import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

class _SnappySnagOverlayState extends State<SnappySnagOverlay> {
  final ScreenshotController _screenshotController = ScreenshotController();
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  bool _isCapturing = false;
  DateTime? _lastShakeTime;

  @override
  void initState() {
    super.initState();
    _initShakeDetection();
  }

  void _initShakeDetection() {
    // SDKが無効の場合はセンサー登録をスキップしてリソースを節約する
    if (!SnappySnag().isEnabled) return;
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
    debugPrint('🎬 SnappySnag: Captured Screen ID: $screenClassName');

    // 即座にスクリーンショットを撮影 (ディレイなしで押した瞬間をキャプチャ)
    final Uint8List? imageBytes = await _screenshotController.capture();

    // 撮影完了後に、ボタンを隠すためのState変更とローディングオーバーレイの表示へ移行
    if (mounted) {
      setState(() => _isCapturing = true);
    }
    await Future.delayed(const Duration(milliseconds: 150));
    _showLoadingOverlay();

    if (imageBytes != null && mounted) {
      try {
        final duplicates = await _fetchExistingFeedbacks(screenClassName);
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
            await _showFeedbackDialog(
              imageBytes,
              widgetTree,
              screenClassName: screenClassName,
            );
          }
        } else {
          await _showFeedbackDialog(
            imageBytes,
            widgetTree,
            screenClassName: screenClassName,
          );
        }
      } on SnappySnagException catch (se) {
        _hideLoadingOverlay();
        if (mounted) {
          _showErrorDialog(se.message);
          setState(() => _isCapturing = false);
        }
        return;
      }

      if (mounted) {
        setState(() => _isCapturing = false);
      }
    } else {
      _hideLoadingOverlay();
    }
  }

  Future<List<dynamic>> _fetchExistingFeedbacks(String screenClassName) async {
    final apiKey = SnappySnag()._apiKey;
    if (apiKey == null) throw SnappySnagException('API Key is not configured.');

    final String url =
        '${SnappySnag().supabaseUrl}/functions/v1/get-existing-feedbacks?screen_class_name=${Uri.encodeComponent(screenClassName)}';

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
      } else if (response.statusCode == 401) {
        throw SnappySnagException('Invalid API Key');
      } else if (response.statusCode == 403) {
        throw SnappySnagException(
          'This API Key is locked to a different application package',
        );
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
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
    final result = await showDialog<bool>(
      context: targetContext,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _SdkLocale.duplicateWarningTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _SdkLocale.duplicateWarningSub,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Scrollbar(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: duplicates.length,
                      itemBuilder: (context, index) {
                        final item = duplicates[index];
                        final memo = item['user_memo'] ?? '';
                        final severity = item['severity'] ?? 'low';
                        final emoji = severity == 'high'
                            ? '🔴'
                            : (severity == 'medium' ? '🟡' : '🔵');

                        return InkWell(
                          onTap: () {
                            Navigator.of(dialogContext).pop(false);
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(
                _SdkLocale.checkLater,
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                _SdkLocale.reportNewIssue,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
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

  void _showCommentsThreadSheet(String feedbackId, String bugTitle) {
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
    final textController = TextEditingController();

    showDialog(
      context: targetContext,
      builder: (dialogContext) {
        List<dynamic> comments = [];
        bool isLoading = true;
        bool isSendingComment = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void loadComments() async {
              final result = await _fetchComments(feedbackId);
              setSheetState(() {
                comments = result;
                isLoading = false;
              });
            }

            if (isLoading && comments.isEmpty) {
              loadComments();
            }

            return Dialog(
              backgroundColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade800),
              ),
              child: Container(
                width: double.maxFinite,
                height: 450,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.chat, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bugTitle,
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
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10),
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.amber,
                              ),
                            )
                          : comments.isEmpty
                              ? Center(
                                  child: Text(
                                    _SdkLocale.noCommentsYet,
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: comments.length,
                                  itemBuilder: (context, index) {
                                    final comment = comments[index];
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
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            maxLength: 500,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
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
                          icon: isSendingComment
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.amber,
                                  ),
                                )
                              : const Icon(Icons.send, color: Colors.amber),
                          onPressed: isSendingComment
                              ? null
                              : () async {
                                  final text = textController.text.trim();
                                  if (text.isEmpty) return;

                                  setSheetState(() => isSendingComment = true);
                                  final success = await _postComment(
                                    feedbackLogId: feedbackId,
                                    message: text,
                                  );

                                  if (success) {
                                    textController.clear();
                                    final updatedComments =
                                        await _fetchComments(feedbackId);
                                    setSheetState(() {
                                      comments = updatedComments;
                                      isSendingComment = false;
                                    });
                                  } else {
                                    setSheetState(
                                      () => isSendingComment = false,
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<int> _sendFeedback({
    required Uint8List imageBytes,
    required Map<String, dynamic> widgetTree,
    required String memo,
    required String screenClassName,
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
          'tags': ['debug', 'feedback'],
          'metadata': {
            'platform': 'flutter',
            'os_name': Platform.operatingSystem,
            'os_version': Platform.operatingSystemVersion,
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
      return -1; // ネットワーク切断を示す独自コード
    }
  }

  Future<void> _showFeedbackDialog(
    Uint8List imageBytes,
    Map<String, dynamic> widgetTree, {
    required String screenClassName,
  }) async {
    final textController = TextEditingController();
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // キャンバス編集用のステート
    final canvasScreenshotController = ScreenshotController();
    List<DrawingPoint> points = [];
    bool isRedPen = true; // true: 赤ペン, false: 黒塗りマスク
    bool isSending = false;
    bool isMemoOpen = false; // メモ入力パネルの開閉フラグ

    await showDialog(
      context: targetContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog.fullscreen(
              child: Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.grey.shade900,
                  leading: TextButton(
                    onPressed: isSending
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                            setState(() => _isCapturing = false);
                          },
                    child: Text(
                      _SdkLocale.cancel,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  title: Text(
                    _SdkLocale.titleFeedback,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                  actions: [
                    TextButton(
                      onPressed: isSending
                          ? null
                          : () async {
                              final memo = textController.text;
                              // メモがない場合は警告
                              if (memo.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _SdkLocale.memoPromptSnackBar,
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                setDialogState(
                                  () => isMemoOpen = true,
                                ); // メモを開いてあげる
                                return;
                              }

                              setDialogState(() => isSending = true);

                              // ⚡️ 1. 赤ペンとマスキングが載ったキャンバスを再キャプチャする
                              final Uint8List? editedBytes =
                                  await canvasScreenshotController.capture();
                              final finalBytes = editedBytes ?? imageBytes;

                              // 2. 送信処理
                              final statusCode = await _sendFeedback(
                                imageBytes: finalBytes,
                                widgetTree: widgetTree,
                                memo: memo,
                                screenClassName: screenClassName,
                              );

                              final success = statusCode == 200;
                              final shouldClose = success ||
                                  statusCode == 401 ||
                                  statusCode == 403;

                              if (shouldClose) {
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                if (mounted) {
                                  setState(() => _isCapturing = false);
                                }
                              } else {
                                setDialogState(() => isSending = false);
                              }

                              if (mounted) {
                                // ignore: use_build_context_synchronously
                                final messengerContext =
                                    SnappySnag().navigatorKey?.currentContext ??
                                        context;
                                String message = _SdkLocale.statusSuccess;
                                if (!success) {
                                  if (statusCode == 429) {
                                    message = _SdkLocale.statusRateLimit;
                                  } else if (statusCode == 401) {
                                    message = _SdkLocale.statusInvalidKey;
                                  } else if (statusCode == 403) {
                                    message =
                                        _SdkLocale.statusUnauthorizedPackage;
                                  } else {
                                    message = _SdkLocale.statusNetworkError;
                                  }
                                }

                                if (messengerContext.mounted) {
                                  ScaffoldMessenger.of(
                                    messengerContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(message),
                                      backgroundColor:
                                          success ? Colors.green : Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isSending
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
                              style: TextStyle(
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
                            aspectRatio: MediaQuery.of(context).size.width /
                                (MediaQuery.of(context).size.height - 160),
                            child: Screenshot(
                              controller: canvasScreenshotController,
                              child: Stack(
                                children: [
                                  // 背景画像
                                  Positioned.fill(
                                    child: Image.memory(
                                      imageBytes,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  // 描画キャンバス
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onPanStart: (details) {
                                        if (isSending || isMemoOpen) return;
                                        setDialogState(() {
                                          points.add(
                                            DrawingPoint(
                                              offsets: [details.localPosition],
                                              color: isRedPen
                                                  ? Colors.red
                                                  : Colors.black.withValues(
                                                      alpha: 0.95,
                                                    ),
                                              strokeWidth:
                                                  isRedPen ? 4.0 : 24.0,
                                            ),
                                          );
                                        });
                                      },
                                      onPanUpdate: (details) {
                                        if (isSending || isMemoOpen) return;
                                        setDialogState(() {
                                          if (points.isNotEmpty) {
                                            points.last.offsets.add(
                                              details.localPosition,
                                            );
                                          }
                                        });
                                      },
                                      onPanEnd: (details) {
                                        if (isSending || isMemoOpen) return;
                                        setDialogState(() {
                                          if (points.isNotEmpty) {
                                            points.last.offsets.add(null);
                                          }
                                        });
                                      },
                                      child: CustomPaint(
                                        painter: DrawingPainter(points: points),
                                        size: Size.infinite,
                                      ),
                                    ),
                                  ),
                                ],
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
                                  color: isRedPen ? Colors.red : Colors.grey,
                                ),
                                tooltip: 'Red Pen',
                                onPressed: isSending
                                    ? null
                                    : () =>
                                        setDialogState(() => isRedPen = true),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.blur_on,
                                  color: !isRedPen ? Colors.white : Colors.grey,
                                ),
                                tooltip: 'Masking',
                                onPressed: isSending
                                    ? null
                                    : () => setDialogState(
                                          () => isRedPen = false,
                                        ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.comment,
                                  color: textController.text.trim().isNotEmpty
                                      ? Colors.amber
                                      : Colors.grey,
                                ),
                                tooltip: 'Memo',
                                onPressed: isSending
                                    ? null
                                    : () => setDialogState(
                                          () => isMemoOpen = true,
                                        ),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                icon: const Icon(
                                  Icons.undo,
                                  color: Colors.white70,
                                ),
                                tooltip: 'Undo',
                                onPressed: isSending || points.isEmpty
                                    ? null
                                    : () => setDialogState(
                                          () => points.removeLast(),
                                        ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'Clear',
                                onPressed: isSending || points.isEmpty
                                    ? null
                                    : () =>
                                        setDialogState(() => points.clear()),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 3. メモ入力用フローティングオーバーレイ
                      if (isMemoOpen)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.75),
                            padding: const EdgeInsets.all(24),
                            child: Center(
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
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: textController,
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
                                          setDialogState(
                                            () => isMemoOpen = false,
                                          );
                                        },
                                        child: Text(
                                          _SdkLocale.done,
                                          style: TextStyle(
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
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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

  BuildContext? _loadingDialogContext;

  void _showLoadingOverlay() {
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;
    showDialog(
      context: targetContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        _loadingDialogContext = dialogContext;
        return PopScope(
          canPop: false, // 戻るボタンでの手動キャンセルを防止
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
        );
      },
    );
  }

  void _hideLoadingOverlay() {
    if (_loadingDialogContext != null) {
      Navigator.of(_loadingDialogContext!).pop();
      _loadingDialogContext = null;
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
        // Tiny Floating Trigger Button
        if (widget.showTriggerButton && !_isCapturing)
          Positioned(
            bottom: 80,
            right: 16,
            child: Material(
              type: MaterialType.transparency,
              child: FloatingActionButton.small(
                onPressed: () => _triggerCapture(),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.8),
                child: const Icon(Icons.bolt, color: Colors.white),
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
      tree = _buildNode(element, 0);
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
    ];
    for (final keyword in frameworkKeywords) {
      if (clean.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> _buildNode(Element element, int depth) {
    final widget = element.widget;
    final String type = widget.runtimeType.toString();

    Map<String, dynamic> node = {'type': type};

    // 主要ウィジェットのプロパティ抽出 ＆ 自動匿名化 (プライバシー保護)
    if (widget is Text) {
      final textData = widget.data ?? '';
      node['text'] = textData.length > 25 ? '[REDACTED]' : textData;
    } else if (type.contains('EditableText') || type.contains('TextField')) {
      node['text'] = '[REDACTED]';
    } else if (widget is Padding) {
      node['padding'] = widget.padding.toString();
    } else if (widget is SizedBox) {
      if (widget.width != null) {
        node['width'] =
            widget.width == double.infinity ? 'infinity' : widget.width;
      }
      if (widget.height != null) {
        node['height'] =
            widget.height == double.infinity ? 'infinity' : widget.height;
      }
    }

    if (widget.key != null) {
      node['key'] = widget.key.toString();
    }

    // ★ 深度が10以上に達した場合は探索を打ち切り
    if (depth >= 10) {
      node['children_truncated'] = true;
      return node;
    }

    // 子ウィジェットを再帰的に走査（バイパス対応）
    List<Map<String, dynamic>> children = [];
    _collectChildren(element, children, depth + 1);

    if (children.isNotEmpty) {
      node['children'] = children;
    }

    return node;
  }

  // ノイズをバイパスしながら子エレメントを収集する再帰ヘルパー
  static void _collectChildren(
    Element element,
    List<Map<String, dynamic>> resultList,
    int depth,
  ) {
    element.visitChildElements((childElement) {
      final childType = childElement.widget.runtimeType.toString();

      if (_isNoiseWidget(childType)) {
        // ノイズウィジェット自身は追加せず、その子供たちを直接現在のリストに引き上げる
        _collectChildren(childElement, resultList, depth);
      } else {
        // ノイズでなければ、通常通りノード化して追加
        resultList.add(_buildNode(childElement, depth));
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

  DrawingPoint({
    required this.offsets,
    required this.color,
    required this.strokeWidth,
  });
}

class SnappySnagException implements Exception {
  final String message;
  SnappySnagException(this.message);
  @override
  String toString() => message;
}

/// Canvas上に線を描画するための CustomPainter
class DrawingPainter extends CustomPainter {
  final List<DrawingPoint> points;

  DrawingPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    for (final point in points) {
      final paint = Paint()
        ..color = point.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = point.strokeWidth
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < point.offsets.length - 1; i++) {
        if (point.offsets[i] != null && point.offsets[i + 1] != null) {
          canvas.drawLine(point.offsets[i]!, point.offsets[i + 1]!, paint);
        } else if (point.offsets[i] != null && point.offsets[i + 1] == null) {
          canvas.drawPoints(ui.PointMode.points, [point.offsets[i]!], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Internal localization helper for SnappySnag SDK.
class _SdkLocale {
  static bool get _isJa => Platform.localeName.toLowerCase().startsWith('ja');

  static String get cancel => _isJa ? 'キャンセル' : 'Cancel';
  static String get send => _isJa ? '送信' : 'Send';
  static String get titleFeedback => _isJa ? 'バグ報告' : 'SnappySnag Feedback';
  static String get memoPromptSnackBar => _isJa
      ? '最初にバグ内容のメモを追加してください。'
      : 'Please add a memo describing the issue first.';

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
      _isJa ? '類似のバグ報告が見つかりました' : 'Similar Feedbacks Found';
  static String get duplicateWarningSub => _isJa
      ? '報告する前に、同様の不具合が既に報告されていないか確認してください。'
      : 'Before submitting, check if your issue is already reported:';
  static String get checkLater => _isJa ? '後で確認する' : 'I will check later';
  static String get reportNewIssue => _isJa ? '新規に報告する' : 'Report New Issue';

  static String get noCommentsYet => _isJa
      ? 'コメントはまだありません。会話を始めましょう！'
      : 'No comments yet. Start the conversation!';
  static String get typeMessage => _isJa ? 'メッセージを入力...' : 'Type a message...';

  static String get describeIssue =>
      _isJa ? 'バグの詳細を説明してください' : 'Describe the issue';
  static String get memoHint => _isJa
      ? '（例: この画面のタイトルのフォントサイズが小さすぎます...）'
      : 'e.g., The title font size is too small on this screen...';
  static String get done => _isJa ? '完了' : 'Done';
}
