import 'package:flutter_riverpod/flutter_riverpod.dart';

// サポートする言語
enum AppLanguage {
  ja, // 日本語
  en, // English
  zh, // 中文 (简体)
  ko, // 한국어
  de, // Deutsch
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

  void nextLanguage() {
    final values = AppLanguage.values;
    final currentIndex = values.indexOf(state);
    state = values[(currentIndex + 1) % values.length];
  }

  // Alias for compatibility
  void toggleLanguage() => nextLanguage();
}

// ローカライズ文字列
class L10n {
  final AppLanguage language;

  L10n(this.language);

  // ヘルパー関数
  String _t(Map<AppLanguage, String> translations) {
    return translations[language] ?? translations[AppLanguage.en] ?? '';
  }

  // 言語名
  String get languageName => _t({
    AppLanguage.ja: '日本語',
    AppLanguage.en: 'English',
    AppLanguage.zh: '中文',
    AppLanguage.ko: '한국어',
    AppLanguage.de: 'Deutsch',
  });

  String get languageFlag => _t({
    AppLanguage.ja: '🇯🇵',
    AppLanguage.en: '🇺🇸',
    AppLanguage.zh: '🇨🇳',
    AppLanguage.ko: '🇰🇷',
    AppLanguage.de: '🇩🇪',
  });

  // ===== Paywall Screen =====
  String get appName => 'RemoteTouch';

  String get appTagline => _t({
    AppLanguage.ja: 'スマホからPCを自由に操作',
    AppLanguage.en: 'Control Your PC From Your Smartphone',
    AppLanguage.zh: '用手机自由控制电脑',
    AppLanguage.ko: '스마트폰으로 PC를 자유롭게 조작',
    AppLanguage.de: 'Steuern Sie Ihren PC vom Smartphone',
  });

  String get featureKeyboard => _t({
    AppLanguage.ja: 'キーボード',
    AppLanguage.en: 'Keyboard',
    AppLanguage.zh: '键盘',
    AppLanguage.ko: '키보드',
    AppLanguage.de: 'Tastatur',
  });

  String get featureKeyboardDesc => _t({
    AppLanguage.ja: 'iPhoneからPCに入力',
    AppLanguage.en: 'Type on your PC from iPhone',
    AppLanguage.zh: '从手机输入到电脑',
    AppLanguage.ko: '스마트폰에서 PC로 입력',
    AppLanguage.de: 'Vom iPhone auf dem PC tippen',
  });

  String get featureMouse => _t({
    AppLanguage.ja: 'マウス',
    AppLanguage.en: 'Mouse',
    AppLanguage.zh: '鼠标',
    AppLanguage.ko: '마우스',
    AppLanguage.de: 'Maus',
  });

  String get featureMouseDesc => _t({
    AppLanguage.ja: 'トラックパッドとして使用',
    AppLanguage.en: 'Use as trackpad',
    AppLanguage.zh: '作为触控板使用',
    AppLanguage.ko: '트랙패드로 사용',
    AppLanguage.de: 'Als Trackpad verwenden',
  });

  String get featureScreenShare => _t({
    AppLanguage.ja: '画面共有',
    AppLanguage.en: 'Screen Share',
    AppLanguage.zh: '屏幕共享',
    AppLanguage.ko: '화면 공유',
    AppLanguage.de: 'Bildschirmfreigabe',
  });

  String get featureScreenShareDesc => _t({
    AppLanguage.ja: 'PC画面を表示',
    AppLanguage.en: 'View your PC screen',
    AppLanguage.zh: '查看电脑屏幕',
    AppLanguage.ko: 'PC 화면 보기',
    AppLanguage.de: 'PC-Bildschirm anzeigen',
  });

  String get featureRemoteAccess => _t({
    AppLanguage.ja: 'リモートアクセス',
    AppLanguage.en: 'Remote Access',
    AppLanguage.zh: '远程访问',
    AppLanguage.ko: '원격 접속',
    AppLanguage.de: 'Fernzugriff',
  });

  String get featureRemoteAccessDesc => _t({
    AppLanguage.ja: 'どこからでも接続',
    AppLanguage.en: 'Connect from anywhere',
    AppLanguage.zh: '随时随地连接',
    AppLanguage.ko: '어디서나 연결',
    AppLanguage.de: 'Von überall verbinden',
  });

  String get monthlyPlan => _t({
    AppLanguage.ja: '月額プラン',
    AppLanguage.en: 'Monthly Plan',
    AppLanguage.zh: '月度套餐',
    AppLanguage.ko: '월간 요금제',
    AppLanguage.de: 'Monatsplan',
  });

  String get freeTrial => _t({
    AppLanguage.ja: '3日間無料お試し',
    AppLanguage.en: '3-day free trial',
    AppLanguage.zh: '3天免费试用',
    AppLanguage.ko: '3일 무료 체험',
    AppLanguage.de: '3 Tage kostenlos testen',
  });

  String get startFreeTrial => _t({
    AppLanguage.ja: '無料で始める',
    AppLanguage.en: 'Start Free Trial',
    AppLanguage.zh: '开始免费试用',
    AppLanguage.ko: '무료 체험 시작',
    AppLanguage.de: 'Kostenlos starten',
  });

  String get restorePurchases => _t({
    AppLanguage.ja: '購入を復元',
    AppLanguage.en: 'Restore Purchases',
    AppLanguage.zh: '恢复购买',
    AppLanguage.ko: '구매 복원',
    AppLanguage.de: 'Käufe wiederherstellen',
  });

  String get manageSubscription => _t({
    AppLanguage.ja: 'サブスク管理',
    AppLanguage.en: 'Manage Subscription',
    AppLanguage.zh: '管理订阅',
    AppLanguage.ko: '구독 관리',
    AppLanguage.de: 'Abo verwalten',
  });

  String get termsOfUse => _t({
    AppLanguage.ja: '利用規約',
    AppLanguage.en: 'Terms of Use',
    AppLanguage.zh: '使用条款',
    AppLanguage.ko: '이용약관',
    AppLanguage.de: 'Nutzungsbedingungen',
  });

  String get privacyPolicy => _t({
    AppLanguage.ja: 'プライバシーポリシー',
    AppLanguage.en: 'Privacy Policy',
    AppLanguage.zh: '隐私政策',
    AppLanguage.ko: '개인정보 처리방침',
    AppLanguage.de: 'Datenschutz',
  });

  String get subscriptionRestored => _t({
    AppLanguage.ja: 'サブスクリプションを復元しました！',
    AppLanguage.en: 'Subscription restored!',
    AppLanguage.zh: '订阅已恢复！',
    AppLanguage.ko: '구독이 복원되었습니다!',
    AppLanguage.de: 'Abonnement wiederhergestellt!',
  });

  String get noActiveSubscription => _t({
    AppLanguage.ja: 'アクティブなサブスクリプションがありません',
    AppLanguage.en: 'No active subscription found',
    AppLanguage.zh: '未找到有效订阅',
    AppLanguage.ko: '활성 구독을 찾을 수 없습니다',
    AppLanguage.de: 'Kein aktives Abonnement gefunden',
  });

  String get close => _t({
    AppLanguage.ja: '閉じる',
    AppLanguage.en: 'Close',
    AppLanguage.zh: '关闭',
    AppLanguage.ko: '닫기',
    AppLanguage.de: 'Schließen',
  });

  // ===== Scan Screen =====
  String get scanQRCode => _t({
    AppLanguage.ja: 'QRコードをスキャン',
    AppLanguage.en: 'Scan QR Code',
    AppLanguage.zh: '扫描二维码',
    AppLanguage.ko: 'QR 코드 스캔',
    AppLanguage.de: 'QR-Code scannen',
  });

  String get connectToPC => _t({
    AppLanguage.ja: 'PCに接続',
    AppLanguage.en: 'Connect to PC',
    AppLanguage.zh: '连接到电脑',
    AppLanguage.ko: 'PC에 연결',
    AppLanguage.de: 'Mit PC verbinden',
  });

  String get manualConnection => _t({
    AppLanguage.ja: '手動接続',
    AppLanguage.en: 'Manual Connection',
    AppLanguage.zh: '手动连接',
    AppLanguage.ko: '수동 연결',
    AppLanguage.de: 'Manuelle Verbindung',
  });

  String get connectionSettings => _t({
    AppLanguage.ja: '接続設定',
    AppLanguage.en: 'Connection Settings',
    AppLanguage.zh: '连接设置',
    AppLanguage.ko: '연결 설정',
    AppLanguage.de: 'Verbindungseinstellungen',
  });

  String get localConnection => 'LAN';
  String get externalConnection => 'Internet';
  String get ipAddress => 'IP';
  String get port => 'Port';
  String get token => 'Token';
  String get hostname => 'Host';

  String get connect => _t({
    AppLanguage.ja: '接続',
    AppLanguage.en: 'Connect',
    AppLanguage.zh: '连接',
    AppLanguage.ko: '연결',
    AppLanguage.de: 'Verbinden',
  });

  String get cancel => _t({
    AppLanguage.ja: 'キャンセル',
    AppLanguage.en: 'Cancel',
    AppLanguage.zh: '取消',
    AppLanguage.ko: '취소',
    AppLanguage.de: 'Abbrechen',
  });

  String get connecting => _t({
    AppLanguage.ja: '接続中...',
    AppLanguage.en: 'Connecting...',
    AppLanguage.zh: '连接中...',
    AppLanguage.ko: '연결 중...',
    AppLanguage.de: 'Verbindung...',
  });

  String get connected => _t({
    AppLanguage.ja: '接続済み',
    AppLanguage.en: 'Connected',
    AppLanguage.zh: '已连接',
    AppLanguage.ko: '연결됨',
    AppLanguage.de: 'Verbunden',
  });

  String get disconnected => _t({
    AppLanguage.ja: '切断',
    AppLanguage.en: 'Disconnected',
    AppLanguage.zh: '已断开',
    AppLanguage.ko: '연결 끊김',
    AppLanguage.de: 'Getrennt',
  });

  String get connectionFailed => _t({
    AppLanguage.ja: '接続失敗',
    AppLanguage.en: 'Connection Failed',
    AppLanguage.zh: '连接失败',
    AppLanguage.ko: '연결 실패',
    AppLanguage.de: 'Verbindung fehlgeschlagen',
  });

  String get retry => _t({
    AppLanguage.ja: '再試行',
    AppLanguage.en: 'Retry',
    AppLanguage.zh: '重试',
    AppLanguage.ko: '다시 시도',
    AppLanguage.de: 'Wiederholen',
  });

  String get cameraPermissionRequired => _t({
    AppLanguage.ja: 'QRコードをスキャンするにはカメラの許可が必要です',
    AppLanguage.en: 'Camera permission is required to scan QR codes',
    AppLanguage.zh: '扫描二维码需要相机权限',
    AppLanguage.ko: 'QR 코드 스캔에는 카메라 권한이 필요합니다',
    AppLanguage.de: 'Kameraberechtigung zum Scannen von QR-Codes erforderlich',
  });

  String get openSettings => _t({
    AppLanguage.ja: '設定を開く',
    AppLanguage.en: 'Open Settings',
    AppLanguage.zh: '打开设置',
    AppLanguage.ko: '설정 열기',
    AppLanguage.de: 'Einstellungen öffnen',
  });

  // ===== Commands Screen =====
  String get commands => _t({
    AppLanguage.ja: 'コマンド',
    AppLanguage.en: 'Commands',
    AppLanguage.zh: '命令',
    AppLanguage.ko: '명령',
    AppLanguage.de: 'Befehle',
  });

  String get screenShare => _t({
    AppLanguage.ja: '画面共有',
    AppLanguage.en: 'Screen Share',
    AppLanguage.zh: '屏幕共享',
    AppLanguage.ko: '화면 공유',
    AppLanguage.de: 'Bildschirmfreigabe',
  });

  String get addCommand => _t({
    AppLanguage.ja: 'コマンド追加',
    AppLanguage.en: 'Add Command',
    AppLanguage.zh: '添加命令',
    AppLanguage.ko: '명령 추가',
    AppLanguage.de: 'Befehl hinzufügen',
  });

  String get commandName => _t({
    AppLanguage.ja: 'コマンド名',
    AppLanguage.en: 'Command Name',
    AppLanguage.zh: '命令名称',
    AppLanguage.ko: '명령 이름',
    AppLanguage.de: 'Befehlsname',
  });

  String get commandContent => _t({
    AppLanguage.ja: 'コマンド内容',
    AppLanguage.en: 'Command Content',
    AppLanguage.zh: '命令内容',
    AppLanguage.ko: '명령 내용',
    AppLanguage.de: 'Befehlsinhalt',
  });

  String get add => _t({
    AppLanguage.ja: '追加',
    AppLanguage.en: 'Add',
    AppLanguage.zh: '添加',
    AppLanguage.ko: '추가',
    AppLanguage.de: 'Hinzufügen',
  });

  String get noCommands => _t({
    AppLanguage.ja: 'コマンドがありません',
    AppLanguage.en: 'No commands',
    AppLanguage.zh: '没有命令',
    AppLanguage.ko: '명령이 없습니다',
    AppLanguage.de: 'Keine Befehle',
  });

  String get running => _t({
    AppLanguage.ja: '実行中...',
    AppLanguage.en: 'Running...',
    AppLanguage.zh: '运行中...',
    AppLanguage.ko: '실행 중...',
    AppLanguage.de: 'Wird ausgeführt...',
  });

  String get success => _t({
    AppLanguage.ja: '成功',
    AppLanguage.en: 'Success',
    AppLanguage.zh: '成功',
    AppLanguage.ko: '성공',
    AppLanguage.de: 'Erfolg',
  });

  String get failed => _t({
    AppLanguage.ja: '失敗',
    AppLanguage.en: 'Failed',
    AppLanguage.zh: '失败',
    AppLanguage.ko: '실패',
    AppLanguage.de: 'Fehlgeschlagen',
  });

  String get command => _t({
    AppLanguage.ja: 'コマンド',
    AppLanguage.en: 'Command',
    AppLanguage.zh: '命令',
    AppLanguage.ko: '명령',
    AppLanguage.de: 'Befehl',
  });

  String get deleteCommand => _t({
    AppLanguage.ja: 'コマンド削除',
    AppLanguage.en: 'Delete Command',
    AppLanguage.zh: '删除命令',
    AppLanguage.ko: '명령 삭제',
    AppLanguage.de: 'Befehl löschen',
  });

  String get deleteConfirm => _t({
    AppLanguage.ja: 'を削除しますか？',
    AppLanguage.en: 'Delete this?',
    AppLanguage.zh: '确定删除？',
    AppLanguage.ko: '삭제하시겠습니까?',
    AppLanguage.de: 'Löschen?',
  });

  String get deleteBtn => _t({
    AppLanguage.ja: '削除',
    AppLanguage.en: 'Delete',
    AppLanguage.zh: '删除',
    AppLanguage.ko: '삭제',
    AppLanguage.de: 'Löschen',
  });

  // ===== Screen Share Screen =====
  String get apps => _t({
    AppLanguage.ja: 'アプリ',
    AppLanguage.en: 'Apps',
    AppLanguage.zh: '应用',
    AppLanguage.ko: '앱',
    AppLanguage.de: 'Apps',
  });

  String get mouse => _t({
    AppLanguage.ja: 'マウス',
    AppLanguage.en: 'Mouse',
    AppLanguage.zh: '鼠标',
    AppLanguage.ko: '마우스',
    AppLanguage.de: 'Maus',
  });

  String get view => _t({
    AppLanguage.ja: '閲覧',
    AppLanguage.en: 'View',
    AppLanguage.zh: '查看',
    AppLanguage.ko: '보기',
    AppLanguage.de: 'Ansicht',
  });

  String get drag => _t({
    AppLanguage.ja: 'ドラッグ',
    AppLanguage.en: 'Drag',
    AppLanguage.zh: '拖拽',
    AppLanguage.ko: '드래그',
    AppLanguage.de: 'Ziehen',
  });

  String get move => _t({
    AppLanguage.ja: '移動',
    AppLanguage.en: 'Move',
    AppLanguage.zh: '移动',
    AppLanguage.ko: '이동',
    AppLanguage.de: 'Bewegen',
  });

  String get finder => 'Finder';

  String get reset => _t({
    AppLanguage.ja: 'リセット',
    AppLanguage.en: 'Reset',
    AppLanguage.zh: '重置',
    AppLanguage.ko: '초기화',
    AppLanguage.de: 'Zurücksetzen',
  });

  String get closeWindow => _t({
    AppLanguage.ja: '閉じる',
    AppLanguage.en: 'Close',
    AppLanguage.zh: '关闭',
    AppLanguage.ko: '닫기',
    AppLanguage.de: 'Schließen',
  });

  String get keyboard => _t({
    AppLanguage.ja: 'キーボード',
    AppLanguage.en: 'Keyboard',
    AppLanguage.zh: '键盘',
    AppLanguage.ko: '키보드',
    AppLanguage.de: 'Tastatur',
  });

  String get loadingScreen => _t({
    AppLanguage.ja: '画面を読み込み中...',
    AppLanguage.en: 'Loading screen...',
    AppLanguage.zh: '加载屏幕中...',
    AppLanguage.ko: '화면 로딩 중...',
    AppLanguage.de: 'Bildschirm wird geladen...',
  });

  String get runningApps => _t({
    AppLanguage.ja: '起動中のアプリ',
    AppLanguage.en: 'Running Apps',
    AppLanguage.zh: '正在运行的应用',
    AppLanguage.ko: '실행 중인 앱',
    AppLanguage.de: 'Laufende Apps',
  });

  String get fetchingApps => _t({
    AppLanguage.ja: 'アプリを取得中...',
    AppLanguage.en: 'Fetching apps...',
    AppLanguage.zh: '获取应用中...',
    AppLanguage.ko: '앱 가져오는 중...',
    AppLanguage.de: 'Apps werden geladen...',
  });

  String get tabs => _t({
    AppLanguage.ja: 'タブ',
    AppLanguage.en: 'Tabs',
    AppLanguage.zh: '标签页',
    AppLanguage.ko: '탭',
    AppLanguage.de: 'Tabs',
  });

  String get fetchingTabs => _t({
    AppLanguage.ja: 'タブを取得中...',
    AppLanguage.en: 'Fetching tabs...',
    AppLanguage.zh: '获取标签页中...',
    AppLanguage.ko: '탭 가져오는 중...',
    AppLanguage.de: 'Tabs werden geladen...',
  });

  String get quitApp => _t({
    AppLanguage.ja: 'アプリを終了',
    AppLanguage.en: 'Quit App',
    AppLanguage.zh: '退出应用',
    AppLanguage.ko: '앱 종료',
    AppLanguage.de: 'App beenden',
  });

  String quitAppConfirm(String appName) => _t({
    AppLanguage.ja: '$appName を終了しますか？',
    AppLanguage.en: 'Quit $appName?',
    AppLanguage.zh: '退出 $appName？',
    AppLanguage.ko: '$appName을(를) 종료하시겠습니까?',
    AppLanguage.de: '$appName beenden?',
  });

  String appQuit(String appName) => _t({
    AppLanguage.ja: '$appName を終了しました',
    AppLanguage.en: '$appName has been quit',
    AppLanguage.zh: '$appName 已退出',
    AppLanguage.ko: '$appName이(가) 종료되었습니다',
    AppLanguage.de: '$appName wurde beendet',
  });

  String get quit => _t({
    AppLanguage.ja: '終了',
    AppLanguage.en: 'Quit',
    AppLanguage.zh: '退出',
    AppLanguage.ko: '종료',
    AppLanguage.de: 'Beenden',
  });

  String get send => _t({
    AppLanguage.ja: '送信',
    AppLanguage.en: 'Send',
    AppLanguage.zh: '发送',
    AppLanguage.ko: '전송',
    AppLanguage.de: 'Senden',
  });

  String get input => _t({
    AppLanguage.ja: '入力...',
    AppLanguage.en: 'Input...',
    AppLanguage.zh: '输入...',
    AppLanguage.ko: '입력...',
    AppLanguage.de: 'Eingabe...',
  });

  String get autoEnter => 'Enter';

  String get unknownApp => _t({
    AppLanguage.ja: '不明なアプリ',
    AppLanguage.en: 'Unknown App',
    AppLanguage.zh: '未知应用',
    AppLanguage.ko: '알 수 없는 앱',
    AppLanguage.de: 'Unbekannte App',
  });

  // 操作説明
  String get operationGuide => _t({
    AppLanguage.ja: '操作ガイド',
    AppLanguage.en: 'Controls',
    AppLanguage.zh: '操作指南',
    AppLanguage.ko: '조작 가이드',
    AppLanguage.de: 'Steuerung',
  });

  String get tapToMove => _t({
    AppLanguage.ja: 'タップ: 移動',
    AppLanguage.en: 'Tap: Move',
    AppLanguage.zh: '点击: 移动',
    AppLanguage.ko: '탭: 이동',
    AppLanguage.de: 'Tippen: Bewegen',
  });

  String get doubleTapToClick => _t({
    AppLanguage.ja: 'ダブルタップ: クリック',
    AppLanguage.en: 'Double-tap: Click',
    AppLanguage.zh: '双击: 点击',
    AppLanguage.ko: '더블 탭: 클릭',
    AppLanguage.de: 'Doppeltippen: Klicken',
  });

  String get longPressForRightClick => _t({
    AppLanguage.ja: '長押し: 右クリック',
    AppLanguage.en: 'Long press: Right-click',
    AppLanguage.zh: '长按: 右键',
    AppLanguage.ko: '길게 누르기: 우클릭',
    AppLanguage.de: 'Lange drücken: Rechtsklick',
  });

  String get swipeToDrag => _t({
    AppLanguage.ja: 'スワイプ: ドラッグ',
    AppLanguage.en: 'Swipe: Drag',
    AppLanguage.zh: '滑动: 拖拽',
    AppLanguage.ko: '스와이프: 드래그',
    AppLanguage.de: 'Wischen: Ziehen',
  });

  String get pinchToZoom => _t({
    AppLanguage.ja: 'ピンチ: ズーム',
    AppLanguage.en: 'Pinch: Zoom',
    AppLanguage.zh: '捏合: 缩放',
    AppLanguage.ko: '핀치: 줌',
    AppLanguage.de: 'Pinch: Zoom',
  });

  String get dragModeOn => _t({
    AppLanguage.ja: 'ドラッグモード: スワイプでドラッグ操作',
    AppLanguage.en: 'Drag mode: Swipe to drag',
    AppLanguage.zh: '拖拽模式: 滑动进行拖拽',
    AppLanguage.ko: '드래그 모드: 스와이프로 드래그',
    AppLanguage.de: 'Ziehmodus: Wischen zum Ziehen',
  });

  String get moveModeOn => _t({
    AppLanguage.ja: '移動モード: タップで移動、ダブルタップでクリック',
    AppLanguage.en: 'Move mode: Tap to move, double-tap to click',
    AppLanguage.zh: '移动模式: 点击移动，双击点击',
    AppLanguage.ko: '이동 모드: 탭으로 이동, 더블 탭으로 클릭',
    AppLanguage.de: 'Bewegungsmodus: Tippen zum Bewegen, Doppeltippen zum Klicken',
  });

  // Directory/File browser
  String get directory => _t({
    AppLanguage.ja: 'ディレクトリ',
    AppLanguage.en: 'Directory',
    AppLanguage.zh: '目录',
    AppLanguage.ko: '디렉토리',
    AppLanguage.de: 'Verzeichnis',
  });

  String get file => _t({
    AppLanguage.ja: 'ファイル',
    AppLanguage.en: 'File',
    AppLanguage.zh: '文件',
    AppLanguage.ko: '파일',
    AppLanguage.de: 'Datei',
  });

  // Terminal
  String get window => _t({
    AppLanguage.ja: 'ウィンドウ',
    AppLanguage.en: 'Window',
    AppLanguage.zh: '窗口',
    AppLanguage.ko: '창',
    AppLanguage.de: 'Fenster',
  });

  String get tab => _t({
    AppLanguage.ja: 'タブ',
    AppLanguage.en: 'Tab',
    AppLanguage.zh: '标签页',
    AppLanguage.ko: '탭',
    AppLanguage.de: 'Tab',
  });

  String get busy => _t({
    AppLanguage.ja: '実行中',
    AppLanguage.en: 'Running',
    AppLanguage.zh: '运行中',
    AppLanguage.ko: '실행 중',
    AppLanguage.de: 'Läuft',
  });

  String get newTerminal => _t({
    AppLanguage.ja: '新規',
    AppLanguage.en: 'New',
    AppLanguage.zh: '新建',
    AppLanguage.ko: '새로 만들기',
    AppLanguage.de: 'Neu',
  });

  // 特殊キー
  String get enter => 'Enter';
  String get escape => 'Esc';
  String get delete => 'Del';

  // キーボード入力
  String get realtimeMode => _t({
    AppLanguage.ja: 'リアルタイム',
    AppLanguage.en: 'Realtime',
    AppLanguage.zh: '实时',
    AppLanguage.ko: '실시간',
    AppLanguage.de: 'Echtzeit',
  });

  String get manualMode => _t({
    AppLanguage.ja: '手動送信',
    AppLanguage.en: 'Manual',
    AppLanguage.zh: '手动',
    AppLanguage.ko: '수동',
    AppLanguage.de: 'Manuell',
  });

  String get inputHint => _t({
    AppLanguage.ja: '入力...',
    AppLanguage.en: 'Input...',
    AppLanguage.zh: '输入...',
    AppLanguage.ko: '입력...',
    AppLanguage.de: 'Eingabe...',
  });

  String get realtimeInputHint => _t({
    AppLanguage.ja: '入力するとリアルタイムで反映...',
    AppLanguage.en: 'Type to send in realtime...',
    AppLanguage.zh: '输入后实时发送...',
    AppLanguage.ko: '입력하면 실시간으로 반영...',
    AppLanguage.de: 'Eingabe wird in Echtzeit gesendet...',
  });

  String get textInput => _t({
    AppLanguage.ja: 'テキスト入力',
    AppLanguage.en: 'Text Input',
    AppLanguage.zh: '文本输入',
    AppLanguage.ko: '텍스트 입력',
    AppLanguage.de: 'Texteingabe',
  });

  String get sendToApp => _t({
    AppLanguage.ja: ' に送信',
    AppLanguage.en: '',
    AppLanguage.zh: ' 发送',
    AppLanguage.ko: '에 전송',
    AppLanguage.de: ' senden',
  });

  String get inputTextHint => _t({
    AppLanguage.ja: '入力するテキスト...',
    AppLanguage.en: 'Text to type...',
    AppLanguage.zh: '输入的文本...',
    AppLanguage.ko: '입력할 텍스트...',
    AppLanguage.de: 'Text eingeben...',
  });

  String get autoEnterAfterSend => _t({
    AppLanguage.ja: '送信後にEnterを押す',
    AppLanguage.en: 'Press Enter after send',
    AppLanguage.zh: '发送后按Enter',
    AppLanguage.ko: '전송 후 Enter 누르기',
    AppLanguage.de: 'Nach dem Senden Enter drücken',
  });

  String get messageSend => _t({
    AppLanguage.ja: '(メッセージ送信)',
    AppLanguage.en: '(Send message)',
    AppLanguage.zh: '(发送消息)',
    AppLanguage.ko: '(메시지 전송)',
    AppLanguage.de: '(Nachricht senden)',
  });

  String get sendAndEnter => _t({
    AppLanguage.ja: '送信 + Enter',
    AppLanguage.en: 'Send + Enter',
    AppLanguage.zh: '发送 + Enter',
    AppLanguage.ko: '전송 + Enter',
    AppLanguage.de: 'Senden + Enter',
  });

  // ウィンドウ関連
  String windowsOf(String appName) => _t({
    AppLanguage.ja: '$appName のウィンドウ',
    AppLanguage.en: 'Windows of $appName',
    AppLanguage.zh: '$appName 的窗口',
    AppLanguage.ko: '$appName의 창',
    AppLanguage.de: 'Fenster von $appName',
  });

  String get selectWindow => _t({
    AppLanguage.ja: 'ウィンドウを選択してください',
    AppLanguage.en: 'Select a window',
    AppLanguage.zh: '请选择窗口',
    AppLanguage.ko: '창을 선택하세요',
    AppLanguage.de: 'Fenster auswählen',
  });

  String get fetchingWindows => _t({
    AppLanguage.ja: 'ウィンドウを取得中...',
    AppLanguage.en: 'Fetching windows...',
    AppLanguage.zh: '获取窗口中...',
    AppLanguage.ko: '창 가져오는 중...',
    AppLanguage.de: 'Fenster werden geladen...',
  });

  String get noTitle => _t({
    AppLanguage.ja: '(タイトルなし)',
    AppLanguage.en: '(No title)',
    AppLanguage.zh: '(无标题)',
    AppLanguage.ko: '(제목 없음)',
    AppLanguage.de: '(Kein Titel)',
  });

  String get minimized => _t({
    AppLanguage.ja: '最小化中',
    AppLanguage.en: 'Minimized',
    AppLanguage.zh: '已最小化',
    AppLanguage.ko: '최소화됨',
    AppLanguage.de: 'Minimiert',
  });

  String tabsOf(String appName) => _t({
    AppLanguage.ja: '$appName のタブ',
    AppLanguage.en: 'Tabs of $appName',
    AppLanguage.zh: '$appName 的标签页',
    AppLanguage.ko: '$appName의 탭',
    AppLanguage.de: 'Tabs von $appName',
  });

  // Spotlight
  String get spotlightSearch => _t({
    AppLanguage.ja: 'Spotlight検索',
    AppLanguage.en: 'Spotlight Search',
    AppLanguage.zh: 'Spotlight 搜索',
    AppLanguage.ko: 'Spotlight 검색',
    AppLanguage.de: 'Spotlight-Suche',
  });

  String get searchHint => _t({
    AppLanguage.ja: 'アプリ名やファイル名...',
    AppLanguage.en: 'App or file name...',
    AppLanguage.zh: '应用或文件名...',
    AppLanguage.ko: '앱 또는 파일 이름...',
    AppLanguage.de: 'App- oder Dateiname...',
  });

  String get search => _t({
    AppLanguage.ja: '検索',
    AppLanguage.en: 'Search',
    AppLanguage.zh: '搜索',
    AppLanguage.ko: '검색',
    AppLanguage.de: 'Suchen',
  });

  // 画面共有画面
  String get startScreenShare => _t({
    AppLanguage.ja: '画面共有を開始',
    AppLanguage.en: 'Start Screen Share',
    AppLanguage.zh: '开始屏幕共享',
    AppLanguage.ko: '화면 공유 시작',
    AppLanguage.de: 'Bildschirmfreigabe starten',
  });

  String get screenShareDescription => _t({
    AppLanguage.ja: 'PC画面を表示して操作できます',
    AppLanguage.en: 'View and control your PC screen',
    AppLanguage.zh: '查看并控制电脑屏幕',
    AppLanguage.ko: 'PC 화면을 보고 조작할 수 있습니다',
    AppLanguage.de: 'PC-Bildschirm anzeigen und steuern',
  });

  // 言語選択
  String get selectLanguage => _t({
    AppLanguage.ja: '言語を選択',
    AppLanguage.en: 'Select Language',
    AppLanguage.zh: '选择语言',
    AppLanguage.ko: '언어 선택',
    AppLanguage.de: 'Sprache wählen',
  });

  // トライアル利用規約（Google/Apple必須）
  String trialTermsWithPrice(String price, {required bool isIOS}) {
    final cancelInstructions = isIOS
        ? _t({
            AppLanguage.ja: '設定 > Apple ID > サブスクリプション',
            AppLanguage.en: 'Settings > Apple ID > Subscriptions',
            AppLanguage.zh: '设置 > Apple ID > 订阅',
            AppLanguage.ko: '설정 > Apple ID > 구독',
            AppLanguage.de: 'Einstellungen > Apple ID > Abonnements',
          })
        : _t({
            AppLanguage.ja: 'Google Play > お支払いと定期購入 > 定期購入',
            AppLanguage.en: 'Google Play > Payments & subscriptions > Subscriptions',
            AppLanguage.zh: 'Google Play > 付款和订阅 > 订阅',
            AppLanguage.ko: 'Google Play > 결제 및 정기 결제 > 정기 결제',
            AppLanguage.de: 'Google Play > Zahlungen & Abos > Abos',
          });

    return _t({
      AppLanguage.ja: '• 3日間の無料トライアル後、$price/月が課金されます\n'
          '• トライアル終了の24時間前までにキャンセルしない場合、自動的に定期購入が開始されます\n'
          '• $cancelInstructionsからいつでもキャンセル可能です',
      AppLanguage.en: '• After 3-day free trial, $price/month will be charged\n'
          '• Subscription auto-renews unless cancelled 24 hours before trial ends\n'
          '• Cancel anytime in $cancelInstructions',
      AppLanguage.zh: '• 3天免费试用后，将收取 $price/月\n'
          '• 如果在试用结束前24小时未取消，将自动续订\n'
          '• 可随时在 $cancelInstructions 中取消',
      AppLanguage.ko: '• 3일 무료 체험 후, $price/월이 청구됩니다\n'
          '• 체험 종료 24시간 전에 취소하지 않으면 자동으로 구독이 갱신됩니다\n'
          '• $cancelInstructions에서 언제든지 취소 가능합니다',
      AppLanguage.de: '• Nach 3 Tagen kostenloser Testversion werden $price/Monat berechnet\n'
          '• Das Abo verlängert sich automatisch, wenn nicht 24 Stunden vor Ende der Testversion gekündigt wird\n'
          '• Jederzeit in $cancelInstructions kündigen',
    });
  }

  // 閉じるダイアログ
  String get closePaywallTitle => _t({
    AppLanguage.ja: 'アプリを閉じますか？',
    AppLanguage.en: 'Close app?',
    AppLanguage.zh: '关闭应用？',
    AppLanguage.ko: '앱을 닫으시겠습니까?',
    AppLanguage.de: 'App schließen?',
  });

  String get closePaywallMessage => _t({
    AppLanguage.ja: 'RemoteTouchを使用するにはサブスクリプションが必要です。',
    AppLanguage.en: 'Subscription is required to use RemoteTouch.',
    AppLanguage.zh: '使用RemoteTouch需要订阅。',
    AppLanguage.ko: 'RemoteTouch를 사용하려면 구독이 필요합니다.',
    AppLanguage.de: 'Für RemoteTouch ist ein Abonnement erforderlich.',
  });

  // ===== Camera/Scan Screen =====
  String get cameraPermissionRequiredTitle => _t({
    AppLanguage.ja: 'カメラ許可が必要です',
    AppLanguage.en: 'Camera permission required',
    AppLanguage.zh: '需要相机权限',
    AppLanguage.ko: '카메라 권한이 필요합니다',
    AppLanguage.de: 'Kameraberechtigung erforderlich',
  });

  String get retryBtn => _t({
    AppLanguage.ja: '再試行',
    AppLanguage.en: 'Retry',
    AppLanguage.zh: '重试',
    AppLanguage.ko: '다시 시도',
    AppLanguage.de: 'Wiederholen',
  });

  String get useManualConnection => _t({
    AppLanguage.ja: '手動接続を使用',
    AppLanguage.en: 'Use manual connection',
    AppLanguage.zh: '使用手动连接',
    AppLanguage.ko: '수동 연결 사용',
    AppLanguage.de: 'Manuelle Verbindung verwenden',
  });

  String get scanPCQRCode => _t({
    AppLanguage.ja: 'PCのQRコードをスキャン',
    AppLanguage.en: 'Scan QR code on your PC',
    AppLanguage.zh: '扫描电脑上的二维码',
    AppLanguage.ko: 'PC의 QR 코드를 스캔',
    AppLanguage.de: 'QR-Code auf Ihrem PC scannen',
  });

  String get connectionDisconnected => _t({
    AppLanguage.ja: '接続が切断されました',
    AppLanguage.en: 'Connection was disconnected',
    AppLanguage.zh: '连接已断开',
    AppLanguage.ko: '연결이 끊어졌습니다',
    AppLanguage.de: 'Verbindung wurde getrennt',
  });

  String get timeout => _t({
    AppLanguage.ja: 'タイムアウト',
    AppLanguage.en: 'Timeout',
    AppLanguage.zh: '超时',
    AppLanguage.ko: '시간 초과',
    AppLanguage.de: 'Zeitüberschreitung',
  });

  // ===== Shortcut Dialog =====
  String get addShortcut => _t({
    AppLanguage.ja: 'ショートカット追加',
    AppLanguage.en: 'Add Shortcut',
    AppLanguage.zh: '添加快捷方式',
    AppLanguage.ko: '단축키 추가',
    AppLanguage.de: 'Verknüpfung hinzufügen',
  });

  String get buttonName => _t({
    AppLanguage.ja: 'ボタン名',
    AppLanguage.en: 'Button Name',
    AppLanguage.zh: '按钮名称',
    AppLanguage.ko: '버튼 이름',
    AppLanguage.de: 'Schaltflächenname',
  });

  String get buttonNameHint => _t({
    AppLanguage.ja: '例: 履歴検索',
    AppLanguage.en: 'e.g. History Search',
    AppLanguage.zh: '例如: 历史搜索',
    AppLanguage.ko: '예: 기록 검색',
    AppLanguage.de: 'z.B. Verlaufssuche',
  });

  String get commandOrKey => _t({
    AppLanguage.ja: 'コマンド / キー',
    AppLanguage.en: 'Command / Key',
    AppLanguage.zh: '命令 / 键',
    AppLanguage.ko: '명령 / 키',
    AppLanguage.de: 'Befehl / Taste',
  });

  String get commandOrKeyHint => _t({
    AppLanguage.ja: '例: ctrl+r',
    AppLanguage.en: 'e.g. ctrl+r',
    AppLanguage.zh: '例如: ctrl+r',
    AppLanguage.ko: '예: ctrl+r',
    AppLanguage.de: 'z.B. ctrl+r',
  });

  String get inputFormat => _t({
    AppLanguage.ja: '入力形式:',
    AppLanguage.en: 'Input format:',
    AppLanguage.zh: '输入格式:',
    AppLanguage.ko: '입력 형식:',
    AppLanguage.de: 'Eingabeformat:',
  });

  String get formatString => _t({
    AppLanguage.ja: '文字列: yes, /help, git status',
    AppLanguage.en: 'String: yes, /help, git status',
    AppLanguage.zh: '字符串: yes, /help, git status',
    AppLanguage.ko: '문자열: yes, /help, git status',
    AppLanguage.de: 'Zeichenfolge: yes, /help, git status',
  });

  String get formatSingleKey => _t({
    AppLanguage.ja: '単一キー: tab, escape, enter, up, down',
    AppLanguage.en: 'Single key: tab, escape, enter, up, down',
    AppLanguage.zh: '单键: tab, escape, enter, up, down',
    AppLanguage.ko: '단일 키: tab, escape, enter, up, down',
    AppLanguage.de: 'Einzeltaste: tab, escape, enter, up, down',
  });

  String get formatModifier => _t({
    AppLanguage.ja: '修飾キー: ctrl+c, cmd+s, alt+f4',
    AppLanguage.en: 'Modifier: ctrl+c, cmd+s, alt+f4',
    AppLanguage.zh: '修饰键: ctrl+c, cmd+s, alt+f4',
    AppLanguage.ko: '수정자 키: ctrl+c, cmd+s, alt+f4',
    AppLanguage.de: 'Modifikator: ctrl+c, cmd+s, alt+f4',
  });

  String get formatCombo => _t({
    AppLanguage.ja: '複合: ctrl+shift+r, cmd+shift+p',
    AppLanguage.en: 'Combo: ctrl+shift+r, cmd+shift+p',
    AppLanguage.zh: '组合: ctrl+shift+r, cmd+shift+p',
    AppLanguage.ko: '조합: ctrl+shift+r, cmd+shift+p',
    AppLanguage.de: 'Kombination: ctrl+shift+r, cmd+shift+p',
  });

  String get save => _t({
    AppLanguage.ja: '保存',
    AppLanguage.en: 'Save',
    AppLanguage.zh: '保存',
    AppLanguage.ko: '저장',
    AppLanguage.de: 'Speichern',
  });

  String get edit => _t({
    AppLanguage.ja: '編集',
    AppLanguage.en: 'Edit',
    AppLanguage.zh: '编辑',
    AppLanguage.ko: '편집',
    AppLanguage.de: 'Bearbeiten',
  });

  String get editShortcut => _t({
    AppLanguage.ja: 'ショートカット編集',
    AppLanguage.en: 'Edit Shortcut',
    AppLanguage.zh: '编辑快捷方式',
    AppLanguage.ko: '단축키 편집',
    AppLanguage.de: 'Verknüpfung bearbeiten',
  });

  String get deleteShortcutConfirm => _t({
    AppLanguage.ja: 'このショートカットを削除しますか？',
    AppLanguage.en: 'Delete this shortcut?',
    AppLanguage.zh: '删除此快捷方式？',
    AppLanguage.ko: '이 단축키를 삭제하시겠습니까?',
    AppLanguage.de: 'Diese Verknüpfung löschen?',
  });

  // ===== Terms & Privacy (short summary) =====
  String get termsContent => _t({
    AppLanguage.ja: 'RemoteTouch 月額サブスクリプション\n\n'
        '・購入確認時にApple IDアカウントに課金されます。\n'
        '・現在の期間終了の24時間前までにキャンセルしない限り、サブスクリプションは自動更新されます。\n'
        '・現在の期間終了の24時間以内に更新料金が請求されます。\n'
        '・購入後、App Storeのアカウント設定からサブスクリプションを管理・キャンセルできます。\n'
        '・無料トライアル期間の未使用分は、サブスクリプション購入時に失効します。',
    AppLanguage.en: 'RemoteTouch Monthly Subscription\n\n'
        '- Payment will be charged to your Apple ID account at confirmation of purchase.\n'
        '- Subscription automatically renews unless canceled at least 24 hours before the end of the current period.\n'
        '- Your account will be charged for renewal within 24 hours prior to the end of the current period.\n'
        '- You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase.\n'
        '- Any unused portion of a free trial period will be forfeited when you purchase a subscription.',
    AppLanguage.zh: 'RemoteTouch 月度订阅\n\n'
        '・确认购买时将向您的Apple ID账户收费。\n'
        '・除非在当前周期结束前至少24小时取消，否则订阅将自动续订。\n'
        '・您的账户将在当前周期结束前24小时内被收取续订费用。\n'
        '・购买后，您可以在App Store的账户设置中管理和取消订阅。\n'
        '・购买订阅时，免费试用期的任何未使用部分将被作废。',
    AppLanguage.ko: 'RemoteTouch 월간 구독\n\n'
        '・구매 확인 시 Apple ID 계정으로 결제됩니다.\n'
        '・현재 기간 종료 최소 24시간 전에 취소하지 않으면 구독이 자동으로 갱신됩니다.\n'
        '・현재 기간 종료 24시간 이내에 갱신 요금이 청구됩니다.\n'
        '・구매 후 App Store의 계정 설정에서 구독을 관리하고 취소할 수 있습니다.\n'
        '・구독 구매 시 무료 체험 기간의 미사용 부분은 소멸됩니다.',
    AppLanguage.de: 'RemoteTouch Monatsabonnement\n\n'
        '・Die Zahlung wird bei Kaufbestätigung Ihrem Apple ID-Konto belastet.\n'
        '・Das Abonnement verlängert sich automatisch, es sei denn, es wird mindestens 24 Stunden vor Ende des aktuellen Zeitraums gekündigt.\n'
        '・Die Verlängerungsgebühr wird innerhalb von 24 Stunden vor Ende des aktuellen Zeitraums berechnet.\n'
        '・Sie können Ihre Abonnements nach dem Kauf in den Kontoeinstellungen im App Store verwalten und kündigen.\n'
        '・Nicht genutzte Teile einer kostenlosen Testversion verfallen beim Kauf eines Abonnements.',
  });

  String get privacyContent => _t({
    AppLanguage.ja: 'RemoteTouch プライバシーポリシー\n\n'
        'RemoteTouchはお客様のプライバシーを尊重します:\n\n'
        '・個人データを収集しません\n'
        '・第三者と情報を共有しません\n'
        '・デスクトップアプリとのみ直接通信します\n'
        '・安全な暗号化接続を使用します\n\n'
        'ご質問は、お問い合わせフォームからご連絡ください。',
    AppLanguage.en: 'RemoteTouch Privacy Policy\n\n'
        'We respect your privacy. RemoteTouch:\n\n'
        '- Does not collect personal data\n'
        '- Does not share your information with third parties\n'
        '- Only communicates directly with your desktop app\n'
        '- Uses secure encrypted connections\n\n'
        'For questions, please contact us through our inquiry form.',
    AppLanguage.zh: 'RemoteTouch 隐私政策\n\n'
        '我们尊重您的隐私。RemoteTouch:\n\n'
        '・不收集个人数据\n'
        '・不与第三方共享您的信息\n'
        '・仅与您的桌面应用程序直接通信\n'
        '・使用安全的加密连接\n\n'
        '如有问题，请通过我们的咨询表单联系我们。',
    AppLanguage.ko: 'RemoteTouch 개인정보 처리방침\n\n'
        '저희는 귀하의 개인정보를 존중합니다. RemoteTouch는:\n\n'
        '・개인 데이터를 수집하지 않습니다\n'
        '・제3자와 정보를 공유하지 않습니다\n'
        '・데스크톱 앱과만 직접 통신합니다\n'
        '・안전한 암호화 연결을 사용합니다\n\n'
        '질문이 있으시면 문의 양식을 통해 연락해 주세요.',
    AppLanguage.de: 'RemoteTouch Datenschutzrichtlinie\n\n'
        'Wir respektieren Ihre Privatsphäre. RemoteTouch:\n\n'
        '・Erfasst keine personenbezogenen Daten\n'
        '・Teilt Ihre Informationen nicht mit Dritten\n'
        '・Kommuniziert nur direkt mit Ihrer Desktop-App\n'
        '・Verwendet sichere verschlüsselte Verbindungen\n\n'
        'Bei Fragen kontaktieren Sie uns bitte über unser Kontaktformular.',
  });

  // Reorder mode
  String get reorderShortcuts => _t({
    AppLanguage.ja: '並び替え',
    AppLanguage.en: 'Reorder',
    AppLanguage.zh: '重新排序',
    AppLanguage.ko: '순서 변경',
    AppLanguage.de: 'Neu ordnen',
  });

  String get done => _t({
    AppLanguage.ja: '完了',
    AppLanguage.en: 'Done',
    AppLanguage.zh: '完成',
    AppLanguage.ko: '완료',
    AppLanguage.de: 'Fertig',
  });

  // ===== Command Safety =====
  String get dangerousCommandWarning => _t({
    AppLanguage.ja: '危険なコマンド',
    AppLanguage.en: 'Dangerous Command',
    AppLanguage.zh: '危险命令',
    AppLanguage.ko: '위험한 명령',
    AppLanguage.de: 'Gefährlicher Befehl',
  });

  String get dangerousCommandMessage => _t({
    AppLanguage.ja: 'このコマンドはシステムに重大な影響を与える可能性があります。実行しますか？',
    AppLanguage.en: 'This command may have serious effects on your system. Do you want to execute it?',
    AppLanguage.zh: '此命令可能对您的系统产生严重影响。您要执行它吗？',
    AppLanguage.ko: '이 명령은 시스템에 심각한 영향을 미칠 수 있습니다. 실행하시겠습니까?',
    AppLanguage.de: 'Dieser Befehl kann schwerwiegende Auswirkungen auf Ihr System haben. Möchten Sie ihn ausführen?',
  });

  String get commandToExecute => _t({
    AppLanguage.ja: '実行するコマンド:',
    AppLanguage.en: 'Command to execute:',
    AppLanguage.zh: '要执行的命令:',
    AppLanguage.ko: '실행할 명령:',
    AppLanguage.de: 'Auszuführender Befehl:',
  });

  String get execute => _t({
    AppLanguage.ja: '実行',
    AppLanguage.en: 'Execute',
    AppLanguage.zh: '执行',
    AppLanguage.ko: '실행',
    AppLanguage.de: 'Ausführen',
  });

  String get safeMode => _t({
    AppLanguage.ja: 'セーフモード',
    AppLanguage.en: 'Safe Mode',
    AppLanguage.zh: '安全模式',
    AppLanguage.ko: '안전 모드',
    AppLanguage.de: 'Sicherer Modus',
  });

  String get safeModeDesc => _t({
    AppLanguage.ja: '危険なコマンド実行前に確認ダイアログを表示',
    AppLanguage.en: 'Show confirmation dialog before executing dangerous commands',
    AppLanguage.zh: '执行危险命令前显示确认对话框',
    AppLanguage.ko: '위험한 명령 실행 전 확인 대화상자 표시',
    AppLanguage.de: 'Bestätigungsdialog vor Ausführung gefährlicher Befehle anzeigen',
  });

  String get commandHistory => _t({
    AppLanguage.ja: 'コマンド履歴',
    AppLanguage.en: 'Command History',
    AppLanguage.zh: '命令历史',
    AppLanguage.ko: '명령 기록',
    AppLanguage.de: 'Befehlsverlauf',
  });

  String get clearHistory => _t({
    AppLanguage.ja: '履歴をクリア',
    AppLanguage.en: 'Clear History',
    AppLanguage.zh: '清除历史',
    AppLanguage.ko: '기록 지우기',
    AppLanguage.de: 'Verlauf löschen',
  });

  String get noHistory => _t({
    AppLanguage.ja: '履歴がありません',
    AppLanguage.en: 'No history',
    AppLanguage.zh: '没有历史记录',
    AppLanguage.ko: '기록 없음',
    AppLanguage.de: 'Kein Verlauf',
  });

  String get blockedBySafeMode => _t({
    AppLanguage.ja: 'セーフモードによりブロックされました',
    AppLanguage.en: 'Blocked by Safe Mode',
    AppLanguage.zh: '被安全模式阻止',
    AppLanguage.ko: '안전 모드에 의해 차단됨',
    AppLanguage.de: 'Durch Sicheren Modus blockiert',
  });
}

// ローカライズ文字列を取得するためのProvider
final l10nProvider = Provider<L10n>((ref) {
  final language = ref.watch(languageProvider);
  return L10n(language);
});
