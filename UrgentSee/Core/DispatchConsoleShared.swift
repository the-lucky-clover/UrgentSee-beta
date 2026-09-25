import SwiftUI

// MARK: - Dispatch Console Shared Types
// Types used across every dashboard skin. Each skin keeps its own views and
// its own dispatch-stage model; only the truly shared models live here.

struct MessageTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let text: String

    init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }
}

/// Subtle per-keystroke haptics for message composers. Throttled so fast
/// typing feels like a keyboard, not a jackhammer. Call from
/// `.onChange(of: messageText)`.
enum KeyboardHaptics {
    private static var lastFire = Date.distantPast

    static func keystroke() {
        let now = Date()
        guard now.timeIntervalSince(lastFire) >= 0.06 else { return }
        lastFire = now
        Haptics.tap()
    }
}
