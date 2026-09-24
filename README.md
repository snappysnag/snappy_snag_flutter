# SnappySnag SDK

SnappySnag is a visual bug reporting and AI auto-fix suggestion tool for Flutter applications. With a single shake or a tap of a button, developers and QA teams can capture screenshots, dump widget tree layouts, and get instant, detailed AI-powered code fix suggestions on their dashboard.

## Features

* 📸 **Prioritized Instant Screenshots**: Captured immediately on-press to freeze the screen state, even during fast page transitions.
* 📍 **Multi-Point Pin Annotations**: Tap anywhere on the captured screen to drop numbered pins (1–5) and attach itemized feedback/bug details for each specific area.
* 🎨 **Clean & Annotated Screenshot Preservation**: Pin coordinates are stored as normalized vectors, keeping the original screenshot crystal clear without destructive image stamping.
* 🌳 **Widget Tree Dumper**: Automatically dumps the widget hierarchy (up to a depth of 10 levels) for precise widget mapping.
* 🤖 **AI Auto-Fix suggestions**: Generates human-focused technical guides and cursor-compatible agent prompts.
* 💾 **Offline Draft & Resilience**: Automatically saves drawing annotations, pins, and comments locally on connection failure or accidental dismissal. Seamlessly resume or discard drafts on the next capture without wasting user efforts.
* ⚡ **Pre-Validation Error Guard**: Instantly validates API key configuration and bundle identifiers before users spend time drawing or writing, preventing post-submit authentication surprises.
* 👥 **One-Build Role-Based Sharing**: Show internal tickets and duplicate warnings to developers while keeping external clients on a clean, simple feedback flow in the exact same build.
* 🛡️ **Package Name Lock**: Prevents unauthorized API requests by locking your API Key to your registered bundle identifier.
* 🚫 **Store Production Safe**: Easily disable the overlay button and sensor listeners completely in App Store/Google Play builds using the `enabled` configuration.

## Getting started

Add `snappy_snag` to your Flutter project's dependencies:

```bash
flutter pub add snappy_snag
```

## Usage

### 1. Initialize and Wrap MaterialApp

Configure the SDK in your `main.dart`. We highly recommend using `bool.fromEnvironment` to enable SnappySnag only during internal testing (e.g., TestFlight or Google Play Internal Testing) and disabling it completely for App Store/Google Play production builds.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:snappy_snag/snappy_snag.dart';

void main() {
  // 1. Initialize the SDK
  SnappySnag().initialize(
    apiKey: 'snag_live_your_api_key_here',
    // packageName: 'your.package.name', // Optional: Lock API key usage to your app's bundle ID
    // Optional: Identify user/tester to automatically unlock developer tickets for team members
    user: const SnappySnagUser(
      email: 'developer@example.com',
    ),
    // Safely enable SnappySnag only when ENABLE_SNAPPY_SNAG=true is passed at build time.
    // It will automatically bypass overlay rendering and sensor listeners in production builds.
    enabled: const bool.fromEnvironment('ENABLE_SNAPPY_SNAG', defaultValue: false) || kDebugMode,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 2. Simply pass SnappySnag's defaultNavigatorKey
      navigatorKey: SnappySnag.defaultNavigatorKey,
      // 3. Wrap your screen with SnappySnagOverlay in builder
      builder: (context, child) => SnappySnagOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const MyHomePage(),
    );
  }
}
```

> 💡 **Tip: Dynamic User Info**: If users log in after app startup, call `SnappySnag().setUser(SnappySnagUser(id: user.id, email: user.email))` anywhere in your authentication flow. Call `SnappySnag().clearUser()` on logout.

### 2. Trigger Button Visibility & Control

By default, the floating capture button is **hidden across all modes (`showTriggerButton: false`)** to keep your application's UI completely undisturbed.

You can display or control the trigger button as needed:

* **Enable Floating Button for Rapid Testing**:
  Pass `showTriggerButton: true` in `initialize()` to display the floating overlay button immediately:
  ```dart
  SnappySnag().initialize(
    apiKey: '...',
    showTriggerButton: true, // Display floating button immediately
  );
  ```

* **Hide on Specific Screens (Declarative)**:
  Wrap any screen (e.g. camera, video player, payment screen) with `SnappySnagHideButton`:
  ```dart
  class CameraScreen extends StatelessWidget {
    @override
    Widget build(BuildContext context) {
      return SnappySnagHideButton(
        child: Scaffold(
          body: YourCameraView(),
        ),
      );
    }
  }
  ```

* **Programmatic Visibility Control**:
  ```dart
  SnappySnag().showTriggerButton();
  SnappySnag().hideTriggerButton();
  SnappySnag().setTriggerButtonVisibility(true);
  ```

### 3. Widget Tree Hierarchy & Privacy Opt-Out (`enableWidgetTree`)

By default (`enableWidgetTree: true`), SnappySnag extracts the Flutter UI hierarchy (up to 10 levels deep) to give Gemini AI complete context on nested layouts and styling:

* **Automatic On-Device PII Redaction**:
  * Text fields, passwords, and user input widgets are automatically redacted before sending.
  * Long text labels (> 15 characters) are truncated.
* **Complete Hierarchy Opt-Out for Strict Compliance**:
  If your application operates under strict security or regulatory compliance (e.g. healthcare, banking) where sending UI component structures is restricted, you can completely opt out:
  ```dart
  SnappySnag().initialize(
    apiKey: '...',
    enableWidgetTree: false, // Disables widget tree traversal completely
  );
  ```
  > 💡 When `enableWidgetTree: false`, SnappySnag skips tree traversal entirely and relies strictly on screenshot visual cues and user annotations for AI analysis. The dashboard will automatically reflect this as `Visual Screenshot Analysis (UI Tree Excluded)`.

### 4. Multi-Point Pin Drop & Itemized Feedback

When users capture a screenshot, they can annotate specific UI elements with numbered pins (1–5) and write separate notes for each pin:
* **Drop Pins**: Tap anywhere on the captured screenshot to place a pin marker.
* **Itemized Notes**: Add targeted feedback or repro notes per pin, helping developers address multiple UI issues in a single report without confusing clutter.
* **Non-Destructive Vectors**: Pin coordinates (`x`, `y` percentages) are stored separately from the image. The original screenshot remains intact and clean on your dashboard.

### 5. Launch Feedback Mode Manually (e.g. from Settings or In-App Menu)

When the floating button is hidden (via `showTriggerButton: false` or `SnappySnagHideButton`), or if you prefer triggering feedback through your own custom UI (such as a "Report Bug" button in a Settings or Help drawer), call `SnappySnag.startFeedbackMode`:

```dart
ListTile(
  leading: const Icon(Icons.feedback_outlined),
  title: const Text('Report a Bug / Feedback'),
  onTap: () {
    // Starts Feedback Mode with a guidance banner and temporary capture trigger
    SnappySnag.startFeedbackMode(context: context);
  },
)
```

> 💡 When invoked, it displays a guided prompt modal and temporarily reveals the capture button, allowing the user to navigate anywhere in the app to capture and highlight the issue.

### 6. Build for TestFlight / Internal Testing

To compile your app with SnappySnag enabled, build with the `--dart-define` flag:

```bash
flutter build ipa --dart-define=ENABLE_SNAPPY_SNAG=true
flutter build appbundle --dart-define=ENABLE_SNAPPY_SNAG=true
```

### 7. Build for App Store / Google Play Store (Production)

To compile your app for production release, build normally. SnappySnag will automatically be disabled, will not render the overlay button, and will not register any shake listeners:

```bash
flutter build ipa
```


## Smart Role-Based Access & Multi-Layer Safety Guards

In team and client work, building separate app binaries (one for internal developers and one for external clients) is time-consuming and prone to human error. SnappySnag provides a comprehensive defense and access control system to **safely share a single build** between developers and clients without risking internal leakages.

### 1. One-Build Sharing: Role-Based Developer In-App Features
With `mode: SnappySnagMode.dev`, you can let your development team view **existing internal tickets and duplicate warnings**, while ensuring clients and external testers only see a clean, distraction-free **feedback submission screen**.

> 🔒 **Default Safety Note**: Newly created projects default to **Disabled** for developer tickets. You can switch this to **Allowed Only** or **Everyone** anytime in your dashboard. Furthermore, if the SDK is running with `mode: SnappySnagMode.user`, developer tickets are **always strictly hidden**, irrespective of dashboard settings.

Control access effortlessly from your **Web Dashboard** > **Project Settings** > **General & SDK**:
* 🛑 **Disabled (Default)**: Suppresses developer tickets completely across all client devices.
* 👥 **Allowed Only (Recommended for Teams)**:
  * **Team Members**: Owners and developers registered in your dashboard's "Team & Members" automatically get full access to internal tickets when their `reporterEmail` matches.
  * **Additional Allowed Emails**: Seamlessly whitelist client leads or external QA testers by email address without touching your code or re-deploying.
  * **Unauthenticated / Unknown Testers**: Automatically skip internal tickets and transition directly to the feedback submission screen.
* 🌐 **Everyone**: Displays developer tickets to anyone running the dev-mode app.

### 2. Automatic Release Guard (`kReleaseMode`)
When you build your application in **Release Mode** (`flutter build ipa` / `flutter build appbundle`), SnappySnag automatically checks Flutter's `kReleaseMode`. Even if `mode: SnappySnagMode.dev` was inadvertently left configured in your source code, SnappySnag automatically falls back to `SnappySnagMode.user`, completely hiding developer tickets.

> 💡 **Internal Dogfooding in Release Builds**: If you intentionally wish to test developer mode in a release-compiled build (e.g. TestFlight distribution to internal team members), explicitly set `forceDevInRelease: true`:
> ```dart
> SnappySnag().initialize(
>   apiKey: 'YOUR_KEY',
>   packageName: 'com.example.app',
>   mode: SnappySnagMode.dev,
>   forceDevInRelease: const bool.fromEnvironment('FORCE_DEV_MODE', defaultValue: false),
> );
> ```

### 3. Client & Server Rate Limiting (Spam & Flood Protection)
Applies to both `user` and `dev` modes out of the box:
- **Client-Side**: The send button enforces a mandatory 3-second cooldown between successive submissions to prevent accidental or malicious double-taps.
- **Server-Side**: The backend API limits continuous messages to a maximum of 5 messages per minute per user/device. Exceeding requests automatically receive `429 Too Many Requests` with an in-app notice.

### 4. Zero-Friction Pre-Validation & Offline Draft Protection
- **Instant Pre-Validation**: When the capture button is triggered, SnappySnag performs a lightweight authorization check in the background. If an invalid API key or package name mismatch (`401`/`403`) occurs, it immediately halts and alerts you without letting the user waste time annotating or typing a memo.
- **On-Device Offline Draft (Zero-Loss Resilience)**:
  - If a feedback submission fails due to an unstable internet connection or if the user cancels with unsaved edits, SnappySnag offers to save the current progress as a draft.
  - **Privacy & Storage Safe**: Drafts are stored strictly on the device's local sandbox (`SharedPreferences`). No draft data is sent to external servers until explicitly submitted. Only 1 active draft is retained, ensuring zero unnecessary storage overhead.
  - On the next capture attempt, users are prompted to either **Resume Draft** or **Discard & Start New Capture**.

