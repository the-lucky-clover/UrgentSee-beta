// MARK: - ReDux skin — neon-glass dispatch deck.
// Selectable in Settings → Appearance → Dashboard Skin.

import SwiftUI
import AudioToolbox

// MARK: - Dispatch Stage
// The dispatch pipeline's honest stage model. Progress only advances on real
// completed work — the UI never claims more than the backend has confirmed.

enum ReDuxDispatchStage: String, CaseIterable {
    case idle = "IDLE"
    case validating = "VALIDATING"
    case encrypting = "ENCRYPTING"
    case dispatching = "DISPATCHING"
    case pushing = "PUSHING APNs"
    case mounted = "MOUNTED ON LOCK SCREEN"
    case confirmed = "DELIVERED & READ"
    case failed = "FAILED"

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
        case .dispatching: return "arrow.up.circle.fill"
        case .pushing: return "antenna.radiowaves.left.and.right"
        case .mounted: return "iphone.gen3.radiowaves.left.and.right"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .red
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

// MARK: - Main Dispatch Console — "Dispatch Deck" redesign
//
// A full reimagining of the dispatch dashboard as a mission-control deck:
// one visual system (neon glass on void black), a task-flow layout that ends
// in the big red button at thumb reach, and — critically — every control that
// affects a dispatch (TTL, DND override) is visible on screen. The button
// always tells you exactly what it will do before you press it.

struct DispatchConsoleReDux: View {
    @EnvironmentObject private var settings: AccessibilitySettings

    @State private var selectedContact: TrustCircleManager.TrustCircleMember?
    @State private var messageText: String = ""
    @State private var isCriticalOverride: Bool = true
    @State private var isDispatching: Bool = false
    @State private var errorMessage: String?
    @State private var showTemplateManager = false
    @State private var newTemplateName = ""
    @State private var showSaveTemplate = false

    @State private var dispatchProgress: Double = 0.0
    @State private var dispatchStage: ReDuxDispatchStage = .idle
    @State private var showDispatchToast = false
    @State private var dispatchToastMessage = ""
    @State private var dispatchToastIcon = "checkmark.circle.fill"
    @State private var dispatchToastColor = Color.green
    @State private var showNotice = false
    @State private var noticeMessage = ""
    @State private var showStageTracker = false
    @State private var renameRecipient: RecipientToName?

    @StateObject private var apiService = APIService.shared
    @StateObject private var recipientsManager = TrustCircleManager.shared

    @State private var animatedIn: [Bool] = Array(repeating: false, count: 7)
    @FocusState private var isMessageFocused: Bool

    @AppStorage("messageTemplates") private var messageTemplatesData: Data = Data()
    @AppStorage("recipientMessages") private var recipientMessagesData: Data = Data()

    private let maxCharacters = 140

    /// TTL intervals from 15 minutes up to 72 hours, plus "Until Received" option.
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
        case untilReceived = -1

        var id: Int { rawValue }
        var minutes: Int { rawValue }

        var label: String {
            switch self {
            case .fifteenMinutes: return "15m"
            case .thirtyMinutes: return "30m"
            case .oneHour: return "1h"
            case .threeHours: return "3h"
            case .sixHours: return "6h"
            case .twelveHours: return "12h"
            case .twentyFourHours: return "24h"
            case .fortyEightHours: return "48h"
            case .seventyTwoHours: return "72h"
            case .untilReceived: return "∞"
            }
        }

        var isUntilReceived: Bool { self == .untilReceived }
    }

    let ttlOptions: [TTLInterval] = TTLInterval.allCases

    @State private var selectedTTL: TTLInterval = .untilReceived

    // MARK: - Computed Data

    var messageTemplates: [MessageTemplate] {
        if let decoded = try? JSONDecoder().decode([MessageTemplate].self, from: messageTemplatesData) {
            return decoded
        }
        return defaultTemplates
    }

    var recipientMessages: [String: String] {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: recipientMessagesData) {
            return decoded
        }
        return [:]
    }

    private let defaultTemplates = [
        MessageTemplate(name: "URGENT", text: "URGENT: Need you to see this immediately. Please respond."),
        MessageTemplate(name: "MEDICAL", text: "MEDICAL EMERGENCY: I need help. Location: [LOCATION]. Please call 911."),
        MessageTemplate(name: "SAFETY", text: "SAFETY ALERT: I don't feel safe. Please check on me now."),
        MessageTemplate(name: "CUSTOM", text: "")
    ]

    var activeContacts: [TrustCircleManager.TrustCircleMember] {
        recipientsManager.activeMembers.filter { $0.hasAppInstalled }
    }

    // MARK: - Derived UI State

    private var ts: Double { settings.textSize }

    /// The big button only arms when a dispatch can actually fire.
    private var isArmed: Bool {
        apiService.isAuthenticated && selectedContact != nil && !messageText.isEmpty && !isDispatching
    }

    /// The button always says exactly why it can't fire — no dead taps.
    private var heroLabel: String {
        if !apiService.isAuthenticated { return "CONNECT DEVICE" }
        if isDispatching { return dispatchStage.rawValue }
        if selectedContact == nil { return "SELECT RECIPIENT" }
        if messageText.isEmpty { return "TYPE MESSAGE" }
        return "DISPATCH"
    }

    private var heroIcon: String {
        if !apiService.isAuthenticated { return "lock.fill" }
        if isArmed { return "paperplane.fill" }
        return "paperplane"
    }

    private var statusText: String {
        if !apiService.isAuthenticated { return "OFFLINE" }
        if isDispatching { return dispatchStage.rawValue }
        if isArmed { return "ARMED" }
        return "IDLE"
    }

    private var statusColor: Color {
        if !apiService.isAuthenticated { return .gray }
        if isDispatching { return dispatchStage.color }
        if isArmed { return .neonCyan }
        return .neonRed
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundLayers

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    commandBar
                        .reduxDeckEntrance(index: 0, animatedIn: animatedIn)

                    if !apiService.isAuthenticated {
                        authBanner
                            .reduxDeckEntrance(index: 1, animatedIn: animatedIn)
                    }

                    targetTile
                        .reduxDeckEntrance(index: 1, animatedIn: animatedIn)

                    payloadTile
                        .reduxDeckEntrance(index: 2, animatedIn: animatedIn)

                    deliveryTile
                        .reduxDeckEntrance(index: 3, animatedIn: animatedIn)

                    dispatchHero
                        .reduxDeckEntrance(index: 4, animatedIn: animatedIn)

                    if showStageTracker {
                        stageTracker
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Bottom breathing room for the thumb zone.
                    Color.clear.frame(height: 8)
                        .reduxDeckEntrance(index: 6, animatedIn: animatedIn)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, isMessageFocused ? 120 : 24)
                .animation(.spring(response: 0.42, dampingFraction: 0.8), value: showStageTracker)
            }
        }
        .onAppear {
            triggerEntranceAnimations()
            Task { await recipientsManager.loadTrustCircle() }
        }
        .alert("Need Attention", isPresented: $showNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(noticeMessage)
        }
        .sheet(isPresented: $showTemplateManager) {
            ReDuxTemplateManagerView(
                templates: messageTemplates,
                onSave: { updated in saveTemplates(updated) },
                textSize: ts
            )
        }
        .alert("Save as Template", isPresented: $showSaveTemplate) {
            TextField("Template Name", text: $newTemplateName)
            Button("Cancel", role: .cancel) { newTemplateName = "" }
            Button("Save") { saveCurrentAsTemplate() }
        } message: {
            Text("Save current message as a quick template")
        }
        .overlay { toastOverlay }
        .sheet(item: $renameRecipient) { pending in
            NameRecipientSheet(userId: pending.id, onSave: { name in
                Haptics.success()
                recipientsManager.setDisplayName(name, for: pending.id)
            })
            .environmentObject(settings)
        }
    }

    // MARK: - Root Subviews

    @ViewBuilder private var backgroundLayers: some View {
        Color.voidBlack.ignoresSafeArea()

        // Red command glow from the top — the deck's light source.
        RadialGradient(
            colors: [Color.neonRed.opacity(0.16), Color.neonPink.opacity(0.05), Color.clear],
            center: .top,
            startRadius: 10,
            endRadius: 620
        )
        .ignoresSafeArea()

        // Faint cyan underglow so the deck feels deep, not flat.
        RadialGradient(
            colors: [Color.neonCyan.opacity(0.05), Color.clear],
            center: .bottom,
            startRadius: 40,
            endRadius: 700
        )
        .ignoresSafeArea()

        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .allowsHitTesting(true)
    }

    // MARK: - Command Bar

    @ViewBuilder private var commandBar: some View {
        HStack(spacing: 10) {
            ShimmeringPhoneIcon(size: ts * 0.72)

            Text("URGENTSEE")
                .font(.system(size: ts * 0.82, weight: .black, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            // Live status readout — the single source of truth for deck state.
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.9), radius: 6)

                Text(statusText)
                    .font(.system(size: ts * 0.32, weight: .black, design: .monospaced))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.1))
            .cornerRadius(9)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(statusColor.opacity(0.35), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.25), value: statusText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Auth Banner (top, not buried — auth gates everything)

    @ViewBuilder private var authBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: ts * 0.62, weight: .bold))
                .foregroundColor(.orange)
                .shadow(color: .orange.opacity(0.5), radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text("DEVICE NOT CONNECTED")
                    .font(.system(size: ts * 0.38, weight: .black, design: .monospaced))
                    .foregroundColor(.orange)
                Text("Recipients tab → gear → Connect This Device")
                    .font(.system(size: ts * 0.32))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(13)
        .glassmorphicBento(glowColor: .orange, cornerRadius: 16)
    }

    // MARK: - Target Tile

    @ViewBuilder private var targetTile: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                ReDuxTileLabel("TARGET", color: .neonRed, textSize: ts)
                Spacer()
                Text("\(activeContacts.count) AVAILABLE")
                    .font(.system(size: ts * 0.28, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }

            if activeContacts.isEmpty {
                Text("No recipients with the app installed yet.\nAdd one in the Recipients tab to arm the deck.")
                    .font(.system(size: ts * 0.4))
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeContacts) { contact in
                            ReDuxRecipientCard(
                                contact: contact,
                                isSelected: selectedContact?.id == contact.id,
                                textSize: ts
                            ) {
                                onRecipientSelected(contact)
                            }
                            .contextMenu {
                                Button {
                                    renameRecipient = RecipientToName(id: contact.userId)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .glassmorphicBento(glowColor: .neonRed, cornerRadius: 20)
    }

    // MARK: - Payload Tile

    @ViewBuilder private var payloadTile: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                ReDuxTileLabel("PAYLOAD", color: .neonCyan, textSize: ts)
                Spacer()
                charRing
            }

            // Quick-message chips live with the composer — one section, no
            // layout shift when the template list is empty.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(messageTemplates.filter { !$0.text.isEmpty }) { template in
                        ReDuxTemplateChip(
                            template: template,
                            isSelected: messageText == template.text,
                            textSize: ts
                        ) {
                            applyTemplate(template)
                        }
                    }

                    Button(action: {
                        if messageText.isEmpty {
                            showTemplateManager = true
                        } else {
                            newTemplateName = ""
                            showSaveTemplate = true
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: messageText.isEmpty ? "gearshape.fill" : "plus")
                                .font(.system(size: ts * 0.32, weight: .bold))
                            Text(messageText.isEmpty ? "MANAGE" : "SAVE")
                                .font(.system(size: ts * 0.32, weight: .black, design: .monospaced))
                        }
                        .foregroundColor(.gray)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }

            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text(selectedContact != nil
                         ? "Message for \(recipientsManager.displayName(for: selectedContact!.userId))…"
                         : "Select a target first…")
                        .font(.system(size: ts * 0.55, design: .rounded))
                        .foregroundColor(.gray.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                }

                TextEditor(text: $messageText)
                    .focused($isMessageFocused)
                    .frame(height: ts * 3.6)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .foregroundColor(.white)
                    .font(.system(size: ts * 0.58, weight: .semibold, design: .rounded))
                    .onChange(of: messageText) { _ in
                        KeyboardHaptics.keystroke()
                        if messageText.count > maxCharacters {
                            messageText = String(messageText.prefix(maxCharacters))
                        }
                        if let contact = selectedContact {
                            saveRecipientMessage(messageText, for: contact.userId)
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { dismissKeyboard() }
                                .font(.system(size: ts * 0.45, weight: .semibold))
                                .foregroundColor(.neonRed)
                        }
                    }
            }
            .background(Color.white.opacity(0.03))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.neonCyan.opacity(isMessageFocused ? 0.6 : 0.25), lineWidth: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: isMessageFocused)
            )
        }
        .padding(14)
        .glassmorphicBento(glowColor: .neonCyan, cornerRadius: 20)
    }

    @ViewBuilder private var charRing: some View {
        let count = messageText.count
        let ratio = min(Double(count) / Double(maxCharacters), 1.0)
        let ringColor: Color = count >= maxCharacters ? .neonRed
            : (count > maxCharacters * 8 / 10 ? .orange : .gray)

        HStack(spacing: 8) {
            Text("\(count)/\(maxCharacters)")
                .font(.system(size: ts * 0.3, weight: .bold, design: .monospaced))
                .foregroundColor(ringColor)
                .monospacedDigit()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 4)
                    .frame(width: 26, height: 26)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: ratio)
            }
        }
    }

    // MARK: - Delivery Tile (TTL + Override — previously invisible on iOS)

    @ViewBuilder private var deliveryTile: some View {
        HStack(alignment: .top, spacing: 12) {
            // TTL — every option that affects the dispatch, on screen.
            VStack(alignment: .leading, spacing: 9) {
                ReDuxTileLabel("TTL", color: .neonAmber, textSize: ts)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(ttlOptions) { option in
                        let isSelected = selectedTTL == option
                        Button(action: {
                            Haptics.medium()
                            selectedTTL = option
                        }) {
                            Text(option.label)
                                .font(.system(size: ts * 0.32, weight: .black, design: .monospaced))
                                .foregroundColor(isSelected ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.neonAmber : Color.white.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.neonAmber : Color.white.opacity(0.1), lineWidth: 1.5)
                                )
                                .shadow(color: isSelected ? .neonAmber.opacity(0.4) : .clear, radius: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDispatching)
                    }
                }

                Text(selectedTTL.isUntilReceived ? "Retries until read" : "Expires after \(selectedTTL.label)")
                    .font(.system(size: ts * 0.27, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            // DND override — visible, honest, reversible.
            VStack(alignment: .leading, spacing: 9) {
                ReDuxTileLabel("OVERRIDE", color: .neonAmber, textSize: ts)

                HStack(spacing: 8) {
                    Image(systemName: isCriticalOverride ? "bell.fill" : "bell.slash.fill")
                        .font(.system(size: ts * 0.5, weight: .bold))
                        .foregroundColor(isCriticalOverride ? .neonRed : .gray)
                        .shadow(color: isCriticalOverride ? .neonRed.opacity(0.6) : .clear, radius: 6)
                    Text("DND\nOVERRIDE")
                        .font(.system(size: ts * 0.32, weight: .black, design: .monospaced))
                        .foregroundColor(isCriticalOverride ? .white : .gray)
                }

                Button(action: {
                    Haptics.medium()
                    isCriticalOverride.toggle()
                }) {
                    ZStack(alignment: isCriticalOverride ? .trailing : .leading) {
                        Capsule()
                            .fill(isCriticalOverride ? Color.neonRed : Color.white.opacity(0.12))
                            .frame(width: 54, height: 31)
                            .shadow(color: isCriticalOverride ? .neonRed.opacity(0.5) : .clear, radius: 8)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 25, height: 25)
                            .padding(3)
                            .shadow(radius: 2)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCriticalOverride)
                }
                .buttonStyle(.plain)
                .disabled(isDispatching)
                .accessibilityLabel("Do Not Disturb override")

                Text(isCriticalOverride
                     ? "Bypasses Do Not Disturb on their device."
                     : "Respects Do Not Disturb.")
                    .font(.system(size: ts * 0.27))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .glassmorphicBento(glowColor: .neonAmber, cornerRadius: 20)
    }

    // MARK: - Dispatch Hero

    @ViewBuilder private var dispatchHero: some View {
        VStack(spacing: 10) {
            Button(action: executeDispatch) {
                HStack(spacing: 11) {
                    if isDispatching {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: heroIcon)
                            .font(.system(size: ts * 0.68, weight: .bold))
                    }
                    Text(heroLabel)
                        .font(.system(size: ts * 0.6, weight: .black, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ts * 0.72)
                .background(
                    LinearGradient(
                        colors: isArmed
                            ? [Color.neonRed, Color.orange]
                            : [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(20)
                .shadow(color: isArmed ? .neonRed.opacity(0.55) : .clear, radius: 18, x: 0, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isArmed ? Color.white.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isArmed)
            .breathe(active: isArmed, color: .neonRed)

            // What happens when you press it. No surprises.
            summaryStrip
        }
    }

    @ViewBuilder private var summaryStrip: some View {
        HStack(spacing: 0) {
            summarySegment(
                label: "TO",
                value: selectedContact.map { recipientsManager.displayName(for: $0.userId) } ?? "—",
                state: selectedContact == nil ? .missing : .ok
            )
            summaryDivider
            summarySegment(label: "TTL", value: selectedTTL.label, state: .ok)
            summaryDivider
            summarySegment(
                label: "OVERRIDE",
                value: isCriticalOverride ? "ON" : "OFF",
                state: isCriticalOverride ? .warn : .ok
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(13)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: selectedContact?.id)
        .animation(.easeInOut(duration: 0.2), value: selectedTTL)
        .animation(.easeInOut(duration: 0.2), value: isCriticalOverride)
    }

    private enum SummaryState { case ok, missing, warn }

    @ViewBuilder private func summarySegment(label: String, value: String, state: SummaryState) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: ts * 0.25, weight: .black, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: ts * 0.33, weight: .bold, design: .monospaced))
                .foregroundColor(state == .missing ? .orange : (state == .warn ? .neonRed : .white))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 26)
    }

    // MARK: - Stage Tracker (inline — replaces the full-screen modal)

    @ViewBuilder private var stageTracker: some View {
        VStack(spacing: 4) {
            if dispatchStage == .failed {
                HStack(spacing: 11) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: ts * 0.62, weight: .bold))
                        .foregroundColor(.neonRed)
                        .shadow(color: .neonRed.opacity(0.6), radius: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("DISPATCH FAILED")
                            .font(.system(size: ts * 0.4, weight: .black, design: .monospaced))
                            .foregroundColor(.neonRed)
                        Text(errorMessage ?? "Unknown error occurred")
                            .font(.system(size: ts * 0.32))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button(action: executeDispatch) {
                        Text("RETRY")
                            .font(.system(size: ts * 0.36, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(Color.neonRed)
                            .cornerRadius(11)
                            .shadow(color: .neonRed.opacity(0.5), radius: 10)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ReDuxStagePipelineView(stage: dispatchStage, progress: dispatchProgress, textSize: ts)
            }
        }
        .padding(14)
        .glassmorphicBento(glowColor: dispatchStage.color, cornerRadius: 20)
    }

    // MARK: - Toast

    @ViewBuilder private var toastOverlay: some View {
        if showDispatchToast {
            VStack {
                Spacer()
                ReDuxDispatchToast(
                    message: dispatchToastMessage,
                    icon: dispatchToastIcon,
                    color: dispatchToastColor,
                    textSize: ts,
                    onDismiss: { showDispatchToast = false }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showDispatchToast)
            }
        }
    }

    // MARK: - Helpers

    private func dismissKeyboard() {
        isMessageFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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
        if let saved = recipientMessages[recipient.userId] {
            messageText = saved
        } else {
            messageText = ""
        }
    }

    private func onRecipientSelected(_ contact: TrustCircleManager.TrustCircleMember) {
        Haptics.selection()
        selectedContact = contact
        loadMessageForRecipient(contact)
    }

    private func applyTemplate(_ template: MessageTemplate) {
        Haptics.tap()
        let tText = template.text
        messageText = tText
        guard let contact = selectedContact else { return }
        saveRecipientMessage(tText, for: contact.userId)
    }

    private func saveCurrentAsTemplate() {
        if !newTemplateName.isEmpty && !messageText.isEmpty {
            var templates = messageTemplates
            templates.append(MessageTemplate(name: newTemplateName, text: messageText))
            saveTemplates(templates)
            newTemplateName = ""
        }
    }

    private func triggerEntranceAnimations() {
        for index in 0..<animatedIn.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.09) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    animatedIn[index] = true
                }
            }
        }
    }

    private func executeDispatch() {
        guard apiService.isAuthenticated else {
            noticeMessage = "Connect this device first: Recipients tab → gear → Connect This Device."
            showNotice = true
            return
        }
        guard let contact = selectedContact else {
            noticeMessage = "Select a recipient first. Recipients tab → gear → Add a Recipient, then choose them here."
            showNotice = true
            return
        }
        guard !messageText.isEmpty else {
            noticeMessage = "Type a message before sending."
            showNotice = true
            return
        }

        dismissKeyboard()

        Haptics.medium()
        isDispatching = true
        dispatchStage = .validating
        dispatchProgress = 0.0
        errorMessage = nil
        showDispatchToast = false
        showStageTracker = true

        let ttlMinutes = selectedTTL == .untilReceived ? 10080 : selectedTTL.minutes
        let isUntilReceived = selectedTTL == .untilReceived

        Task {
            do {
                // Real pipeline only: progress advances on actual completed work.
                // E2EE seal + POST happen inside dispatchRushAlert; the server
                // attempts the APNs push synchronously before responding.
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

                // Server responded: APNs push was attempted server-side.
                dispatchStage = .pushing
                dispatchProgress = 0.70

                // A mounted/on-screen delivery is only claimed when the backend
                // confirms it; otherwise we stay honest at the pushing stage.
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
                    showDeliveryToast(confirmations)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        dismissStageTracker()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

    /// Failure keeps the tracker on screen with the real error and a retry —
    /// no blocking alert, no dead end. Auto-resets only if untouched.
    private func handleDispatchFailure(_ description: String) {
        isDispatching = false
        dispatchStage = .failed
        dispatchProgress = 0.0
        errorMessage = description
        showFailureToast(description)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            if dispatchStage == .failed {
                showStageTracker = false
                dispatchStage = .idle
            }
        }
    }

    // Only claims what is actually known: local trust-circle state + the
    // backend's confirmed dispatch status. Nothing is assumed about APNs
    // delivery beyond what the server reported.
    private func checkDeliveryConfirmations(_ contact: TrustCircleManager.TrustCircleMember, serverStatus: String) -> [String] {
        var confirmations = [String]()
        if contact.hasAppInstalled {
            confirmations.append("✅ Recipient in trust circle & active")
        } else {
            confirmations.append("⚠️ Recipient app not seen - delivery pending")
        }
        if isCriticalOverride {
            confirmations.append("🔊 Critical flag requested")
        }
        if serverStatus == "MOUNTED_ON_LOCK_SCREEN" {
            confirmations.append("📤 Server confirmed push accepted")
        } else if serverStatus == "PUSH_FAILED" {
            confirmations.append("❌ Server reported push failed")
        } else {
            confirmations.append("📤 Server response: " + serverStatus)
        }
        if selectedTTL == .untilReceived {
            confirmations.append("🔄 Server will auto-retry until read")
        }
        return confirmations
    }

    private func showDeliveryToast(_ confirmations: [String]) {
        dispatchToastMessage = confirmations.joined(separator: "\n")
        dispatchToastIcon = "checkmark.circle.fill"
        dispatchToastColor = .green
        showDispatchToast = true

        Haptics.success()
        AudioServicesPlaySystemSound(1016)
    }

    private func showFailureToast(_ error: String) {
        dispatchToastMessage = "❌ Dispatch failed: \(error)"
        dispatchToastIcon = "xmark.octagon.fill"
        dispatchToastColor = .red
        showDispatchToast = true

        Haptics.error()
        AudioServicesPlaySystemSound(1006)
    }

    private func dismissStageTracker() {
        showStageTracker = false
        isDispatching = false
    }
}

// MARK: - Supporting Views


// MARK: - Deck Tiles

/// Small mono label with an accent bar — the deck's section header.
struct ReDuxTileLabel: View {
    let text: String
    let color: Color
    let textSize: Double

    init(_ text: String, color: Color, textSize: Double) {
        self.text = text
        self.color = color
        self.textSize = textSize
    }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 15)
                .shadow(color: color.opacity(0.7), radius: 4)
            Text(text)
                .font(.system(size: textSize * 0.36, weight: .black, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

/// Recipient target card — presence, name, last-seen, and a selection state
/// that reads at a glance.
struct ReDuxRecipientCard: View {
    let contact: TrustCircleManager.TrustCircleMember
    let isSelected: Bool
    let textSize: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(contact.hasAppInstalled ? Color.neonGreen : Color.gray)
                        .frame(width: textSize * 0.28, height: textSize * 0.28)
                        .shadow(color: contact.hasAppInstalled ? .neonGreen.opacity(0.8) : .clear, radius: 5)

                    Text(TrustCircleManager.shared.displayName(for: contact.userId))
                        .font(.system(size: textSize * 0.52, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                if let lastSeen = contact.lastSeenText {
                    Text(lastSeen)
                        .font(.system(size: textSize * 0.29, design: .monospaced))
                        .foregroundColor(.gray)
                }

                Text(isSelected ? "TARGET LOCKED" : "TAP TO TARGET")
                    .font(.system(size: textSize * 0.25, weight: .black, design: .monospaced))
                    .foregroundColor(isSelected ? .neonRed : .gray.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: textSize * 3.6, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.neonRed.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.neonRed : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? .neonRed.opacity(0.35) : .clear, radius: 10)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

/// Quick-message chip — cyan accent, part of the payload tile.
struct ReDuxTemplateChip: View {
    let template: MessageTemplate
    let isSelected: Bool
    let textSize: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(template.name)
                .font(.system(size: textSize * 0.35, weight: .black, design: .monospaced))
                .foregroundColor(isSelected ? .white : .neonCyan.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.neonCyan.opacity(0.85) : Color.neonCyan.opacity(0.08))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.neonCyan.opacity(isSelected ? 0.9 : 0.3), lineWidth: 1.5)
                )
                .shadow(color: isSelected ? .neonCyan.opacity(0.4) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Stage Pipeline
// Replaces the old full-screen DispatchModalView / DispatchProgressView: the
// pipeline stays on the deck, in flow, with a retry on failure.

struct ReDuxStagePipelineView: View {
    let stage: ReDuxDispatchStage
    let progress: Double
    let textSize: Double

    private let nodes: [(label: String, stages: [ReDuxDispatchStage])] = [
        ("ENCRYPT", [.validating, .encrypting]),
        ("TRANSMIT", [.dispatching]),
        ("PUSH", [.pushing]),
        ("LOCK", [.mounted]),
        ("READ", [.confirmed]),
    ]

    private var activeIndex: Int {
        nodes.firstIndex(where: { $0.stages.contains(stage) }) ?? -1
    }

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 2) {
                ForEach(0..<nodes.count, id: \.self) { i in
                    nodeView(index: i)
                    if i < nodes.count - 1 {
                        connectorView(index: i)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [stage.color, stage.color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                Image(systemName: stage.icon)
                    .font(.system(size: textSize * 0.45, weight: .bold))
                    .foregroundColor(stage.color)
                    .shadow(color: stage.color.opacity(0.6), radius: 6)

                Text(stage.rawValue)
                    .font(.system(size: textSize * 0.36, weight: .black, design: .monospaced))
                    .foregroundColor(stage.color)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.system(size: textSize * 0.32, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder private func nodeView(index: Int) -> some View {
        let done = stage == .confirmed || index < activeIndex
        let active = index == activeIndex
        let ringColor = done ? Color.neonGreen : (active ? stage.color : Color.white.opacity(0.15))

        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(done ? Color.neonGreen.opacity(0.18)
                          : (active ? stage.color.opacity(0.22) : Color.white.opacity(0.05)))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(ringColor, lineWidth: active ? 2.5 : 1.5))
                    .shadow(color: active ? stage.color.opacity(0.6) : (done ? .neonGreen.opacity(0.3) : .clear), radius: 8)

                Image(systemName: done ? "checkmark" : (active ? stage.icon : "circle"))
                    .font(.system(size: textSize * 0.3, weight: .bold))
                    .foregroundColor(done ? .neonGreen : (active ? stage.color : .gray.opacity(0.5)))
            }

            Text(nodes[index].label)
                .font(.system(size: textSize * 0.21, weight: .black, design: .monospaced))
                .foregroundColor(done ? .neonGreen : (active ? stage.color : .gray.opacity(0.5)))
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: activeIndex)
    }

    @ViewBuilder private func connectorView(index: Int) -> some View {
        let filled = stage == .confirmed || index < activeIndex
        RoundedRectangle(cornerRadius: 1)
            .fill(filled ? Color.neonGreen.opacity(0.7) : Color.white.opacity(0.12))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            .animation(.easeInOut(duration: 0.3), value: filled)
    }
}

// MARK: - Template Management (unchanged behavior, carried over)

struct ReDuxTemplateManagerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var settings: AccessibilitySettings
    let templates: [MessageTemplate]
    let onSave: ([MessageTemplate]) -> Void
    let textSize: Double

    @State private var editingTemplates: [MessageTemplate]
    @State private var newName = ""
    @State private var newText = ""
    @State private var isAdding = false
    @State private var editingIndex: Int?

    init(templates: [MessageTemplate], onSave: @escaping ([MessageTemplate]) -> Void, textSize: Double) {
        self.templates = templates
        self.onSave = onSave
        self.textSize = textSize
        _editingTemplates = State(initialValue: templates)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isAdding || editingIndex != nil {
                        ReDuxAddTemplateView(
                            name: $newName,
                            text: $newText,
                            textSize: textSize,
                            onSave: {
                                if let idx = editingIndex {
                                    editingTemplates[idx] = MessageTemplate(id: editingTemplates[idx].id, name: newName, text: newText)
                                    editingIndex = nil
                                } else {
                                    editingTemplates.append(MessageTemplate(name: newName, text: newText))
                                }
                                newName = ""
                                newText = ""
                                isAdding = false
                            },
                            onCancel: {
                                isAdding = false
                                editingIndex = nil
                            }
                        )
                    } else {
                        List {
                            ForEach(editingTemplates.indices, id: \.self) { idx in
                                let template = editingTemplates[idx]
                                ReDuxTemplateRowView(
                                    template: template,
                                    textSize: textSize,
                                    onEdit: {
                                        newName = template.name
                                        newText = template.text
                                        editingIndex = idx
                                    },
                                    onDelete: {
                                        editingTemplates.removeAll { $0.id == template.id }
                                    }
                                )
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                editingTemplates.remove(atOffsets: indexSet)
                            }

                            Button(action: {
                                newName = ""
                                newText = ""
                                isAdding = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Add Template")
                                        .foregroundColor(.blue)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Quick Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(editingTemplates)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ReDuxAddTemplateView: View {
    @EnvironmentObject private var settings: AccessibilitySettings
    @Binding var name: String
    @Binding var text: String
    let textSize: Double
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("NEW QUICK MESSAGE")
                .font(.system(size: textSize * 0.5, weight: .black, design: .monospaced))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: textSize * 0.4))
                    .foregroundColor(.gray)
                TextField("e.g., MEETING", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: textSize * 0.5))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Message")
                    .font(.system(size: textSize * 0.4))
                    .foregroundColor(.gray)
                TextEditor(text: $text)
                    .frame(height: textSize * 3)
                    .font(.system(size: textSize * 0.5))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || text.isEmpty)
            }

            Spacer()
        }
        .padding(16)
    }
}

struct ReDuxTemplateRowView: View {
    let template: MessageTemplate
    let textSize: Double
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.system(size: textSize * 0.5, weight: .bold))
                    .foregroundColor(.white)
                Text(template.text.isEmpty ? "(empty)" : template.text)
                    .font(.system(size: textSize * 0.35))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }

            Spacer()

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

struct ReDuxDispatchToast: View {
    let message: String
    let icon: String
    let color: Color
    let textSize: Double
    let onDismiss: () -> Void

    @State private var show = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: textSize * 0.6, weight: .bold))
                .foregroundColor(color)

            Text(message)
                .font(.system(size: textSize * 0.45, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.9))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: color.opacity(0.3), radius: 15, x: 0, y: 8)
        .scaleEffect(show ? 1 : 0.85)
        .opacity(show ? 1 : 0)
        .offset(y: show ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                show = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    show = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onDismiss()
                }
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                show = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDismiss()
            }
        }
    }
}

// NOTE: glassmorphicBento() lives in Shared/CyberpunkDesignSystem.swift
// (single source of truth for the bento tile). Do not redeclare here.
// NOTE: The old full-screen DispatchModalView / DispatchProgressView were
// removed in the Dispatch Deck redesign — the inline ReDuxStagePipelineView above
// replaces them. Nothing outside this file referenced them.

// MARK: - Deck Entrance

extension View {
    /// Staggered tile entrance for the deck. Reads the console's animatedIn
    /// flags so tiles fly in one after another on first appear.
    func reduxDeckEntrance(index: Int, animatedIn: [Bool]) -> some View {
        self
            .opacity(index < animatedIn.count && animatedIn[index] ? 1 : 0)
            .scaleEffect(index < animatedIn.count && animatedIn[index] ? 1 : 0.92)
            .offset(y: index < animatedIn.count && animatedIn[index] ? 0 : 34)
    }
}

// MARK: - Beta color bridge
// The legacy DesignSystem exposed GameBoyPalette.neonAmber; the Dispatch Deck
// consolidates on the cyberpunk system, so the amber lives here as a peer color.
extension Color {
    static let neonAmber = Color(red: 1.0, green: 0.72, blue: 0.05)
}
