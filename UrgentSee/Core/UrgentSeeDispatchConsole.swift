import SwiftUI

// MARK: - Dispatch Console Router
// Thin router: renders whichever dashboard skin is selected globally in
// Settings → Appearance → Dashboard Skin (@AppStorage("dashboardSkin")).
// Every skin drives the same real dispatch pipeline.

struct UrgentSeeDispatchConsole: View {
    @AppStorage("dashboardSkin") private var skinId: String = DashboardSkin.redux.rawValue

    var body: some View {
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
        }
    }
}
