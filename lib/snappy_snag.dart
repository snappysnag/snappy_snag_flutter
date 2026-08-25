import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'src/browser_info_helper.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Main class for SnappySnag SDK configuration.
class SnappySnag {
  static final SnappySnag _instance = SnappySnag._internal();
  factory SnappySnag() => _instance;
  SnappySnag._internal();

  String? _apiKey;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _reporterUserId;
  String? _reporterEmail;
  String? _packageName;
  Map<String, dynamic>? _customMetadata;
  String _supabaseUrl =
      'https://apwesndoqpdlgwcylkzj.supabase.co'; // デフォルトは本番環境

  // 有効無効の状態管理フラグを追加
  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;
  String get supabaseUrl => _supabaseUrl;

  /// GlobalKey for accessing top-level Navigator context.
  GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// Initialize the SnappySnag SDK with a Project/API Key, Package Name, and optional NavigatorKey.
  void initialize({
    required String apiKey,
    required String packageName,
    GlobalKey<NavigatorState>? navigatorKey,
    String? reporterUserId,
    String? reporterEmail,
    Map<String, dynamic>? customMetadata,
    bool enabled = true,
    String? supabaseUrl,
  }) {
    _isEnabled = enabled;
    if (!_isEnabled) {
      debugPrint('🚀 SnappySnag: SDK is disabled by configuration.');
      return;
    }
    _apiKey = apiKey;
    _packageName = packageName.trim();
    _navigatorKey = navigatorKey;
    _reporterUserId = reporterUserId;
    _reporterEmail = reporterEmail;
    _customMetadata = customMetadata;
    if (supabaseUrl != null && supabaseUrl.trim().isNotEmpty) {
      _supabaseUrl = supabaseUrl.trim();
    }

    if (_apiKey == null || _apiKey!.trim().isEmpty) {
      debugPrint('⚠️ SnappySnag Warning: apiKey is empty or not configured.');
    }
    if (_packageName == null || _packageName!.isEmpty) {
      debugPrint(
        '⚠️ SnappySnag Warning: packageName is empty or not configured.',
      );
    }
    debugPrint('🚀 SnappySnag initialized.');
  }

  /// ユーザー情報を後から動的に更新するためのメソッド
  void setReporterInfo({String? userId, String? email}) {
    _reporterUserId = userId;
    _reporterEmail = email;
    debugPrint(
      '👤 SnappySnag: Reporter info updated (ID: $userId, Email: $email)',
    );
  }
}

/// Overlay Widget that wraps your App to capture screenshots and feedback memos.
class SnappySnagOverlay extends StatefulWidget {
  final Widget child;
  final bool showTriggerButton;

  const SnappySnagOverlay({
    super.key,
    required this.child,
    this.showTriggerButton = true,
  });

  @override
  State<SnappySnagOverlay> createState() => _SnappySnagOverlayState();
}

enum _SnappyOverlayMode {
  none,
  loading,
  duplicateWarning,
  commentsThread,
  drawing,
}

class _SnappySnagOverlayState extends State<SnappySnagOverlay> {
  final ScreenshotController _screenshotController = ScreenshotController();
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  bool _isCapturing = false;
  Uint8List? _capturedImageForFreeze;
  _SnappyOverlayMode _overlayMode = _SnappyOverlayMode.none;
  List<dynamic> _currentDuplicates = [];
  Completer<bool>? _duplicateWarningCompleter;

  // コメントスレッド用ステート
  String _commentsFeedbackId = '';
  String _commentsBugTitle = '';
  List<dynamic> _commentsList = [];
  bool _commentsLoading = false;
  bool _isSendingComment = false;
  final TextEditingController _commentTextController = TextEditingController();
  bool _isFeedbackDialogOpen = false;

  // お絵描きキャンバス用ステート
  Uint8List? _drawingImageBytes;
  Map<String, dynamic> _drawingWidgetTree = {};
  String _drawingScreenClassName = '';
  String _drawingScreenSignature = '';
  List<DrawingPoint> _drawingPoints = [];
  bool _isRedPen = true;
  bool _isSendingFeedback = false;
  bool _isMemoOpen = false;
  final TextEditingController _feedbackMemoController = TextEditingController();
  final ScreenshotController _canvasScreenshotController = ScreenshotController();
  Completer<void>? _drawingCompleter;
  double? _drawingAspectRatio;

  DateTime? _lastShakeTime;

  @override
  void initState() {
    super.initState();
    _initShakeDetection();
  }

  void _initShakeDetection() {
    // SDKが無効の場合はセンサー登録をスキップしてリソースを節約する
    if (!SnappySnag().isEnabled) return;

    // Webやデスクトップ（macOS/Windows/Linux）などの非モバイルプラットフォームではシェイク検知を無効化
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!isMobile) return;

    // しきい値（Gフォース）。一般的なシェイクの強さ
    const double shakeThreshold = 12.0;

    _accelerometerSubscription = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        if (_isCapturing) return;

        // 加速度ベクトル長（G-force）を算出
        final double gForce = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        if (gForce > shakeThreshold) {
          final now = DateTime.now();
          // チャタリング防止（前回の検知から1秒以上経過している場合のみトリガー）
          if (_lastShakeTime == null ||
              now.difference(_lastShakeTime!) > const Duration(seconds: 1)) {
            _lastShakeTime = now;
            _triggerCapture();
          }
        }
      },
      onError: (error) {
        debugPrint('⚠️ SnappySnag Accelerometer Error: $error');
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // パッケージロック制限（locked / package / archived / free plan）の判定を最優先で行う
    String instruction = 'Please verify your SDK configuration.';
    final msgLower = message.toLowerCase();
    if (msgLower.contains('locked') ||
        msgLower.contains('package') ||
        msgLower.contains('archived') ||
        msgLower.contains('free plan')) {
      instruction =
          'Please verify your app\'s package name (Bundle ID) or check if your project is archived under the Free plan in the dashboard.';
    } else if (msgLower.contains('api key')) {
      instruction = 'Please verify your API key in the SnappySnag dashboard.';
    }

    showDialog(
      context: targetContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c1e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Configuration Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'SnappySnag initialization failed: $message.\n\n$instruction',
          style: const TextStyle(
            color: Color(0xFFa1a1aa),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Color(0xFFf59e0b),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerCapture() async {
    final apiKey = SnappySnag()._apiKey;
    final packageName = SnappySnag()._packageName;

    if (apiKey == null ||
        apiKey.trim().isEmpty ||
        packageName == null ||
        packageName.trim().isEmpty) {
      _showErrorDialog(
        'SnappySnag is not properly configured. Please check that apiKey and packageName are set during initialization.',
      );
      return;
    }

    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // === 【超高速先行キャプチャ】画面遷移に備え、ボタンタップしたその瞬間のデータを即座にフリーズ ===
    final Map<String, dynamic> widgetTree = WidgetTreeDumper.dump(
      // ignore: use_build_context_synchronously
      targetContext,
    );
    final String screenClassName = WidgetTreeDumper.findScreenName(
      // ignore: use_build_context_synchronously
      targetContext,
    );
    final String screenSignature = WidgetTreeDumper.findScreenSignature(
      // ignore: use_build_context_synchronously
      targetContext,
      screenClassName,
    );
    debugPrint('🎬 SnappySnag: Captured Screen ID: $screenClassName, Signature: $screenSignature');

    // 即座にスクリーンショットを撮影 (ディレイなしで押した瞬間をキャプチャ)
    final Uint8List? imageBytes = await _screenshotController.capture();

    // 撮影完了後に、ボタンを隠すためのState変更とローディングオーバーレイの表示へ移行
    if (mounted) {
      setState(() {
        _isCapturing = true;
        _capturedImageForFreeze = imageBytes;
      });
    }
    await Future.delayed(const Duration(milliseconds: 150));
    _showLoadingOverlay();

    if (imageBytes != null && mounted) {
      try {
        final duplicates = await _fetchExistingFeedbacks(screenClassName, screenSignature);
        _hideLoadingOverlay();
        if (!mounted) return;

        if (duplicates.isNotEmpty) {
          final bool shouldReportNew = await _showDuplicateWarningDialog(
            duplicates: duplicates,
            imageBytes: imageBytes,
            widgetTree: widgetTree,
            screenClassName: screenClassName,
          );
          if (shouldReportNew && mounted) {
            setState(() {
              _isCapturing = false;
              _capturedImageForFreeze = null;
              _isFeedbackDialogOpen = true;
            });
            try {
              await _startDrawingFlow(
                imageBytes,
                widgetTree,
                screenClassName: screenClassName,
                screenSignature: screenSignature,
              );
            } finally {
              if (mounted) {
                setState(() => _isFeedbackDialogOpen = false);
              }
            }
          }
        } else {
          setState(() {
            _isCapturing = false;
            _capturedImageForFreeze = null;
            _isFeedbackDialogOpen = true;
          });
          try {
            await _startDrawingFlow(
              imageBytes,
              widgetTree,
              screenClassName: screenClassName,
              screenSignature: screenSignature,
            );
          } finally {
            if (mounted) {
              setState(() => _isFeedbackDialogOpen = false);
            }
          }
        }
      } on SnappySnagException catch (se) {
        _hideLoadingOverlay();
        if (mounted) {
          _showErrorDialog(se.message);
          setState(() {
            _isCapturing = false;
            _capturedImageForFreeze = null;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isCapturing = false;
          _capturedImageForFreeze = null;
        });
      }
    } else {
      _hideLoadingOverlay();
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _capturedImageForFreeze = null;
        });
      }
    }
  }

  Future<List<dynamic>> _fetchExistingFeedbacks(String screenClassName, String screenSignature) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) throw SnappySnagException('API Key is not configured.');

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/get-existing-feedbacks'
        '?screen_class_name=${Uri.encodeComponent(screenClassName)}'
        '&screen_signature=${Uri.encodeComponent(screenSignature)}';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'x-snappy-api-key': apiKey,
          'x-snappy-package-name': SnappySnag()._packageName ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['duplicates'] as List<dynamic>?) ?? [];
      } else {
        String serverError = '';
        try {
          final data = jsonDecode(response.body);
          serverError = data['error'] as String? ?? '';
        } catch (_) {}

        if (response.statusCode == 401) {
          throw SnappySnagException(serverError.isNotEmpty ? serverError : 'Invalid API Key');
        } else if (response.statusCode == 403) {
          throw SnappySnagException(
            serverError.isNotEmpty
                ? serverError
                : 'This API Key is locked to a different application package',
          );
        }
      }
    } on SnappySnagException {
      rethrow;
    } catch (e) {
      debugPrint('❌ SnappySnag Fetch Duplicates Error: $e');
    }
    return [];
  }

  Future<bool> _showDuplicateWarningDialog({
    required List<dynamic> duplicates,
    required Uint8List imageBytes,
    required Map<String, dynamic> widgetTree,
    required String screenClassName,
  }) async {
    _duplicateWarningCompleter = Completer<bool>();
    if (mounted) {
      setState(() {
        _currentDuplicates = duplicates;
        _overlayMode = _SnappyOverlayMode.duplicateWarning;
      });
    }
    return _duplicateWarningCompleter!.future;
  }

  Future<List<dynamic>> _fetchComments(String feedbackLogId) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) return [];

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/comments?feedback_log_id=${Uri.encodeComponent(feedbackLogId)}';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'x-snappy-api-key': apiKey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['comments'] as List<dynamic>?) ?? [];
      }
    } catch (e) {
      debugPrint('❌ SnappySnag Fetch Comments Error: $e');
    }
    return [];
  }

  Future<bool> _postComment({
    required String feedbackLogId,
    required String message,
  }) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) return false;

    final String url = '${SnappySnag().supabaseUrl}/functions/v1/comments';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-snappy-api-key': apiKey,
        },
        body: jsonEncode({
          'feedback_log_id': feedbackLogId,
          'sender_type': 'reporter',
          'sender_name': SnappySnag()._reporterUserId ?? 'Reporter',
          'message': message,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ SnappySnag Post Comment Error: $e');
      return false;
    }
  }

  void _showCommentsThreadSheet(String feedbackId, String bugTitle) async {
    _commentTextController.clear();
    if (mounted) {
      setState(() {
        _commentsFeedbackId = feedbackId;
        _commentsBugTitle = bugTitle;
        _commentsList = [];
        _commentsLoading = true;
        _isSendingComment = false;
        _overlayMode = _SnappyOverlayMode.commentsThread;
      });
    }

    try {
      final result = await _fetchComments(feedbackId);
      if (mounted && _commentsFeedbackId == feedbackId) {
        setState(() {
          _commentsList = result;
          _commentsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _commentsLoading = false);
      }
    }
  }

  Future<void> _sendCommentInline() async {
    final text = _commentTextController.text.trim();
    if (text.isEmpty || _isSendingComment) return;

    if (mounted) {
      setState(() => _isSendingComment = true);
    }

    final success = await _postComment(
      feedbackLogId: _commentsFeedbackId,
      message: text,
    );

    if (success) {
      _commentTextController.clear();
      final updatedComments = await _fetchComments(_commentsFeedbackId);
      if (mounted) {
        setState(() {
          _commentsList = updatedComments;
          _isSendingComment = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isSendingComment = false);
      }
    }
  }


  Future<int> _sendFeedback({
    required Uint8List imageBytes,
    required Map<String, dynamic> widgetTree,
    required String memo,
    required String screenClassName,
    required String screenSignature,
  }) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) {
      debugPrint('❌ SnappySnag Error: API Key is not configured.');
      return 401;
    }

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/collect-feedback';

    try {
      final compressedBytes = await _resizeAndCompressScreenshot(imageBytes);
      final base64Image = base64Encode(compressedBytes);

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-snappy-api-key': apiKey,
        },
        body: jsonEncode({
          'screenshot_base64': base64Image,
          'widget_tree': widgetTree,
          'memo': memo,
          'screen_class_name': screenClassName,
          'screen_signature': screenSignature,
          'tags': ['debug', 'feedback'],
          'metadata': {
            'platform': 'flutter',
            'os_name': kIsWeb ? 'web_${defaultTargetPlatform.name.toLowerCase()}' : Platform.operatingSystem,
            'os_version': kIsWeb ? getBrowserInfoHelper() : Platform.operatingSystemVersion,
            'package_name': SnappySnag()._packageName,
            'reporter_user_id': SnappySnag()._reporterUserId ?? 'anonymous',
            'reporter_email': SnappySnag()._reporterEmail ?? 'anonymous',
            ...?SnappySnag()._customMetadata,
          },
        }),
      );

      debugPrint('🌐 SnappySnag HTTP Response: ${response.statusCode}');
      return response.statusCode;
    } catch (e) {
      debugPrint('❌ SnappySnag Network Error: $e');
      if (!kIsWeb && Platform.isMacOS && e.toString().contains('Operation not permitted')) {
        debugPrint('⚠️ [SnappySnag WARNING] macOS Sandbox Network client restriction detected!');
        debugPrint('======================================================================');
        debugPrint('To allow internet access for your macOS build, please add:');
        debugPrint('  <key>com.apple.security.network.client</key>');
        debugPrint('  <true/>');
        debugPrint('inside macos/Runner/DebugProfile.entitlements and Release.entitlements.');
        debugPrint('======================================================================');
      }
      return -1; // ネットワーク切断を示す独自コード
    }
  }

  Future<void> _startDrawingFlow(
    Uint8List imageBytes,
    Map<String, dynamic> widgetTree, {
    required String screenClassName,
    required String screenSignature,
  }) async {
    if (!mounted) return;
    _drawingCompleter = Completer<void>();
    final mediaSize = MediaQuery.of(context).size;
    final capturedAspect = mediaSize.height > 0 ? (mediaSize.width / mediaSize.height) : (9 / 16);
    setState(() {
      _drawingImageBytes = imageBytes;
      _drawingWidgetTree = widgetTree;
      _drawingScreenClassName = screenClassName;
      _drawingScreenSignature = screenSignature;
      _drawingPoints = [];
      _isRedPen = true;
      _isSendingFeedback = false;
      _isMemoOpen = false;
      _feedbackMemoController.clear();
      _drawingAspectRatio = capturedAspect;
      _overlayMode = _SnappyOverlayMode.drawing;
    });
    return _drawingCompleter!.future;
  }

  void _cancelDrawingFlow() {
    setState(() {
      _overlayMode = _SnappyOverlayMode.none;
      _isCapturing = false;
    });
    _drawingCompleter?.complete();
  }

  Future<void> _sendFeedbackInlineFlow() async {
    final memo = _feedbackMemoController.text;
    if (memo.trim().isEmpty) {
      if (mounted) {
        final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          SnackBar(
            content: Text(_SdkLocale.memoPromptSnackBar),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() {
        _isMemoOpen = true;
      });
      return;
    }

    setState(() {
      _isSendingFeedback = true;
    });

    // 1. 赤ペンとマスキングが載ったキャンバスを再キャプチャする
    final Uint8List? editedBytes = await _canvasScreenshotController.capture();
    final finalBytes = editedBytes ?? _drawingImageBytes!;

    // 2. 送信処理
    final statusCode = await _sendFeedback(
      imageBytes: finalBytes,
      widgetTree: _drawingWidgetTree,
      memo: memo,
      screenClassName: _drawingScreenClassName,
      screenSignature: _drawingScreenSignature,
    );

    final success = statusCode == 200;
    final shouldClose = success || statusCode == 401 || statusCode == 403;

    if (shouldClose) {
      setState(() {
        _overlayMode = _SnappyOverlayMode.none;
        _isCapturing = false;
      });
      _drawingCompleter?.complete();
    } else {
      setState(() {
        _isSendingFeedback = false;
      });
    }

    if (mounted) {
      final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
      String message = _SdkLocale.statusSuccess;
      if (!success) {
        if (statusCode == 429) {
          message = _SdkLocale.statusRateLimit;
        } else if (statusCode == 401) {
          message = _SdkLocale.statusInvalidKey;
        } else if (statusCode == 403) {
          message = _SdkLocale.statusUnauthorizedPackage;
        } else {
          if (!kIsWeb && Platform.isMacOS) {
            message = 'Network error: macOS network.client entitlement may be missing.';
          } else {
            message = _SdkLocale.statusNetworkError;
          }
        }
      }

      ScaffoldMessenger.of(messengerContext).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<Uint8List> _resizeAndCompressScreenshot(Uint8List rawPng) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        rawPng,
        targetWidth: 480,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List() ?? rawPng;
    } catch (e) {
      debugPrint('⚠️ Failed to compress screenshot: $e');
      return rawPng;
    }
  }

  void _showLoadingOverlay() {
    if (mounted) {
      setState(() => _overlayMode = _SnappyOverlayMode.loading);
    }
  }

  void _hideLoadingOverlay() {
    if (mounted) {
      setState(() => _overlayMode = _SnappyOverlayMode.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    // SDK自体が無効化されている場合、一切のオーバーレイ装飾を行わずに素の child をそのまま返す
    if (!SnappySnag().isEnabled) {
      return widget.child;
    }
    return Stack(
      children: [
        // Screenshot wrapper
        Screenshot(controller: _screenshotController, child: widget.child),
        // ⚡️ キャプチャ（撮影）中かつ静止画データがある場合、ライブ画面の上にフリーズ静止画を固定表示（タッチはIgnorePointerで透過）
        if (_isCapturing && _capturedImageForFreeze != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Image.memory(
                _capturedImageForFreeze!,
                fit: BoxFit.fill,
              ),
            ),
          ),
        // ⚡️ インライン・オーバーレイダイアログ (Z-Indexの解決策)
        if (_overlayMode == _SnappyOverlayMode.loading)
          Positioned.fill(
            child: Container(
              color: Colors.black45, // 半透明のバリア (元のアプリ画面やフリーズ画像を覆ってタッチをブロック)
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFFF59E0B)),
                      const SizedBox(height: 16),
                      Text(
                        _SdkLocale.analyzingScreen,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_overlayMode == _SnappyOverlayMode.duplicateWarning)
          Positioned.fill(
            child: Container(
              color: Colors.black54, // 半透明のバリア
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Center(
                child: Material(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 24,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _SdkLocale.duplicateWarningTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _SdkLocale.duplicateWarningSub,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: Scrollbar(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _currentDuplicates.length,
                              itemBuilder: (context, index) {
                                final item = _currentDuplicates[index];
                                final memo = item['user_memo'] ?? '';
                                final severity = item['severity'] ?? 'low';
                                final emoji = severity == 'high'
                                    ? '🔴'
                                    : (severity == 'medium' ? '🟡' : '🔵');

                                return InkWell(
                                  onTap: () {
                                    _showCommentsThreadSheet(
                                      item['id'].toString(),
                                      memo,
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '$emoji $memo',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          item['has_comments'] == true
                                              ? Icons.chat_bubble
                                              : Icons.chat_bubble_outline,
                                          size: 16,
                                          color: Colors.amber,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                            TextButton(
                              onPressed: () {
                                if (mounted) {
                                  setState(() {
                                    _overlayMode = _SnappyOverlayMode.none;
                                  });
                                }
                                _duplicateWarningCompleter?.complete(false);
                              },
                              child: Text(
                                _SdkLocale.checkLater,
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () {
                                if (mounted) {
                                  setState(() {
                                    _overlayMode = _SnappyOverlayMode.none;
                                  });
                                }
                                _duplicateWarningCompleter?.complete(true);
                              },
                              child: Text(
                                _SdkLocale.reportNewIssue,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_overlayMode == _SnappyOverlayMode.commentsThread)
          Positioned.fill(
            child: Container(
              color: Colors.black54, // 半透明のバリア
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Center(
                child: Material(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    constraints: const BoxConstraints(maxWidth: 400, maxHeight: 480),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white70),
                              onPressed: () {
                                if (mounted) {
                                  setState(() {
                                    _overlayMode = _SnappyOverlayMode.duplicateWarning;
                                  });
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chat, color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _commentsBugTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () {
                                if (mounted) {
                                  setState(() {
                                    _overlayMode = _SnappyOverlayMode.none;
                                  });
                                }
                                _duplicateWarningCompleter?.complete(false);
                              },
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10),
                        Expanded(
                          child: _commentsLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.amber,
                                  ),
                                )
                              : _commentsList.isEmpty
                                  ? Center(
                                      child: Text(
                                        _SdkLocale.noCommentsYet,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _commentsList.length,
                                      itemBuilder: (context, index) {
                                        final comment = _commentsList[index];
                                        final isReporter =
                                            comment['sender_type'] == 'reporter';
                                        final senderName = comment['sender_name'] ??
                                            (isReporter ? 'Reporter' : 'Developer');
                                        final msg = comment['message'] ?? '';

                                        return Align(
                                          alignment: isReporter
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.65,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isReporter
                                                  ? Colors.amber.shade700
                                                  : Colors.grey.shade800,
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(12),
                                                topRight: const Radius.circular(12),
                                                bottomLeft: Radius.circular(
                                                  isReporter ? 12 : 2,
                                                ),
                                                bottomRight: Radius.circular(
                                                  isReporter ? 2 : 12,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: isReporter
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  senderName,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isReporter
                                                        ? Colors.black87
                                                        : Colors.amber.shade300,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  msg,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isReporter
                                                        ? Colors.black
                                                        : Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentTextController,
                                maxLength: 500,
                                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  counterText: "", // 下部の文字カウンターを消してコンパクトにする
                                  hintText: _SdkLocale.typeMessage,
                                  hintStyle: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                  fillColor: Colors.black26,
                                  filled: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: _isSendingComment
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.amber,
                                      ),
                                    )
                                  : const Icon(Icons.send, color: Colors.amber),
                              onPressed: _isSendingComment
                                  ? null
                                  : () => _sendCommentInline(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // ⚡️ インラインお絵描き・送信画面
        if (_overlayMode == _SnappyOverlayMode.drawing && _drawingImageBytes != null)
          Positioned.fill(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (overlayContext) {
                    final canvasRatio = _drawingAspectRatio ?? (9 / 16);
                    return Material(
                      type: MaterialType.transparency,
                      child: Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(
                          backgroundColor: Colors.grey.shade900,
                          leading: TextButton(
                            onPressed: _isSendingFeedback
                                ? null
                                : () => _cancelDrawingFlow(),
                            child: Text(
                              _SdkLocale.cancel,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          title: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _SdkLocale.titleFeedback,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Screen: $_drawingScreenSignature',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          centerTitle: true,
                          actions: [
                            TextButton(
                              onPressed: _isSendingFeedback
                                  ? null
                                  : () => _sendFeedbackInlineFlow(),
                              child: _isSendingFeedback
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.amber,
                                      ),
                                    )
                                  : Text(
                                      _SdkLocale.send,
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        body: SafeArea(
                          child: Stack(
                            children: [
                              // 1. お絵描きエリア（画面一杯に表示）
                              Positioned.fill(
                                bottom: 80, // 下部ツールバーのスペースを空ける
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: canvasRatio,
                                    child: Screenshot(
                                      controller: _canvasScreenshotController,
                                      child: LayoutBuilder(
                                        builder: (layoutContext, constraints) {
                                          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                                          return Stack(
                                            children: [
                                              // 背景画像
                                              Positioned.fill(
                                                child: Image.memory(
                                                  _drawingImageBytes!,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                              // 描画キャンバス
                                              Positioned.fill(
                                                child: GestureDetector(
                                                  onPanStart: (details) {
                                                    if (_isSendingFeedback || _isMemoOpen) return;
                                                    setState(() {
                                                      _drawingPoints.add(
                                                        DrawingPoint(
                                                          offsets: [details.localPosition],
                                                          color: _isRedPen
                                                              ? Colors.red
                                                              : Colors.black.withValues(
                                                                  alpha: 0.95,
                                                                ),
                                                          strokeWidth:
                                                              _isRedPen ? 4.0 : 24.0,
                                                          recordedSize: canvasSize,
                                                        ),
                                                      );
                                                    });
                                                  },
                                    onPanUpdate: (details) {
                                      if (_isSendingFeedback || _isMemoOpen) return;
                                      setState(() {
                                        if (_drawingPoints.isNotEmpty) {
                                          _drawingPoints.last.offsets.add(
                                            details.localPosition,
                                          );
                                        }
                                      });
                                    },
                                    onPanEnd: (details) {
                                      if (_isSendingFeedback || _isMemoOpen) return;
                                      setState(() {
                                        if (_drawingPoints.isNotEmpty) {
                                          _drawingPoints.last.offsets.add(null);
                                        }
                                      });
                                    },
                                    child: CustomPaint(
                                      painter: DrawingPainter(points: _drawingPoints),
                                      size: Size.infinite,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                    // 2. 下部フローティングツールバー
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.grey.shade800),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                color: _isRedPen ? Colors.red : Colors.grey,
                              ),
                              tooltip: 'Red Pen',
                              onPressed: _isSendingFeedback
                                  ? null
                                  : () =>
                                      setState(() => _isRedPen = true),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.blur_on,
                                color: !_isRedPen ? Colors.white : Colors.grey,
                              ),
                              tooltip: 'Masking',
                              onPressed: _isSendingFeedback
                                  ? null
                                  : () => setState(
                                        () => _isRedPen = false,
                                      ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.comment,
                                color: _feedbackMemoController.text.trim().isNotEmpty
                                    ? Colors.amber
                                    : Colors.grey,
                              ),
                              tooltip: 'Memo',
                              onPressed: _isSendingFeedback
                                  ? null
                                  : () => setState(
                                        () => _isMemoOpen = true,
                                      ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(
                                Icons.undo,
                                color: Colors.white70,
                              ),
                              tooltip: 'Undo',
                              onPressed: _isSendingFeedback || _drawingPoints.isEmpty
                                  ? null
                                  : () => setState(
                                        () => _drawingPoints.removeLast(),
                                      ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Clear',
                              onPressed: _isSendingFeedback || _drawingPoints.isEmpty
                                  ? null
                                  : () =>
                                      setState(() => _drawingPoints.clear()),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3. メモ入力用フローティングオーバーレイ
                    if (_isMemoOpen)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.75),
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Card(
                                color: Colors.grey.shade900,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: Colors.grey.shade800),
                                ),
                                child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _SdkLocale.describeIssue,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _feedbackMemoController,
                                      maxLength: 500,
                                      maxLengthEnforcement:
                                          MaxLengthEnforcement.enforced,
                                      maxLines: 4,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: _SdkLocale.memoHint,
                                        hintStyle: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                        fillColor: Colors.black26,
                                        filled: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _isMemoOpen = false,
                                        );
                                      },
                                      child: Text(
                                        _SdkLocale.done,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ],
  ),
),
        // Tiny Floating Trigger Button
        if (widget.showTriggerButton && !_isCapturing && !_isFeedbackDialogOpen)
          Positioned(
            bottom: 80,
            right: 16,
            child: GestureDetector(
              onTap: () => _triggerCapture(),
              child: Container(
                width: 68, // Reduced from 80 to fit tightly around the 56px icon
                height: 68, // Reduced from 80
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(18), // Slightly tighter radius for smaller container
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: SnappySnagIcon(size: 56, color: Colors.black), // Double the icon size to 56px
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dumps the active widget tree context into a JSON-compatible map, filtering out noise widgets.
class WidgetTreeDumper {
  static Map<String, dynamic> dump(BuildContext context) {
    Map<String, dynamic> tree = {};
    context.visitChildElements((element) {
      tree = _buildNode(element, 0) ?? {};
    });
    return tree;
  }

  // ★ 根本解決: Scaffoldを起点として先祖を上に遡り、正しい画面カスタムクラスを特定する
  static String findScreenName(BuildContext context) {
    Element? scaffoldElement;

    // ツリー内をくまなく走り、最後に見つかった Scaffold (最前面に重なっている画面) を保持する
    void findScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        scaffoldElement = element; // 見つかるたびに上書きして最新のエレメントにする
      }
      element.visitChildren((child) {
        findScaffold(child); // 途中で止めずに全ての枝を走査
      });
    }

    // 最上位のコンテキストから Scaffold を探索
    context.visitChildElements((element) {
      findScaffold(element);
    });

    if (scaffoldElement == null) {
      return 'UnknownScreen';
    }

    String detectedScreenName = 'UnknownScreen';

    // Scaffold から上に親を遡り、最初のカスタムウィジェットを特定
    scaffoldElement!.visitAncestorElements((ancestor) {
      final typeStr = ancestor.widget.runtimeType.toString();
      final clean = _cleanType(typeStr);

      if (!_isNoiseWidget(clean) && !_isStandardOrFrameworkWidget(clean)) {
        detectedScreenName = typeStr;
        return false; // 探索終了
      }
      return true; // さらに親を遡る
    });

    return detectedScreenName;
  }

  // ★ 画面構成シグネチャの自動生成 (Scaffold 以下のカスタムウィジェットを収集)
  static String findScreenSignature(BuildContext context, String screenClassName) {
    Element? scaffoldElement;

    void findScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        scaffoldElement = element;
      }
      element.visitChildren((child) {
        findScaffold(child);
      });
    }

    context.visitChildElements((element) {
      findScaffold(element);
    });

    if (scaffoldElement == null) {
      return screenClassName;
    }

    final Set<String> customWidgets = {};

    void collectCustomWidgets(Element element, int currentDepth) {
      if (currentDepth > 20 || customWidgets.length >= 2) return;

      final typeStr = element.widget.runtimeType.toString();
      final clean = _cleanType(typeStr);

      if (!_isNoiseWidget(clean) &&
          !_isStandardOrFrameworkWidget(clean) &&
          clean != screenClassName &&
          !clean.startsWith('_')) {
        customWidgets.add(clean);
      }

      element.visitChildren((child) {
        collectCustomWidgets(child, currentDepth + 1);
      });
    }

    scaffoldElement!.visitChildren((child) {
      collectCustomWidgets(child, 0);
    });

    if (customWidgets.isEmpty) {
      return screenClassName;
    }

    final sortedList = customWidgets.toList()..sort();
    return '$screenClassName#${sortedList.join('_')}';
  }

  static String _cleanType(String type) {
    return type.contains('<') ? type.split('<')[0] : type;
  }

  // ★ 改善: キーワードマッチにより、標準ウィジェットのすり抜けを完璧にブロックする
  static bool _isStandardOrFrameworkWidget(String type) {
    final clean = _cleanType(type);

    // 1. 完全一致で除外するFlutterの基本UIウィジェット
    const standards = [
      'MaterialApp',
      'Navigator',
      'Overlay',
      'Scaffold',
      'Container',
      'Padding',
      'SizedBox',
      'Column',
      'Row',
      'Stack',
      'Center',
      'Align',
      'Text',
      'Image',
      'GestureDetector',
      'CustomPaint',
      'Builder',
      'StatefulBuilder',
      'CheckedModeBanner',
      'Banner',
      'SafeArea',
      'Visibility',
      'Material',
      'AnimatedPhysicalModel',
      'PhysicalModel',
      'CustomMultiChildLayout',
      'LayoutId',
      'Semantics',
      'Offstage',
      'TickerMode',
      'KeyedSubtree',
      'MouseRegion',
      'Actions',
      'Shortcuts',
      'Tooltip',
      'ClipRRect',
      'ClipRect',
      'ClipPath',
      'InkWell',
      'InkResponse',
      'ElevatedButton',
      'TextButton',
      'OutlinedButton',
      'IconButton',
      'DropdownButton',
      'FloatingActionButton',
      'RawMaterialButton',
      'BackButton',
      'CloseButton',
      'PopupMenuButton',
      'ToggleButtons',
      'AnimatedDefaultTextStyle',
      'DefaultTextStyle',
      'MediaQuery',
      'ConstrainedBox',
      'UnconstrainedBox',
      'OverflowBox',
      'LimitedBox',
      'FlexibleSpaceBarSettings',
      'FlexibleSpaceBar',
      'DecoratedBox',
      'AppBar',
      'SliverAppBar',
    ];
    if (standards.contains(clean)) return true;

    // 2. Flutterのフレームワーク内部で使われる命名キーワード（部分一致で一括除外）
    const frameworkKeywords = [
      'Scope',
      'Provider',
      'Builder',
      'Listener',
      'Gesture',
      'Paint',
      'Theme',
      'Animation',
      'Route',
      'Navigator',
      'Overlay',
      'Scroll',
      'Focus',
      'Clip',
      'Controller',
      'Observer',
      'Notification',
      'Transition',
      'Tween',
      'Barrier',
      'Modal',
      'Ticker',
      'Style',
      'Query',
      'Media',
    ];
    for (final keyword in frameworkKeywords) {
      if (clean.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static String? _getLocation(Element element) {
    try {
      // 1. RenderObject's debugCreator
      final renderObject = element.renderObject;
      if (renderObject != null) {
        final creator = renderObject.debugCreator;
        if (creator != null) {
          final str = creator.toString();
          // Filter out SDK and library noise paths
          if (str.contains('package:flutter/') ||
              str.contains('package:flutter_web/') ||
              str.contains('package:provider/') ||
              str.contains('package:flutter_riverpod/') ||
              str.contains('package:riverpod/')) {
            return null;
          }
          final match = RegExp(r'([\w\-_]+\.dart:\d+)').firstMatch(str);
          if (match != null) {
            return match.group(1);
          }
        }
      }

      // 2. DiagnosticsNode debug-level output fallback (non-recursive)
      final str = element.toDiagnosticsNode().toString(minLevel: DiagnosticLevel.debug);
      if (str.contains('package:flutter/') ||
          str.contains('package:flutter_web/') ||
          str.contains('package:provider/') ||
          str.contains('package:flutter_riverpod/') ||
          str.contains('package:riverpod/')) {
        return null;
      }
      final match = RegExp(r'([\w\-_]+\.dart:\d+)').firstMatch(str);
      if (match != null) {
        return match.group(1);
      }
    } catch (_) {}
    return null;
  }

  static bool _isLayoutStructuralWidget(String type) {
    final clean = _cleanType(type);
    const layoutWidgets = [
      'Scaffold',
      'Column',
      'Row',
      'Stack',
      'ListView',
      'GridView',
      'SingleChildScrollView',
      'Navigator',
      'MaterialApp'
    ];
    return layoutWidgets.contains(clean);
  }

  static Map<String, dynamic>? _buildNode(Element element, int depth) {
    final widget = element.widget;
    final String type = widget.runtimeType.toString();

    final loc = _getLocation(element);
    final String? key = widget.key?.toString();
    String? text;

    if (widget is Text) {
      final textData = widget.data ?? '';
      text = textData.length > 15 ? '[REDACTED]' : textData;
    } else if (type.contains('EditableText') || type.contains('TextField')) {
      text = '[REDACTED]';
    }

    // Bypass check: If the node contains no location, key, or text, AND is not a structural layout widget,
    // we return null to bypass (skip) this node entirely and let the children flatten up.
    // NOTE: We never bypass the root node (depth == 0) to ensure the tree has a valid starting node.
    if (depth > 0 && loc == null && key == null && text == null && !_isLayoutStructuralWidget(type)) {
      return null;
    }

    Map<String, dynamic> node = {'type': type};
    if (loc != null) node['location'] = loc;
    if (key != null) node['key'] = key;
    if (text != null) node['text'] = text;

    if (depth >= 30) {
      node['truncated'] = true;
      return node;
    }

    // Recursively collect children
    List<Map<String, dynamic>> children = [];
    _collectChildren(element, children, depth + 1);

    if (children.isNotEmpty) {
      node['children'] = children;
    }

    return node;
  }

  // Helper to collect child elements recursively, flattening bypassed null nodes
  static void _collectChildren(
    Element element,
    List<Map<String, dynamic>> resultList,
    int depth,
  ) {
    element.visitChildElements((childElement) {
      final childType = childElement.widget.runtimeType.toString();

      if (_isNoiseWidget(childType)) {
        _collectChildren(childElement, resultList, depth);
      } else {
        final node = _buildNode(childElement, depth);
        if (node != null) {
          resultList.add(node);
        } else {
          // Flatten: If this child node was bypassed, push its descendants directly to this parent level
          _collectChildren(childElement, resultList, depth);
        }
      }
    });
  }

  static bool _isNoiseWidget(String type) {
    final clean = _cleanType(type);
    if (clean.startsWith('_')) return true;
    // バグ解析に直接関係なく、階層を深くしてトークンを浪費する標準ウィジェット群を除外
    const noiseTypes = [
      'Padding',
      'SizedBox',
      'Center',
      'Align',
      'Container',
      'ColoredBox',
      'DefaultTextStyle',
      'DefaultSelectionStyle',
      'Focus',
      'FocusScope',
      'GestureDetector',
      'RawGestureDetector',
      'RepaintBoundary',
      'CustomPaint',
      'AbsorbPointer',
      'IgnorePointer',
      'Semantics',
      'AnimatedBuilder',
      'Builder',
      'StatefulBuilder',
      'WillPopScope',
      'PopScope',
      'Offstage',
      'Visibility',
      'TickerMode',
      'KeyedSubtree',
      'MouseRegion',
      'Listener',
      'Actions',
      'Shortcuts',
      'CheckedModeBanner',
      'Banner',
      'MetaData',
      'Tooltip',
      'PhysicalModel',
      'ClipRRect',
      'ClipRect',
      'ClipPath',
      'AnimatedTheme',
      'Theme',
      'IconTheme',
      'IconThemeColorProvider',
      'DefaultTextHeightBehavior',
      'SelectionArea',
      'SelectionRegistrarScope',
      'Navigator',
      'Overlay',
      'OverlayEntry',
      'Material',
      'ScaffoldMessenger',
    ];
    return noiseTypes.contains(clean);
  }
}

/// 描画の一筆を表現するデータクラス
class DrawingPoint {
  final List<Offset?> offsets;
  final Color color;
  final double strokeWidth;
  final Size recordedSize;

  DrawingPoint({
    required this.offsets,
    required this.color,
    required this.strokeWidth,
    required this.recordedSize,
  });
}

class SnappySnagException implements Exception {
  final String message;
  SnappySnagException(this.message);
  @override
  String toString() => message;
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPoint> points;

  DrawingPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    for (final point in points) {
      final double scaleX = point.recordedSize.width > 0 ? size.width / point.recordedSize.width : 1.0;
      final double scaleY = point.recordedSize.height > 0 ? size.height / point.recordedSize.height : 1.0;

      final paint = Paint()
        ..color = point.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = point.strokeWidth * scaleX
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < point.offsets.length - 1; i++) {
        if (point.offsets[i] != null && point.offsets[i + 1] != null) {
          final p1 = Offset(point.offsets[i]!.dx * scaleX, point.offsets[i]!.dy * scaleY);
          final p2 = Offset(point.offsets[i + 1]!.dx * scaleX, point.offsets[i + 1]!.dy * scaleY);
          canvas.drawLine(p1, p2, paint);
        } else if (point.offsets[i] != null && point.offsets[i + 1] == null) {
          final p1 = Offset(point.offsets[i]!.dx * scaleX, point.offsets[i]!.dy * scaleY);
          canvas.drawPoints(ui.PointMode.points, [p1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Internal localization helper for SnappySnag SDK.
class _SdkLocale {
  static bool get _isJa => ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase().startsWith('ja');

  static String get cancel => _isJa ? 'キャンセル' : 'Cancel';
  static String get send => _isJa ? '送信' : 'Send';
  static String get titleFeedback =>
      _isJa ? 'フィードバック送信' : 'SnappySnag Feedback';
  static String get memoPromptSnackBar => _isJa
      ? '最初に内容のメモを追加してください。'
      : 'Please add a memo describing your feedback first.';

  static String get statusSuccess =>
      _isJa ? 'フィードバックの送信が成功しました！' : 'Feedback sent successfully!';
  static String get statusRateLimit => _isJa
      ? '送信頻度の上限を超えました。1分ほど待って再度お試しください。'
      : 'Rate limit exceeded. Please wait a minute before retrying.';
  static String get statusInvalidKey => _isJa
      ? '送信失敗: APIキーが無効または停止されています。'
      : 'Failed to send: Invalid or inactive API Key.';
  static String get statusUnauthorizedPackage => _isJa
      ? '送信失敗: このアプリパッケージは許可されていません。'
      : 'Failed to send: This app package is not authorized.';
  static String get statusNetworkError => _isJa
      ? 'フィードバックの送信に失敗しました（ネットワークまたはサーバーエラー）。'
      : 'Failed to send feedback (Network or Server Error).';

  static String get duplicateWarningTitle =>
      _isJa ? 'この画面で報告されているフィードバック' : 'Feedbacks reported on this screen';
  static String get duplicateWarningSub => _isJa
      ? '送信する前に、同様の内容が既に報告されていないか確認してください。'
      : 'Before submitting, check if your issue is already reported:';
  static String get checkLater => _isJa ? '後で確認する' : 'I will check later';
  static String get reportNewIssue =>
      _isJa ? '新規にフィードバックを送信' : 'Report New Feedback';

  static String get noCommentsYet => _isJa
      ? 'コメントはまだありません。会話を始めましょう！'
      : 'No comments yet. Start the conversation!';
  static String get typeMessage => _isJa ? 'メッセージを入力...' : 'Type a message...';

  static String get describeIssue =>
      _isJa ? 'フィードバックの詳細を説明してください' : 'Describe your feedback';
  static String get memoHint => _isJa
      ? '（例: この画面のタイトルのフォントサイズが小さすぎます...）'
      : 'e.g., The title font size is too small on this screen...';
  static String get done => _isJa ? '完了' : 'Done';

  static String get analyzingScreen =>
      _isJa ? '画面を解析中...' : 'Analyzing screen...';
}

/// Custom Widget that draws the SnappySnag lightning logo with circular border gap mask.
class SnappySnagIcon extends StatelessWidget {
  final double size;
  final Color color;

  const SnappySnagIcon({
    super.key,
    this.size = 24.0,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: SnappySnagIconPainter(color: color),
      ),
    );
  }
}

/// CustomPainter to draw the SnappySnag logo using path logic similar to the SVG mask.
class SnappySnagIconPainter extends CustomPainter {
  final Color color;

  SnappySnagIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double minSize = size.width < size.height ? size.width : size.height;
    final double scale = minSize / 512.0;

    final double dx = (size.width - minSize) / 2;
    final double dy = (size.height - minSize) / 2;

    canvas.save();
    canvas.translate(dx, dy);

    // 1. Draw circle and erase the gap using saveLayer and BlendMode.clear
    final Rect bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.saveLayer(bounds, Paint());

    // Draw the camera lens circle
    final Paint paintCircle = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0 * scale;

    canvas.drawCircle(
      Offset(256.0 * scale, 256.0 * scale),
      110.0 * scale,
      paintCircle,
    );

    // Setup eraser paints (BlendMode.clear acting as transparent mask)
    final Paint eraserFill = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    final Paint eraserStroke = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0 * scale // This creates the 12px clear gap on each side of the bolt
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Define the bolt paths to be used for erasing and later drawing
    final Path path1 = Path()
      ..moveTo(330.0 * scale, 130.0 * scale)
      ..lineTo(270.0 * scale, 250.0 * scale)
      ..lineTo(190.0 * scale, 250.0 * scale)
      ..lineTo(270.0 * scale, 130.0 * scale)
      ..close();

    final Path path2 = Path()
      ..moveTo(322.0 * scale, 262.0 * scale)
      ..lineTo(242.0 * scale, 382.0 * scale)
      ..lineTo(162.0 * scale, 382.0 * scale)
      ..lineTo(242.0 * scale, 262.0 * scale)
      ..close();

    // Erase the bolt shapes (including a stroke margin) from the circle layer
    canvas.drawPath(path1, eraserStroke);
    canvas.drawPath(path1, eraserFill);
    canvas.drawPath(path2, eraserStroke);
    canvas.drawPath(path2, eraserFill);

    canvas.restore(); // Composites the erased circle layer back to screen

    // 2. Draw the actual sharp solid lightning bolt on top of the circle
    final Paint paintBolt = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path1, paintBolt);
    canvas.drawPath(path2, paintBolt);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

