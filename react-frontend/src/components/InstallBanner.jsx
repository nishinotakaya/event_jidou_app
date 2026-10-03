import { useState, useEffect, useCallback } from 'react';

const DISMISSED_STORAGE_KEY = 'pwa_install_banner_dismissed';
const DISMISS_DURATION_MS = 14 * 24 * 60 * 60 * 1000; // 14日間は再表示しない

function readDismissedAt() {
  try {
    return localStorage.getItem(DISMISSED_STORAGE_KEY);
  } catch {
    return null;
  }
}

function writeDismissedAt() {
  try {
    localStorage.setItem(DISMISSED_STORAGE_KEY, new Date().toISOString());
  } catch {
    // localStorage が使えない環境では何もしない
  }
}

function isDismissedRecently() {
  const dismissedAt = readDismissedAt();
  if (!dismissedAt) return false;
  const elapsedMs = Date.now() - new Date(dismissedAt).getTime();
  return Number.isFinite(elapsedMs) && elapsedMs < DISMISS_DURATION_MS;
}

function isRunningAsInstalledApp() {
  const matchesStandaloneMediaQuery = window.matchMedia('(display-mode: standalone)').matches;
  const isIosStandalone = window.navigator.standalone === true;
  return matchesStandaloneMediaQuery || isIosStandalone;
}

function isIosDevice() {
  return /iPhone|iPad|iPod/.test(navigator.userAgent) && !window.MSStream;
}

// マウント時点で一度だけ判定する（display-mode / 画面幅 / dismiss 履歴は実行中に変わらない前提）
function shouldEvaluateInstallability() {
  if (isRunningAsInstalledApp() || isDismissedRecently()) return false;
  return window.matchMedia('(max-width: 768px)').matches;
}

export default function InstallBanner() {
  const [deferredInstallPrompt, setDeferredInstallPrompt] = useState(null);
  // iOS Safari は beforeinstallprompt が発火しないため、初期状態で判定して即座にバナーを出す
  const [isIosSafari] = useState(() => shouldEvaluateInstallability() && isIosDevice());
  const [isBannerVisible, setIsBannerVisible] = useState(isIosSafari);

  useEffect(() => {
    if (isIosSafari || !shouldEvaluateInstallability()) return undefined;

    const handleBeforeInstallPrompt = (event) => {
      event.preventDefault();
      setDeferredInstallPrompt(event);
      setIsBannerVisible(true);
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    return () => window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
  }, [isIosSafari]);

  const handleDismiss = useCallback(() => {
    writeDismissedAt();
    setIsBannerVisible(false);
  }, []);

  const handleInstallClick = useCallback(async () => {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    setIsBannerVisible(false);
  }, [deferredInstallPrompt]);

  if (!isBannerVisible) return null;

  return (
    <div className="install-banner">
      <span className="install-banner-message">
        {isIosSafari
          ? '共有ボタン → 「ホーム画面に追加」でアプリとして使えます'
          : 'ホーム画面にアプリを追加できます'}
      </span>
      {!isIosSafari && (
        <button type="button" className="install-banner-button" onClick={handleInstallClick}>
          インストール
        </button>
      )}
      <button type="button" className="install-banner-close" aria-label="閉じる" onClick={handleDismiss}>
        ×
      </button>
    </div>
  );
}
