import 'package:flutter/material.dart';
import 'package:snappy_snag/snappy_snag.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SnappySnag SDK in Sandbox / Demo Mode
  // No server configuration or API key required to test locally!
  SnappySnag().initialize(
    apiKey: 'demo', // Use 'demo' for instant local testing without an account
    showTriggerButton: true, // Show the floating SnappySnag trigger button
    enableLogging: true,
    user: const SnappySnagUser(
      id: 'demo_user_1',
      name: 'Flutter Explorer',
      email: 'demo@example.com',
    ),
  );

  runApp(const SnappySnagShowroomApp());
}

class SnappySnagShowroomApp extends StatelessWidget {
  const SnappySnagShowroomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnappySnag Demo Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      // Pass SnappySnag default navigator key
      navigatorKey: SnappySnag.defaultNavigatorKey,
      // Wrap your app with SnappySnagOverlay
      builder: (context, child) => SnappySnagOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const ShowroomHomePage(),
    );
  }
}

class ShowroomHomePage extends StatefulWidget {
  const ShowroomHomePage({super.key});

  @override
  State<ShowroomHomePage> createState() => _ShowroomHomePageState();
}

class _ShowroomHomePageState extends State<ShowroomHomePage> {
  int _counter = 0;
  bool _toggleSwitch = true;
  double _sliderValue = 40.0;
  final TextEditingController _feedbackInput = TextEditingController(
    text: 'Example issue: The checkout button has incorrect padding.',
  );

  @override
  void dispose() {
    _feedbackInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF818CF8), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'SnappySnag Playground',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Launch Feedback Mode',
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => SnappySnag.startFeedbackMode(context: context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner: Demo Mode Announcement
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF22C55E)),
                        ),
                        child: const Text(
                          'DEMO MODE ACTIVE',
                          style: TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.touch_app_outlined, color: Colors.white70, size: 18),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Account or Server Required!',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. Tap the floating lightning icon on the bottom right (or the button below).\n'
                    '2. Tap anywhere on this screen to drop a Pin with a note.\n'
                    '3. Tap "Send" — you will see the full widget tree and pin payload in your debug console.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Try Feedback Capture Now'),
                    onPressed: () {
                      SnappySnag.startFeedbackMode(context: context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Sample Interactive UI Components',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),

            // Card 1: Counter & Buttons
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Interactive Counter', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Current Value: $_counter', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove),
                          onPressed: () => setState(() => _counter--),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          icon: const Icon(Icons.add),
                          onPressed: () => setState(() => _counter++),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Card 2: Switch & Slider
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Feature Flag'),
                      subtitle: const Text('Simulates dynamic app state', style: TextStyle(fontSize: 12)),
                      value: _toggleSwitch,
                      onChanged: (val) => setState(() => _toggleSwitch = val),
                    ),
                    const Divider(color: Colors.white12),
                    Row(
                      children: [
                        const Text('Slider: ', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Slider(
                            value: _sliderValue,
                            min: 0,
                            max: 100,
                            onChanged: (val) => setState(() => _sliderValue = val),
                          ),
                        ),
                        Text('${_sliderValue.toInt()}%', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Card 3: Sample Text Input Form
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sample Input Field', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _feedbackInput,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        hintText: 'Enter some text to test...',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Footer note
            Center(
              child: Text(
                'Visit https://snappysnag.com to sync issues with GitHub',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
