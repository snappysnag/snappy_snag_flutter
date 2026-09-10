import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'src/browser_info_helper.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, defaultTargetPlatform, DiagnosticsSerializationDelegate;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode of SnappySnag SDK operation.
enum SnappySnagMode {
  /// Developer / Internal QA Mode:
  /// Enables duplicate feedback warning dialogs and internal team comments thread.
  dev,

  /// End-User / Production Mode:
  /// Hides internal tickets and warnings, offering a clean, friendly feedback submission experience.
  user,
}

/// Representation of reporter/user information for SnappySnag.
class SnappySnagUser {
  /// Unique identifier of the user (e.g. database UUID, user ID).
  final String? id;

  /// Contact email address of the user.
  final String? email;

  /// Display name of the user.
  final String? name;

  /// Optional arbitrary attributes associated with this user.
  final Map<String, dynamic>? customAttributes;

  const SnappySnagUser({
    this.id,
    this.email,
    this.name,
    this.customAttributes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (customAttributes != null) ...customAttributes!,
      };
}

/// Main class for SnappySnag SDK configuration.
class SnappySnag {
  static final SnappySnag _instance = SnappySnag._internal();
  factory SnappySnag() => _instance;
  SnappySnag._internal();

  /// Default top-level NavigatorKey provided by SnappySnag SDK.
  /// Pass this directly to `MaterialApp(navigatorKey: SnappySnag.defaultNavigatorKey)` or `SnappySnag().navigatorKey` to avoid manual key management.
  static final GlobalKey<NavigatorState> defaultNavigatorKey = GlobalKey<NavigatorState>();

  String? _apiKey;
  String? _deviceId;
  GlobalKey<NavigatorState>? _customNavigatorKey;
  SnappySnagUser? _user;
  String? _packageName;
  Map<String, dynamic>? _customMetadata;
  String _supabaseUrl =
      'https://apwesndoqpdlgwcylkzj.supabase.co'; // デフォルトは本番環境

  SnappySnagMode _mode = SnappySnagMode.user;
  SnappySnagMode get mode => _mode;
  bool _isDevChatEnabled = true;
  bool get isDevChatEnabled => _isDevChatEnabled;

  /// Current user/reporter information.
  SnappySnagUser? get user => _user;
  String? get reporterUserId => _user?.id;
  String? get reporterEmail => _user?.email;

  /// 常駐ボタンの表示状態を保持・通知する ValueNotifier
  final ValueNotifier<bool> isTriggerButtonVisible = ValueNotifier<bool>(true);

  /// 常駐ボタンが表示中かどうか
  bool get isTriggerButtonAlwaysVisible => isTriggerButtonVisible.value;

  /// 常駐ボタンを表示する
  void showTriggerButton() {
    isTriggerButtonVisible.value = true;
  }

  /// 常駐ボタンを非表示にする
  void hideTriggerButton() {
    isTriggerButtonVisible.value = false;
  }

  /// 常駐ボタンの表示/非表示を切り替える
  void setTriggerButtonVisibility(bool visible) {
    isTriggerButtonVisible.value = visible;
  }

  /// フィードバックモードのアクティブ状態を通知する ValueNotifier
  final ValueNotifier<bool> isFeedbackModeActive = ValueNotifier<bool>(false);

  /// アプリ内ボタン（設定画面など）からフィードバックモードを開始する
  static void startFeedbackMode({BuildContext? context}) {
    final ctx = context ?? SnappySnag().navigatorKey?.currentContext;

    // ★ SDKが無効（isEnabled == false）の場合のダイアログ
    if (!SnappySnag().isEnabled) {
      if (ctx != null) {
        showDialog(
          context: ctx,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF2E2E38)),
            ),
            title: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  _SdkLocale.disabledTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              _SdkLocale.disabledContent,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3E3E48),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  _SdkLocale.ok,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      } else {
        debugPrint('⚠️ SnappySnag Warning: Cannot show disabled dialog because BuildContext is null. Please pass context to SnappySnag.startFeedbackMode(context: context) or pass navigatorKey to SnappySnag().initialize().');
      }
      debugPrint('ℹ️ SnappySnag: Feedback feature is currently disabled (enabled: false).');
      return;
    }

    final isAlreadyVisible = SnappySnag().isTriggerButtonAlwaysVisible;

    if (ctx != null) {
      showDialog(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E38)),
          ),
          title: Row(
            children: [
              const Icon(Icons.camera_alt_outlined, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                isAlreadyVisible
                    ? _SdkLocale.feedbackModeAlreadyVisibleTitle
                    : _SdkLocale.feedbackModeDialogTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            isAlreadyVisible
                ? _SdkLocale.feedbackModeAlreadyVisibleContent
                : _SdkLocale.feedbackModeDialogContent,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            if (!isAlreadyVisible)
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  _SdkLocale.cancel,
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                if (!isAlreadyVisible) {
                  SnappySnag().isFeedbackModeActive.value = true;
                  debugPrint('📸 SnappySnag: Feedback Mode started.');
                }
              },
              child: Text(
                isAlreadyVisible ? _SdkLocale.ok : _SdkLocale.start,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } else {
      if (!isAlreadyVisible) {
        SnappySnag().isFeedbackModeActive.value = true;
        debugPrint('📸 SnappySnag: Feedback Mode started.');
      }
    }
  }

  /// フィードバックモードをキャンセルして終了する
  static void cancelFeedbackMode() {
    SnappySnag().isFeedbackModeActive.value = false;
    debugPrint('❌ SnappySnag: Feedback Mode cancelled.');
  }

  // 有効無効の状態管理フラグを追加
  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;
  String get supabaseUrl => _supabaseUrl;

  /// GlobalKey for accessing top-level Navigator context.
  /// Returns custom navigatorKey if provided to `initialize()`, otherwise returns the default `SnappySnag.navigatorKey`.
  GlobalKey<NavigatorState>? get navigatorKey => _customNavigatorKey ?? SnappySnag.defaultNavigatorKey;

  /// Initialize the SnappySnag SDK with a Project/API Key, Package Name, optional SnappySnagUser, and optional custom NavigatorKey.
  void initialize({
    required String apiKey,
    required String packageName,
    SnappySnagMode mode = SnappySnagMode.user,
    GlobalKey<NavigatorState>? navigatorKey,
    SnappySnagUser? user,
    Map<String, dynamic>? customMetadata,
    bool enabled = true,
    bool showTriggerButton = true,
    String? supabaseUrl,
    bool forceDevInRelease = false,
  }) {
    isTriggerButtonVisible.value = showTriggerButton;
    // ★ 第1の防壁: Releaseモード時の安全ガード
    // 本番ビルド時に mode: SnappySnagMode.dev が指定されていても、
    // forceDevInRelease: true が明示されていない限り自動的に user モードへフォールバック
    if (kReleaseMode && mode == SnappySnagMode.dev && !forceDevInRelease) {
      _mode = SnappySnagMode.user;
      debugPrint('🛡️ SnappySnag Security Guard: SnappySnagMode.dev was specified in release mode without forceDevInRelease: true. Automatically falling back to SnappySnagMode.user to protect internal tickets & developer chats.');
    } else {
      _mode = mode;
    }
    _isEnabled = enabled;
    _apiKey = apiKey;
    _packageName = packageName.trim();
    _customNavigatorKey = navigatorKey;
    _user = user;
    _customMetadata = customMetadata;
    if (supabaseUrl != null && supabaseUrl.trim().isNotEmpty) {
      _supabaseUrl = supabaseUrl.trim();
    }

    if (!_isEnabled) {
      debugPrint('🚀 SnappySnag: SDK is disabled by configuration (enabled: false).');
      return;
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

  /// ユーザー情報を設定・動的更新するためのメソッド
  void setUser(SnappySnagUser? user) {
    _user = user;
    debugPrint(
      '👤 SnappySnag: User info updated (ID: ${user?.id}, Email: ${user?.email}, Name: ${user?.name})',
    );
  }

  /// ユーザー情報をクリアする（ログアウト時など）
  void clearUser() {
    _user = null;
    debugPrint('👤 SnappySnag: User info cleared.');
  }

  /// 端末固有のランダムUUIDを取得（存在しない場合は初回生成してローカルに永続化）
  Future<String> getOrGenerateDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) {
      return _deviceId!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedId = prefs.getString('snappy_snag_device_id');
      if (savedId == null || savedId.isEmpty) {
        savedId = _generateUuidV4();
        await prefs.setString('snappy_snag_device_id', savedId);
      }
      _deviceId = savedId;
      return _deviceId!;
    } catch (e) {
      debugPrint('⚠️ SnappySnag: Failed to access SharedPreferences for deviceId: $e');
      _deviceId ??= _generateUuidV4();
      return _deviceId!;
    }
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    // Set version to 4
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122 (10xxxxxx)
    values[8] = (values[8] & 0x3f) | 0x80;

    final hexDigits =
        values.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hexDigits.sublist(0, 4).join()}-${hexDigits.sublist(4, 6).join()}-${hexDigits.sublist(6, 8).join()}-${hexDigits.sublist(8, 10).join()}-${hexDigits.sublist(10, 16).join()}';
  }
}

/// Overlay Widget that wraps your App to capture screenshots and feedback memos.
class SnappySnagOverlay extends StatefulWidget {
  final Widget child;

  const SnappySnagOverlay({
    super.key,
    required this.child,
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
  bool _isCommentCooldownActive = false;
  final TextEditingController _commentTextController = TextEditingController();
  bool _isFeedbackDialogOpen = false;

  // お絵描きキャンバス用ステート
  Uint8List? _drawingImageBytes;
  Map<String, dynamic> _drawingWidgetTree = {};
  String _drawingScreenClassName = '';
  String _drawingScreenSignature = '';
  List<DrawingPoint> _drawingPoints = [];
  SnappyDrawingTool _activeTool = SnappyDrawingTool.redPen;
  bool _isSendingFeedback = false;
  bool _isMemoOpen = false;
  bool _isPrivacyConfirmOpen = false;
  bool _includeAccountAndDiagnostics = true;
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
    // パスワード等の機密フィールドの絶対座標を自動抽出
    final List<Rect> sensitiveBounds = WidgetTreeDumper.findSensitiveFieldBounds(
      // ignore: use_build_context_synchronously
      targetContext,
    );
    debugPrint('🎬 SnappySnag: Captured Screen ID: $screenClassName, Signature: $screenSignature, Sensitive Areas: ${sensitiveBounds.length}');

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
        // ★ 第2の防壁: ユーザーモードまたはリモートキルスイッチ（isDevChatEnabled == false）時は
        // 内部チケット一覧を一般露出させず、直接フィードバック送信フローへスキップ
        final isUserMode = SnappySnag().mode == SnappySnagMode.user || SnappySnag().isDevChatEnabled == false;
        final duplicates = isUserMode
            ? <dynamic>[]
            : await _fetchExistingFeedbacks(screenClassName, screenSignature);
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
                sensitiveBounds: sensitiveBounds,
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
              sensitiveBounds: sensitiveBounds,
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
          if (SnappySnag().reporterEmail != null && SnappySnag().reporterEmail!.isNotEmpty)
            'x-snappy-reporter-email': SnappySnag().reporterEmail!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['is_dev_chat_enabled'] != null) {
          SnappySnag()._isDevChatEnabled = data['is_dev_chat_enabled'] == true;
        }
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
        headers: {
          'x-snappy-api-key': apiKey,
          if (SnappySnag().reporterEmail != null && SnappySnag().reporterEmail!.isNotEmpty)
            'x-snappy-reporter-email': SnappySnag().reporterEmail!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['is_dev_chat_enabled'] != null) {
          SnappySnag()._isDevChatEnabled = data['is_dev_chat_enabled'] == true;
        }
        return (data['comments'] as List<dynamic>?) ?? [];
      }
    } catch (e) {
      debugPrint('❌ SnappySnag Fetch Comments Error: $e');
    }
    return [];
  }

    Future<_CommentPostResult> _postComment({
    required String feedbackLogId,
    required String message,
  }) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) return _CommentPostResult(false, 'API Key is missing');

    final String url = '${SnappySnag().supabaseUrl}/functions/v1/comments';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-snappy-api-key': apiKey,
          if (SnappySnag().reporterEmail != null && SnappySnag().reporterEmail!.isNotEmpty)
            'x-snappy-reporter-email': SnappySnag().reporterEmail!,
        },
        body: jsonEncode({
          'feedback_log_id': feedbackLogId,
          'sender_type': 'reporter',
          'sender_name': SnappySnag()._user?.name ?? SnappySnag().reporterUserId ?? 'Reporter',
          'message': message,
          if (SnappySnag().reporterEmail != null) 'user_email': SnappySnag().reporterEmail!,
        }),
      );

      if (response.statusCode == 200) {
        return _CommentPostResult(true);
      } else if (response.statusCode == 403) {
        SnappySnag()._isDevChatEnabled = false;
        return _CommentPostResult(false, _SdkLocale.chatDisabled);
      } else if (response.statusCode == 429) {
        return _CommentPostResult(false, _SdkLocale.statusRateLimit);
      } else {
        return _CommentPostResult(false, _SdkLocale.statusNetworkError);
      }
    } catch (e) {
      debugPrint('❌ SnappySnag Post Comment Error: $e');
      return _CommentPostResult(false, _SdkLocale.statusNetworkError);
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
    if (text.isEmpty || _isSendingComment || _isCommentCooldownActive) return;

    if (mounted) {
      setState(() {
        _isSendingComment = true;
        _isCommentCooldownActive = true;
      });
    }

    final result = await _postComment(
      feedbackLogId: _commentsFeedbackId,
      message: text,
    );

    if (result.success) {
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
        if (result.errorMessage != null && result.errorMessage!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage!),
              backgroundColor: Colors.redAccent.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }

    // 第3の防壁: 送信後3秒間のクールダウンタイマー
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isCommentCooldownActive = false);
      }
    });
  }


  Future<_FeedbackResponse> _sendFeedback({
    required Uint8List imageBytes,
    required Map<String, dynamic> widgetTree,
    required String memo,
    required String screenClassName,
    required String screenSignature,
  }) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) {
      debugPrint('❌ SnappySnag Error: API Key is not configured.');
      return _FeedbackResponse(401, 'API Key is not configured.');
    }

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/collect-feedback';

    try {
      final deviceId = await SnappySnag().getOrGenerateDeviceId();
      final compressedBytes = await _resizeAndCompressScreenshot(imageBytes);
      final base64Image = base64Encode(compressedBytes);

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-snappy-api-key': apiKey,
          'x-snappy-device-id': deviceId,
        },
        body: jsonEncode({
          'device_id': deviceId,
          'screenshot_base64': base64Image,
          'widget_tree': (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user) ? widgetTree : <String, dynamic>{},
          'memo': memo,
          'screen_class_name': screenClassName,
          'screen_signature': screenSignature,
          'tags': [
            'debug',
            'feedback',
            SnappySnag().mode == SnappySnagMode.user ? 'user_feedback' : 'dev_report',
          ],
          'metadata': {
            'device_id': deviceId,
            'platform': 'flutter',
            'os_name': kIsWeb ? 'web_${defaultTargetPlatform.name.toLowerCase()}' : Platform.operatingSystem,
            'os_version': kIsWeb ? getBrowserInfoHelper() : Platform.operatingSystemVersion,
            'package_name': SnappySnag()._packageName,
            'reporter_user_id': (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user)
                ? (SnappySnag().reporterUserId ?? 'anonymous')
                : 'anonymous',
            'reporter_email': (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user)
                ? (SnappySnag().reporterEmail ?? 'anonymous')
                : 'anonymous',
            if (SnappySnag()._user?.name != null && (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user))
              'reporter_name': SnappySnag()._user!.name!,
            'mode': SnappySnag().mode == SnappySnagMode.user ? 'user' : 'dev',
            'is_anonymous': (SnappySnag().mode == SnappySnagMode.user && !_includeAccountAndDiagnostics),
            if (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user) ...?SnappySnag()._user?.customAttributes,
            if (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user)
              ...?SnappySnag()._customMetadata,
          },
        }),
      );

      debugPrint('🌐 SnappySnag HTTP Response: ${response.statusCode}');
      String? errorMessage;
      if (response.statusCode != 200) {
        try {
          final Map<String, dynamic> body = jsonDecode(response.body);
          errorMessage = body['error'] as String?;
        } catch (_) {}
      }
      return _FeedbackResponse(response.statusCode, errorMessage);
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
      return _FeedbackResponse(-1, e.toString());
    }
  }

  Future<void> _startDrawingFlow(
    Uint8List imageBytes,
    Map<String, dynamic> widgetTree, {
    required String screenClassName,
    required String screenSignature,
    List<Rect>? sensitiveBounds,
  }) async {
    if (!mounted) return;
    _drawingCompleter = Completer<void>();
    final mediaSize = MediaQuery.of(context).size;
    final capturedAspect = mediaSize.height > 0 ? (mediaSize.width / mediaSize.height) : (9 / 16);

    // パスワード等の機密フィールドを自動検出して初期マスクポイントに追加
    final List<DrawingPoint> initialPoints = [];
    if (sensitiveBounds != null && sensitiveBounds.isNotEmpty) {
      for (final rect in sensitiveBounds) {
        initialPoints.add(
          DrawingPoint(
            offsets: [rect.topLeft, rect.bottomRight],
            rect: rect,
            tool: SnappyDrawingTool.mosaic,
            color: const Color(0xEE303036),
            strokeWidth: rect.height,
            recordedSize: mediaSize,
          ),
        );
      }
    }

    setState(() {
      _drawingImageBytes = imageBytes;
      _drawingWidgetTree = widgetTree;
      _drawingScreenClassName = screenClassName;
      _drawingScreenSignature = screenSignature;
      _drawingPoints = initialPoints;
      _activeTool = SnappyDrawingTool.redPen;
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

    // ★ SnappySnagMode.user（一般ユーザーモード）の場合、最前面オーバーレイのプライバシー確認ダイアログを開く
    if (SnappySnag().mode == SnappySnagMode.user) {
      setState(() {
        _isPrivacyConfirmOpen = true;
      });
      return;
    }

    // dev モードはそのまま即座に送信実行
    await _executeFeedbackSubmission();
  }

  Future<void> _executeFeedbackSubmission() async {
    final memo = _feedbackMemoController.text;
    setState(() {
      _isPrivacyConfirmOpen = false;
      _isSendingFeedback = true;
    });

    // 1. 赤ペンとマスキングが載ったキャンバスを再キャプチャする
    final Uint8List? editedBytes = await _canvasScreenshotController.capture();
    final finalBytes = editedBytes ?? _drawingImageBytes!;

    // 2. 送信処理
    final feedbackRes = await _sendFeedback(
      imageBytes: finalBytes,
      widgetTree: _drawingWidgetTree,
      memo: memo,
      screenClassName: _drawingScreenClassName,
      screenSignature: _drawingScreenSignature,
    );

    final success = feedbackRes.statusCode == 200;
    final shouldClose = success || feedbackRes.statusCode == 401 || feedbackRes.statusCode == 403;

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

    // トースト等の通知
    if (mounted) {
      final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
      String message = _SdkLocale.statusSuccess;
      if (!success) {
        if (feedbackRes.errorMessage != null && feedbackRes.errorMessage!.isNotEmpty) {
          message = feedbackRes.errorMessage!;
        } else {
          if (feedbackRes.statusCode == 429) {
            message = _SdkLocale.statusRateLimit;
          } else if (feedbackRes.statusCode == 401) {
            message = _SdkLocale.statusInvalidKey;
          } else if (feedbackRes.statusCode == 403) {
            message = _SdkLocale.statusUnauthorizedPackage;
          } else {
            if (!kIsWeb && Platform.isMacOS) {
              message = 'Network error: macOS network.client entitlement may be missing.';
            } else {
              message = _SdkLocale.statusNetworkError;
            }
          }
        }
      }

      // ignore: use_build_context_synchronously
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
      // 1. Get raw image dimensions first without scaling
      final ui.Codec metadataCodec = await ui.instantiateImageCodec(rawPng);
      final ui.FrameInfo fi = await metadataCodec.getNextFrame();
      final double width = fi.image.width.toDouble();
      final double height = fi.image.height.toDouble();

      int? targetWidth;
      int? targetHeight;
      const double maxDimension = 640.0;

      // 2. Adjust target bounds depending on orientation (portrait vs landscape)
      if (height > width) {
        targetHeight = maxDimension.toInt();
        targetWidth = ((width / height) * maxDimension).toInt();
      } else {
        targetWidth = maxDimension.toInt();
        targetHeight = ((height / width) * maxDimension).toInt();
      }

      // 3. Load frame and encode at target sizes
      final ui.Codec resizeCodec = await ui.instantiateImageCodec(
        rawPng,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final ui.FrameInfo resizedFrame = await resizeCodec.getNextFrame();
      final byteData = await resizedFrame.image.toByteData(
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
                                final severity = item['severity'] ?? 'unassessed';
                                final emoji = severity == 'high'
                                    ? '🔴'
                                    : (severity == 'medium'
                                        ? '🟡'
                                        : (severity == 'low' ? '🔵' : '⚪'));

                                return InkWell(
                                  onTap: () {
                                    if (SnappySnag().isDevChatEnabled == false) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(_SdkLocale.chatDisabled),
                                          backgroundColor: const Color(0xFF2E2E38),
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                      return;
                                    }
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
                              icon: (_isSendingComment || _isCommentCooldownActive)
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _isCommentCooldownActive && !_isSendingComment ? Colors.grey : Colors.amber,
                                      ),
                                    )
                                  : const Icon(Icons.send, color: Colors.amber),
                              onPressed: (_isSendingComment || _isCommentCooldownActive)
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
                                                      final double strokeWidth = _activeTool == SnappyDrawingTool.mosaic ? 24.0 : 4.0;
                                                      final Color color = _activeTool == SnappyDrawingTool.mosaic ? const Color(0xEE303036) : Colors.red;
                                                      _drawingPoints.add(
                                                        DrawingPoint(
                                                          offsets: [details.localPosition],
                                                          color: color,
                                                          strokeWidth: strokeWidth,
                                                          tool: _activeTool,
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
                          horizontal: 14,
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
                            // 1. 赤ペン
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                color: _activeTool == SnappyDrawingTool.redPen
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                              tooltip: 'Red Pen',
                              onPressed: _isSendingFeedback
                                  ? null
                                  : () => setState(
                                        () => _activeTool = SnappyDrawingTool.redPen,
                                      ),
                            ),
                            // 2. モザイクペン
                            IconButton(
                              icon: Icon(
                                Icons.blur_on,
                                color: _activeTool == SnappyDrawingTool.mosaic
                                    ? const Color(0xFFF59E0B)
                                    : Colors.grey,
                              ),
                              tooltip: 'Mosaic Blur',
                              onPressed: _isSendingFeedback
                                  ? null
                                  : () => setState(
                                        () => _activeTool = SnappyDrawingTool.mosaic,
                                      ),
                            ),
                            // 4. メモ
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
                            const SizedBox(width: 6),
                            // 5. 元に戻す (Undo)
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
                            // 6. 全消去 (Clear)
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
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                                        maxLines: 4,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: _SdkLocale.memoHint,
                                          hintStyle: const TextStyle(color: Colors.grey),
                                          fillColor: Colors.black26,
                                          filled: true,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: Colors.grey.shade800),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: () {
                                          setState(() => _isMemoOpen = false);
                                        },
                                        child: Text(
                                          _SdkLocale.done,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
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

                    // 4. プライバシー確認用フローティングオーバーレイ（最前面に描画）
                    if (_isPrivacyConfirmOpen)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.75),
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Card(
                                color: const Color(0xFF1E1E24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: Color(0xFF2E2E38)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B)),
                                          const SizedBox(width: 8),
                                          Text(
                                            _SdkLocale.privacyConfirmTitle,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      // 1. 画像モザイク確認
                                      Text(
                                        _SdkLocale.privacyConfirmContent,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Divider(color: Color(0xFF2E2E38)),
                                      const SizedBox(height: 8),
                                      // 2. 診断・アカウント情報共有チェックボックス
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _includeAccountAndDiagnostics = !_includeAccountAndDiagnostics;
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: _includeAccountAndDiagnostics,
                                                  activeColor: const Color(0xFFF59E0B),
                                                  checkColor: Colors.black,
                                                  side: const BorderSide(color: Colors.white38),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _includeAccountAndDiagnostics = val ?? true;
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      SnappySnag().reporterEmail != null && SnappySnag().reporterEmail!.isNotEmpty
                                                          ? _SdkLocale.privacyShareAccountWithEmail(SnappySnag().reporterEmail!)
                                                          : _SdkLocale.privacyShareAccount,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _SdkLocale.privacyAnonymousHint,
                                                      style: TextStyle(
                                                        color: Colors.grey.shade400,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              setState(() => _isPrivacyConfirmOpen = false);
                                            },
                                            child: Text(
                                              _SdkLocale.backToEdit,
                                              style: const TextStyle(color: Colors.white60),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFF59E0B),
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              _executeFeedbackSubmission();
                                            },
                                            child: Text(
                                              _SdkLocale.sendConfirm,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
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
        // Feedback Mode Guidance Banner & Floating Trigger Button
        AnimatedBuilder(
          animation: Listenable.merge([
            SnappySnag().isTriggerButtonVisible,
            SnappySnag().isFeedbackModeActive,
          ]),
          builder: (context, _) {
            final isTriggerVisible = SnappySnag().isTriggerButtonVisible.value;
            final isFeedbackActive = SnappySnag().isFeedbackModeActive.value;
            final shouldShowButton =
                (isTriggerVisible || isFeedbackActive) &&
                    !_isCapturing &&
                    !_isFeedbackDialogOpen &&
                    _overlayMode == _SnappyOverlayMode.none;

            return Stack(
              children: [
                // フローティング撮影ボタン（フィードバックモードまたは常駐設定時）
                if (shouldShowButton)
                  Positioned(
                    bottom: 80,
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        // 撮影開始時にフィードバックモードを解除
                        SnappySnag().isFeedbackModeActive.value = false;
                        _triggerCapture();
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: SnappySnagIcon(size: 42, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A widget that temporarily hides the SnappySnag floating trigger button
/// while this widget is mounted in the widget tree (e.g., Camera, Payment, Video screens).
///
/// When disposed, it automatically restores the trigger button visibility.
class SnappySnagHideButton extends StatefulWidget {
  final Widget child;

  const SnappySnagHideButton({
    super.key,
    required this.child,
  });

  @override
  State<SnappySnagHideButton> createState() => _SnappySnagHideButtonState();
}

class _SnappySnagHideButtonState extends State<SnappySnagHideButton> {
  bool _wasVisibleBefore = true;

  @override
  void initState() {
    super.initState();
    _wasVisibleBefore = SnappySnag().isTriggerButtonVisible.value;
    SnappySnag().hideTriggerButton();
  }

  @override
  void dispose() {
    if (_wasVisibleBefore) {
      SnappySnag().showTriggerButton();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SimpleDiagnosticsSerializationDelegate implements DiagnosticsSerializationDelegate {
  const _SimpleDiagnosticsSerializationDelegate();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      if (invocation.memberName == #subtreeDepth) return 0;
      if (invocation.memberName == #includeProperties) return true;
      if (invocation.memberName == #expandValueProperties) return false;
    }
    return null;
  }
}


class _CommentPostResult {
  final bool success;
  final String? errorMessage;
  _CommentPostResult(this.success, [this.errorMessage]);
}

class _FeedbackResponse {
  final int statusCode;
  final String? errorMessage;
  _FeedbackResponse(this.statusCode, this.errorMessage);
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

  /// 画面上のパスワード欄、Email欄、電話番号欄、機密入力欄のグローバル絶対座標（Rect）を自動収集
  /// （※ 最前面のアクティブな画面かつ目に見えて表示されている入力欄のみを対象にする）
  static List<Rect> findSensitiveFieldBounds(BuildContext context) {
    final List<Rect> bounds = [];
    final Set<int> visitedHashCodes = {};

    // 1. 最前面の Scaffold (最前面に重なっている画面) を特定
    Element? topScaffoldElement;
    void findTopScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        topScaffoldElement = element;
      }
      element.visitChildren(findTopScaffold);
    }
    context.visitChildElements(findTopScaffold);

    // 探索の起点: 最前面のScaffoldが見つかればそれを起点にし、なければ渡されたcontextを使用
    final Element searchRoot = topScaffoldElement ?? (context as Element);

    // 画面全体のサイズを取得（画面外の座標を除外するため）
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenWidth = mediaQuery?.size.width ?? 5000.0;
    final screenHeight = mediaQuery?.size.height ?? 5000.0;

    // 個人情報検出用の正規表現（メール、電話番号、クレジットカード、郵便番号）
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final phoneRegex = RegExp(r'(?:\+?\d{1,3}[- ]?)?(?:0\d{1,4}[- ]?\d{1,4}[- ]?\d{3,4}|\b\d{3}[- ]?\d{4}[- ]?\d{4}\b)');
    final creditCardRegex = RegExp(r'\b(?:\d{4}[ -]?){3}\d{4}\b');
    final postalCodeRegex = RegExp(r'〒?\s*\d{3}-\d{4}');

    void inspectElement(Element element) {
      if (visitedHashCodes.contains(element.hashCode)) return;
      visitedHashCodes.add(element.hashCode);

      final widget = element.widget;

      // 非表示ウィジェット（Offstage / Visibility / TickerMode）の場合はその配下ごとスキップ
      if (widget is Offstage && widget.offstage) return;
      if (widget is Visibility && !widget.visible) return;
      if (widget is TickerMode && !widget.enabled) return;

      bool isSensitive = false;

      // 1. Text / RichText 内の個人情報パターン検知（メール、電話番号、カード番号、郵便番号）
      if (widget is Text && widget.data != null) {
        final text = widget.data!;
        if (text.length >= 6 &&
            (emailRegex.hasMatch(text) ||
                phoneRegex.hasMatch(text) ||
                creditCardRegex.hasMatch(text) ||
                postalCodeRegex.hasMatch(text))) {
          isSensitive = true;
        }
      } else if (widget is RichText) {
        final text = widget.text.toPlainText();
        if (text.length >= 6 &&
            (emailRegex.hasMatch(text) ||
                phoneRegex.hasMatch(text) ||
                creditCardRegex.hasMatch(text) ||
                postalCodeRegex.hasMatch(text))) {
          isSensitive = true;
        }
      }

      // 2. CircleAvatar（プロフィール顔写真）の検知
      if (widget is CircleAvatar) {
        isSensitive = true;
      }

      // 3. TextField / EditableText の判定（アクティブかつ編集可能な入力フィールドのみ）
      if (widget is TextField) {
        if (!widget.readOnly && (widget.enabled ?? true)) {
          isSensitive = true;
        }
      } else if (widget is EditableText) {
        // SelectableTextなどの読み取り専用EditableTextは除外
        if (!widget.readOnly) {
          isSensitive = true;
        }
      }

      if (isSensitive) {
        final renderBox = element.findRenderObject();
        if (renderBox is RenderBox && renderBox.hasSize && renderBox.attached) {
          try {
            final position = renderBox.localToGlobal(Offset.zero);
            final size = renderBox.size;

            // 最小サイズ条件（幅20px以上、高さ10px以上）
            if (size.width >= 20 && size.height >= 10) {
              // 画面内（Viewport）に実際に存在しているかをチェック
              final isInsideScreen = position.dx < screenWidth &&
                  position.dx + size.width > 0 &&
                  position.dy < screenHeight &&
                  position.dy + size.height > 0;

              if (isInsideScreen) {
                final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
                if (!bounds.any((b) => (b.left - rect.left).abs() < 5 && (b.top - rect.top).abs() < 5)) {
                  bounds.add(rect);
                }
              }
            }
          } catch (_) {}
        }
      }

      element.visitChildren(inspectElement);
    }

    searchRoot.visitChildren(inspectElement);
    return bounds;
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
      final node = element.toDiagnosticsNode();
      // Use toJsonMap with our concrete delegate implementation to safely extract creationLocation metadata
      final jsonMap = node.toJsonMap(const _SimpleDiagnosticsSerializationDelegate());
      if (jsonMap.containsKey('creationLocation')) {
        final locMap = jsonMap['creationLocation'] as Map<String, dynamic>?;
        if (locMap != null && locMap.containsKey('file')) {
          final file = locMap['file'] as String;
          final line = locMap['line'] as int;

          // Reject framework paths
          if (!file.contains('package:flutter/') &&
              !file.contains('package:provider/') &&
              !file.contains('package:flutter_riverpod/') &&
              !file.contains('package:riverpod/')) {
            // Safe URI parsing to extract the basename, falling back to full path if needed
            String fileName = file;
            try {
              final uri = Uri.parse(file);
              if (uri.pathSegments.isNotEmpty) {
                fileName = uri.pathSegments.last;
              }
            } catch (_) {}
            return '$fileName:$line';
          }
        }
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

/// Drawing tool type for annotation and masking.
enum SnappyDrawingTool {
  redPen,
  mosaic,
}

/// 描画の一筆を表現するデータクラス
class DrawingPoint {
  final List<Offset?> offsets;
  final Color color;
  final double strokeWidth;
  final Size recordedSize;
  final SnappyDrawingTool tool;
  final Rect? rect;

  DrawingPoint({
    required this.offsets,
    required this.color,
    required this.strokeWidth,
    required this.recordedSize,
    this.tool = SnappyDrawingTool.redPen,
    this.rect,
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

      // 1. 自動マスキング矩形がある場合
      if (point.rect != null) {
        final scaledRect = Rect.fromLTRB(
          point.rect!.left * scaleX,
          point.rect!.top * scaleY,
          point.rect!.right * scaleX,
          point.rect!.bottom * scaleY,
        );

        if (point.tool == SnappyDrawingTool.mosaic) {
          // モザイク風のフロスト角丸矩形を描画
          final bgPaint = Paint()
            ..color = const Color(0xE62A2A2E)
            ..style = PaintingStyle.fill;
          canvas.drawRRect(
            RRect.fromRectAndRadius(scaledRect, const Radius.circular(6)),
            bgPaint,
          );

          // ピクセルモザイク風グリッドライン
          final gridPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.12)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke;
          for (double x = scaledRect.left; x < scaledRect.right; x += 10) {
            canvas.drawLine(Offset(x, scaledRect.top), Offset(x, scaledRect.bottom), gridPaint);
          }
          for (double y = scaledRect.top; y < scaledRect.bottom; y += 10) {
            canvas.drawLine(Offset(scaledRect.left, y), Offset(scaledRect.right, y), gridPaint);
          }
        } else {
          // 黒塗り
          final blackPaint = Paint()
            ..color = Colors.black
            ..style = PaintingStyle.fill;
          canvas.drawRRect(
            RRect.fromRectAndRadius(scaledRect, const Radius.circular(4)),
            blackPaint,
          );
        }
        continue;
      }

      // 2. なぞり書きパスの描画
      if (point.tool == SnappyDrawingTool.mosaic) {
        // ★ 本物のモザイク（Pixelation）タイル描画
        const double tileSize = 10.0;
        final Set<String> drawnTiles = {};

        for (final offset in point.offsets) {
          if (offset == null) continue;
          final center = Offset(offset.dx * scaleX, offset.dy * scaleY);
          final radius = point.strokeWidth * scaleX * 0.65;

          final int minTileX = ((center.dx - radius) / tileSize).floor();
          final int maxTileX = ((center.dx + radius) / tileSize).ceil();
          final int minTileY = ((center.dy - radius) / tileSize).floor();
          final int maxTileY = ((center.dy + radius) / tileSize).ceil();

          for (int tx = minTileX; tx <= maxTileX; tx++) {
            for (int ty = minTileY; ty <= maxTileY; ty++) {
              final key = '$tx,$ty';
              if (drawnTiles.contains(key)) continue;

              final tileRect = Rect.fromLTWH(
                tx * tileSize,
                ty * tileSize,
                tileSize,
                tileSize,
              );

              if ((tileRect.center - center).distance <= radius) {
                drawnTiles.add(key);

                final hash = (tx * 73856093 ^ ty * 19349663).abs() % 4;
                final Color tileColor;
                switch (hash) {
                  case 0:
                    tileColor = const Color(0xF02A2A2E);
                    break;
                  case 1:
                    tileColor = const Color(0xF0404048);
                    break;
                  case 2:
                    tileColor = const Color(0xF05A5A66);
                    break;
                  default:
                    tileColor = const Color(0xF01E1E22);
                }

                final tilePaint = Paint()
                  ..color = tileColor
                  ..style = PaintingStyle.fill;
                canvas.drawRect(tileRect, tilePaint);

                final borderPaint = Paint()
                  ..color = Colors.white.withValues(alpha: 0.08)
                  ..strokeWidth = 0.5
                  ..style = PaintingStyle.stroke;
                canvas.drawRect(tileRect, borderPaint);
              }
            }
          }
        }
        continue;
      }

      // 赤ペン・黒塗りペンの描画
      final paint = Paint()
        ..color = point.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
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

  static String get disabledTitle =>
      _isJa ? 'フィードバック機能は無効です' : 'Feedback Feature Disabled';
  static String get disabledContent => _isJa
      ? '現在フィードバック機能は無効に設定されているため、ご利用いただけません。'
      : 'The feedback feature is currently disabled and unavailable.';

  static String get start => _isJa ? '開始する' : 'Start';
  static String get ok => _isJa ? '了解' : 'OK';
  static String get feedbackModeDialogTitle =>
      _isJa ? 'フィードバックモード' : 'Feedback Mode';
  static String get feedbackModeDialogContent => _isJa
      ? 'アプリを自由に操作して報告したい画面へ移動してください。\n目的の画面で右下のボタンをタップすると撮影できます。'
      : 'Navigate freely to the screen you want to report.\nTap the button at the bottom right to capture.';

  static String get feedbackModeAlreadyVisibleTitle =>
      _isJa ? 'フィードバックボタン' : 'Feedback Button';
  static String get feedbackModeAlreadyVisibleContent => _isJa
      ? 'フィードバック用のボタンは既に画面右下に表示されています。\nいつでもタップして現在の画面を報告できます。'
      : 'The feedback button is already visible at the bottom right.\nTap it anytime to report the current screen.';

  static String get privacyConfirmTitle =>
      _isJa ? '送信前の確認' : 'Privacy Check';
  static String get privacyConfirmContent => _isJa
      ? '画面内の個人情報や機密情報（パスワード・住所・顔写真など）はモザイクで隠れていますか？'
      : 'Are personal or sensitive details (passwords, address, photos) properly masked with blur?';
  static String privacyShareAccountWithEmail(String email) => _isJa
      ? '問題解決のために診断情報とアカウント情報 ($email) を共有する'
      : 'Include diagnostics and account info ($email) to resolve issues';
  static String get privacyShareAccount => _isJa
      ? '問題解決のためにデバイス診断情報を共有する'
      : 'Include device diagnostics to resolve issues';
  static String get privacyAnonymousHint => _isJa
      ? '※チェックを外すと匿名（画像とメモのみ）で送信されます'
      : 'Uncheck to submit anonymously (screenshot and memo only)';
  static String get backToEdit => _isJa ? '戻って編集' : 'Back to Edit';
  static String get sendConfirm => _isJa ? '送信する' : 'Send';

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
  static String get chatDisabled => _isJa
      ? '管理者により現在チャット機能は無効に設定されています。'
      : 'Chat is currently disabled by the project administrator.';

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

