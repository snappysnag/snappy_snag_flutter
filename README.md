# SnappySnag SDK

SnappySnag is a visual bug reporting and AI auto-fix suggestion tool for Flutter applications. With a single shake or a tap of a button, developers and QA teams can capture screenshots, dump widget tree layouts, and get instant, detailed AI-powered code fix suggestions on their dashboard.

## Features

* 📸 **Prioritized Instant Screenshots**: Captured immediately on-press to freeze the screen state, even during fast page transitions.
* 🌳 **Widget Tree Dumper**: Automatically dumps the widget hierarchy (up to a depth of 10 levels) for precise widget mapping.
* 🤖 **AI Auto-Fix suggestions**: Generates human-focused technical guides and cursor-compatible agent prompts.
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

// 1. Define a global NavigatorKey to access BuildContext from anywhere
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // 2. Initialize the SDK
  SnappySnag().initialize(
    apiKey: 'snag_live_your_api_key_here',
    packageName: 'your.package.name',
    navigatorKey: navigatorKey,
    // Safely enable SnappySnag only when ENABLE_SNAPPY_SNAG=true is passed at build time.
    // It will automatically bypass overlay rendering and sensor listeners in production builds.
    enabled: const bool.fromEnvironment('ENABLE_SNAPPY_SNAG', defaultValue: false) || kDebugMode,
  );

  runApp(
    // 3. Wrap your root widget with SnappySnagOverlay
    const SnappySnagOverlay(
      showTriggerButton: true, // Set to false if you only want shake detection
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      navigatorKey: navigatorKey, // Ensure the NavigatorKey is attached!
      home: const HomeScreen(),
    );
  }
}
```

### 2. Build for TestFlight / Internal Testing

To compile your app with SnappySnag enabled, build with the `--dart-define` flag:

```bash
flutter build ipa --dart-define=ENABLE_SNAPPY_SNAG=true
flutter build appbundle --dart-define=ENABLE_SNAPPY_SNAG=true
```

### 3. Build for App Store / Google Play Store (Production)

To compile your app for production release, build normally. SnappySnag will automatically be disabled, will not render the overlay button, and will not register any shake listeners:

```bash
flutter build ipa
```
