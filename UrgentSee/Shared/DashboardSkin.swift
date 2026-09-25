import SwiftUI

// MARK: - Dashboard Skin
// The dispatch console ships as interchangeable skins, selectable globally
// in the in-app Settings tab ("Appearance"). The router
// (UrgentSeeDispatchConsole) renders whichever skin is stored in
// @AppStorage("dashboardSkin"). Every skin drives the same real dispatch
// pipeline — only the presentation changes.

enum DashboardSkin: String, CaseIterable, Identifiable {
    case og = "og"
    case redux = "redux"
    case vanilla = "vanilla"
    case redline = "redline"
    case nukeOps = "nukeops"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .og: return "OG"
        case .redux: return "ReDux"
        case .vanilla: return "Vanilla"
        case .redline: return "Redline"
        case .nukeOps: return "Nuke Ops"
        }
    }

    var tagline: String {
        switch self {
        case .og: return "The original console"
        case .redux: return "Neon-glass dispatch deck"
        case .vanilla: return "Apple design language"
        case .redline: return "Disruptive mono/red concept"
        case .nukeOps: return "Tactical nuclear ops"
        }
    }
}
