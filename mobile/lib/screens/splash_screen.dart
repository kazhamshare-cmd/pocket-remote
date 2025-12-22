import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/force_update_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    print('[SplashScreen] initState called');
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    // バージョンチェックを実行
    _checkVersionAndProceed();
  }

  Future<void> _checkVersionAndProceed() async {
    // バージョンチェック
    await ref.read(forceUpdateProvider.notifier).checkForUpdate();

    // 少し待ってからチェック（スプラッシュを見せる時間）
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    final state = ref.read(forceUpdateProvider);

    if (state.status == ForceUpdateStatus.updateRequired) {
      // アップデートが必要な場合はダイアログを表示
      await showForceUpdateDialog(context, state);
      // ダイアログは閉じられないので、ここには到達しない
    } else {
      // アップデート不要なら続行
      _proceedToApp();
    }
  }

  void _proceedToApp() {
    if (!_completed && mounted) {
      _completed = true;
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    print('[SplashScreen] dispose called');
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('[SplashScreen] build called');
    return Scaffold(
      backgroundColor: Colors.white, // 白背景（ネイティブスプラッシュと統一）
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.all(48.0),
            child: Image.asset(
              'assets/splash.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
