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
  String get manualConnection => '手動接続 / Manual Connection';
  String get connectionSettings => language == AppLanguage.ja ? '接続設定' : 'Connection Settings';
  String get localConnection => 'LAN';
  String get externalConnection => 'Internet';
  String get ipAddress => 'IP Address';
  String get port => 'Port';
  String get token => 'Token';
  String get hostname => 'Hostname';
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
  String get command => language == AppLanguage.ja ? 'コマンド' : 'Command';
  String get deleteCommand => language == AppLanguage.ja ? 'コマンド削除' : 'Delete Command';
  String get deleteConfirm => language == AppLanguage.ja ? 'を削除しますか？' : 'Delete this?';
  String get deleteBtn => language == AppLanguage.ja ? '削除' : 'Delete';

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
  String get newTerminal => language == AppLanguage.ja ? '新規' : 'New';

  // 特殊キー
  String get enter => 'Enter';
  String get escape => 'Esc';
  String get delete => 'Del';

  // キーボード入力
  String get realtimeMode => language == AppLanguage.ja ? 'リアルタイム' : 'Realtime';
  String get manualMode => language == AppLanguage.ja ? '手動送信' : 'Manual';
  String get inputHint => language == AppLanguage.ja ? '入力...' : 'Input...';
  String get realtimeInputHint => language == AppLanguage.ja ? '入力するとリアルタイムで反映...' : 'Type to send in realtime...';
  String get textInput => language == AppLanguage.ja ? 'テキスト入力' : 'Text Input';
  String get sendToApp => language == AppLanguage.ja ? ' に送信' : '';
  String get inputTextHint => language == AppLanguage.ja ? '入力するテキスト...' : 'Text to type...';
  String get autoEnterAfterSend => language == AppLanguage.ja ? '送信後にEnterを押す' : 'Press Enter after send';
  String get messageSend => language == AppLanguage.ja ? '(メッセージ送信)' : '(Send message)';
  String get sendAndEnter => language == AppLanguage.ja ? '送信 + Enter' : 'Send + Enter';

  // ウィンドウ関連
  String windowsOf(String appName) => language == AppLanguage.ja
      ? '$appName のウィンドウ'
      : 'Windows of $appName';
  String get selectWindow => language == AppLanguage.ja ? 'ウィンドウを選択してください' : 'Select a window';
  String get fetchingWindows => language == AppLanguage.ja ? 'ウィンドウを取得中...' : 'Fetching windows...';
  String get noTitle => language == AppLanguage.ja ? '(タイトルなし)' : '(No title)';
  String get minimized => language == AppLanguage.ja ? '最小化中' : 'Minimized';
  String tabsOf(String appName) => language == AppLanguage.ja
      ? '$appName のタブ'
      : 'Tabs of $appName';

  // Spotlight
  String get spotlightSearch => language == AppLanguage.ja ? 'Spotlight検索' : 'Spotlight Search';
  String get searchHint => language == AppLanguage.ja ? 'アプリ名やファイル名...' : 'App or file name...';
  String get search => language == AppLanguage.ja ? '検索' : 'Search';

  // 画面共有画面
  String get startScreenShare => language == AppLanguage.ja ? '画面共有を開始' : 'Start Screen Share';
  String get screenShareDescription => language == AppLanguage.ja
      ? 'PC画面を表示して操作できます'
      : 'View and control your PC screen';

  // 言語選択
  String get selectLanguage => language == AppLanguage.ja ? '言語を選択' : 'Select Language';

  // トライアル利用規約（Google/Apple必須）
  String trialTermsWithPrice(String price, {required bool isIOS}) {
    final cancelInstructions = isIOS
        ? (language == AppLanguage.ja
            ? '設定 > Apple ID > サブスクリプション'
            : 'Settings > Apple ID > Subscriptions')
        : (language == AppLanguage.ja
            ? 'Google Play > お支払いと定期購入 > 定期購入'
            : 'Google Play > Payments & subscriptions > Subscriptions');

    return language == AppLanguage.ja
        ? '• 3日間の無料トライアル後、$price/月が課金されます\n'
          '• トライアル終了の24時間前までにキャンセルしない場合、自動的に定期購入が開始されます\n'
          '• $cancelInstructionsからいつでもキャンセル可能です'
        : '• After 3-day free trial, $price/month will be charged\n'
          '• Subscription auto-renews unless cancelled 24 hours before trial ends\n'
          '• Cancel anytime in $cancelInstructions';
  }

  // 閉じるダイアログ
  String get closePaywallTitle => language == AppLanguage.ja ? 'アプリを閉じますか？' : 'Close app?';
  String get closePaywallMessage => language == AppLanguage.ja
      ? 'RemoteTouchを使用するにはサブスクリプションが必要です。'
      : 'Subscription is required to use RemoteTouch.';
}

// ローカライズ文字列を取得するためのProvider
final l10nProvider = Provider<L10n>((ref) {
  final language = ref.watch(languageProvider);
  return L10n(language);
});
