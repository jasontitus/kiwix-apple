// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CryptoKit

actor StreetZimAssembler {
    typealias RangeReader = @Sendable (URL, Int64, Int64, Int64) async throws -> Data
    typealias Progress = @Sendable (Int64, Int64) async -> Void
    typealias CapacityReader = @Sendable (URL) throws -> VolumeCapacity
    typealias RetrySleep = @Sendable (Duration) async throws -> Void

    struct VolumeCapacity: Sendable {
        let available: Int64?
        let volume: URL?
    }

    private static let capacityKeys: Set<URLResourceKey> = [
        .volumeAvailableCapacityForImportantUsageKey, .volumeURLKey
    ]
    private let endpoint: StreetZimEndpoint
    private let cache: URL
    private let readRange: RangeReader
    private let capacity: CapacityReader
    private let retrySleep: RetrySleep

    init(
        endpoint: StreetZimEndpoint,
        cache: URL,
        capacity: @escaping CapacityReader = StreetZimAssembler.volumeCapacity,
        retrySleep: @escaping RetrySleep = { try await Task.sleep(for: $0) },
        readRange: @escaping RangeReader = StreetZimHTTP.range
    ) {
        self.endpoint = endpoint
        self.cache = cache
        self.capacity = capacity
        self.retrySleep = retrySleep
        self.readRange = readRange
    }

    /// The cache is content-addressed by the hash of a verified (masked) chunk.
    /// A retry rewrites the output but reuses these chunks; a second language
    /// uses the same base and Wikipedia chunks. Memory stays bounded to a chunk.
    func assemble(
        recipe: StreetZimRecipe,
        baseURL: URL,
        localBase: URL? = nil,
        destination: URL,
        progress: Progress = { _, _ in }
    ) async throws -> URL {
        let masks = try recipe.validate()
        try Task.checkCancellation()
        let manager = FileManager.default
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let access = localBase?.startAccessingSecurityScopedResource() ?? false
        defer { if access { localBase?.stopAccessingSecurityScopedResource() } }
        let localFile = localBase.flatMap { try? FileHandle(forReadingFrom: $0) }
        defer { try? localFile?.close() }
        let localSize = try? localFile?.seekToEnd()
        let useLocal = localSize.map { $0 >= UInt64(recipe.base.size) } ?? false

        var urls = ["base": baseURL]
        var sources = ["base": recipe.base]
        for (key, source) in recipe.packs {
            try Task.checkCancellation()
            guard let address = source.url else { throw StreetZimError.invalidRecipe }
            urls["pack:" + key] = try endpoint.sourceURL(address)
            sources["pack:" + key] = source
        }
        try checkSpace(recipe: recipe, sources: sources, localBase: useLocal, destination: destination)

        // A unique temporary file and a non-overwriting move protect existing maps.
        let partial = destination.appendingPathComponent(".streetzim-\(UUID().uuidString).part")
        guard manager.createFile(atPath: partial.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? manager.removeItem(at: partial) }
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }
        var lastKey: String?
        var lastData = Data()
        var written: Int64 = 0

        func chunk(_ key: String, _ index: Int64, isolation: isolated StreetZimAssembler) async throws -> Data {
            try Task.checkCancellation()
            guard let source = sources[key], let url = urls[key], let mask = masks[key] else {
                throw StreetZimError.invalidRecipe
            }
            let expected = source.sha256[Int(index)]
            let start = index * source.chunk
            let length = min(source.chunk, source.size - start)
            let cacheKey = "\(expected)-\(length)"
            if lastKey == cacheKey { return lastData }
            let cached = cache.appendingPathComponent(cacheKey)
            let bytes: Data
            if (try? cached.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(length),
               let data = try? Data(contentsOf: cached), Int64(data.count) == length,
               StreetZimRecipe.sha256(data) == expected {
                bytes = data
            } else {
                try? manager.removeItem(at: cached)
                var verified: Data?
                if key == "base", useLocal, let localFile {
                    do {
                        try localFile.seek(toOffset: UInt64(start))
                        if let raw = try localFile.read(upToCount: Int(length)), Int64(raw.count) == length {
                            let data = try mask.masked(raw, at: start)
                            if StreetZimRecipe.sha256(data) == expected { verified = data }
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch { /* A missing/unreadable candidate falls back to the network. */ }

                }
                if verified == nil {
                    // A previous language/build may not match this chunk. Recheck
                    // before each fallback so a candidate never causes us to
                    // consume space reserved for the still-unwritten output.
                    try checkCapacity(outputBytes: recipe.size - written, cacheBytes: length, destination: destination)
                    for attempt in 0..<3 {
                        do {
                            try Task.checkCancellation()
                            let raw = try await readRange(url, start, length, source.size)
                            guard Int64(raw.count) == length else { throw StreetZimError.invalidResponse }
                            let data = try mask.masked(raw, at: start)
                            guard StreetZimRecipe.sha256(data) == expected else { throw StreetZimError.integrity }
                            try data.write(to: cached, options: .atomic)
                            verified = data
                            break
                        } catch {
                            try Task.checkCancellation()
                            if error is CancellationError || attempt == 2 { throw error }
                            try await retrySleep(.seconds(attempt + 1))
                        }
                    }
                }
                guard let verified else { throw StreetZimError.integrity }
                bytes = verified
            }
            lastKey = cacheKey
            lastData = bytes
            return bytes
        }

        let head = try await chunk("base", 0, isolation: self)
        guard head.count >= 24,
              StreetZimRecipe.hex(head[8..<24]) == recipe.base.uuid.replacingOccurrences(of: "-", with: "").lowercased()
        else { throw StreetZimError.integrity }
        var md5 = Insecure.MD5()
        await progress(written, recipe.size)
        for segment in recipe.segments {
            try Task.checkCancellation()
            switch segment.src {
            case "inline":
                // Validated before any input is downloaded or output created.
                guard let encoded = segment.data, let data = Data(base64Encoded: encoded) else {
                    throw StreetZimError.invalidRecipe
                }
                md5.update(data: data)
                try output.write(contentsOf: data)
                written += Int64(data.count)
            case "md5":
                let checksum = Data(md5.finalize())
                guard StreetZimRecipe.hex(checksum) == recipe.md5 else { throw StreetZimError.integrity }
                md5.update(data: checksum)
                if let expected = recipe.fileMD5, StreetZimRecipe.hex(md5.finalize()) != expected {
                    throw StreetZimError.integrity
                }
                try output.write(contentsOf: checksum)
                written += 16
            default:
                let key = segment.src == "base" ? "base" : "pack:" + (segment.pack ?? "")
                guard let source = sources[key], var offset = segment.off, let length = segment.len else {
                    throw StreetZimError.invalidRecipe
                }
                let end = offset + length
                while offset < end {
                    try Task.checkCancellation()
                    let index = offset / source.chunk
                    let data = try await chunk(key, index, isolation: self)
                    let from = Int(offset % source.chunk)
                    let count = min(data.count - from, Int(end - offset))
                    let slice = data.subdata(in: from..<from + count)
                    md5.update(data: slice)
                    try output.write(contentsOf: slice)
                    written += Int64(count)
                    offset += Int64(count)
                    await progress(written, recipe.size)
                }
            }
        }
        guard written == recipe.size else { throw StreetZimError.integrity }
        try output.synchronize()
        try output.close()
        try Task.checkCancellation()
        var final = destination.appendingPathComponent(recipe.outputName)
        var suffix = 1
        while manager.fileExists(atPath: final.path) {
            final = destination.appendingPathComponent(recipe.outputName)
                .deletingPathExtension().appendingPathExtension("\(suffix).zim")
            suffix += 1
        }
        try manager.moveItem(at: partial, to: final)
        await progress(written, recipe.size)
        return final
    }

    private func checkSpace(
        recipe: StreetZimRecipe, sources: [String: StreetZimRecipe.Source], localBase: Bool, destination: URL
    ) throws {
        try checkCapacity(outputBytes: recipe.size, cacheBytes: 0, destination: destination)
        let referenced = try Self.referencedChunks(recipe: recipe, sources: sources, localBase: localBase)
        var missing: Int64 = 0
        var touched = Set<String>()
        for (key, intervals) in referenced {
            guard let source = sources[key] else { throw StreetZimError.invalidRecipe }
            for range in intervals.ranges {
                for index in range {
                    try Task.checkCancellation()
                    let length = min(source.chunk, source.size - index * source.chunk)
                    let cacheKey = "\(source.sha256[Int(index)])-\(length)"
                    if touched.insert(cacheKey).inserted,
                       !FileManager.default.fileExists(atPath: cache.appendingPathComponent(cacheKey).path) {
                        let (sum, overflow) = missing.addingReportingOverflow(length)
                        guard !overflow else { throw StreetZimError.invalidRecipe }
                        missing = sum
                    }
                }
            }
        }
        try checkCapacity(outputBytes: recipe.size, cacheBytes: missing, destination: destination)
    }

    /// Merge references before visiting chunks: repeated segments must not
    /// multiply preflight work. The recipe has already passed bounds validation.
    nonisolated static func referencedChunks(
        recipe: StreetZimRecipe, sources: [String: StreetZimRecipe.Source], localBase: Bool
    ) throws -> [String: StreetZimRecipe.MaskIndex] {
        var intervals: [String: [[Int64]]] = [:]
        for segment in recipe.segments where segment.src == "base" || segment.src == "pack" {
            try Task.checkCancellation()
            if segment.src == "base" && localBase { continue }
            let key = segment.src == "base" ? "base" : "pack:" + (segment.pack ?? "")
            guard let source = sources[key], let off = segment.off, let len = segment.len, len > 0 else { continue }
            let first = off / source.chunk
            let last = (off + len - 1) / source.chunk
            intervals[key, default: []].append([first, last - first + 1])
        }
        var result: [String: StreetZimRecipe.MaskIndex] = [:]
        for (key, ranges) in intervals {
            guard let source = sources[key] else { throw StreetZimError.invalidRecipe }
            result[key] = try StreetZimRecipe.MaskIndex(ranges, size: Int64(source.sha256.count))
        }
        return result
    }

    private func checkCapacity(outputBytes: Int64, cacheBytes: Int64, destination: URL) throws {
        let outputVolume = try capacity(destination)
        let cacheVolume = try capacity(cache)
        let sharedVolume = outputVolume.volume == cacheVolume.volume
        let (required, overflow) = outputBytes.addingReportingOverflow(sharedVolume ? cacheBytes : 0)
        guard !overflow else { throw StreetZimError.insufficientSpace }
        if let free = outputVolume.available, free < required { throw StreetZimError.insufficientSpace }
        if let free = cacheVolume.available, free < cacheBytes { throw StreetZimError.insufficientSpace }
    }

    nonisolated static func volumeCapacity(at url: URL) throws -> VolumeCapacity {
        let values = try url.resourceValues(forKeys: capacityKeys)
        return VolumeCapacity(available: values.volumeAvailableCapacityForImportantUsage, volume: values.volume)
    }
}

/// A bounded data delegate keeps a server ignoring Range, a compressed JSON
/// response, or an unknown-length body from growing memory/disk without limit.
/// Only cancellation crosses the serial URLSession delegate queue; the lock
/// also covers cancellation arriving before the task has been installed.
private final class StreetZimRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximum: Int
    private let contentRange: String?
    private let progress: (@Sendable (Int64, Int64) -> Void)?
    private var lastReportedBytes = 0
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var transferSession: URLSession?
    private var continuation: CheckedContinuation<Data, Error>?
    private var bytes = Data()
    private var failure: Error?
    private var cancelled = false

    init(maximum: Int, contentRange: String? = nil, progress: (@Sendable (Int64, Int64) -> Void)? = nil) {
        self.maximum = maximum
        self.contentRange = contentRange
        self.progress = progress
    }

    func run(_ request: URLRequest, session: URLSession) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let transferSession = URLSession(
                    configuration: session.configuration, delegate: self, delegateQueue: nil
                )
                let task = transferSession.dataTask(with: request)
                self.transferSession = transferSession
                self.task = task
                lock.unlock()
                progress?(0, Int64(maximum))
                task.resume()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let task = self.task
            self.lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let error: StreetZimError?
        if let contentRange {
            if let http = response as? HTTPURLResponse, http.statusCode == 206,
               http.value(forHTTPHeaderField: "Content-Range") == contentRange,
               response.expectedContentLength <= maximum {
                error = nil
            } else { error = .invalidResponse }
        } else if (response as? HTTPURLResponse)?.statusCode != 200 {
            error = .catalogUnavailable
        } else if response.expectedContentLength > maximum {
            error = .invalidRecipe
        } else { error = nil }
        lock.lock()
        failure = error
        lock.unlock()
        completionHandler(error == nil ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let tooLarge = data.count > maximum - bytes.count
        if tooLarge { failure = contentRange == nil ? StreetZimError.invalidRecipe : StreetZimError.invalidResponse }
        else if failure == nil { bytes.append(data) }
        let received = bytes.count
        let report = progress != nil && failure == nil &&
            (received - lastReportedBytes >= 256 * 1024 || received == maximum)
        if report { lastReportedBytes = received }
        lock.unlock()
        if report { progress?(Int64(received), Int64(maximum)) }
        if tooLarge { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock()
        transferSession = nil
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.task = nil
        let transferSession = self.transferSession
        let failure = cancelled ? CancellationError() : (self.failure ?? error)
        let bytes = self.bytes
        lock.unlock()
        transferSession?.finishTasksAndInvalidate()
        if let failure { continuation?.resume(throwing: failure) }
        else { continuation?.resume(returning: bytes) }
    }
}

enum StreetZimHTTP {
    static func json<T: Decodable & Sendable>(
        _ url: URL, as type: T.Type, cellular: Bool = true, session: URLSession = .shared
    ) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.allowsCellularAccess = cellular
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await StreetZimRequest(maximum: 32 * 1024 * 1024).run(request, session: session)
        return try JSONDecoder().decode(type, from: data)
    }

    static func range(_ url: URL, offset: Int64, length: Int64, size: Int64) async throws -> Data {
        try await range(url, offset: offset, length: length, size: size, cellular: true)
    }

    static func range(_ url: URL, offset: Int64, length: Int64, size: Int64, cellular: Bool,
                      session: URLSession = .shared,
                      progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> Data {
        guard offset >= 0, length > 0, length <= 16 * 1024 * 1024,
              offset <= size, length <= size - offset else { throw StreetZimError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.allowsCellularAccess = cellular
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let contentRange = "bytes \(offset)-\(offset + length - 1)/\(size)"
        let data = try await StreetZimRequest(maximum: Int(length), contentRange: contentRange, progress: progress)
            .run(request, session: session)
        guard Int64(data.count) == length else { throw StreetZimError.invalidResponse }
        return data
    }
}
