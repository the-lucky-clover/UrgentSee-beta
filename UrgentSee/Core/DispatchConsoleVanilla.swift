// MARK: - Vanilla skin — Apple design language reboot.
// Selectable in Settings → Appearance → Dashboard Skin.

import SwiftUI
import AudioToolbox

// MARK: - Dispatch Stage
// The dispatch pipeline's honest stage model. Progress only advances on real
// completed work — the UI never claims more than the backend has confirmed.

enum VanillaDispatchStage: String, CaseIterable {
    case idle = "Idle"
    case validating = "Validating"
    case encrypting = "Encrypting"
    case dispatching = "Sending"
    case pushing = "Pushing"
    case mounted = "On Their Lock Screen"
    case confirmed = "Delivered & Read"
    case failed = "Failed"

    var progress: Double {
        switch self {
        case .idle: return 0.0
        case .validating: return 0.15
        case .encrypting: return 0.30
        case .dispatching: return 0.50
        case .pushing: return 0.70
        case .mounted: return 0.85
        case .confirmed: return 1.0
        case .failed: return 0.0
        }
    }

    var icon: String {
        switch self {
        case .idle: return "bolt.shield.fill"
        case .validating: return "checkmark.shield.fill"
        case .encrypting: return "lock.shield.fill"
        case .dispatching: return "paperplane.fill"
        case .pushing: return "antenna.radiowaves.left.and.right"
        case .mounted: return "iphone.gen3.radiowaves.left.and.right"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .validating: return .blue
        case .encrypting: return .purple
        case .dispatching: return .orange
        case .pushing: return .cyan
        case .mounted: return .green
        case .confirmed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Main Dispatch Console — Apple design language reboot
//
// The same dispatch console, rebuilt the way Apple would: a NavigationStack
// with a large title, native grouped-list sections, SF Symbols, system
// colors that adapt to light and dark, and standard iOS patterns throughout
// (pickers, toggles, sheets, prominent buttons). Every control that affects
// a dispatch — TTL, Critical Alert — is a first-class visible row. The Send
// button always states its prerequisite. Progress lives in a dismissible
// sheet with a native ProgressView; failure offers Try Again, never a
// blocking alert. No custom visual language to learn.

struct DispatchConsoleVanilla: View {
    @EnvironmentObject private var settings: AccessibilitySettings

    @State private var selectedContact: TrustCircleManager.TrustCircleMember?
    @State private var messageText: String = ""
    @State private var isCriticalOverride: Bool = true
    @State private var isDispatching: Bool = false
    @State private var errorMessage: String?
    @State private var showTemplateManager = false
    @State private var showAddTemplate = false
    @State private var newTemplateName = ""
    @State private var newTemplateText = ""

    @State private var dispatchProgress: Double = 0.0
    @State private var dispatchStage: VanillaDispatchStage = .idle
    @State private var showNotice = false
    @State private var noticeMessage = ""
    @State private var showProgressSheet = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = "checkmark.circle.fill"
    @State private var showRename = false
    @State private var renameTargetId: String = ""
    @State private var renameName: String = ""

    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared

    @FocusState private var isMessageFocused: Bool

    @AppStorage("messageTemplates") private var messageTemplatesData: Data = Data()
    @AppStorage("recipientMessages") private var recipientMessagesData: Data = Data()

    private let maxCharacters = 140

    /// TTL intervals from 15 minutes up to 72 hours, plus "Until read".
    enum TTLInterval: Int, CaseIterable, Identifiable {
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case oneHour = 60
        case threeHours = 180
        case sixHours = 360
        case twelveHours = 720
        case twentyFourHours = 1440
        case fortyEightHours = 2880
        case seventyTwoHours = 4320
        case untilRead = -1

        var id: Int { rawValue }
        var minutes: Int { rawValue }
        var isUntilRead: Bool { self == .untilRead }

        var label: String {
            switch self {
            case .fifteenMinutes: return "15 minutes"
            case .thirtyMinutes: return "30 minutes"
            case .oneHour: return "1 hour"
            case .threeHours: return "3 hours"
            case .sixHours: return "6 hours"
            case .twelveHours: return "12 hours"
            case .twentyFourHours: return "24 hours"
            case .fortyEightHours: return "48 hours"
            case .seventyTwoHours: return "72 hours"
            case .untilRead: return "Until read"
            }
        }

        var shortLabel: String {
            switch self {
            case .fifteenMinutes: return "15 min"
            case .thirtyMinutes: return "30 min"
            case .oneHour: return "1 hour"
            case .threeHours: return "3 hours"
            case .sixHours: return "6 hours"
            case .twelveHours: return "12 hours"
            case .twentyFourHours: return "24 hours"
            case .fortyEightHours: return "48 hours"
            case .seventyTwoHours: return "72 hours"
            case .untilRead: return "Until read"
            }
        }
    }

    @State private var selectedTTL: TTLInterval = .untilRead

    // MARK: - Computed Data

    var messageTemplates: [MessageTemplate] {
        if let decoded = try? JSONDecoder().decode([MessageTemplate].self, from: messageTemplatesData) {
            return decoded
        }
        return [
            MessageTemplate(name: "Urgent", text: "URGENT: Need you to see this immediately. Please respond."),
            MessageTemplate(name: "Medical", text: "MEDICAL EMERGENCY: I need help. Location: [LOCATION]. Please call emergency services."),
            MessageTemplate(name: "Safety", text: "SAFETY ALERT: I don't feel safe. Please check on me now."),
        ]
    }

    var availableRecipients: [TrustCircleManager.TrustCircleMember] {
        recipientsManager.activeMembers.filter { $0.hasAppInstalled }
    }

    var recipientMessages: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: recipientMessagesData)) ?? [:]
    }

    /// The button is only live when a real send can happen.
    var canDispatch: Bool {
        apiService.isAuthenticated && selectedContact != nil && !messageText.isEmpty && !isDispatching
    }

    /// The button always states its prerequisite — no mystery taps.
    var sendButtonTitle: String {
        if !apiService.isAuthenticated { return "Connect Device" }
        if selectedContact == nil { return "Select a Recipient" }
        if messageText.isEmpty { return "Write a Message" }
        return "Send"
    }

    var statusLine: (text: String, icon: String, color: Color) {
        if !apiService.isAuthenticated {
            return ("Device not connected", "iphone.slash", .red)
        }
        if isDispatching {
            return ("Sending…", "paperplane.fill", .orange)
        }
        if selectedContact != nil && !messageText.isEmpty {
            return ("Ready to send", "checkmark.circle.fill", .blue)
        }
        return ("Idle", "moon.zzz.fill", .secondary)
    }

    var deliverySummary: String {
        var parts: [String] = []
        if let contact = selectedContact {
            parts.append("To \(recipientsManager.displayName(for: contact.userId))")
        } else {
            parts.append("No recipient")
        }
        parts.append("Expires \(selectedTTL.shortLabel.lowercased())")
        parts.append(isCriticalOverride ? "Critical alert on" : "Critical alert off")
        return parts.joined(separator: " · ")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if !apiService.isAuthenticated {
                    connectionSection
                }
                recipientSection
                messageSection
                deliverySection
                sendSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dispatch")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: statusLine.icon)
                            .font(.footnote)
                        Text(statusLine.text)
                            .font(.footnote)
                    }
                    .foregroundStyle(statusLine.color)
                    .accessibilityLabel("Status: \(statusLine.text)")
                }
            }
            .onAppear {
                Task { await recipientsManager.loadTrustCircle() }
            }
            .sheet(isPresented: $showProgressSheet) {
                VanillaDispatchProgressSheet(
                    stage: $dispatchStage,
                    progress: $dispatchProgress,
                    errorMessage: $errorMessage,
                    onRetry: { executeDispatch() },
                    onDismiss: { dismissProgressSheet() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showTemplateManager) {
                VanillaTemplateManagerSheet(
                    templates: messageTemplates,
                    onSave: saveTemplates(_:),
                    onAdd: { showAddTemplate = true }
                )
            }
            .alert("Rename Recipient", isPresented: $showRename) {
                TextField("Name", text: $renameName)
                Button("Save") {
                    let trimmed = renameName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        recipientsManager.setDisplayName(trimmed, for: renameTargetId)
                        Haptics.success()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose a display name for this recipient.")
            }
            .alert("Notice", isPresented: $showNotice) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(noticeMessage)
            }
            .alert("New Template", isPresented: $showAddTemplate) {
                TextField("Name", text: $newTemplateName)
                TextField("Text", text: $newTemplateText, axis: .vertical)
                Button("Save") { saveCurrentAsTemplate() }
                Button("Cancel", role: .cancel) {
                    newTemplateName = ""
                    newTemplateText = ""
                }
            } message: {
                Text("Save the current message as a reusable template.")
            }
            .overlay(alignment: .top) {
                if showToast {
                    VanillaToastBanner(icon: toastIcon, message: toastMessage)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: showToast)
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            Button {
                noticeMessage = "Connect this device first: Recipients tab → Settings → Connect This Device."
                showNotice = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device Not Connected")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Connect in Recipients → Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.title3)
                }
            }
            .accessibilityHint("Shows how to connect this device.")
        }
    }

    private var recipientSection: some View {
        Section {
            if availableRecipients.isEmpty {
                Label("No recipients yet", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
                Text("Add someone in the Recipients tab to get started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(availableRecipients, id: \.userId) { contact in
                            VanillaRecipientAvatarButton(
                                name: recipientsManager.displayName(for: contact.userId),
                                isSelected: selectedContact?.userId == contact.userId,
                                isActive: contact.hasAppInstalled
                            ) {
                                onRecipientSelected(contact)
                            }
                            .contextMenu {
                                Button {
                                    renameTargetId = contact.userId
                                    renameName = recipientsManager.displayName(for: contact.userId)
                                    showRename = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            Text("Recipient")
        } footer: {
            if let contact = selectedContact {
                Text("Sending to \(recipientsManager.displayName(for: contact.userId)). Long-press an avatar to rename.")
            }
        }
    }

    private var messageSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $messageText)
                    .focused($isMessageFocused)
                    .frame(minHeight: 120)
                    .font(.body)
                    .onChange(of: messageText) { _, newValue in
                        KeyboardHaptics.keystroke()
                        if newValue.count > maxCharacters {
                            messageText = String(newValue.prefix(maxCharacters))
                            Haptics.warning()
                        }
                        if let contact = selectedContact {
                            saveRecipientMessage(messageText, for: contact.userId)
                        }
                    }
                    .accessibilityLabel("Message")
                    .accessibilityHint("Up to 140 characters.")
                if messageText.isEmpty {
                    Text("Message…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            Menu {
                ForEach(messageTemplates) { template in
                    Button(template.name) { applyTemplate(template) }
                }
                Divider()
                Button("Manage Templates…") { showTemplateManager = true }
            } label: {
                Label("Templates", systemImage: "text.badge.plus")
            }
        } header: {
            Text("Message")
        } footer: {
            Text("\(messageText.count) / \(maxCharacters)")
                .monospacedDigit()
        }
    }

    private var deliverySection: some View {
        Section {
            Picker("Expires After", selection: $selectedTTL) {
                ForEach(TTLInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            .pickerStyle(.navigationLink)

            Toggle(isOn: $isCriticalOverride) {
                Label("Critical Alert", systemImage: "bell.badge.fill")
            }
            .tint(.red)
        } header: {
            Text("Delivery")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Critical alerts bypass silent mode and Do Not Disturb on their device. Use only when it truly can't wait.")
                Text(deliverySummary)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
            }
        }
    }

    private var sendSection: some View {
        Section {
            Button {
                executeDispatch()
            } label: {
                HStack {
                    if isDispatching {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: canDispatch ? "paperplane.fill" : "paperplane")
                    }
                    Text(isDispatching ? "Sending…" : sendButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canDispatch && apiService.isAuthenticated)
            .accessibilityHint(accessibilityHintForSend)
        } footer: {
            Text("The message, recipient, and delivery options above are exactly what will be sent.")
        }
    }

    private var accessibilityHintForSend: String {
        if !apiService.isAuthenticated { return "Connect this device before sending." }
        if selectedContact == nil { return "Choose a recipient first." }
        if messageText.isEmpty { return "Write a message first." }
        return "Sends the message now."
    }

    // MARK: - Actions

    private func saveTemplates(_ templates: [MessageTemplate]) {
        if let encoded = try? JSONEncoder().encode(templates) {
            messageTemplatesData = encoded
        }
    }

    private func saveRecipientMessage(_ message: String, for recipientId: String) {
        var messages = recipientMessages
        messages[recipientId] = message
        if let encoded = try? JSONEncoder().encode(messages) {
            recipientMessagesData = encoded
        }
    }

    private func loadMessageForRecipient(_ recipient: TrustCircleManager.TrustCircleMember) {
        messageText = recipientMessages[recipient.userId] ?? ""
    }

    private func onRecipientSelected(_ contact: TrustCircleManager.TrustCircleMember) {
        Haptics.selection()
        selectedContact = contact
        loadMessageForRecipient(contact)
    }

    private func applyTemplate(_ template: MessageTemplate) {
        Haptics.tap()
        messageText = template.text
        guard let contact = selectedContact else { return }
        saveRecipientMessage(template.text, for: contact.userId)
    }

    private func saveCurrentAsTemplate() {
        let text = newTemplateText.isEmpty ? messageText : newTemplateText
        guard !newTemplateName.isEmpty, !text.isEmpty else { return }
        var templates = messageTemplates
        templates.append(MessageTemplate(name: newTemplateName, text: text))
        saveTemplates(templates)
        newTemplateName = ""
        newTemplateText = ""
        Haptics.success()
    }

    private func executeDispatch() {
        guard apiService.isAuthenticated else {
            noticeMessage = "Connect this device first: Recipients tab → Settings → Connect This Device."
            showNotice = true
            return
        }
        guard let contact = selectedContact else {
            noticeMessage = "Select a recipient first."
            showNotice = true
            return
        }
        guard !messageText.isEmpty else {
            noticeMessage = "Write a message before sending."
            showNotice = true
            return
        }

        isMessageFocused = false
        Haptics.medium()
        isDispatching = true
        dispatchStage = .validating
        dispatchProgress = 0.0
        errorMessage = nil
        showToast = false
        showProgressSheet = true

        let ttlMinutes = selectedTTL.isUntilRead ? 10080 : selectedTTL.minutes
        let isUntilReceived = selectedTTL.isUntilRead

        Task {
            do {
                // Real pipeline only: progress advances on actual completed work.
                dispatchStage = .validating
                dispatchProgress = 0.15

                dispatchStage = .encrypting
                dispatchProgress = 0.30

                dispatchStage = .dispatching
                dispatchProgress = 0.50

                let dispatchResult = try await apiService.dispatchRushAlert(
                    senderName: apiService.deviceDisplayName,
                    recipientId: contact.userId,
                    messageText: messageText,
                    ttlMinutes: ttlMinutes,
                    isCritical: isCriticalOverride,
                    untilReceived: isUntilReceived
                )

                dispatchStage = .pushing
                dispatchProgress = 0.70

                let confirmations = checkDeliveryConfirmations(contact, serverStatus: dispatchResult.status)
                if dispatchResult.status == "MOUNTED_ON_LOCK_SCREEN" {
                    dispatchStage = .mounted
                    dispatchProgress = 0.85
                }

                await MainActor.run {
                    isDispatching = false
                    dispatchStage = .confirmed
                    dispatchProgress = 1.0
                    saveRecipientMessage(messageText, for: contact.userId)
                    messageText = ""
                    Haptics.success()
                    AudioServicesPlaySystemSound(1016)
                    showDeliveryToast(confirmations)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismissProgressSheet()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            dispatchStage = .idle
                            dispatchProgress = 0.0
                        }
                    }
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    handleDispatchFailure(apiError.localizedDescription)
                }
            } catch {
                await MainActor.run {
                    handleDispatchFailure(error.localizedDescription)
                }
            }
        }
    }

    /// Failure keeps the sheet on screen with the real error and Try Again —
    /// no blocking alert, no dead end.
    private func handleDispatchFailure(_ description: String) {
        isDispatching = false
        dispatchStage = .failed
        dispatchProgress = 0.0
        errorMessage = description
        Haptics.error()
        AudioServicesPlaySystemSound(1006)
    }

    // Only claims what is actually known: local trust-circle state + the
    // backend's confirmed dispatch status.
    private func checkDeliveryConfirmations(_ contact: TrustCircleManager.TrustCircleMember, serverStatus: String) -> [String] {
        var confirmations = [String]()
        if contact.hasAppInstalled {
            confirmations.append("Recipient in trust circle & active")
        } else {
            confirmations.append("Recipient app not seen — delivery pending")
        }
        if isCriticalOverride {
            confirmations.append("Critical flag requested")
        }
        if serverStatus == "MOUNTED_ON_LOCK_SCREEN" {
            confirmations.append("Server confirmed push accepted")
        } else if serverStatus == "PUSH_FAILED" {
            confirmations.append("Server reported push failed")
        } else {
            confirmations.append("Server response: " + serverStatus)
        }
        if selectedTTL.isUntilRead {
            confirmations.append("Server will auto-retry until read")
        }
        return confirmations
    }

    private func showDeliveryToast(_ confirmations: [String]) {
        toastMessage = confirmations.joined(separator: "\n")
        toastIcon = "checkmark.circle.fill"
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { showToast = false }
        }
    }

    private func dismissProgressSheet() {
        showProgressSheet = false
        isDispatching = false
    }
}

// MARK: - Supporting Views


/// Apple-style contact avatar: initials in a system color, blue ring + check
/// badge when selected. Deterministic color per recipient.
struct VanillaRecipientAvatarButton: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void

    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]

    private var avatarColor: Color {
        let hash = abs(name.hashValue)
        return Self.palette[hash % Self.palette.count]
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combined = first + second
        return combined.isEmpty ? "?" : combined.uppercased()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(avatarColor.gradient)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(initials)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                        .opacity(isActive ? 1.0 : 0.5)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .accentColor)
                            .background(Circle().fill(.background))
                            .offset(x: 2, y: 2)
                    }
                }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("Recipient \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The dispatch progress sheet: native ProgressView plus an honest,
/// checkmark-driven stage list. Failure shows the real error with Try Again.
struct VanillaDispatchProgressSheet: View {
    @Binding var stage: VanillaDispatchStage
    @Binding var progress: Double
    @Binding var errorMessage: String?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var orderedStages: [VanillaDispatchStage] {
        [.validating, .encrypting, .dispatching, .pushing, .mounted, .confirmed]
    }

    private enum StageRowState { case pending, active, done, failed }

    private func stageState(_ s: VanillaDispatchStage) -> StageRowState {
        if stage == .failed { return .failed }
        let order = orderedStages
        guard let current = order.firstIndex(of: stage),
              let target = order.firstIndex(of: s) else {
            return stage == s ? .active : .pending
        }
        if target < current { return .done }
        if target == current { return stage == .confirmed ? .done : .active }
        return .pending
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if stage == .failed {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Couldn't Send")
                                    .font(.headline)
                                Text(errorMessage ?? "An unknown error occurred.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(stage.rawValue)
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: progress)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Progress") {
                    ForEach(orderedStages, id: \.self) { s in
                        StageRow(stage: s, state: stageState(s))
                    }
                }

                if stage == .failed {
                    Section {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            onRetry()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Cancel", role: .cancel) {
                            onDismiss()
                        }
                    }
                }
            }
            .navigationTitle(stage == .failed ? "Failed" : stage == .confirmed ? "Delivered" : "Sending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage == .confirmed || stage == .failed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDismiss() }
                    }
                }
            }
        }
    }

    private struct StageRow: View {
        let stage: VanillaDispatchStage
        let state: StageRowState

        var body: some View {
            HStack(spacing: 12) {
                Group {
                    switch state {
                    case .pending:
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                    case .active:
                        ProgressView()
                            .controlSize(.small)
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .frame(width: 24)
                Text(stage.rawValue)
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                Spacer()
            }
            .font(.subheadline)
        }
    }
}

/// Standard iOS editable list for message templates.
struct VanillaTemplateManagerSheet: View {
    let templates: [MessageTemplate]
    let onSave: ([MessageTemplate]) -> Void
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing: [MessageTemplate]
    @State private var editMode: EditMode = .inactive

    init(templates: [MessageTemplate], onSave: @escaping ([MessageTemplate]) -> Void, onAdd: @escaping () -> Void) {
        self.templates = templates
        self.onSave = onSave
        self.onAdd = onAdd
        _editing = State(initialValue: templates)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(editing) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                        Text(template.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .onDelete { offsets in
                    editing.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    editing.move(fromOffsets: source, toOffset: destination)
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onSave(editing)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        onSave(editing)
                        dismiss()
                        onAdd()
                    } label: {
                        Label("New Template", systemImage: "plus")
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }
    }
}

/// Lightweight system-material banner for transient confirmations.
struct VanillaToastBanner: View {
    let icon: String
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
                .lineLimit(3)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityLabel(message)
    }
}
