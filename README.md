# SnappySnag SDK

SnappySnag is a visual bug reporting and AI auto-fix suggestion tool for Flutter applications. With a single shake or a tap of a button, developers and QA teams can capture screenshots, dump widget tree layouts, and get instant, detailed AI-powered code fix suggestions on their dashboard.

## Features

* 📸 **Prioritized Instant Screenshots**: Captured immediately on-press to freeze the screen state, even during fast page transitions.
* 🌳 **Widget Tree Dumper**: Automatically dumps the widget hierarchy (up to a depth of 10 levels) for precise widget mapping.
* 🤖 **AI Auto-Fix suggestions**: Generates human-focused technical guides and cursor-compatible agent prompts.
* 👥 **One-Build Role-Based Sharing**: Show internal tickets, duplicate warnings, and discussion threads to developers while keeping external clients on a clean, simple feedback flow in the exact same build.
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
    packageName: 'your.package.name',
    // Optional: Identify user/tester to automatically unlock developer tickets/chat for team members
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

By default, the floating capture button is displayed on all screens (`showTriggerButton: true`). You can customize this behavior:

* **Hide Globally by Default**:
  ```dart
  SnappySnag().initialize(
    apiKey: '...',
    packageName: '...',
    showTriggerButton: false, // Default is true. When false, trigger button won't show globally.
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

### 3. Build for TestFlight / Internal Testing

To compile your app with SnappySnag enabled, build with the `--dart-define` flag:

```bash
flutter build ipa --dart-define=ENABLE_SNAPPY_SNAG=true
flutter build appbundle --dart-define=ENABLE_SNAPPY_SNAG=true
```

### 4. Build for App Store / Google Play Store (Production)

To compile your app for production release, build normally. SnappySnag will automatically be disabled, will not render the overlay button, and will not register any shake listeners:

```bash
flutter build ipa
```


## Smart Role-Based Access & Multi-Layer Safety Guards

In team and client work, building separate app binaries (one for internal developers and one for external clients) is time-consuming and prone to human error. SnappySnag provides a comprehensive defense and access control system to **safely share a single build** between developers and clients without risking internal leakages.

### 1. One-Build Sharing: Role-Based Developer In-App Features
With `mode: SnappySnagMode.dev`, you can let your development team view **existing internal tickets, duplicate warnings, and discussion threads**, while ensuring clients and external testers only see a clean, distraction-free **feedback submission screen**.

Control access effortlessly from your **Web Dashboard** > **Project Settings** > **General & SDK**:
* 👥 **Allowed Only (Recommended)**:
  * **Team Members**: Owners and developers registered in your dashboard's "Team & Members" automatically get full access to internal tickets and chat threads when their `reporterEmail` matches.
  * **Additional Allowed Emails**: Seamlessly whitelist client leads or external QA testers by email address without touching your code or re-deploying.
  * **Unauthenticated / Unknown Testers**: Automatically skip internal tickets and transition directly to the feedback submission screen. Chat submissions are rejected with `403 Forbidden`.
* 🌐 **Everyone**: Displays developer tickets and chat to anyone running the dev-mode app.
* 🛑 **Disabled (Remote Kill-Switch)**: Instantly suppresses internal tickets and chat worldwide across all mobile instances.

### 2. Automatic Release Guard (`kReleaseMode`)
When you build your application in **Release Mode** (`flutter build ipa` / `flutter build appbundle`), SnappySnag automatically checks Flutter's `kReleaseMode`. Even if `mode: SnappySnagMode.dev` was inadvertently left configured in your source code, SnappySnag automatically falls back to `SnappySnagMode.user`, completely hiding developer tickets and comments.

> 💡 **Internal Dogfooding in Release Builds**: If you intentionally wish to test developer mode in a release-compiled build (e.g. TestFlight distribution to internal team members), explicitly set `forceDevInRelease: true`:
> ```dart
> SnappySnag().initialize(
>   apiKey: 'YOUR_KEY',
>   packageName: 'com.example.app',
>   mode: SnappySnagMode.dev,
>   forceDevInRelease: const bool.fromEnvironment('FORCE_DEV_CHAT', defaultValue: false),
> );
> ```

### 3. Client & Server Rate Limiting (Spam & Flood Protection)
Applies to both `user` and `dev` modes out of the box:
- **Client-Side**: The send button enforces a mandatory 3-second cooldown between successive submissions to prevent accidental or malicious double-taps.
- **Server-Side**: The backend API limits continuous messages to a maximum of 5 messages per minute per user/device. Exceeding requests automatically receive `429 Too Many Requests` with an in-app notice.
