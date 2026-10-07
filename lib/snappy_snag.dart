// ignore_for_file: unused_element, use_build_context_synchronously
import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'src/browser_info_helper.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  bool _enableWidgetTree = true;
  bool get enableWidgetTree => _enableWidgetTree;
  bool _enableShakeTrigger = true;
  bool get enableShakeTrigger => _enableShakeTrigger;
  bool _enableLogging = false;
  bool get enableLogging => _enableLogging;

  /// アプリ起動中のみメモリ保持される開発者機能保護パスコード（4桁）
  /// ローカルストレージには一切書き込まず、アプリ終了で自動クリアされる
  String? _devPasscode;
  String? get devPasscode => _devPasscode;
  void setDevPasscode(String? code) {
    _devPasscode = code;
  }
  void clearDevPasscode() {
    _devPasscode = null;
  }

  /// Current user/reporter information.
  SnappySnagUser? get user => _user;
  String? get reporterUserId => _user?.id;
  String? get reporterEmail => _user?.email;

  /// 常駐ボタンの表示状態を保持・通知する ValueNotifier
  final ValueNotifier<bool> isTriggerButtonVisible = ValueNotifier<bool>(true);

  /// 基本の表示設定（initializeで設定された値）
  bool _baseTriggerButtonVisibility = true;

  /// SnappySnagHideButton などによる一時的非表示リクエストの参照カウント
  int _hideRequestsCount = 0;

  /// 常駐ボタンが表示中かどうか
  bool get isTriggerButtonAlwaysVisible => isTriggerButtonVisible.value;

  /// 常駐ボタンを表示する
  void showTriggerButton() {
    _baseTriggerButtonVisibility = true;
    _updateTriggerButtonVisibility();
  }

  /// 常駐ボタンを非表示にする
  void hideTriggerButton() {
    _baseTriggerButtonVisibility = false;
    _updateTriggerButtonVisibility();
  }

  /// 常駐ボタンの表示/非表示を切り替える
  void setTriggerButtonVisibility(bool visible) {
    _baseTriggerButtonVisibility = visible;
    _updateTriggerButtonVisibility();
  }

  void _pushHideRequest() {
    _hideRequestsCount++;
    _updateTriggerButtonVisibility();
  }

  void _popHideRequest() {
    if (_hideRequestsCount > 0) {
      _hideRequestsCount--;
    }
    _updateTriggerButtonVisibility();
  }

  void _updateTriggerButtonVisibility() {
    final shouldBeVisible = _baseTriggerButtonVisibility && _hideRequestsCount == 0;
    if (isTriggerButtonVisible.value != shouldBeVisible) {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        binding.addPostFrameCallback((_) {
          final currentTarget = _baseTriggerButtonVisibility && _hideRequestsCount == 0;
          if (isTriggerButtonVisible.value != currentTarget) {
            isTriggerButtonVisible.value = currentTarget;
          }
        });
      } else {
        isTriggerButtonVisible.value = shouldBeVisible;
      }
    }
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
      SnappySnag._log('ℹ️ SnappySnag: Feedback feature is currently disabled (enabled: false).');
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
                  SnappySnag._log('📸 SnappySnag: Feedback Mode started.');
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
        SnappySnag._log('📸 SnappySnag: Feedback Mode started.');
      }
    }
  }

  /// フィードバックモードをキャンセルして終了する
  static void cancelFeedbackMode() {
    SnappySnag().isFeedbackModeActive.value = false;
    SnappySnag._log('❌ SnappySnag: Feedback Mode cancelled.');
  }

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;
  String get supabaseUrl => _supabaseUrl;

  /// Returns `true` if the SDK is operating in Demo / Sandbox mode.
  /// Demo mode is active when [apiKey] is empty, `'demo'`, `'sandbox'`, or `'snag_live_sample_api_key'`.
  /// In this mode, developers can test UI capturing and pin annotations locally without a dashboard account.
  bool get isDemoMode {
    final key = _apiKey?.trim() ?? '';
    return key.isEmpty ||
        key.toLowerCase() == 'demo' ||
        key.toLowerCase() == 'sandbox' ||
        key == 'snag_live_sample_api_key';
  }

  /// GlobalKey for accessing top-level Navigator context.
  /// Returns custom navigatorKey if provided to `initialize()`, otherwise returns the default `SnappySnag.navigatorKey`.
  GlobalKey<NavigatorState>? get navigatorKey => _customNavigatorKey ?? SnappySnag.defaultNavigatorKey;

  /// Initialize the SnappySnag SDK with a Project/API Key, optional Package Name, optional SnappySnagUser, and optional custom NavigatorKey.
  ///
  /// [enableLogging]: Set to `true` to enable debug output via `debugPrint` during development.
  /// Defaults to `false`. **Disable before releasing to production** — logs may contain
  /// sensitive information such as screen class names, UI element data, and user metadata.
  void initialize({
    required String apiKey,
    String? packageName,
    SnappySnagMode mode = SnappySnagMode.user,
    GlobalKey<NavigatorState>? navigatorKey,
    SnappySnagUser? user,
    Map<String, dynamic>? customMetadata,
    bool enabled = true,
    bool showTriggerButton = false,
    bool enableWidgetTree = true,
    bool enableShakeTrigger = true,
    bool enableLogging = false,
    String? supabaseUrl,
    bool forceDevInRelease = false,
  }) {
    _enableLogging = enableLogging;
    // 常駐ボタンの表示制御:
    // 安全のため、modeに関わらずデフォルトは非表示 (false)。
    // テスト等で画面にボタンを出したい場合は showTriggerButton: true を指定する。
    _baseTriggerButtonVisibility = showTriggerButton;
    _updateTriggerButtonVisibility();
    _enableWidgetTree = enableWidgetTree;
    _enableShakeTrigger = enableShakeTrigger;
    // ★ 第1の防壁: Releaseモード時の安全ガード
    // 本番ビルド時に mode: SnappySnagMode.dev が指定されていても、
    // forceDevInRelease: true が明示されていない限り自動的に user モードへフォールバック
    if (kReleaseMode && mode == SnappySnagMode.dev && !forceDevInRelease) {
      _mode = SnappySnagMode.user;
      // 🔴 常時出力: セキュリティ保護の通知（enableLogging に関わらず出力）
      debugPrint('🛡️ SnappySnag Security Guard: SnappySnagMode.dev was specified in release mode without forceDevInRelease: true. Automatically falling back to SnappySnagMode.user to protect internal tickets & developer chats.');
    } else {
      _mode = mode;
    }
    _isEnabled = enabled;
    _apiKey = apiKey;
    _packageName = packageName?.trim();
    _customNavigatorKey = navigatorKey;
    _user = user;
    _customMetadata = customMetadata;
    if (supabaseUrl != null && supabaseUrl.trim().isNotEmpty) {
      _supabaseUrl = supabaseUrl.trim();
    }

    if (!_isEnabled) {
      _log('🚀 SnappySnag: SDK is disabled by configuration (enabled: false).');
      return;
    }

    if (isDemoMode) {
      // 🎯 デモ・サンドボックスモードの通知
      debugPrint('🎯 [SnappySnag] Demo/Sandbox Mode Active! Local capturing & pin testing enabled without server account.');
    } else if (_apiKey == null || _apiKey!.trim().isEmpty) {
      // 🔴 常時出力: 必須設定ミスの警告（enableLogging に関わらず出力）
      debugPrint('⚠️ SnappySnag Warning: apiKey is empty or not configured.');
    }
    _log('🚀 SnappySnag initialized.');
  }

  /// [enableLogging] が true のときのみ debugPrint でログ出力する内部ユーティリティ。
  /// pub.dev パッケージとして組み込まれたアプリのコンソールを汚染しないよう、
  /// デフォルトは false（無音）。開発時のデバッグ用途で true に設定する。
  static void _log(String message) {
    if (SnappySnag()._enableLogging) {
      debugPrint(message);
    }
  }

  /// ユーザー情報を設定・動的更新するためのメソッド
  void setUser(SnappySnagUser? user) {
    _user = user;
    SnappySnag._log(
      '👤 SnappySnag: User info updated (ID: ${user?.id}, Email: ${user?.email}, Name: ${user?.name})',
    );
  }

  /// ユーザー情報をクリアする（ログアウト時など）
  void clearUser() {
    _user = null;
    SnappySnag._log('👤 SnappySnag: User info cleared.');
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
      SnappySnag._log('⚠️ SnappySnag: Failed to access SharedPreferences for deviceId: $e');
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

  // お絵描き＆ピン留めキャンバス用ステート
  Uint8List? _drawingImageBytes;
  Map<String, dynamic> _drawingWidgetTree = {};
  String _drawingScreenClassName = '';
  String _drawingScreenSignature = '';
  List<DrawingPoint> _drawingPoints = [];
  List<SnappyPin> _pins = [];
  // ★ undo/redo 統合履歴スタック
  // SnappyPin (ピン追加) または DrawingPoint (モザイク1ストローク) を時系列順に記録する
  final List<Object> _undoStack = [];
  final List<Object> _redoStack = [];
  SnappyPin? _editingPin;
  // ★ 社内実験用内部フラグ（初期リリースでは非公開・無効化）
  // 今後のアップデートでUI/UXの検証・改善が完了した際に公開検討
  static const bool _enableSectionHighlights = false;

  List<dynamic> _existingFeedbacks = [];
  List<ExistingPinItem> _existingPins = [];
  List<ExistingSectionItem> _existingSections = [];
  bool _requiresPasscode = false;
  bool _showExistingPins = _enableSectionHighlights;
  ExistingSectionItem? _selectedSection;
  ExistingPinItem? _previewingPin;
  bool _showAllScreenPinsModal = false;
  Offset? _dragStartGlobal;
  double? _dragStartPinX;
  double? _dragStartPinY;
  final TextEditingController _pinCommentController = TextEditingController();
  SnappyDrawingTool _activeTool = SnappyDrawingTool.pin;
  bool _isSendingFeedback = false;
  bool _isMemoOpen = false;
  bool _isPrivacyConfirmOpen = false;
  bool _isCancelDraftConfirmOpen = false;
  bool _isFailedSendDraftConfirmOpen = false;
  bool _isClearConfirmOpen = false;
  bool _isDevPasscodeDialogOpen = false;
  bool _isVerifyingDevPasscode = false;
  bool _isLoadingAllScreenPins = false;
  final TextEditingController _devPasscodeInputController = TextEditingController();
  String? _devPasscodeErrorMessage;
  bool _includeAccountAndDiagnostics = true;
  final TextEditingController _feedbackMemoController = TextEditingController();
  final ScreenshotController _canvasScreenshotController = ScreenshotController();
  Completer<void>? _drawingCompleter;
  double? _drawingAspectRatio;

  DateTime? _lastShakeTime;
  int _shakeFlipCount = 0;
  DateTime? _firstFlipTime;
  double _lastSignX = 0;
  double _lastSignY = 0;

  @override
  void initState() {
    super.initState();
    _initShakeDetection();
  }

  void _initShakeDetection() {
    // SDKが無効またはシェイク検知が無効化されている場合はセンサー登録をスキップ
    if (!SnappySnag().isEnabled || !SnappySnag().enableShakeTrigger) return;

    // Webやデスクトップ（macOS/Windows/Linux）などの非モバイルプラットフォームではシェイク検知を無効化
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!isMobile) return;

    // ★ 端末を傾けたり持ち上げただけの誤検知を完全に防止する高精度シェイク検知
    // 1. しきい値: 傾き操作では届かない 22.0 m/s^2 以上の強い加速度
    // 2. 往復検知: 加速度の向き（正負）が急激に反転（往復）した回数が短時間（600ms以内）に2回以上発生した場合のみトリガー
    const double shakeThreshold = 22.0;

    _accelerometerSubscription = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        if (_isCapturing || _isFeedbackDialogOpen || _overlayMode != _SnappyOverlayMode.none) return;

        // 加速度ベクトル長（G-force）を算出
        final double gForce = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        if (gForce > shakeThreshold) {
          final now = DateTime.now();
          final currentSignX = event.x.abs() > 8.0 ? (event.x > 0 ? 1.0 : -1.0) : 0.0;
          final currentSignY = event.y.abs() > 8.0 ? (event.y > 0 ? 1.0 : -1.0) : 0.0;

          // 前回のフリップから600ms以上経過していたらカウントをリセット
          if (_firstFlipTime == null || now.difference(_firstFlipTime!) > const Duration(milliseconds: 600)) {
            _shakeFlipCount = 1;
            _firstFlipTime = now;
            _lastSignX = currentSignX;
            _lastSignY = currentSignY;
          } else {
            // X軸またはY軸で急激な向きの反転（正負の切り替わり＝手首の往復運動）を検知
            final bool isReversedX = (currentSignX != 0.0 && _lastSignX != 0.0 && currentSignX != _lastSignX);
            final bool isReversedY = (currentSignY != 0.0 && _lastSignY != 0.0 && currentSignY != _lastSignY);

            if (isReversedX || isReversedY) {
              _shakeFlipCount++;
              _lastSignX = currentSignX != 0.0 ? currentSignX : _lastSignX;
              _lastSignY = currentSignY != 0.0 ? currentSignY : _lastSignY;

              // 2回以上の急峻な往復（フリップ）を確認した時点で本物の「シェイク」と認定
              if (_shakeFlipCount >= 2) {
                _shakeFlipCount = 0;
                _firstFlipTime = null;

                // チャタリング防止（前回の撮影トリガーから2秒以上経過している場合のみ実行）
                if (_lastShakeTime == null || now.difference(_lastShakeTime!) > const Duration(seconds: 2)) {
                  _lastShakeTime = now;
                  SnappySnag._log('📱 SnappySnag: Genuine device shake detected (gForce: ${gForce.toStringAsFixed(1)}). Triggering capture.');
                  _triggerCapture();
                }
              }
            }
          }
        }
      },
      onError: (error) {
        SnappySnag._log('⚠️ SnappySnag Accelerometer Error: $error');
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _devPasscodeInputController.dispose();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    final isUserMode = SnappySnag().mode == SnappySnagMode.user;
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // ユーザーモード（一般ユーザー）の場合は技術的・内部的なダイアログを出さず、
    // 親切な案内トースト/SnackBarのみを表示して不安を与えない
    if (isUserMode) {
      SnappySnag._log('⚠️ SnappySnag [UserMode] Suppressed error dialog: $message');
      ScaffoldMessenger.of(targetContext).showSnackBar(
        SnackBar(
          content: Text(_SdkLocale.userModeUnavailable),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

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

  /// パスコードを検証し、正しければピン一覧を更新して true を返す。不正なら false を返す。
  Future<bool> _verifyDevPasscodeAndFetch(String code) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) return false;

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/get-existing-feedbacks'
        '?screen_class_name=${Uri.encodeComponent(_drawingScreenClassName)}'
        '&screen_signature=${Uri.encodeComponent(_drawingScreenSignature)}';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'x-snappy-api-key': apiKey,
          'x-snappy-package-name': SnappySnag()._packageName ?? '',
          if (SnappySnag().reporterEmail != null && SnappySnag().reporterEmail!.isNotEmpty)
            'x-snappy-reporter-email': SnappySnag().reporterEmail!,
          'x-snappy-dev-passcode': code,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isVerified = data['is_passcode_verified'] == true;
        if (isVerified) {
          SnappySnag().setDevPasscode(code);
          if (data['is_dev_chat_enabled'] != null) {
            SnappySnag()._isDevChatEnabled = data['is_dev_chat_enabled'] == true;
          }
          final duplicates = (data['duplicates'] as List<dynamic>?) ?? [];
          _updateExistingFeedbacksState(duplicates);
          return true;
        }
      }
    } catch (e) {
      SnappySnag._log('❌ SnappySnag Dev Passcode Verify Error: $e');
    }
    return false;
  }

  Future<void> _submitDevPasscode() async {
    final code = _devPasscodeInputController.text.trim();
    if (code.length != 4) {
      setState(() {
        _devPasscodeErrorMessage = _SdkLocale.devPasscodeInvalid;
      });
      return;
    }

    setState(() {
      _isVerifyingDevPasscode = true;
      _devPasscodeErrorMessage = null;
    });

    final success = await _verifyDevPasscodeAndFetch(code);

    if (!mounted) return;

    if (success) {
      setState(() {
        _isVerifyingDevPasscode = false;
        _isDevPasscodeDialogOpen = false;
        _devPasscodeErrorMessage = null;
        _devPasscodeInputController.clear();
        _showAllScreenPinsModal = true;
      });
    } else {
      setState(() {
        _isVerifyingDevPasscode = false;
        _devPasscodeErrorMessage = _SdkLocale.devPasscodeInvalid;
      });
    }
  }

  Future<void> _triggerCapture() async {
    final isDemo = SnappySnag().isDemoMode;
    final apiKey = SnappySnag()._apiKey;

    if (!isDemo && (apiKey == null || apiKey.trim().isEmpty)) {
      _showErrorDialog(
        'SnappySnag is not properly configured. Please check that apiKey is set during initialization.',
      );
      return;
    }

    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // ★ 下書きチェック: 保存された下書きが存在するかローカル（通信なし）で確認
    final hasDraft = await _SnappyDraftData.hasDraft();
    if (hasDraft && mounted && targetContext.mounted) {
      final resume = await showDialog<bool>(
        context: targetContext,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E38)),
          ),
          title: Row(
            children: [
              const Icon(Icons.edit_note, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                _SdkLocale.draftFoundTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            _SdkLocale.draftFoundContent,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                _SdkLocale.discardAndNewCapture,
                style: const TextStyle(color: Colors.redAccent),
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
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(
                _SdkLocale.resumeDraft,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (resume == true) {
        // 下書きを読み込んで復元
        final draft = await _SnappyDraftData.load();
        if (draft != null && mounted) {
          setState(() {
            _isCapturing = false;
            _capturedImageForFreeze = null;
            _isFeedbackDialogOpen = true;
          });
          try {
            // ★ 下書き再開時はサーバーリクエストを行わず、保存時点のキャッシュを使用する
            // これによりオフライン環境でも即座に再開でき、「全指摘一覧」ボタンも正しく表示される
            final isUserMode = SnappySnag().mode == SnappySnagMode.user || draft.isDevChatEnabled == false;
            final existingFeedbacksForDraft = isUserMode ? <dynamic>[] : draft.existingFeedbacks;
            // キャッシュ済みの isDevChatEnabled を復元する
            SnappySnag()._isDevChatEnabled = draft.isDevChatEnabled;

            await _startDrawingFlow(
              draft.imageBytes,
              draft.widgetTree,
              screenClassName: draft.screenClassName,
              screenSignature: draft.screenSignature,
              initialCustomPoints: draft.drawingPoints,
              initialPins: draft.pins,
              initialMemo: draft.memo,
              initialAspectRatio: draft.drawingAspectRatio,
              existingFeedbacks: existingFeedbacksForDraft,
            );
          } finally {
            if (mounted) {
              setState(() => _isFeedbackDialogOpen = false);
            }
          }
          return;
        }
      } else {
        // 破棄して新規撮影を選択した場合、下書きを即時消去
        await _SnappyDraftData.clear();
        // ダイアログのポップ（破棄アニメーション）が完全に完了し、
        // 画面上からダイアログが消去されるのを待機してから新規キャプチャを開始する
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // === 【超高速先行キャプチャ】画面遷移に備え、ボタンタップしたその瞬間のデータを即座にフリーズ ===
    final Map<String, dynamic> widgetTree = SnappySnag().enableWidgetTree
        ? WidgetTreeDumper.dump(
            targetContext,
          )
        : <String, dynamic>{};
    final String screenClassName = WidgetTreeDumper.findScreenName(
      targetContext,
    );
    final String screenSignature = WidgetTreeDumper.findScreenSignature(
      targetContext,
      screenClassName,
    );
    // パスワード等の機密フィールドの絶対座標を自動抽出
    final List<Rect> sensitiveBounds = WidgetTreeDumper.findSensitiveFieldBounds(
      targetContext,
    );
    SnappySnag._log('🎬 SnappySnag: Captured Screen ID: $screenClassName, Signature: $screenSignature, Sensitive Areas: ${sensitiveBounds.length}');

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
        // ★ 認証＆有効性の事前検証:
        // モードに関わらずサーバーと通信して API Key と Package Name の整合性を検証する。
        // 不正なキーやパッケージ不一致（401/403）があればここで SnappySnagException がスローされ、
        // ユーザーにお絵描きやメモの手間をかけさせる前にエラーを検知・停止できる。
        final fetched = await _fetchExistingFeedbacks(screenClassName, screenSignature);
        final isUserMode = SnappySnag().mode == SnappySnagMode.user || SnappySnag().isDevChatEnabled == false;
        final duplicates = isUserMode ? <dynamic>[] : fetched;
        _hideLoadingOverlay();
        if (!mounted) return;

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
            existingFeedbacks: duplicates,
          );
        } finally {
          if (mounted) {
            setState(() => _isFeedbackDialogOpen = false);
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
    if (SnappySnag().isDemoMode) {
      SnappySnag._log('🎯 [SnappySnag Demo] Skipping server validation for existing feedbacks.');
      return [];
    }

    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) throw SnappySnagException('API Key is not configured.');

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/get-existing-feedbacks'
        '?screen_class_name=${Uri.encodeComponent(screenClassName)}'
        '&screen_signature=${Uri.encodeComponent(screenSignature)}';

    try {
      final devPasscode = SnappySnag().devPasscode;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'x-snappy-api-key': apiKey,
          'x-snappy-package-name': SnappySnag()._packageName ?? '',
          if (SnappySnag().reporterEmail != null && SnappySnag().reporterEmail!.isNotEmpty)
            'x-snappy-reporter-email': SnappySnag().reporterEmail!,
          if (devPasscode != null && devPasscode.isNotEmpty)
            'x-snappy-dev-passcode': devPasscode,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['is_dev_chat_enabled'] != null) {
          SnappySnag()._isDevChatEnabled = data['is_dev_chat_enabled'] == true;
        }
        if (data['requires_passcode'] != null) {
          _requiresPasscode = data['requires_passcode'] == true;
        }
        final bool isPasscodeRejected = devPasscode != null &&
            (data['is_passcode_verified'] == false ||
             (data['requires_passcode'] == true && data['is_dev_chat_enabled'] == false) ||
             (data['requires_passcode'] == true && data['is_passcode_verified'] != true));
        if (isPasscodeRejected) {
          SnappySnag().clearDevPasscode();
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
      SnappySnag._log('❌ SnappySnag Fetch Duplicates Error: $e');
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
      SnappySnag._log('❌ SnappySnag Fetch Comments Error: $e');
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
      SnappySnag._log('❌ SnappySnag Post Comment Error: $e');
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
    List<SnappyPin> pins = const [],
    required String screenClassName,
    required String screenSignature,
  }) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) {
      SnappySnag._log('❌ SnappySnag Error: API Key is not configured.');
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
          'widget_tree': (SnappySnag().enableWidgetTree && (_includeAccountAndDiagnostics || SnappySnag().mode != SnappySnagMode.user)) ? widgetTree : <String, dynamic>{},
          'memo': memo,
          'pins': pins.map((p) => p.toJson()).toList(),
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

      SnappySnag._log('🌐 SnappySnag HTTP Response: ${response.statusCode}');
      String? errorMessage;
      if (response.statusCode != 200) {
        try {
          final Map<String, dynamic> body = jsonDecode(response.body);
          errorMessage = body['error'] as String?;
        } catch (_) {}
      }
      return _FeedbackResponse(response.statusCode, errorMessage);
    } catch (e) {
      SnappySnag._log('❌ SnappySnag Network Error: $e');
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
    List<DrawingPoint>? initialCustomPoints,
    List<SnappyPin>? initialPins,
    String? initialMemo,
    double? initialAspectRatio,
    List<dynamic>? existingFeedbacks,
  }) async {
    if (!mounted) return;
    _drawingCompleter = Completer<void>();
    final mediaSize = MediaQuery.of(context).size;
    final capturedAspect = initialAspectRatio ?? (mediaSize.height > 0 ? (mediaSize.width / mediaSize.height) : (9 / 16));

    // パスワード等の機密フィールドを自動検出して初期マスクポイントに追加
    final List<DrawingPoint> initialPoints = [];
    if (initialCustomPoints != null) {
      initialPoints.addAll(initialCustomPoints);
    } else if (sensitiveBounds != null && sensitiveBounds.isNotEmpty) {
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

    final parsedExistingFeedbacks = existingFeedbacks ?? <dynamic>[];

    setState(() {
      _drawingImageBytes = imageBytes;
      _drawingWidgetTree = widgetTree;
      _drawingScreenClassName = screenClassName;
      _drawingScreenSignature = screenSignature;
      _drawingPoints = initialPoints;
      _pins = initialPins != null ? List<SnappyPin>.from(initialPins) : [];
      _undoStack.clear();
      _redoStack.clear();
      _editingPin = null;
      _updateExistingFeedbacksState(parsedExistingFeedbacks);
      _showAllScreenPinsModal = false;
      _activeTool = SnappyDrawingTool.pin;
      _isSendingFeedback = false;
      _isMemoOpen = false;
      _isPrivacyConfirmOpen = false;
      _isCancelDraftConfirmOpen = false;
      _isFailedSendDraftConfirmOpen = false;
      _isClearConfirmOpen = false;
      _isDevPasscodeDialogOpen = false;
      _feedbackMemoController.text = initialMemo ?? '';
      _drawingAspectRatio = capturedAspect;
      _overlayMode = _SnappyOverlayMode.drawing;
    });
    return _drawingCompleter!.future;
  }

  /// サーバーから取得した指摘一覧データをパースしてStateを更新する
  void _updateExistingFeedbacksState(List<dynamic> feedbacks) {
    final parsedExistingFeedbacks = feedbacks;
    final List<ExistingPinItem> parsedExistingPins = [];
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
    final targetRenderBox = targetContext.findRenderObject() as RenderBox?;
    final targetOrigin = (targetRenderBox != null && targetRenderBox.attached)
        ? targetRenderBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final mediaSize = MediaQuery.maybeOf(context)?.size ?? Size.zero;
    final targetSize = (targetRenderBox != null && targetRenderBox.attached && targetRenderBox.hasSize)
        ? targetRenderBox.size
        : (MediaQuery.maybeOf(targetContext)?.size ?? mediaSize);

    for (final fb in parsedExistingFeedbacks) {
      final feedbackId = fb['id']?.toString() ?? '';
      final userMemo = fb['user_memo']?.toString() ?? '';
      final severity = fb['severity']?.toString() ?? 'unassessed';
      final rawScreenshot = fb['screenshot_url']?.toString();

      String? resolvedScreenshotUrl;
      if (rawScreenshot != null && rawScreenshot.trim().isNotEmpty) {
        final trimmed = rawScreenshot.trim();
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          resolvedScreenshotUrl = trimmed;
        } else {
          final cleanPath = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
          resolvedScreenshotUrl = '${SnappySnag().supabaseUrl}/storage/v1/object/public/feedback-assets/$cleanPath';
        }
      }

      final rawPins = fb['pins'];
      if (rawPins is List) {
        for (final p in rawPins) {
          if (p is Map<String, dynamic>) {
            final pin = SnappyPin.fromJson(p);
            if (!pin.isActive) continue;

            Offset? resolvedRatio;
            if (pin.target != null) {
              try {
                final resolvedPos = WidgetTreeDumper.resolveTargetPosition(
                  targetContext,
                  pin.target!,
                  fallbackPosition: Offset(pin.xRatio, pin.yRatio),
                );
                if (resolvedPos != null && targetSize.width > 0 && targetSize.height > 0) {
                  resolvedRatio = Offset(
                    ((resolvedPos.dx - targetOrigin.dx) / targetSize.width).clamp(0.0, 1.0),
                    ((resolvedPos.dy - targetOrigin.dy) / targetSize.height).clamp(0.0, 1.0),
                  );
                }
              } catch (e) {
                SnappySnag._log('⚠️ SnappySnag: Failed to resolve target position: $e');
              }
            }
            parsedExistingPins.add(
              ExistingPinItem(
                feedbackId: feedbackId,
                userMemo: userMemo,
                severity: severity,
                pin: pin,
                resolvedRatio: resolvedRatio,
                screenshotUrl: resolvedScreenshotUrl,
              ),
            );
          }
        }
      }
    }

    final List<ExistingSectionItem> parsedExistingSections = [];
    final Map<String, List<ExistingPinItem>> sectionPinGroups = {};
    final Map<String, Rect> sectionRects = {};
    final Map<String, String> sectionNames = {};

    for (final item in parsedExistingPins) {
      final target = item.pin.target;
      if (target != null) {
        try {
          final rect = WidgetTreeDumper.resolveTargetRect(
            targetContext,
            target,
            fallbackPosition: Offset(item.pin.xRatio, item.pin.yRatio),
          );
          if (rect != null) {
            final groupKey = '${target.widgetType}_${target.widgetKey ?? ""}_${(rect.left / 10).round()}_${(rect.top / 10).round()}';
            sectionPinGroups.putIfAbsent(groupKey, () => []).add(item);
            sectionRects[groupKey] = rect;
            final label = (target.widgetText != null && target.widgetText!.isNotEmpty)
                ? '${target.widgetType} ("${target.widgetText}")'
                : target.widgetType;
            sectionNames[groupKey] = label;
          }
        } catch (e) {
          SnappySnag._log('⚠️ SnappySnag: Error resolving target section rect: $e');
        }
      }
    }

    final List<ExistingSectionItem> rawSections = [];
    sectionPinGroups.forEach((key, pinList) {
      final rect = sectionRects[key]!;
      final name = sectionNames[key]!;
      rawSections.add(
        ExistingSectionItem(
          id: key,
          sectionName: name,
          screenRect: rect,
          pins: pinList,
        ),
      );
    });

    final double screenTotalArea = (targetSize.width > 0 && targetSize.height > 0)
        ? (targetSize.width * targetSize.height)
        : (mediaSize.width * mediaSize.height);

    rawSections.sort((a, b) {
      final areaA = a.screenRect.width * a.screenRect.height;
      final areaB = b.screenRect.width * b.screenRect.height;
      return areaB.compareTo(areaA);
    });

    final List<ExistingSectionItem> mergedSections = [];
    for (final sec in rawSections) {
      bool mergedIntoParent = false;
      final childArea = sec.screenRect.width * sec.screenRect.height;

      for (int i = 0; i < mergedSections.length; i++) {
        final parent = mergedSections[i];
        final parentRect = parent.screenRect;
        final childRect = sec.screenRect;
        final parentArea = parentRect.width * parentRect.height;

        final isParentTooHuge = screenTotalArea > 0 && (parentArea / screenTotalArea) >= 0.5;
        if (isParentTooHuge) {
          continue;
        }

        final centerInParent = parentRect.contains(childRect.center);
        final overlapLeft = max(parentRect.left, childRect.left);
        final overlapTop = max(parentRect.top, childRect.top);
        final overlapRight = min(parentRect.right, childRect.right);
        final overlapBottom = min(parentRect.bottom, childRect.bottom);
        final overlapWidth = max(0.0, overlapRight - overlapLeft);
        final overlapHeight = max(0.0, overlapBottom - overlapTop);
        final overlapArea = overlapWidth * overlapHeight;
        final overlapRatio = childArea > 0 ? (overlapArea / childArea) : 0.0;

        if (centerInParent || overlapRatio >= 0.7) {
          final updatedPins = List<ExistingPinItem>.from(parent.pins)..addAll(sec.pins);
          mergedSections[i] = ExistingSectionItem(
            id: parent.id,
            sectionName: parent.sectionName,
            screenRect: parent.screenRect,
            pins: updatedPins,
          );
          mergedIntoParent = true;
          break;
        }
      }

      if (!mergedIntoParent) {
        mergedSections.add(sec);
      }
    }

    mergedSections.sort((a, b) {
      final areaA = a.screenRect.width * a.screenRect.height;
      final areaB = b.screenRect.width * b.screenRect.height;
      return areaB.compareTo(areaA);
    });

    parsedExistingSections.addAll(mergedSections);

    _existingFeedbacks = parsedExistingFeedbacks;
    _existingPins = parsedExistingPins;
    _existingSections = parsedExistingSections;
    _showExistingPins = _enableSectionHighlights;
    _selectedSection = null;
    _previewingPin = null;
  }

  /// ネットワーク画像の実際のピクセルサイズを取得する（キャッシュ対応）
  /// ピン座標計算で _drawingAspectRatio の代わりに使用し、EXIF回転等による誤差を防ぐ
  final Map<String, Size> _imageSizeCache = {};
  Future<Size> _resolveImageSize(String url) async {
    if (_imageSizeCache.containsKey(url)) return _imageSizeCache[url]!;
    final completer = Completer<Size>();
    final imageProvider = NetworkImage(url);
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        _imageSizeCache[url] = size;
        if (!completer.isCompleted) completer.complete(size);
        stream.removeListener(listener);
      },
      onError: (dynamic exception, StackTrace? stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(exception, stackTrace);
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  void _renumberPins() {
    for (int i = 0; i < _pins.length; i++) {
      _pins[i] = _pins[i].copyWith(number: i + 1);
    }
  }

  Future<void> _cancelDrawingFlow() async {
    // ユーザーがピン留め、モザイクを追加しているか判定
    final hasUserEdits = _pins.isNotEmpty || _drawingPoints.any((p) => p.rect == null);

    if (hasUserEdits && mounted) {
      // 全画面OverlayEntryの内側で確実に最前面に表示するため、インラインモーダルを開く
      setState(() {
        _isCancelDraftConfirmOpen = true;
      });
      return;
    }

    _closeDrawingOverlay();
  }

  void _closeDrawingOverlay() {
    setState(() {
      _isCancelDraftConfirmOpen = false;
      _isFailedSendDraftConfirmOpen = false;
      _isDevPasscodeDialogOpen = false;
      _isVerifyingDevPasscode = false;
      _overlayMode = _SnappyOverlayMode.none;
      _isCapturing = false;
    });
    _drawingCompleter?.complete();
  }

  Future<void> _sendFeedbackInlineFlow() async {
    // ピンが1つ以上あり、かつコメントが存在するか確認
    final validPins = _pins.where((p) => p.comment.trim().isNotEmpty).toList();
    if (validPins.isEmpty) {
      if (mounted) {
        final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          SnackBar(
            content: Text(_SdkLocale.pinRequiredSnackBar),
            backgroundColor: Colors.orange,
          ),
        );
      }
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
    // ピンのコメント一覧から全体の概要テキストを自動合成（下位互換およびIssue概要用）
    final validPins = _pins.where((p) => p.comment.trim().isNotEmpty).toList();
    final memo = validPins.map((p) => '【Pin ${p.number}】${p.comment.trim()}').join('\n');
    setState(() {
      _isPrivacyConfirmOpen = false;
      _isSendingFeedback = true;
    });

    // 1. モザイクマスキングのみが載ったキャンバスを再キャプチャする（ピンや赤ペンは画像に焼き込まない）
    final Uint8List? editedBytes = await _canvasScreenshotController.capture();
    final finalBytes = editedBytes ?? _drawingImageBytes!;

    // 2. 送信処理（デモモード時はローカルシミュレーション）
    final _FeedbackResponse feedbackRes;
    if (SnappySnag().isDemoMode) {
      debugPrint('\n======================================================================');
      debugPrint('🎯 [SnappySnag Demo Mode] Feedback Captured Successfully!');
      debugPrint('======================================================================');
      debugPrint('📍 Screen: $_drawingScreenClassName');
      debugPrint('💬 Memo:\n$memo');
      debugPrint('📌 Pins count: ${_pins.length}');
      for (final p in _pins) {
        debugPrint('  - Pin #${p.number}: "${p.comment}" (x: ${p.xRatio.toStringAsFixed(2)}, y: ${p.yRatio.toStringAsFixed(2)}, widget: ${p.target?.widgetType ?? "Unknown"})');
      }
      debugPrint('🌳 Widget Tree: ${_drawingWidgetTree.keys.join(", ")} (${_drawingWidgetTree.length} nodes)');
      debugPrint('----------------------------------------------------------------------');
      debugPrint('👉 To sync feedback to GitHub Issues and enable AI auto-fix,');
      debugPrint('   get your free API key at: https://snappysnag.com');
      debugPrint('======================================================================\n');

      // 擬似的に通信時間を設けてUXを滑らかにする
      await Future.delayed(const Duration(milliseconds: 350));
      feedbackRes = _FeedbackResponse(200, null);
    } else {
      feedbackRes = await _sendFeedback(
        imageBytes: finalBytes,
        widgetTree: _drawingWidgetTree,
        memo: memo,
        pins: _pins,
        screenClassName: _drawingScreenClassName,
        screenSignature: _drawingScreenSignature,
      );
    }

    final success = feedbackRes.statusCode == 200;

    if (success) {
      // 送信成功時は下書きをクリアして閉じる
      await _SnappyDraftData.clear();
      setState(() {
        _overlayMode = _SnappyOverlayMode.none;
        _isCapturing = false;
      });
      _drawingCompleter?.complete();
    } else {
      // 送信失敗時は入力内容・描画内容を破棄せず、再試行できるようにモーダルを維持する
      setState(() {
        _isSendingFeedback = false;
      });
    }

    // トースト等の通知
    if (mounted) {
      final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
      final isUserMode = SnappySnag().mode == SnappySnagMode.user;
      final isDemo = SnappySnag().isDemoMode;
      String message = isDemo ? _SdkLocale.statusDemoSuccess : _SdkLocale.statusSuccess;
      if (!success) {
        if (isUserMode) {
          // 一般ユーザー向け: 不安を与えない親切な共通案内
          message = _SdkLocale.statusGenericError;
          SnappySnag._log('⚠️ SnappySnag [UserMode] Submit failed (code: ${feedbackRes.statusCode}, msg: ${feedbackRes.errorMessage})');
        } else {
          // 開発者モード向け: 原因特定のための詳細メッセージ
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
      }

      ScaffoldMessenger.of(messengerContext).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      // 送信失敗時の下書き保存提案（インラインモーダルで確実に最前面表示）
      if (!success && mounted) {
        setState(() {
          _isFailedSendDraftConfirmOpen = true;
        });
      }
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
      SnappySnag._log('⚠️ Failed to compress screenshot: $e');
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

                                return Container(
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
                                    ],
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
                            if (SnappySnag().mode == SnappySnagMode.dev && (_existingPins.isNotEmpty || _requiresPasscode))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: _isLoadingAllScreenPins ? null : () async {
                                    if (_requiresPasscode) {
                                      if (SnappySnag().devPasscode == null) {
                                        setState(() {
                                          _devPasscodeErrorMessage = null;
                                          _isVerifyingDevPasscode = false;
                                          _devPasscodeInputController.clear();
                                          _isDevPasscodeDialogOpen = true;
                                        });
                                        return;
                                      }

                                      // すでにパスコードが保持されている場合、最新の有効性を検証
                                      // ダッシュボードでパスコードが変更された場合、古いパスコードをクリアして再入力を促す
                                      setState(() {
                                        _isLoadingAllScreenPins = true;
                                      });
                                      try {
                                        final isValid = await _verifyDevPasscodeAndFetch(SnappySnag().devPasscode!);
                                        if (!isValid) {
                                          SnappySnag().clearDevPasscode();
                                          if (mounted) {
                                            setState(() {
                                              _devPasscodeErrorMessage = _SdkLocale.devPasscodeInvalid;
                                              _isVerifyingDevPasscode = false;
                                              _devPasscodeInputController.clear();
                                              _isDevPasscodeDialogOpen = true;
                                            });
                                          }
                                          return;
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() {
                                            _isLoadingAllScreenPins = false;
                                          });
                                        }
                                      }
                                    }

                                    setState(() {
                                      _showAllScreenPinsModal = true;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white24,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isLoadingAllScreenPins)
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white70,
                                            ),
                                          )
                                        else
                                          Icon(
                                            _requiresPasscode && SnappySnag().devPasscode == null
                                                ? Icons.lock_outline
                                                : Icons.list_alt,
                                            size: 14,
                                            color: Colors.white70,
                                          ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isLoadingAllScreenPins
                                              ? _SdkLocale.devPasscodeChecking
                                              : (_requiresPasscode && SnappySnag().devPasscode == null
                                                  ? _SdkLocale.allScreenPinsBtn
                                                  : '${_SdkLocale.allScreenPinsBtn} (${_existingPins.length})'),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            else if (SnappySnag().mode != SnappySnagMode.dev && _existingPins.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    setState(() {
                                      _showAllScreenPinsModal = true;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white24,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.list_alt,
                                          size: 14,
                                          color: Colors.white70,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${_SdkLocale.allScreenPinsBtn} (${_existingPins.length})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (_enableSectionHighlights && _existingSections.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    setState(() {
                                      _showExistingPins = !_showExistingPins;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _showExistingPins
                                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _showExistingPins
                                            ? const Color(0xFF8B5CF6)
                                            : Colors.white38,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _showExistingPins ? Icons.layers : Icons.layers_outlined,
                                          size: 14,
                                          color: _showExistingPins
                                              ? const Color(0xFFA78BFA)
                                              : Colors.white60,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${_SdkLocale.existingPinsToggle} (${_existingSections.length})',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _showExistingPins
                                                ? const Color(0xFFA78BFA)
                                                : Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
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
                                    child: LayoutBuilder(
                                      builder: (layoutContext, constraints) {
                                        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                                        return Stack(
                                          children: [
                                            // 1. スクショ保存対象（背景画像 + モザイクのみ）
                                            // ※ ピンはスクショ画像自体には焼き込まず、メタデータとして座標とコメントを保存・連携する
                                            Positioned.fill(
                                              child: Screenshot(
                                                controller: _canvasScreenshotController,
                                                child: Stack(
                                                  children: [
                                                    Positioned.fill(
                                                      child: Image.memory(
                                                        _drawingImageBytes!,
                                                        fit: BoxFit.contain,
                                                      ),
                                                    ),
                                                    Positioned.fill(
                                                      child: CustomPaint(
                                                        painter: DrawingPainter(points: _drawingPoints),
                                                        size: Size.infinite,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // 2. お絵描き・ピン配置ジェスチャー受付レイヤー
                                            Positioned.fill(
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.translucent,
                                                onTapUp: (details) {
                                                  if (_isSendingFeedback || _isMemoOpen || _editingPin != null) return;
                                                  if (_activeTool == SnappyDrawingTool.pin) {
                                                    // ピン配置の上限チェック（最大5個）
                                                    if (_pins.length >= 5) {
                                                      final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
                                                      ScaffoldMessenger.of(messengerContext).showSnackBar(
                                                        SnackBar(
                                                          content: Text(_SdkLocale.pinLimitReached),
                                                          duration: const Duration(seconds: 2),
                                                          behavior: SnackBarBehavior.floating,
                                                          backgroundColor: Colors.black87,
                                                        ),
                                                      );
                                                      return;
                                                    }

                                                    final double xRatio = (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0);
                                                    final double yRatio = (details.localPosition.dy / canvasSize.height).clamp(0.0, 1.0);
                                                    final int nextNumber = _pins.isEmpty
                                                        ? 1
                                                        : (_pins.map((p) => p.number).reduce((a, b) => a > b ? a : b) + 1);
                                                    // タップ座標に対応する最前面UI要素のアンカー情報を特定
                                                    // ※ overlayContext ではなくアプリ画面（targetContext）のツリーを走査し、
                                                    // キャンバス比率 (xRatio, yRatio) からアプリ画面のグローバル座標に変換して渡す
                                                    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
                                                    final targetRenderBox = targetContext.findRenderObject() as RenderBox?;
                                                    final targetOrigin = (targetRenderBox != null && targetRenderBox.attached)
                                                        ? targetRenderBox.localToGlobal(Offset.zero)
                                                        : Offset.zero;
                                                    final targetSize = (targetRenderBox != null && targetRenderBox.attached && targetRenderBox.hasSize)
                                                        ? targetRenderBox.size
                                                        : MediaQuery.of(targetContext).size;
                                                    final screenGlobalPos = Offset(
                                                      targetOrigin.dx + (xRatio * targetSize.width),
                                                      targetOrigin.dy + (yRatio * targetSize.height),
                                                    );
                                                    final detectedTarget = WidgetTreeDumper.findTargetAtPosition(
                                                      targetContext,
                                                      screenGlobalPos,
                                                    );
                                                    if (detectedTarget != null) {
                                                      SnappySnag._log('🎯 SnappySnag: Pin placed on element -> [${detectedTarget.widgetType}] (Text: "${detectedTarget.widgetText ?? ''}", Key: "${detectedTarget.widgetKey ?? ''}") at screen pos: $screenGlobalPos');
                                                    } else {
                                                      SnappySnag._log('⚠️ SnappySnag: No specific UI element detected at screen pos: $screenGlobalPos. Falling back to relative coordinate.');
                                                    }
                                                    final newPin = SnappyPin(
                                                      id: 'pin_${DateTime.now().millisecondsSinceEpoch}',
                                                      number: nextNumber,
                                                      xRatio: xRatio,
                                                      yRatio: yRatio,
                                                      comment: '',
                                                      target: detectedTarget,
                                                    );
                                                    setState(() {
                                                      _pins.add(newPin);
                                                      _editingPin = newPin;
                                                      _pinCommentController.text = '';
                                                    });
                                                  }
                                                },
                                                onPanStart: (details) {
                                                  if (_isSendingFeedback || _isMemoOpen || _editingPin != null) return;
                                                  if (_activeTool != SnappyDrawingTool.mosaic) return;
                                                  setState(() {
                                                    const double strokeWidth = 24.0;
                                                    const Color color = Color(0xEE303036);
                                                    _drawingPoints.add(
                                                      DrawingPoint(
                                                        offsets: [details.localPosition],
                                                        color: color,
                                                        strokeWidth: strokeWidth,
                                                        tool: SnappyDrawingTool.mosaic,
                                                        recordedSize: canvasSize,
                                                      ),
                                                    );
                                                  });
                                                },
                                                onPanUpdate: (details) {
                                                  if (_isSendingFeedback || _isMemoOpen || _editingPin != null) return;
                                                  if (_activeTool != SnappyDrawingTool.mosaic) return;
                                                  setState(() {
                                                    if (_drawingPoints.isNotEmpty) {
                                                      _drawingPoints.last.offsets.add(details.localPosition);
                                                    }
                                                  });
                                                },
                                                onPanEnd: (details) {
                                                  if (_isSendingFeedback || _isMemoOpen || _editingPin != null) return;
                                                  if (_activeTool != SnappyDrawingTool.mosaic) return;
                                                  setState(() {
                                                    if (_drawingPoints.isNotEmpty) {
                                                      _drawingPoints.last.offsets.add(null);
                                                      // 1ストローク完了時点で履歴スタックに記録
                                                      _undoStack.add(_drawingPoints.last);
                                                      _redoStack.clear();
                                                    }
                                                  });
                                                },
                                              ),
                                            ),

                                            // 3. 過去指摘のあるセクション・ブロックのハイライト枠線表示（SnappySnagMode.dev かつ _enableSectionHighlights かつ _showExistingPins が有効な場合）
                                            if (_enableSectionHighlights && _showExistingPins)
                                              ..._existingSections.map((sec) {
                                                // アプリ画面座標からキャンバス内相対比率へマッピング
                                                final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
                                                final targetRenderBox = targetContext.findRenderObject() as RenderBox?;
                                                final targetOrigin = (targetRenderBox != null && targetRenderBox.attached)
                                                    ? targetRenderBox.localToGlobal(Offset.zero)
                                                    : Offset.zero;
                                                final targetSize = (targetRenderBox != null && targetRenderBox.attached && targetRenderBox.hasSize)
                                                    ? targetRenderBox.size
                                                    : (MediaQuery.maybeOf(targetContext)?.size ?? canvasSize);

                                                final double leftRatio = targetSize.width > 0
                                                    ? ((sec.screenRect.left - targetOrigin.dx) / targetSize.width).clamp(0.0, 1.0)
                                                    : 0.0;
                                                final double topRatio = targetSize.height > 0
                                                    ? ((sec.screenRect.top - targetOrigin.dy) / targetSize.height).clamp(0.0, 1.0)
                                                    : 0.0;
                                                final double widthRatio = targetSize.width > 0
                                                    ? (sec.screenRect.width / targetSize.width).clamp(0.0, 1.0)
                                                    : 0.0;
                                                final double heightRatio = targetSize.height > 0
                                                    ? (sec.screenRect.height / targetSize.height).clamp(0.0, 1.0)
                                                    : 0.0;

                                                final double pixelLeft = leftRatio * canvasSize.width;
                                                final double pixelTop = topRatio * canvasSize.height;
                                                final double pixelWidth = (widthRatio * canvasSize.width).clamp(32.0, canvasSize.width);
                                                final double pixelHeight = (heightRatio * canvasSize.height).clamp(24.0, canvasSize.height);

                                                return Positioned(
                                                  left: pixelLeft.clamp(0.0, canvasSize.width - 32),
                                                  top: pixelTop.clamp(0.0, canvasSize.height - 24),
                                                  width: pixelWidth.clamp(0.0, canvasSize.width - pixelLeft),
                                                  height: pixelHeight.clamp(0.0, canvasSize.height - pixelTop),
                                                  child: GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: () {
                                                      if (_isSendingFeedback || _isMemoOpen) return;
                                                      setState(() {
                                                        _selectedSection = sec;
                                                      });
                                                    },
                                                    child: Stack(
                                                      clipBehavior: Clip.none,
                                                      children: [
                                                        Container(
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(
                                                              color: const Color(0xFF8B5CF6),
                                                              width: 2.0,
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          top: -10,
                                                          right: 4,
                                                          child: Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF8B5CF6),
                                                              borderRadius: BorderRadius.circular(10),
                                                              border: Border.all(color: Colors.white, width: 1.5),
                                                              boxShadow: const [
                                                                BoxShadow(
                                                                  color: Colors.black45,
                                                                  blurRadius: 4,
                                                                  offset: Offset(0, 2),
                                                                ),
                                                              ],
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const Icon(Icons.comment, size: 10, color: Colors.white),
                                                                const SizedBox(width: 3),
                                                                Text(
                                                                  '${_SdkLocale.issueBadgePrefix}${sec.pins.length}${_SdkLocale.issueBadgeSuffix}',
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 10,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),

                                            // 4. ピンのオーバーレイ表示（画像には焼き込まれない）
                                            ..._pins.map((pin) {
                                              final pinPixelX = pin.xRatio * canvasSize.width;
                                              final pinPixelY = pin.yRatio * canvasSize.height;
                                              const pinSize = 34.0;

                                              return Positioned(
                                                left: (pinPixelX - pinSize / 2).clamp(0.0, canvasSize.width - pinSize),
                                                top: (pinPixelY - pinSize).clamp(0.0, canvasSize.height - pinSize),
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onTap: () {
                                                    if (_isSendingFeedback || _isMemoOpen) return;
                                                    setState(() {
                                                      _editingPin = pin;
                                                      _pinCommentController.text = pin.comment;
                                                    });
                                                  },
                                                  onPanStart: (details) {
                                                    if (_isSendingFeedback || _isMemoOpen || _editingPin != null) return;
                                                    _dragStartGlobal = details.globalPosition;
                                                    _dragStartPinX = pin.xRatio * canvasSize.width;
                                                    _dragStartPinY = pin.yRatio * canvasSize.height;
                                                  },
                                                  onPanUpdate: (details) {
                                                    if (_isSendingFeedback || _isMemoOpen || _editingPin != null) return;
                                                    if (_dragStartGlobal == null || _dragStartPinX == null || _dragStartPinY == null) return;
                                                    final dx = details.globalPosition.dx - _dragStartGlobal!.dx;
                                                    final dy = details.globalPosition.dy - _dragStartGlobal!.dy;
                                                    final newDx = (_dragStartPinX! + dx).clamp(0.0, canvasSize.width);
                                                    final newDy = (_dragStartPinY! + dy).clamp(0.0, canvasSize.height);
                                                    final newXRatio = (newDx / canvasSize.width).clamp(0.0, 1.0);
                                                    final newYRatio = (newDy / canvasSize.height).clamp(0.0, 1.0);

                                                    setState(() {
                                                      final idx = _pins.indexWhere((p) => p.id == pin.id);
                                                      if (idx != -1) {
                                                        _pins[idx] = pin.copyWith(xRatio: newXRatio, yRatio: newYRatio);
                                                      }
                                                    });
                                                  },
                                                  onPanEnd: (_) {
                                                    // ドラッグ移動完了時に移動先のUI要素アンカー情報を再取得・更新
                                                    if (_dragStartGlobal != null) {
                                                      final currentPin = _pins.firstWhere((p) => p.id == pin.id, orElse: () => pin);
                                                      final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
                                                      final targetRenderBox = targetContext.findRenderObject() as RenderBox?;
                                                      final targetOrigin = (targetRenderBox != null && targetRenderBox.attached)
                                                          ? targetRenderBox.localToGlobal(Offset.zero)
                                                          : Offset.zero;
                                                      final targetSize = (targetRenderBox != null && targetRenderBox.attached && targetRenderBox.hasSize)
                                                          ? targetRenderBox.size
                                                          : MediaQuery.of(targetContext).size;
                                                      final screenGlobalPos = Offset(
                                                        targetOrigin.dx + (currentPin.xRatio * targetSize.width),
                                                        targetOrigin.dy + (currentPin.yRatio * targetSize.height),
                                                      );
                                                      final newTarget = WidgetTreeDumper.findTargetAtPosition(
                                                        targetContext,
                                                        screenGlobalPos,
                                                      );
                                                      if (newTarget != null) {
                                                        SnappySnag._log('🎯 SnappySnag: Pin moved to element -> [${newTarget.widgetType}] (Text: "${newTarget.widgetText ?? ''}", Key: "${newTarget.widgetKey ?? ''}") at screen pos: $screenGlobalPos');
                                                      } else {
                                                        SnappySnag._log('⚠️ SnappySnag: Pin moved to relative coordinate (no specific element detected at $screenGlobalPos)');
                                                      }
                                                      setState(() {
                                                        final idx = _pins.indexWhere((p) => p.id == pin.id);
                                                        if (idx != -1) {
                                                          _pins[idx] = currentPin.copyWith(target: newTarget);
                                                        }
                                                      });
                                                    }
                                                    _dragStartGlobal = null;
                                                    _dragStartPinX = null;
                                                    _dragStartPinY = null;
                                                  },
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: pinSize,
                                                        height: pinSize,
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFF95738),
                                                          shape: BoxShape.circle,
                                                          border: Border.all(color: Colors.white, width: 2),
                                                          boxShadow: const [
                                                            BoxShadow(
                                                              color: Colors.black45,
                                                              blurRadius: 6,
                                                              offset: Offset(0, 3),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            '${pin.number}',
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        );
                                      },
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
                            // 1. ピン留めツール（デフォルト）
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.place,
                                    color: _activeTool == SnappyDrawingTool.pin
                                        ? const Color(0xFFF95738)
                                        : Colors.grey,
                                  ),
                                  tooltip: 'Pin Marker (Max 5)',
                                  onPressed: _isSendingFeedback
                                      ? null
                                      : () => setState(
                                            () => _activeTool = SnappyDrawingTool.pin,
                                          ),
                                ),
                                if (_pins.isNotEmpty)
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF95738),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${_pins.length}/5',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
                            const SizedBox(width: 8),
                            // 3. 元に戻す (Undo: 操作の時系列順)
                            IconButton(
                              icon: Icon(
                                Icons.undo,
                                color: (!_isSendingFeedback && _undoStack.isNotEmpty)
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                              tooltip: 'Undo',
                              onPressed: _isSendingFeedback || _undoStack.isEmpty
                                  ? null
                                  : () => setState(() {
                                        final last = _undoStack.removeLast();
                                        _redoStack.add(last);
                                        if (last is SnappyPin) {
                                          _pins.removeWhere((p) => p.id == last.id);
                                        } else if (last is DrawingPoint) {
                                          _drawingPoints.remove(last);
                                        }
                                      }),
                            ),
                            // 4. やり直す (Redo: undo した操作を復元)
                            IconButton(
                              icon: Icon(
                                Icons.redo,
                                color: (!_isSendingFeedback && _redoStack.isNotEmpty)
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                              tooltip: 'Redo',
                              onPressed: _isSendingFeedback || _redoStack.isEmpty
                                  ? null
                                  : () => setState(() {
                                        final next = _redoStack.removeLast();
                                        _undoStack.add(next);
                                        if (next is SnappyPin) {
                                          _pins.add(next);
                                        } else if (next is DrawingPoint) {
                                          _drawingPoints.add(next);
                                        }
                                      }),
                            ),
                            // 5. 全消去 (Clear) - 確認モーダルを経由
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: (!_isSendingFeedback && (_drawingPoints.isNotEmpty || _pins.isNotEmpty))
                                    ? Colors.redAccent
                                    : Colors.grey.shade700,
                              ),
                              tooltip: 'Clear',
                              onPressed: _isSendingFeedback || (_drawingPoints.isEmpty && _pins.isEmpty)
                                  ? null
                                  : () => setState(() => _isClearConfirmOpen = true),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3. ピンコメント入力用フローティングオーバーレイ
                    if (_editingPin != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, modalConstraints) {
                            final isLandscape = modalConstraints.maxWidth > modalConstraints.maxHeight;
                            return Container(
                              color: Colors.black.withValues(alpha: 0.75),
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: isLandscape ? 8 : 20,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: 480,
                                    maxHeight: isLandscape ? modalConstraints.maxHeight * 0.95 : 540,
                                  ),
                                  child: Card(
                                    color: Colors.grey.shade900,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: Colors.grey.shade800),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFFF95738),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      '${_editingPin!.number}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _SdkLocale.pinCommentTitle,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Spacer(),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                                  tooltip: _SdkLocale.delete,
                                                  onPressed: () {
                                                    setState(() {
                                                      _pins.removeWhere((p) => p.id == _editingPin!.id);
                                                      _renumberPins();
                                                      _editingPin = null;
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: _pinCommentController,
                                              maxLength: 500,
                                              maxLengthEnforcement: MaxLengthEnforcement.enforced,
                                              maxLines: isLandscape ? 2 : 4,
                                              autofocus: true,
                                              style: const TextStyle(color: Colors.white),
                                              decoration: InputDecoration(
                                                hintText: _SdkLocale.pinCommentHint,
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
                                                final updatedComment = _pinCommentController.text.trim();
                                                final editingId = _editingPin!.id;
                                                // 新規ピン判定: undoStack にまだ登録されていない場合のみ新規
                                                final isNewPin = !_undoStack.any((e) => e is SnappyPin && e.id == editingId);
                                                setState(() {
                                                  if (updatedComment.isEmpty) {
                                                    // コメントが空の場合はピンを削除（undoStackには積まない）
                                                    _pins.removeWhere((p) => p.id == editingId);
                                                    _renumberPins();
                                                  } else {
                                                    final idx = _pins.indexWhere((p) => p.id == editingId);
                                                    if (idx != -1) {
                                                      final finalPin = _editingPin!.copyWith(comment: updatedComment);
                                                      _pins[idx] = finalPin;
                                                      if (isNewPin) {
                                                        // 新規ピン: コメント確定時点で正しい内容を undoStack に記録
                                                        _undoStack.add(finalPin);
                                                        _redoStack.clear();
                                                      }
                                                      // 既存ピンの編集は undoStack 対象外（移動と同様）
                                                    }
                                                  }
                                                  _editingPin = null;
                                                });
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
                            );
                          },
                        ),
                      ),



                    // 4-A. セクション詳細モーダル（タップしたセクション・ブロック内の指摘一覧）
                    if (_selectedSection != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, modalConstraints) {
                            final isLandscape = modalConstraints.maxWidth > modalConstraints.maxHeight;
                            return Container(
                              color: Colors.black.withValues(alpha: 0.75),
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: isLandscape ? 8 : 20,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: 420,
                                    maxHeight: isLandscape ? modalConstraints.maxHeight * 0.95 : 540,
                                  ),
                                  child: Card(
                                    color: Colors.grey.shade900,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF8B5CF6),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.layers, color: Colors.white, size: 16),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _selectedSection!.sectionName,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${_SdkLocale.sectionPinsTitle} (${_selectedSection!.pins.length}${_SdkLocale.issueBadgeSuffix})',
                                                      style: TextStyle(
                                                        color: Colors.grey.shade400,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                                onPressed: () {
                                                  setState(() {
                                                    _selectedSection = null;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Flexible(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(maxHeight: isLandscape ? 160 : 280),
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                itemCount: _selectedSection!.pins.length,
                                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                                itemBuilder: (context, index) {
                                                  final item = _selectedSection!.pins[index];
                                                  final commentText = item.pin.comment.trim().isNotEmpty
                                                      ? item.pin.comment.trim()
                                                      : _SdkLocale.noCommentForPin;
                                                  return InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        _previewingPin = item;
                                                      });
                                                    },
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withValues(alpha: 0.05),
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(color: Colors.white12),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            width: 24,
                                                            height: 24,
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFF8B5CF6),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: Center(
                                                              child: Text(
                                                                '${item.pin.number}',
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 10),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text(
                                                                  commentText,
                                                                  maxLines: 2,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 13,
                                                                  ),
                                                                ),
                                                                if (item.screenshotUrl != null)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(top: 2),
                                                                    child: Row(
                                                                      children: [
                                                                        const Icon(Icons.image_outlined, size: 10, color: Color(0xFFA78BFA)),
                                                                        const SizedBox(width: 3),
                                                                        Text(
                                                                          _SdkLocale.previewOriginalScreenshot,
                                                                          style: const TextStyle(
                                                                            color: Color(0xFFA78BFA),
                                                                            fontSize: 10,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white70,
                                              side: const BorderSide(color: Colors.white24),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _selectedSection = null;
                                              });
                                            },
                                            child: Text(_SdkLocale.close),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // 4-B. この画面の全指摘一覧モーダル（AppBarの「全指摘一覧」ボタンから起動）
                    if (_showAllScreenPinsModal)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, modalConstraints) {
                            final isLandscape = modalConstraints.maxWidth > modalConstraints.maxHeight;
                            return Container(
                              color: Colors.black.withValues(alpha: 0.75),
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: isLandscape ? 8 : 20,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: 440,
                                    maxHeight: isLandscape ? modalConstraints.maxHeight * 0.95 : 560,
                                  ),
                                  child: Card(
                                    color: Colors.grey.shade900,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: const BorderSide(color: Colors.white24, width: 1.5),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.15),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.list_alt, color: Colors.white, size: 16),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _SdkLocale.allScreenPinsTitle,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _SdkLocale.allScreenPinsSub,
                                                      style: TextStyle(
                                                        color: Colors.grey.shade400,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                                onPressed: () {
                                                  setState(() {
                                                    _showAllScreenPinsModal = false;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Flexible(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(maxHeight: isLandscape ? 170 : 320),
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                itemCount: _existingPins.length,
                                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                                itemBuilder: (context, index) {
                                                  final item = _existingPins[index];
                                                  final commentText = item.pin.comment.trim().isNotEmpty
                                                      ? item.pin.comment.trim()
                                                      : _SdkLocale.noCommentForPin;
                                                  return InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        _previewingPin = item;
                                                      });
                                                    },
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withValues(alpha: 0.05),
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(color: Colors.white12),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            width: 24,
                                                            height: 24,
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFF8B5CF6),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: Center(
                                                              child: Text(
                                                                '${item.pin.number}',
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 10),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text(
                                                                  commentText,
                                                                  maxLines: 2,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 13,
                                                                  ),
                                                                ),
                                                                if (item.pin.target != null)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(top: 2),
                                                                    child: Text(
                                                                      '${_SdkLocale.elementAttachedBadge}: ${item.pin.target!.widgetType}',
                                                                      style: const TextStyle(
                                                                        color: Color(0xFFA78BFA),
                                                                        fontSize: 10,
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white70,
                                              side: const BorderSide(color: Colors.white24),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _showAllScreenPinsModal = false;
                                              });
                                            },
                                            child: Text(_SdkLocale.close),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // 4-C. 選択した指摘ピンの元スクショ ＆ ピン位置プレビューモーダル
                    if (_previewingPin != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, modalConstraints) {
                            final isLandscape = modalConstraints.maxWidth > modalConstraints.maxHeight;
                            return Container(
                              color: Colors.black.withValues(alpha: 0.88),
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: isLandscape ? 8 : 20,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: isLandscape ? 600 : 480,
                                    maxHeight: isLandscape ? modalConstraints.maxHeight * 0.96 : 680,
                                  ),
                                  child: Card(
                                    color: Colors.grey.shade900,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // ヘッダー（縦横共通）
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                                                onPressed: () {
                                                  setState(() {
                                                    _previewingPin = null;
                                                  });
                                                },
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  _SdkLocale.previewOriginalScreenshot,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                                onPressed: () {
                                                  setState(() {
                                                    _previewingPin = null;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                           if (isLandscape)
                                            // 横画面: 左（画像）＋ 右（コメント＋ボタン）の横並びレイアウト
                                            Expanded(
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  // 左側: スクショ画像エリア（実画像サイズでピン座標計算）
                                                  Expanded(
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(10),
                                                      child: Container(
                                                        color: Colors.black,
                                                        child: _previewingPin!.screenshotUrl != null && _previewingPin!.screenshotUrl!.isNotEmpty
                                                            ? LayoutBuilder(
                                                                builder: (context, constraints) {
                                                                  final pWidth = constraints.maxWidth;
                                                                  final pHeight = constraints.maxHeight;
                                                                  final pin = _previewingPin!.pin;
                                                                  const pinSize = 30.0;
                                                                  final url = _previewingPin!.screenshotUrl!;

                                                                  return FutureBuilder<Size>(
                                                                    future: _resolveImageSize(url),
                                                                    builder: (context, snapshot) {
                                                                      // 実画像サイズが取れたらそれを使う。取れなければ _drawingAspectRatio にフォールバック
                                                                      final double imgAspect = snapshot.hasData && snapshot.data!.height > 0
                                                                          ? snapshot.data!.width / snapshot.data!.height
                                                                          : (_drawingAspectRatio ?? (9 / 16));
                                                                      final containerAspect = pWidth / (pHeight > 0 ? pHeight : 1.0);
                                                                      double renderW = pWidth;
                                                                      double renderH = pHeight;
                                                                      double offsetX = 0.0;
                                                                      double offsetY = 0.0;

                                                                      if (containerAspect > imgAspect) {
                                                                        renderW = pHeight * imgAspect;
                                                                        offsetX = (pWidth - renderW) / 2.0;
                                                                      } else {
                                                                        renderH = pWidth / (imgAspect > 0 ? imgAspect : 1.0);
                                                                        offsetY = (pHeight - renderH) / 2.0;
                                                                      }

                                                                      final pinX = (offsetX + (pin.xRatio * renderW) - (pinSize / 2.0)).clamp(0.0, pWidth - pinSize);
                                                                      final pinY = (offsetY + (pin.yRatio * renderH) - (pinSize / 2.0)).clamp(0.0, pHeight - pinSize);

                                                                      return Stack(
                                                                        fit: StackFit.expand,
                                                                        children: [
                                                                          Image.network(
                                                                            url,
                                                                            fit: BoxFit.contain,
                                                                            loadingBuilder: (context, child, loadingProgress) {
                                                                              if (loadingProgress == null) return child;
                                                                              return const Center(
                                                                                child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                                                                              );
                                                                            },
                                                                            errorBuilder: (context, error, stackTrace) {
                                                                              SnappySnag._log('⚠️ SnappySnag: Failed to load screenshot image from $url: $error');
                                                                              return Center(
                                                                                child: Column(
                                                                                  mainAxisSize: MainAxisSize.min,
                                                                                  children: [
                                                                                    const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 36),
                                                                                    const SizedBox(height: 8),
                                                                                    Text(
                                                                                      _SdkLocale.originalScreenshotNotFound,
                                                                                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                          if (snapshot.hasData)
                                                                            Positioned(
                                                                              left: pinX,
                                                                              top: pinY,
                                                                              child: Container(
                                                                                width: pinSize,
                                                                                height: pinSize,
                                                                                decoration: BoxDecoration(
                                                                                  color: const Color(0xFF8B5CF6),
                                                                                  shape: BoxShape.circle,
                                                                                  border: Border.all(color: Colors.white, width: 2),
                                                                                  boxShadow: const [
                                                                                    BoxShadow(
                                                                                      color: Colors.black54,
                                                                                      blurRadius: 6,
                                                                                      offset: Offset(0, 3),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                                child: Center(
                                                                                  child: Text(
                                                                                    '${pin.number}',
                                                                                    style: const TextStyle(
                                                                                      color: Colors.white,
                                                                                      fontWeight: FontWeight.bold,
                                                                                      fontSize: 12,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  );
                                                                },
                                                              )
                                                            : Center(
                                                                child: Text(
                                                                  _SdkLocale.originalScreenshotNotFound,
                                                                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                                                                ),
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // 右側: コメント＋戻るボタン
                                                  SizedBox(
                                                    width: 200,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Expanded(
                                                          child: Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black38,
                                                              borderRadius: BorderRadius.circular(8),
                                                              border: Border.all(color: Colors.white12),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                // ① 問題修正: Row→Column で「要素：xxx」が長くてもオーバーフローしない
                                                                Text(
                                                                  _SdkLocale.pinCommentTitle,
                                                                  style: const TextStyle(
                                                                    color: Color(0xFFC4B5FD),
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                                if (_previewingPin!.pin.target != null) ...[
                                                                  const SizedBox(height: 2),
                                                                  Text(
                                                                    '${_SdkLocale.elementAttachedBadge}: ${_previewingPin!.pin.target!.widgetType}',
                                                                    style: const TextStyle(
                                                                      color: Color(0xFFA78BFA),
                                                                      fontSize: 10,
                                                                      fontWeight: FontWeight.bold,
                                                                      overflow: TextOverflow.ellipsis,
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ],
                                                                const SizedBox(height: 4),
                                                                Expanded(
                                                                  child: SingleChildScrollView(
                                                                    child: Text(
                                                                      _previewingPin!.pin.comment.trim().isNotEmpty
                                                                          ? _previewingPin!.pin.comment.trim()
                                                                          : _SdkLocale.noCommentForPin,
                                                                      style: const TextStyle(
                                                                        color: Colors.white,
                                                                        fontSize: 13,
                                                                        height: 1.3,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 8),
                                                        ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: const Color(0xFF8B5CF6),
                                                            foregroundColor: Colors.white,
                                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                          ),
                                                          onPressed: () {
                                                            setState(() {
                                                              _previewingPin = null;
                                                            });
                                                          },
                                                          child: Text(
                                                            _SdkLocale.back,
                                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                           else ...[
                                            // 縦画面: 元スクショプレビュー（当時の画像上にピンをオーバーレイ）
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Container(
                                                  color: Colors.black,
                                                  child: _previewingPin!.screenshotUrl != null && _previewingPin!.screenshotUrl!.isNotEmpty
                                                      ? LayoutBuilder(
                                                          builder: (context, constraints) {
                                                            final pWidth = constraints.maxWidth;
                                                            final pHeight = constraints.maxHeight;
                                                            final pin = _previewingPin!.pin;
                                                            const pinSize = 30.0;
                                                            final url = _previewingPin!.screenshotUrl!;

                                                            return FutureBuilder<Size>(
                                                              future: _resolveImageSize(url),
                                                              builder: (context, snapshot) {
                                                                // 実画像サイズが取れたらそれを使う。取れなければ _drawingAspectRatio にフォールバック
                                                                final double imgAspect = snapshot.hasData && snapshot.data!.height > 0
                                                                    ? snapshot.data!.width / snapshot.data!.height
                                                                    : (_drawingAspectRatio ?? (9 / 16));
                                                                final containerAspect = pWidth / (pHeight > 0 ? pHeight : 1.0);
                                                                double renderW = pWidth;
                                                                double renderH = pHeight;
                                                                double offsetX = 0.0;
                                                                double offsetY = 0.0;

                                                                if (containerAspect > imgAspect) {
                                                                  // 左右に黒帯（レターボックス）
                                                                  renderW = pHeight * imgAspect;
                                                                  offsetX = (pWidth - renderW) / 2.0;
                                                                } else {
                                                                  // 上下に黒帯
                                                                  renderH = pWidth / (imgAspect > 0 ? imgAspect : 1.0);
                                                                  offsetY = (pHeight - renderH) / 2.0;
                                                                }

                                                                final pinX = (offsetX + (pin.xRatio * renderW) - (pinSize / 2.0)).clamp(0.0, pWidth - pinSize);
                                                                final pinY = (offsetY + (pin.yRatio * renderH) - (pinSize / 2.0)).clamp(0.0, pHeight - pinSize);

                                                                return Stack(
                                                                  fit: StackFit.expand,
                                                                  children: [
                                                                    Image.network(
                                                                      url,
                                                                      fit: BoxFit.contain,
                                                                      loadingBuilder: (context, child, loadingProgress) {
                                                                        if (loadingProgress == null) return child;
                                                                        return const Center(
                                                                          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                                                                        );
                                                                      },
                                                                      errorBuilder: (context, error, stackTrace) {
                                                                        SnappySnag._log('⚠️ SnappySnag: Failed to load screenshot image from $url: $error');
                                                                        return Center(
                                                                          child: Column(
                                                                            mainAxisSize: MainAxisSize.min,
                                                                            children: [
                                                                              const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 36),
                                                                              const SizedBox(height: 8),
                                                                              Text(
                                                                                _SdkLocale.originalScreenshotNotFound,
                                                                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        );
                                                                      },
                                                                    ),
                                                                    if (snapshot.hasData)
                                                                      Positioned(
                                                                        left: pinX,
                                                                        top: pinY,
                                                                        child: Container(
                                                                          width: pinSize,
                                                                          height: pinSize,
                                                                          decoration: BoxDecoration(
                                                                            color: const Color(0xFF8B5CF6),
                                                                            shape: BoxShape.circle,
                                                                            border: Border.all(color: Colors.white, width: 2),
                                                                            boxShadow: const [
                                                                              BoxShadow(
                                                                                color: Colors.black54,
                                                                                blurRadius: 6,
                                                                                offset: Offset(0, 3),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          child: Center(
                                                                            child: Text(
                                                                              '${pin.number}',
                                                                              style: const TextStyle(
                                                                                color: Colors.white,
                                                                                fontWeight: FontWeight.bold,
                                                                                fontSize: 12,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                  ],
                                                                );
                                                              },
                                                            );
                                                          },
                                                        )
                                                      : Center(
                                                          child: Text(
                                                            _SdkLocale.originalScreenshotNotFound,
                                                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                                                          ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // 指摘コメント表示
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.black38,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        _SdkLocale.pinCommentTitle,
                                                        style: const TextStyle(
                                                          color: Color(0xFFC4B5FD),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      if (_previewingPin!.pin.target != null)
                                                        Text(
                                                          '${_SdkLocale.elementAttachedBadge}: ${_previewingPin!.pin.target!.widgetType}',
                                                          style: const TextStyle(
                                                            color: Color(0xFFA78BFA),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  ConstrainedBox(
                                                    constraints: const BoxConstraints(maxHeight: 80),
                                                    child: SingleChildScrollView(
                                                      child: Text(
                                                        _previewingPin!.pin.comment.trim().isNotEmpty
                                                            ? _previewingPin!.pin.comment.trim()
                                                            : _SdkLocale.noCommentForPin,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF8B5CF6),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _previewingPin = null;
                                                });
                                              },
                                              child: Text(
                                                _SdkLocale.back,
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // 5. プライバシー確認用フローティングオーバーレイ（最前面に描画）
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
                    // 5. 全消去確認オーバーレイ
                    if (_isClearConfirmOpen)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.75),
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
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
                                          const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          const SizedBox(width: 8),
                                          Text(
                                            _SdkLocale.clearConfirmTitle,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _SdkLocale.clearConfirmBody,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              setState(() => _isClearConfirmOpen = false);
                                            },
                                            child: Text(
                                              _SdkLocale.cancel,
                                              style: const TextStyle(color: Colors.white54),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.redAccent,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _drawingPoints.clear();
                                                _pins.clear();
                                                _undoStack.clear();
                                                _redoStack.clear();
                                                _isClearConfirmOpen = false;
                                              });
                                            },
                                            child: Text(
                                              _SdkLocale.clearConfirmButton,
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
                    // 6. キャンセル時の下書き保存確認オーバーレイ
                    if (_isCancelDraftConfirmOpen)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.75),
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
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
                                          const Icon(Icons.bookmark_border, color: Color(0xFFF59E0B)),
                                          const SizedBox(width: 8),
                                          Text(
                                            _SdkLocale.saveDraftPromptTitle,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _SdkLocale.saveDraftPromptOnCancel,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              setState(() => _isCancelDraftConfirmOpen = false);
                                            },
                                            child: Text(
                                              _SdkLocale.cancel,
                                              style: const TextStyle(color: Colors.white54),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              await _SnappyDraftData.clear();
                                              _closeDrawingOverlay();
                                            },
                                            child: Text(
                                              _SdkLocale.discardDraft,
                                              style: const TextStyle(color: Colors.redAccent),
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
                                            onPressed: () async {
                                              if (_drawingImageBytes != null) {
                                                await _SnappyDraftData.save(
                                                  imageBytes: _drawingImageBytes!,
                                                  widgetTree: _drawingWidgetTree,
                                                  screenClassName: _drawingScreenClassName,
                                                  screenSignature: _drawingScreenSignature,
                                                  drawingPoints: _drawingPoints,
                                                  pins: _pins,
                                                  memo: _feedbackMemoController.text,
                                                  drawingAspectRatio: _drawingAspectRatio,
                                                  existingFeedbacks: _existingFeedbacks,
                                                  isDevChatEnabled: SnappySnag().isDevChatEnabled,
                                                );
                                              }
                                              final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
                                              _closeDrawingOverlay();
                                              ScaffoldMessenger.of(messengerContext).showSnackBar(
                                                SnackBar(
                                                  content: Text(_SdkLocale.draftSavedToast),
                                                  backgroundColor: Colors.black87,
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            },
                                            child: Text(
                                              _SdkLocale.saveDraft,
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

                    // 6. 送信失敗時の下書き保存確認オーバーレイ
                    if (_isFailedSendDraftConfirmOpen)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.75),
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
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
                                          const Icon(Icons.bookmark_border, color: Color(0xFFF59E0B)),
                                          const SizedBox(width: 8),
                                          Text(
                                            _SdkLocale.saveDraftPromptTitle,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _SdkLocale.saveDraftPromptOnFailedSend,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              setState(() => _isFailedSendDraftConfirmOpen = false);
                                            },
                                            child: Text(
                                              _SdkLocale.stayOnScreen,
                                              style: const TextStyle(color: Colors.white70),
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
                                            onPressed: () async {
                                              if (_drawingImageBytes != null) {
                                                await _SnappyDraftData.save(
                                                  imageBytes: _drawingImageBytes!,
                                                  widgetTree: _drawingWidgetTree,
                                                  screenClassName: _drawingScreenClassName,
                                                  screenSignature: _drawingScreenSignature,
                                                  drawingPoints: _drawingPoints,
                                                  pins: _pins,
                                                  memo: _feedbackMemoController.text,
                                                  drawingAspectRatio: _drawingAspectRatio,
                                                  existingFeedbacks: _existingFeedbacks,
                                                  isDevChatEnabled: SnappySnag().isDevChatEnabled,
                                                );
                                              }
                                              final messengerContext = SnappySnag().navigatorKey?.currentContext ?? context;
                                              _closeDrawingOverlay();
                                              ScaffoldMessenger.of(messengerContext).showSnackBar(
                                                SnackBar(
                                                  content: Text(_SdkLocale.draftSavedToast),
                                                  backgroundColor: Colors.black87,
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            },
                                            child: Text(
                                              _SdkLocale.saveDraft,
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
                    // 7. 開発者パスコード入力オーバーレイ（最前面・コンパクトサイズ）
                    if (_isDevPasscodeDialogOpen)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.75),
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
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
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.lock_outline,
                                              color: Color(0xFFA78BFA),
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _SdkLocale.devPasscodeDialogTitle,
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
                                        _SdkLocale.devPasscodeDialogDesc,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _devPasscodeInputController,
                                        autofocus: true,
                                        keyboardType: TextInputType.number,
                                        maxLength: 4,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          letterSpacing: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(4),
                                        ],
                                        decoration: InputDecoration(
                                          hintText: _SdkLocale.devPasscodeHint,
                                          hintStyle: const TextStyle(
                                            color: Colors.white24,
                                            letterSpacing: 8,
                                          ),
                                          counterText: '',
                                          filled: true,
                                          fillColor: Colors.black26,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(color: Colors.white24),
                                          ),
                                          focusedBorder: const OutlineInputBorder(
                                            borderRadius: BorderRadius.all(Radius.circular(10)),
                                            borderSide: BorderSide(color: Color(0xFF8B5CF6), width: 2),
                                          ),
                                        ),
                                        onChanged: (_) {
                                          if (_devPasscodeErrorMessage != null) {
                                            setState(() {
                                              _devPasscodeErrorMessage = null;
                                            });
                                          }
                                        },
                                        onSubmitted: (_) {
                                          if (!_isVerifyingDevPasscode) {
                                            _submitDevPasscode();
                                          }
                                        },
                                      ),
                                      if (_devPasscodeErrorMessage != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _devPasscodeErrorMessage!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: _isVerifyingDevPasscode
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _isDevPasscodeDialogOpen = false;
                                                      _devPasscodeErrorMessage = null;
                                                      _devPasscodeInputController.clear();
                                                    });
                                                  },
                                            child: Text(
                                              _SdkLocale.devPasscodeCancel,
                                              style: const TextStyle(color: Colors.white54),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF8B5CF6),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: _isVerifyingDevPasscode ? null : () => _submitDevPasscode(),
                                            child: _isVerifyingDevPasscode
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : Text(
                                                    _SdkLocale.devPasscodeSubmit,
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
                    bottom: 16 + MediaQuery.of(context).padding.bottom,
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
  @override
  void initState() {
    super.initState();
    SnappySnag()._pushHideRequest();
  }

  @override
  void dispose() {
    SnappySnag()._popHideRequest();
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

  /// Unicode私用領域（PUA: \uE000-\uF8FF, \uF0000以上）などのアイコンフォント外字であるかを判定
  static bool _isPrivateUseAreaIconText(String? str) {
    if (str == null) return false;
    final trimmed = str.trim();
    if (trimmed.isEmpty) return false;
    // 長さが3文字以下で、文字コードがPUA（私用領域）にある場合はアイコンと見なす
    if (trimmed.runes.length <= 2) {
      for (final rune in trimmed.runes) {
        if ((rune >= 0xE000 && rune <= 0xF8FF) ||
            (rune >= 0xF0000 && rune <= 0xFFFFD) ||
            (rune >= 0x100000 && rune <= 0x10FFFD)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 画面上のタップ座標から、最も適合するUIウィジェットのアンカー情報（SnappyPinTarget）を抽出する
  static SnappyPinTarget? findTargetAtPosition(BuildContext context, Offset globalPos) {
    Element? topScaffoldElement;
    void findTopScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        topScaffoldElement = element;
      }
      element.visitChildren(findTopScaffold);
    }
    context.visitChildElements(findTopScaffold);
    final Element searchRoot = topScaffoldElement ?? (context as Element);

    final List<_CandidateTarget> candidates = [];
    final Set<int> visited = {};
    int traversalOrder = 0;

    void search(Element element, List<String> currentPath) {
      if (visited.contains(element.hashCode)) return;
      visited.add(element.hashCode);
      final currentOrder = ++traversalOrder;

      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is Visibility && !widget.visible) return;
      if (widget is TickerMode && !widget.enabled) return;

      final typeStr = widget.runtimeType.toString();
      final clean = _cleanType(typeStr);

      final List<String> nextPath = List<String>.from(currentPath);
      if (!_isNoiseWidget(clean) && !_isStandardOrFrameworkWidget(clean)) {
        nextPath.add(clean);
      }

      final renderBox = element.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize && renderBox.attached) {
        try {
          final pos = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;
          final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);

          // タップ座標がウィジェットの境界内に含まれているか
          if (rect.contains(globalPos)) {
            final keyStr = widget.key?.toString();
            String? text;
            if (widget is Text && widget.data != null) {
              text = widget.data;
            } else if (widget is RichText) {
              text = widget.text.toPlainText();
            } else if (widget is EditableText) {
              text = widget.controller.text;
            } else if (widget is TextField) {
              text = widget.controller?.text ?? widget.decoration?.hintText;
            }

            // TextFieldなどの入力欄の場合でテキストがまだ取れていない時は子孫からEditableTextを探す
            if ((text == null || text.trim().isEmpty) &&
                (clean.contains('TextField') || clean.contains('TextFormField') || clean.contains('EditableText'))) {
              void findInputText(Element el) {
                if (text != null && text!.trim().isNotEmpty) return;
                final w = el.widget;
                if (w is EditableText) {
                  text = w.controller.text;
                } else if (w is Text && w.data != null && w.data!.trim().isNotEmpty) {
                  text = w.data!.trim();
                }
                if (text == null || text!.isEmpty) {
                  el.visitChildren(findInputText);
                }
              }
              element.visitChildren(findInputText);
            }

            // テキストコードによるアイコン（外字フォント・PUA）の場合はテキストとして扱わない（アイコン扱い）
            final bool isIconGlyph = _isPrivateUseAreaIconText(text);

            // テキストの有効性チェック（空文字、空白のみ、または私用領域アイコンはテキスト除外）
            final rawText = text;
            final bool hasValidText = !isIconGlyph && rawText != null && rawText.trim().isNotEmpty;
            final String? trimmedText = hasValidText ? rawText.trim() : null;

            // 祖先（ancestors）を遡って、ボタンや操作可能コンテナがないかを探索
            Element? clickableAncestor;
            String? ancestorType;
            String? ancestorKey;
            Rect? ancestorRect;

            element.visitAncestorElements((ancestor) {
              if (ancestor == searchRoot) return false;
              final aWidget = ancestor.widget;
              final aType = _cleanType(aWidget.runtimeType.toString());

              // 内部・低レベルフレームワークウィジェットは除外（_で始まるもの、RawGestureDetector、Scopeなど）
              if (aType.startsWith('_') ||
                  aType == 'RawGestureDetector' ||
                  aType.endsWith('Scope') ||
                  aType == 'Semantics' ||
                  aType == 'Focus' ||
                  aType == 'FocusScope' ||
                  aType == 'IgnorePointer' ||
                  aType == 'AbsorbPointer' ||
                  aType == 'KeyedSubtree') {
                return true;
              }

              // 操作可能コンテナ、ボタン、テキスト入力欄、ヘッダー/バーコンテナ
              final isClickable = aType.contains('Button') ||
                  aType.contains('InkWell') ||
                  aType.contains('GestureDetector') ||
                  aType.contains('Card') ||
                  aType.contains('ListTile') ||
                  aType.contains('Chip') ||
                  aType.contains('TextField') ||
                  aType.contains('TextFormField') ||
                  aType.contains('AppBar') ||
                  aType.contains('Header') ||
                  aType.contains('Bar');

              if (isClickable) {
                final aBox = ancestor.findRenderObject();
                if (aBox is RenderBox && aBox.hasSize && aBox.attached) {
                  try {
                    final aPos = aBox.localToGlobal(Offset.zero);
                    final aSize = aBox.size;
                    final aR = Rect.fromLTWH(aPos.dx, aPos.dy, aSize.width, aSize.height);
                    if (aR.contains(globalPos)) {
                      clickableAncestor = ancestor;
                      ancestorType = aType;
                      ancestorKey = aWidget.key?.toString();
                      ancestorRect = aR;
                      // アプリ独自のカスタムボタン（例: OneStaStartButton 等）やTextFieldを見つけたら即座に確定
                      if (!aType.startsWith('GestureDetector') && !aType.startsWith('InkResponse')) {
                        return false;
                      }
                    }
                  } catch (_) {}
                }
              }
              return true;
            });

            // 祖先にボタン等の操作可能コンテナが存在する場合、そのコンテナを候補として登録
            if (clickableAncestor != null && ancestorType != null && ancestorRect != null) {
              final cArea = ancestorRect!.width * ancestorRect!.height;
              final localXRatio = ancestorRect!.width > 0 ? ((globalPos.dx - ancestorRect!.left) / ancestorRect!.width).clamp(0.0, 1.0) : 0.5;
              final localYRatio = ancestorRect!.height > 0 ? ((globalPos.dy - ancestorRect!.top) / ancestorRect!.height).clamp(0.0, 1.0) : 0.5;

              // ボタン内部にテキストがあればそれをアンカーテキストとして拝借する
              // タップ位置そのものにテキストがない場合（アイコンや矢印をタップした場合）、
              // ボタン（clickableAncestor）の子孫要素全体から、タップ座標に最も近いテキストを選択する
              String? buttonText = trimmedText;
              if (buttonText == null || buttonText.isEmpty) {
                double minDistance = double.infinity;
                String? closestText;

                void findClosestChildText(Element el) {
                  final w = el.widget;
                  String? candidate;
                  if (w is Text && w.data != null && !_isPrivateUseAreaIconText(w.data) && w.data!.trim().isNotEmpty) {
                    candidate = w.data!.trim();
                  } else if (w is RichText) {
                    final plain = w.text.toPlainText().trim();
                    if (!_isPrivateUseAreaIconText(plain) && plain.isNotEmpty) {
                      candidate = plain;
                    }
                  } else if (w is EditableText) {
                    final plain = w.controller.text.trim();
                    if (plain.isNotEmpty) {
                      candidate = plain;
                    }
                  }

                  if (candidate != null && candidate.isNotEmpty) {
                    final rBox = el.findRenderObject();
                    if (rBox is RenderBox && rBox.hasSize && rBox.attached) {
                      try {
                        final pos = rBox.localToGlobal(Offset.zero);
                        final center = Offset(pos.dx + rBox.size.width * 0.5, pos.dy + rBox.size.height * 0.5);
                        final dist = (center - globalPos).distance;
                        if (dist < minDistance) {
                          minDistance = dist;
                          closestText = candidate;
                        }
                      } catch (_) {
                        closestText ??= candidate;
                      }
                    } else {
                      closestText ??= candidate;
                    }
                  }

                  el.visitChildren(findClosestChildText);
                }

                clickableAncestor!.visitChildren(findClosestChildText);
                buttonText = closestText;
              }

              final finalButtonText = buttonText;
              final resolvedText = (finalButtonText != null && finalButtonText.length > 30)
                  ? finalButtonText.substring(0, 30)
                  : finalButtonText;

              final isForeContainer = ancestorType!.contains('AppBar') ||
                  ancestorType!.contains('Header') ||
                  ancestorType!.contains('NavigationBar');

              candidates.add(
                _CandidateTarget(
                  area: cArea,
                  depth: nextPath.length,
                  priority: isForeContainer ? 110 : 100, // ヘッダー系コンテナは110点、ボタン/TextFieldは100点
                  traversalIndex: currentOrder,
                  target: SnappyPinTarget(
                    widgetKey: ancestorKey,
                    widgetType: ancestorType!,
                    widgetText: resolvedText,
                    widgetPath: nextPath.length > 5 ? nextPath.sublist(nextPath.length - 5) : nextPath,
                    localXRatio: localXRatio,
                    localYRatio: localYRatio,
                  ),
                ),
              );
            }

            // ウィジェット自体の優先度判定
            // 制御・ラッパー・ノイズウィジェットは単体候補として絶対に採用しない
            final isNoise = clean.startsWith('_') ||
                clean == 'ScrollSemantics' ||
                clean.endsWith('Scope') ||
                clean == 'IgnorePointer' ||
                clean == 'AbsorbPointer' ||
                clean == 'Semantics' ||
                clean == 'Focus' ||
                clean == 'FocusScope' ||
                clean == 'RawGestureDetector' ||
                clean == 'KeyedSubtree';

            if (!isNoise) {
              int priority = 0;
              final isInputWidget = clean.contains('TextField') || clean.contains('TextFormField') || clean.contains('EditableText');
              final isButtonSelf = clean.contains('Button') || clean.contains('InkWell') || clean.contains('Tile') || clean.contains('Card') || isInputWidget;
              final isForeElement = clean.contains('AppBar') || clean.contains('Header') || clean.contains('NavigationBar');

              if (isForeElement) {
                priority = 110; // ヘッダー・AppBar要素は最前面として優先
              } else if (isButtonSelf) {
                priority = 100;
              } else if (keyStr != null && keyStr.isNotEmpty) {
                priority = 80;
              } else if (hasValidText) {
                priority = 60;
              } else if (clean.contains('Image') || clean.contains('Icon') || isIconGlyph) {
                priority = 40; // 画像やアイコン（外字フォント含む）
              }

              if (priority > 0) {
                final area = size.width * size.height;
                final localXRatio = size.width > 0 ? ((globalPos.dx - pos.dx) / size.width).clamp(0.0, 1.0) : 0.5;
                final localYRatio = size.height > 0 ? ((globalPos.dy - pos.dy) / size.height).clamp(0.0, 1.0) : 0.5;

                candidates.add(
                  _CandidateTarget(
                    area: area,
                    depth: nextPath.length,
                    priority: priority,
                    traversalIndex: currentOrder,
                    target: SnappyPinTarget(
                      widgetKey: keyStr,
                      widgetType: clean,
                      widgetText: trimmedText != null && trimmedText.length > 30 ? trimmedText.substring(0, 30) : trimmedText,
                      widgetPath: nextPath.length > 5 ? nextPath.sublist(nextPath.length - 5) : nextPath,
                      localXRatio: localXRatio,
                      localYRatio: localYRatio,
                    ),
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }

      element.visitChildren((child) => search(child, nextPath));
    }

    search(searchRoot, []);

    if (candidates.isEmpty) return null;

    // ソート順:
    // 1. priority（ヘッダー: 110, ボタン/TextField: 100, Key: 80, テキスト: 60, アイコン/画像: 40）
    // 2. traversalIndex（重なりがある場合、ツリーで後から描画された前面レイヤーを最優先）
    // 3. area（より具体的で小さい要素を優先）
    // 4. depth（より深い特化ウィジェットを優先）
    candidates.sort((a, b) {
      // 画面の重なり（後勝ち）を強く反映させるため、priority が近い場合は traversalIndex を優先考慮
      final prioDiff = b.priority.compareTo(a.priority);
      if (prioDiff != 0) return prioDiff;
      final orderDiff = b.traversalIndex.compareTo(a.traversalIndex);
      if (orderDiff != 0) return orderDiff;
      final areaDiff = a.area.compareTo(b.area);
      if (areaDiff != 0) return areaDiff;
      return b.depth.compareTo(a.depth);
    });

    return candidates.first.target;
  }

  /// 現在の画面ウィジェットツリーを走査し、ターゲット情報に最も合致するUI要素のグローバル座標を算出する
  static Offset? resolveTargetPosition(
    BuildContext context,
    SnappyPinTarget target, {
    Offset? fallbackPosition,
  }) {
    Element? topScaffoldElement;
    void findTopScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        topScaffoldElement = element;
      }
      element.visitChildren(findTopScaffold);
    }
    context.visitChildElements(findTopScaffold);
    final Element searchRoot = topScaffoldElement ?? (context as Element);

    // 画面全体のルートRenderBoxを取得（同一共通コンポーネントが複数ある場合の近接判定用）
    final rootRenderBox = searchRoot.findRenderObject() as RenderBox?;
    final rootOrigin = (rootRenderBox != null && rootRenderBox.attached)
        ? rootRenderBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final rootSize = (rootRenderBox != null && rootRenderBox.attached && rootRenderBox.hasSize)
        ? rootRenderBox.size
        : (MediaQuery.maybeOf(context)?.size ?? Size.zero);

    _MatchResult? bestMatch;
    final Set<int> visited = {};

    void search(Element element, List<String> currentPath) {
      if (visited.contains(element.hashCode)) return;
      visited.add(element.hashCode);

      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is Visibility && !widget.visible) return;
      if (widget is TickerMode && !widget.enabled) return;

      final typeStr = widget.runtimeType.toString();
      final clean = _cleanType(typeStr);

      final List<String> nextPath = List<String>.from(currentPath);
      if (!_isNoiseWidget(clean) && !_isStandardOrFrameworkWidget(clean)) {
        nextPath.add(clean);
      }

      final keyStr = widget.key?.toString();
      String? text;
      if (widget is Text && widget.data != null) {
        text = widget.data;
      } else if (widget is RichText) {
        text = widget.text.toPlainText();
      } else if (widget is EditableText) {
        text = widget.controller.text;
      } else if (widget is TextField) {
        text = widget.controller?.text ?? widget.decoration?.hintText;
      } else if (target.widgetText != null && target.widgetText!.isNotEmpty) {
        // ボタンやコンテナの場合、子孫のTextウィジェットからテキストを探してマッチングに使用
        void findDescendantText(Element el) {
          if (text != null && text!.trim().isNotEmpty) return;
          final w = el.widget;
          if (w is Text && w.data != null && !_isPrivateUseAreaIconText(w.data) && w.data!.trim().isNotEmpty) {
            text = w.data!.trim();
          } else if (w is RichText) {
            final plain = w.text.toPlainText().trim();
            if (!_isPrivateUseAreaIconText(plain) && plain.isNotEmpty) {
              text = plain;
            }
          } else if (w is EditableText) {
            final plain = w.controller.text.trim();
            if (plain.isNotEmpty) {
              text = plain;
            }
          }
          if (text == null || text!.isEmpty) {
            el.visitChildren(findDescendantText);
          }
        }
        element.visitChildren(findDescendantText);
      }

      int score = 0;

      // 1. Key の完全一致 (最優先: 100点)
      if (target.widgetKey != null && keyStr != null && target.widgetKey == keyStr) {
        score += 100;
      }

      // 2. ウィジェットの型一致 (20点)
      if (target.widgetType == clean) {
        score += 20;
      }

      // 3. テキストの一致判定
      final String? currentText = text?.trim();
      final String? targetText = target.widgetText?.trim();
      if (targetText != null && currentText != null && currentText.isNotEmpty) {
        if (currentText == targetText) {
          // 完全一致: 最も信頼度が高いため高配点 (50点)
          score += 50;
        } else {
          // 数字のみ、または短い文字列（4文字以下、例: "3" と "30"）の場合は誤判定防止のため部分一致を不許可
          final isNumericOrShort = currentText.length <= 4 ||
              targetText.length <= 4 ||
              int.tryParse(currentText) != null ||
              int.tryParse(targetText) != null;
          if (!isNumericOrShort) {
            if (currentText.startsWith(targetText) || targetText.startsWith(currentText)) {
              score += 20; // 長文の部分一致
            }
          }
        }
      }

      // 4. パスの合致 (最大20点)
      if (target.widgetPath.isNotEmpty && nextPath.isNotEmpty) {
        int commonAncestors = 0;
        for (final p in target.widgetPath) {
          if (nextPath.contains(p)) commonAncestors++;
        }
        score += (commonAncestors * 5).clamp(0, 20);
      }

      final renderBox = element.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize && renderBox.attached) {
        try {
          final pos = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;
          if (size.width > 0 && size.height > 0) {
            // ★ ユーザー指示: 要素吸着時は要素の中心（50% / 50%）にピタッと吸着させる
            final resolvedOffset = Offset(
              pos.dx + (size.width * 0.5),
              pos.dy + (size.height * 0.5),
            );

            // 5. 相対座標の近接度ボーナス (最大30点)
            // カレンダーの日付や同型セル、共通ボタンが複数ある場合、元ピンの画面位置に近いものを優先
            int positionBonus = 0;
            final refRatioX = fallbackPosition?.dx ?? target.localXRatio;
            final refRatioY = fallbackPosition?.dy ?? target.localYRatio;
            if (rootSize.width > 0 && rootSize.height > 0 && refRatioX != null && refRatioY != null) {
              final elemCenterRatioX = (resolvedOffset.dx - rootOrigin.dx) / rootSize.width;
              final elemCenterRatioY = (resolvedOffset.dy - rootOrigin.dy) / rootSize.height;
              // 元の画面相対比率と候補要素の中心比率のユークリッド距離
              final dist = sqrt(
                pow(elemCenterRatioX - refRatioX, 2) +
                pow(elemCenterRatioY - refRatioY, 2),
              );
              // 距離が近いほど高得点（最大30点）
              positionBonus = ((1.0 - dist.clamp(0.0, 1.0)) * 30).round();
            }

            final totalScore = score + positionBonus;

            // 型一致(20点) + 近接ボーナス(最大30点) または テキスト一致(40点) などで25点以上なら吸着候補とする
            if (totalScore >= 25) {
              if (bestMatch == null || totalScore > bestMatch!.score) {
                bestMatch = _MatchResult(
                  score: totalScore,
                  offset: resolvedOffset,
                  matchedType: clean,
                  matchedText: text,
                  matchedKey: keyStr,
                );
              }
            }
          }
        } catch (_) {}
      }

      element.visitChildren((child) => search(child, nextPath));
    }

    search(searchRoot, []);
    final match = bestMatch;
    if (match != null) {
      SnappySnag._log('📍 SnappySnag: Target resolved successfully -> [${match.matchedType}] (Text: "${match.matchedText ?? ''}", Key: "${match.matchedKey ?? ''}") at center pos: ${match.offset} (score: ${match.score})');
      return match.offset;
    } else {
      SnappySnag._log('⚠️ SnappySnag: Target resolution failed for [${target.widgetType}] (Text: "${target.widgetText ?? ''}", Key: "${target.widgetKey ?? ''}"). Falling back to relative ratio.');
      return null;
    }
  }

  /// ターゲット情報に合致するUI要素の画面内 Rect（大枠の領域）を特定する
  /// 見つからない場合（画面外・スクロール等）は null を返す
  static Rect? resolveTargetRect(
    BuildContext context,
    SnappyPinTarget target, {
    Offset? fallbackPosition,
  }) {
    final searchRoot = context as Element;
    _MatchResult? bestMatch;

    final rootBox = context.findRenderObject() as RenderBox?;
    final rootOrigin = (rootBox != null && rootBox.attached)
        ? rootBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final rootSize = (rootBox != null && rootBox.attached && rootBox.hasSize)
        ? rootBox.size
        : MediaQuery.of(context).size;

    void search(Element element, List<String> currentPath) {
      final widget = element.widget;
      final rawType = widget.runtimeType.toString();
      final clean = _cleanType(rawType);

      final nextPath = List<String>.from(currentPath);
      if (!_isNoiseWidget(clean) && !_isStandardOrFrameworkWidget(clean)) {
        nextPath.add(clean);
      }

      final keyStr = widget.key?.toString();
      String? text;
      if (widget is Text && widget.data != null) {
        text = widget.data;
      } else if (widget is RichText) {
        text = widget.text.toPlainText();
      } else if (widget is EditableText) {
        text = widget.controller.text;
      } else if (widget is TextField) {
        text = widget.controller?.text ?? widget.decoration?.hintText;
      } else if (target.widgetText != null && target.widgetText!.isNotEmpty) {
        void findDescendantText(Element el) {
          if (text != null && text!.trim().isNotEmpty) return;
          final w = el.widget;
          if (w is Text && w.data != null && !_isPrivateUseAreaIconText(w.data) && w.data!.trim().isNotEmpty) {
            text = w.data!.trim();
          } else if (w is RichText) {
            final plain = w.text.toPlainText().trim();
            if (!_isPrivateUseAreaIconText(plain) && plain.isNotEmpty) {
              text = plain;
            }
          } else if (w is EditableText) {
            final plain = w.controller.text.trim();
            if (plain.isNotEmpty) {
              text = plain;
            }
          }
          if (text == null || text!.isEmpty) {
            el.visitChildren(findDescendantText);
          }
        }
        element.visitChildren(findDescendantText);
      }

      int score = 0;
      if (target.widgetKey != null && keyStr != null && target.widgetKey == keyStr) {
        score += 100;
      }
      if (target.widgetType == clean) {
        score += 20;
      }
      final String? currentText = text?.trim();
      final String? targetText = target.widgetText?.trim();
      if (targetText != null && currentText != null && currentText.isNotEmpty) {
        if (currentText == targetText) {
          score += 50;
        } else {
          final isNumericOrShort = currentText.length <= 4 ||
              targetText.length <= 4 ||
              int.tryParse(currentText) != null ||
              int.tryParse(targetText) != null;
          if (!isNumericOrShort) {
            if (currentText.startsWith(targetText) || targetText.startsWith(currentText)) {
              score += 20;
            }
          }
        }
      }
      if (target.widgetPath.isNotEmpty && nextPath.isNotEmpty) {
        int commonAncestors = 0;
        for (final p in target.widgetPath) {
          if (nextPath.contains(p)) commonAncestors++;
        }
        score += (commonAncestors * 5).clamp(0, 20);
      }

      final renderBox = element.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize && renderBox.attached) {
        try {
          final pos = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;
          if (size.width > 0 && size.height > 0) {
            final resolvedOffset = Offset(
              pos.dx + (size.width * 0.5),
              pos.dy + (size.height * 0.5),
            );

            int positionBonus = 0;
            final refRatioX = fallbackPosition?.dx ?? target.localXRatio;
            final refRatioY = fallbackPosition?.dy ?? target.localYRatio;
            if (rootSize.width > 0 && rootSize.height > 0 && refRatioX != null && refRatioY != null) {
              final elemCenterRatioX = (resolvedOffset.dx - rootOrigin.dx) / rootSize.width;
              final elemCenterRatioY = (resolvedOffset.dy - rootOrigin.dy) / rootSize.height;
              final dist = sqrt(
                pow(elemCenterRatioX - refRatioX, 2) +
                pow(elemCenterRatioY - refRatioY, 2),
              );
              positionBonus = ((1.0 - dist.clamp(0.0, 1.0)) * 30).round();
            }

            final totalScore = score + positionBonus;

            if (totalScore >= 25) {
              if (bestMatch == null || totalScore > bestMatch!.score) {
                // セクション領域の特定: 親コンテナ（AppBar / Card / セクションブロック）への昇格判定
                Rect resolvedRect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
                String bestType = clean;

                element.visitAncestorElements((ancestor) {
                  final aWidget = ancestor.widget;
                  final aRawType = aWidget.runtimeType.toString();
                  final aClean = _cleanType(aRawType);

                  if (aClean == 'Scaffold' || aClean == 'MaterialApp' || aClean == 'Navigator') {
                    return false;
                  }

                  final isAppBarAncestor = aClean.contains('AppBar') || aClean.contains('SliverAppBar') || aClean.contains('Header');
                  final isCardAncestor = aClean.contains('Card') || aClean.contains('Calendar') || aClean.contains('Section');

                  if (isAppBarAncestor || isCardAncestor) {
                    final aBox = ancestor.findRenderObject();
                    if (aBox is RenderBox && aBox.hasSize && aBox.attached) {
                      final aPos = aBox.localToGlobal(Offset.zero);
                      final aSize = aBox.size;
                      if (aSize.width > 0 && aSize.height > 0) {
                        resolvedRect = Rect.fromLTWH(aPos.dx, aPos.dy, aSize.width, aSize.height);
                        bestType = aClean;
                        if (isAppBarAncestor) {
                          return false; // AppBarは最上位ヘッダーとして即座に確定
                        }
                      }
                    }
                  }
                  return true;
                });

                bestMatch = _MatchResult(
                  score: totalScore,
                  offset: resolvedOffset,
                  matchedType: bestType,
                  matchedText: text,
                  matchedKey: keyStr,
                  rect: resolvedRect,
                );
              }
            }
          }
        } catch (_) {}
      }

      element.visitChildren((child) => search(child, nextPath));
    }

    search(searchRoot, []);
    final match = bestMatch;
    if (match != null && match.rect != null) {
      SnappySnag._log('📍 SnappySnag: Target section Rect resolved successfully -> [${match.matchedType}] ${match.rect} (score: ${match.score})');
      return match.rect;
    } else {
      SnappySnag._log('⚠️ SnappySnag: Target section Rect resolution failed for [${target.widgetType}]');
      return null;
    }
  }
}

/// Drawing tool type for annotation and masking.
enum SnappyDrawingTool {
  pin,
  mosaic,
  @Deprecated('Use pin instead')
  redPen,
}

/// ピンが紐づくUIウィジェットの特定アンカー情報（異なる画面サイズ・解像度での要素吸着用）

class _CandidateTarget {
  final double area;
  final int depth;
  final int priority;
  final int traversalIndex;
  final SnappyPinTarget target;
  _CandidateTarget({
    required this.area,
    required this.depth,
    required this.priority,
    required this.traversalIndex,
    required this.target,
  });
}

class _MatchResult {
  final int score;
  final Offset offset;
  final String matchedType;
  final String? matchedText;
  final String? matchedKey;
  final Rect? rect;
  _MatchResult({
    required this.score,
    required this.offset,
    required this.matchedType,
    this.matchedText,
    this.matchedKey,
    this.rect,
  });
}
class SnappyPinTarget {
  final String? widgetKey;
  final String widgetType;
  final String? widgetText;
  final List<String> widgetPath;
  final double? localXRatio;
  final double? localYRatio;

  SnappyPinTarget({
    this.widgetKey,
    required this.widgetType,
    this.widgetText,
    this.widgetPath = const [],
    this.localXRatio,
    this.localYRatio,
  });

  SnappyPinTarget copyWith({
    String? widgetKey,
    String? widgetType,
    String? widgetText,
    List<String>? widgetPath,
    double? localXRatio,
    double? localYRatio,
  }) {
    return SnappyPinTarget(
      widgetKey: widgetKey ?? this.widgetKey,
      widgetType: widgetType ?? this.widgetType,
      widgetText: widgetText ?? this.widgetText,
      widgetPath: widgetPath ?? this.widgetPath,
      localXRatio: localXRatio ?? this.localXRatio,
      localYRatio: localYRatio ?? this.localYRatio,
    );
  }

  Map<String, dynamic> toJson() => {
        if (widgetKey != null) 'key': widgetKey,
        'type': widgetType,
        if (widgetText != null) 'text': widgetText,
        if (widgetPath.isNotEmpty) 'path': widgetPath,
        if (localXRatio != null) 'localX': localXRatio,
        if (localYRatio != null) 'localY': localYRatio,
      };

  factory SnappyPinTarget.fromJson(Map<String, dynamic> json) {
    return SnappyPinTarget(
      widgetKey: json['key'] as String?,
      widgetType: json['type'] as String? ?? 'Widget',
      widgetText: json['text'] as String?,
      widgetPath: (json['path'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      localXRatio: (json['localX'] as num?)?.toDouble(),
      localYRatio: (json['localY'] as num?)?.toDouble(),
    );
  }
}

/// スクリーンショット上の特定箇所を指し示すピンモデル
class SnappyPin {
  final String id;
  final int number;
  final double xRatio; // 0.0 ~ 1.0 (相対X座標 - フォールバック用)
  final double yRatio; // 0.0 ~ 1.0 (相対Y座標 - フォールバック用)
  final String comment;
  final SnappyPinTarget? target; // ★ 要素吸着用メタデータ
  final bool isActive; // ★ ピンの有効状態 (feedback_logs の pins["is_active"])

  SnappyPin({
    required this.id,
    required this.number,
    required this.xRatio,
    required this.yRatio,
    this.comment = '',
    this.target,
    this.isActive = true,
  });

  SnappyPin copyWith({
    String? id,
    int? number,
    double? xRatio,
    double? yRatio,
    String? comment,
    SnappyPinTarget? target,
    bool? isActive,
  }) {
    return SnappyPin(
      id: id ?? this.id,
      number: number ?? this.number,
      xRatio: xRatio ?? this.xRatio,
      yRatio: yRatio ?? this.yRatio,
      comment: comment ?? this.comment,
      target: target ?? this.target,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'x': xRatio,
        'y': yRatio,
        'xRatio': xRatio,
        'yRatio': yRatio,
        'comment': comment,
        'is_active': isActive,
        if (target != null) 'target': target!.toJson(),
      };

  factory SnappyPin.fromJson(Map<String, dynamic> json) {
    SnappyPinTarget? target;
    if (json['target'] is Map<String, dynamic>) {
      target = SnappyPinTarget.fromJson(json['target'] as Map<String, dynamic>);
    }
    final rawIsActive = json['is_active'] ?? json['isActive'];
    final bool isActive = (rawIsActive == null)
        ? true
        : (rawIsActive is bool
            ? rawIsActive
            : (rawIsActive.toString().toLowerCase() != 'false' && rawIsActive.toString() != '0'));
    return SnappyPin(
      id: json['id'] as String? ?? 'pin_${DateTime.now().millisecondsSinceEpoch}',
      number: (json['number'] as num?)?.toInt() ?? 1,
      xRatio: (json['xRatio'] as num?)?.toDouble() ?? (json['x'] as num?)?.toDouble() ?? 0.0,
      yRatio: (json['yRatio'] as num?)?.toDouble() ?? (json['y'] as num?)?.toDouble() ?? 0.0,
      comment: json['comment'] as String? ?? '',
      target: target,
      isActive: isActive,
    );
  }
}
/// 過去に投稿された既存チケットのピン情報
class ExistingPinItem {
  final String feedbackId;
  final String userMemo;
  final String severity;
  final SnappyPin pin;
  final Offset? resolvedRatio; // ★ 要素吸着により解決された画面に対する相対比率(0.0~1.0)
  final String? screenshotUrl; // ★ 投稿当時の元スクリーンショット画像URL/パス

  ExistingPinItem({
    required this.feedbackId,
    required this.userMemo,
    required this.severity,
    required this.pin,
    this.resolvedRatio,
    this.screenshotUrl,
  });
}

/// 過去にピンが打たれた要素・セクションのグループ情報（ハイライト表示用）
class ExistingSectionItem {
  final String id;
  final String sectionName;
  final Rect screenRect; // アプリ画面（グローバル）上の座標・サイズ
  final List<ExistingPinItem> pins;

  ExistingSectionItem({
    required this.id,
    required this.sectionName,
    required this.screenRect,
    required this.pins,
  });
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

  Map<String, dynamic> toJson() => {
        'offsets': offsets
            .map((o) => o != null ? {'dx': o.dx, 'dy': o.dy} : null)
            .toList(),
        'color': color.toARGB32(),
        'strokeWidth': strokeWidth,
        'recordedWidth': recordedSize.width,
        'recordedHeight': recordedSize.height,
        'tool': tool.name,
        if (rect != null)
          'rect': {
            'left': rect!.left,
            'top': rect!.top,
            'right': rect!.right,
            'bottom': rect!.bottom,
          },
      };

  factory DrawingPoint.fromJson(Map<String, dynamic> json) {
    final rawOffsets = json['offsets'] as List<dynamic>? ?? [];
    final offsets = rawOffsets.map<Offset?>((item) {
      if (item == null) return null;
      final m = item as Map<String, dynamic>;
      return Offset((m['dx'] as num).toDouble(), (m['dy'] as num).toDouble());
    }).toList();

    Rect? rect;
    if (json['rect'] != null) {
      final r = json['rect'] as Map<String, dynamic>;
      rect = Rect.fromLTRB(
        (r['left'] as num).toDouble(),
        (r['top'] as num).toDouble(),
        (r['right'] as num).toDouble(),
        (r['bottom'] as num).toDouble(),
      );
    }

    final toolName = json['tool'] as String? ?? 'redPen';
    final tool = SnappyDrawingTool.values.firstWhere(
      (t) => t.name == toolName,
      orElse: () => SnappyDrawingTool.redPen,
    );

    return DrawingPoint(
      offsets: offsets,
      color: Color(json['color'] as int? ?? 0xFFEF4444),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 4.0,
      recordedSize: Size(
        (json['recordedWidth'] as num?)?.toDouble() ?? 0.0,
        (json['recordedHeight'] as num?)?.toDouble() ?? 0.0,
      ),
      tool: tool,
      rect: rect,
    );
  }
}

/// 下書きデータを SharedPreferences に保存・復元するためのヘルパークラス
class _SnappyDraftData {
  static const String _draftKey = 'snappy_snag_draft_v1';

  final Uint8List imageBytes;
  final Map<String, dynamic> widgetTree;
  final String screenClassName;
  final String screenSignature;
  final List<DrawingPoint> drawingPoints;
  final List<SnappyPin> pins;
  final String memo;
  final double? drawingAspectRatio;
  final int timestamp;
  // ★ 下書き保存時点の既存ピン一覧（生JSONリスト）。再開時にサーバーリクエストを不要にする。
  // スクショURLはString(軽量)であり、実際のバイナリは持たない。
  final List<dynamic> existingFeedbacks;
  // ★ 下書き保存時点の isDevChatEnabled フラグ。「全指摘一覧」ボタン表示に使用。
  final bool isDevChatEnabled;

  _SnappyDraftData({
    required this.imageBytes,
    required this.widgetTree,
    required this.screenClassName,
    required this.screenSignature,
    required this.drawingPoints,
    this.pins = const [],
    required this.memo,
    this.drawingAspectRatio,
    required this.timestamp,
    this.existingFeedbacks = const [],
    this.isDevChatEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'imageBytesBase64': base64Encode(imageBytes),
        'widgetTree': widgetTree,
        'screenClassName': screenClassName,
        'screenSignature': screenSignature,
        'drawingPoints': drawingPoints.map((p) => p.toJson()).toList(),
        'pins': pins.map((p) => p.toJson()).toList(),
        'memo': memo,
        if (drawingAspectRatio != null) 'drawingAspectRatio': drawingAspectRatio,
        'timestamp': timestamp,
        'existingFeedbacks': existingFeedbacks,
        'isDevChatEnabled': isDevChatEnabled,
      };

  factory _SnappyDraftData.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['drawingPoints'] as List<dynamic>? ?? [];
    final rawPins = json['pins'] as List<dynamic>? ?? [];
    return _SnappyDraftData(
      imageBytes: base64Decode(json['imageBytesBase64'] as String),
      widgetTree: json['widgetTree'] as Map<String, dynamic>? ?? {},
      screenClassName: json['screenClassName'] as String? ?? '',
      screenSignature: json['screenSignature'] as String? ?? '',
      drawingPoints: rawPoints
          .map((p) => DrawingPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      pins: rawPins
          .map((p) => SnappyPin.fromJson(p as Map<String, dynamic>))
          .toList(),
      memo: json['memo'] as String? ?? '',
      drawingAspectRatio: (json['drawingAspectRatio'] as num?)?.toDouble(),
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      existingFeedbacks: json['existingFeedbacks'] as List<dynamic>? ?? [],
      isDevChatEnabled: json['isDevChatEnabled'] as bool? ?? true,
    );
  }

  static Future<bool> hasDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_draftKey);
    } catch (_) {
      return false;
    }
  }

  static Future<_SnappyDraftData?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawStr = prefs.getString(_draftKey);
      if (rawStr == null || rawStr.isEmpty) return null;
      final json = jsonDecode(rawStr) as Map<String, dynamic>;
      return _SnappyDraftData.fromJson(json);
    } catch (e) {
      SnappySnag._log('⚠️ SnappySnag: Failed to load draft: $e');
      return null;
    }
  }

  static Future<void> save({
    required Uint8List imageBytes,
    required Map<String, dynamic> widgetTree,
    required String screenClassName,
    required String screenSignature,
    required List<DrawingPoint> drawingPoints,
    List<SnappyPin> pins = const [],
    required String memo,
    double? drawingAspectRatio,
    List<dynamic> existingFeedbacks = const [],
    bool isDevChatEnabled = true,
  }) async {
    try {
      final draft = _SnappyDraftData(
        imageBytes: imageBytes,
        widgetTree: widgetTree,
        screenClassName: screenClassName,
        screenSignature: screenSignature,
        drawingPoints: drawingPoints,
        pins: pins,
        memo: memo,
        drawingAspectRatio: drawingAspectRatio,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        existingFeedbacks: existingFeedbacks,
        isDevChatEnabled: isDevChatEnabled,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
      SnappySnag._log('💾 SnappySnag: Draft saved successfully (1 item max).');
    } catch (e) {
      SnappySnag._log('⚠️ SnappySnag: Failed to save draft: $e');
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      SnappySnag._log('🗑️ SnappySnag: Draft cleared.');
    } catch (e) {
      SnappySnag._log('⚠️ SnappySnag: Failed to clear draft: $e');
    }
  }
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
  static String get statusDemoSuccess =>
      _isJa ? '🎯 [デモモード] 送信完了！コンソールログを確認してください。' : '🎯 [Demo Mode] Captured! Check debug console for details.';
  static String get statusRateLimit => _isJa
      ? '送信頻度の上限を超えました。1分ほど待って再度お試しください。'
      : 'Rate limit exceeded. Please wait a minute before retrying.';
  static String get statusGenericError => _isJa
      ? 'フィードバックの送信に失敗しました。しばらく時間をおいて再度お試しください。'
      : 'Failed to send feedback. Please try again later.';
  static String get userModeUnavailable => _isJa
      ? '現在フィードバック機能をご利用いただけません。しばらく時間をおいて再度お試しください。'
      : 'The feedback feature is currently unavailable. Please try again later.';
  static String get statusInvalidKey => _isJa
      ? '[開発エラー] APIキーが無効または停止されています。'
      : '[Dev Error] Invalid or inactive API Key.';
  static String get statusUnauthorizedPackage => _isJa
      ? '[開発エラー] このアプリパッケージは許可されていません。'
      : '[Dev Error] This app package is not authorized.';
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
  static String get delete => _isJa ? '削除' : 'Delete';
  static String get pinCommentTitle => _isJa ? 'ピンのコメント' : 'Pin Comment';
  static String get pinCommentHint => _isJa ? 'この箇所へのコメントを入力...' : 'Add comment for this pin...';
  static String get pinLimitReached => _isJa
      ? 'ピンは最大5個まで配置できます。'
      : 'You can place up to 5 pins.';
  static String get memoOrPinRequiredSnackBar => _isJa
      ? 'ピン留めしてコメントを追加するか、全体のメモを入力してください。'
      : 'Please place a pin with comment or enter a general memo.';
  static String get pinRequiredSnackBar => _isJa
      ? '画面をタップしてピンを立て、コメントを入力してください。'
      : 'Please tap the screen to place a pin and add a comment.';
  static String get tapToPlacePinHint => _isJa
      ? '画面をタップして指摘箇所にピンを立ててください'
      : 'Tap on screen to place feedback pins';

  static String get existingPinsToggle => _isJa ? '指摘エリア' : 'Issue Areas';
  static String get existingPinDetailTitle => _isJa ? '指摘ピンの詳細' : 'Pin Details';
  static String get sectionPinsTitle => _isJa ? 'このエリアの指摘一覧' : 'Issues in this area';
  static String get sectionPinsSub => _isJa ? 'タップして元スクショとピン位置を確認' : 'Tap to preview screenshot and pin';
  static String get allScreenPinsTitle => _isJa ? 'この画面の全指摘一覧' : 'All Issues on this Screen';
  static String get allScreenPinsSub => _isJa ? '画面外・スクロール先を含むすべての指摘' : 'All pins including off-screen/scrolled areas';
  static String get allScreenPinsBtn => _isJa ? '全指摘一覧' : 'All Issues';
  static String get previewOriginalScreenshot => _isJa ? '元スクショプレビュー' : 'Screenshot Preview';
  static String get originalScreenshotNotFound => _isJa ? '元スクショ画像がありません' : 'Original screenshot not found';
  static String get issueBadgePrefix => _isJa ? '指摘 ' : 'Issues: ';
  static String get issueBadgeSuffix => _isJa ? '件' : '';
  static String get nearbyPinsTitle => _isJa ? 'この付近のピンを選択' : 'Select a Pin Nearby';
  static String get nearbyPinsSub => _isJa ? '重なり合っているピンが複数あります' : 'Multiple pins are grouped together';
  static String get noCommentForPin => _isJa ? '（コメントなし）' : '(No comment)';
  static String get close => _isJa ? '閉じる' : 'Close';
  static String get back => _isJa ? '戻る' : 'Back';
  static String get elementAttachedBadge => _isJa ? '要素' : 'Element';

  static String get analyzingScreen =>
      _isJa ? '画面を解析中...' : 'Analyzing screen...';

  // 全消去確認モーダル
  static String get clearConfirmTitle => _isJa ? '全て消去しますか？' : 'Clear All?';
  static String get clearConfirmBody => _isJa
      ? 'ピンとモザイクを全て削除します。この操作は元に戻せません。'
      : 'All pins and mosaic strokes will be deleted. This action cannot be undone.';
  static String get clearConfirmButton => _isJa ? '全て消去' : 'Clear All';

  // 下書き関連
  static String get draftFoundTitle =>
      _isJa ? '保存された下書き' : 'Saved Draft Found';
  static String get draftFoundContent => _isJa
      ? '前回保存した下書きがあります。下書きを再開しますか？'
      : 'You have a saved feedback draft. Would you like to resume it?';
  static String get resumeDraft =>
      _isJa ? '下書きを再開' : 'Resume Draft';
  static String get discardAndNewCapture =>
      _isJa ? '破棄して新規撮影' : 'Discard & Capture New';
  static String get saveDraftPromptTitle =>
      _isJa ? '下書きの保存' : 'Save Draft';
  static String get saveDraftPromptOnCancel => _isJa
      ? '編集中の内容を下書きとして保存しますか？'
      : 'Would you like to save your edits as a draft?';
  static String get saveDraftPromptOnFailedSend => _isJa
      ? '送信に失敗しました。この内容を下書きとして保存しますか？'
      : 'Failed to send feedback. Would you like to save it as a draft?';
  static String get saveDraft =>
      _isJa ? '下書き保存' : 'Save Draft';
  static String get discardDraft =>
      _isJa ? '破棄する' : 'Discard';
  static String get stayOnScreen =>
      _isJa ? '画面に留まる' : 'Stay Here';
  static String get draftSavedToast =>
      _isJa ? '下書きに保存しました' : 'Draft saved successfully.';

  // 開発者機能パスコード認証
  static String get devPasscodeDialogTitle =>
      _isJa ? '開発者パスコード認証' : 'Dev Passcode Required';
  static String get devPasscodeDialogDesc =>
      _isJa ? '内部指摘一覧を表示するには、ダッシュボードのプロジェクト設定に表示されている4桁のパスコードを入力してください。' : 'Please enter the 4-digit passcode configured in your dashboard project settings to view internal tickets.';
  static String get devPasscodeFieldLabel =>
      _isJa ? '4桁のパスコード' : '4-digit Passcode';
  static String get devPasscodeHint =>
      '0000';
  static String get devPasscodeChecking =>
      _isJa ? '確認中...' : 'Checking...';
  static String get devPasscodeInvalid =>
      _isJa ? 'パスコードが正しくありません' : 'Invalid passcode';
  static String get devPasscodeSubmit =>
      _isJa ? '認証' : 'Unlock';
  static String get devPasscodeCancel =>
      _isJa ? 'キャンセル' : 'Cancel';
  static String get devPasscodeSuccess =>
      _isJa ? '開発者モードが認証されました' : 'Dev mode unlocked';
  static String get devPasscodeHeaderRequired =>
      _isJa ? 'パスコードが必要です' : 'Passcode required to view tickets';
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

