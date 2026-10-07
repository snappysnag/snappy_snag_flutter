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
