import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    print('[SplashScreen] initState called');
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      print('[SplashScreen] Timer completed, calling onComplete');
      if (!_completed && mounted) {
        _completed = true;
        widget.onComplete();
      }
    });
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
      backgroundColor: const Color(0xFF1a1a2e),
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
