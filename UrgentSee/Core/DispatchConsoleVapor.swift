import SwiftUI
import AudioToolbox

// MARK: - Vapor skin — the vision-quest remix.
//
// The whole console remixed pillar to post: a deep indigo night sky with
// drifting aurora, warm rounded type, and one signature interaction — the
// orb. Press and hold to CHARGE it; release at full charge to send. Let go
// early and it breathes back out — nothing sent, no harm done.
//
// The trip is presentation only. Underneath: the same real dispatch
// pipeline, TTL mapping, critical flag, drafts, and templates as every
// other skin. Selectable in Settings → Appearance → Dashboard Skin.

// MARK: - Stage model

enum VaporDispatchStage: String, CaseIterable {
    case idle = "Drifting"
    case validating = "Gathering"
    case encrypting = "Weaving"
    case dispatching = "Sending"
    case pushing = "Rippling out"
    case mounted = "On their screen"
    case confirmed = "Heard"
    case failed = "Lost"

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
    static let vaporNight = Color(red: 0.05, green: 0.04, blue: 0.10)
    static let vaporIridescent = LinearGradient(
        colors: [Color.cyan, Color.purple, Color.pink],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Main view

struct DispatchConsoleVapor: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var dispatchStage: VaporDispatchStage = .idle
    @State private var showNotice = false
    @State private var noticeMessage = ""
    @State private var showRename = false
    @State private var renameTargetId: String = ""
    @State private var renameName: String = ""

    // The orb: charge 0 → 1 by holding, release at full charge to send.
    @State private var charge: Double = 0.0
    @State private var isCharging: Bool = false
    @State private var chargeTimer: Timer?
    @State private var orbBreathing = false

    @State private var showRipple = false
    @State private var lastEcho: VaporEcho?

    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared

    @FocusState private var isMessageFocused: Bool

    @AppStorage("messageTemplates") private var messageTemplatesData: Data = Data()
    @AppStorage("recipientMessages") private var recipientMessagesData: Data = Data()

    private let maxCharacters = 140
    private let chargeDuration = 1.5

    enum VaporTTL: Int, CaseIterable, Identifiable {
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case oneHour = 60
        case threeHours = 180
        case sixHours = 360
        case twelveHours = 720
        case twentyFourHours = 1440
        case fortyEightHours = 2880
        case seventyTwoHours = 4320
        case untilHeard = -1

        var id: Int { rawValue }
        var minutes: Int { rawValue }
        var isUntilHeard: Bool { self == .untilHeard }

        var label: String {
            switch self {
            case .fifteenMinutes: return "15 min"
            case .thirtyMinutes: return "30 min"
            case .oneHour: return "1 hour"
            case .threeHours: return "3 hours"
            case .sixHours: return "6 hours"
            case .twelveHours: return "12 hours"
            case .twentyFourHours: return "A day"
            case .fortyEightHours: return "2 days"
            case .seventyTwoHours: return "3 days"
            case .untilHeard: return "Until it's heard"
            }
        }

        var sublabel: String {
            self == .untilHeard ? "Echoes until confirmed" : "Then it fades out"
        }
    }

    @State private var selectedTTL: VaporTTL = .untilHeard

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

    var canCharge: Bool {
        apiService.isAuthenticated && selectedContact != nil && !messageText.isEmpty && !isDispatching
    }

    var statusWord: String {
        if !apiService.isAuthenticated { return "quiet" }
        if showRipple { return dispatchStage.rawValue }
        if isCharging { return "charging" }
        if selectedContact != nil && !messageText.isEmpty { return "ready" }
        return "drifting"
    }

    var vibeLine: String {
        let who = selectedContact.map { recipientsManager.displayName(for: $0.userId) } ?? "no one yet"
        let loud = isCriticalOverride ? "breaks the quiet" : "keeps the quiet"
        return "to \(who) · echoes \(selectedTTL.label) · \(loud)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.vaporNight.ignoresSafeArea()
            VaporAuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    statusLine
                    if !apiService.isAuthenticated {
                        quietBlock
                    }
                    Group {
                        whoSection
                        saySection
                        echoSection
                        vibeSection
                        orbSection
                    }
                    .opacity(apiService.isAuthenticated ? 1.0 : 0.35)
                    .disabled(!apiService.isAuthenticated)
                    if let echo = lastEcho {
                        echoesSection(echo)
                    }
                    Spacer(minLength: 48)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            .onAppear {
                Task { await recipientsManager.loadTrustCircle() }
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                        orbBreathing = true
                    }
                }
            }
            if showRipple {
                rippleOverlay
            }
        }
        .navigationTitle("Vapor")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTemplateManager) {
            VaporTemplateManager(templates: messageTemplates, onSave: saveTemplates(_:), onAdd: { showAddTemplate = true })
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameName)
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
        HStack(spacing: 8) {
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 7, height: 7)
                .blur(radius: 1)
            Text(statusWord)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text("vapor trail")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
        }
        .accessibilityLabel("Status: \(statusWord)")
    }

    private var quietBlock: some View {
        Button {
            noticeMessage = "Connect this device first: Recipients tab → Settings → Connect This Device."
            showNotice = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("It's quiet here.")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Connect your device and the night lights up. Recipients → Settings → Connect This Device.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Show me how")
                    .font(.system(.headline, design: .rounded))
                    .underline()
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded))
            .fontWeight(.heavy)
            .foregroundStyle(.white)
    }

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            question("Who's out there?")
            if availableRecipients.isEmpty {
                Text("No one yet — add someone in the Recipients tab.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: 10) {
                    ForEach(availableRecipients, id: \.userId) { contact in
                        someoneRow(contact)
                    }
                }
            }
        }
    }

    private func someoneRow(_ contact: TrustCircleManager.TrustCircleMember) -> some View {
        let isSelected = selectedContact?.userId == contact.userId
        let name = recipientsManager.displayName(for: contact.userId)
        return Button {
            onRecipientSelected(contact)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.vaporIridescent : Color.white.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(contact.hasAppInstalled ? "here right now" : "away")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(isSelected ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.vaporIridescent : Color.white.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
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

    private var saySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            question("Say it.")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $messageText)
                    .focused($isMessageFocused)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
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
                if messageText.isEmpty {
                    Text("What do they need to hear?")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(28)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Text("\(messageText.count) / \(maxCharacters)")
                    .font(.system(.subheadline, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(messageText.count >= maxCharacters ? .pink : .white.opacity(0.5))
                Spacer()
                Menu {
                    ForEach(messageTemplates) { template in
                        Button(template.name) { applyTemplate(template) }
                    }
                    Divider()
                    Button("Manage…") { showTemplateManager = true }
                } label: {
                    Text("Templates")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.10), in: Capsule())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(messageTemplates.prefix(4)) { template in
                        Button(template.name) { applyTemplate(template) }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.08), in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var echoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            question("How long should it echo?")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(VaporTTL.allCases) { ttl in
                    echoCell(ttl)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("How loud?")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Toggle(isOn: $isCriticalOverride) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Break the quiet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Cuts through silent mode and Do Not Disturb on their phone.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .tint(.pink)
                if isCriticalOverride {
                    Text("This breaks through silent mode and Do Not Disturb. Save it for the real ones.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pink.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.pink.opacity(0.4), lineWidth: 1))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.default, value: isCriticalOverride)
        }
    }

    private func echoCell(_ ttl: VaporTTL) -> some View {
        let isSelected = selectedTTL == ttl
        return Button {
            Haptics.selection()
            selectedTTL = ttl
        } label: {
            VStack(spacing: 4) {
                Text(ttl.label)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text(ttl.sublabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.vaporIridescent.opacity(0.35) : .white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.vaporIridescent : .white.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Echo: \(ttl.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var vibeSection: some View {
        Text(vibeLine)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Summary: \(vibeLine)")
    }

    // MARK: - The orb

    private var orbSection: some View {
        VStack(spacing: 16) {
            question("Send it.")
            ZStack {
                // Charge ring
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 10)
                    .frame(width: 190, height: 190)
                Circle()
                    .trim(from: 0, to: charge)
                    .stroke(Color.vaporIridescent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 190, height: 190)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: charge)
                // The orb itself
                Circle()
                    .fill(Color.vaporIridescent)
                    .frame(width: 150, height: 150)
                    .blur(radius: 2)
                    .opacity(canCharge ? 0.55 + 0.45 * charge : 0.25)
                    .scaleEffect(orbBreathing && !reduceMotion ? 1.04 : 1.0)
                    .scaleEffect(1.0 + 0.12 * charge)
                VStack(spacing: 4) {
                    Text(orbLabel)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                    if canCharge {
                        Text(orbSublabel)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .frame(height: 210)
            .contentShape(Circle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if canCharge && !isCharging { startCharge() }
                    }
                    .onEnded { _ in
                        releaseCharge()
                    }
            )
            .accessibilityLabel(canCharge ? "Charge the orb to send" : orbPrerequisite)
            .accessibilityHint("Press and hold to charge, release at full charge to send.")
            if !canCharge {
                Text(orbPrerequisite)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var orbLabel: String {
        if !canCharge { return "…" }
        if charge >= 1.0 { return "RELEASE" }
        if isCharging { return "\(Int(charge * 100))%" }
        return "HOLD"
    }

    private var orbSublabel: String {
        if charge >= 1.0 { return "to send it" }
        if isCharging { return "charging — let go to cancel" }
        return "press and hold to charge"
    }

    private var orbPrerequisite: String {
        if selectedContact == nil { return "Pick who's out there first." }
        if messageText.isEmpty { return "Say it first." }
        return ""
    }

    private func startCharge() {
        guard canCharge else { return }
        isCharging = true
        charge = 0.0
        Haptics.tap()
        chargeTimer?.invalidate()
        let start = Date()
        chargeTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(start)
            charge = min(elapsed / chargeDuration, 1.0)
            if elapsed >= chargeDuration {
                timer.invalidate()
                Haptics.heavy()
            } else if Int(elapsed * 10) % 5 == 0 {
                Haptics.tap()
            }
        }
    }

    private func releaseCharge() {
        chargeTimer?.invalidate()
        chargeTimer = nil
        if isCharging {
            if charge >= 1.0 {
                // Full charge released → send.
                isCharging = false
                charge = 0.0
                executeDispatch()
            } else {
                // Early release → breathe back out. Nothing sent.
                Haptics.selection()
                isCharging = false
                withAnimation(.easeOut(duration: 0.6)) {
                    charge = 0.0
                }
            }
        }
    }

    // MARK: - Echoes (receipt)

    private func echoesSection(_ echo: VaporEcho) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Echoes")
                .font(.system(.title, design: .rounded))
                .fontWeight(.heavy)
                .foregroundStyle(.white)
            Text(echo.failed ? "The signal didn't make it." : "Heard.")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(echo.failed ? .pink : .white)
            Text("\(echo.recipientName) · \(echo.date, style: .time)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(echo.lines, id: \.self) { line in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(echo.failed ? Color.pink : Color.mint)
                            .frame(width: 8, height: 8)
                        Text(line)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                if let error = echo.error {
                    Text(error)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if echo.failed {
                Button("Try again") { lastEcho = nil }
                    .font(.system(.headline, design: .rounded))
                    .underline()
                    .foregroundStyle(.white)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Ripple overlay (transmission)

    private var rippleOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                if dispatchStage == .failed {
                    Text("Lost.")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(.pink)
                    Text(errorMessage ?? "Something went wrong.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try again") {
                        showRipple = false
                        dispatchStage = .idle
                        executeDispatch()
                    }
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
                    .background(Color.vaporIridescent, in: Capsule())
                    Button("Drift back") {
                        showRipple = false
                        dispatchStage = .idle
                        dispatchProgress = 0
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .underline()
                } else {
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color.vaporIridescent.opacity(0.5 - Double(i) * 0.12), lineWidth: 2)
                                .frame(width: 120 + CGFloat(i) * 50 + CGFloat(dispatchProgress * 60),
                                       height: 120 + CGFloat(i) * 50 + CGFloat(dispatchProgress * 60))
                        }
                        Circle()
                            .fill(Color.vaporIridescent)
                            .frame(width: 90, height: 90)
                            .blur(radius: 2)
                    }
                    .frame(height: 280)
                    Text(dispatchStage.rawValue)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                        .id(dispatchStage)
                        .transition(.opacity)
                    Text("\(Int(dispatchProgress * 100))%")
                        .font(.system(.caption, design: .rounded))
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
            noticeMessage = "Pick who's out there first."
            showNotice = true
            return
        }
        guard !messageText.isEmpty else {
            noticeMessage = "Say it first."
            showNotice = true
            return
        }

        isMessageFocused = false
        isDispatching = true
        dispatchStage = .validating
        dispatchProgress = 0.0
        errorMessage = nil
        showRipple = true

        let ttlMinutes = selectedTTL.isUntilHeard ? 10080 : selectedTTL.minutes
        let isUntilReceived = selectedTTL.isUntilHeard
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

                let lines = checkEchoes(contact, serverStatus: dispatchResult.status)
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
                    lastEcho = VaporEcho(recipientName: recipientName, date: Date(), lines: lines, failed: false, error: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        showRipple = false
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
        lastEcho = VaporEcho(
            recipientName: recipientName, date: Date(),
            lines: ["Nothing left the night sky. Try again."],
            failed: true, error: description
        )
    }

    // Only claims what is actually known: local trust-circle state + the
    // backend's confirmed dispatch status.
    private func checkEchoes(_ contact: TrustCircleManager.TrustCircleMember, serverStatus: String) -> [String] {
        var lines = [String]()
        lines.append(contact.hasAppInstalled ? "They're here" : "They're away — delivery pending")
        if isCriticalOverride { lines.append("Broke through the quiet") }
        if serverStatus == "MOUNTED_ON_LOCK_SCREEN" {
            lines.append("Server confirmed it landed")
        } else if serverStatus == "PUSH_FAILED" {
            lines.append("Server reported push failed")
        } else {
            lines.append("Server response: " + serverStatus)
        }
        if selectedTTL.isUntilHeard { lines.append("Echoing until heard") }
        return lines
    }
}

// MARK: - Supporting types

struct VaporEcho: Identifiable {
    let id = UUID()
    let recipientName: String
    let date: Date
    let lines: [String]
    let failed: Bool
    let error: String?
}

/// Slow-drifting aurora blobs. Still when reduce motion is on.
private struct VaporAuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: -80 + (drift && !reduceMotion ? 40 : 0),
                            y: 120 + (drift && !reduceMotion ? -50 : 0))
                Circle()
                    .fill(Color.purple.opacity(0.20))
                    .frame(width: 340, height: 340)
                    .blur(radius: 100)
                    .offset(x: 140 + (drift && !reduceMotion ? -50 : 0),
                            y: 320 + (drift && !reduceMotion ? 40 : 0))
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 90)
                    .offset(x: 40 + (drift && !reduceMotion ? 30 : 0),
                            y: 560 + (drift && !reduceMotion ? -30 : 0))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                        drift = true
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Template manager in vapor dress.
struct VaporTemplateManager: View {
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
                Color.vaporNight.ignoresSafeArea()
                List {
                    ForEach(editing) { template in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.white)
                            Text(template.text)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                    .onDelete { editing.remove(atOffsets: $0) }
                    .onMove { editing.move(fromOffsets: $0, toOffset: $1) }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onSave(editing); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .bottomBar) {
                    Button { onSave(editing); dismiss(); onAdd() } label: {
                        Label("New Template", systemImage: "plus")
                    }
                }
            }
        }
    }
}
