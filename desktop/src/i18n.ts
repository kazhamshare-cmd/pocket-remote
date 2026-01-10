// Supported languages
export type AppLanguage = 'ja' | 'en' | 'zh' | 'ko' | 'de';

// Language metadata
export const languages: Record<AppLanguage, { name: string; flag: string }> = {
  ja: { name: '日本語', flag: '🇯🇵' },
  en: { name: 'English', flag: '🇺🇸' },
  zh: { name: '中文', flag: '🇨🇳' },
  ko: { name: '한국어', flag: '🇰🇷' },
  de: { name: 'Deutsch', flag: '🇩🇪' },
};

// Translation helper
type Translations = Record<AppLanguage, string>;

function t(translations: Translations, lang: AppLanguage): string {
  return translations[lang] || translations.en;
}

// Get all translations for a language
export function getTranslations(lang: AppLanguage) {
  return {
    // App title
    appName: 'RemoteTouch',

    // Connection dialog
    connectionRequest: t({
      ja: '接続リクエスト',
      en: 'Connection Request',
      zh: '连接请求',
      ko: '연결 요청',
      de: 'Verbindungsanfrage',
    }, lang),
    allowConnection: t({
      ja: 'このデバイスからの接続を許可しますか？',
      en: 'Allow connection from this device?',
      zh: '允许此设备连接？',
      ko: '이 기기의 연결을 허용하시겠습니까?',
      de: 'Verbindung von diesem Gerät erlauben?',
    }, lang),
    allow: t({
      ja: '許可',
      en: 'Allow',
      zh: '允许',
      ko: '허용',
      de: 'Erlauben',
    }, lang),
    deny: t({
      ja: '拒否',
      en: 'Deny',
      zh: '拒绝',
      ko: '거부',
      de: 'Ablehnen',
    }, lang),
    autodenied: t({
      ja: '30秒後に自動拒否',
      en: 'Auto-denied after 30 seconds',
      zh: '30秒后自动拒绝',
      ko: '30초 후 자동 거부',
      de: 'Automatisch abgelehnt nach 30 Sekunden',
    }, lang),

    // Update notification
    updateAvailable: t({
      ja: '新しいバージョンがあります！',
      en: 'New version available!',
      zh: '有新版本可用！',
      ko: '새 버전이 있습니다!',
      de: 'Neue Version verfügbar!',
    }, lang),
    updateNow: t({
      ja: '今すぐ更新',
      en: 'Update Now',
      zh: '立即更新',
      ko: '지금 업데이트',
      de: 'Jetzt aktualisieren',
    }, lang),
    later: t({
      ja: '後で',
      en: 'Later',
      zh: '稍后',
      ko: '나중에',
      de: 'Später',
    }, lang),
    updating: t({
      ja: '更新中...',
      en: 'Updating...',
      zh: '更新中...',
      ko: '업데이트 중...',
      de: 'Wird aktualisiert...',
    }, lang),

    // Accessibility permission
    accessibilityRequired: t({
      ja: 'アクセシビリティ権限が必要です',
      en: 'Accessibility Permission Required',
      zh: '需要辅助功能权限',
      ko: '접근성 권한이 필요합니다',
      de: 'Bedienungshilfen-Berechtigung erforderlich',
    }, lang),
    accessibilityDescription: t({
      ja: 'キーボードとマウスの操作には、アクセシビリティ権限が必要です。システム設定で有効にしてください。',
      en: 'Keyboard and mouse control requires accessibility permission. Please enable it in System Settings.',
      zh: '键盘和鼠标控制需要辅助功能权限。请在系统设置中启用。',
      ko: '키보드와 마우스 제어에는 접근성 권한이 필요합니다. 시스템 설정에서 활성화해 주세요.',
      de: 'Tastatur- und Maussteuerung erfordert Bedienungshilfen-Berechtigung. Bitte in den Systemeinstellungen aktivieren.',
    }, lang),
    openSystemSettings: t({
      ja: 'システム設定を開く',
      en: 'Open System Settings',
      zh: '打开系统设置',
      ko: '시스템 설정 열기',
      de: 'Systemeinstellungen öffnen',
    }, lang),
    recheck: t({
      ja: '再確認',
      en: 'Recheck',
      zh: '重新检查',
      ko: '다시 확인',
      de: 'Erneut prüfen',
    }, lang),
    permissionSteps: t({
      ja: '手順:',
      en: 'Steps:',
      zh: '步骤:',
      ko: '단계:',
      de: 'Schritte:',
    }, lang),
    step1: t({
      ja: 'システム設定 → プライバシーとセキュリティ',
      en: 'System Settings → Privacy & Security',
      zh: '系统设置 → 隐私与安全性',
      ko: '시스템 설정 → 개인정보 보호 및 보안',
      de: 'Systemeinstellungen → Datenschutz & Sicherheit',
    }, lang),
    step2: t({
      ja: '「アクセシビリティ」を選択',
      en: 'Select "Accessibility"',
      zh: '选择「辅助功能」',
      ko: '"손쉬운 사용" 선택',
      de: '"Bedienungshilfen" auswählen',
    }, lang),
    step3: t({
      ja: '「RemoteTouch」または「Terminal」を有効にする',
      en: 'Enable "RemoteTouch" or "Terminal"',
      zh: '启用「RemoteTouch」或「终端」',
      ko: '"RemoteTouch" 또는 "Terminal" 활성화',
      de: '"RemoteTouch" oder "Terminal" aktivieren',
    }, lang),
    permissionOK: t({
      ja: '権限 OK',
      en: 'Permission OK',
      zh: '权限已授予',
      ko: '권한 확인됨',
      de: 'Berechtigung OK',
    }, lang),

    // Connection status
    waitingForConnection: t({
      ja: '接続待機中...',
      en: 'Waiting for connection...',
      zh: '等待连接...',
      ko: '연결 대기 중...',
      de: 'Warte auf Verbindung...',
    }, lang),
    connected: t({
      ja: '接続済み',
      en: 'Connected',
      zh: '已连接',
      ko: '연결됨',
      de: 'Verbunden',
    }, lang),

    // QR Code section
    scanQRCode: t({
      ja: 'QRコードをスキャンして接続',
      en: 'Scan QR Code to Connect',
      zh: '扫描二维码连接',
      ko: 'QR 코드를 스캔하여 연결',
      de: 'QR-Code scannen zum Verbinden',
    }, lang),
    local: t({
      ja: 'ローカル',
      en: 'Local',
      zh: '本地',
      ko: '로컬',
      de: 'Lokal',
    }, lang),
    external: t({
      ja: '外部',
      en: 'External',
      zh: '外部',
      ko: '외부',
      de: 'Extern',
    }, lang),
    connectWithinSameNetwork: t({
      ja: '同じWiFi/ネットワーク内で接続',
      en: 'Connect within same WiFi/network',
      zh: '在同一WiFi/网络内连接',
      ko: '동일한 WiFi/네트워크에서 연결',
      de: 'Im selben WiFi/Netzwerk verbinden',
    }, lang),
    connectViaInternet: t({
      ja: 'インターネット経由で接続',
      en: 'Connect via internet',
      zh: '通过互联网连接',
      ko: '인터넷을 통해 연결',
      de: 'Über Internet verbinden',
    }, lang),
    manualConnection: t({
      ja: '手動接続:',
      en: 'Manual Connection:',
      zh: '手动连接:',
      ko: '수동 연결:',
      de: 'Manuelle Verbindung:',
    }, lang),
    ipAddress: 'IP',
    port: 'Port',
    token: 'Token',
    url: 'URL',

    // Tunnel
    startTunnel: t({
      ja: 'トンネル開始',
      en: 'Start Tunnel',
      zh: '启动隧道',
      ko: '터널 시작',
      de: 'Tunnel starten',
    }, lang),
    stopTunnel: t({
      ja: 'トンネル停止',
      en: 'Stop Tunnel',
      zh: '停止隧道',
      ko: '터널 중지',
      de: 'Tunnel stoppen',
    }, lang),
    startingTunnel: t({
      ja: 'トンネル開始中...',
      en: 'Starting tunnel...',
      zh: '正在启动隧道...',
      ko: '터널 시작 중...',
      de: 'Tunnel wird gestartet...',
    }, lang),
    cloudflaredNotInstalled: t({
      ja: 'cloudflaredがインストールされていません',
      en: 'cloudflared is not installed',
      zh: 'cloudflared 未安装',
      ko: 'cloudflared가 설치되지 않았습니다',
      de: 'cloudflared ist nicht installiert',
    }, lang),
    autoInstall: t({
      ja: '自動インストール',
      en: 'Auto Install',
      zh: '自动安装',
      ko: '자동 설치',
      de: 'Automatisch installieren',
    }, lang),
    manualInstallHint: t({
      ja: 'または手動で:',
      en: 'Or manual:',
      zh: '或手动安装:',
      ko: '또는 수동으로:',
      de: 'Oder manuell:',
    }, lang),
    enableExternalConnection: t({
      ja: '外部ネットワークからの接続を有効にする',
      en: 'Enable connection from external network',
      zh: '启用外部网络连接',
      ko: '외부 네트워크 연결 활성화',
      de: 'Verbindung von externem Netzwerk aktivieren',
    }, lang),
    installing: t({
      ja: 'インストール中...',
      en: 'Installing...',
      zh: '安装中...',
      ko: '설치 중...',
      de: 'Wird installiert...',
    }, lang),

    // Connected devices
    connectedDevices: t({
      ja: '接続中のデバイス',
      en: 'Connected Devices',
      zh: '已连接设备',
      ko: '연결된 기기',
      de: 'Verbundene Geräte',
    }, lang),
    noDevicesConnected: t({
      ja: 'デバイスが接続されていません。モバイルアプリでQRコードをスキャンしてください。',
      en: 'No devices connected. Scan QR code with mobile app.',
      zh: '没有设备连接。请用手机App扫描二维码。',
      ko: '연결된 기기가 없습니다. 모바일 앱으로 QR 코드를 스캔하세요.',
      de: 'Keine Geräte verbunden. QR-Code mit mobiler App scannen.',
    }, lang),

    // Language selector
    selectLanguage: t({
      ja: '言語を選択',
      en: 'Select Language',
      zh: '选择语言',
      ko: '언어 선택',
      de: 'Sprache wählen',
    }, lang),
  };
}

// Get browser/system language
export function getSystemLanguage(): AppLanguage {
  const browserLang = navigator.language.split('-')[0];
  if (browserLang === 'ja') return 'ja';
  if (browserLang === 'zh') return 'zh';
  if (browserLang === 'ko') return 'ko';
  if (browserLang === 'de') return 'de';
  return 'en';
}

// Language storage key
const LANGUAGE_KEY = 'remotetouch_language';

// Save language preference
export function saveLanguage(lang: AppLanguage): void {
  localStorage.setItem(LANGUAGE_KEY, lang);
}

// Load saved language or use system default
export function loadLanguage(): AppLanguage {
  const saved = localStorage.getItem(LANGUAGE_KEY) as AppLanguage | null;
  if (saved && Object.keys(languages).includes(saved)) {
    return saved;
  }
  return getSystemLanguage();
}
