import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/websocket_service.dart';
import '../services/localization_service.dart';
import '../services/subscription_service.dart';

class CommandsScreen extends ConsumerStatefulWidget {
  const CommandsScreen({super.key});

  @override
  ConsumerState<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends ConsumerState<CommandsScreen> {
  bool _wasConnected = false; // 一度でも接続成功したかどうか

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webSocketProvider);
    final l10n = ref.watch(l10nProvider);
    final language = ref.watch(languageProvider);

    // 接続成功を記録
    if (state.connectionState == WsConnectionState.connected) {
      _wasConnected = true;
    }

    // 一度接続成功した後に切れた場合のみスキャン画面に戻る
    // （初回ビルド時のレースコンディションを防ぐ）
    if (_wasConnected &&
        (state.connectionState == WsConnectionState.disconnected ||
         state.connectionState == WsConnectionState.error)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(subscriptionProvider.notifier).resetLoadingState();
          context.go('/');
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RemoteTouch'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          // 切断ボタン
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(subscriptionProvider.notifier).resetLoadingState();
              context.go('/');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(webSocketProvider.notifier).disconnect();
              });
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF1a1a2e),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 接続状態
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16213e),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: state.connectionState == WsConnectionState.connected
                            ? Colors.green
                            : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      state.connectionState == WsConnectionState.connected
                          ? l10n.connected
                          : l10n.connecting,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // 言語選択
              Text(
                l10n.selectLanguage,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 日本語
                  GestureDetector(
                    onTap: () {
                      ref.read(languageProvider.notifier).setLanguage(AppLanguage.ja);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: language == AppLanguage.ja
                            ? const Color(0xFFe94560)
                            : const Color(0xFF16213e),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: language == AppLanguage.ja
                              ? const Color(0xFFe94560)
                              : Colors.white24,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🇯🇵', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Text(
                            '日本語',
                            style: TextStyle(
                              color: language == AppLanguage.ja
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 16,
                              fontWeight: language == AppLanguage.ja
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // English
                  GestureDetector(
                    onTap: () {
                      ref.read(languageProvider.notifier).setLanguage(AppLanguage.en);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: language == AppLanguage.en
                            ? const Color(0xFFe94560)
                            : const Color(0xFF16213e),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: language == AppLanguage.en
                              ? const Color(0xFFe94560)
                              : Colors.white24,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🇺🇸', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Text(
                            'English',
                            style: TextStyle(
                              color: language == AppLanguage.en
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 16,
                              fontWeight: language == AppLanguage.en
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              // 画面共有アイコン
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFFe94560).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.screen_share,
                  color: Color(0xFFe94560),
                  size: 80,
                ),
              ),
              const SizedBox(height: 32),
              // 画面共有ボタン
              ElevatedButton.icon(
                onPressed: () => context.push('/screen'),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.startScreenShare),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe94560),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.screenShareDescription,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
