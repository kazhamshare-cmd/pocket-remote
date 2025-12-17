import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/websocket_service.dart';

class CommandsScreen extends ConsumerStatefulWidget {
  const CommandsScreen({super.key});

  @override
  ConsumerState<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends ConsumerState<CommandsScreen> {
  @override
  void initState() {
    super.initState();
    print('[CommandsScreen] initState called');
    // ターミナルタブを取得
    Future.microtask(() {
      ref.read(webSocketProvider.notifier).getTerminalTabs('Terminal');
    });
  }

  @override
  Widget build(BuildContext context) {
    print('[CommandsScreen] build called');
    final state = ref.watch(webSocketProvider);

    // 接続が切れたらスキャン画面に戻る
    if (state.connectionState == WsConnectionState.disconnected ||
        state.connectionState == WsConnectionState.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketRemote'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          // 更新ボタン
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(webSocketProvider.notifier).getTerminalTabs('Terminal');
            },
          ),
          // 切断ボタン
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(webSocketProvider.notifier).disconnect();
              context.go('/');
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF1a1a2e),
        child: Column(
          children: [
            // 接続状態
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
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
                        ? '接続中'
                        : '接続中...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  // ターゲットアプリ表示
                  if (state.targetApp != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFe94560).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFe94560).withOpacity(0.5)),
                      ),
                      child: Text(
                        state.targetApp!,
                        style: const TextStyle(color: Color(0xFFe94560), fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),

            // セクションヘッダー: ターミナル
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'ターミナル',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // 新規ターミナルボタン
                  TextButton.icon(
                    onPressed: _openNewTerminal,
                    icon: const Icon(Icons.add, color: Color(0xFFe94560), size: 18),
                    label: const Text(
                      '新規',
                      style: TextStyle(color: Color(0xFFe94560)),
                    ),
                  ),
                ],
              ),
            ),

            // ターミナルタブリスト
            Expanded(
              child: state.terminalTabs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.terminal, color: Colors.white24, size: 64),
                          const SizedBox(height: 16),
                          const Text(
                            'ターミナルが開いていません',
                            style: TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _openNewTerminal,
                            icon: const Icon(Icons.add),
                            label: const Text('新規ターミナルを開く'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFe94560),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              ref.read(webSocketProvider.notifier).getTerminalTabs('Terminal');
                            },
                            child: const Text(
                              '更新',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.terminalTabs.length,
                      itemBuilder: (context, index) {
                        final tab = state.terminalTabs[index];
                        return Card(
                          color: const Color(0xFF16213e),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: tab.isBusy
                                  ? Colors.orange.withOpacity(0.3)
                                  : const Color(0xFF0a0a14),
                              child: Text(
                                'W${tab.windowIndex}',
                                style: TextStyle(
                                  color: tab.isBusy ? Colors.orange : Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              tab.title.isNotEmpty ? tab.title : 'Tab ${tab.tabIndex}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  'Window ${tab.windowIndex}, Tab ${tab.tabIndex}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                                if (tab.isBusy) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '実行中',
                                      style: TextStyle(color: Colors.orange, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.white38,
                            ),
                            onTap: () {
                              // ターミナルタブをアクティブにして画面共有へ
                              ref.read(webSocketProvider.notifier).activateTerminalTab(
                                'Terminal',
                                tab.windowIndex,
                                tab.tabIndex,
                              );
                              context.go('/screen');
                            },
                          ),
                        );
                      },
                    ),
            ),

            // クイックアクション
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _quickActionButton(
                      icon: Icons.apps,
                      label: 'アプリ',
                      onTap: () => _showAppsSheet(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quickActionButton(
                      icon: Icons.keyboard,
                      label: 'キーボード',
                      onTap: () {
                        context.go('/screen');
                        // 少し遅延してからキーボードダイアログを開く
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // 画面共有ボタン
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/screen'),
        backgroundColor: const Color(0xFFe94560),
        icon: const Icon(Icons.screen_share),
        label: const Text('画面共有'),
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF16213e),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _openNewTerminal() {
    // Spotlightでターミナルを開く
    ref.read(webSocketProvider.notifier).spotlightSearch('Terminal');
    // 少し待ってからタブを更新
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ref.read(webSocketProvider.notifier).getTerminalTabs('Terminal');
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ターミナルを起動中...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showAppsSheet() {
    ref.read(webSocketProvider.notifier).getRunningApps();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(webSocketProvider);
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '起動中のアプリ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white54),
                      onPressed: () {
                        ref.read(webSocketProvider.notifier).getRunningApps();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.runningApps.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: Color(0xFFe94560)),
                    ),
                  )
                else
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      itemCount: state.runningApps.length,
                      itemBuilder: (context, index) {
                        final app = state.runningApps[index];
                        return ListTile(
                          leading: Icon(
                            app.isActive ? Icons.check_circle : Icons.circle_outlined,
                            color: app.isActive ? Colors.green : Colors.white54,
                          ),
                          title: Text(
                            app.name,
                            style: TextStyle(
                              color: app.isActive ? Colors.white : Colors.white70,
                              fontWeight: app.isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            ref.read(webSocketProvider.notifier).focusApp(app.name);
                            Navigator.pop(context);
                            context.go('/screen');
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
