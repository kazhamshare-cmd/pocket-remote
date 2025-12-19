import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

interface ConnectionInfo {
  ip: string;
  port: number;
  qr_code: string;
  auth_token: string;
}

interface TunnelInfo {
  url: string;
  qr_code: string;
}

interface CloudflaredStatus {
  installed: boolean;
  is_system: boolean;
  is_local: boolean;
  path: string | null;
}

interface ConnectionRequest {
  request_id: string;
  device_name: string;
  ip_address: string;
}

// 通知音を鳴らす関数（ピンポン音）
function playNotificationSound() {
  try {
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();

    // 最初の音（ピン）
    const osc1 = audioContext.createOscillator();
    const gain1 = audioContext.createGain();
    osc1.connect(gain1);
    gain1.connect(audioContext.destination);
    osc1.frequency.value = 880; // A5
    osc1.type = 'sine';
    gain1.gain.setValueAtTime(0.5, audioContext.currentTime);
    gain1.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.2);
    osc1.start(audioContext.currentTime);
    osc1.stop(audioContext.currentTime + 0.2);

    // 2番目の音（ポン）
    const osc2 = audioContext.createOscillator();
    const gain2 = audioContext.createGain();
    osc2.connect(gain2);
    gain2.connect(audioContext.destination);
    osc2.frequency.value = 1100; // C#6
    osc2.type = 'sine';
    gain2.gain.setValueAtTime(0.5, audioContext.currentTime + 0.2);
    gain2.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.4);
    osc2.start(audioContext.currentTime + 0.2);
    osc2.stop(audioContext.currentTime + 0.4);

    console.log('[Audio] Notification sound played');
  } catch (e) {
    console.error('[Audio] Failed to play notification sound:', e);
  }
}

function App() {
  const [connectionInfo, setConnectionInfo] = useState<ConnectionInfo | null>(null);
  const [connected, setConnected] = useState(false);
  const [connectedDevice, setConnectedDevice] = useState<string | null>(null);
  const [accessibilityGranted, setAccessibilityGranted] = useState<boolean | null>(null);
  const [checkingPermission, setCheckingPermission] = useState(true);

  // トンネル関連
  const [cloudflaredStatus, setCloudflaredStatus] = useState<CloudflaredStatus | null>(null);
  const [tunnelInfo, setTunnelInfo] = useState<TunnelInfo | null>(null);
  const [tunnelStarting, setTunnelStarting] = useState(false);
  const [showExternalQR, setShowExternalQR] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [installProgress, setInstallProgress] = useState<string | null>(null);

  // 接続リクエスト（承認待ち）
  const [pendingRequest, setPendingRequest] = useState<ConnectionRequest | null>(null);

  useEffect(() => {
    // アクセシビリティ権限をチェック（プロンプトは表示しない）
    const checkPermissions = async () => {
      try {
        const granted = await invoke<boolean>("check_accessibility");
        setAccessibilityGranted(granted);
        // 自動でプロンプトを表示しない（ユーザーが手動で設定する）
      } catch (e) {
        console.error("Failed to check accessibility:", e);
        setAccessibilityGranted(true); // エラー時はスキップ
      } finally {
        setCheckingPermission(false);
      }
    };
    checkPermissions();

    // cloudflaredがインストールされているかチェック
    const checkCloudflared = async () => {
      try {
        const status = await invoke<CloudflaredStatus>("get_cloudflared_status");
        setCloudflaredStatus(status);
      } catch (e) {
        console.error("Failed to check cloudflared:", e);
        setCloudflaredStatus({ installed: false, is_system: false, is_local: false, path: null });
      }
    };
    checkCloudflared();

    // トンネル開始イベントをリッスン
    const unlistenTunnel = listen<TunnelInfo>("tunnel_started", (event) => {
      console.log("Tunnel started:", event.payload);
      setTunnelInfo(event.payload);
      setTunnelStarting(false);
      setShowExternalQR(true);
    });

    // インストール進捗をリッスン
    const unlistenProgress = listen<string>("cloudflared_install_progress", (event) => {
      console.log("Install progress:", event.payload);
      setInstallProgress(event.payload);
    });

    // 接続リクエストをリッスン
    const unlistenConnectionRequest = listen<ConnectionRequest>("connection_request", (event) => {
      console.log("===== CONNECTION REQUEST RECEIVED =====");
      console.log("Event payload:", event.payload);
      console.log("Setting pendingRequest...");
      setPendingRequest(event.payload);
      // 通知音を鳴らす
      playNotificationSound();
    });
    console.log("Connection request listener registered");

    return () => {
      unlistenTunnel.then(fn => fn());
      unlistenProgress.then(fn => fn());
      unlistenConnectionRequest.then(fn => fn());
    };
  }, []);

  // 接続状態の監視
  useEffect(() => {
    const interval = setInterval(async () => {
      try {
        // 接続情報がまだない場合は取得を試みる
        if (!connectionInfo) {
          const info = await invoke<ConnectionInfo | null>("get_connection_info");
          if (info) {
            setConnectionInfo(info);
          }
        }

        const status = await invoke<{ connected: boolean; device: string | null }>("get_connection_status");
        setConnected(status.connected);
        setConnectedDevice(status.device);

        // アクセシビリティ権限を定期的に再チェック
        if (!accessibilityGranted) {
          const granted = await invoke<boolean>("check_accessibility");
          if (granted) {
            setAccessibilityGranted(true);
          }
        }

        // トンネル情報をポーリングで取得（イベントが届かない場合のフォールバック）
        if (tunnelStarting && !tunnelInfo) {
          const info = await invoke<TunnelInfo | null>("get_tunnel_info");
          if (info) {
            console.log("Tunnel info received via polling:", info);
            setTunnelInfo(info);
            setTunnelStarting(false);
            setShowExternalQR(true);
          }
        }

        // 保留中の接続リクエストをポーリングで取得
        const request = await invoke<ConnectionRequest | null>("get_pending_request");
        if (request && !pendingRequest) {
          console.log("Pending request found:", request);
          setPendingRequest(request);
          // 通知音を鳴らす
          playNotificationSound();
        }
      } catch (e) {
        console.error(e);
      }
    }, 500); // 500msでポーリング（より素早く検出）

    return () => clearInterval(interval);
  }, [accessibilityGranted, connectionInfo, tunnelStarting, tunnelInfo]);

  const handleOpenSettings = async () => {
    await invoke("open_accessibility_settings");
  };

  const handleRetryPermission = async () => {
    const granted = await invoke<boolean>("check_accessibility");
    setAccessibilityGranted(granted);
  };

  const handleStartTunnel = async () => {
    setTunnelStarting(true);
    try {
      await invoke("start_tunnel");
    } catch (e) {
      console.error("Failed to start tunnel:", e);
      setTunnelStarting(false);
    }
  };

  const handleStopTunnel = async () => {
    try {
      await invoke("stop_tunnel");
      setTunnelInfo(null);
      setShowExternalQR(false);
    } catch (e) {
      console.error("Failed to stop tunnel:", e);
    }
  };

  const handleInstallCloudflared = async () => {
    setInstalling(true);
    setInstallProgress("Preparing...");
    try {
      await invoke("install_cloudflared");
      // インストール完了後、ステータスを再チェック
      const status = await invoke<CloudflaredStatus>("get_cloudflared_status");
      setCloudflaredStatus(status);
      setInstallProgress(null);
    } catch (e) {
      console.error("Failed to install cloudflared:", e);
      setInstallProgress(`Error: ${e}`);
    } finally {
      setInstalling(false);
    }
  };

  const handleConnectionResponse = async (approved: boolean) => {
    if (!pendingRequest) return;
    try {
      await invoke("respond_to_connection", {
        requestId: pendingRequest.request_id,
        approved,
      });
    } catch (e) {
      console.error("Failed to respond to connection:", e);
    } finally {
      setPendingRequest(null);
    }
  };

  return (
    <div className="container">
      <h1>RemoteTouch</h1>

      {/* 接続確認ダイアログ / Connection Dialog */}
      {pendingRequest && (
        <div className="connection-dialog-overlay">
          <div className="connection-dialog">
            <div className="dialog-icon">📱</div>
            <h3>Connection Request</h3>
            <p className="device-name">{pendingRequest.device_name}</p>
            <p className="device-ip">IP: {pendingRequest.ip_address}</p>
            <p className="dialog-message">Allow connection from this device?</p>
            <div className="dialog-buttons">
              <button
                className="approve-button"
                onClick={() => handleConnectionResponse(true)}
              >
                ✓ Allow
              </button>
              <button
                className="deny-button"
                onClick={() => handleConnectionResponse(false)}
              >
                ✕ Deny
              </button>
            </div>
            <p className="dialog-timeout">Auto-denied after 30 seconds</p>
          </div>
        </div>
      )}

      {/* アクセシビリティ権限の警告 / Accessibility Permission Warning */}
      {!checkingPermission && accessibilityGranted === false && (
        <div className="permission-warning">
          <div className="warning-icon">⚠️</div>
          <h3>Accessibility Permission Required</h3>
          <p>
            Keyboard and mouse control requires accessibility permission.
            Please enable it in System Settings.
          </p>
          <div className="permission-buttons">
            <button className="primary-button" onClick={handleOpenSettings}>
              Open System Settings
            </button>
            <button className="secondary-button" onClick={handleRetryPermission}>
              Recheck
            </button>
          </div>
          <div className="permission-steps">
            <p><strong>Steps:</strong></p>
            <ol>
              <li>System Settings → Privacy & Security</li>
              <li>Select "Accessibility"</li>
              <li>Enable "RemoteTouch" or "Terminal"</li>
            </ol>
          </div>
        </div>
      )}

      <div className="status-card">
        <div className={`status-indicator ${connected ? "connected" : "waiting"}`} />
        <span>{connected ? `Connected: ${connectedDevice}` : "Waiting for connection..."}</span>
        {accessibilityGranted && (
          <span className="permission-badge granted">✓ Permission OK</span>
        )}
      </div>

      {connectionInfo && (
        <div className="qr-section">
          <h2>Scan QR Code to Connect</h2>

          {/* ローカル/外部切り替えタブ / Local/External Tabs */}
          <div className="connection-tabs">
            <button
              className={`tab-button ${!showExternalQR ? 'active' : ''}`}
              onClick={() => setShowExternalQR(false)}
            >
              🏠 Local
            </button>
            <button
              className={`tab-button ${showExternalQR ? 'active' : ''}`}
              onClick={() => setShowExternalQR(true)}
            >
              🌐 External
            </button>
          </div>

          {/* ローカル接続QR / Local Connection QR */}
          {!showExternalQR && (
            <>
              <div className="qr-placeholder" id="qr-code">
                <img src={`data:image/png;base64,${connectionInfo.qr_code}`} alt="QR Code" />
              </div>
              <p className="connection-note">Connect within same WiFi/network</p>
              <div className="manual-connection-info">
                <p className="manual-title">Manual Connection:</p>
                <div className="manual-field">
                  <span className="field-label">IP Address:</span>
                  <code className="field-value">{connectionInfo.ip}</code>
                </div>
                <div className="manual-field">
                  <span className="field-label">Port:</span>
                  <code className="field-value">{connectionInfo.port}</code>
                </div>
                <div className="manual-field">
                  <span className="field-label">Token:</span>
                  <code className="field-value token">{connectionInfo.auth_token}</code>
                </div>
              </div>
            </>
          )}

          {/* 外部接続QR / External Connection QR */}
          {showExternalQR && (
            <>
              {tunnelInfo ? (
                <>
                  <div className="qr-placeholder" id="qr-code">
                    <img src={`data:image/png;base64,${tunnelInfo.qr_code}`} alt="External QR Code" />
                  </div>
                  <p className="connection-note">Connect via internet</p>
                  <div className="manual-connection-info">
                    <p className="manual-title">Manual Connection:</p>
                    <div className="manual-field">
                      <span className="field-label">URL:</span>
                      <code className="field-value url">{tunnelInfo.url.replace('https://', '')}</code>
                    </div>
                    <div className="manual-field">
                      <span className="field-label">Port:</span>
                      <code className="field-value">443</code>
                    </div>
                    <div className="manual-field">
                      <span className="field-label">Token:</span>
                      <code className="field-value token">{connectionInfo.auth_token}</code>
                    </div>
                  </div>
                  <button className="stop-tunnel-button" onClick={handleStopTunnel}>
                    Stop Tunnel
                  </button>
                </>
              ) : tunnelStarting ? (
                <div className="tunnel-loading">
                  <div className="spinner"></div>
                  <p>Starting tunnel...</p>
                </div>
              ) : (
                <div className="tunnel-setup">
                  {cloudflaredStatus?.installed === false ? (
                    installing ? (
                      <div className="install-progress">
                        <div className="spinner"></div>
                        <p>{installProgress || "Installing..."}</p>
                      </div>
                    ) : (
                      <>
                        <p className="warning-text">cloudflared is not installed</p>
                        <button className="start-tunnel-button" onClick={handleInstallCloudflared}>
                          📥 Auto Install
                        </button>
                        <p className="install-guide">
                          Or manual: <code>brew install cloudflared</code>
                        </p>
                      </>
                    )
                  ) : (
                    <>
                      <p>Enable connection from external network</p>
                      <button className="start-tunnel-button" onClick={handleStartTunnel}>
                        🚀 Start Tunnel
                      </button>
                    </>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      )}

      <div className="commands-section">
        <h2>Connection Info</h2>
        <div className="command-list">
          <p className="empty-message">Scan QR code with mobile app to connect</p>
        </div>
      </div>
    </div>
  );
}

export default App;
