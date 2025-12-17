import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/connection_info.dart';
import '../services/websocket_service.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  MobileScannerController? cameraController;
  bool _isProcessing = false;
  bool _cameraError = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    print('[ScanScreen] initState called');
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    print('[ScanScreen] _initializeCamera started');
    try {
      cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
      print('[ScanScreen] MobileScannerController created');

      // カメラの起動を待つ
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        print('[ScanScreen] Setting _isInitialized = true');
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e, stackTrace) {
      print('[ScanScreen] Camera initialization error: $e');
      print('[ScanScreen] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _cameraError = true;
          _isInitialized = true;
        });
      }
    }
  }

  @override
  void dispose() {
    print('[ScanScreen] dispose called');
    cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _isProcessing = true;
        _processQrCode(barcode.rawValue!);
        break;
      }
    }
  }

  Future<void> _processQrCode(String data) async {
    try {
      final info = ConnectionInfo.fromQrData(data);
      await ref.read(webSocketProvider.notifier).connect(info);

      if (mounted) {
        context.go('/commands');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無効なQRコード: $e')),
        );
        _isProcessing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('[ScanScreen] build called - _isInitialized: $_isInitialized, _cameraError: $_cameraError, cameraController: ${cameraController != null}');
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRコードをスキャン'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ローディングまたはカメラ
          if (!_isInitialized)
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFe94560)),
                    SizedBox(height: 16),
                    Text(
                      'カメラを起動中...',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          else if (_cameraError)
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'カメラを使用できません',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '手動接続を使用してください',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else if (cameraController != null)
            MobileScanner(
              controller: cameraController!,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                print('[ScanScreen] MobileScanner errorBuilder: ${error.errorCode}');
                // エラー時は手動接続を促す
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_cameraError) {
                    setState(() {
                      _cameraError = true;
                    });
                  }
                });
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          'カメラエラー: ${error.errorCode}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: Text(
                  'カメラコントローラー初期化エラー',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          // スキャンフレーム
          if (_isInitialized && !_cameraError)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFe94560), width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Text(
              _cameraError
                  ? '下の「手動で接続」ボタンを押してください'
                  : 'デスクトップアプリのQRコードを\nスキャンしてください',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          // 手動接続ボタン
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: _showManualConnectDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFe94560),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('手動で接続'),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
    );
  }

  void _showManualConnectDialog() {
    final ipController = TextEditingController(text: '192.168.3.72');
    final portController = TextEditingController(text: '9876');
    final tokenController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('手動接続', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'IPアドレス',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            TextField(
              controller: portController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'ポート',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            TextField(
              controller: tokenController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'トークン（QRから）',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final data = '${ipController.text}:${portController.text}:${tokenController.text}';
              _processQrCode(data);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
            child: const Text('接続'),
          ),
        ],
      ),
    );
  }
}
