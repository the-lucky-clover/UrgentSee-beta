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
