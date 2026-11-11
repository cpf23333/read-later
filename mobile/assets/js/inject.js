/*
 * ReadLater 注入脚本：长按链接检测 + 页面内信息提取。
 * 运行在页面上下文，通过 flutter_inappwebview 的 JS handler 与 Dart 通信。
 */
(() => {
  if (window.__rlInjected) return;
  window.__rlInjected = true;

  const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
  const LONG_PRESS_MS = 500;
  const MOVE_THRESHOLD = 10;

  function isHttpUrl(url) {
    return typeof url === 'string' && /^https?:\/\//i.test(url);
  }

  function findLink(element) {
    let node = element;
    for (let i = 0; i < 6 && node; i += 1) {
      if (node.tagName === 'A' && node.getAttribute('href')) return node;
      node = node.parentElement;
    }
    return null;
  }

  function getNearbyText(anchor) {
    const title = anchor.getAttribute('title');
    if (title) return title;

    const aria = anchor.getAttribute('aria-label');
    if (aria) return aria;

    const parent = anchor.parentElement;
    if (parent) {
      const clone = parent.cloneNode(true);
      clone.querySelectorAll('a').forEach((a) => a.remove());
      const text = (clone.textContent || '').trim();
      if (text.length > 5) return text;
    }

    return (anchor.textContent || '').trim();
  }

  function findNearbyImage(anchor) {
    if (anchor.tagName === 'IMG') return anchor.src;

    const inner = anchor.querySelector('img');
    if (inner) return inner.src;

    const parent = anchor.parentElement;
    if (parent) {
      const img = parent.querySelector('img');
      if (img) return img.src;
    }

    const prev = anchor.previousElementSibling;
    if (prev && prev.tagName === 'IMG') return prev.src;

    const next = anchor.nextElementSibling;
    if (next && next.tagName === 'IMG') return next.src;

    let current = anchor;
    for (let i = 0; i < 3 && current; i += 1) {
      current = current.parentElement;
      if (current) {
        const img = current.querySelector('img');
        if (img) return img.src;
      }
    }

    return null;
  }

  function blobToDataUrl(blob) {
    return new Promise((resolve) => {
      try {
        const reader = new FileReader();
        reader.onloadend = () => resolve(typeof reader.result === 'string' ? reader.result : null);
        reader.onerror = () => resolve(null);
        reader.readAsDataURL(blob);
      } catch (_) {
        resolve(null);
      }
    });
  }

  async function imageToBase64(url) {
    if (!url) return null;
    if (url.startsWith('data:')) return url;

    try {
      const response = await fetch(url);
      if (!response.ok) return null;
      const blob = await response.blob();
      if (blob.size > MAX_IMAGE_BYTES) return null;
      return await blobToDataUrl(blob);
    } catch (_) {
      return null;
    }
  }

  /**
   * 提取当前长按链接（或按 url 匹配到的链接）的信息。
   * 结果通过 rl:extractResult 回传给 Dart（evaluateJavascript 不会 await Promise）。
   */
  async function collectLinkInfo(url) {
    let anchor = window.__rlLastAnchor;
    if (!anchor || (url && anchor.href !== url)) {
      try {
        anchor = document.querySelector(`a[href="${url}"]`);
      } catch (_) {
        anchor = null;
      }
    }

    if (!anchor) {
      return { linkText: '', nearbyText: '', nearbyImage: null };
    }

    const linkText = (anchor.textContent || '').trim();
    const nearbyText = getNearbyText(anchor);
    const imageUrl = findNearbyImage(anchor);

    let nearbyImage = null;
    if (imageUrl) {
      nearbyImage =
        imageUrl.startsWith('blob:') || imageUrl.startsWith('data:')
          ? await imageToBase64(imageUrl)
          : imageUrl;
    }

    return {
      linkText: linkText,
      nearbyText: nearbyText,
      nearbyImage: nearbyImage,
    };
  }

  window.__rlExtract = async function (url) {
    const data = await collectLinkInfo(url);
    try {
      window.flutter_inappwebview.callHandler('rl:extractResult', JSON.stringify(data));
    } catch (_) {
      // 非 app 环境忽略。
    }
    return true;
  };

  function sendLongPress(anchor) {
    window.__rlLastAnchor = anchor;
    const rect = anchor.getBoundingClientRect();
    try {
      window.flutter_inappwebview.callHandler('rl:longPress', {
        url: anchor.href,
        text: (anchor.textContent || '').trim(),
        sourcePage: location.href,
        rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      });
    } catch (_) {
      // 非 app 环境（例如普通浏览器）忽略。
    }
  }

  let timer = null;
  let startX = 0;
  let startY = 0;
  let suppressClick = false;

  function cancelLongPress() {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  }

  document.addEventListener(
    'touchstart',
    (event) => {
      if (event.touches.length !== 1) return;
      const touch = event.touches[0];
      const anchor = findLink(event.target);
      if (!anchor || !isHttpUrl(anchor.href)) return;

      startX = touch.clientX;
      startY = touch.clientY;
      cancelLongPress();
      timer = setTimeout(() => {
        timer = null;
        suppressClick = true;
        setTimeout(() => {
          suppressClick = false;
        }, 800);
        sendLongPress(anchor);
      }, LONG_PRESS_MS);
    },
    { capture: true, passive: true }
  );

  document.addEventListener('touchend', cancelLongPress, { capture: true, passive: true });
  document.addEventListener('touchcancel', cancelLongPress, { capture: true, passive: true });

  document.addEventListener(
    'touchmove',
    (event) => {
      if (!timer) return;
      const touch = event.touches[0];
      if (!touch) return;
      if (
        Math.abs(touch.clientX - startX) > MOVE_THRESHOLD ||
        Math.abs(touch.clientY - startY) > MOVE_THRESHOLD
      ) {
        cancelLongPress();
      }
    },
    { capture: true, passive: true }
  );

  document.addEventListener(
    'click',
    (event) => {
      if (!suppressClick) return;
      suppressClick = false;
      event.preventDefault();
      event.stopPropagation();
    },
    true
  );

  // iOS callout 兜底（Android 无副作用）。
  try {
    const style = document.createElement('style');
    style.textContent = 'a[href] { -webkit-touch-callout: none; }';
    (document.head || document.documentElement).appendChild(style);
  } catch (_) {
    // 忽略 CSP 限制。
  }

  // ---- 视频地址检测：<video>/<source> + fetch/XHR ----
  const MEDIA_URL_RE = /\.(m3u8|mpd|mp4)(?=$|[?#])/i;
  const reportedMedia = new Set();

  function sendMedia(url, type) {
    if (!isHttpUrl(url) || !MEDIA_URL_RE.test(url)) return;
    if (reportedMedia.has(url)) return;
    reportedMedia.add(url);
    try {
      window.flutter_inappwebview.callHandler('rl:media', {
        url: url,
        type: type,
        title: document.title,
        sourcePage: location.href,
        ua: navigator.userAgent,
      });
    } catch (_) {
      // 非 app 环境忽略。
    }
  }

  function scanMediaUrl(raw) {
    if (!raw) return;
    try {
      const url = new URL(String(raw), location.href).href;
      if (MEDIA_URL_RE.test(url)) sendMedia(url, 'network');
    } catch (_) {
      // 忽略非法 URL。
    }
  }

  function scanMediaElements() {
    document.querySelectorAll('video').forEach((video) => {
      const src = video.currentSrc || video.src;
      if (src) sendMedia(src, 'video');
      video.querySelectorAll('source').forEach((source) => {
        if (source.src) sendMedia(source.src, 'source');
      });
    });
  }

  try {
    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function (...args) {
        try {
          const input = args[0];
          scanMediaUrl(typeof input === 'string' ? input : input && input.url);
        } catch (_) {}
        return originalFetch.apply(this, args);
      };
    }
  } catch (_) {}

  try {
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url, ...rest) {
      try {
        scanMediaUrl(url);
      } catch (_) {}
      return originalOpen.call(this, method, url, ...rest);
    };
  } catch (_) {}

  // ---- Bilibili DASH：页面登录后 __playinfo__ 内含音视频分轨 ----
  const reportedBilibili = new Set();

  function bilibiliTrack(track) {
    if (!track) return null;
    const segment =
      track.SegmentBase || track.segmentBase || track.segment_base || {};
    const backups = track.backupUrl || track.backup_url || [];
    return {
      baseUrl: track.baseUrl || track.base_url || '',
      backupUrl: Array.isArray(backups) ? backups.slice(0, 2) : [],
      bandwidth: track.bandwidth || 0,
      codecs: track.codecs || '',
      mimeType: track.mimeType || track.mime_type || '',
      width: track.width || 0,
      height: track.height || 0,
      frameRate: track.frameRate || track.frame_rate || '',
      segmentBase: {
        Initialization: segment.Initialization || segment.initialization || '',
        indexRange: segment.indexRange || segment.index_range || '',
      },
    };
  }

  function reportBilibili() {
    const info = window.__playinfo__;
    const data = info && info.data;
    const dash = data && data.dash;
    if (!dash || !Array.isArray(dash.video) || dash.video.length === 0) return;

    const first = bilibiliTrack(dash.video[0]);
    if (!first || !first.baseUrl) return;
    const reportKey = location.href + '|' + first.baseUrl;
    if (reportedBilibili.has(reportKey)) return;
    reportedBilibili.add(reportKey);

    const video = dash.video.map(bilibiliTrack).filter((item) => item && item.baseUrl);
    const audio = (Array.isArray(dash.audio) ? dash.audio : [])
      .map(bilibiliTrack)
      .filter((item) => item && item.baseUrl);
    const duration = dash.duration || (data.timelength ? data.timelength / 1000 : 0);

    try {
      window.flutter_inappwebview.callHandler('rl:bilibili', {
        url: first.baseUrl,
        type: 'bilibili-dash',
        title: document.title,
        sourcePage: location.href,
        ua: navigator.userAgent,
        bilibili: { duration: duration, video: video, audio: audio },
      });
    } catch (_) {
      // 非 app 环境忽略。
    }
  }

  function scheduleMediaScan() {
    scanMediaElements();
    reportBilibili();
    setTimeout(scanMediaElements, 1000);
    setTimeout(reportBilibili, 1000);
    setTimeout(reportBilibili, 3000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleMediaScan);
  } else {
    scheduleMediaScan();
  }
  setInterval(scanMediaElements, 3000);
  setInterval(reportBilibili, 3000);
  window.__rlScanMedia = scheduleMediaScan;
  window.__rlScanBilibili = reportBilibili;

  // Bilibili 的站内切视频通常走 SPA 路由，不触发页面重载。
  // URL 变化时清掉旧视频的探测缓存，并通知 Flutter 丢弃旧媒体。
  let lastPageUrl = location.href;
  function watchPageUrl() {
    if (location.href === lastPageUrl) return;
    lastPageUrl = location.href;
    reportedBilibili.clear();
    try {
      window.flutter_inappwebview.callHandler('rl:urlChanged', {
        url: location.href,
      });
    } catch (_) {}
    reportBilibili();
  }
  setInterval(watchPageUrl, 1000);
  window.__rlWatchPageUrl = watchPageUrl;

  // 集成测试钩子：直接触发长按回调（不模拟真实手势）。
  window.__rlTestLongPress = function (selector) {
    const anchor = document.querySelector(selector);
    if (!anchor) return false;
    sendLongPress(anchor);
    return true;
  };
})();
