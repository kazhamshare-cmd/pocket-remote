import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { check } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
import { AppLanguage, languages, getTranslations, loadLanguage, saveLanguage } from "./i18n";

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

// Play notification sound (gentle chime)
function playNotificationSound() {
  try {
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();

    const osc = audioContext.createOscillator();
    const gain = audioContext.createGain();
    osc.connect(gain);
    gain.connect(audioContext.destination);
    osc.frequency.value = 523.25; // C5
    osc.type = 'sine';
    gain.gain.setValueAtTime(0.3, audioContext.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3);
    osc.start(audioContext.currentTime);
    osc.stop(audioContext.currentTime + 0.3);

    console.log('[Audio] Notification sound played');
  } catch (e) {
    console.error('[Audio] Failed to play notification sound:', e);
  }
}

function App() {
  // Language state
  const [language, setLanguage] = useState<AppLanguage>(loadLanguage());
  const [showLanguageMenu, setShowLanguageMenu] = useState(false);
  const t = getTranslations(language);

  const [connectionInfo, setConnectionInfo] = useState<ConnectionInfo | null>(null);
  const [connected, setConnected] = useState(false);
  const [connectedDevice, setConnectedDevice] = useState<string | null>(null);
  const [accessibilityGranted, setAccessibilityGranted] = useState<boolean | null>(null);
  const [checkingPermission, setCheckingPermission] = useState(true);

  // Tunnel
  const [cloudflaredStatus, setCloudflaredStatus] = useState<CloudflaredStatus | null>(null);
  const [tunnelInfo, setTunnelInfo] = useState<TunnelInfo | null>(null);
  const [tunnelStarting, setTunnelStarting] = useState(false);
  const [showExternalQR, setShowExternalQR] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [installProgress, setInstallProgress] = useState<string | null>(null);

  // Connection request
  const [pendingRequest, setPendingRequest] = useState<ConnectionRequest | null>(null);
  const lastSoundRequestId = useRef<string | null>(null);

  // Update
  const [updateAvailable, setUpdateAvailable] = useState<{ version: string; notes?: string } | null>(null);
  const [updateDownloading, setUpdateDownloading] = useState(false);

  // Handle language change
  const handleLanguageChange = (lang: AppLanguage) => {
    setLanguage(lang);
    saveLanguage(lang);
    setShowLanguageMenu(false);
  };

  useEffect(() => {
    // Check for updates
    const checkForUpdates = async () => {
      try {
        console.log("[Updater] Checking for updates...");
        const update = await check();
        if (update) {
          console.log(`[Updater] Update available: v${update.version}`);
          setUpdateAvailable({
            version: update.version,
            notes: update.body || undefined,
          });
        } else {
          console.log("[Updater] No updates available");
        }
      } catch (e) {
        console.error("[Updater] Failed to check for updates:", e);
      }
    };
    checkForUpdates();

    // Check accessibility permission
    const checkPermissions = async () => {
      try {
        const granted = await invoke<boolean>("check_accessibility");
        setAccessibilityGranted(granted);
      } catch (e) {
        console.error("Failed to check accessibility:", e);
        setAccessibilityGranted(true);
      } finally {
        setCheckingPermission(false);
      }
    };
    checkPermissions();

    // Check cloudflared status
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

    // Listen for tunnel started event
    const unlistenTunnel = listen<TunnelInfo>("tunnel_started", (event) => {
      console.log("Tunnel started:", event.payload);
      setTunnelInfo(event.payload);
      setTunnelStarting(false);
      setShowExternalQR(true);
    });

    // Listen for install progress
    const unlistenProgress = listen<string>("cloudflared_install_progress", (event) => {
      console.log("Install progress:", event.payload);
      setInstallProgress(event.payload);
    });

    // Listen for connection requests
    const unlistenConnectionRequest = listen<ConnectionRequest>("connection_request", (event) => {
      console.log("===== CONNECTION REQUEST RECEIVED =====");
      console.log("Event payload:", event.payload);
      console.log("Setting pendingRequest...");
      setPendingRequest(event.payload);
      if (lastSoundRequestId.current !== event.payload.request_id) {
        lastSoundRequestId.current = event.payload.request_id;
        playNotificationSound();
      }
    });
    console.log("Connection request listener registered");

    return () => {
      unlistenTunnel.then(fn => fn());
      unlistenProgress.then(fn => fn());
      unlistenConnectionRequest.then(fn => fn());
    };
  }, []);

  // Monitor connection state
  useEffect(() => {
    const interval = setInterval(async () => {
      try {
        const info = await invoke<ConnectionInfo | null>("get_connection_info");
        if (info) {
          if (!connectionInfo || connectionInfo.auth_token !== info.auth_token) {
            console.log("[App] Connection info updated, new token:", info.auth_token);
            setConnectionInfo(info);
          }
        }

        const status = await invoke<{ connected: boolean; device: string | null }>("get_connection_status");
        setConnected(status.connected);
        setConnectedDevice(status.device);

        if (!accessibilityGranted) {
          const granted = await invoke<boolean>("check_accessibility");
          if (granted) {
            setAccessibilityGranted(true);
          }
        }

        if (tunnelStarting && !tunnelInfo) {
          const info = await invoke<TunnelInfo | null>("get_tunnel_info");
          if (info) {
            console.log("Tunnel info received via polling:", info);
            setTunnelInfo(info);
            setTunnelStarting(false);
            setShowExternalQR(true);
          }
        }

        const request = await invoke<ConnectionRequest | null>("get_pending_request");
        if (request && !pendingRequest) {
          console.log("Pending request found via polling:", request);
          setPendingRequest(request);
        }
      } catch (e) {
        console.error(e);
      }
    }, 500);

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
    setInstallProgress(t.installing);
    try {
      await invoke("install_cloudflared");
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

  const handleUpdate = async () => {
    try {
      setUpdateDownloading(true);
      const update = await check();
      if (update) {
        console.log("[Updater] Downloading and installing update...");
        await update.downloadAndInstall();
        console.log("[Updater] Relaunching...");
        await relaunch();
      }
    } catch (e) {
      console.error("[Updater] Failed to update:", e);
      setUpdateDownloading(false);
    }
  };

  return (
    <div className="container">
      {/* Language Selector */}
      <div className="language-selector">
        <button
          className="language-button"
          onClick={() => setShowLanguageMenu(!showLanguageMenu)}
        >
          {languages[language].flag} {languages[language].name}
        </button>
        {showLanguageMenu && (
          <div className="language-menu">
            {(Object.keys(languages) as AppLanguage[]).map((lang) => (
              <button
                key={lang}
                className={`language-option ${lang === language ? 'active' : ''}`}
                onClick={() => handleLanguageChange(lang)}
              >
                {languages[lang].flag} {languages[lang].name}
              </button>
            ))}
          </div>
        )}
      </div>

      <h1>{t.appName}</h1>

      {/* Connection Request Dialog */}
      {pendingRequest && (
        <div className="connection-dialog-overlay">
          <div className="connection-dialog">
            <div className="dialog-icon">📱</div>
            <h3>{t.connectionRequest}</h3>
            <p className="device-name">{pendingRequest.device_name}</p>
            <p className="device-ip">IP: {pendingRequest.ip_address}</p>
            <p className="dialog-message">{t.allowConnection}</p>
            <div className="dialog-buttons">
              <button
                className="approve-button"
                onClick={() => handleConnectionResponse(true)}
              >
                ✓ {t.allow}
              </button>
              <button
                className="deny-button"
                onClick={() => handleConnectionResponse(false)}
              >
                ✕ {t.deny}
              </button>
            </div>
            <p className="dialog-timeout">{t.autodenied}</p>
          </div>
        </div>
      )}

      {/* Update Notification */}
      {updateAvailable && (
        <div className="update-banner">
          <div className="update-content">
            <span className="update-icon">🎉</span>
            <span className="update-text">
              {t.updateAvailable} v{updateAvailable.version}
            </span>
          </div>
          {updateDownloading ? (
            <div className="update-progress">
              <div className="spinner small"></div>
              <span>{t.updating}</span>
            </div>
          ) : (
            <div className="update-buttons">
              <button className="update-button" onClick={handleUpdate}>
                {t.updateNow}
              </button>
              <button className="update-dismiss" onClick={() => setUpdateAvailable(null)}>
                {t.later}
              </button>
            </div>
          )}
        </div>
      )}

      {/* Accessibility Permission Warning */}
      {!checkingPermission && accessibilityGranted === false && (
        <div className="permission-warning">
          <div className="warning-icon">⚠️</div>
          <h3>{t.accessibilityRequired}</h3>
          <p>{t.accessibilityDescription}</p>
          <div className="permission-buttons">
            <button className="primary-button" onClick={handleOpenSettings}>
              {t.openSystemSettings}
            </button>
            <button className="secondary-button" onClick={handleRetryPermission}>
              {t.recheck}
            </button>
          </div>
          <div className="permission-steps">
            <p><strong>{t.permissionSteps}</strong></p>
            <ol>
              <li>{t.step1}</li>
              <li>{t.step2}</li>
              <li>{t.step3}</li>
            </ol>
          </div>
        </div>
      )}

      <div className="status-card">
        <div className={`status-indicator ${connected ? "connected" : "waiting"}`} />
        <span>{connected ? `${t.connected}: ${connectedDevice}` : t.waitingForConnection}</span>
        {accessibilityGranted && (
          <span className="permission-badge granted">✓ {t.permissionOK}</span>
        )}
      </div>

      {connectionInfo && (
        <div className="qr-section">
          <h2>{t.scanQRCode}</h2>

          {/* Local/External Tabs */}
          <div className="connection-tabs">
            <button
              className={`tab-button ${!showExternalQR ? 'active' : ''}`}
              onClick={() => setShowExternalQR(false)}
            >
              🏠 {t.local}
            </button>
            <button
              className={`tab-button ${showExternalQR ? 'active' : ''}`}
              onClick={() => setShowExternalQR(true)}
            >
              🌐 {t.external}
            </button>
          </div>

          {/* Local Connection QR */}
          {!showExternalQR && (
            <>
              <div className="qr-placeholder" id="qr-code">
                <img src={`data:image/png;base64,${connectionInfo.qr_code}`} alt="QR Code" />
              </div>
              <p className="connection-note">{t.connectWithinSameNetwork}</p>
              <div className="manual-connection-info">
                <p className="manual-title">{t.manualConnection}</p>
                <div className="manual-field">
                  <span className="field-label">{t.ipAddress}:</span>
                  <code className="field-value">{connectionInfo.ip}</code>
                </div>
                <div className="manual-field">
                  <span className="field-label">{t.port}:</span>
                  <code className="field-value">{connectionInfo.port}</code>
                </div>
                <div className="manual-field">
                  <span className="field-label">{t.token}:</span>
                  <code className="field-value token">{connectionInfo.auth_token}</code>
                </div>
              </div>
            </>
          )}

          {/* External Connection QR */}
          {showExternalQR && (
            <>
              {tunnelInfo ? (
                <>
                  <div className="qr-placeholder" id="qr-code">
                    <img src={`data:image/png;base64,${tunnelInfo.qr_code}`} alt="External QR Code" />
                  </div>
                  <p className="connection-note">{t.connectViaInternet}</p>
                  <div className="manual-connection-info">
                    <p className="manual-title">{t.manualConnection}</p>
                    <div className="manual-field">
                      <span className="field-label">{t.url}:</span>
                      <code className="field-value url">{tunnelInfo.url.replace('https://', '')}</code>
                    </div>
                    <div className="manual-field">
                      <span className="field-label">{t.port}:</span>
                      <code className="field-value">443</code>
                    </div>
                    <div className="manual-field">
                      <span className="field-label">{t.token}:</span>
                      <code className="field-value token">{connectionInfo.auth_token}</code>
                    </div>
                  </div>
                  <button className="stop-tunnel-button" onClick={handleStopTunnel}>
                    {t.stopTunnel}
                  </button>
                </>
              ) : tunnelStarting ? (
                <div className="tunnel-loading">
                  <div className="spinner"></div>
                  <p>{t.startingTunnel}</p>
                </div>
              ) : (
                <div className="tunnel-setup">
                  {cloudflaredStatus?.installed === false ? (
                    installing ? (
                      <div className="install-progress">
                        <div className="spinner"></div>
                        <p>{installProgress || t.installing}</p>
                      </div>
                    ) : (
                      <>
                        <p className="warning-text">{t.cloudflaredNotInstalled}</p>
                        <button className="start-tunnel-button" onClick={handleInstallCloudflared}>
                          📥 {t.autoInstall}
                        </button>
                        <p className="install-guide">
                          {t.manualInstallHint} <code>brew install cloudflared</code>
                        </p>
                      </>
                    )
                  ) : (
                    <>
                      <p>{t.enableExternalConnection}</p>
                      <button className="start-tunnel-button" onClick={handleStartTunnel}>
                        🚀 {t.startTunnel}
                      </button>
                    </>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      )}

      {/* Connected Devices */}
      <div className="connected-devices-section">
        <h2>{t.connectedDevices}</h2>
        <div className="device-list">
          {connected && connectedDevice ? (
            <div className="device-item connected">
              <span className="device-icon">📱</span>
              <span className="device-name">{connectedDevice}</span>
              <span className="device-status">● {t.connected}</span>
            </div>
          ) : (
            <p className="empty-message">{t.noDevicesConnected}</p>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
