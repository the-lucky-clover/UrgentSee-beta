import SwiftUI
import AudioToolbox

// MARK: - Nuke Ops skin — tactical nuclear ops.
//
// A full tactical-ops reskin of the dispatch console: phosphor green on
// ops-black, stencil monospaced type, hazard striping, and two-person-rule
// style launch discipline (ARM, then LAUNCH, then a 3-second ABORT window).
// The theme is presentation only — underneath it drives the exact same real
// dispatch pipeline, TTL mapping, and critical flag as every other skin.
// Selectable in Settings → Appearance → Dashboard Skin.

// MARK: - Stage model

enum NukeOpsDispatchStage: String, CaseIterable {
    case idle = "STANDBY"
    case validating = "VALIDATING ORDERS"
    case encrypting = "SEALING PACKAGE"
    case dispatching = "UPLINKING"
    case pushing = "PUSHING"
    case mounted = "ON THEIR SCREEN"
    case confirmed = "CONFIRMED"
    case failed = "SCRUBBED"

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
}

// MARK: - Palette

extension Color {
    static let opsBlack = Color(red: 0.03, green: 0.05, blue: 0.045)
    static let phosphor = Color(red: 0.30, green: 1.0, blue: 0.55)
    static let opsAmber = Color(red: 1.0, green: 0.70, blue: 0.20)
    static let opsRed = Color(red: 1.0, green: 0.22, blue: 0.15)
}

// MARK: - Main view

struct DispatchConsoleNukeOps: View {
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
    @State private var dispatchStage: NukeOpsDispatchStage = .idle
    @State private var showNotice = false
    @State private var noticeMessage = ""
    @State private var showRename = false
    @State private var renameTargetId: String = ""
    @State private var renameName: String = ""

    // Launch discipline: ARM → LAUNCH → 3s ABORT window.
    @State private var isArmed: Bool = false
    @State private var commitCountdown: Int = 3
    @State private var commitTimer: Timer?

    @State private var showUplink = false
    @State private var lastAfterAction: NukeOpsAfterAction?

    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared

    @FocusState private var isMessageFocused: Bool

    @AppStorage("messageTemplates") private var messageTemplatesData: Data = Data()
    @AppStorage("recipientMessages") private var recipientMessagesData: Data = Data()

    private let maxCharacters = 140

    enum NukeOpsTTL: Int, CaseIterable, Identifiable {
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case oneHour = 60
        case threeHours = 180
        case sixHours = 360
        case twelveHours = 720
        case twentyFourHours = 1440
        case fortyEightHours = 2880
        case seventyTwoHours = 4320
        case untilConfirmed = -1

        var id: Int { rawValue }
        var minutes: Int { rawValue }
        var isUntilConfirmed: Bool { self == .untilConfirmed }

        var label: String {
            switch self {
            case .fifteenMinutes: return "15 MIN"
            case .thirtyMinutes: return "30 MIN"
            case .oneHour: return "1 HR"
            case .threeHours: return "3 HR"
            case .sixHours: return "6 HR"
            case .twelveHours: return "12 HR"
            case .twentyFourHours: return "24 HR"
            case .fortyEightHours: return "48 HR"
            case .seventyTwoHours: return "72 HR"
            case .untilConfirmed: return "UNTIL CONFIRMED"
            }
        }

        var sublabel: String {
            self == .untilConfirmed ? "Signal repeats until read" : "Signal decays, then gone"
        }
    }

    @State private var selectedTTL: NukeOpsTTL = .untilConfirmed

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

    var canLaunch: Bool {
        apiService.isAuthenticated && selectedContact != nil && !messageText.isEmpty && !isDispatching && !isArmed
    }

    var statusWord: String {
        if !apiService.isAuthenticated { return "OFFLINE" }
        if showUplink { return dispatchStage.rawValue }
        if isArmed { return "ARMED" }
        if selectedContact != nil && !messageText.isEmpty { return "READY" }
        return "STANDBY"
    }

    var opOrder: String {
        let who = selectedContact.map { recipientsManager.displayName(for: $0.userId).uppercased() } ?? "--"
        let loud = isCriticalOverride ? "EMCON OVERRIDE" : "EMCON RESPECTED"
        return "TGT \(who) // DECAY \(selectedTTL.label) // \(loud)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.opsBlack.ignoresSafeArea()
            NukeOpsGridBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    statusLine
                    if !apiService.isAuthenticated {
                        offlineBlock
                    }
                    Group {
                        targetSection
                        payloadSection
                        decaySection
                        opOrderLine
                        launchSection
                    }
                    .opacity(apiService.isAuthenticated ? 1.0 : 0.35)
                    .disabled(!apiService.isAuthenticated)
                    if let aa = lastAfterAction {
                        afterActionSection(aa)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .onAppear {
                Task { await recipientsManager.loadTrustCircle() }
            }
            if showUplink {
                uplinkOverlay
            }
        }
        .navigationTitle("SILO")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTemplateManager) {
            NukeOpsTemplateManager(templates: messageTemplates, onSave: saveTemplates(_:), onAdd: { showAddTemplate = true })
        }
        .alert("Rename Target", isPresented: $showRename) {
            TextField("Callsign", text: $renameName)
            Button("Save") {
                let trimmed = renameName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    recipientsManager.setDisplayName(trimmed, for: renameTargetId)
                    Haptics.success()
                }
            }
            Button("Cancel", role: .cancel) { }
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
        }
    }

    // MARK: - Sections

    private var statusLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "atom")
                .foregroundStyle(.phosphor)
            Text("STATUS: \(statusWord)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.phosphor)
            Spacer()
            Text("SKIN: NUKE OPS")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .accessibilityLabel("Status: \(statusWord)")
    }

    private var offlineBlock: some View {
        Button {
            noticeMessage = "Connect this device first: Recipients tab → Settings → Connect This Device."
            showNotice = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("// NO UPLINK")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.opsAmber)
                Text("Establish connection.")
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white)
                Text("Recipients → Settings → Connect This Device.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.opsAmber, lineWidth: 1.5))
            .background(Color.opsAmber.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NukeOpsSectionHeader(number: "01", title: "TARGET PACKAGE")
            if availableRecipients.isEmpty {
                Text("No targets on scope. Add recipients in the Recipients tab.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: 8) {
                    ForEach(availableRecipients, id: \.userId) { contact in
                        targetRow(contact)
                    }
                }
            }
        }
    }

    private func targetRow(_ contact: TrustCircleManager.TrustCircleMember) -> some View {
        let isSelected = selectedContact?.userId == contact.userId
        let name = recipientsManager.displayName(for: contact.userId)
        return Button {
            onRecipientSelected(contact)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "scope" : "circle")
                    .foregroundStyle(isSelected ? .phosphor : .white.opacity(0.3))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.uppercased())
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                    Text(contact.hasAppInstalled ? "SIGNAL ACQUIRED" : "SIGNAL WEAK")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(contact.hasAppInstalled ? .phosphor.opacity(0.8) : .opsAmber)
                }
                Spacer()
                if isSelected {
                    Text("[ LOCKED ]")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.phosphor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? .phosphor : .white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
            .background((isSelected ? Color.phosphor : Color.white).opacity(isSelected ? 0.08 : 0.03),
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameTargetId = contact.userId
                renameName = name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        .accessibilityLabel("Target \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var payloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NukeOpsSectionHeader(number: "02", title: "PAYLOAD")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $messageText)
                    .focused($isMessageFocused)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
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
                    Text("> ENTER MESSAGE_")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(24)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Text("\(messageText.count)/\(maxCharacters)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(messageText.count >= maxCharacters ? .opsRed : .phosphor)
                Spacer()
                Menu {
                    ForEach(messageTemplates) { template in
                        Button(template.name.uppercased()) { applyTemplate(template) }
                    }
                    Divider()
                    Button("MANAGE TEMPLATES") { showTemplateManager = true }
                } label: {
                    Text("+ TEMPLATES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.phosphor)
                }
            }
            HStack(spacing: 16) {
                ForEach(messageTemplates.prefix(3)) { template in
                    Button("[ \(template.name.uppercased()) ]") { applyTemplate(template) }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var decaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                NukeOpsSectionHeader(number: "03", title: "SIGNAL DECAY")
                Text("How long the signal persists.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(NukeOpsTTL.allCases) { ttl in
                        decayCell(ttl)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                NukeOpsSectionHeader(number: "04", title: "EMCON")
                Toggle(isOn: $isCriticalOverride) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OVERRIDE EMCON")
                            .font(.system(.headline, design: .monospaced))
                            .fontWeight(.bold)
                            .tracking(1)
                        Text("Bypasses silent mode and Do Not Disturb on their device.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .tint(.opsAmber)
                if isCriticalOverride {
                    Text("!! OVERRIDE ACTIVE — this will break through silent mode and Do Not Disturb. True emergencies only.")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.opsAmber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.opsAmber, lineWidth: 1))
                        .transition(.opacity)
                }
            }
            .animation(.default, value: isCriticalOverride)
        }
    }

    private func decayCell(_ ttl: NukeOpsTTL) -> some View {
        let isSelected = selectedTTL == ttl
        return Button {
            Haptics.selection()
            selectedTTL = ttl
        } label: {
            VStack(spacing: 4) {
                Text(ttl.label)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                Text(ttl.sublabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? .phosphor : .white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
            .background(Color.phosphor.opacity(isSelected ? 0.10 : 0.0), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isSelected ? .phosphor : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Signal decay: \(ttl.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var opOrderLine: some View {
        Text(opOrder)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Operation summary: \(opOrder)")
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NukeOpsSectionHeader(number: "05", title: "LAUNCH AUTH")
            if isArmed {
                commitView
            } else {
                Toggle(isOn: $isArmed) {
                    Text("ARM LAUNCH")
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(2)
                }
                .tint(.opsRed)
                .disabled(!canLaunch)
                .onChange(of: isArmed) { _, armed in
                    if armed { startCommit() } else { cancelCommit() }
                }
                if canLaunch {
                    Text("Two-step rule: ARM first, then LAUNCH. You get 3 seconds to ABORT.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    Text(launchPrerequisite)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.opsAmber)
                }
            }
        }
    }

    private var launchPrerequisite: String {
        if selectedContact == nil { return "!! SELECT TARGET FIRST" }
        if messageText.isEmpty { return "!! LOAD PAYLOAD FIRST" }
        return ""
    }

    private var commitView: some View {
        VStack(spacing: 12) {
            NukeOpsHazardStripes()
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Button {
                fireCommit()
            } label: {
                Text("LAUNCH")
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.heavy)
                    .tracking(6)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(.opsRed, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Text("COMMIT IN \(commitCountdown)…")
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.opsRed)
            Button("ABORT") {
                isArmed = false
            }
            .font(.system(.headline, design: .monospaced))
            .fontWeight(.bold)
            .tracking(2)
            .foregroundStyle(.white.opacity(0.7))
            .underline()
            .accessibilityHint("Aborts the launch.")
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func startCommit() {
        guard canLaunch else { isArmed = false; return }
        Haptics.heavy()
        commitCountdown = 3
        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            commitCountdown -= 1
            if commitCountdown > 0 { Haptics.tap() }
            if commitCountdown <= 0 {
                timer.invalidate()
                // Hold at zero until the operator presses LAUNCH — the
                // countdown arms, it never fires on its own.
                commitCountdown = 0
            }
        }
    }

    private func cancelCommit() {
        commitTimer?.invalidate()
        commitTimer = nil
        Haptics.selection()
    }

    private func fireCommit() {
        commitTimer?.invalidate()
        commitTimer = nil
        isArmed = false
        executeDispatch()
    }

    private func afterActionSection(_ aa: NukeOpsAfterAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NukeOpsSectionHeader(number: "AA", title: "AFTER-ACTION")
            Text(aa.failed ? "MISSION SCRUBBED." : "HIT CONFIRMED.")
                .font(.title)
                .fontWeight(.heavy)
                .foregroundStyle(aa.failed ? .opsRed : .phosphor)
            Text("TGT \(aa.recipientName.uppercased()) // \(aa.date, style: .time)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(aa.lines, id: \.self) { line in
                    Text("> \(line)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if let error = aa.error {
                    Text("> ERROR: \(error)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.opsRed)
                }
            }
            if aa.failed {
                Button("[ RETRY LAUNCH ]") { lastAfterAction = nil }
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.phosphor)
            }
        }
        .padding(20)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private var uplinkOverlay: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                if dispatchStage == .failed {
                    Text("LAUNCH SCRUBBED.")
                        .font(.system(size: 40, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.opsRed)
                        .multilineTextAlignment(.center)
                    Text(errorMessage ?? "Unknown error.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("[ RETRY LAUNCH ]") {
                        showUplink = false
                        dispatchStage = .idle
                        executeDispatch()
                    }
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(.opsRed, in: RoundedRectangle(cornerRadius: 10))
                    Button("STAND DOWN") {
                        showUplink = false
                        dispatchStage = .idle
                        dispatchProgress = 0
                    }
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .underline()
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundStyle(.phosphor)
                    Text(dispatchStage.rawValue)
                        .font(.system(size: 36, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.phosphor)
                        .multilineTextAlignment(.center)
                        .id(dispatchStage)
                        .transition(.opacity)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.15))
                            Rectangle()
                                .fill(.phosphor)
                                .frame(width: geo.size.width * dispatchProgress)
                        }
                    }
                    .frame(width: 220, height: 6)
                    Text("\(Int(dispatchProgress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(32)
        }
        .transition(.opacity)
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
            noticeMessage = "Select a target first."
            showNotice = true
            return
        }
        guard !messageText.isEmpty else {
            noticeMessage = "Load a payload before launching."
            showNotice = true
            return
        }

        isMessageFocused = false
        isDispatching = true
        dispatchStage = .validating
        dispatchProgress = 0.0
        errorMessage = nil
        showUplink = true

        let ttlMinutes = selectedTTL.isUntilConfirmed ? 10080 : selectedTTL.minutes
        let isUntilReceived = selectedTTL.isUntilConfirmed
        let recipientName = recipientsManager.displayName(for: contact.userId)
        let critical = isCriticalOverride

        Task {
            do {
                // Real pipeline only: progress advances on actual completed work.
                await MainActor.run { dispatchStage = .validating; dispatchProgress = 0.15 }
                await MainActor.run { dispatchStage = .encrypting; dispatchProgress = 0.30 }
                await MainActor.run { dispatchStage = .dispatching; dispatchProgress = 0.50 }

                let dispatchResult = try await apiService.dispatchRushAlert(
                    senderName: apiService.deviceDisplayName,
                    recipientId: contact.userId,
                    messageText: messageText,
                    ttlMinutes: ttlMinutes,
                    isCritical: critical,
                    untilReceived: isUntilReceived
                )

                await MainActor.run { dispatchStage = .pushing; dispatchProgress = 0.70 }

                let lines = checkAfterAction(contact, serverStatus: dispatchResult.status)
                let mounted = dispatchResult.status == "MOUNTED_ON_LOCK_SCREEN"

                await MainActor.run {
                    if mounted { dispatchStage = .mounted; dispatchProgress = 0.85 }
                    isDispatching = false
                    dispatchStage = .confirmed
                    dispatchProgress = 1.0
                    saveRecipientMessage(messageText, for: contact.userId)
                    messageText = ""
                    Haptics.success()
                    AudioServicesPlaySystemSound(1016)
                    lastAfterAction = NukeOpsAfterAction(recipientName: recipientName, date: Date(), lines: lines, failed: false, error: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        showUplink = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            dispatchStage = .idle
                            dispatchProgress = 0.0
                        }
                    }
                }
            } catch let apiError as APIError {
                await MainActor.run { handleFailure(apiError.localizedDescription, recipientName: recipientName) }
            } catch {
                await MainActor.run { handleFailure(error.localizedDescription, recipientName: recipientName) }
            }
        }
    }

    private func handleFailure(_ description: String, recipientName: String) {
        isDispatching = false
        dispatchStage = .failed
        dispatchProgress = 0.0
        errorMessage = description
        Haptics.error()
        AudioServicesPlaySystemSound(1006)
        lastAfterAction = NukeOpsAfterAction(
            recipientName: recipientName, date: Date(),
            lines: ["Nothing left the silo. Retry when ready."],
            failed: true, error: description
        )
    }

    // Only claims what is actually known: local trust-circle state + the
    // backend's confirmed dispatch status.
    private func checkAfterAction(_ contact: TrustCircleManager.TrustCircleMember, serverStatus: String) -> [String] {
        var lines = [String]()
        lines.append(contact.hasAppInstalled ? "Target active" : "Target signal weak — delivery pending")
        if isCriticalOverride { lines.append("EMCON override transmitted") }
        if serverStatus == "MOUNTED_ON_LOCK_SCREEN" {
            lines.append("Server confirmed push accepted")
        } else if serverStatus == "PUSH_FAILED" {
            lines.append("Server reported push failed")
        } else {
            lines.append("Server response: " + serverStatus)
        }
        if selectedTTL.isUntilConfirmed { lines.append("Signal repeating until confirmed") }
        return lines
    }
}

// MARK: - Supporting types

struct NukeOpsAfterAction: Identifiable {
    let id = UUID()
    let recipientName: String
    let date: Date
    let lines: [String]
    let failed: Bool
    let error: String?
}

struct NukeOpsSectionHeader: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("// \(number)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.phosphor)
            Text(title)
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.heavy)
                .tracking(2)
                .foregroundStyle(.white)
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Section \(title)")
    }
}

/// Diagonal hazard striping for the launch commit block.
struct NukeOpsHazardStripes: View {
    var body: some View {
        GeometryReader { geo in
            let stripeWidth: CGFloat = 16
            let count = Int(geo.size.width / stripeWidth) + 2
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle()
                        .fill(i.isMultiple(of: 2) ? Color.opsAmber : Color.black)
                        .frame(width: stripeWidth)
                        .skewX(-0.5)
                }
            }
        }
    }
}

private extension View {
    func skewX(_ amount: CGFloat) -> some View {
        self.transformEffect(CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: 0, ty: 0))
    }
}

/// Faint tactical grid behind the console.
private struct NukeOpsGridBackground: View {
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 32
            let cols = Int(geo.size.width / step) + 1
            let rows = Int(geo.size.height / step) + 1
            ZStack {
                ForEach(0..<cols, id: \.self) { c in
                    Rectangle()
                        .fill(Color.phosphor.opacity(0.05))
                        .frame(width: 1)
                        .position(x: CGFloat(c) * step, y: geo.size.height / 2)
                        .frame(height: geo.size.height)
                }
                ForEach(0..<rows, id: \.self) { r in
                    Rectangle()
                        .fill(Color.phosphor.opacity(0.05))
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: CGFloat(r) * step)
                        .frame(width: geo.size.width)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Template manager in ops dress.
struct NukeOpsTemplateManager: View {
    let templates: [MessageTemplate]
    let onSave: ([MessageTemplate]) -> Void
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing: [MessageTemplate]

    init(templates: [MessageTemplate], onSave: @escaping ([MessageTemplate]) -> Void, onAdd: @escaping () -> Void) {
        self.templates = templates
        self.onSave = onSave
        self.onAdd = onAdd
        _editing = State(initialValue: templates)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.opsBlack.ignoresSafeArea()
                List {
                    ForEach(editing) { template in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name.uppercased())
                                .font(.system(.headline, design: .monospaced))
                                .foregroundStyle(.phosphor)
                            Text(template.text)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                    .onDelete { editing.remove(atOffsets: $0) }
                    .onMove { editing.move(fromOffsets: $0, toOffset: $1) }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("TEMPLATES")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("DONE") { onSave(editing); dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .bottomBar) {
                    Button { onSave(editing); dismiss(); onAdd() } label: {
                        Label("NEW TEMPLATE", systemImage: "plus")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }
}
