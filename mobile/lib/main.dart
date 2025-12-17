import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/scan_screen.dart';
import 'screens/commands_screen.dart';
import 'screens/screen_share_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
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
  ],
);

void main() {
  print('[Main] App starting...');
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('[MyApp] build called');
    return MaterialApp.router(
      title: 'PocketRemote',
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
