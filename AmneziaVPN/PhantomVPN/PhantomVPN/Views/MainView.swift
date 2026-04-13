import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: VPNViewModel
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home = "STATUS"
        case servers = "NODES"
        case settings = "CONFIG"
    }

    var body: some View {
        VStack(spacing: 0) {
            selectedView

            Divider()
                .frame(height: 1)
                .overlay(Color.black)

            tabBar
        }
        .background(Color.white)
        .alert("ERROR", isPresented: $viewModel.showError) {
            Button("DISMISS") {}
        } message: {
            Text(viewModel.errorMessage.uppercased())
                .font(MaurtenFont.mono)
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .servers:
            ServerListView()
        case .settings:
            SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(MaurtenFont.monoSmall)
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(selectedTab == tab ? Color.black : Color.white)
                }
                .buttonStyle(.plain)

                if tab != Tab.allCases.last {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 1)
                        .frame(height: 48)
                }
            }
        }
        .frame(height: 48)
    }
}

extension Color {
    static let accentGreen = Color.black
    static let darkBackground = Color.white
    static let cardBackground = Color.white
    static let subtleGray = Color.black.opacity(0.4)
}
