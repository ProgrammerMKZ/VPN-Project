import SwiftUI

extension View {
    @ViewBuilder
    func iOSNavigationBarInline() -> some View {
        #if os(iOS)
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func iOSNavigationBarLarge() -> some View {
        #if os(iOS)
        self
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.light, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func iOSInsetGroupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.sidebar)
        #endif
    }

    @ViewBuilder
    func iOSPresentationDetentsLarge() -> some View {
        #if os(iOS)
        self.presentationDetents([.large])
        #else
        self
        #endif
    }
}
