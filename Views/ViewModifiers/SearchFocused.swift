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

import SwiftUI

#if os(macOS)

struct SearchFocused: ViewModifier {
    
    var isSearchFocused: FocusState<Bool>.Binding
    
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused(isSearchFocused)
        } else {
            content
        }
    }
}

#endif

private struct ReaderSearchPresentedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReaderSearchDismissKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var isReaderSearchPresented: Bool {
        get { self[ReaderSearchPresentedKey.self] }
        set { self[ReaderSearchPresentedKey.self] = newValue }
    }

    var dismissReaderSearch: (@MainActor () -> Void)? {
        get { self[ReaderSearchDismissKey.self] }
        set { self[ReaderSearchDismissKey.self] = newValue }
    }
}

struct ReaderSearchModifier: ViewModifier {
    @Binding var text: String
    let placement: SearchFieldPlacement

    func body(content: Content) -> some View {
        #if os(iOS)
        if usesSceneLocalSearch {
            content.modifier(IOSAppOnMacReaderSearch(text: $text))
        } else {
            content.searchable(text: $text, placement: placement, prompt: LocalString.common_search)
        }
        #else
        content.searchable(text: $text, placement: placement, prompt: LocalString.common_search)
        #endif
    }

    #if os(iOS)
    private var usesSceneLocalSearch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reader-search-text-field-ui-test") {
            return true
        }
        #endif
        return ProcessInfo.processInfo.isiOSAppOnMac
    }
    #endif
}

#if os(iOS)
/// SDK 27's UISearchController uses unsupported screen-based focus on older macOS.
/// Keep search scene-local without changing the app's single-scene configuration.
/// See https://developer.apple.com/forums/thread/841090.
private struct IOSAppOnMacReaderSearch: ViewModifier {
    @Binding var text: String
    @State private var isPresented = false
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.isReaderSearchPresented, isPresented)
            .environment(\.dismissReaderSearch, dismiss)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Button {
                            isPresented = true
                            isFocused = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(LocalString.common_search)
                        .keyboardShortcut("f", modifiers: .command)

                        TextField(LocalString.common_search, text: $text)
                            .textFieldStyle(.roundedBorder)
                            .focused($isFocused)
                            .accessibilityIdentifier("reader_search_field")
                            .onKeyPress(.escape) {
                                dismiss()
                                return .handled
                            }
                        if !text.isEmpty {
                            Button {
                                text = ""
                                isFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel(LocalString.search_result_button_clear)
                            .accessibilityIdentifier("reader_search_clear")
                        }
                        if isPresented {
                            Button(LocalString.common_button_cancel, action: dismiss)
                        }
                    }
                    .frame(minWidth: 160, idealWidth: 320, maxWidth: 480)
                }
            }
            .onChange(of: isFocused) { _, focused in
                if focused { isPresented = true }
            }
            .onChange(of: text) { _, value in
                if !value.isEmpty { isPresented = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openURL)) { _ in
                dismiss()
            }
            .onDisappear(perform: dismiss)
    }

    private func dismiss() {
        isFocused = false
        isPresented = false
        text = ""
    }
}
#endif
