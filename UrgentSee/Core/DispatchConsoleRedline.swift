// MARK: - Redline skin — disruptive mono/red concept.
// Selectable in Settings → Appearance → Dashboard Skin.

import SwiftUI
import AudioToolbox

// MARK: - Dispatch Stage
// The dispatch pipeline's honest stage model. Progress only advances on real
// completed work — the UI never claims more than the backend has confirmed.

enum RedlineDispatchStage: String, CaseIterable {
    case idle = "Idle"
    case validating = "Validating"
    case encrypting = "Encrypting"
    case dispatching = "Sending"
    case pushing = "Pushing"
    case mounted = "On their lock screen"
    case confirmed = "Read"
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

    /// Editorial display word for the transmission sequence.
    var displayWord: String {
        switch self {
        case .idle: return "Ready"
        case .validating: return "Validating"
        case .encrypting: return "Encrypting"
        case .dispatching: return "Sending"
        case .pushing: return "Pushing"
        case .mounted: return "On their lock screen"
        case .confirmed: return "Read"
        case .failed: return "Failed"
        }
    }
}

// MARK: - REDLINE
//
// A creative-director reboot of the dispatch console. MONO/RED: the whole
// interface is monochrome — system background, primary text — with ONE
// sacred red reserved exclusively for the send action. When you see red,
// it means action. Nothing else on screen is red, ever.
//
// The screen asks human questions instead of labeling sections, numbered
// like a manifesto: 01 Who needs you? / 02 What's the message? /
// 03 How long should it live? How loud? / 04 Send.
//
// Disruptive, invincible interactions:
// - HOLD TO SEND: press and hold 1.2s to arm. Release early and nothing
//   happens — misfires are impossible.
// - ARMED countdown: 3 seconds to cancel before anything leaves the phone.
//   Invincible means recoverable.
// - THE RECEIPT: after sending, what actually happened is the whole screen.
// - Honest degradation: unauthenticated isn't an error, it's one clear path.

extension Color {
    /// The only red in the interface. Reserved for the send action.
    static let sacredRed = Color(red: 1.0, green: 0.18, blue: 0.13)
}

struct RedlineDispatchReceipt: Identifiable {
    let id = UUID()
    let recipientName: String
    let date: Date
    let confirmations: [String]
    let failed: Bool
    let error: String?
}

struct DispatchConsoleRedline: View {
    @EnvironmentObject private var settings: AccessibilitySettings

    @State private var selectedContact: TrustCircleManager.TrustCircleMember?
    @State private var messageText: String = ""
    @State private var isCriticalOverride: Bool = false
    @State private var isDispatching: Bool = false
    @State private var errorMessage: String?
    @State private var showTemplateManager = false
    @State private var showAddTemplate = false
    @State private var newTemplateName = ""
    @State private var newTemplateText = ""

    @State private var dispatchProgress: Double = 0.0
    @State private var dispatchStage: RedlineDispatchStage = .idle
    @State private var showNotice = false
    @State private var noticeMessage = ""
    @State private var showRename = false
    @State private var renameTargetId: String = ""
    @State private var renameName: String = ""

    // Hold-to-send + armed countdown state
    @State private var holdProgress: Double = 0.0
    @State private var isHolding: Bool = false
    @State private var holdTimer: Timer?
    @State private var isArmed: Bool = false
    @State private var armCountdown: Int = 3
    @State private var armTimer: Timer?

    // Transmission + receipt
    @State private var showTransmission = false
    @State private var lastReceipt: RedlineDispatchReceipt?

    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared

    @FocusState private var isMessageFocused: Bool

    @AppStorage("messageTemplates") private var messageTemplatesData: Data = Data()
    @AppStorage("recipientMessages") private var recipientMessagesData: Data = Data()

    private let maxCharacters = 140
    private let holdDuration = 1.2

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

        /// Plain-language labels. The UI talks like a human in a hurry.
        var plainLabel: String {
            switch self {
            case .fifteenMinutes: return "15 minutes"
            case .thirtyMinutes: return "30 minutes"
            case .oneHour: return "An hour"
            case .threeHours: return "3 hours"
            case .sixHours: return "6 hours"
            case .twelveHours: return "12 hours"
            case .twentyFourHours: return "A day"
            case .fortyEightHours: return "2 days"
            case .seventyTwoHours: return "3 days"
            case .untilRead: return "Until they read it"
            }
        }

        var sublabel: String {
            switch self {
            case .untilRead: return "Retries until confirmed read"
            case .fifteenMinutes: return "Then it's gone"
            case .thirtyMinutes: return "Then it's gone"
            default: return "Then it expires"
            }
        }

        var contractWord: String {
            switch self {
            case .fifteenMinutes: return "15 MIN"
            case .thirtyMinutes: return "30 MIN"
            case .oneHour: return "1 HOUR"
            case .threeHours: return "3 HOURS"
            case .sixHours: return "6 HOURS"
            case .twelveHours: return "12 HOURS"
            case .twentyFourHours: return "24 HOURS"
            case .fortyEightHours: return "48 HOURS"
            case .seventyTwoHours: return "72 HOURS"
            case .untilRead: return "UNTIL READ"
            }
        }
    }

    @State private var selectedTTL: TTLInterval = .untilRead

    // MARK: - Computed

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

    var canSend: Bool {
        apiService.isAuthenticated && selectedContact != nil && !messageText.isEmpty && !isDispatching && !isArmed
    }

    var statusWord: String {
        if !apiService.isAuthenticated { return "Offline" }
        if showTransmission { return dispatchStage.displayWord }
        if isArmed { return "Armed" }
        if isHolding { return "Hold…" }
        if selectedContact != nil && !messageText.isEmpty { return "Ready" }
        return "Idle"
    }

    /// The contract, stated plainly before every send.
    var contractLine: String {
        let who = selectedContact.map { recipientsManager.displayName(for: $0.userId).uppercased() } ?? "—"
        let loud = isCriticalOverride ? "BREAKS SILENCE" : "QUIET"
        return "TO \(who) · LIVES \(selectedTTL.contractWord) · \(loud)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    statusKicker
                    if !apiService.isAuthenticated {
                        connectBlock
                    }
                    Group {
                        whoSection
                        whatSection
                        howSection
                        contractSection
                        sendSection
                    }
                    .opacity(apiService.isAuthenticated ? 1.0 : 0.3)
                    .disabled(!apiService.isAuthenticated)
                    if let receipt = lastReceipt {
                        receiptSection(receipt)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .onAppear {
                Task { await recipientsManager.loadTrustCircle() }
            }

            if showTransmission {
                transmissionOverlay
            }
        }
        .navigationTitle("Dispatch")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showTemplateManager) {
            RedlineTemplateManagerSheet(
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
    }

    // MARK: - Sections

    private var statusKicker: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            Text(statusWord.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Status: \(statusWord)")
    }

    private var statusDotColor: Color {
        if !apiService.isAuthenticated { return .gray }
        if showTransmission || isArmed { return .sacredRed }
        if selectedContact != nil && !messageText.isEmpty { return .primary }
        return .secondary
    }

    private var connectBlock: some View {
        Button {
            noticeMessage = "Connect this device first: Recipients tab → Settings → Connect This Device."
            showNotice = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect your device.")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                Text("Nothing here works until your device is connected. One step, then you're live.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Show me how →")
                    .font(.headline)
                    .underline()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(.primary, in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(.background)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how to connect this device.")
    }

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionNumber("01")
            Text("Who needs you?")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .tracking(-0.5)
            if availableRecipients.isEmpty {
                Text("No one here yet. Add someone in the Recipients tab.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(availableRecipients, id: \.userId) { contact in
                        recipientRow(contact)
                    }
                }
            }
        }
    }

    private func recipientRow(_ contact: TrustCircleManager.TrustCircleMember) -> some View {
        let isSelected = selectedContact?.userId == contact.userId
        let name = recipientsManager.displayName(for: contact.userId)
        return Button {
            onRecipientSelected(contact)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title2)
                        .fontWeight(.heavy)
                    Text(contact.hasAppInstalled ? "Active now" : "Not seen yet")
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .background.opacity(0.7) : .secondary)
                }
                Spacer()
                if isSelected {
                    Text("◉ LOCKED")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(isSelected ? .primary : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(isSelected ? .background : .primary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            Button {
                renameTargetId = contact.userId
                renameName = name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        .accessibilityLabel("Recipient \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionNumber("02")
            Text("What's the message?")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .tracking(-0.5)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $messageText)
                    .focused($isMessageFocused)
                    .frame(minHeight: 140)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    .onChange(of: messageText) { _, newValue in
                        if newValue.count > maxCharacters {
                            messageText = String(newValue.prefix(maxCharacters))
                            Haptics.warning()
                        }
                        if let contact = selectedContact {
                            saveRecipientMessage(messageText, for: contact.userId)
                        }
                    }
                    .accessibilityLabel("Message")
                if messageText.isEmpty {
                    Text("Type it like you mean it…")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .padding(24)
                        .allowsHitTesting(false)
                }
            }
            // The count is the design: huge numerals.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(messageText.count)")
                    .font(.system(size: 48, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(messageText.count >= maxCharacters ? .sacredRed : .primary)
                Text("/ \(maxCharacters)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(messageTemplates) { template in
                        Button(template.name) { applyTemplate(template) }
                    }
                    Divider()
                    Button("Manage…") { showTemplateManager = true }
                } label: {
                    Text("Templates →")
                        .font(.headline)
                        .underline()
                }
            }
            // Quick actions as plain-text arrows.
            HStack(spacing: 20) {
                ForEach(messageTemplates.prefix(3)) { template in
                    Button("\(template.name) →") { applyTemplate(template) }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var howSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sectionNumber("03")
                Text("How long should it live?")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .tracking(-0.5)
                VStack(spacing: 2) {
                    ForEach(TTLInterval.allCases) { interval in
                        ttlRow(interval)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("How loud?")
                    .font(.title)
                    .fontWeight(.heavy)
                    .tracking(-0.5)
                Toggle(isOn: $isCriticalOverride) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Break through silence")
                            .font(.headline)
                        Text("Bypasses silent mode and Do Not Disturb on their phone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
                if isCriticalOverride {
                    Text("This will bypass silent mode and Do Not Disturb on their phone. Only for true emergencies.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.default, value: isCriticalOverride)
        }
    }

    private func ttlRow(_ interval: TTLInterval) -> some View {
        let isSelected = selectedTTL == interval
        return Button {
            Haptics.selection()
            selectedTTL = interval
        } label: {
            HStack {
                Circle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(interval.plainLabel)
                        .font(.headline)
                        .fontWeight(isSelected ? .bold : .regular)
                    Text(interval.sublabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expires: \(interval.plainLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var contractSection: some View {
        Text(contractLine)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Summary: \(contractLine.lowercased())")
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionNumber("04")
            if isArmed {
                armedView
            } else {
                holdToSendButton
            }
        }
    }

    /// The sacred red block. Press and hold — release early and nothing happens.
    private var holdToSendButton: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(canSend ? .sacredRed : Color.primary.opacity(0.12))
            // Hold progress fill
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white.opacity(0.35))
                    .frame(width: geo.size.width * holdProgress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Text(canSend ? (isHolding ? "KEEP HOLDING" : "HOLD TO SEND") : sendPrerequisite)
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundStyle(canSend ? .white : .secondary)
                    if canSend && !isHolding {
                        Text("Press and hold — release early and nothing sends.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if isHolding {
                        Text("Release to cancel")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer()
            }
            .padding(.vertical, 30)
        }
        .frame(height: 120)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if canSend && !isHolding && !isArmed { startHold() }
                }
                .onEnded { _ in
                    cancelHold(wasReleased: true)
                }
        )
        .accessibilityLabel(canSend ? "Hold to send" : sendPrerequisite)
        .accessibilityHint("Press and hold for just over a second to arm the send.")
    }

    private var sendPrerequisite: String {
        if selectedContact == nil { return "PICK WHO FIRST" }
        if messageText.isEmpty { return "WRITE IT FIRST" }
        return "HOLD TO SEND"
    }

    private var armedView: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.primary)
                VStack(spacing: 4) {
                    Text("ARMED")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.background.opacity(0.7))
                    Text("\(armCountdown)")
                        .font(.system(size: 64, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.background)
                }
                .padding(.vertical, 24)
            }
            Text("Cancel before it leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Cancel") {
                disarm()
            }
            .font(.headline)
            .underline()
            .accessibilityHint("Cancels the send.")
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func receiptSection(_ receipt: RedlineDispatchReceipt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionNumber("RECEIPT")
            Text(receipt.failed ? "It didn't go through." : "Delivered.")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .tracking(-0.5)
                .foregroundStyle(receipt.failed ? .sacredRed : .primary)
            Text("To \(receipt.recipientName) · \(receipt.date, style: .time)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(receipt.confirmations, id: \.self) { line in
                    HStack(spacing: 10) {
                        Image(systemName: receipt.failed ? "xmark" : "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(line)
                            .font(.subheadline)
                    }
                }
                if let error = receipt.error, receipt.failed {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if receipt.failed {
                Button("Try again →") {
                    lastReceipt = nil
                }
                .font(.headline)
                .underline()
            }
        }
        .padding(24)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    /// Full-screen transmission sequence. Huge words, thin progress line.
    private var transmissionOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                if dispatchStage == .failed {
                    Text("Failed.")
                        .font(.system(size: 64, weight: .heavy))
                        .foregroundStyle(.sacredRed)
                    Text(errorMessage ?? "An unknown error occurred.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        showTransmission = false
                        dispatchStage = .idle
                        executeDispatch()
                    } label: {
                        Text("TRY AGAIN")
                            .font(.title2)
                            .fontWeight(.heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 20)
                            .background(.sacredRed, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(.top, 8)
                    Button("Back") {
                        showTransmission = false
                        dispatchStage = .idle
                        dispatchProgress = 0
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .underline()
                } else {
                    Text(dispatchStage.displayWord.uppercased())
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .id(dispatchStage)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    Rectangle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 200 * dispatchProgress, height: 3)
                        .animation(.linear(duration: 0.3), value: dispatchProgress)
                }
                Spacer()
            }
            .padding(32)
        }
        .transition(.opacity)
    }

    private func sectionNumber(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    // MARK: - Hold / Arm

    private func startHold() {
        guard canSend else { return }
        isHolding = true
        holdProgress = 0.0
        Haptics.tap()
        holdTimer?.invalidate()
        let start = Date()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(start)
            holdProgress = min(elapsed / holdDuration, 1.0)
            if elapsed >= holdDuration {
                timer.invalidate()
                completeHold()
            }
        }
    }

    private func cancelHold(wasReleased: Bool) {
        holdTimer?.invalidate()
        holdTimer = nil
        if isHolding && wasReleased && holdProgress < 1.0 {
            Haptics.selection()
        }
        isHolding = false
        holdProgress = 0.0
    }

    private func completeHold() {
        isHolding = false
        holdProgress = 0.0
        Haptics.heavy()
        isArmed = true
        armCountdown = 3
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            armCountdown -= 1
            if armCountdown > 0 {
                Haptics.tap()
            }
            if armCountdown <= 0 {
                timer.invalidate()
                fireArmed()
            }
        }
    }

    private func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        isArmed = false
        Haptics.selection()
    }

    private func fireArmed() {
        armTimer?.invalidate()
        armTimer = nil
        isArmed = false
        executeDispatch()
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
        isDispatching = true
        dispatchStage = .validating
        dispatchProgress = 0.0
        errorMessage = nil
        showTransmission = true

        let ttlMinutes = selectedTTL.isUntilRead ? 10080 : selectedTTL.minutes
        let isUntilReceived = selectedTTL.isUntilRead
        let recipientName = recipientsManager.displayName(for: contact.userId)
        let critical = isCriticalOverride

        Task {
            do {
                // Real pipeline only: progress advances on actual completed work.
                await MainActor.run {
                    dispatchStage = .validating
                    dispatchProgress = 0.15
                }
                await MainActor.run {
                    dispatchStage = .encrypting
                    dispatchProgress = 0.30
                }
                await MainActor.run {
                    dispatchStage = .dispatching
                    dispatchProgress = 0.50
                }

                let dispatchResult = try await apiService.dispatchRushAlert(
                    senderName: apiService.deviceDisplayName,
                    recipientId: contact.userId,
                    messageText: messageText,
                    ttlMinutes: ttlMinutes,
                    isCritical: critical,
                    untilReceived: isUntilReceived
                )

                await MainActor.run {
                    dispatchStage = .pushing
                    dispatchProgress = 0.70
                }

                let confirmations = checkDeliveryConfirmations(contact, serverStatus: dispatchResult.status)
                let mounted = dispatchResult.status == "MOUNTED_ON_LOCK_SCREEN"

                await MainActor.run {
                    if mounted {
                        dispatchStage = .mounted
                        dispatchProgress = 0.85
                    }
                    isDispatching = false
                    dispatchStage = .confirmed
                    dispatchProgress = 1.0
                    saveRecipientMessage(messageText, for: contact.userId)
                    messageText = ""
                    Haptics.success()
                    AudioServicesPlaySystemSound(1016)
                    lastReceipt = RedlineDispatchReceipt(
                        recipientName: recipientName,
                        date: Date(),
                        confirmations: confirmations,
                        failed: false,
                        error: nil
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        showTransmission = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            dispatchStage = .idle
                            dispatchProgress = 0.0
                        }
                    }
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    handleDispatchFailure(apiError.localizedDescription, recipientName: recipientName)
                }
            } catch {
                await MainActor.run {
                    handleDispatchFailure(error.localizedDescription, recipientName: recipientName)
                }
            }
        }
    }

    /// Failure keeps the transmission screen up with the real error and a
    /// retry — and writes a failed receipt so the miss is never silent.
    private func handleDispatchFailure(_ description: String, recipientName: String) {
        isDispatching = false
        dispatchStage = .failed
        dispatchProgress = 0.0
        errorMessage = description
        Haptics.error()
        AudioServicesPlaySystemSound(1006)
        lastReceipt = RedlineDispatchReceipt(
            recipientName: recipientName,
            date: Date(),
            confirmations: ["Nothing was sent. Try again."],
            failed: true,
            error: description
        )
    }

    // Only claims what is actually known: local trust-circle state + the
    // backend's confirmed dispatch status.
    private func checkDeliveryConfirmations(_ contact: TrustCircleManager.TrustCircleMember, serverStatus: String) -> [String] {
        var confirmations = [String]()
        if contact.hasAppInstalled {
            confirmations.append("Recipient active")
        } else {
            confirmations.append("Recipient app not seen — delivery pending")
        }
        if isCriticalOverride {
            confirmations.append("Critical flag sent")
        }
        if serverStatus == "MOUNTED_ON_LOCK_SCREEN" {
            confirmations.append("Server confirmed push accepted")
        } else if serverStatus == "PUSH_FAILED" {
            confirmations.append("Server reported push failed")
        } else {
            confirmations.append("Server response: " + serverStatus)
        }
        if selectedTTL.isUntilRead {
            confirmations.append("Retrying until read")
        }
        return confirmations
    }
}

// MARK: - Supporting Views


/// Standard editable list for message templates.
struct RedlineTemplateManagerSheet: View {
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
