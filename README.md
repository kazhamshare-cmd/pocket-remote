# RemoteTouch

iPhoneからMac/Windows PCをリモート操作するアプリ

## 機能

- **画面共有**: WebRTCによる低遅延画面共有
- **キーボード入力**: 日本語入力対応（クリップボード経由）
- **マウス操作**: タップ、スワイプ、ピンチでマウス操作
- **アプリ切り替え**: 実行中のアプリ一覧から選択

## ダウンロード

- [macOS (Apple Silicon)](https://github.com/kazhamshare-cmd/pocket-remote/releases/download/v1.0.0/RemoteTouch_1.0.0_aarch64.dmg)
- [Windows (64-bit)](https://github.com/kazhamshare-cmd/pocket-remote/releases/download/v1.0.0/RemoteTouch_1.0.0_x64-setup.exe)
- iOS: App Store (準備中)
- Android: Google Play (準備中)

## 使い方

1. デスクトップアプリをインストールして起動
2. 表示されるQRコードをモバイルアプリでスキャン
3. 接続完了！iPhoneからPCを操作できます

## 技術スタック

### デスクトップ (Tauri + Rust)
- Tauri 2.0
- WebRTC (webrtc-rs)
- scrap (画面キャプチャ)
- enigo (キーボード/マウス操作)

### モバイル (Flutter)
- Flutter 3.x
- flutter_webrtc
- Riverpod (状態管理)

## 開発

### デスクトップ

```bash
cd desktop
npm install
npm run tauri dev
```

### モバイル

```bash
cd mobile
flutter pub get
flutter run
```

## ビルド

### macOS

```bash
cd desktop
npm run tauri build
```

### Windows

GitHub Actionsで自動ビルド（mainブランチへのpush時）

### Android

```bash
cd mobile
flutter build appbundle --release
```

### iOS

```bash
cd mobile
flutter build ios --release
```

## ライセンス

Private

## バージョン履歴

### v1.5.1 (2024-12)
- Windows対応
- WebRTC画面共有
- 日本語入力改善
- Android SDK 36対応
