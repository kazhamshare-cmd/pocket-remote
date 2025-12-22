class ConnectionInfo {
  final String ip;
  final int port;
  final String token;
  final bool isExternal; // 外部接続（Cloudflare Tunnel）かどうか
  final String? externalUrl; // 外部接続時のURL

  ConnectionInfo({
    required this.ip,
    required this.port,
    required this.token,
    this.isExternal = false,
    this.externalUrl,
  });

  factory ConnectionInfo.fromQrData(String data) {
    // 外部接続（wss://で始まる場合）
    if (data.startsWith('wss://')) {
      // 形式: wss://xxxx.trycloudflare.com:token
      final colonIndex = data.lastIndexOf(':');
      if (colonIndex == -1 || colonIndex <= 6) {
        throw FormatException('Invalid external connection format');
      }
      final url = data.substring(0, colonIndex);
      final token = data.substring(colonIndex + 1);

      // URLからホスト名を抽出
      final host = url.replaceFirst('wss://', '');

      return ConnectionInfo(
        ip: host,
        port: 443, // wssはデフォルトで443
        token: token,
        isExternal: true,
        externalUrl: url,
      );
    }

    // ローカル接続
    // 形式: ip:port:token
    final parts = data.split(':');
    if (parts.length < 3) {
      throw FormatException('Invalid QR code format');
    }
    final port = int.tryParse(parts[1]);
    if (port == null) {
      throw FormatException('Invalid port number: ${parts[1]}');
    }
    return ConnectionInfo(
      ip: parts[0],
      port: port,
      token: parts.sublist(2).join(':'),
    );
  }

  String get wsUrl => isExternal ? (externalUrl ?? 'wss://$ip') : 'ws://$ip:$port';

  String get displayUrl => isExternal ? (externalUrl ?? ip) : '$ip:$port';
}
