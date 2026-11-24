## 1.2.2

* **Breadcrumb Auto-Reset on Successful Submission**:
  * Automatically flushes and resets the breadcrumb history buffer (`SnappySnag.clearBreadcrumbs()`) when feedback is successfully submitted.
  * Ensures that subsequent bug reports start with a clean slate, preventing past user journeys from cluttering future reports.
  * In case of network errors or failed submissions, breadcrumb logs are preserved so retries retain full diagnostic history.
* **Static Analysis & Flutter SDK Pre-release Compatibility**:
  * Added `deprecated_member_use` suppression for `package:flutter/material.dart` under future Flutter pre-release SDK analysis environments (Pana 0.23.19+ / Flutter 3.50+).
  * Guarantees 100% static analysis score on pub.dev without breaking backward compatibility for Flutter Stable channels.

## 1.2.1

* **Documentation & Developer Onboarding Refresh**:
  * Added visual showcase banner and direct link to browser-based interactive demo (`https://snappysnag.com/demo`).
  * Added 10-second passwordless sign-up badges and clear setup instructions for instant API key retrieval.
  * Enhanced local Sandbox (`apiKey: 'demo'`) debug console output with direct guidance to unlock Gemini AI code fix suggestions, MCP server integration for Cursor & Claude Code, and GitHub Issue sync.
  * Updated package description and example comments highlighting modern AI coding workflows.

## 1.2.0

* **Breadcrumbs & Screen Navigation Tracking (`SnappySnagNavigatorObserver`, `SnappySnagBreadcrumb`)**:
  * Added automatic screen transition tracking (`didPush`, `didPop`, `didReplace`, `didRemove`) leading up to a bug report.
  * Developers can simply add `SnappySnagNavigatorObserver()` to `MaterialApp(navigatorObservers: [...])` or `GoRouter` to effortlessly collect user reproduction journeys.
  * **Zero Breaking Change**: Opt-in design ensures apps that do not add `SnappySnagNavigatorObserver` continue to function normally without any errors or configuration changes.
  * **Memory-Safe Ring Buffer**: Retains up to 25 recent events in memory, automatically evicting older actions to guarantee zero performance or memory footprint overhead.
  * **Custom Action Logging**: Added `SnappySnag.addBreadcrumb(category: ..., message: ..., data: ...)` and `SnappySnag.clearBreadcrumbs()` for logging key business actions and network responses.
  * **Demo / Sandbox Mode Output**: Recorded breadcrumbs are clearly printed in the debug console during local evaluation.

## 1.1.1

* **Security Architecture Hardening (Strict Write-Only Publishable Key Model)**:
  * Enforced a strict **Write-Only** data flow for client API keys. Removed legacy in-app ticket fetching (`ExistingPinItem`, `ExistingSectionItem`), duplicate warning modals, and 4-digit passcode verification flows so that internal project feedback can never be queried or read from client devices, even if an API key is extracted via reverse engineering.
  * Streamlined pre-validation checks to strictly verify API key status, bundle identifier locks, and monthly quota availability with minimal payload overhead.
* **Localization & Footprint Cleanup (`SnappySnagLocalization`)**:
  * Removed 17 deprecated localization properties related to legacy in-app ticket lists and passcode dialogs, reducing SDK memory footprint and simplifying custom dictionary overrides.

## 1.1.0

* **Internationalization & Localization (`SnappySnagLocalization`)**:
  * Added first-class localization support out of the box with built-in English (`en`) and Japanese (`ja`) dictionaries.
  * **Automatic Locale Resolution**: Automatically adapts UI copy to the app's current locale, with explicit override support via `locale: const Locale('ja')`.
  * **Custom Dictionaries & Tone Tuning (`copyWith`)**: Developers can easily customize or rebrand individual labels (e.g. `send`, `pinCommentHint`, `statusSuccess`) without replacing the whole dictionary:
    ```dart
    SnappySnag().initialize(
      apiKey: '...',
      localization: SnappySnagLocalization.ja().copyWith(
        send: 'フィードバック送信！',
        pinCommentTitle: '気になるポイント',
      ),
    );
    ```
  * **Dynamic Language Switching**: Dynamically update language at runtime using `SnappySnag().setLocale(...)` or `SnappySnag().setLocalization(...)`.
* **Full-Screen Sending Overlay & Tap Block**:
  * Enhanced submission UX with a dedicated semi-transparent modal overlay and card indicator displaying localized sending status (`sending: '送信中...'` / `'Sending...'`).
  * Blocks touch interactions across the entire screen during feedback uploads to prevent accidental re-submissions, multi-taps, or misplaced annotations.
* **Foremost Floating Toast Notifications**:
  * Decoupled notification toasts from host app's `ScaffoldMessenger`, rendering them directly in `SnappySnagOverlay`'s root stack.
  * Toasts reliably float above all drawing canvases, modals, dialogs, and floating trigger buttons at standard bottom margin (`16.0 + safeBottom`).
  * Smooth fade-in/fade-out animations with `IgnorePointer` passthrough when dismissed.

## 1.0.0 - Official Stable Release 🎉

* **Comprehensive Theme Customization (`SnappySnagTheme`)**:
  * Seamlessly match SnappySnag's feedback UI to your host app's brand aesthetic.
  * **Brand Accents**: Customize `primaryColor` (Send button, active tools, accent highlights) and `pinColor` (marker badge color).
  * **Light & Dark Mode**: Support `ThemeMode.dark`, `ThemeMode.light`, and `ThemeMode.system` (auto-adapting to system brightness).
  * **Border Radius**: Fine-tune `borderRadius` for modal cards and floating toolbars.
  * **Zero-Breaking Backwards Compatibility**: Defaults to SnappySnag's signature dark aesthetic (`#F59E0B` amber & `#F95738` coral red).
  * Configurable via `SnappySnag().initialize(theme: SnappySnagTheme(...))`.

## 0.0.4

* **Tactile Haptic Feedback**:
  * Added crisp tactile haptic feedback for key user interactions:
    * Dropping new pins (`HapticFeedback.mediumImpact()`)
    * Dragging pins & switching tools (`HapticFeedback.selectionClick()`)
    * Deleting pins & submitting feedback (`HapticFeedback.lightImpact()`)
    * Capturing screenshot freeze (`HapticFeedback.mediumImpact()`)
  * Configurable via `SnappySnag().initialize(enableHaptics: true/false)` (defaults to `true`).

## 0.0.3

* **Zero-Friction Sandbox / Demo Mode**:
  * Developers can now test SnappySnag instantly using `apiKey: 'demo'` without creating an account or registering a project on the web dashboard.
  * Local screen capture, multi-pin drop annotations, and drawing tools operate seamlessly in offline/demo mode.
  * Feedback submissions in demo mode dump the full widget tree and pin payload directly into the debug console, complete with an onboarding guide to connect to GitHub Issues.
* **Interactive Showroom Example**:
  * Overhauled `example/lib/main.dart` with interactive controls (sliders, forms, counters) to easily test pin annotations and bug reporting out of the box (`cd example && flutter run`).

## 0.0.2

* Supported `sensors_plus` v7.x while maintaining backward compatibility with v6.x (`>=6.0.0 <8.0.0`).

## 0.0.1

* **Initial release of SnappySnag Flutter SDK**:
  * **Instant Screen Capture**: High-speed screenshot capture via Shake gesture or floating trigger button.
  * **Multi-Point Pin Annotations**: Tap anywhere on the captured screen to drop numbered pins (1–5) with targeted repro notes.
  * **Non-Destructive Vectors**: Clean vector coordinates preservation without destructive watermark stamping.
  * **Widget Tree Hierarchy Dumper**: Traverses up to 10 levels of widget tree layout with automatic PII redaction (opt-out available via `enableWidgetTree`).
  * **Zero-Loss Offline Drafts**: Automatically saves unsaved annotations and notes locally on connectivity drops or dismissal.
  * **Smart Role-Based Sharing & Release Safety**: Seamlessly switch between user and developer feedback flows in a single build with `kReleaseMode` protection and 4-digit Dev Features Passcode.
  * **Client & Server Rate Limiting**: Cooldown and anti-spam protection against accidental multi-taps and flood submissions.
  * **Clean Console Output**: Console logging muted by default (`enableLogging: false`) to avoid cluttering host app logs during development.
