# UrgentSee — Android Port Plan

Status: **PREP** (not started). iOS remains the lead platform; this document
freezes the contracts Android must honor so the two clients stay interoperable.

## What transfers for free

- **Backend is platform-agnostic.** All clients talk to the same Cloudflare
  Worker (`urgentsee-edge.pounds1.workers.dev`) REST API: device registration,
  public-key directory, `/v1/rush/alerts`, `/v1/rush/unsend`, APNs/FCM token
  sync to Edge KV. Android reuses these endpoints 1:1 — no server changes.
- **Product logic is documented in the iOS code.** TTL mapping (15m → "until
  read/heard/confirmed"), template model, per-recipient drafts, critical-flag
  semantics, receipt model — port the rules, not just the screens.

## Platform mapping (iOS → Android)

| iOS | Android |
|---|---|
| SwiftUI + 6 `DashboardSkin` themes | Kotlin + Jetpack Compose; skins become a `Skin` theme system (colors, type, motion) over one shared `DispatchViewModel` |
| `@AppStorage` (skin, drafts, settings) | DataStore (proto or preferences) |
| CryptoKit: Curve25519 key agreement + ChaChaPoly AEAD (`E2EEManager`) | Manual X25519 + ChaChaPoly via Conscrypt/BouncyCastle **or** Tink — MUST produce byte-identical wire format; generate interop test vectors from iOS first |
| Keychain (private key) | Android Keystore |
| APNs + `.criticalAlert` entitlement | FCM high-priority messages; "break through DND" via `NotificationChannel.setBypassDnd(true)` — **requires the user to grant Do Not Disturb access**, extra friction vs iOS; the honest explainer copy must be adapted |
| `UINotificationFeedbackGenerator` / `Haptics` | `VibratorManager` + `VibrationEffect` (keystroke ticks already designed throttled at 60ms — reuse the timing) |
| Live Activity / lock-screen push | FCM full-screen intent for critical alerts |
| TestFlight | Play Console internal testing track |

## Honest platform differences to design for

1. **DND bypass is not entitlement-based on Android.** iOS Critical Alerts are
   Apple-approved; Android needs `ACCESS_NOTIFICATION_POLICY` + user grant.
   Onboarding must ask clearly, explain why, and degrade honestly when denied.
2. **Background execution.** FCM high-priority is usually enough, but OEM
   battery optimizers (Samsung, Xiaomi) can delay delivery — document, and
   consider a "delivery health check" in settings.
3. **Crypto interop is the highest-risk item.** One wrong nonce encoding and
   iOS↔Android messages fail silently. Freeze the wire format and test with
   fixtures before any UI work.

## Phased execution

- **Phase 0 — Contract freeze.** Export API + crypto wire-format fixtures from
  iOS. No Android code until fixtures pass.
- **Phase 1 — Core.** API client, auth, trust circle (recipients), E2E encrypt/
  decrypt with interop tests, DataStore persistence.
- **Phase 2 — Push.** FCM integration, channels, DND-permission onboarding,
  full-screen intent, receipt/ack pipeline (`ReverseAckService` equivalent).
- **Phase 3 — Dispatch UI.** One Compose dispatch screen + the skin theme
  system. Start with OG + Vanilla; add the rest after parity.
- **Phase 4 — Settings/templates/history.** Templates CRUD, per-recipient
  drafts, TTL mapping, accessibility (TalkBack, font scaling).
- **Phase 5 — Parity testing.** Same matrix as iOS: auth states, offline,
  failure/retry, all TTLs, critical on/off, skin switching, reduced motion.
- **Phase 6 — Ship.** Play internal testing → production.

## Out of scope for the port

Rewriting the backend, changing the API contract, or "fixing" iOS behavior to
match Android quirks. iOS is the reference implementation.
