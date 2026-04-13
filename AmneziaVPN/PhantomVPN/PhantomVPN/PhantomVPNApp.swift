import SwiftUI

@main
struct PhantomVPNApp: App {
    @StateObject private var viewModel = VPNViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .preferredColorScheme(.light)
        }
    }
}
