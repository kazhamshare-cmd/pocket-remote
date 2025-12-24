# RemoteTouch

iPhoneやAndroidからMac/Windowsをリモート操作するアプリケーション

## 概要

RemoteTouchは、モバイルデバイスからデスクトップPCを完全にリモート制御できるクロスプラットフォームアプリケーションです。WebRTCによる低遅延な画面共有と、直感的なタッチ操作でデスクトップを操作できます。

## 対応プラットフォーム

| プラットフォーム | 状態 |
|---|---|
| macOS (Apple Silicon) | ✅ 対応 |
| macOS (Intel) | ✅ 対応 |
| Windows (64-bit) | ✅ 対応 |
| iOS | ✅ App Store |
| Android | ✅ Google Play |

## ダウンロード

- [macOS (Apple Silicon)](https://github.com/kazhamshare-cmd/pocket-remote/releases)
- [macOS (Intel)](https://github.com/kazhamshare-cmd/pocket-remote/releases)
- [Windows (64-bit)](https://github.com/kazhamshare-cmd/pocket-remote/releases)
- iOS: App Store
- Android: Google Play

---

## 主な機能

### 1. 画面共有 (Screen Sharing)
- WebRTCベースの低遅延ストリーミング
- デュアルエンコーディング: JPEG / H.264
- 最大フルデスクトップ解像度対応
- ネットワーク状況に応じた適応的品質調整
- 特定領域のキャプチャ（ビューポート機能）
- ビットレート: 2 Mbps / フレームレート: 30 FPS

### 2. キーボード入力
- フルキーボードサポート
- 日本語入力対応（IME）
- カスタムショートカット保存
- 特殊キー対応（Shift, Cmd, Ctrl, Alt, etc.）
- テキスト入力のデバウンス処理
- 自動Enterオプション

### 3. マウス/トラックパッド操作
- マウス移動トラッキング
- クリック、ダブルクリック、ドラッグ
- 右クリック対応
- スクロール（上下左右）
- マルチタッチジェスチャー（ピンチ、パン）
- ドラッグモード / タップ移動モード切り替え

### 4. リモート接続
- **ローカルネットワーク (LAN)**: IP:Port:Token で接続
- **インターネット経由**: Cloudflare Tunnel による外部アクセス
- QRコードスキャンによる簡単ペアリング
- WebSocket (ws://) / Secure WebSocket (wss://) 対応
- トークンベース認証

### 5. アプリケーション管理
- 起動中アプリケーションの一覧表示
- アプリのフォーカス切り替え
- 複数ウィンドウ間の切り替え
- ウィンドウを閉じる / アプリを終了
- ターミナルアプリ・CLIツールの検出

### 6. ブラウザ制御
- Chrome, Safari, Firefox のタブ一覧取得
- 特定タブのアクティブ化
- URLナビゲーション

### 7. ファイル管理
- ディレクトリ閲覧
- ファイルプロパティ表示（サイズ、種類）
- デフォルトアプリでファイルを開く
- Spotlight検索連携 (macOS)

### 8. ターミナル/シェル機能
- フルPTY（疑似端末）セッション対応
- インタラクティブシェルコマンド（zsh/bash）
- 最大1000行の履歴保持
- リアルタイム出力ストリーミング
- 既存ターミナルの内容取得
- ANSIエスケープシーケンス対応

### 9. メッセージアプリ連携 (macOS)
- メッセージアプリのチャット一覧
- 特定チャットを開く
- SMS / iMessage 対応

### 10. ウィンドウ管理
- ウィンドウ情報取得（タイトル、位置、サイズ）
- ウィンドウの最大化 / リサイズ
- ウィンドウの移動
- 3倍ズーム機能（アプリフォーカス時）

---

## 画面構成（モバイルアプリ）

### スプラッシュ画面
- 起動時の読み込み画面
- 強制アップデートチェック

### ペイウォール画面
- サブスクリプション管理
- 機能紹介（キーボード、マウス、画面共有、リモートアクセス）
- 3日間無料トライアル
- 購入復元オプション
- 利用規約・プライバシーポリシーリンク
- 言語選択（日本語 / English）

### スキャン画面
- QRコードスキャン（カメラ使用）
- 手動接続ダイアログ（LAN / インターネットモード）
- 設定メニュー
- カメラ権限エラーハンドリング

### コマンド画面
- 接続状態表示
- デフォルトコマンド（Build, Test）
- 画面共有ボタン
- コマンドリスト管理

### 画面共有画面
- リアルタイム画面表示
- インタラクティブビューア（ズーム/パン）
- マウスモード / ビューモード切り替え
- インラインテキスト入力
- カスタムショートカットパネル
- カーソル位置表示
- リアルタイム同期トグル

### ターミナル画面
- フルPTYセッション
- スクロール可能な出力バッファ
- リアルタイムコマンド入力

---

## 技術スタック

### モバイルアプリ (Flutter)
| 技術 | 用途 |
|---|---|
| Flutter 3.x | UIフレームワーク |
| Riverpod | 状態管理 |
| go_router | ナビゲーション |
| flutter_webrtc | ビデオ/データチャネル |
| mobile_scanner | QRコードスキャン |
| Firebase Core | Firebase基盤 |
| Firebase Remote Config | リモート設定・強制アップデート |
| in_app_purchase | アプリ内課金 |
| package_info_plus | バージョン情報取得 |

### デスクトップアプリ (Tauri + Rust)
| 技術 | 用途 |
|---|---|
| Tauri 2.0 | デスクトップフレームワーク |
| Tokio | 非同期ランタイム |
| webrtc-rs | WebRTCピア接続 |
| scrap | 画面キャプチャ |
| enigo | キーボード/マウス制御 |
| openh264 | H.264エンコーディング |
| portable-pty | PTYセッション管理 |
| tokio-tungstenite | WebSocket通信 |
| Rayon | 並列処理 |

---

## 通信プロトコル

### WebSocket サーバー
- **ポート**: 9876
- **認証**: トークンベース
- **接続**: 複数クライアント同時対応
- **メッセージ形式**: JSON

### WebRTC
- **シグナリング**: SDPオファー/アンサー交換
- **接続**: ICE候補収集・交換
- **データ転送**: データチャネル（H.264フレーム）
- **STUNサーバー**: stun.l.google.com:19302

### Cloudflare Tunnel
- cloudflaredの自動インストール
- WSSによるセキュア接続
- 外部URL自動生成
- トンネルプロセス管理

---

## WebSocket メッセージタイプ (70種類以上)

### 認証
- `Auth` / `AuthResponse`

### 画面共有
- `StartScreenShare` / `StopScreenShare`
- `SetCaptureRegion` / `ResetCaptureRegion`
- `SetViewport` / `Scroll`
- `SetEncodingMode` / `EncodingModeResponse`

### 入力制御
- `Input` (マウス/キーボード)
- `MousePosition`
- `TypeText` / `TypeTextAndEnter` / `PressKey`

### アプリケーション
- `GetRunningApps` / `RunningApps`
- `FocusApp` / `FocusResult`
- `GetAppWindows` / `AppWindows`
- `FocusAppWindow` / `QuitApp`

### ブラウザ
- `GetBrowserTabs` / `BrowserTabs`
- `ActivateTab` / `ActivateTabResult`

### ターミナル
- `GetTerminalTabs` / `TerminalTabs`
- `ActivateTerminalTab`
- `GetTerminalContent` / `TerminalContent`

### シェル/コマンド
- `Execute` / `ExecuteResult`
- `ShellExecute` / `ShellExecuteResult`

### ファイルシステム
- `ListDirectory` / `DirectoryContents`
- `OpenFile`
- `SpotlightSearch`

### ウィンドウ管理
- `GetWindowInfo` / `WindowInfo`
- `MaximizeWindow` / `ResizeWindow` / `CloseWindow`

### メッセージ
- `GetMessagesChats` / `MessagesChats`
- `OpenMessagesChat`

### WebRTC
- `StartWebRTC` / `StopWebRTC`
- `WebRTCOffer` / `WebRTCAnswer`
- `WebRTCIceCandidate`

### PTY
- `PtyStart` / `PtyInput` / `PtyOutput`
- `PtyGetHistory` / `PtyHistory`

---

## サブスクリプション

| 項目 | 内容 |
|---|---|
| 価格 | 月額 $2.99 |
| 無料トライアル | 3日間 |
| iOS プロダクトID | `b19.ikushima.pocketremote.monthly` |
| Android プロダクトID | `remotetouch_monthly` |

---

## システム要件

### デスクトップ（ホスト）

#### macOS
- macOS 10.15 (Catalina) 以上
- **必要な権限**:
  - アクセシビリティ（キーボード/マウス制御）
  - 画面収録（画面共有）

#### Windows
- Windows 10 64-bit 以上

### モバイル（クライアント）

#### iOS
- iOS 15.0 以上
- カメラ権限（QRコードスキャン）

#### Android
- API 28 (Android 9.0) 以上
- カメラ権限（QRコードスキャン）
- 16KBページサイズ対応

---

## セットアップ

### デスクトップアプリのインストール

#### macOS
1. DMGファイルをダウンロード
2. DMGを開く
3. RemoteTouchをアプリケーションフォルダにドラッグ
4. 初回起動時にアクセシビリティと画面収録の権限を許可

#### Windows
1. EXEインストーラーをダウンロード
2. インストーラーを実行
3. 指示に従ってインストール

### 接続方法

#### QRコード接続（推奨）
1. デスクトップアプリを起動
2. 表示されるQRコードをモバイルアプリでスキャン
3. 接続完了

#### 手動接続（LAN）
1. デスクトップアプリでIPアドレス、ポート、トークンを確認
2. モバイルアプリで「手動接続」を選択
3. IPアドレス、ポート、トークンを入力

#### Cloudflare Tunnel（外部アクセス）
1. デスクトップアプリで「インターネット経由」を選択
2. cloudflaredが自動でインストール・起動
3. 生成されたURLをモバイルアプリに入力

---

## 開発

### 必要なツール
- Node.js 18+
- Rust (stable)
- Flutter 3.x
- Xcode (macOS/iOS)
- Android Studio (Android)

### ビルド方法

#### モバイルアプリ
```bash
cd mobile
flutter pub get

# iOS
flutter build ios --release

# Android
flutter build appbundle --release
```

#### デスクトップアプリ
```bash
cd desktop
npm install

# 開発モード
npm run tauri dev

# リリースビルド
npm run tauri build
```

### GitHub Actions
- Windows/macOSビルドは自動化
- mainブランチへのpushでビルド開始
- アーティファクト: DMG (macOS), EXE (Windows)

---

## バージョン履歴

### v1.5.5 (2024-12)
- Firebase Remote Configによる強制アップデート機能
- H.264エンコーダー改善
- Android 16KBページサイズ対応
- Windows ビルドエラー修正 (`get_cli_tools_fast`)
- mobile_scanner 7.x API対応

### v1.5.4 (2024-12)
- 3カラムレイアウト問題修正
- AppleScriptタイムアウト対応
- 16KBページサイズ設定追加

### v1.5.1 (2024-12)
- Windows対応
- WebRTC画面共有
- 日本語入力改善
- Android SDK 36対応

### v1.0.0 (2024-11)
- 初回リリース
- macOS対応
- 基本的なリモート操作機能

---

## 注目機能

1. **デュアルコーデック**: JPEG（フォールバック）+ H.264（プライマリ）
2. **日本語ファースト**: フルIME対応、日本語入力ハンドリング
3. **低遅延設計**: HTTPではなくWebRTCデータチャネル使用
4. **アクセシビリティ優先**: macOSアクセシビリティAPI活用
5. **Cloudflare統合**: ゼロコンフィグトンネリング
6. **ターミナルエミュレーション**: 完全なPTYセッション
7. **スマート座標マッピング**: マルチスクリーン対応
8. **カスタムショートカット**: ユーザー定義のキーボードショートカット
9. **ジェスチャーサポート**: ピンチ、パン、タップ、ダブルタップ
10. **永続セッション**: PTYとWebRTCセッションの維持

---

## トラブルシューティング

### macOSで操作できない
- システム環境設定 > セキュリティとプライバシー > アクセシビリティ でRemoteTouchを許可

### 画面が表示されない
- システム環境設定 > セキュリティとプライバシー > 画面収録 でRemoteTouchを許可

### 接続できない
- ファイアウォールでポート9876が開いているか確認
- 同一ネットワーク上にいることを確認

### Cloudflare Tunnelが動作しない
- インターネット接続を確認
- cloudflaredが正しくインストールされているか確認

---

## ライセンス

Proprietary - All Rights Reserved

## サポート

問題が発生した場合は、GitHubのIssuesでご報告ください。

---

**RemoteTouch** - Your Mac/Windows, in your pocket.
