import SwiftUI

// MARK: - Dispatch Console Router
// Thin router: renders whichever dashboard skin is selected globally in
// Settings → Appearance → Dashboard Skin (@AppStorage("dashboardSkin")).
// Every skin drives the same real dispatch pipeline.

struct UrgentSeeDispatchConsole: View {
    @AppStorage("dashboardSkin") private var skinId: String = DashboardSkin.redux.rawValue

    var body: some View {
        Group {
            switch DashboardSkin(rawValue: skinId) ?? .redux {
            case .og:
                DispatchConsoleOG()
            case .redux:
                DispatchConsoleReDux()
            case .vanilla:
                DispatchConsoleVanilla()
            case .redline:
                DispatchConsoleRedline()
            case .nukeOps:
                DispatchConsoleNukeOps()
            case .vapor:
                DispatchConsoleVapor()
            }
        }
        .id(skinId)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.easeInOut(duration: 0.35), value: skinId)
    }
}
