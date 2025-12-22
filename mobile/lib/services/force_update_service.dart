import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 強制アップデートの状態
enum ForceUpdateStatus {
  checking,
  upToDate,
  updateRequired,
  error,
}

class ForceUpdateState {
  final ForceUpdateStatus status;
  final String? currentVersion;
  final String? minVersion;
  final String? updateMessage;

  const ForceUpdateState({
    this.status = ForceUpdateStatus.checking,
    this.currentVersion,
    this.minVersion,
    this.updateMessage,
  });

  ForceUpdateState copyWith({
    ForceUpdateStatus? status,
    String? currentVersion,
    String? minVersion,
    String? updateMessage,
  }) {
    return ForceUpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      minVersion: minVersion ?? this.minVersion,
      updateMessage: updateMessage ?? this.updateMessage,
    );
  }
}

class ForceUpdateNotifier extends StateNotifier<ForceUpdateState> {
  ForceUpdateNotifier() : super(const ForceUpdateState());

  /// バージョンチェックを実行
  Future<void> checkForUpdate() async {
    try {
      print('[ForceUpdate] Starting version check...');

      // 全体のタイムアウトを設定（5秒）
      await _doCheckForUpdate().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('[ForceUpdate] Timeout - proceeding without update check');
          state = state.copyWith(status: ForceUpdateStatus.upToDate);
        },
      );
    } catch (e) {
      print('[ForceUpdate] Error checking for update: $e');
      // エラー時はアップデート不要として続行（アプリをブロックしない）
      state = state.copyWith(status: ForceUpdateStatus.upToDate);
    }
  }

  Future<void> _doCheckForUpdate() async {
    // アプリの現在バージョンを取得
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    print('[ForceUpdate] Current version: $currentVersion');

    state = state.copyWith(
      status: ForceUpdateStatus.checking,
      currentVersion: currentVersion,
    );

    // Remote Configを初期化して取得
    final remoteConfig = FirebaseRemoteConfig.instance;
    print('[ForceUpdate] Got RemoteConfig instance');

    // デフォルト値を設定
    await remoteConfig.setDefaults({
      'min_version_ios': '1.0.0',
      'min_version_android': '1.0.0',
      'update_message_ja': 'アプリを最新バージョンに更新してください。',
      'update_message_en': 'Please update to the latest version.',
      'force_update_enabled': false,
    });
    print('[ForceUpdate] Defaults set');

    // 設定をフェッチ
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 3),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    print('[ForceUpdate] Config settings applied');

    await remoteConfig.fetchAndActivate();
    print('[ForceUpdate] Fetched and activated');

    // 強制アップデートが有効かチェック
    final forceUpdateEnabled = remoteConfig.getBool('force_update_enabled');
    print('[ForceUpdate] force_update_enabled: $forceUpdateEnabled');

    if (!forceUpdateEnabled) {
      state = state.copyWith(status: ForceUpdateStatus.upToDate);
      return;
    }

    // 最小バージョンを取得
    final minVersion = Platform.isIOS
        ? remoteConfig.getString('min_version_ios')
        : remoteConfig.getString('min_version_android');

    // メッセージを取得（ロケールに基づく）
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final updateMessage = locale.languageCode == 'ja'
        ? remoteConfig.getString('update_message_ja')
        : remoteConfig.getString('update_message_en');

    state = state.copyWith(
      minVersion: minVersion,
      updateMessage: updateMessage,
    );

    // バージョン比較
    if (_isVersionLower(currentVersion, minVersion)) {
      state = state.copyWith(status: ForceUpdateStatus.updateRequired);
    } else {
      state = state.copyWith(status: ForceUpdateStatus.upToDate);
    }
  }

  /// バージョン比較（current < min なら true）
  bool _isVersionLower(String current, String min) {
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final minParts = min.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // パーツ数を揃える
    while (currentParts.length < 3) currentParts.add(0);
    while (minParts.length < 3) minParts.add(0);

    for (int i = 0; i < 3; i++) {
      if (currentParts[i] < minParts[i]) return true;
      if (currentParts[i] > minParts[i]) return false;
    }
    return false; // 同じバージョン
  }

  /// ストアを開く
  Future<void> openStore() async {
    final urlString = Platform.isIOS
        ? 'https://apps.apple.com/app/id6738028857' // あなたのApp Store ID
        : 'https://play.google.com/store/apps/details?id=com.remotetouch.app';
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

final forceUpdateProvider =
    StateNotifierProvider<ForceUpdateNotifier, ForceUpdateState>((ref) {
  return ForceUpdateNotifier();
});

/// 強制アップデートダイアログを表示
Future<void> showForceUpdateDialog(BuildContext context, ForceUpdateState state) async {
  final locale = Localizations.localeOf(context);
  final isJapanese = locale.languageCode == 'ja';

  return showDialog(
    context: context,
    barrierDismissible: false, // ダイアログ外タップで閉じない
    builder: (context) => PopScope(
      canPop: false, // 戻るボタンで閉じない
      child: AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(
          isJapanese ? 'アップデートが必要です' : 'Update Required',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.updateMessage ?? (isJapanese
                  ? 'アプリを最新バージョンに更新してください。'
                  : 'Please update to the latest version.'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Text(
              isJapanese
                  ? '現在のバージョン: ${state.currentVersion}'
                  : 'Current version: ${state.currentVersion}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              isJapanese
                  ? '必要なバージョン: ${state.minVersion}'
                  : 'Required version: ${state.minVersion}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              // ストアを開く
              final notifier = ForceUpdateNotifier();
              notifier.openStore();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFe94560),
            ),
            child: Text(
              isJapanese ? 'アップデート' : 'Update',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}
