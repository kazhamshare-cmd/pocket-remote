import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/connection_info.dart';
import '../services/websocket_service.dart';
import '../services/localization_service.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  late final MobileScannerController cameraController;
  bool _isProcessing = false;
  bool _cameraError = false;

  @override
  void initState() {
    super.initState();
    print('[ScanScreen] initState called');
    // mobile_scanner 7.x: コントローラーを作成（ウィジェットにアタッチされたら自動起動）
    cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    print('[ScanScreen] MobileScannerController created');
  }

  /// カメラを再起動
  Future<void> _retryCamera() async {
    print('[ScanScreen] Retrying camera');
    setState(() {
      _cameraError = false;
    });
    try {
      await cameraController.start();
    } catch (e) {
      print('[ScanScreen] Camera retry error: $e');
      if (mounted) {
        setState(() {
          _cameraError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    print('[ScanScreen] dispose called');
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    print('[ScanScreen] _onDetect called, _isProcessing=$_isProcessing');
    if (_isProcessing) {
      print('[ScanScreen] Already processing, ignoring');
      return;
    }

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _isProcessing = true;
        // 2重検出を防ぐためカメラを停止
        print('[ScanScreen] QR detected, stopping camera...');
        cameraController.stop();
        print('[ScanScreen] Camera stopped, calling _processQrCode');
        _processQrCode(barcode.rawValue!);
        break;
      }
    }
  }

  Future<void> _processQrCode(String data) async {
    final l10n = ref.read(l10nProvider);
    print('[ScanScreen] _processQrCode started, data=$data');

    // 既に接続処理中の場合はスキップ
    final currentState = ref.read(webSocketProvider);
    print('[ScanScreen] Current connection state: ${currentState.connectionState}');
    if (currentState.connectionState == WsConnectionState.connecting) {
      print('[ScanScreen] Already connecting, skipping...');
      return;
    }

    try {
      final info = ConnectionInfo.fromQrData(data);
      print('[ScanScreen] Parsed connection info, wsUrl=${info.wsUrl}');
      print('[ScanScreen] Calling connect()...');
      await ref.read(webSocketProvider.notifier).connect(info);
      print('[ScanScreen] connect() returned');

      // 接続結果を待つ（最大15秒 - デスクトップでの承認時間を考慮）
      print('[ScanScreen] Waiting for connection result...');
      final startTime = DateTime.now();
      for (int i = 0; i < 150 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final state = ref.read(webSocketProvider);
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (i % 10 == 0) {
          print('[ScanScreen] Loop $i (${elapsed}ms): connectionState=${state.connectionState}');
        }
        if (state.connectionState == WsConnectionState.connected) {
          print('[ScanScreen] Connected! (after ${elapsed}ms) Navigating to commands...');
          context.push('/commands');
          return;
        } else if (state.connectionState == WsConnectionState.error) {
          print('[ScanScreen] Error (after ${elapsed}ms): ${state.errorMessage}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? l10n.connectionFailed),
              duration: const Duration(seconds: 3),
            ),
          );
          _restartCameraAfterFailure();
          return;
        } else if (state.connectionState == WsConnectionState.disconnected) {
          // connecting状態からdisconnectedに変わった場合のみエラー扱い
          // （初期状態のdisconnectedは無視）
          if (i > 0) {
            print('[ScanScreen] Disconnected (after ${elapsed}ms)');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${l10n.connectionFailed}: 接続が切断されました'),
                duration: const Duration(seconds: 3),
              ),
            );
            _restartCameraAfterFailure();
            return;
          }
        }
      }
      // タイムアウト
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.connectionFailed}: タイムアウト')),
        );
        _restartCameraAfterFailure();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.connectionFailed}: $e')),
        );
        _restartCameraAfterFailure();
      }
    }
  }

  /// 接続失敗後にカメラを再開
  void _restartCameraAfterFailure() {
    _isProcessing = false;
    if (mounted) {
      print('[ScanScreen] Restarting camera after failure');
      cameraController.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    print('[ScanScreen] build called - _cameraError: $_cameraError');
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QRコードをスキャン', style: TextStyle(fontSize: 16)),
            Text('Scan QR Code', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsSheet(context, l10n),
          ),
        ],
      ),
      body: Stack(
        children: [
          // カメラエラー時
          if (_cameraError)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'カメラ許可が必要です\nCamera permission required',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _retryCamera,
                      icon: const Icon(Icons.refresh),
                      label: const Text('再試行 / Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe94560),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            MobileScanner(
              controller: cameraController,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
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
            ),
          // スキャンフレーム
          if (!_cameraError)
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
                  ? '手動接続を使用\nUse manual connection'
                  : 'PCのQRコードをスキャン\nScan QR code on your PC',
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
              child: const Text('手動接続 / Manual Connection'),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
    );
  }

  void _showManualConnectDialog() {
    final l10n = ref.read(l10nProvider);
    final hostController = TextEditingController();
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
                          hostController.text = '';
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

  // 設定メニューを表示
  void _showSettingsSheet(BuildContext context, L10n l10n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // サブスク管理
              ListTile(
                leading: const Icon(Icons.subscriptions, color: Color(0xFFe94560)),
                title: Text(l10n.manageSubscription, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _openSubscriptionManagement();
                },
              ),
              const Divider(color: Colors.white24),
              // 利用規約
              ListTile(
                leading: const Icon(Icons.description, color: Colors.white70),
                title: Text(l10n.termsOfUse, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showTermsDialog(context, l10n);
                },
              ),
              // プライバシーポリシー
              ListTile(
                leading: const Icon(Icons.privacy_tip, color: Colors.white70),
                title: Text(l10n.privacyPolicy, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showPrivacyDialog(context, l10n);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // サブスク管理を開く
  Future<void> _openSubscriptionManagement() async {
    final urlString = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // 利用規約ダイアログ
  void _showTermsDialog(BuildContext context, L10n l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.termsOfUse, style: const TextStyle(color: Colors.white)),
        content: const SingleChildScrollView(
          child: Text(
            'RemoteTouch Monthly Subscription\n\n'
            '- Payment will be charged to your Apple ID account at confirmation of purchase.\n'
            '- Subscription automatically renews unless canceled at least 24 hours before the end of the current period.\n'
            '- Your account will be charged for renewal within 24 hours prior to the end of the current period.\n'
            '- You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase.\n'
            '- Any unused portion of a free trial period will be forfeited when you purchase a subscription.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close, style: const TextStyle(color: Color(0xFFe94560))),
          ),
        ],
      ),
    );
  }

  // プライバシーポリシーダイアログ
  void _showPrivacyDialog(BuildContext context, L10n l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.privacyPolicy, style: const TextStyle(color: Colors.white)),
        content: const SingleChildScrollView(
          child: Text(
            'RemoteTouch Privacy Policy\n\n'
            'We respect your privacy. RemoteTouch:\n\n'
            '- Does not collect personal data\n'
            '- Does not share your information with third parties\n'
            '- Only communicates directly with your desktop app\n'
            '- Uses secure encrypted connections\n\n'
            'For questions, please contact us through our inquiry form.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close, style: const TextStyle(color: Color(0xFFe94560))),
          ),
        ],
      ),
    );
  }
}
