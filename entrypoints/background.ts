import { addLink, getEnabledCustomJsConfig, isLinkExists, getLinkByUrl } from '@/utils/storage';

// 右键菜单ID
const CONTEXT_MENU_ID = 'url-mem-save-link';

export default defineBackground(() => {
  console.log('[UrlMem] Background script started');

  // 创建右键菜单
  browser.contextMenus.create({
    id: CONTEXT_MENU_ID,
    title: '收藏链接到 UrlMem',
    contexts: ['link'],
  });

  // 监听菜单点击
  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    if (info.menuItemId !== CONTEXT_MENU_ID) return;
    if (!tab?.id || !info.linkUrl) return;

    console.log('[UrlMem] Save link clicked:', info.linkUrl);

    try {
      // 检查链接是否已存在
      const exists = await isLinkExists(info.linkUrl);
      if (exists) {
        const existingLink = await getLinkByUrl(info.linkUrl);
        console.log('[UrlMem] Link already exists:', existingLink?.id);
        
        // 通知内容脚本链接已存在
        browser.tabs.sendMessage(tab.id, {
          type: 'SAVE_DUPLICATE',
          data: { 
            id: existingLink?.id,
            title: existingLink?.title,
            createdAt: existingLink?.createdAt,
          },
        }).catch(() => {});
        return;
      }

      // 向内容脚本发送消息，获取链接信息
      const result = await browser.tabs.sendMessage(tab.id, {
        type: 'EXTRACT_LINK_INFO',
        url: info.linkUrl,
      });

      if (result.success) {
        // 获取页面标题（通过打开链接）
        const pageTitle = await fetchPageTitle(info.linkUrl);
        
        // 尝试获取页面截图
        const screenshot = await captureTab(tab.id);

        // 获取自定义JS配置
        const customJsConfig = await getEnabledCustomJsConfig();

        // 保存链接
        const linkItem = await addLink({
          url: info.linkUrl,
          title: pageTitle || result.data.nearbyText || info.linkUrl,
          nearbyImage: result.data.nearbyImage,
          screenshot: screenshot,
          sourcePage: tab.url || '',
          customData: {
            linkText: result.data.linkText,
            customJsUsed: !!customJsConfig,
          },
        });

        console.log('[UrlMem] Link saved:', linkItem.id);
        
        // 通知内容脚本保存成功
        browser.tabs.sendMessage(tab.id, {
          type: 'SAVE_SUCCESS',
          data: { id: linkItem.id, title: linkItem.title },
        }).catch(() => {});
      }
    } catch (error) {
      console.error('[UrlMem] Failed to save link:', error);
      
      // 通知内容脚本保存失败
      if (tab.id) {
        browser.tabs.sendMessage(tab.id, {
          type: 'SAVE_ERROR',
          error: error instanceof Error ? error.message : 'Unknown error',
        }).catch(() => {});
      }
    }
  });

  // 监听来自内容脚本和弹出窗口的消息
  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    handleMessage(message, sender)
      .then(sendResponse)
      .catch((error) => sendResponse({ success: false, error: error.message }));
    return true; // 保持消息通道开放
  });
});

// 处理消息
async function handleMessage(message: any, sender: any) {
  switch (message.type) {
    case 'CAPTURE_TAB':
      if (sender.tab?.id) {
        const screenshot = await captureTab(sender.tab.id);
        return { success: true, data: screenshot };
      }
      return { success: false, error: 'No active tab' };

    case 'FETCH_TITLE':
      const title = await fetchPageTitle(message.url);
      return { success: true, data: title };

    case 'OPEN_LINK_MANAGER':
      await browser.tabs.create({
        url: browser.runtime.getURL('/link-manager.html'),
      });
      return { success: true };

    case 'OPEN_SETTINGS':
      await browser.tabs.create({
        url: browser.runtime.getURL('/options.html'),
      });
      return { success: true };

    default:
      return { success: false, error: 'Unknown message type' };
  }
}

// 获取页面标题
async function fetchPageTitle(url: string): Promise<string | null> {
  try {
    // 先尝试通过内容脚本获取
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    if (tabs[0]?.url === url && tabs[0]?.title) {
      return tabs[0].title;
    }

    // 尝试fetch获取
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    const response = await fetch(url, {
      method: 'GET',
      signal: controller.signal,
      headers: {
        'Accept': 'text/html',
      },
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      return null;
    }

    const html = await response.text();
    
    // 解析标题
    const titleMatch = html.match(/<title[^>]*>([^<]*)<\/title>/i);
    if (titleMatch) {
      return titleMatch[1].trim();
    }

    // 尝试获取og:title
    const ogTitleMatch = html.match(/<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']*)["']/i);
    if (ogTitleMatch) {
      return ogTitleMatch[1].trim();
    }

    return null;
  } catch (error) {
    console.warn('[UrlMem] Failed to fetch page title:', error);
    return null;
  }
}

// 捕获标签页截图
async function captureTab(tabId: number): Promise<string | null> {
  try {
    // 检查权限
    const hasPermission = await browser.permissions.contains({
      permissions: ['activeTab'],
    });

    if (!hasPermission) {
      console.warn('[UrlMem] No activeTab permission');
      return null;
    }

    // 捕获可见区域
    const dataUrl = await browser.tabs.captureVisibleTab({
      format: 'jpeg',
      quality: 80,
    });

    return dataUrl;
  } catch (error) {
    console.warn('[UrlMem] Failed to capture tab:', error);
    return null;
  }
}
