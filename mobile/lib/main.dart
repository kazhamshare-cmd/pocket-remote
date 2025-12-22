import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/scan_screen.dart';
import 'screens/commands_screen.dart';
import 'screens/screen_share_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/splash_screen.dart';

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) {
        print('[Router] Building SplashScreen');
        return SplashScreen(
          onComplete: () {
            context.go('/');
          },
        );
      },
    ),
    GoRoute(
      path: '/',
      builder: (context, state) {
        print('[Router] Building PaywallScreen');
        return const PaywallScreen();
      },
    ),
    GoRoute(
      path: '/scan',
      builder: (context, state) {
        print('[Router] Building ScanScreen');
        return const ScanScreen();
      },
    ),
    GoRoute(
      path: '/commands',
      builder: (context, state) {
        print('[Router] Building CommandsScreen');
        return const CommandsScreen();
      },
    ),
    GoRoute(
      path: '/screen',
      builder: (context, state) {
        print('[Router] Building ScreenShareScreen');
        return const ScreenShareScreen();
      },
    ),
    GoRoute(
      path: '/terminal',
      builder: (context, state) {
        print('[Router] Building TerminalScreen');
        return const TerminalScreen();
      },
    ),
  ],
);

void main() async {
  print('[Main] App starting...');
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase を初期化
  try {
    await Firebase.initializeApp();
    print('[Main] Firebase initialized');
  } catch (e) {
    print('[Main] Firebase initialization error: $e');
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    print('[MyApp] build called');
    return MaterialApp.router(
      title: 'RemoteTouch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFe94560),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
      ),
      routerConfig: _router,
    );
  }
}
