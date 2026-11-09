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
   * 返回 JSON 字符串，供 Dart evaluateJavascript 使用。
   */
  window.__rlExtract = async function (url) {
    let anchor = window.__rlLastAnchor;
    if (!anchor || (url && anchor.href !== url)) {
      try {
        anchor = document.querySelector(`a[href="${url}"]`);
      } catch (_) {
        anchor = null;
      }
    }

    if (!anchor) {
      return JSON.stringify({ linkText: '', nearbyText: '', nearbyImage: null });
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

    return JSON.stringify({
      linkText: linkText,
      nearbyText: nearbyText,
      nearbyImage: nearbyImage,
    });
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

  // 集成测试钩子：直接触发长按回调（不模拟真实手势）。
  window.__rlTestLongPress = function (selector) {
    const anchor = document.querySelector(selector);
    if (!anchor) return false;
    sendLongPress(anchor);
    return true;
  };
})();
