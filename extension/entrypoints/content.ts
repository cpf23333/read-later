import { extractNearbyImage, type ImageExtractionResult } from '@/utils/imageExtractor';
import { getEnabledCustomJsConfig } from '@/utils/apiStorage';

// 记录最后右键点击的元素
let lastRightClickedElement: HTMLElement | null = null;

export default defineContentScript({
  matches: ['<all_urls>'],
  main() {
    console.log('[ReadLater] Content script loaded');

    // 监听右键点击事件
    document.addEventListener('contextmenu', handleContextMenu, true);

    // 监听长按事件（移动设备）
    let longPressTimer: number | null = null;
    let touchStartElement: HTMLElement | null = null;

    document.addEventListener(
      'touchstart',
      (e) => {
        const target = e.target as HTMLElement;
        const linkElement = findLinkElement(target);

        if (linkElement) {
          touchStartElement = linkElement;
          longPressTimer = window.setTimeout(() => {
            lastRightClickedElement = linkElement;
          }, 500); // 500ms视为长按
        }
      },
      { passive: true }
    );

    document.addEventListener(
      'touchend',
      () => {
        if (longPressTimer) {
          clearTimeout(longPressTimer);
          longPressTimer = null;
        }
      },
      { passive: true }
    );

    document.addEventListener(
      'touchmove',
      () => {
        if (longPressTimer) {
          clearTimeout(longPressTimer);
          longPressTimer = null;
        }
      },
      { passive: true }
    );

    // 监听来自后台脚本的消息
    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
      handleMessage(message)
        .then((result) => sendResponse(result))
        .catch((error) => sendResponse({ success: false, error: error.message }));
      return true;
    });
  },
});

// 处理右键菜单事件
function handleContextMenu(e: MouseEvent) {
  const target = e.target as HTMLElement;
  const linkElement = findLinkElement(target);

  if (linkElement) {
    lastRightClickedElement = linkElement;
    console.log('[ReadLater] Link detected on context menu:', linkElement);
  }
}

// 查找链接元素
function findLinkElement(element: HTMLElement): HTMLAnchorElement | null {
  if (element.tagName === 'A') {
    return element as HTMLAnchorElement;
  }

  // 向上查找5层
  let current: HTMLElement | null = element;
  for (let i = 0; i < 5 && current; i++) {
    if (current.tagName === 'A') {
      return current as HTMLAnchorElement;
    }
    current = current.parentElement;
  }

  return null;
}

// 处理消息
async function handleMessage(message: any) {
  switch (message.type) {
    case 'EXTRACT_LINK_INFO':
      return await extractLinkInfo(message.url);

    case 'SAVE_SUCCESS':
      showToast(`链接已保存: ${message.data.title.substring(0, 30)}...`, 'success');
      return { success: true };

    case 'SAVE_DUPLICATE':
      const date = message.data.createdAt
        ? new Date(message.data.createdAt).toLocaleDateString('zh-CN')
        : '';
      showToast(`链接已存在 (${date})`, 'warning');
      return { success: true };

    case 'SAVE_ERROR':
      showToast(`保存失败: ${message.error}`, 'error');
      return { success: true };

    default:
      return { success: false, error: 'Unknown message type' };
  }
}

// 提取链接信息
async function extractLinkInfo(
  url: string
): Promise<{ success: boolean; data?: any; error?: string }> {
  if (!lastRightClickedElement) {
    return { success: false, error: 'No element selected' };
  }

  try {
    const linkElement = findLinkElement(lastRightClickedElement);
    if (!linkElement) {
      return { success: false, error: 'Link element not found' };
    }

    // 获取链接文本
    const linkText = linkElement.textContent?.trim() || '';

    // 获取附近的文本内容（用于标题）
    const nearbyText = getNearbyText(linkElement);

    // 获取自定义JS配置
    const customJsConfig = await getEnabledCustomJsConfig();

    // 提取附近的图片
    const imageResult = await extractNearbyImage(linkElement, url, customJsConfig?.code || null);

    console.log('[ReadLater] Extracted link info:', {
      url,
      linkText,
      nearbyText,
      imageUrl: imageResult.url,
      imageBase64: imageResult.base64 ? `${imageResult.base64.substring(0, 50)}...` : null,
    });

    return {
      success: true,
      data: {
        url,
        linkText,
        nearbyText,
        nearbyImage: imageResult.base64 || imageResult.url,
        hasCustomJs: !!customJsConfig,
      },
    };
  } catch (error) {
    console.error('[ReadLater] Failed to extract link info:', error);
    return { success: false, error: String(error) };
  }
}

// 获取链接附近的文本
function getNearbyText(element: HTMLElement): string {
  // 1. 获取title属性
  const title = element.getAttribute('title');
  if (title) return title;

  // 2. 获取aria-label
  const ariaLabel = element.getAttribute('aria-label');
  if (ariaLabel) return ariaLabel;

  // 3. 获取父元素的文本
  const parent = element.parentElement;
  if (parent) {
    // 排除链接本身的文本
    const clone = parent.cloneNode(true) as HTMLElement;
    const links = clone.querySelectorAll('a');
    links.forEach((a) => a.remove());
    const text = clone.textContent?.trim();
    if (text && text.length > 5) return text;
  }

  // 4. 返回链接文本
  return element.textContent?.trim() || '';
}

// 显示 Toast 提示（内容脚本专用，使用原生 DOM 实现）
// Vue 组件请使用 @/utils/toast
function showToast(message: string, type: 'success' | 'error' | 'warning' | 'info' = 'success') {
  const notification = document.createElement('div');

  const icons = {
    success: '✅',
    error: '❌',
    warning: '⚠️',
    info: 'ℹ️',
  };

  const colors = {
    success: 'background: #ecfdf5; color: #065f46; border: 1px solid #10b981;',
    error: 'background: #fef2f2; color: #991b1b; border: 1px solid #ef4444;',
    warning: 'background: #fffbeb; color: #92400e; border: 1px solid #f59e0b;',
    info: 'background: #eff6ff; color: #1e40af; border: 1px solid #3b82f6;',
  };

  notification.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    padding: 12px 20px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 500;
    font-family: system-ui, -apple-system, sans-serif;
    z-index: 2147483647;
    max-width: 400px;
    min-width: 200px;
    word-break: break-word;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    animation: readlater-slide-in 0.3s ease;
    display: flex;
    align-items: center;
    gap: 8px;
    ${colors[type]}
  `;

  const icon = document.createElement('span');
  icon.textContent = icons[type];
  icon.style.cssText = 'font-size: 16px;';

  const text = document.createElement('span');
  text.textContent = message;

  notification.appendChild(icon);
  notification.appendChild(text);

  // 添加动画样式
  if (!document.getElementById('readlater-styles')) {
    const style = document.createElement('style');
    style.id = 'readlater-styles';
    style.textContent = `
      @keyframes readlater-slide-in {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
      }
      @keyframes readlater-fade-out {
        from { transform: translateX(0); opacity: 1; }
        to { transform: translateX(100%); opacity: 0; }
      }
    `;
    document.head.appendChild(style);
  }

  document.body.appendChild(notification);

  // 3秒后自动移除
  setTimeout(() => {
    notification.style.animation = 'readlater-fade-out 0.3s ease forwards';
    setTimeout(() => {
      notification.remove();
    }, 300);
  }, 3000);
}
