import 'package:flutter/material.dart';
import 'package:snappy_snag/snappy_snag.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SnappySnag SDK
  SnappySnag().initialize(
    // Replace with your project API Key from https://snappysnag.com
    apiKey: 'snag_live_sample_api_key',
    // Enable the floating trigger button for demonstration
    showTriggerButton: true,
    user: const SnappySnagUser(
      email: 'tester@example.com',
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnappySnag Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Pass SnappySnag default navigator key
      navigatorKey: SnappySnag.defaultNavigatorKey,
      // Wrap your app with SnappySnagOverlay
      builder: (context, child) => SnappySnagOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SnappySnag Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.bug_report_outlined,
              size: 64,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 16),
            const Text(
              'Shake your device or tap the floating button\nto report bugs and visual feedback!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Text(
              'Counter: $_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Manually Launch Feedback Mode'),
              onPressed: () {
                SnappySnag.startFeedbackMode(context: context);
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
