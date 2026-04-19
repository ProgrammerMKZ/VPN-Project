import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home, servers, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("CONNECT", systemImage: "shield.checkered")
                }
                .tag(Tab.home)

            ServerListView()
                .tabItem {
                    Label("SERVERS", systemImage: "server.rack")
                }
                .tag(Tab.servers)

            SettingsView()
                .tabItem {
                    Label("SETTINGS", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(.black)
        .alert("ERROR", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

extension Color {
    static let accentGreen = Color.black
    static let darkBackground = Color.white
    static let cardBackground = Color(white: 0.95)
    static let subtleGray = Color(white: 0.55)
}
