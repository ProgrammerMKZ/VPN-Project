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
                    Label("Connect", systemImage: "shield.checkered")
                }
                .tag(Tab.home)

            ServerListView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                .tag(Tab.servers)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(.accentGreen)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

extension Color {
    static let accentGreen = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let darkBackground = Color(red: 0.06, green: 0.07, blue: 0.11)
    static let cardBackground = Color(red: 0.10, green: 0.11, blue: 0.16)
    static let subtleGray = Color(red: 0.40, green: 0.42, blue: 0.48)
}
