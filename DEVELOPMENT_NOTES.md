# RemoteTouch 開発ノート

## アプリ概要

RemoteTouchは、スマートフォンからPCをリモート操作するためのアプリケーションです。

### 構成

- **mobile/** - Flutter製モバイルアプリ（iOS/Android）
- **desktop/** - Tauri + Rust製デスクトップアプリ（Mac/Windows）

### 主な機能

1. **画面共有** - PCの画面をスマホでリアルタイム表示（WebRTC使用）
2. **マウス操作** - タップでクリック、ドラッグ操作
3. **キーボード入力** - スマホからPCへテキスト入力
4. **アプリ選択** - 実行中のアプリを選択して、そのウィンドウを3倍ズームで表示
5. **QRコード接続** - QRコードスキャンで簡単接続

---

## 現在の作業内容（2024/12/20）

### 課題：座標のズレとUI改善

#### 1. ヘッダーとコンテンツの分離
- **問題**: ヘッダー（←ボタン、画面サイズ表示）が画面コンテンツと重なっていた
- **解決**: `Stack`から`Column`レイアウトに変更し、ヘッダーを独立したContainerに配置

```dart
// 変更前: Stack内にすべて配置
Stack(
  children: [
    // 画面表示
    // ヘッダー（Positioned）
    // ツールバー（Positioned）
  ],
)

// 変更後: Columnで分離
Column(
  children: [
    // ヘッダー（独立したContainer）
    Container(...SafeArea...),
    // 画面表示エリア
    Expanded(
      child: Stack(
        children: [
          // 画面表示
          // ツールバー（Positioned）
        ],
      ),
    ),
  ],
)
```

#### 2. 座標計算の修正
- **問題**: ヘッダー分離後、座標計算に不要な`topPadding`が残っていた
- **解決**: `_screenToRemoteCoordinates`から`topPadding`調整を削除

```dart
// 変更前
const topPadding = 80.0;
final adjustedPos = Offset(screenPos.dx, screenPos.dy - topPadding);

// 変更後
// ヘッダーは別のContainerにあるため、調整不要
final contentPos = _getTransformedPosition(screenPos);
```

#### 3. InteractiveViewerの設定改善
- `boundaryMargin: EdgeInsets.all(double.infinity)` - 無制限パン許可
- `constrained: false` - 子要素を制約しない
- `ClipRect`でラップ - はみ出し部分をクリップ

#### 4. ズームタイミングの修正
- **問題**: `_zoomToWindow`でトランスフォーム設定が早すぎた
- **解決**: `WidgetsBinding.instance.addPostFrameCallback`でウィジェット再構築後に適用

```dart
void _zoomToWindow(...) {
  setState(() {
    _focusedWindow = windowInfo;
  });

  // ウィジェット再構築後に3倍ズームを適用
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _transformController.value = Matrix4.identity()..scale(_fixedZoom);
  });
}
```

---

## 変更ファイル

### `/mobile/lib/screens/screen_share_screen.dart`

主な変更箇所:
- L329-390: `_screenToRemoteCoordinates` - 座標変換（topPadding削除）
- L502-523: `_zoomToWindow` - ズーム適用タイミング修正
- L549-916: `build` - レイアウト構造変更（Column + Expanded + Stack）
- L715-744: InteractiveViewer設定改善

---

## 既知の問題・未解決

1. **座標ズレ** - アプリ選択時の座標計算がまだ正確でない可能性
   - デバッグログで確認が必要
   - `[Coords-Focused]`ログでtransform値、window座標、計算結果を出力

2. **iOS実機インストール** - flutter runがタイムアウトすることがある
   - Xcodeから直接Runで解決

3. **画像サイズ** - アプリ選択時の画像サイズが期待通りでない場合がある

---

## デバッグ方法

### 座標ログの確認
```bash
flutter run -d [device_id]
# コンソールで以下のログを確認
# [Coords-Focused] screenPos=..., contentPos=...
# [Coords-Focused] window: x,y widthxheight
# [Coords-Focused] rel=..., PC=...
# [Coords-Focused] transform: Matrix4(...)
```

### ビルドコマンド
```bash
# iOS
cd mobile
flutter build ios --debug
flutter run -d [device_id]

# Android
flutter build apk --debug
flutter run -d [device_id]
```

---

## 次のステップ

1. 座標計算の検証とデバッグ
2. 3倍ズーム時の画像表示サイズの確認
3. パン操作後の座標計算の確認
4. テスト完了後、本番ビルドの作成

---

## 参考

- Flutter InteractiveViewer: https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html
- Matrix4変換: https://api.flutter.dev/flutter/vector_math_64/Matrix4-class.html
