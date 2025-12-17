import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/connection_info.dart';
import '../services/websocket_service.dart';
import '../services/localization_service.dart';

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
    final l10n = ref.read(l10nProvider);
    try {
      final info = ConnectionInfo.fromQrData(data);
      await ref.read(webSocketProvider.notifier).connect(info);

      if (mounted) {
        context.go('/commands');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.connectionFailed}: $e')),
        );
        _isProcessing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    print('[ScanScreen] build called - _isInitialized: $_isInitialized, _cameraError: $_cameraError, cameraController: ${cameraController != null}');
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanQRCode),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ローディングまたはカメラ
          if (!_isInitialized)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFe94560)),
                    const SizedBox(height: 16),
                    Text(
                      l10n.connecting,
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          else if (_cameraError)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      l10n.cameraPermissionRequired,
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
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
                          '${l10n.connectionFailed}: ${error.errorCode}',
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
              child: Center(
                child: Text(
                  l10n.connectionFailed,
                  style: const TextStyle(color: Colors.white54),
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
            left: 20,
            right: 20,
            child: Text(
              _cameraError
                  ? l10n.manualConnection
                  : l10n.scanQRCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
              child: Text(l10n.manualConnection),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
    );
  }

  void _showManualConnectDialog() {
    final l10n = ref.read(l10nProvider);
    final hostController = TextEditingController(text: '192.168.3.72');
    final portController = TextEditingController(text: '9876');
    final tokenController = TextEditingController();
    bool isExternal = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: Text(l10n.manualConnection, style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 接続タイプ切り替え
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          isExternal = false;
                          hostController.text = '192.168.3.72';
                          portController.text = '9876';
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !isExternal ? const Color(0xFFe94560) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFe94560)),
                          ),
                          child: Text(
                            l10n.localConnection,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: !isExternal ? Colors.white : Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          isExternal = true;
                          hostController.text = '';
                          portController.text = '443';
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isExternal ? const Color(0xFFe94560) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFe94560)),
                          ),
                          child: Text(
                            l10n.externalConnection,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isExternal ? Colors.white : Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: hostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: isExternal ? '${l10n.hostname} (xxx.trycloudflare.com)' : l10n.ipAddress,
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: isExternal ? 'xxx.trycloudflare.com' : '192.168.x.x',
                    hintStyle: const TextStyle(color: Colors.white24),
                  ),
                ),
                if (!isExternal)
                  TextField(
                    controller: portController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: l10n.port,
                      labelStyle: const TextStyle(color: Colors.white54),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                TextField(
                  controller: tokenController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.token,
                    labelStyle: const TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                String data;
                if (isExternal) {
                  // 外部接続: wss://hostname:token 形式
                  data = 'wss://${hostController.text}:${tokenController.text}';
                } else {
                  // ローカル接続: ip:port:token 形式
                  data = '${hostController.text}:${portController.text}:${tokenController.text}';
                }
                _processQrCode(data);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
              child: Text(l10n.connect),
            ),
          ],
        ),
      ),
    );
  }
}
