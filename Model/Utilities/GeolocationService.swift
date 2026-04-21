// This file is part of Kiwix for iOS & macOS.
//
// Kiwix is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// any later version.
//
// Kiwix is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Kiwix; If not, see https://www.gnu.org/licenses/.

import CoreLocation
import Foundation

/// Errors matching the HTML5 Geolocation API `PositionError` codes.
enum GeolocationError: Int, Error {
    case permissionDenied = 1
    case positionUnavailable = 2
    case timeout = 3

    var message: String {
        switch self {
        case .permissionDenied: return "User denied geolocation permission."
        case .positionUnavailable: return "Location is unavailable."
        case .timeout: return "Location request timed out."
        }
    }
}

/// Sendable snapshot of a CLLocation, safe to pass across isolation domains.
struct LocationSnapshot: Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let verticalAccuracy: Double?
    let course: Double?
    let speed: Double?
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        if location.verticalAccuracy >= 0 {
            altitude = location.altitude
            verticalAccuracy = location.verticalAccuracy
        } else {
            altitude = nil
            verticalAccuracy = nil
        }
        course = location.course >= 0 ? location.course : nil
        speed = location.speed >= 0 ? location.speed : nil
        timestamp = location.timestamp
    }
}

/// Provides geolocation to the WebKit viewer, bridging HTML5 Geolocation API
/// calls from ZIM content (e.g. map ZIMs) to CoreLocation.
///
/// CoreLocation authorization is requested lazily on the first location request,
/// so users of ZIMs that never touch `navigator.geolocation` are never prompted.
@MainActor
final class GeolocationService: NSObject {

    private let manager: CLLocationManager
    private let delegateShim = GeolocationDelegateShim()

    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationContinuations: [CheckedContinuation<LocationSnapshot, Error>] = []

    override init() {
        manager = CLLocationManager()
        super.init()
        delegateShim.owner = self
        manager.delegate = delegateShim
    }

    /// Returns the current CoreLocation authorization status, prompting the
    /// user if it has not yet been decided.
    func requestAuthorization() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            #if os(macOS)
            manager.requestAlwaysAuthorization()
            #else
            manager.requestWhenInUseAuthorization()
            #endif
        }
    }

    /// Requests a one-shot location reading. Prompts the user for authorization
    /// on first use.
    func requestLocation(highAccuracy: Bool) async throws -> LocationSnapshot {
        let status = await requestAuthorization()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted, .notDetermined:
            throw GeolocationError.permissionDenied
        @unknown default:
            throw GeolocationError.positionUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)
            manager.desiredAccuracy = highAccuracy
                ? kCLLocationAccuracyBest
                : kCLLocationAccuracyHundredMeters
            manager.requestLocation()
        }
    }

    fileprivate func didChangeAuthorization(status: CLAuthorizationStatus) {
        guard status != .notDetermined else { return }
        let waiting = authorizationContinuations
        authorizationContinuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: status)
        }
    }

    fileprivate func didUpdate(snapshot: LocationSnapshot) {
        let waiting = locationContinuations
        locationContinuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: snapshot)
        }
    }

    fileprivate func didFail(code: Int, message: String) {
        let waiting = locationContinuations
        locationContinuations.removeAll()
        let error = NSError(
            domain: "org.kiwix.geolocation",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        for continuation in waiting {
            continuation.resume(throwing: error)
        }
    }
}

/// Nonisolated shim so CLLocationManager can invoke delegate methods from
/// CoreLocation's internal queue while keeping GeolocationService on MainActor.
private final class GeolocationDelegateShim: NSObject, CLLocationManagerDelegate {
    weak var owner: GeolocationService?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak owner] in
            owner?.didChangeAuthorization(status: status)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let snapshot = LocationSnapshot(latest)
        Task { @MainActor [weak owner] in
            owner?.didUpdate(snapshot: snapshot)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        let code = nsError.code
        let message = nsError.localizedDescription
        Task { @MainActor [weak owner] in
            owner?.didFail(code: code, message: message)
        }
    }
}
