// ignore_for_file: unused_element, use_build_context_synchronously
import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'src/browser_info_helper.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart'
    show
        kIsWeb,
        kReleaseMode,
        defaultTargetPlatform,
        DiagnosticsSerializationDelegate;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode of SnappySnag SDK operation.
enum SnappySnagMode {
  /// Developer / Internal QA Mode:
  /// Enables existing feedback pins visualization, inspection, and dev mode tools.
  dev,

  /// End-User / Production Mode:
  /// Hides internal tickets and warnings, offering a clean, friendly feedback submission experience.
  user,
}

enum _SnappyToastType { success, error, warning, info }

/// Visual theme configuration for the SnappySnag SDK.
///
/// Allows customizing accent colors, light/dark mode behavior, and dialog corner radii
/// to blend seamlessly with your application's brand identity.
class SnappySnagTheme {
  /// Primary accent color used for pins, action buttons, and active tools.
  /// Defaults to Amber Gold (`#F59E0B`).
  final Color primaryColor;

  /// Pin marker background color.
  /// If null, falls back to Coral Red (`#F95738`) or [primaryColor].
  final Color? pinColor;

  /// Theme brightness mode.
  /// - [ThemeMode.system]: Follows the host device or MaterialApp theme brightness.
  /// - [ThemeMode.dark]: Enforces dark aesthetic (default).
  /// - [ThemeMode.light]: Enforces clean light aesthetic.
  final ThemeMode themeMode;

  /// Corner radius for floating toolbars, cards, and modal dialogs.
  /// Defaults to 16.0.
  final double borderRadius;

  const SnappySnagTheme({
    this.primaryColor = const Color(0xFFF59E0B),
    this.pinColor,
    this.themeMode = ThemeMode.dark,
    this.borderRadius = 16.0,
  });

  /// Resolves whether the current active theme should render in dark mode.
  bool isDark(BuildContext context) {
    if (themeMode == ThemeMode.dark) return true;
    if (themeMode == ThemeMode.light) return false;
    return MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
  }
}

/// Localization dictionary defining all user-facing texts and dialog messages in SnappySnag SDK.
///
/// Use [SnappySnagLocalization.en()] for English, [SnappySnagLocalization.ja()] for Japanese,
/// or instantiate with custom strings to support other languages (e.g. French, Chinese)
/// or customize specific phrasing using [copyWith].
class SnappySnagLocalization {
  final String disabledTitle;
  final String disabledContent;
  final String start;
  final String ok;
  final String feedbackModeDialogTitle;
  final String feedbackModeDialogContent;
  final String feedbackModeAlreadyVisibleTitle;
  final String feedbackModeAlreadyVisibleContent;
  final String privacyConfirmTitle;
  final String privacyConfirmContent;
  final String Function(String email)? privacyShareAccountWithEmailBuilder;
  final String privacyShareAccount;
  final String privacyAnonymousHint;
  final String backToEdit;
  final String sendConfirm;
  final String cancel;
  final String send;
  final String sending;
  final String titleFeedback;
  final String statusSuccess;
  final String statusDemoSuccess;
  final String statusRateLimit;
  final String statusGenericError;
  final String userModeUnavailable;
  final String statusInvalidKey;
  final String statusUnauthorizedPackage;
  final String statusNetworkError;
  final String done;
  final String delete;
  final String pinCommentTitle;
  final String pinCommentHint;
  final String pinLimitReached;
  final String pinRequiredSnackBar;
  final String close;
  final String back;
  final String elementAttachedBadge;
  final String analyzingScreen;
  final String clearConfirmTitle;
  final String clearConfirmBody;
  final String clearConfirmButton;
  final String draftFoundTitle;
  final String draftFoundContent;
  final String resumeDraft;
  final String discardAndNewCapture;
  final String saveDraftPromptTitle;
  final String saveDraftPromptOnCancel;
  final String saveDraftPromptOnFailedSend;
  final String saveDraft;
  final String discardDraft;
  final String stayOnScreen;
  final String draftSavedToast;

  const SnappySnagLocalization({
    required this.disabledTitle,
    required this.disabledContent,
    required this.start,
    required this.ok,
    required this.feedbackModeDialogTitle,
    required this.feedbackModeDialogContent,
    required this.feedbackModeAlreadyVisibleTitle,
    required this.feedbackModeAlreadyVisibleContent,
    required this.privacyConfirmTitle,
    required this.privacyConfirmContent,
    this.privacyShareAccountWithEmailBuilder,
    required this.privacyShareAccount,
    required this.privacyAnonymousHint,
    required this.backToEdit,
    required this.sendConfirm,
    required this.cancel,
    required this.send,
    required this.sending,
    required this.titleFeedback,
    required this.statusSuccess,
    required this.statusDemoSuccess,
    required this.statusRateLimit,
    required this.statusGenericError,
    required this.userModeUnavailable,
    required this.statusInvalidKey,
    required this.statusUnauthorizedPackage,
    required this.statusNetworkError,
    required this.done,
    required this.delete,
    required this.pinCommentTitle,
    required this.pinCommentHint,
    required this.pinLimitReached,
    required this.pinRequiredSnackBar,
    required this.close,
    required this.back,
    required this.elementAttachedBadge,
    required this.analyzingScreen,
    required this.clearConfirmTitle,
    required this.clearConfirmBody,
    required this.clearConfirmButton,
    required this.draftFoundTitle,
    required this.draftFoundContent,
    required this.resumeDraft,
    required this.discardAndNewCapture,
    required this.saveDraftPromptTitle,
    required this.saveDraftPromptOnCancel,
    required this.saveDraftPromptOnFailedSend,
    required this.saveDraft,
    required this.discardDraft,
    required this.stayOnScreen,
    required this.draftSavedToast,
  });

  String privacyShareAccountWithEmail(String email) {
    if (privacyShareAccountWithEmailBuilder != null) {
      return privacyShareAccountWithEmailBuilder!(email);
    }
    return 'Include diagnostics and account info ($email) to resolve issues';
  }

  /// Built-in English localization dictionary.
  factory SnappySnagLocalization.en() => const SnappySnagLocalization(
        disabledTitle: 'Feedback Feature Disabled',
        disabledContent:
            'The feedback feature is currently disabled and unavailable.',
        start: 'Start',
        ok: 'OK',
        feedbackModeDialogTitle: 'Feedback Mode',
        feedbackModeDialogContent:
            'Navigate freely to the screen you want to report.\nTap the button at the bottom right to capture.',
        feedbackModeAlreadyVisibleTitle: 'Feedback Button',
        feedbackModeAlreadyVisibleContent:
            'The feedback button is already visible at the bottom right.\nTap it anytime to report the current screen.',
        privacyConfirmTitle: 'Privacy Check',
        privacyConfirmContent:
            'Are personal or sensitive details (passwords, address, photos) properly masked with blur?',
        privacyShareAccount: 'Include device diagnostics to resolve issues',
        privacyAnonymousHint:
            'Uncheck to submit anonymously (screenshot and memo only)',
        backToEdit: 'Back to Edit',
        sendConfirm: 'Send',
        cancel: 'Cancel',
        send: 'Send',
        sending: 'Sending...',
        titleFeedback: 'SnappySnag Feedback',
        statusSuccess: 'Feedback sent successfully!',
        statusDemoSuccess:
            '🎯 [Demo Mode] Captured! Check debug console for details.',
        statusRateLimit:
            'Rate limit exceeded. Please wait a minute before retrying.',
        statusGenericError: 'Failed to send feedback. Please try again later.',
        userModeUnavailable:
            'The feedback feature is currently unavailable. Please try again later.',
        statusInvalidKey: '[Dev Error] Invalid or inactive API Key.',
        statusUnauthorizedPackage:
            '[Dev Error] This app package is not authorized.',
        statusNetworkError:
            'Failed to send feedback (Network or Server Error).',
        done: 'Done',
        delete: 'Delete',
        pinCommentTitle: 'Pin Comment',
        pinCommentHint: 'Add comment for this pin...',
        pinLimitReached: 'You can place up to 5 pins.',
        pinRequiredSnackBar:
            'Please tap the screen to place a pin and add a comment.',
        close: 'Close',
        back: 'Back',
        elementAttachedBadge: 'Element',
        analyzingScreen: 'Analyzing screen...',
        clearConfirmTitle: 'Clear All?',
        clearConfirmBody:
            'All pins and mosaic strokes will be deleted. This action cannot be undone.',
        clearConfirmButton: 'Clear All',
        draftFoundTitle: 'Saved Draft Found',
        draftFoundContent:
            'You have a saved feedback draft. Would you like to resume it?',
        resumeDraft: 'Resume Draft',
        discardAndNewCapture: 'Discard & Capture New',
        saveDraftPromptTitle: 'Save Draft',
        saveDraftPromptOnCancel:
            'Would you like to save your edits as a draft?',
        saveDraftPromptOnFailedSend:
            'Failed to send feedback. Would you like to save it as a draft?',
        saveDraft: 'Save Draft',
        discardDraft: 'Discard',
        stayOnScreen: 'Stay Here',
        draftSavedToast: 'Draft saved successfully.',
      );

  /// Built-in Japanese localization dictionary.
  factory SnappySnagLocalization.ja() => SnappySnagLocalization(
        disabledTitle: 'フィードバック機能は無効です',
        disabledContent: '現在フィードバック機能は無効に設定されているため、ご利用いただけません。',
        start: '開始する',
        ok: '了解',
        feedbackModeDialogTitle: 'フィードバックモード',
        feedbackModeDialogContent:
            'アプリを自由に操作して報告したい画面へ移動してください。\n目的の画面で右下のボタンをタップすると撮影できます。',
        feedbackModeAlreadyVisibleTitle: 'フィードバックボタン',
        feedbackModeAlreadyVisibleContent:
            'フィードバック用のボタンは既に画面右下に表示されています。\nいつでもタップして現在の画面を報告できます。',
        privacyConfirmTitle: '送信前の確認',
        privacyConfirmContent: '画面内の個人情報や機密情報（パスワード・住所・顔写真など）はモザイクで隠れていますか？',
        privacyShareAccountWithEmailBuilder: (email) =>
            '問題解決のために診断情報とアカウント情報 ($email) を共有する',
        privacyShareAccount: '問題解決のためにデバイス診断情報を共有する',
        privacyAnonymousHint: '※チェックを外すと匿名（画像とメモのみ）で送信されます',
        backToEdit: '戻って編集',
        sendConfirm: '送信する',
        cancel: 'キャンセル',
        send: '送信',
        sending: '送信中...',
        titleFeedback: 'フィードバック送信',
        statusSuccess: 'フィードバックの送信が成功しました！',
        statusDemoSuccess: '🎯 [デモモード] 送信完了！コンソールログを確認してください。',
        statusRateLimit: '送信頻度の上限を超えました。1分ほど待って再度お試しください。',
        statusGenericError: 'フィードバックの送信に失敗しました。しばらく時間をおいて再度お試しください。',
        userModeUnavailable: '現在フィードバック機能をご利用いただけません。しばらく時間をおいて再度お試しください。',
        statusInvalidKey: '[開発エラー] APIキーが無効または停止されています。',
        statusUnauthorizedPackage: '[開発エラー] このアプリパッケージは許可されていません。',
        statusNetworkError: 'フィードバックの送信に失敗しました（ネットワークまたはサーバーエラー）。',
        done: '完了',
        delete: '削除',
        pinCommentTitle: 'ピンのコメント',
        pinCommentHint: 'この箇所へのコメントを入力...',
        pinLimitReached: 'ピンは最大5個まで配置できます。',
        pinRequiredSnackBar: '画面をタップしてピンを立て、コメントを入力してください。',
        close: '閉じる',
        back: '戻る',
        elementAttachedBadge: '要素',
        analyzingScreen: '画面を解析中...',
        clearConfirmTitle: '全て消去しますか？',
        clearConfirmBody: 'ピンとモザイクを全て削除します。この操作は元に戻せません。',
        clearConfirmButton: '全て消去',
        draftFoundTitle: '保存された下書き',
        draftFoundContent: '前回保存した下書きがあります。下書きを再開しますか？',
        resumeDraft: '下書きを再開',
        discardAndNewCapture: '破棄して新規撮影',
        saveDraftPromptTitle: '下書きの保存',
        saveDraftPromptOnCancel: '編集中の内容を下書きとして保存しますか？',
        saveDraftPromptOnFailedSend: '送信に失敗しました。この内容を下書きとして保存しますか？',
        saveDraft: '下書き保存',
        discardDraft: '破棄する',
        stayOnScreen: '画面に留まる',
        draftSavedToast: '下書きに保存しました',
      );

  /// Resolves the built-in dictionary based on a given [locale].
  /// Defaults to Japanese if the language code starts with 'ja', otherwise English.
  factory SnappySnagLocalization.fromLocale(Locale? locale) {
    final code = locale?.languageCode.toLowerCase() ??
        ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    if (code.startsWith('ja')) {
      return SnappySnagLocalization.ja();
    }
    return SnappySnagLocalization.en();
  }

  /// Creates a copy of this localization dictionary with specified fields replaced.
  SnappySnagLocalization copyWith({
    String? disabledTitle,
    String? disabledContent,
    String? start,
    String? ok,
    String? feedbackModeDialogTitle,
    String? feedbackModeDialogContent,
    String? feedbackModeAlreadyVisibleTitle,
    String? feedbackModeAlreadyVisibleContent,
    String? privacyConfirmTitle,
    String? privacyConfirmContent,
    String Function(String email)? privacyShareAccountWithEmailBuilder,
    String? privacyShareAccount,
    String? privacyAnonymousHint,
    String? backToEdit,
    String? sendConfirm,
    String? cancel,
    String? send,
    String? sending,
    String? titleFeedback,
    String? statusSuccess,
    String? statusDemoSuccess,
    String? statusRateLimit,
    String? statusGenericError,
    String? userModeUnavailable,
    String? statusInvalidKey,
    String? statusUnauthorizedPackage,
    String? statusNetworkError,
    String? done,
    String? delete,
    String? pinCommentTitle,
    String? pinCommentHint,
    String? pinLimitReached,
    String? pinRequiredSnackBar,
    String? close,
    String? back,
    String? elementAttachedBadge,
    String? analyzingScreen,
    String? clearConfirmTitle,
    String? clearConfirmBody,
    String? clearConfirmButton,
    String? draftFoundTitle,
    String? draftFoundContent,
    String? resumeDraft,
    String? discardAndNewCapture,
    String? saveDraftPromptTitle,
    String? saveDraftPromptOnCancel,
    String? saveDraftPromptOnFailedSend,
    String? saveDraft,
    String? discardDraft,
    String? stayOnScreen,
    String? draftSavedToast,
  }) {
    return SnappySnagLocalization(
      disabledTitle: disabledTitle ?? this.disabledTitle,
      disabledContent: disabledContent ?? this.disabledContent,
      start: start ?? this.start,
      ok: ok ?? this.ok,
      feedbackModeDialogTitle:
          feedbackModeDialogTitle ?? this.feedbackModeDialogTitle,
      feedbackModeDialogContent:
          feedbackModeDialogContent ?? this.feedbackModeDialogContent,
      feedbackModeAlreadyVisibleTitle: feedbackModeAlreadyVisibleTitle ??
          this.feedbackModeAlreadyVisibleTitle,
      feedbackModeAlreadyVisibleContent: feedbackModeAlreadyVisibleContent ??
          this.feedbackModeAlreadyVisibleContent,
      privacyConfirmTitle: privacyConfirmTitle ?? this.privacyConfirmTitle,
      privacyConfirmContent:
          privacyConfirmContent ?? this.privacyConfirmContent,
      privacyShareAccountWithEmailBuilder:
          privacyShareAccountWithEmailBuilder ??
              this.privacyShareAccountWithEmailBuilder,
      privacyShareAccount: privacyShareAccount ?? this.privacyShareAccount,
      privacyAnonymousHint: privacyAnonymousHint ?? this.privacyAnonymousHint,
      backToEdit: backToEdit ?? this.backToEdit,
      sendConfirm: sendConfirm ?? this.sendConfirm,
      cancel: cancel ?? this.cancel,
      send: send ?? this.send,
      sending: sending ?? this.sending,
      titleFeedback: titleFeedback ?? this.titleFeedback,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusDemoSuccess: statusDemoSuccess ?? this.statusDemoSuccess,
      statusRateLimit: statusRateLimit ?? this.statusRateLimit,
      statusGenericError: statusGenericError ?? this.statusGenericError,
      userModeUnavailable: userModeUnavailable ?? this.userModeUnavailable,
      statusInvalidKey: statusInvalidKey ?? this.statusInvalidKey,
      statusUnauthorizedPackage:
          statusUnauthorizedPackage ?? this.statusUnauthorizedPackage,
      statusNetworkError: statusNetworkError ?? this.statusNetworkError,
      done: done ?? this.done,
      delete: delete ?? this.delete,
      pinCommentTitle: pinCommentTitle ?? this.pinCommentTitle,
      pinCommentHint: pinCommentHint ?? this.pinCommentHint,
      pinLimitReached: pinLimitReached ?? this.pinLimitReached,
      pinRequiredSnackBar: pinRequiredSnackBar ?? this.pinRequiredSnackBar,
      close: close ?? this.close,
      back: back ?? this.back,
      elementAttachedBadge: elementAttachedBadge ?? this.elementAttachedBadge,
      analyzingScreen: analyzingScreen ?? this.analyzingScreen,
      clearConfirmTitle: clearConfirmTitle ?? this.clearConfirmTitle,
      clearConfirmBody: clearConfirmBody ?? this.clearConfirmBody,
      clearConfirmButton: clearConfirmButton ?? this.clearConfirmButton,
      draftFoundTitle: draftFoundTitle ?? this.draftFoundTitle,
      draftFoundContent: draftFoundContent ?? this.draftFoundContent,
      resumeDraft: resumeDraft ?? this.resumeDraft,
      discardAndNewCapture: discardAndNewCapture ?? this.discardAndNewCapture,
      saveDraftPromptTitle: saveDraftPromptTitle ?? this.saveDraftPromptTitle,
      saveDraftPromptOnCancel:
          saveDraftPromptOnCancel ?? this.saveDraftPromptOnCancel,
      saveDraftPromptOnFailedSend:
          saveDraftPromptOnFailedSend ?? this.saveDraftPromptOnFailedSend,
      saveDraft: saveDraft ?? this.saveDraft,
      discardDraft: discardDraft ?? this.discardDraft,
      stayOnScreen: stayOnScreen ?? this.stayOnScreen,
      draftSavedToast: draftSavedToast ?? this.draftSavedToast,
    );
  }
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
  static final GlobalKey<NavigatorState> defaultNavigatorKey =
      GlobalKey<NavigatorState>();

  String? _apiKey;
  String? _deviceId;
  GlobalKey<NavigatorState>? _customNavigatorKey;
  SnappySnagUser? _user;
  String? _packageName;
  Map<String, dynamic>? _customMetadata;
  String _supabaseUrl =
      'https://apwesndoqpdlgwcylkzj.supabase.co'; // Default is production

  SnappySnagMode _mode = SnappySnagMode.user;
  SnappySnagMode get mode => _mode;
  bool _enableWidgetTree = true;
  bool get enableWidgetTree => _enableWidgetTree;
  bool _enableShakeTrigger = true;
  bool get enableShakeTrigger => _enableShakeTrigger;
  bool _enableHaptics = true;
  bool get enableHaptics => _enableHaptics;
  bool _enableLogging = false;
  bool get enableLogging => _enableLogging;
  SnappySnagTheme _theme = const SnappySnagTheme();
  SnappySnagTheme get theme => _theme;
  Locale? _locale;
  Locale? get locale => _locale;
  SnappySnagLocalization? _customLocalization;

  /// Active localization dictionary for SnappySnag SDK.
  /// Returns custom localization if configured, or resolves based on [locale] / device OS settings.
  SnappySnagLocalization get localization {
    if (_customLocalization != null) {
      return _customLocalization!;
    }
    return SnappySnagLocalization.fromLocale(_locale);
  }

  /// Sets or dynamically updates the active UI locale.
  void setLocale(Locale? locale) {
    _locale = locale;
    _customLocalization = null;
    SnappySnag._log('🌐 SnappySnag: Locale updated to ${locale?.languageCode}');
  }

  /// Sets a custom localization dictionary overriding standard translations.
  /// Pass `null` to clear the custom dictionary and fall back to [locale] resolution.
  void setLocalization(SnappySnagLocalization? localization) {
    _customLocalization = localization;
    SnappySnag._log(
        '🌐 SnappySnag: Custom localization dictionary ${localization != null ? "applied" : "cleared"}');
  }

  /// Current user/reporter information.
  SnappySnagUser? get user => _user;
  String? get reporterUserId => _user?.id;
  String? get reporterEmail => _user?.email;

  /// ValueNotifier holding and notifying the floating trigger button visibility.
  final ValueNotifier<bool> isTriggerButtonVisible = ValueNotifier<bool>(true);

  /// Base trigger button visibility setting (configured during initialize).
  bool _baseTriggerButtonVisibility = true;

  /// Reference count for temporary hide requests (e.g. from SnappySnagHideButton).
  int _hideRequestsCount = 0;

  /// Whether the floating trigger button is currently visible.
  bool get isTriggerButtonAlwaysVisible => isTriggerButtonVisible.value;

  /// Shows the floating trigger button.
  void showTriggerButton() {
    _baseTriggerButtonVisibility = true;
    _updateTriggerButtonVisibility();
  }

  /// Hides the floating trigger button.
  void hideTriggerButton() {
    _baseTriggerButtonVisibility = false;
    _updateTriggerButtonVisibility();
  }

  /// Toggles visibility of the floating trigger button.
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
    final shouldBeVisible =
        _baseTriggerButtonVisibility && _hideRequestsCount == 0;
    if (isTriggerButtonVisible.value != shouldBeVisible) {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        binding.addPostFrameCallback((_) {
          final currentTarget =
              _baseTriggerButtonVisibility && _hideRequestsCount == 0;
          if (isTriggerButtonVisible.value != currentTarget) {
            isTriggerButtonVisible.value = currentTarget;
          }
        });
      } else {
        isTriggerButtonVisible.value = shouldBeVisible;
      }
    }
  }

  /// ValueNotifier notifying the active state of Feedback Mode.
  final ValueNotifier<bool> isFeedbackModeActive = ValueNotifier<bool>(false);

  /// Starts Feedback Mode from an in-app button (e.g. settings screen).
  static void startFeedbackMode({BuildContext? context}) {
    final ctx = context ?? SnappySnag().navigatorKey?.currentContext;

    final theme = SnappySnag().theme;

    // Show dialog if SDK is disabled (isEnabled == false)
    if (!SnappySnag().isEnabled) {
      if (ctx != null) {
        final isDark = theme.isDark(ctx);
        final dialogBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
        final dialogBorder =
            isDark ? const Color(0xFF2E2E38) : Colors.grey.shade300;
        final titleColor = isDark ? Colors.white : Colors.black87;
        final bodyColor = isDark ? Colors.white70 : Colors.black54;

        showDialog(
          context: ctx,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.borderRadius),
              side: BorderSide(color: dialogBorder),
            ),
            title: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  _SdkLocale.disabledTitle,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              _SdkLocale.disabledContent,
              style: TextStyle(
                color: bodyColor,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isDark ? const Color(0xFF3E3E48) : Colors.grey.shade300,
                  foregroundColor: isDark ? Colors.white : Colors.black87,
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
        debugPrint(
            '⚠️ SnappySnag Warning: Cannot show disabled dialog because BuildContext is null. Please pass context to SnappySnag.startFeedbackMode(context: context) or pass navigatorKey to SnappySnag().initialize().');
      }
      SnappySnag._log(
          'ℹ️ SnappySnag: Feedback feature is currently disabled (enabled: false).');
      return;
    }

    final isAlreadyVisible = SnappySnag().isTriggerButtonAlwaysVisible;

    if (ctx != null) {
      final isDark = theme.isDark(ctx);
      final dialogBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
      final dialogBorder =
          isDark ? const Color(0xFF2E2E38) : Colors.grey.shade300;
      final titleColor = isDark ? Colors.white : Colors.black87;
      final bodyColor = isDark ? Colors.white70 : Colors.black54;
      final primaryColor = theme.primaryColor;

      showDialog(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.borderRadius),
            side: BorderSide(color: dialogBorder),
          ),
          title: Row(
            children: [
              Icon(Icons.camera_alt_outlined, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                isAlreadyVisible
                    ? _SdkLocale.feedbackModeAlreadyVisibleTitle
                    : _SdkLocale.feedbackModeDialogTitle,
                style: TextStyle(
                  color: titleColor,
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
            style: TextStyle(
              color: bodyColor,
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
                  style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor:
                    ThemeData.estimateBrightnessForColor(primaryColor) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
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

  /// Cancels and terminates Feedback Mode.
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
  GlobalKey<NavigatorState>? get navigatorKey =>
      _customNavigatorKey ?? SnappySnag.defaultNavigatorKey;

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
    bool enableHaptics = true,
    bool enableLogging = false,
    SnappySnagTheme? theme,
    Locale? locale,
    SnappySnagLocalization? localization,
    String? supabaseUrl,
    bool forceDevInRelease = false,
  }) {
    if (theme != null) {
      _theme = theme;
    }
    _locale = locale;
    _customLocalization = localization;
    _enableLogging = enableLogging;
    _enableHaptics = enableHaptics;
    // Trigger button visibility:
    // Default is hidden (false) for safety regardless of mode.
    // Set showTriggerButton: true to display the button for manual testing.
    _baseTriggerButtonVisibility = showTriggerButton;
    _updateTriggerButtonVisibility();
    _enableWidgetTree = enableWidgetTree;
    _enableShakeTrigger = enableShakeTrigger;
    // Safety guard in Release mode:
    // When mode: SnappySnagMode.dev is specified in production builds,
    // automatically fall back to user mode unless forceDevInRelease: true is explicitly set.
    if (kReleaseMode && mode == SnappySnagMode.dev && !forceDevInRelease) {
      _mode = SnappySnagMode.user;
      // High-priority notification: Security guard warning
      debugPrint(
          '🛡️ SnappySnag Security Guard: SnappySnagMode.dev was specified in release mode without forceDevInRelease: true. Automatically falling back to SnappySnagMode.user to protect internal tickets & developer chats.');
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
      // Demo / Sandbox mode notification
      debugPrint(
          '🎯 [SnappySnag] Demo/Sandbox Mode Active! Local capturing & pin testing enabled without server account.');
    } else if (_apiKey == null || _apiKey!.trim().isEmpty) {
      // Essential config warning
      debugPrint('⚠️ SnappySnag Warning: apiKey is empty or not configured.');
    }
    _log('🚀 SnappySnag initialized.');
  }

  /// Internal utility to output logs via `debugPrint` only when [enableLogging] is true.
  /// Defaults to false (silent) to avoid cluttering host app console logs.
  static void _log(String message) {
    if (SnappySnag()._enableLogging) {
      debugPrint(message);
    }
  }

  /// Sets or dynamically updates user/reporter information.
  void setUser(SnappySnagUser? user) {
    _user = user;
    SnappySnag._log(
      '👤 SnappySnag: User info updated (ID: ${user?.id}, Email: ${user?.email}, Name: ${user?.name})',
    );
  }

  /// Clears user information (e.g. on user logout).
  void clearUser() {
    _user = null;
    SnappySnag._log('👤 SnappySnag: User info cleared.');
  }

  /// Retrieves device-unique random UUID (generates and persists locally on first run).
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
      SnappySnag._log(
          '⚠️ SnappySnag: Failed to access SharedPreferences for deviceId: $e');
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
  State<SnappySnagOverlay> createState() => SnappySnagOverlayState();
}

enum _SnappyOverlayMode {
  none,
  loading,
  drawing,
}

class SnappySnagOverlayState extends State<SnappySnagOverlay> {
  final ScreenshotController _screenshotController = ScreenshotController();
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  bool _isCapturing = false;
  Uint8List? _capturedImageForFreeze;
  _SnappyOverlayMode _overlayMode = _SnappyOverlayMode.none;
  bool _isFeedbackDialogOpen = false;

  // State for canvas drawing & pin annotations
  Uint8List? _drawingImageBytes;
  Map<String, dynamic> _drawingWidgetTree = {};
  String _drawingScreenClassName = '';
  String _drawingScreenSignature = '';
  List<DrawingPoint> _drawingPoints = [];
  List<SnappyPin> _pins = [];
  // Unified undo/redo history stack:
  // Records SnappyPin (pin addition) or DrawingPoint (mosaic stroke) in chronological order
  final List<Object> _undoStack = [];
  final List<Object> _redoStack = [];
  SnappyPin? _editingPin;
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
  bool _includeAccountAndDiagnostics = true;
  final TextEditingController _feedbackMemoController = TextEditingController();
  final ScreenshotController _canvasScreenshotController =
      ScreenshotController();
  Completer<void>? _drawingCompleter;
  double? _drawingAspectRatio;

  DateTime? _lastShakeTime;
  int _shakeFlipCount = 0;
  DateTime? _firstFlipTime;
  double _lastSignX = 0;
  double _lastSignY = 0;

  // Custom Toast State (rendered at top of overlay stack)
  String? _toastMessage;
  _SnappyToastType _toastType = _SnappyToastType.info;
  bool _isToastVisible = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _initShakeDetection();
  }

  void _initShakeDetection() {
    // Skip sensor subscription if SDK is disabled or shake trigger is turned off
    if (!SnappySnag().isEnabled || !SnappySnag().enableShakeTrigger) return;

    // Disable shake detection on non-mobile platforms (Web, macOS, Windows, Linux)
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!isMobile) return;

    // High-precision shake detection to prevent false triggers from tilt or pickup:
    // 1. Threshold: Acceleration >= 22.0 m/s^2 unreachable by casual hand tilting
    // 2. Flip count: Triggers only when acceleration sign rapidly alternates 2+ times within 600ms
    const double shakeThreshold = 22.0;

    _accelerometerSubscription = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        if (_isCapturing ||
            _isFeedbackDialogOpen ||
            _overlayMode != _SnappyOverlayMode.none) {
          return;
        }

        // Calculate G-force vector length
        final double gForce = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        if (gForce > shakeThreshold) {
          final now = DateTime.now();
          final currentSignX =
              event.x.abs() > 8.0 ? (event.x > 0 ? 1.0 : -1.0) : 0.0;
          final currentSignY =
              event.y.abs() > 8.0 ? (event.y > 0 ? 1.0 : -1.0) : 0.0;

          // Reset flip count if more than 600ms elapsed since the previous flip
          if (_firstFlipTime == null ||
              now.difference(_firstFlipTime!) >
                  const Duration(milliseconds: 600)) {
            _shakeFlipCount = 1;
            _firstFlipTime = now;
            _lastSignX = currentSignX;
            _lastSignY = currentSignY;
          } else {
            // Detect sharp direction reversal (positive/negative flip from wrist motion)
            final bool isReversedX = (currentSignX != 0.0 &&
                _lastSignX != 0.0 &&
                currentSignX != _lastSignX);
            final bool isReversedY = (currentSignY != 0.0 &&
                _lastSignY != 0.0 &&
                currentSignY != _lastSignY);

            if (isReversedX || isReversedY) {
              _shakeFlipCount++;
              _lastSignX = currentSignX != 0.0 ? currentSignX : _lastSignX;
              _lastSignY = currentSignY != 0.0 ? currentSignY : _lastSignY;

              // Confirm genuine shake after 2 or more sharp reversals
              if (_shakeFlipCount >= 2) {
                _shakeFlipCount = 0;
                _firstFlipTime = null;

                // Anti-chattering (ensure at least 2 seconds between capture triggers)
                if (_lastShakeTime == null ||
                    now.difference(_lastShakeTime!) >
                        const Duration(seconds: 2)) {
                  _lastShakeTime = now;
                  SnappySnag._log(
                      '📱 SnappySnag: Genuine device shake detected (gForce: ${gForce.toStringAsFixed(1)}). Triggering capture.');
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
    _toastTimer?.cancel();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  @visibleForTesting
  void showToastForTesting({
    required String message,
    bool isSuccess = true,
  }) {
    _showToast(
      targetContext: context,
      message: message,
      type: isSuccess ? _SnappyToastType.success : _SnappyToastType.error,
    );
  }

  void _showToast({
    required BuildContext targetContext,
    required String message,
    _SnappyToastType type = _SnappyToastType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;

    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastType = type;
      _isToastVisible = true;
    });

    _toastTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _isToastVisible = false;
        });
      }
    });
  }

  void _showErrorDialog(String message) {
    final isUserMode = SnappySnag().mode == SnappySnagMode.user;
    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // In user mode, suppress technical dialogs and show a friendly toast/SnackBar instead
    if (isUserMode) {
      SnappySnag._log(
          '⚠️ SnappySnag [UserMode] Suppressed error dialog: $message');
      _showToast(
        targetContext: targetContext,
        message: _SdkLocale.userModeUnavailable,
        type: _SnappyToastType.error,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    // Determine package lock restrictions (locked / package / archived / free plan) with top priority
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
    final isDemo = SnappySnag().isDemoMode;
    final apiKey = SnappySnag()._apiKey;

    if (!isDemo && (apiKey == null || apiKey.trim().isEmpty)) {
      _showErrorDialog(
        'SnappySnag is not properly configured. Please check that apiKey is set during initialization.',
      );
      return;
    }

    final targetContext = SnappySnag().navigatorKey?.currentContext ?? context;

    // Draft check: inspect locally whether a saved draft exists (without network request)
    final hasDraft = await _SnappyDraftData.hasDraft();
    if (hasDraft && mounted && targetContext.mounted) {
      final theme = SnappySnag().theme;
      final isDark = theme.isDark(targetContext);
      final dialogBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
      final dialogBorder =
          isDark ? const Color(0xFF2E2E38) : Colors.grey.shade300;
      final titleColor = isDark ? Colors.white : Colors.black87;
      final bodyColor = isDark ? Colors.white70 : Colors.black54;
      final primaryColor = theme.primaryColor;

      final resume = await showDialog<bool>(
        context: targetContext,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.borderRadius),
            side: BorderSide(color: dialogBorder),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_note, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                _SdkLocale.draftFoundTitle,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            _SdkLocale.draftFoundContent,
            style: TextStyle(
              color: bodyColor,
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
                backgroundColor: primaryColor,
                foregroundColor:
                    ThemeData.estimateBrightnessForColor(primaryColor) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
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
        // Load and resume draft
        final draft = await _SnappyDraftData.load();
        if (draft != null && mounted) {
          setState(() {
            _isCapturing = false;
            _capturedImageForFreeze = null;
            _isFeedbackDialogOpen = true;
          });
          try {
            await _startDrawingFlow(
              draft.imageBytes,
              draft.widgetTree,
              screenClassName: draft.screenClassName,
              screenSignature: draft.screenSignature,
              initialCustomPoints: draft.drawingPoints,
              initialPins: draft.pins,
              initialMemo: draft.memo,
              initialAspectRatio: draft.drawingAspectRatio,
            );
          } finally {
            if (mounted) {
              setState(() => _isFeedbackDialogOpen = false);
            }
          }
          return;
        }
      } else {
        // Clear saved draft if user opted to discard and take new capture
        await _SnappyDraftData.clear();
        // Wait for discard dialog pop animation to fully complete before capturing
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // === High-Speed Instant Pre-Capture: freeze UI state on button press ===
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
    // Automatically detect global bounds of sensitive fields (password, email, etc.)
    final List<Rect> sensitiveBounds =
        WidgetTreeDumper.findSensitiveFieldBounds(
      targetContext,
    );
    SnappySnag._log(
        '🎬 SnappySnag: Captured Screen ID: $screenClassName, Signature: $screenSignature, Sensitive Areas: ${sensitiveBounds.length}');

    // Immediately capture screenshot (zero delay to freeze button-press moment)
    final Uint8List? imageBytes = await _screenshotController.capture();
    if (SnappySnag().enableHaptics) {
      HapticFeedback.mediumImpact();
    }

    // After capture completes, update state to hide trigger button and show loading overlay
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
        // Pre-validation of authentication & active status:
        // Validates API Key & Package Name with server regardless of mode.
        // Throws SnappySnagException on 401/403 so errors are caught early before user begins editing.
        await _fetchExistingFeedbacks(screenClassName, screenSignature);
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

  Future<List<dynamic>> _fetchExistingFeedbacks(
      String screenClassName, String screenSignature) async {
    if (SnappySnag().isDemoMode) {
      SnappySnag._log('🎯 [SnappySnag Demo] Skipping server pre-validation.');
      return [];
    }

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
        // Write-Only security model: only pre-validates API key and package lock, never returns existing feedback items
        return [];
      } else {
        String serverError = '';
        try {
          final data = jsonDecode(response.body);
          serverError = data['error'] as String? ?? '';
        } catch (_) {}

        if (response.statusCode == 401) {
          throw SnappySnagException(
              serverError.isNotEmpty ? serverError : 'Invalid API Key');
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
      SnappySnag._log('❌ SnappySnag Pre-validation Error: $e');
    }
    return [];
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
          'widget_tree': (SnappySnag().enableWidgetTree &&
                  (_includeAccountAndDiagnostics ||
                      SnappySnag().mode != SnappySnagMode.user))
              ? widgetTree
              : <String, dynamic>{},
          'memo': memo,
          'pins': pins.map((p) => p.toJson()).toList(),
          'screen_class_name': screenClassName,
          'screen_signature': screenSignature,
          'tags': [
            'debug',
            'feedback',
            SnappySnag().mode == SnappySnagMode.user
                ? 'user_feedback'
                : 'dev_report',
          ],
          'metadata': {
            'device_id': deviceId,
            'platform': 'flutter',
            'os_name': kIsWeb
                ? 'web_${defaultTargetPlatform.name.toLowerCase()}'
                : Platform.operatingSystem,
            'os_version': kIsWeb
                ? getBrowserInfoHelper()
                : Platform.operatingSystemVersion,
            'package_name': SnappySnag()._packageName,
            'reporter_user_id': (_includeAccountAndDiagnostics ||
                    SnappySnag().mode != SnappySnagMode.user)
                ? (SnappySnag().reporterUserId ?? 'anonymous')
                : 'anonymous',
            'reporter_email': (_includeAccountAndDiagnostics ||
                    SnappySnag().mode != SnappySnagMode.user)
                ? (SnappySnag().reporterEmail ?? 'anonymous')
                : 'anonymous',
            if (SnappySnag()._user?.name != null &&
                (_includeAccountAndDiagnostics ||
                    SnappySnag().mode != SnappySnagMode.user))
              'reporter_name': SnappySnag()._user!.name!,
            'mode': SnappySnag().mode == SnappySnagMode.user ? 'user' : 'dev',
            'is_anonymous': (SnappySnag().mode == SnappySnagMode.user &&
                !_includeAccountAndDiagnostics),
            if (_includeAccountAndDiagnostics ||
                SnappySnag().mode != SnappySnagMode.user)
              ...?SnappySnag()._user?.customAttributes,
            if (_includeAccountAndDiagnostics ||
                SnappySnag().mode != SnappySnagMode.user)
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
      if (!kIsWeb &&
          Platform.isMacOS &&
          e.toString().contains('Operation not permitted')) {
        debugPrint(
            '⚠️ [SnappySnag WARNING] macOS Sandbox Network client restriction detected!');
        debugPrint(
            '======================================================================');
        debugPrint(
            'To allow internet access for your macOS build, please add:');
        debugPrint('  <key>com.apple.security.network.client</key>');
        debugPrint('  <true/>');
        debugPrint(
            'inside macos/Runner/DebugProfile.entitlements and Release.entitlements.');
        debugPrint(
            '======================================================================');
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
  }) async {
    if (!mounted) return;
    _drawingCompleter = Completer<void>();
    final mediaSize = MediaQuery.of(context).size;
    final capturedAspect = initialAspectRatio ??
        (mediaSize.height > 0
            ? (mediaSize.width / mediaSize.height)
            : (9 / 16));

    // Automatically detect sensitive fields and add initial masking points
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
      _activeTool = SnappyDrawingTool.pin;
      _isSendingFeedback = false;
      _isMemoOpen = false;
      _isPrivacyConfirmOpen = false;
      _isCancelDraftConfirmOpen = false;
      _isFailedSendDraftConfirmOpen = false;
      _isClearConfirmOpen = false;
      _feedbackMemoController.text = initialMemo ?? '';
      _drawingAspectRatio = capturedAspect;
      _overlayMode = _SnappyOverlayMode.drawing;
    });
    return _drawingCompleter!.future;
  }

  void _renumberPins() {
    for (int i = 0; i < _pins.length; i++) {
      _pins[i] = _pins[i].copyWith(number: i + 1);
    }
  }

  Future<void> _cancelDrawingFlow() async {
    // Check if user has added pins or non-rect mosaic drawings
    final hasUserEdits =
        _pins.isNotEmpty || _drawingPoints.any((p) => p.rect == null);

    if (hasUserEdits && mounted) {
      // Display inline dialog to ensure topmost visibility inside fullscreen OverlayEntry
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
      _overlayMode = _SnappyOverlayMode.none;
      _isCapturing = false;
    });
    _drawingCompleter?.complete();
  }

  Future<void> _sendFeedbackInlineFlow() async {
    // Check if at least 1 pin has a non-empty comment
    final validPins = _pins.where((p) => p.comment.trim().isNotEmpty).toList();
    if (validPins.isEmpty) {
      if (mounted) {
        final messengerContext =
            SnappySnag().navigatorKey?.currentContext ?? context;
        _showToast(
          targetContext: messengerContext,
          message: _SdkLocale.pinRequiredSnackBar,
          type: _SnappyToastType.warning,
          duration: const Duration(seconds: 3),
        );
      }
      return;
    }

    // In user mode, open privacy confirmation dialog in topmost overlay
    if (SnappySnag().mode == SnappySnagMode.user) {
      setState(() {
        _isPrivacyConfirmOpen = true;
      });
      return;
    }

    // In dev mode, immediately proceed with submission
    await _executeFeedbackSubmission();
  }

  Future<void> _executeFeedbackSubmission() async {
    // Automatically synthesize summary text from itemized pin comments
    final validPins = _pins.where((p) => p.comment.trim().isNotEmpty).toList();
    final memo =
        validPins.map((p) => '【Pin ${p.number}】${p.comment.trim()}').join('\n');
    setState(() {
      _isPrivacyConfirmOpen = false;
      _isSendingFeedback = true;
    });

    // 1. Re-capture canvas with mosaic masking only (pins are preserved as vectors)
    final Uint8List? editedBytes = await _canvasScreenshotController.capture();
    final finalBytes = editedBytes ?? _drawingImageBytes!;

    // 2. Submission (simulated locally in demo mode)
    final _FeedbackResponse feedbackRes;
    if (SnappySnag().isDemoMode) {
      debugPrint(
          '\n======================================================================');
      debugPrint('🎯 [SnappySnag Demo Mode] Feedback Captured Successfully!');
      debugPrint(
          '======================================================================');
      debugPrint('📍 Screen: $_drawingScreenClassName');
      debugPrint('💬 Memo:\n$memo');
      debugPrint('📌 Pins count: ${_pins.length}');
      for (final p in _pins) {
        debugPrint(
            '  - Pin #${p.number}: "${p.comment}" (x: ${p.xRatio.toStringAsFixed(2)}, y: ${p.yRatio.toStringAsFixed(2)}, widget: ${p.target?.widgetType ?? "Unknown"})');
      }
      debugPrint(
          '🌳 Widget Tree: ${_drawingWidgetTree.keys.join(", ")} (${_drawingWidgetTree.length} nodes)');
      debugPrint(
          '----------------------------------------------------------------------');
      debugPrint(
          '👉 To sync feedback to GitHub Issues and enable AI auto-fix,');
      debugPrint('   get your free API key at: https://snappysnag.com');
      debugPrint(
          '======================================================================\n');

      // Slight simulated network delay for smooth UX
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
      if (SnappySnag().enableHaptics) {
        HapticFeedback.lightImpact();
      }
      // Clear draft on successful submission and close overlay
      await _SnappyDraftData.clear();
      setState(() {
        _overlayMode = _SnappyOverlayMode.none;
        _isCapturing = false;
      });
      _drawingCompleter?.complete();
    } else {
      // Retain modal state on submission failure to allow retries
      setState(() {
        _isSendingFeedback = false;
      });
    }

    // Feedback notification toast
    if (mounted) {
      final messengerContext =
          SnappySnag().navigatorKey?.currentContext ?? context;
      final isUserMode = SnappySnag().mode == SnappySnagMode.user;
      final isDemo = SnappySnag().isDemoMode;
      String message =
          isDemo ? _SdkLocale.statusDemoSuccess : _SdkLocale.statusSuccess;
      if (!success) {
        if (isUserMode) {
          // For end users: friendly, calm message
          message = _SdkLocale.statusGenericError;
          SnappySnag._log(
              '⚠️ SnappySnag [UserMode] Submit failed (code: ${feedbackRes.statusCode}, msg: ${feedbackRes.errorMessage})');
        } else {
          // For developers: detailed diagnostics message
          if (feedbackRes.errorMessage != null &&
              feedbackRes.errorMessage!.isNotEmpty) {
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
                message =
                    'Network error: macOS network.client entitlement may be missing.';
              } else {
                message = _SdkLocale.statusNetworkError;
              }
            }
          }
        }
      }

      _showToast(
        targetContext: messengerContext,
        message: message,
        type: success ? _SnappyToastType.success : _SnappyToastType.error,
        duration: const Duration(seconds: 4),
      );

      // Offer saving draft on send failure via inline modal
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
    // If the SDK itself is disabled, return raw child without overlay decorations
    if (!SnappySnag().isEnabled) {
      return widget.child;
    }
    return Stack(
      children: [
        // Screenshot wrapper
        Screenshot(controller: _screenshotController, child: widget.child),
        // During capture: freeze live screen with captured image (touches pass through via IgnorePointer)
        if (_isCapturing && _capturedImageForFreeze != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Image.memory(
                _capturedImageForFreeze!,
                fit: BoxFit.fill,
              ),
            ),
          ),
        // Inline overlay dialog (Z-Index solution)
        if (_overlayMode == _SnappyOverlayMode.loading)
          Positioned.fill(
            child: Container(
              color: Colors.black45, // Semi-transparent modal barrier
              child: Center(
                child: Builder(
                  builder: (dialogContext) {
                    final theme = SnappySnag().theme;
                    final isDark = theme.isDark(dialogContext);
                    final dialogBg =
                        isDark ? const Color(0xFF1E1E24) : Colors.white;
                    final dialogBorder =
                        isDark ? const Color(0xFF2E2E38) : Colors.grey.shade300;
                    final textColor = isDark ? Colors.white : Colors.black87;

                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: dialogBg,
                        borderRadius: BorderRadius.circular(theme.borderRadius),
                        border: Border.all(color: dialogBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: theme.primaryColor),
                          const SizedBox(height: 16),
                          Text(
                            _SdkLocale.analyzingScreen,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        // ⚡️ Inline drawing and feedback submission screen
        if (_overlayMode == _SnappyOverlayMode.drawing &&
            _drawingImageBytes != null)
          Positioned.fill(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (overlayContext) {
                    final canvasRatio = _drawingAspectRatio ?? (9 / 16);
                    final theme = SnappySnag().theme;
                    final isDark = theme.isDark(overlayContext);
                    final primaryColor = theme.primaryColor;
                    final pinColor = theme.pinColor ?? const Color(0xFFF95738);
                    final barBgColor =
                        isDark ? Colors.grey.shade900 : Colors.white;
                    final barTextColor = isDark ? Colors.white : Colors.black87;
                    final barSubtextColor =
                        isDark ? Colors.grey.shade400 : Colors.grey.shade600;
                    final dialogBg =
                        isDark ? const Color(0xFF1E1E24) : Colors.white;
                    final dialogBorder =
                        isDark ? const Color(0xFF2E2E38) : Colors.grey.shade300;
                    final dialogRadius =
                        BorderRadius.circular(theme.borderRadius);

                    return Material(
                      type: MaterialType.transparency,
                      child: Scaffold(
                        backgroundColor:
                            isDark ? Colors.black : const Color(0xFFF0F0F2),
                        appBar: AppBar(
                          backgroundColor: barBgColor,
                          leading: TextButton(
                            onPressed: _isSendingFeedback
                                ? null
                                : () => _cancelDrawingFlow(),
                            child: Text(
                              _SdkLocale.cancel,
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.white70 : Colors.black54),
                            ),
                          ),
                          title: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _SdkLocale.titleFeedback,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: barTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Screen: $_drawingScreenSignature',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: barSubtextColor,
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
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: primaryColor,
                                      ),
                                    )
                                  : Text(
                                      _SdkLocale.send,
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        body: SafeArea(
                          child: Stack(
                            children: [
                              // 1. Drawing canvas area (expanded fullscreen)
                              Positioned.fill(
                                bottom:
                                    80, // Reserve space for the bottom toolbar
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: canvasRatio,
                                    child: LayoutBuilder(
                                      builder: (layoutContext, constraints) {
                                        final canvasSize = Size(
                                            constraints.maxWidth,
                                            constraints.maxHeight);
                                        return Stack(
                                          children: [
                                            // 1. Screenshot capture target (background image + mosaic blur only)
                                            // Note: Pins are not baked into the screenshot image, but saved and synchronized as coordinate/comment metadata.
                                            Positioned.fill(
                                              child: Screenshot(
                                                controller:
                                                    _canvasScreenshotController,
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
                                                        painter: DrawingPainter(
                                                            points:
                                                                _drawingPoints),
                                                        size: Size.infinite,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // 2. Gesture listener layer for drawing and pin placement
                                            Positioned.fill(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTapUp: (details) {
                                                  if (_isSendingFeedback ||
                                                      _isMemoOpen ||
                                                      _editingPin != null) {
                                                    return;
                                                  }
                                                  if (_activeTool ==
                                                      SnappyDrawingTool.pin) {
                                                    // Pin count limit check (maximum 5)
                                                    if (_pins.length >= 5) {
                                                      final messengerContext =
                                                          SnappySnag()
                                                                  .navigatorKey
                                                                  ?.currentContext ??
                                                              context;
                                                      _showToast(
                                                        targetContext:
                                                            messengerContext,
                                                        message: _SdkLocale
                                                            .pinLimitReached,
                                                        type: _SnappyToastType
                                                            .warning,
                                                        duration:
                                                            const Duration(
                                                                seconds: 2),
                                                      );
                                                      return;
                                                    }

                                                    final double xRatio =
                                                        (details.localPosition
                                                                    .dx /
                                                                canvasSize
                                                                    .width)
                                                            .clamp(0.0, 1.0);
                                                    final double yRatio =
                                                        (details.localPosition
                                                                    .dy /
                                                                canvasSize
                                                                    .height)
                                                            .clamp(0.0, 1.0);
                                                    final int nextNumber = _pins
                                                            .isEmpty
                                                        ? 1
                                                        : (_pins
                                                                .map((p) =>
                                                                    p.number)
                                                                .reduce((a,
                                                                        b) =>
                                                                    a > b
                                                                        ? a
                                                                        : b) +
                                                            1);
                                                    // Identify anchor information for the topmost UI element at tapped coordinates.
                                                    // Traverses the application screen tree (targetContext) instead of overlayContext,
                                                    // converting canvas ratios (xRatio, yRatio) into global screen coordinates.
                                                    final targetContext =
                                                        SnappySnag()
                                                                .navigatorKey
                                                                ?.currentContext ??
                                                            context;
                                                    final targetRenderBox =
                                                        targetContext
                                                                .findRenderObject()
                                                            as RenderBox?;
                                                    final targetOrigin =
                                                        (targetRenderBox !=
                                                                    null &&
                                                                targetRenderBox
                                                                    .attached)
                                                            ? targetRenderBox
                                                                .localToGlobal(
                                                                    Offset.zero)
                                                            : Offset.zero;
                                                    final targetSize =
                                                        (targetRenderBox !=
                                                                    null &&
                                                                targetRenderBox
                                                                    .attached &&
                                                                targetRenderBox
                                                                    .hasSize)
                                                            ? targetRenderBox
                                                                .size
                                                            : MediaQuery.of(
                                                                    targetContext)
                                                                .size;
                                                    final screenGlobalPos =
                                                        Offset(
                                                      targetOrigin.dx +
                                                          (xRatio *
                                                              targetSize.width),
                                                      targetOrigin.dy +
                                                          (yRatio *
                                                              targetSize
                                                                  .height),
                                                    );
                                                    final detectedTarget =
                                                        WidgetTreeDumper
                                                            .findTargetAtPosition(
                                                      targetContext,
                                                      screenGlobalPos,
                                                    );
                                                    if (detectedTarget !=
                                                        null) {
                                                      SnappySnag._log(
                                                          '🎯 SnappySnag: Pin placed on element -> [${detectedTarget.widgetType}] (Text: "${detectedTarget.widgetText ?? ''}", Key: "${detectedTarget.widgetKey ?? ''}") at screen pos: $screenGlobalPos');
                                                    } else {
                                                      SnappySnag._log(
                                                          '⚠️ SnappySnag: No specific UI element detected at screen pos: $screenGlobalPos. Falling back to relative coordinate.');
                                                    }
                                                    final newPin = SnappyPin(
                                                      id: 'pin_${DateTime.now().millisecondsSinceEpoch}',
                                                      number: nextNumber,
                                                      xRatio: xRatio,
                                                      yRatio: yRatio,
                                                      comment: '',
                                                      target: detectedTarget,
                                                    );
                                                    if (SnappySnag()
                                                        .enableHaptics) {
                                                      HapticFeedback
                                                          .mediumImpact();
                                                    }
                                                    setState(() {
                                                      _pins.add(newPin);
                                                      _editingPin = newPin;
                                                      _pinCommentController
                                                          .text = '';
                                                    });
                                                  }
                                                },
                                                onPanStart: (details) {
                                                  if (_isSendingFeedback ||
                                                      _isMemoOpen ||
                                                      _editingPin != null) {
                                                    return;
                                                  }
                                                  if (_activeTool !=
                                                      SnappyDrawingTool.mosaic) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    const double strokeWidth =
                                                        24.0;
                                                    const Color color =
                                                        Color(0xEE303036);
                                                    _drawingPoints.add(
                                                      DrawingPoint(
                                                        offsets: [
                                                          details.localPosition
                                                        ],
                                                        color: color,
                                                        strokeWidth:
                                                            strokeWidth,
                                                        tool: SnappyDrawingTool
                                                            .mosaic,
                                                        recordedSize:
                                                            canvasSize,
                                                      ),
                                                    );
                                                  });
                                                },
                                                onPanUpdate: (details) {
                                                  if (_isSendingFeedback ||
                                                      _isMemoOpen ||
                                                      _editingPin != null) {
                                                    return;
                                                  }
                                                  if (_activeTool !=
                                                      SnappyDrawingTool.mosaic) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    if (_drawingPoints
                                                        .isNotEmpty) {
                                                      _drawingPoints
                                                          .last.offsets
                                                          .add(details
                                                              .localPosition);
                                                    }
                                                  });
                                                },
                                                onPanEnd: (details) {
                                                  if (_isSendingFeedback ||
                                                      _isMemoOpen ||
                                                      _editingPin != null) {
                                                    return;
                                                  }
                                                  if (_activeTool !=
                                                      SnappyDrawingTool.mosaic) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    if (_drawingPoints
                                                        .isNotEmpty) {
                                                      _drawingPoints
                                                          .last.offsets
                                                          .add(null);
                                                      // Record completed stroke to undo stack
                                                      _undoStack.add(
                                                          _drawingPoints.last);
                                                      _redoStack.clear();
                                                    }
                                                  });
                                                },
                                              ),
                                            ),

                                            // 4. Pin overlay display (not baked into the screenshot image)
                                            ..._pins.map((pin) {
                                              final pinPixelX =
                                                  pin.xRatio * canvasSize.width;
                                              final pinPixelY = pin.yRatio *
                                                  canvasSize.height;
                                              const pinSize = 34.0;

                                              return Positioned(
                                                left: (pinPixelX - pinSize / 2)
                                                    .clamp(
                                                        0.0,
                                                        canvasSize.width -
                                                            pinSize),
                                                top: (pinPixelY - pinSize)
                                                    .clamp(
                                                        0.0,
                                                        canvasSize.height -
                                                            pinSize),
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    if (_isSendingFeedback ||
                                                        _isMemoOpen) {
                                                      return;
                                                    }
                                                    setState(() {
                                                      _editingPin = pin;
                                                      _pinCommentController
                                                          .text = pin.comment;
                                                    });
                                                  },
                                                  onPanStart: (details) {
                                                    if (_isSendingFeedback ||
                                                        _isMemoOpen ||
                                                        _editingPin != null) {
                                                      return;
                                                    }
                                                    if (SnappySnag()
                                                        .enableHaptics) {
                                                      HapticFeedback
                                                          .selectionClick();
                                                    }
                                                    _dragStartGlobal =
                                                        details.globalPosition;
                                                    _dragStartPinX =
                                                        pin.xRatio *
                                                            canvasSize.width;
                                                    _dragStartPinY =
                                                        pin.yRatio *
                                                            canvasSize.height;
                                                  },
                                                  onPanUpdate: (details) {
                                                    if (_isSendingFeedback ||
                                                        _isMemoOpen ||
                                                        _editingPin != null) {
                                                      return;
                                                    }
                                                    if (_dragStartGlobal ==
                                                            null ||
                                                        _dragStartPinX ==
                                                            null ||
                                                        _dragStartPinY == null) {
                                                      return;
                                                    }
                                                    final dx = details
                                                            .globalPosition.dx -
                                                        _dragStartGlobal!.dx;
                                                    final dy = details
                                                            .globalPosition.dy -
                                                        _dragStartGlobal!.dy;
                                                    final newDx =
                                                        (_dragStartPinX! + dx)
                                                            .clamp(
                                                                0.0,
                                                                canvasSize
                                                                    .width);
                                                    final newDy =
                                                        (_dragStartPinY! + dy)
                                                            .clamp(
                                                                0.0,
                                                                canvasSize
                                                                    .height);
                                                    final newXRatio = (newDx /
                                                            canvasSize.width)
                                                        .clamp(0.0, 1.0);
                                                    final newYRatio = (newDy /
                                                            canvasSize.height)
                                                        .clamp(0.0, 1.0);

                                                    setState(() {
                                                      final idx = _pins
                                                          .indexWhere((p) =>
                                                              p.id == pin.id);
                                                      if (idx != -1) {
                                                        _pins[idx] =
                                                            pin.copyWith(
                                                                xRatio:
                                                                    newXRatio,
                                                                yRatio:
                                                                    newYRatio);
                                                      }
                                                    });
                                                  },
                                                  onPanEnd: (_) {
                                                    // Re-detect and update UI element anchor at drop position upon drag completion
                                                    if (_dragStartGlobal !=
                                                        null) {
                                                      final currentPin =
                                                          _pins.firstWhere(
                                                              (p) =>
                                                                  p.id ==
                                                                  pin.id,
                                                              orElse: () =>
                                                                  pin);
                                                      final targetContext =
                                                          SnappySnag()
                                                                  .navigatorKey
                                                                  ?.currentContext ??
                                                              context;
                                                      final targetRenderBox =
                                                          targetContext
                                                                  .findRenderObject()
                                                              as RenderBox?;
                                                      final targetOrigin =
                                                          (targetRenderBox !=
                                                                      null &&
                                                                  targetRenderBox
                                                                      .attached)
                                                              ? targetRenderBox
                                                                  .localToGlobal(
                                                                      Offset
                                                                          .zero)
                                                              : Offset.zero;
                                                      final targetSize =
                                                          (targetRenderBox !=
                                                                      null &&
                                                                  targetRenderBox
                                                                      .attached &&
                                                                  targetRenderBox
                                                                      .hasSize)
                                                              ? targetRenderBox
                                                                  .size
                                                              : MediaQuery.of(
                                                                      targetContext)
                                                                  .size;
                                                      final screenGlobalPos =
                                                          Offset(
                                                        targetOrigin.dx +
                                                            (currentPin.xRatio *
                                                                targetSize
                                                                    .width),
                                                        targetOrigin.dy +
                                                            (currentPin.yRatio *
                                                                targetSize
                                                                    .height),
                                                      );
                                                      final newTarget =
                                                          WidgetTreeDumper
                                                              .findTargetAtPosition(
                                                        targetContext,
                                                        screenGlobalPos,
                                                      );
                                                      if (newTarget != null) {
                                                        SnappySnag._log(
                                                            '🎯 SnappySnag: Pin moved to element -> [${newTarget.widgetType}] (Text: "${newTarget.widgetText ?? ''}", Key: "${newTarget.widgetKey ?? ''}") at screen pos: $screenGlobalPos');
                                                      } else {
                                                        SnappySnag._log(
                                                            '⚠️ SnappySnag: Pin moved to relative coordinate (no specific element detected at $screenGlobalPos)');
                                                      }
                                                      setState(() {
                                                        final idx = _pins
                                                            .indexWhere((p) =>
                                                                p.id == pin.id);
                                                        if (idx != -1) {
                                                          _pins[idx] = currentPin
                                                              .copyWith(
                                                                  target:
                                                                      newTarget);
                                                        }
                                                      });
                                                    }
                                                    _dragStartGlobal = null;
                                                    _dragStartPinX = null;
                                                    _dragStartPinY = null;
                                                  },
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: pinSize,
                                                        height: pinSize,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: pinColor,
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                              color:
                                                                  Colors.white,
                                                              width: 2),
                                                          boxShadow: const [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black45,
                                                              blurRadius: 6,
                                                              offset:
                                                                  Offset(0, 3),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            '${pin.number}',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
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

                              // 2. Bottom floating toolbar
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
                                    color: barBgColor.withValues(
                                        alpha: isDark ? 0.9 : 0.95),
                                    borderRadius: BorderRadius.circular(
                                        theme.borderRadius > 20
                                            ? theme.borderRadius
                                            : 30),
                                    border: Border.all(
                                        color: isDark
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade300),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isDark
                                            ? Colors.black54
                                            : Colors.black12,
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // 1. Pin tool (default)
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.place,
                                              color: _activeTool ==
                                                      SnappyDrawingTool.pin
                                                  ? pinColor
                                                  : (isDark
                                                      ? Colors.grey
                                                      : Colors.grey.shade500),
                                            ),
                                            tooltip: 'Pin Marker (Max 5)',
                                            onPressed: _isSendingFeedback
                                                ? null
                                                : () {
                                                    if (SnappySnag()
                                                        .enableHaptics) {
                                                      HapticFeedback
                                                          .selectionClick();
                                                    }
                                                    setState(
                                                      () => _activeTool =
                                                          SnappyDrawingTool.pin,
                                                    );
                                                  },
                                          ),
                                          if (_pins.isNotEmpty)
                                            Positioned(
                                              right: 4,
                                              top: 4,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: pinColor,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
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
                                      // 2. Mosaic blur pen
                                      IconButton(
                                        icon: Icon(
                                          Icons.blur_on,
                                          color: _activeTool ==
                                                  SnappyDrawingTool.mosaic
                                              ? primaryColor
                                              : (isDark
                                                  ? Colors.grey
                                                  : Colors.grey.shade500),
                                        ),
                                        tooltip: 'Mosaic Blur',
                                        onPressed: _isSendingFeedback
                                            ? null
                                            : () {
                                                if (SnappySnag()
                                                    .enableHaptics) {
                                                  HapticFeedback
                                                      .selectionClick();
                                                }
                                                setState(
                                                  () => _activeTool =
                                                      SnappyDrawingTool.mosaic,
                                                );
                                              },
                                      ),
                                      const SizedBox(width: 8),
                                      // 3. Undo (chronological action history)
                                      IconButton(
                                        icon: Icon(
                                          Icons.undo,
                                          color: (!_isSendingFeedback &&
                                                  _undoStack.isNotEmpty)
                                              ? (isDark
                                                  ? Colors.white70
                                                  : Colors.black87)
                                              : (isDark
                                                  ? Colors.grey.shade700
                                                  : Colors.grey.shade400),
                                        ),
                                        tooltip: 'Undo',
                                        onPressed: _isSendingFeedback ||
                                                _undoStack.isEmpty
                                            ? null
                                            : () {
                                                if (SnappySnag()
                                                    .enableHaptics) {
                                                  HapticFeedback
                                                      .selectionClick();
                                                }
                                                setState(() {
                                                  final last =
                                                      _undoStack.removeLast();
                                                  _redoStack.add(last);
                                                  if (last is SnappyPin) {
                                                    _pins.removeWhere(
                                                        (p) => p.id == last.id);
                                                  } else if (last
                                                      is DrawingPoint) {
                                                    _drawingPoints.remove(last);
                                                  }
                                                });
                                              },
                                      ),
                                      // 4. Redo (restore undone action)
                                      IconButton(
                                        icon: Icon(
                                          Icons.redo,
                                          color: (!_isSendingFeedback &&
                                                  _redoStack.isNotEmpty)
                                              ? (isDark
                                                  ? Colors.white70
                                                  : Colors.black87)
                                              : (isDark
                                                  ? Colors.grey.shade700
                                                  : Colors.grey.shade400),
                                        ),
                                        tooltip: 'Redo',
                                        onPressed: _isSendingFeedback ||
                                                _redoStack.isEmpty
                                            ? null
                                            : () {
                                                if (SnappySnag()
                                                    .enableHaptics) {
                                                  HapticFeedback
                                                      .selectionClick();
                                                }
                                                setState(() {
                                                  final next =
                                                      _redoStack.removeLast();
                                                  _undoStack.add(next);
                                                  if (next is SnappyPin) {
                                                    _pins.add(next);
                                                  } else if (next
                                                      is DrawingPoint) {
                                                    _drawingPoints.add(next);
                                                  }
                                                });
                                              },
                                      ),
                                      // 5. Clear all - prompts confirmation dialog
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: (!_isSendingFeedback &&
                                                  (_drawingPoints.isNotEmpty ||
                                                      _pins.isNotEmpty))
                                              ? Colors.redAccent
                                              : Colors.grey.shade700,
                                        ),
                                        tooltip: 'Clear',
                                        onPressed: _isSendingFeedback ||
                                                (_drawingPoints.isEmpty &&
                                                    _pins.isEmpty)
                                            ? null
                                            : () => setState(() =>
                                                _isClearConfirmOpen = true),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 3. Floating overlay for editing pin comments
                              if (_editingPin != null)
                                Positioned.fill(
                                  child: LayoutBuilder(
                                    builder: (context, modalConstraints) {
                                      final isLandscape =
                                          modalConstraints.maxWidth >
                                              modalConstraints.maxHeight;
                                      return Container(
                                        color: Colors.black
                                            .withValues(alpha: 0.75),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: isLandscape ? 8 : 20,
                                        ),
                                        child: Center(
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: 480,
                                              maxHeight: isLandscape
                                                  ? modalConstraints.maxHeight *
                                                      0.95
                                                  : 540,
                                            ),
                                            child: Card(
                                              color: barBgColor,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        theme.borderRadius),
                                                side: BorderSide(
                                                    color: isDark
                                                        ? Colors.grey.shade800
                                                        : Colors.grey.shade300),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(16),
                                                child: SingleChildScrollView(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 28,
                                                            height: 28,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: pinColor,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                            child: Center(
                                                              child: Text(
                                                                '${_editingPin!.number}',
                                                                style:
                                                                    const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Text(
                                                            _SdkLocale
                                                                .pinCommentTitle,
                                                            style: TextStyle(
                                                              color:
                                                                  barTextColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 16,
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons
                                                                    .delete_outline,
                                                                color: Colors
                                                                    .redAccent,
                                                                size: 20),
                                                            tooltip: _SdkLocale
                                                                .delete,
                                                            onPressed: () {
                                                              if (SnappySnag()
                                                                  .enableHaptics) {
                                                                HapticFeedback
                                                                    .lightImpact();
                                                              }
                                                              setState(() {
                                                                _pins.removeWhere(
                                                                    (p) =>
                                                                        p.id ==
                                                                        _editingPin!
                                                                            .id);
                                                                _renumberPins();
                                                                _editingPin =
                                                                    null;
                                                              });
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      TextField(
                                                        controller:
                                                            _pinCommentController,
                                                        maxLength: 500,
                                                        maxLengthEnforcement:
                                                            MaxLengthEnforcement
                                                                .enforced,
                                                        maxLines:
                                                            isLandscape ? 2 : 4,
                                                        autofocus: true,
                                                        style: TextStyle(
                                                            color:
                                                                barTextColor),
                                                        decoration:
                                                            InputDecoration(
                                                          hintText: _SdkLocale
                                                              .pinCommentHint,
                                                          hintStyle: TextStyle(
                                                              color:
                                                                  barSubtextColor),
                                                          fillColor: isDark
                                                              ? Colors.black26
                                                              : Colors.grey
                                                                  .shade100,
                                                          filled: true,
                                                          border:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                            borderSide: BorderSide(
                                                                color: isDark
                                                                    ? Colors
                                                                        .grey
                                                                        .shade800
                                                                    : Colors
                                                                        .grey
                                                                        .shade300),
                                                          ),
                                                          enabledBorder:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                            borderSide: BorderSide(
                                                                color: isDark
                                                                    ? Colors
                                                                        .grey
                                                                        .shade800
                                                                    : Colors
                                                                        .grey
                                                                        .shade300),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 16),
                                                      ElevatedButton(
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              primaryColor,
                                                          foregroundColor:
                                                              ThemeData.estimateBrightnessForColor(
                                                                          primaryColor) ==
                                                                      Brightness
                                                                          .dark
                                                                  ? Colors.white
                                                                  : Colors
                                                                      .black,
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          final updatedComment =
                                                              _pinCommentController
                                                                  .text
                                                                  .trim();
                                                          final editingId =
                                                              _editingPin!.id;
                                                          // Determine if pin is new: new only if not yet registered in undoStack
                                                          final isNewPin =
                                                              !_undoStack.any((e) =>
                                                                  e is SnappyPin &&
                                                                  e.id ==
                                                                      editingId);
                                                          setState(() {
                                                            if (updatedComment
                                                                .isEmpty) {
                                                              // Delete pin if comment is empty (do not push to undoStack)
                                                              _pins.removeWhere(
                                                                  (p) =>
                                                                      p.id ==
                                                                      editingId);
                                                              _renumberPins();
                                                            } else {
                                                              final idx = _pins
                                                                  .indexWhere((p) =>
                                                                      p.id ==
                                                                      editingId);
                                                              if (idx != -1) {
                                                                final finalPin =
                                                                    _editingPin!.copyWith(
                                                                        comment:
                                                                            updatedComment);
                                                                _pins[idx] =
                                                                    finalPin;
                                                                if (isNewPin) {
                                                                  // New pin: record finalized content to undoStack once comment is submitted
                                                                  _undoStack.add(
                                                                      finalPin);
                                                                  _redoStack
                                                                      .clear();
                                                                }
                                                                // Editing existing pin is excluded from undoStack (same as moving)
                                                              }
                                                            }
                                                            _editingPin = null;
                                                          });
                                                        },
                                                        child: Text(
                                                          _SdkLocale.done,
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold),
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

                              // 5. Privacy confirmation floating overlay (rendered on topmost layer)
                              if (_isPrivacyConfirmOpen)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 440),
                                        child: Card(
                                          color: dialogBg,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: dialogRadius,
                                            side:
                                                BorderSide(color: dialogBorder),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(Icons.shield_outlined,
                                                        color: primaryColor),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _SdkLocale
                                                          .privacyConfirmTitle,
                                                      style: TextStyle(
                                                        color: barTextColor,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                // 1. Image mosaic review
                                                Text(
                                                  _SdkLocale
                                                      .privacyConfirmContent,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontSize: 13,
                                                    height: 1.4,
                                                  ),
                                                ),
                                                const SizedBox(height: 14),
                                                Divider(color: dialogBorder),
                                                const SizedBox(height: 8),
                                                // 2. Diagnostics and account metadata sharing checkbox
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      _includeAccountAndDiagnostics =
                                                          !_includeAccountAndDiagnostics;
                                                    });
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(vertical: 4),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        SizedBox(
                                                          width: 24,
                                                          height: 24,
                                                          child: Checkbox(
                                                            value:
                                                                _includeAccountAndDiagnostics,
                                                            activeColor:
                                                                primaryColor,
                                                            checkColor: ThemeData
                                                                        .estimateBrightnessForColor(
                                                                            primaryColor) ==
                                                                    Brightness
                                                                        .dark
                                                                ? Colors.white
                                                                : Colors.black,
                                                            side: BorderSide(
                                                                color: isDark
                                                                    ? Colors
                                                                        .white38
                                                                    : Colors
                                                                        .black38),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                            onChanged: (val) {
                                                              setState(() {
                                                                _includeAccountAndDiagnostics =
                                                                    val ?? true;
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                SnappySnag().reporterEmail !=
                                                                            null &&
                                                                        SnappySnag()
                                                                            .reporterEmail!
                                                                            .isNotEmpty
                                                                    ? _SdkLocale.privacyShareAccountWithEmail(
                                                                        SnappySnag()
                                                                            .reporterEmail!)
                                                                    : _SdkLocale
                                                                        .privacyShareAccount,
                                                                style:
                                                                    TextStyle(
                                                                  color:
                                                                      barTextColor,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 2),
                                                              Text(
                                                                _SdkLocale
                                                                    .privacyAnonymousHint,
                                                                style:
                                                                    TextStyle(
                                                                  color:
                                                                      barSubtextColor,
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
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    TextButton(
                                                      onPressed: () {
                                                        setState(() =>
                                                            _isPrivacyConfirmOpen =
                                                                false);
                                                      },
                                                      child: Text(
                                                        _SdkLocale.backToEdit,
                                                        style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white60
                                                                : Colors
                                                                    .black54),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            primaryColor,
                                                        foregroundColor:
                                                            ThemeData.estimateBrightnessForColor(
                                                                        primaryColor) ==
                                                                    Brightness
                                                                        .dark
                                                                ? Colors.white
                                                                : Colors.black,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        _executeFeedbackSubmission();
                                                      },
                                                      child: Text(
                                                        _SdkLocale.sendConfirm,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
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
                              // 5. Clear all confirmation overlay
                              if (_isClearConfirmOpen)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 420),
                                        child: Card(
                                          color: dialogBg,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: dialogRadius,
                                            side:
                                                BorderSide(color: dialogBorder),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.delete_outline,
                                                        color:
                                                            Colors.redAccent),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _SdkLocale
                                                          .clearConfirmTitle,
                                                      style: TextStyle(
                                                        color: barTextColor,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  _SdkLocale.clearConfirmBody,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontSize: 13,
                                                    height: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    TextButton(
                                                      onPressed: () {
                                                        setState(() =>
                                                            _isClearConfirmOpen =
                                                                false);
                                                      },
                                                      child: Text(
                                                        _SdkLocale.cancel,
                                                        style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white54
                                                                : Colors
                                                                    .black54),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            Colors.redAccent,
                                                        foregroundColor:
                                                            Colors.white,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _drawingPoints
                                                              .clear();
                                                          _pins.clear();
                                                          _undoStack.clear();
                                                          _redoStack.clear();
                                                          _isClearConfirmOpen =
                                                              false;
                                                        });
                                                      },
                                                      child: Text(
                                                        _SdkLocale
                                                            .clearConfirmButton,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
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
                              // 6. Draft save confirmation overlay on cancel
                              if (_isCancelDraftConfirmOpen)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 420),
                                        child: Card(
                                          color: dialogBg,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: dialogRadius,
                                            side:
                                                BorderSide(color: dialogBorder),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(Icons.bookmark_border,
                                                        color: primaryColor),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _SdkLocale
                                                          .saveDraftPromptTitle,
                                                      style: TextStyle(
                                                        color: barTextColor,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  _SdkLocale
                                                      .saveDraftPromptOnCancel,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontSize: 13,
                                                    height: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    TextButton(
                                                      onPressed: () {
                                                        setState(() =>
                                                            _isCancelDraftConfirmOpen =
                                                                false);
                                                      },
                                                      child: Text(
                                                        _SdkLocale.cancel,
                                                        style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white54
                                                                : Colors
                                                                    .black54),
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () async {
                                                        await _SnappyDraftData
                                                            .clear();
                                                        _closeDrawingOverlay();
                                                      },
                                                      child: Text(
                                                        _SdkLocale.discardDraft,
                                                        style: const TextStyle(
                                                            color: Colors
                                                                .redAccent),
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            primaryColor,
                                                        foregroundColor:
                                                            ThemeData.estimateBrightnessForColor(
                                                                        primaryColor) ==
                                                                    Brightness
                                                                        .dark
                                                                ? Colors.white
                                                                : Colors.black,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                      ),
                                                      onPressed: () async {
                                                        if (_drawingImageBytes !=
                                                            null) {
                                                          await _SnappyDraftData
                                                              .save(
                                                            imageBytes:
                                                                _drawingImageBytes!,
                                                            widgetTree:
                                                                _drawingWidgetTree,
                                                            screenClassName:
                                                                _drawingScreenClassName,
                                                            screenSignature:
                                                                _drawingScreenSignature,
                                                            drawingPoints:
                                                                _drawingPoints,
                                                            pins: _pins,
                                                            memo:
                                                                _feedbackMemoController
                                                                    .text,
                                                            drawingAspectRatio:
                                                                _drawingAspectRatio,
                                                          );
                                                        }
                                                        final messengerContext =
                                                            SnappySnag()
                                                                    .navigatorKey
                                                                    ?.currentContext ??
                                                                context;
                                                        _closeDrawingOverlay();
                                                        _showToast(
                                                          targetContext:
                                                              messengerContext,
                                                          message: _SdkLocale
                                                              .draftSavedToast,
                                                          type: _SnappyToastType
                                                              .success,
                                                          duration:
                                                              const Duration(
                                                                  seconds: 3),
                                                        );
                                                      },
                                                      child: Text(
                                                        _SdkLocale.saveDraft,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
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

                              // 6. Draft save confirmation overlay on send failure
                              if (_isFailedSendDraftConfirmOpen)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 420),
                                        child: Card(
                                          color: dialogBg,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: dialogRadius,
                                            side:
                                                BorderSide(color: dialogBorder),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(Icons.bookmark_border,
                                                        color: primaryColor),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _SdkLocale
                                                          .saveDraftPromptTitle,
                                                      style: TextStyle(
                                                        color: barTextColor,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  _SdkLocale
                                                      .saveDraftPromptOnFailedSend,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontSize: 13,
                                                    height: 1.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    TextButton(
                                                      onPressed: () {
                                                        setState(() =>
                                                            _isFailedSendDraftConfirmOpen =
                                                                false);
                                                      },
                                                      child: Text(
                                                        _SdkLocale.stayOnScreen,
                                                        style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white70
                                                                : Colors
                                                                    .black54),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            primaryColor,
                                                        foregroundColor:
                                                            ThemeData.estimateBrightnessForColor(
                                                                        primaryColor) ==
                                                                    Brightness
                                                                        .dark
                                                                ? Colors.white
                                                                : Colors.black,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                      ),
                                                      onPressed: () async {
                                                        if (_drawingImageBytes !=
                                                            null) {
                                                          await _SnappyDraftData
                                                              .save(
                                                            imageBytes:
                                                                _drawingImageBytes!,
                                                            widgetTree:
                                                                _drawingWidgetTree,
                                                            screenClassName:
                                                                _drawingScreenClassName,
                                                            screenSignature:
                                                                _drawingScreenSignature,
                                                            drawingPoints:
                                                                _drawingPoints,
                                                            pins: _pins,
                                                            memo:
                                                                _feedbackMemoController
                                                                    .text,
                                                            drawingAspectRatio:
                                                                _drawingAspectRatio,
                                                          );
                                                        }
                                                        final messengerContext =
                                                            SnappySnag()
                                                                    .navigatorKey
                                                                    ?.currentContext ??
                                                                context;
                                                        _closeDrawingOverlay();
                                                        _showToast(
                                                          targetContext:
                                                              messengerContext,
                                                          message: _SdkLocale
                                                              .draftSavedToast,
                                                          type: _SnappyToastType
                                                              .success,
                                                          duration:
                                                              const Duration(
                                                                  seconds: 3),
                                                        );
                                                      },
                                                      child: Text(
                                                        _SdkLocale.saveDraft,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
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

                              // Fullscreen loading overlay while sending feedback
                              if (_isSendingFeedback)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    child: Center(
                                      child: Card(
                                        color: dialogBg,
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: dialogRadius,
                                          side: BorderSide(color: dialogBorder),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 28, vertical: 24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 36,
                                                height: 36,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 3,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                              Color>(
                                                          theme.primaryColor),
                                                ),
                                              ),
                                              const SizedBox(height: 18),
                                              Text(
                                                _SdkLocale.sending,
                                                style: TextStyle(
                                                  color: barTextColor,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
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
            final shouldShowButton = (isTriggerVisible || isFeedbackActive) &&
                !_isCapturing &&
                !_isFeedbackDialogOpen &&
                _overlayMode == _SnappyOverlayMode.none;

            return Stack(
              children: [
                // Floating trigger button (rendered in feedback mode or persistent setting)
                if (shouldShowButton)
                  Positioned(
                    bottom: 16 + MediaQuery.of(context).padding.bottom,
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        // Exit feedback mode when capture begins
                        SnappySnag().isFeedbackModeActive.value = false;
                        _triggerCapture();
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: SnappySnag().theme.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: SnappySnagIcon(
                            size: 42,
                            color: ThemeData.estimateBrightnessForColor(
                                        SnappySnag().theme.primaryColor) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),

        // 9. Foremost Floating Toast Notification (highest Z-index above all overlays and buttons)
        if (_toastMessage != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
            child: IgnorePointer(
              ignoring: !_isToastVisible,
              child: AnimatedOpacity(
                opacity: _isToastVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Builder(
                  builder: (toastContext) {
                    final theme = SnappySnag().theme;
                    final isDark = theme.isDark(toastContext);
                    final toastBg =
                        isDark ? const Color(0xFF1E1E24) : Colors.white;
                    final toastBorder =
                        isDark ? const Color(0xFF2E2E38) : Colors.grey.shade300;
                    final textColor = isDark ? Colors.white : Colors.black87;

                    final IconData iconData;
                    final Color iconColor;
                    switch (_toastType) {
                      case _SnappyToastType.success:
                        iconData = Icons.check_circle_rounded;
                        iconColor = const Color(0xFF10B981); // Emerald Green
                        break;
                      case _SnappyToastType.error:
                        iconData = Icons.error_outline_rounded;
                        iconColor = const Color(0xFFEF4444); // Rose Red
                        break;
                      case _SnappyToastType.warning:
                        iconData = Icons.warning_amber_rounded;
                        iconColor = const Color(0xFFF59E0B); // Amber
                        break;
                      case _SnappyToastType.info:
                        iconData = Icons.info_outline_rounded;
                        iconColor = theme.primaryColor;
                        break;
                    }

                    final radius =
                        theme.borderRadius > 16 ? 16.0 : theme.borderRadius;

                    return Material(
                      elevation: 10,
                      shadowColor: Colors.black45,
                      color: toastBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(radius),
                        side: BorderSide(color: toastBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(iconData, color: iconColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _toastMessage ?? '',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
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

class _SimpleDiagnosticsSerializationDelegate
    implements DiagnosticsSerializationDelegate {
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

  /// Automatically collects global screen bounding boxes (Rect) for password fields, email fields, phone numbers, and sensitive inputs.
  /// (Targets only visible and active input fields on the topmost screen)
  static List<Rect> findSensitiveFieldBounds(BuildContext context) {
    final List<Rect> bounds = [];
    final Set<int> visitedHashCodes = {};

    // 1. Identify the topmost visible Scaffold
    Element? topScaffoldElement;
    void findTopScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        topScaffoldElement = element;
      }
      element.visitChildren(findTopScaffold);
    }

    context.visitChildElements(findTopScaffold);

    // Starting context: use topmost Scaffold if resolved, fallback to provided context
    final Element searchRoot = topScaffoldElement ?? (context as Element);

    // Get screen size to filter out off-screen coordinates
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenWidth = mediaQuery?.size.width ?? 5000.0;
    final screenHeight = mediaQuery?.size.height ?? 5000.0;

    // PII detection regex patterns (email, phone number, credit card, postal code)
    final emailRegex =
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final phoneRegex = RegExp(
        r'(?:\+?\d{1,3}[- ]?)?(?:0\d{1,4}[- ]?\d{1,4}[- ]?\d{3,4}|\b\d{3}[- ]?\d{4}[- ]?\d{4}\b)');
    final creditCardRegex = RegExp(r'\b(?:\d{4}[ -]?){3}\d{4}\b');
    final postalCodeRegex = RegExp(r'〒?\s*\d{3}-\d{4}');

    void inspectElement(Element element) {
      if (visitedHashCodes.contains(element.hashCode)) return;
      visitedHashCodes.add(element.hashCode);

      final widget = element.widget;

      // Skip hidden widgets and descendants (Offstage, Visibility, TickerMode)
      if (widget is Offstage && widget.offstage) return;
      if (widget is Visibility && !widget.visible) return;
      if (widget is TickerMode && !widget.enabled) return;

      bool isSensitive = false;

      // 1. Detect PII patterns within Text / RichText (email, phone, credit card, postal code)
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

      // 2. Detect CircleAvatar (user profile photo)
      if (widget is CircleAvatar) {
        isSensitive = true;
      }

      // 3. Check TextField / EditableText (active and editable input fields only)
      if (widget is TextField) {
        if (!widget.readOnly && (widget.enabled ?? true)) {
          isSensitive = true;
        }
      } else if (widget is EditableText) {
        // Exclude read-only EditableText such as SelectableText
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

            // Minimum bounding size requirement (width >= 20px, height >= 10px)
            if (size.width >= 20 && size.height >= 10) {
              // Verify if element is within the visible screen viewport
              final isInsideScreen = position.dx < screenWidth &&
                  position.dx + size.width > 0 &&
                  position.dy < screenHeight &&
                  position.dy + size.height > 0;

              if (isInsideScreen) {
                final rect = Rect.fromLTWH(
                    position.dx, position.dy, size.width, size.height);
                if (!bounds.any((b) =>
                    (b.left - rect.left).abs() < 5 &&
                    (b.top - rect.top).abs() < 5)) {
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

  // Traverse ancestors upwards starting from Scaffold to identify the correct screen custom widget class
  static String findScreenName(BuildContext context) {
    Element? scaffoldElement;

    // Traverse tree to retain the last encountered Scaffold (topmost visible screen overlay)
    void findScaffold(Element element) {
      if (element.widget.runtimeType.toString() == 'Scaffold') {
        scaffoldElement =
            element; // Update on each match to capture the latest topmost element
      }
      element.visitChildren((child) {
        findScaffold(child); // Traverse all subtrees without early return
      });
    }

    // Search for Scaffold starting from top-level root context
    context.visitChildElements((element) {
      findScaffold(element);
    });

    if (scaffoldElement == null) {
      return 'UnknownScreen';
    }

    String detectedScreenName = 'UnknownScreen';

    // Walk up ancestor chain from Scaffold to find the first custom widget class
    scaffoldElement!.visitAncestorElements((ancestor) {
      final typeStr = ancestor.widget.runtimeType.toString();
      final clean = _cleanType(typeStr);

      if (!_isNoiseWidget(clean) && !_isStandardOrFrameworkWidget(clean)) {
        detectedScreenName = typeStr;
        return false; // Stop traversal
      }
      return true; // Continue ascending parent chain
    });

    return detectedScreenName;
  }

  // Generate screen structure signature (collects custom widgets below Scaffold)
  static String findScreenSignature(
      BuildContext context, String screenClassName) {
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

  // Filter standard framework widgets using keyword matching
  static bool _isStandardOrFrameworkWidget(String type) {
    final clean = _cleanType(type);

    // 1. Core Flutter framework widgets excluded by exact class name match
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

    // 2. Framework-internal naming keywords excluded by partial match
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
      final jsonMap =
          node.toJsonMap(const _SimpleDiagnosticsSerializationDelegate());
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
    if (depth > 0 &&
        loc == null &&
        key == null &&
        text == null &&
        !_isLayoutStructuralWidget(type)) {
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
    // Exclude redundant framework widgets that inflate depth and token consumption without aiding bug diagnostics
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

  /// Determines whether text consists of icon font glyphs in Unicode Private Use Areas (PUA: \uE000-\uF8FF, >= \uF0000).
  static bool _isPrivateUseAreaIconText(String? str) {
    if (str == null) return false;
    final trimmed = str.trim();
    if (trimmed.isEmpty) return false;
    // Treat as icon glyph if length <= 3 and character code points fall within PUA
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

  /// Extracts the best-matching UI widget anchor metadata (SnappyPinTarget) at the tapped screen position.
  static SnappyPinTarget? findTargetAtPosition(
      BuildContext context, Offset globalPos) {
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

          // Check whether tap coordinates fall within widget boundaries
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

            // Search descendants for EditableText if input widget has not extracted text yet
            if ((text == null || text.trim().isEmpty) &&
                (clean.contains('TextField') ||
                    clean.contains('TextFormField') ||
                    clean.contains('EditableText'))) {
              void findInputText(Element el) {
                if (text != null && text!.trim().isNotEmpty) return;
                final w = el.widget;
                if (w is EditableText) {
                  text = w.controller.text;
                } else if (w is Text &&
                    w.data != null &&
                    w.data!.trim().isNotEmpty) {
                  text = w.data!.trim();
                }
                if (text == null || text!.isEmpty) {
                  el.visitChildren(findInputText);
                }
              }

              element.visitChildren(findInputText);
            }

            // Exclude icon glyphs in Private Use Areas (PUA) from text anchor extraction
            final bool isIconGlyph = _isPrivateUseAreaIconText(text);

            // Validate text content (exclude empty, whitespace-only, or PUA icon glyphs)
            final rawText = text;
            final bool hasValidText =
                !isIconGlyph && rawText != null && rawText.trim().isNotEmpty;
            final String? trimmedText = hasValidText ? rawText.trim() : null;

            // Traverse ancestors upwards to locate interactive buttons or containers
            Element? clickableAncestor;
            String? ancestorType;
            String? ancestorKey;
            Rect? ancestorRect;

            element.visitAncestorElements((ancestor) {
              if (ancestor == searchRoot) return false;
              final aWidget = ancestor.widget;
              final aType = _cleanType(aWidget.runtimeType.toString());

              // Exclude low-level internal framework widgets (prefixed with _, RawGestureDetector, Scope, etc.)
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

              // Interactive containers, buttons, text fields, or header/bar containers
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
                    final aR = Rect.fromLTWH(
                        aPos.dx, aPos.dy, aSize.width, aSize.height);
                    if (aR.contains(globalPos)) {
                      clickableAncestor = ancestor;
                      ancestorType = aType;
                      ancestorKey = aWidget.key?.toString();
                      ancestorRect = aR;
                      // Immediately prioritize custom app buttons or TextFields when encountered
                      if (!aType.startsWith('GestureDetector') &&
                          !aType.startsWith('InkResponse')) {
                        return false;
                      }
                    }
                  } catch (_) {}
                }
              }
              return true;
            });

            // Register interactive ancestor container as candidate if present
            if (clickableAncestor != null &&
                ancestorType != null &&
                ancestorRect != null) {
              final cArea = ancestorRect!.width * ancestorRect!.height;
              final localXRatio = ancestorRect!.width > 0
                  ? ((globalPos.dx - ancestorRect!.left) / ancestorRect!.width)
                      .clamp(0.0, 1.0)
                  : 0.5;
              final localYRatio = ancestorRect!.height > 0
                  ? ((globalPos.dy - ancestorRect!.top) / ancestorRect!.height)
                      .clamp(0.0, 1.0)
                  : 0.5;

              // Borrow inner button text as anchor text.
              // If tap position itself has no text (e.g. icon or arrow tapped),
              // select the closest text element from within the clickable container.
              String? buttonText = trimmedText;
              if (buttonText == null || buttonText.isEmpty) {
                double minDistance = double.infinity;
                String? closestText;

                void findClosestChildText(Element el) {
                  final w = el.widget;
                  String? candidate;
                  if (w is Text &&
                      w.data != null &&
                      !_isPrivateUseAreaIconText(w.data) &&
                      w.data!.trim().isNotEmpty) {
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
                        final center = Offset(pos.dx + rBox.size.width * 0.5,
                            pos.dy + rBox.size.height * 0.5);
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
              final resolvedText =
                  (finalButtonText != null && finalButtonText.length > 30)
                      ? finalButtonText.substring(0, 30)
                      : finalButtonText;

              final isForeContainer = ancestorType!.contains('AppBar') ||
                  ancestorType!.contains('Header') ||
                  ancestorType!.contains('NavigationBar');

              candidates.add(
                _CandidateTarget(
                  area: cArea,
                  depth: nextPath.length,
                  priority: isForeContainer
                      ? 110
                      : 100, // Header containers: 110, Buttons/TextFields: 100
                  traversalIndex: currentOrder,
                  target: SnappyPinTarget(
                    widgetKey: ancestorKey,
                    widgetType: ancestorType!,
                    widgetText: resolvedText,
                    widgetPath: nextPath.length > 5
                        ? nextPath.sublist(nextPath.length - 5)
                        : nextPath,
                    localXRatio: localXRatio,
                    localYRatio: localYRatio,
                  ),
                ),
              );
            }

            // Determine widget priority score.
            // Wrapper and noisy control widgets are strictly excluded as standalone candidates.
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
              final isInputWidget = clean.contains('TextField') ||
                  clean.contains('TextFormField') ||
                  clean.contains('EditableText');
              final isButtonSelf = clean.contains('Button') ||
                  clean.contains('InkWell') ||
                  clean.contains('Tile') ||
                  clean.contains('Card') ||
                  isInputWidget;
              final isForeElement = clean.contains('AppBar') ||
                  clean.contains('Header') ||
                  clean.contains('NavigationBar');

              if (isForeElement) {
                priority =
                    110; // Header/AppBar elements prioritized as topmost foreground
              } else if (isButtonSelf) {
                priority = 100;
              } else if (keyStr != null && keyStr.isNotEmpty) {
                priority = 80;
              } else if (hasValidText) {
                priority = 60;
              } else if (clean.contains('Image') ||
                  clean.contains('Icon') ||
                  isIconGlyph) {
                priority = 40; // Images and icons (including PUA font glyphs)
              }

              if (priority > 0) {
                final area = size.width * size.height;
                final localXRatio = size.width > 0
                    ? ((globalPos.dx - pos.dx) / size.width).clamp(0.0, 1.0)
                    : 0.5;
                final localYRatio = size.height > 0
                    ? ((globalPos.dy - pos.dy) / size.height).clamp(0.0, 1.0)
                    : 0.5;

                candidates.add(
                  _CandidateTarget(
                    area: area,
                    depth: nextPath.length,
                    priority: priority,
                    traversalIndex: currentOrder,
                    target: SnappyPinTarget(
                      widgetKey: keyStr,
                      widgetType: clean,
                      widgetText: trimmedText != null && trimmedText.length > 30
                          ? trimmedText.substring(0, 30)
                          : trimmedText,
                      widgetPath: nextPath.length > 5
                          ? nextPath.sublist(nextPath.length - 5)
                          : nextPath,
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

    // Sorting criteria:
    // 1. priority (Header: 110, Button/TextField: 100, Key: 80, Text: 60, Icon/Image: 40)
    // 2. traversalIndex (foreground layers rendered later in the tree take precedence on overlap)
    // 3. area (smaller, more specific elements prioritized)
    // 4. depth (deeper specialized widgets prioritized)
    candidates.sort((a, b) {
      // Prioritize traversalIndex when priority scores are close to respect foreground layering
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

  /// Traverses the current widget tree and resolves global screen coordinates for the best-matching UI element.
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

    // Obtain root RenderBox of the screen (for proximity disambiguation among duplicate components)
    final rootRenderBox = searchRoot.findRenderObject() as RenderBox?;
    final rootOrigin = (rootRenderBox != null && rootRenderBox.attached)
        ? rootRenderBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final rootSize = (rootRenderBox != null &&
            rootRenderBox.attached &&
            rootRenderBox.hasSize)
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
        // For buttons or containers, search descendant Text widgets for matching anchor text
        void findDescendantText(Element el) {
          if (text != null && text!.trim().isNotEmpty) return;
          final w = el.widget;
          if (w is Text &&
              w.data != null &&
              !_isPrivateUseAreaIconText(w.data) &&
              w.data!.trim().isNotEmpty) {
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

      // 1. Exact Key match (highest priority: 100 pts)
      if (target.widgetKey != null &&
          keyStr != null &&
          target.widgetKey == keyStr) {
        score += 100;
      }

      // 2. Widget runtime type match (20 pts)
      if (target.widgetType == clean) {
        score += 20;
      }

      // 3. Text content match
      final String? currentText = text?.trim();
      final String? targetText = target.widgetText?.trim();
      if (targetText != null && currentText != null && currentText.isNotEmpty) {
        if (currentText == targetText) {
          // Exact match: highest confidence (50 pts)
          score += 50;
        } else {
          // Disallow partial match for short or numeric strings (<= 4 chars) to prevent false positives
          final isNumericOrShort = currentText.length <= 4 ||
              targetText.length <= 4 ||
              int.tryParse(currentText) != null ||
              int.tryParse(targetText) != null;
          if (!isNumericOrShort) {
            if (currentText.startsWith(targetText) ||
                targetText.startsWith(currentText)) {
              score += 20; // Partial match on longer strings
            }
          }
        }
      }

      // 4. Widget hierarchy path match (up to 20 pts)
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
            // Snap pin directly to element center (50% / 50%) when target matches
            final resolvedOffset = Offset(
              pos.dx + (size.width * 0.5),
              pos.dy + (size.height * 0.5),
            );

            // 5. Proximity bonus based on relative coordinates (up to 30 pts)
            // Prioritizes elements closer to original pin position when duplicate items exist (e.g. calendar cells)
            int positionBonus = 0;
            final refRatioX = fallbackPosition?.dx ?? target.localXRatio;
            final refRatioY = fallbackPosition?.dy ?? target.localYRatio;
            if (rootSize.width > 0 &&
                rootSize.height > 0 &&
                refRatioX != null &&
                refRatioY != null) {
              final elemCenterRatioX =
                  (resolvedOffset.dx - rootOrigin.dx) / rootSize.width;
              final elemCenterRatioY =
                  (resolvedOffset.dy - rootOrigin.dy) / rootSize.height;
              // Euclidean distance between original ratio and candidate center ratio
              final dist = sqrt(
                pow(elemCenterRatioX - refRatioX, 2) +
                    pow(elemCenterRatioY - refRatioY, 2),
              );
              // Higher score for closer proximity (up to 30 pts)
              positionBonus = ((1.0 - dist.clamp(0.0, 1.0)) * 30).round();
            }

            final totalScore = score + positionBonus;

            // Qualify as candidate if total score >= 25 (e.g. type match 20 + proximity bonus, or text match)
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
      SnappySnag._log(
          '📍 SnappySnag: Target resolved successfully -> [${match.matchedType}] (Text: "${match.matchedText ?? ''}", Key: "${match.matchedKey ?? ''}") at center pos: ${match.offset} (score: ${match.score})');
      return match.offset;
    } else {
      SnappySnag._log(
          '⚠️ SnappySnag: Target resolution failed for [${target.widgetType}] (Text: "${target.widgetText ?? ''}", Key: "${target.widgetKey ?? ''}"). Falling back to relative ratio.');
      return null;
    }
  }

  /// Resolves bounding Rect of the UI element matching target metadata.
  /// Returns null if not found (scrolled off-screen or unmounted).
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
          if (w is Text &&
              w.data != null &&
              !_isPrivateUseAreaIconText(w.data) &&
              w.data!.trim().isNotEmpty) {
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
      if (target.widgetKey != null &&
          keyStr != null &&
          target.widgetKey == keyStr) {
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
            if (currentText.startsWith(targetText) ||
                targetText.startsWith(currentText)) {
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
            if (rootSize.width > 0 &&
                rootSize.height > 0 &&
                refRatioX != null &&
                refRatioY != null) {
              final elemCenterRatioX =
                  (resolvedOffset.dx - rootOrigin.dx) / rootSize.width;
              final elemCenterRatioY =
                  (resolvedOffset.dy - rootOrigin.dy) / rootSize.height;
              final dist = sqrt(
                pow(elemCenterRatioX - refRatioX, 2) +
                    pow(elemCenterRatioY - refRatioY, 2),
              );
              positionBonus = ((1.0 - dist.clamp(0.0, 1.0)) * 30).round();
            }

            final totalScore = score + positionBonus;

            if (totalScore >= 25) {
              if (bestMatch == null || totalScore > bestMatch!.score) {
                // Identify section boundary: promote to parent container (AppBar / Card / section block)
                Rect resolvedRect =
                    Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
                String bestType = clean;

                element.visitAncestorElements((ancestor) {
                  final aWidget = ancestor.widget;
                  final aRawType = aWidget.runtimeType.toString();
                  final aClean = _cleanType(aRawType);

                  if (aClean == 'Scaffold' ||
                      aClean == 'MaterialApp' ||
                      aClean == 'Navigator') {
                    return false;
                  }

                  final isAppBarAncestor = aClean.contains('AppBar') ||
                      aClean.contains('SliverAppBar') ||
                      aClean.contains('Header');
                  final isCardAncestor = aClean.contains('Card') ||
                      aClean.contains('Calendar') ||
                      aClean.contains('Section');

                  if (isAppBarAncestor || isCardAncestor) {
                    final aBox = ancestor.findRenderObject();
                    if (aBox is RenderBox && aBox.hasSize && aBox.attached) {
                      final aPos = aBox.localToGlobal(Offset.zero);
                      final aSize = aBox.size;
                      if (aSize.width > 0 && aSize.height > 0) {
                        resolvedRect = Rect.fromLTWH(
                            aPos.dx, aPos.dy, aSize.width, aSize.height);
                        bestType = aClean;
                        if (isAppBarAncestor) {
                          return false; // AppBar is immediately selected as top header section
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
      SnappySnag._log(
          '📍 SnappySnag: Target section Rect resolved successfully -> [${match.matchedType}] ${match.rect} (score: ${match.score})');
      return match.rect;
    } else {
      SnappySnag._log(
          '⚠️ SnappySnag: Target section Rect resolution failed for [${target.widgetType}]');
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

/// Anchor metadata linking a pin to a specific UI widget (for responsive snapping across screen sizes)

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
      widgetPath:
          (json['path'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
      localXRatio: (json['localX'] as num?)?.toDouble(),
      localYRatio: (json['localY'] as num?)?.toDouble(),
    );
  }
}

/// Pin model pointing to a specific location on a screenshot.
class SnappyPin {
  final String id;
  final int number;
  final double xRatio; // 0.0 ~ 1.0 (Relative X ratio - fallback)
  final double yRatio; // 0.0 ~ 1.0 (Relative Y ratio - fallback)
  final String comment;
  final SnappyPinTarget? target; // UI element snapping metadata
  final bool
      isActive; // Pin active status (maps to feedback_logs pins["is_active"])

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
            : (rawIsActive.toString().toLowerCase() != 'false' &&
                rawIsActive.toString() != '0'));
    return SnappyPin(
      id: json['id'] as String? ??
          'pin_${DateTime.now().millisecondsSinceEpoch}',
      number: (json['number'] as num?)?.toInt() ?? 1,
      xRatio: (json['xRatio'] as num?)?.toDouble() ??
          (json['x'] as num?)?.toDouble() ??
          0.0,
      yRatio: (json['yRatio'] as num?)?.toDouble() ??
          (json['y'] as num?)?.toDouble() ??
          0.0,
      comment: json['comment'] as String? ?? '',
      target: target,
      isActive: isActive,
    );
  }
}

/// Data class representing a single drawing stroke or point.
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

/// Helper class for persisting and restoring feedback drafts via SharedPreferences.
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
  });

  Map<String, dynamic> toJson() => {
        'imageBytesBase64': base64Encode(imageBytes),
        'widgetTree': widgetTree,
        'screenClassName': screenClassName,
        'screenSignature': screenSignature,
        'drawingPoints': drawingPoints.map((p) => p.toJson()).toList(),
        'pins': pins.map((p) => p.toJson()).toList(),
        'memo': memo,
        if (drawingAspectRatio != null)
          'drawingAspectRatio': drawingAspectRatio,
        'timestamp': timestamp,
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
      timestamp:
          json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
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
      final double scaleX = point.recordedSize.width > 0
          ? size.width / point.recordedSize.width
          : 1.0;
      final double scaleY = point.recordedSize.height > 0
          ? size.height / point.recordedSize.height
          : 1.0;

      // 1. When auto-masking rectangles exist
      if (point.rect != null) {
        final scaledRect = Rect.fromLTRB(
          point.rect!.left * scaleX,
          point.rect!.top * scaleY,
          point.rect!.right * scaleX,
          point.rect!.bottom * scaleY,
        );

        if (point.tool == SnappyDrawingTool.mosaic) {
          // Render frosted rounded rectangle overlay
          final bgPaint = Paint()
            ..color = const Color(0xE62A2A2E)
            ..style = PaintingStyle.fill;
          canvas.drawRRect(
            RRect.fromRectAndRadius(scaledRect, const Radius.circular(6)),
            bgPaint,
          );

          // Pixelated mosaic grid lines
          final gridPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.12)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke;
          for (double x = scaledRect.left; x < scaledRect.right; x += 10) {
            canvas.drawLine(Offset(x, scaledRect.top),
                Offset(x, scaledRect.bottom), gridPaint);
          }
          for (double y = scaledRect.top; y < scaledRect.bottom; y += 10) {
            canvas.drawLine(Offset(scaledRect.left, y),
                Offset(scaledRect.right, y), gridPaint);
          }
        } else {
          // Solid black masking
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

      // 2. Render freehand drawn paths
      if (point.tool == SnappyDrawingTool.mosaic) {
        // Mosaic pixelation tile rendering
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

      // Render red pen and black pen strokes
      final paint = Paint()
        ..color = point.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = point.strokeWidth * scaleX
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < point.offsets.length - 1; i++) {
        if (point.offsets[i] != null && point.offsets[i + 1] != null) {
          final p1 = Offset(
              point.offsets[i]!.dx * scaleX, point.offsets[i]!.dy * scaleY);
          final p2 = Offset(point.offsets[i + 1]!.dx * scaleX,
              point.offsets[i + 1]!.dy * scaleY);
          canvas.drawLine(p1, p2, paint);
        } else if (point.offsets[i] != null && point.offsets[i + 1] == null) {
          final p1 = Offset(
              point.offsets[i]!.dx * scaleX, point.offsets[i]!.dy * scaleY);
          canvas.drawPoints(ui.PointMode.points, [p1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Internal bridge delegating to the active [SnappySnagLocalization].
class _SdkLocale {
  static SnappySnagLocalization get _l => SnappySnag().localization;

  static String get disabledTitle => _l.disabledTitle;
  static String get disabledContent => _l.disabledContent;
  static String get start => _l.start;
  static String get ok => _l.ok;
  static String get feedbackModeDialogTitle => _l.feedbackModeDialogTitle;
  static String get feedbackModeDialogContent => _l.feedbackModeDialogContent;
  static String get feedbackModeAlreadyVisibleTitle =>
      _l.feedbackModeAlreadyVisibleTitle;
  static String get feedbackModeAlreadyVisibleContent =>
      _l.feedbackModeAlreadyVisibleContent;
  static String get privacyConfirmTitle => _l.privacyConfirmTitle;
  static String get privacyConfirmContent => _l.privacyConfirmContent;
  static String privacyShareAccountWithEmail(String email) =>
      _l.privacyShareAccountWithEmail(email);
  static String get privacyShareAccount => _l.privacyShareAccount;
  static String get privacyAnonymousHint => _l.privacyAnonymousHint;
  static String get backToEdit => _l.backToEdit;
  static String get sendConfirm => _l.sendConfirm;
  static String get cancel => _l.cancel;
  static String get send => _l.send;
  static String get sending => _l.sending;
  static String get titleFeedback => _l.titleFeedback;
  static String get statusSuccess => _l.statusSuccess;
  static String get statusDemoSuccess => _l.statusDemoSuccess;
  static String get statusRateLimit => _l.statusRateLimit;
  static String get statusGenericError => _l.statusGenericError;
  static String get userModeUnavailable => _l.userModeUnavailable;
  static String get statusInvalidKey => _l.statusInvalidKey;
  static String get statusUnauthorizedPackage => _l.statusUnauthorizedPackage;
  static String get statusNetworkError => _l.statusNetworkError;
  static String get done => _l.done;
  static String get delete => _l.delete;
  static String get pinCommentTitle => _l.pinCommentTitle;
  static String get pinCommentHint => _l.pinCommentHint;
  static String get pinLimitReached => _l.pinLimitReached;
  static String get pinRequiredSnackBar => _l.pinRequiredSnackBar;
  static String get close => _l.close;
  static String get back => _l.back;
  static String get elementAttachedBadge => _l.elementAttachedBadge;
  static String get analyzingScreen => _l.analyzingScreen;
  static String get clearConfirmTitle => _l.clearConfirmTitle;
  static String get clearConfirmBody => _l.clearConfirmBody;
  static String get clearConfirmButton => _l.clearConfirmButton;
  static String get draftFoundTitle => _l.draftFoundTitle;
  static String get draftFoundContent => _l.draftFoundContent;
  static String get resumeDraft => _l.resumeDraft;
  static String get discardAndNewCapture => _l.discardAndNewCapture;
  static String get saveDraftPromptTitle => _l.saveDraftPromptTitle;
  static String get saveDraftPromptOnCancel => _l.saveDraftPromptOnCancel;
  static String get saveDraftPromptOnFailedSend =>
      _l.saveDraftPromptOnFailedSend;
  static String get saveDraft => _l.saveDraft;
  static String get discardDraft => _l.discardDraft;
  static String get stayOnScreen => _l.stayOnScreen;
  static String get draftSavedToast => _l.draftSavedToast;
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
      ..strokeWidth = 24.0 *
          scale // This creates the 12px clear gap on each side of the bolt
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
