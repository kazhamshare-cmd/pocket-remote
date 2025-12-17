import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// サポートする言語
enum AppLanguage {
  ja, // 日本語
  en, // English
}

// 言語設定のProvider
final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>((ref) {
  return LanguageNotifier();
});

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.ja); // デフォルトは日本語

  void setLanguage(AppLanguage language) {
    state = language;
  }

  void toggleLanguage() {
    state = state == AppLanguage.ja ? AppLanguage.en : AppLanguage.ja;
  }
}

// ローカライズ文字列
class L10n {
  final AppLanguage language;

  L10n(this.language);

  // 言語名
  String get languageName => language == AppLanguage.ja ? '日本語' : 'English';
  String get languageFlag => language == AppLanguage.ja ? '🇯🇵' : '🇺🇸';

  // ===== Paywall Screen =====
  String get appName => 'RemoteTouch';
  String get appTagline => language == AppLanguage.ja
      ? 'スマホからPCを自由に操作'
      : 'Control Your PC From Your Smartphone';

  String get featureKeyboard => language == AppLanguage.ja ? 'キーボード' : 'Keyboard';
  String get featureKeyboardDesc => language == AppLanguage.ja
      ? 'iPhoneからPCに入力'
      : 'Type on your PC from iPhone';
  String get featureMouse => language == AppLanguage.ja ? 'マウス' : 'Mouse';
  String get featureMouseDesc => language == AppLanguage.ja
      ? 'トラックパッドとして使用'
      : 'Use as trackpad';
  String get featureScreenShare => language == AppLanguage.ja ? '画面共有' : 'Screen Share';
  String get featureScreenShareDesc => language == AppLanguage.ja
      ? 'PC画面を表示'
      : 'View your PC screen';
  String get featureRemoteAccess => language == AppLanguage.ja ? 'リモートアクセス' : 'Remote Access';
  String get featureRemoteAccessDesc => language == AppLanguage.ja
      ? 'どこからでも接続'
      : 'Connect from anywhere';

  String get monthlyPlan => language == AppLanguage.ja ? '月額プラン' : 'Monthly Plan';
  String get freeTrial => language == AppLanguage.ja ? '3日間無料お試し' : '3-day free trial';
  String get startFreeTrial => language == AppLanguage.ja ? '無料で始める' : 'Start Free Trial';
  String get restorePurchases => language == AppLanguage.ja ? '購入を復元' : 'Restore Purchases';
  String get manageSubscription => language == AppLanguage.ja ? 'サブスク管理' : 'Manage Subscription';
  String get termsOfUse => language == AppLanguage.ja ? '利用規約' : 'Terms of Use';
  String get privacyPolicy => language == AppLanguage.ja ? 'プライバシーポリシー' : 'Privacy Policy';
  String get subscriptionRestored => language == AppLanguage.ja ? 'サブスクリプションを復元しました！' : 'Subscription restored!';
  String get noActiveSubscription => language == AppLanguage.ja ? 'アクティブなサブスクリプションがありません' : 'No active subscription found';
  String get close => language == AppLanguage.ja ? '閉じる' : 'Close';

  // ===== Scan Screen =====
  String get scanQRCode => language == AppLanguage.ja ? 'QRコードをスキャン' : 'Scan QR Code';
  String get connectToPC => language == AppLanguage.ja ? 'PCに接続' : 'Connect to PC';
  String get manualConnection => language == AppLanguage.ja ? '手動接続' : 'Manual Connection';
  String get connectionSettings => language == AppLanguage.ja ? '接続設定' : 'Connection Settings';
  String get localConnection => language == AppLanguage.ja ? 'ローカル' : 'Local';
  String get externalConnection => language == AppLanguage.ja ? '外部接続' : 'External';
  String get ipAddress => language == AppLanguage.ja ? 'IPアドレス' : 'IP Address';
  String get port => language == AppLanguage.ja ? 'ポート' : 'Port';
  String get token => language == AppLanguage.ja ? 'トークン' : 'Token';
  String get hostname => language == AppLanguage.ja ? 'ホスト名' : 'Hostname';
  String get connect => language == AppLanguage.ja ? '接続' : 'Connect';
  String get cancel => language == AppLanguage.ja ? 'キャンセル' : 'Cancel';
  String get connecting => language == AppLanguage.ja ? '接続中...' : 'Connecting...';
  String get connected => language == AppLanguage.ja ? '接続済み' : 'Connected';
  String get disconnected => language == AppLanguage.ja ? '切断' : 'Disconnected';
  String get connectionFailed => language == AppLanguage.ja ? '接続失敗' : 'Connection Failed';
  String get retry => language == AppLanguage.ja ? '再試行' : 'Retry';
  String get cameraPermissionRequired => language == AppLanguage.ja
      ? 'QRコードをスキャンするにはカメラの許可が必要です'
      : 'Camera permission is required to scan QR codes';
  String get openSettings => language == AppLanguage.ja ? '設定を開く' : 'Open Settings';

  // ===== Commands Screen =====
  String get commands => language == AppLanguage.ja ? 'コマンド' : 'Commands';
  String get screenShare => language == AppLanguage.ja ? '画面共有' : 'Screen Share';
  String get addCommand => language == AppLanguage.ja ? 'コマンド追加' : 'Add Command';
  String get commandName => language == AppLanguage.ja ? 'コマンド名' : 'Command Name';
  String get commandContent => language == AppLanguage.ja ? 'コマンド内容' : 'Command Content';
  String get add => language == AppLanguage.ja ? '追加' : 'Add';
  String get noCommands => language == AppLanguage.ja ? 'コマンドがありません' : 'No commands';
  String get running => language == AppLanguage.ja ? '実行中...' : 'Running...';
  String get success => language == AppLanguage.ja ? '成功' : 'Success';
  String get failed => language == AppLanguage.ja ? '失敗' : 'Failed';

  // ===== Screen Share Screen =====
  String get apps => language == AppLanguage.ja ? 'アプリ' : 'Apps';
  String get mouse => language == AppLanguage.ja ? 'マウス' : 'Mouse';
  String get view => language == AppLanguage.ja ? '閲覧' : 'View';
  String get drag => language == AppLanguage.ja ? 'ドラッグ' : 'Drag';
  String get move => language == AppLanguage.ja ? '移動' : 'Move';
  String get finder => language == AppLanguage.ja ? 'Finder' : 'Finder';
  String get reset => language == AppLanguage.ja ? 'リセット' : 'Reset';
  String get closeWindow => language == AppLanguage.ja ? '閉じる' : 'Close';
  String get keyboard => language == AppLanguage.ja ? 'キーボード' : 'Keyboard';
  String get loadingScreen => language == AppLanguage.ja ? '画面を読み込み中...' : 'Loading screen...';
  String get runningApps => language == AppLanguage.ja ? '起動中のアプリ' : 'Running Apps';
  String get fetchingApps => language == AppLanguage.ja ? 'アプリを取得中...' : 'Fetching apps...';
  String get tabs => language == AppLanguage.ja ? 'タブ' : 'Tabs';
  String get fetchingTabs => language == AppLanguage.ja ? 'タブを取得中...' : 'Fetching tabs...';
  String get quitApp => language == AppLanguage.ja ? 'アプリを終了' : 'Quit App';
  String quitAppConfirm(String appName) => language == AppLanguage.ja
      ? '$appName を終了しますか？'
      : 'Quit $appName?';
  String appQuit(String appName) => language == AppLanguage.ja
      ? '$appName を終了しました'
      : '$appName has been quit';
  String get quit => language == AppLanguage.ja ? '終了' : 'Quit';
  String get send => language == AppLanguage.ja ? '送信' : 'Send';
  String get input => language == AppLanguage.ja ? '入力...' : 'Input...';
  String get autoEnter => language == AppLanguage.ja ? 'Enter' : 'Enter';
  String get unknownApp => language == AppLanguage.ja ? '不明なアプリ' : 'Unknown App';

  // 操作説明
  String get operationGuide => language == AppLanguage.ja ? '操作ガイド' : 'Controls';
  String get tapToMove => language == AppLanguage.ja ? 'タップ: 移動' : 'Tap: Move';
  String get doubleTapToClick => language == AppLanguage.ja ? 'ダブルタップ: クリック' : 'Double-tap: Click';
  String get longPressForRightClick => language == AppLanguage.ja ? '長押し: 右クリック' : 'Long press: Right-click';
  String get swipeToDrag => language == AppLanguage.ja ? 'スワイプ: ドラッグ' : 'Swipe: Drag';
  String get pinchToZoom => language == AppLanguage.ja ? 'ピンチ: ズーム' : 'Pinch: Zoom';

  String get dragModeOn => language == AppLanguage.ja
      ? 'ドラッグモード: スワイプでドラッグ操作'
      : 'Drag mode: Swipe to drag';
  String get moveModeOn => language == AppLanguage.ja
      ? '移動モード: タップで移動、ダブルタップでクリック'
      : 'Move mode: Tap to move, double-tap to click';

  // Directory/File browser
  String get directory => language == AppLanguage.ja ? 'ディレクトリ' : 'Directory';
  String get file => language == AppLanguage.ja ? 'ファイル' : 'File';

  // Terminal
  String get window => language == AppLanguage.ja ? 'ウィンドウ' : 'Window';
  String get tab => language == AppLanguage.ja ? 'タブ' : 'Tab';
  String get busy => language == AppLanguage.ja ? '実行中' : 'Running';

  // 特殊キー
  String get enter => 'Enter';
  String get escape => 'Esc';
  String get delete => 'Del';
}

// ローカライズ文字列を取得するためのProvider
final l10nProvider = Provider<L10n>((ref) {
  final language = ref.watch(languageProvider);
  return L10n(language);
});
