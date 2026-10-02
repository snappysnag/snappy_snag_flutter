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
