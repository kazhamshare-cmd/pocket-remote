import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';

/// ANSIエスケープシーケンスを除去する正規表現
final _ansiRegex = RegExp(
  r'\x1B\[[0-9;?]*[a-zA-Z]'  // CSI sequences: ESC [ ... letter (including ? for private modes like ?2004h)
  r'|\x1B\][^\x07]*\x07'     // OSC sequences: ESC ] ... BEL
  r'|\x1B\][^\x1B]*\x1B\\'   // OSC sequences: ESC ] ... ESC \
  r'|\x1B[PX^_][^\x1B]*\x1B\\' // DCS, SOS, PM, APC
  r'|\x1B.'                   // Other ESC sequences
  r'|\x07'                    // BEL
  r'|\r'                      // Carriage return (改行のみ残す)
);

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final StringBuffer _outputBuffer = StringBuffer();
  StreamSubscription<String>? _ptySubscription;
  bool _ptyStarted = false;

  @override
  void initState() {
    super.initState();
    _startPtySession();
  }

  void _startPtySession() {
    final notifier = ref.read(webSocketProvider.notifier);

    // PTY出力ストリームを購読（ANSIエスケープシーケンスを除去）
    _ptySubscription = notifier.ptyOutputStream.listen((output) {
      // ANSIエスケープシーケンスを除去
      final cleanOutput = output.replaceAll(_ansiRegex, '');
      if (cleanOutput.isNotEmpty) {
        setState(() {
          _outputBuffer.write(cleanOutput);
        });
        _scrollToBottom();
      }
    });

    // PTYセッションを開始
    notifier.startPty();
    _ptyStarted = true;
  }

  @override
  void dispose() {
    _ptySubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendInput() {
    final input = _inputController.text;
    if (input.isEmpty) {
      // 空でもEnterを送信（コマンド実行のため）
      ref.read(webSocketProvider.notifier).sendPtyInput('\n');
    } else {
      // 入力 + 改行を送信
      ref.read(webSocketProvider.notifier).sendPtyInput('$input\n');
      _inputController.clear();
    }
    _focusNode.requestFocus();
  }

  void _clearScreen() {
    setState(() {
      _outputBuffer.clear();
    });
    // clearコマンドも送信
    ref.read(webSocketProvider.notifier).sendPtyInput('clear\n');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webSocketProvider);
    final isConnected = state.isConnected;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(
              _ptyStarted ? Icons.terminal : Icons.terminal_outlined,
              color: _ptyStarted ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            const Text(
              'Terminal (PTY)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          // Ctrl+C送信
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Send Ctrl+C',
            onPressed: () {
              ref.read(webSocketProvider.notifier).sendPtyInput('\x03');
              HapticFeedback.lightImpact();
            },
          ),
          // クリア
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _clearScreen,
          ),
        ],
      ),
      body: Column(
        children: [
          // 出力エリア（スクロール可能）
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _outputBuffer.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 入力エリア
          Container(
            color: const Color(0xFF2D2D2D),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  '> ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    color: Colors.green.shade400,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    enabled: isConnected && _ptyStarted,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: _ptyStarted
                          ? 'Enter command...'
                          : 'Starting PTY session...',
                      hintStyle: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.grey.shade600,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _sendInput(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.send,
                    color: isConnected && _ptyStarted ? Colors.green : Colors.grey,
                  ),
                  onPressed: isConnected && _ptyStarted ? _sendInput : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
