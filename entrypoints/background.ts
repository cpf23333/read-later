import { 
  addLink, 
  getEnabledCustomJsConfig, 
  isLinkExists, 
  getLinkByUrl 
} from '@/utils/storage';
import {
  syncPendingItems,
  checkServerHealth,
  getSyncStatus,
} from '@/utils/hybridStorage';

// 右键菜单ID
const CONTEXT_MENU_ID = 'read-later-save-link';

// 同步定时器
let syncIntervalId: number | null = null;
const SYNC_INTERVAL = 60 * 1000; // 每分钟检查一次同步

export default defineBackground(() => {
  console.log('[ReadLater] Background script started');

  // 创建右键菜单
  browser.contextMenus.create({
    id: CONTEXT_MENU_ID,
    title: '收好链接（稍后再看）',
    contexts: ['link'],
  });

  // 监听菜单点击
  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    if (info.menuItemId !== CONTEXT_MENU_ID) return;
    if (!tab?.id || !info.linkUrl) return;

    console.log('[ReadLater] Save link clicked:', info.linkUrl);

    try {
      // 检查链接是否已存在
      const exists = await isLinkExists(info.linkUrl);
      if (exists) {
        const existingLink = await getLinkByUrl(info.linkUrl);
        console.log('[ReadLater] Link already exists:', existingLink?.id);
        
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

        // 保存链接（会自动处理服务器同步）
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

        console.log('[ReadLater] Link saved:', linkItem.id);
        
        // 通知内容脚本保存成功
        browser.tabs.sendMessage(tab.id, {
          type: 'SAVE_SUCCESS',
          data: { id: linkItem.id, title: linkItem.title },
        }).catch(() => {});
      }
    } catch (error) {
      console.error('[ReadLater] Failed to save link:', error);
      
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

  // 启动定期同步任务
  startPeriodicSync();

  // 监听在线状态变化
  browser.runtime.onConnect.addListener((port) => {
    if (port.name === 'sync-status') {
      port.onMessage.addListener(async (message) => {
        if (message.type === 'GET_SYNC_STATUS') {
          const status = await getSyncStatus();
          port.postMessage({ type: 'SYNC_STATUS', data: status });
        } else if (message.type === 'TRIGGER_SYNC') {
          const result = await syncPendingItems();
          port.postMessage({ type: 'SYNC_RESULT', data: result });
        }
      });
    }
  });
});

// 启动定期同步
function startPeriodicSync() {
  // 立即执行一次同步
  performSync();
  
  // 设置定时器
  syncIntervalId = window.setInterval(performSync, SYNC_INTERVAL);
  console.log('[ReadLater] Periodic sync started');
}

// 执行同步
async function performSync() {
  try {
    const status = await getSyncStatus();
    
    // 只有有待同步项目时才执行
    if (status.pendingCount > 0) {
      console.log(`[ReadLater] Syncing ${status.pendingCount} pending items...`);
      const result = await syncPendingItems();
      
      if (result.synced > 0) {
        console.log(`[ReadLater] Synced ${result.synced} items, ${result.failed} failed`);
      }
      
      if (result.errors.length > 0) {
        console.warn('[ReadLater] Sync errors:', result.errors);
      }
    }
  } catch (error) {
    console.error('[ReadLater] Sync failed:', error);
  }
}

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

    case 'CHECK_SERVER_HEALTH':
      const isOnline = await checkServerHealth();
      return { success: true, data: { isOnline } };

    case 'SYNC_NOW':
      const syncResult = await syncPendingItems();
      return { success: syncResult.success, data: syncResult };

    case 'GET_SYNC_STATUS':
      const status = await getSyncStatus();
      return { success: true, data: status };

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
    console.warn('[ReadLater] Failed to fetch page title:', error);
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
      console.warn('[ReadLater] No activeTab permission');
      return null;
    }

    // 捕获可见区域
    const dataUrl = await browser.tabs.captureVisibleTab({
      format: 'jpeg',
      quality: 80,
    });

    return dataUrl;
  } catch (error) {
    console.warn('[ReadLater] Failed to capture tab:', error);
    return null;
  }
}
