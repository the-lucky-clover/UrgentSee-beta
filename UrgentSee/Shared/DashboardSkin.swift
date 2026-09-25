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
    case vapor = "vapor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .og: return "OG"
        case .redux: return "ReDux"
        case .vanilla: return "Vanilla"
        case .redline: return "Redline"
        case .nukeOps: return "Nuke Ops"
        case .vapor: return "Vapor"
        }
    }

    var tagline: String {
        switch self {
        case .og: return "The original console"
        case .redux: return "Neon-glass dispatch deck"
        case .vanilla: return "Apple design language"
        case .redline: return "Disruptive mono/red concept"
        case .nukeOps: return "Tactical nuclear ops"
        case .vapor: return "Vision-quest remix"
        }
    }

    /// A miniature abstract portrait of the skin, shown in Settings.
    @ViewBuilder
    var thumbnail: some View {
        SkinThumbnail(skin: self)
    }
}

// MARK: - Skin thumbnails

/// Tiny abstract portraits — color, shape, and layout hints, not screenshots.
private struct SkinThumbnail: View {
    let skin: DashboardSkin

    var body: some View {
        ZStack {
            thumbBackground
            thumbGlyph
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbBackground: some View {
        switch skin {
        case .og:
            Color(red: 0.06, green: 0.07, blue: 0.12)
        case .redux:
            Color.black
        case .vanilla:
            Color(.systemBackground)
        case .redline:
            Color.white
        case .nukeOps:
            Color(red: 0.03, green: 0.05, blue: 0.045)
        case .vapor:
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.05, blue: 0.20), Color(red: 0.03, green: 0.08, blue: 0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var thumbGlyph: some View {
        switch skin {
        case .og:
            // Three glow dots + message bar: the original's neon pills.
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 8, height: 8).shadow(color: .red, radius: 4)
                    Circle().fill(Color.blue).frame(width: 8, height: 8).shadow(color: .blue, radius: 4)
                    Circle().fill(Color.orange).frame(width: 8, height: 8).shadow(color: .orange, radius: 4)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 30, height: 7)
            }
        case .redux:
            // 2x2 neon-bento tiles.
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.red, lineWidth: 1.5).frame(width: 13, height: 13)
                    RoundedRectangle(cornerRadius: 2).stroke(Color.blue, lineWidth: 1.5).frame(width: 13, height: 13)
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.orange, lineWidth: 1.5).frame(width: 13, height: 13)
                    RoundedRectangle(cornerRadius: 2).stroke(Color.purple, lineWidth: 1.5).frame(width: 13, height: 13)
                }
            }
        case .vanilla:
            // Grouped list rows + blue send bar.
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.25)).frame(width: 34, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.25)).frame(width: 34, height: 6)
                RoundedRectangle(cornerRadius: 5).fill(Color.blue).frame(width: 34, height: 10)
            }
        case .redline:
            // Heavy black lines + the sacred red block.
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: 30, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.55)).frame(width: 22, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 1.0, green: 0.18, blue: 0.13)).frame(width: 34, height: 12)
            }
            .padding(.horizontal, 8)
        case .nukeOps:
            // Phosphor lines + amber hazard stripe.
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.30, green: 1.0, blue: 0.55)).frame(width: 30, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.30, green: 1.0, blue: 0.55).opacity(0.5)).frame(width: 22, height: 4)
                HStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        Rectangle()
                            .fill(i.isMultiple(of: 2) ? Color(red: 1.0, green: 0.70, blue: 0.20) : Color.black)
                            .frame(width: 6, height: 7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        case .vapor:
            // The charged orb.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .purple, .pink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .blur(radius: 1)
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
            }
        }
    }
}
