// WebDAV 同步模块 - 支持历史版本

import { 
  exportLinks, 
  importLinks, 
  LinkItem, 
  getCustomJsConfigs, 
  saveCustomJsConfig, 
  CustomJsConfig, 
  normalizeUrl,
  getDeleteRecords,
  clearOldDeleteRecords,
  DeleteRecord,
} from './storage';

export interface WebDAVConfig {
  enabled: boolean;
  url: string;
  username: string;
  password: string;
  autoSync: boolean;
  syncInterval: number; // 分钟
  lastSyncTime?: number;
  folderName?: string; // 存储文件夹名称
  keepHistory?: number; // 保留历史版本数量
}

const CONFIG_KEY = 'webdav_config';
const DEFAULT_FOLDER = 'ReadLater';
const DEFAULT_HISTORY_COUNT = 10;
const DATA_FILE_NAME = 'readlater-data.json';
const HISTORY_FOLDER = 'history';
const IMAGES_FOLDER = 'images'; // 图片文件夹
const DELETED_IMAGES_FOLDER = 'images/deleted'; // 已删除图片文件夹（在images下）

// 获取 WebDAV 配置
export async function getWebDAVConfig(): Promise<WebDAVConfig> {
  const result = await browser.storage.sync.get(CONFIG_KEY);
  const defaultConfig: WebDAVConfig = {
    enabled: false,
    url: '',
    username: '',
    password: '',
    autoSync: false,
    syncInterval: 30,
    folderName: DEFAULT_FOLDER,
    keepHistory: DEFAULT_HISTORY_COUNT,
  };
  const saved = (result[CONFIG_KEY] as WebDAVConfig) || {};
  return { ...defaultConfig, ...saved };
}

// 保存 WebDAV 配置
export async function saveWebDAVConfig(config: WebDAVConfig): Promise<void> {
  await browser.storage.sync.set({ [CONFIG_KEY]: config });
}

// 测试 WebDAV 连接
export async function testWebDAVConnection(config: WebDAVConfig): Promise<{ success: boolean; message: string }> {
  try {
    const response = await fetch(config.url, {
      method: 'PROPFIND',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        'Depth': '0',
      },
    });

    if (response.ok) {
      return { success: true, message: '连接成功' };
    } else if (response.status === 401) {
      return { success: false, message: '认证失败，请检查用户名和密码' };
    } else {
      return { success: false, message: `连接失败: HTTP ${response.status}` };
    }
  } catch (error) {
    return { success: false, message: `连接失败: ${error instanceof Error ? error.message : '未知错误'}` };
  }
}

// 同步数据结构
interface SyncData {
  version: number;
  lastModified: number;
  links: LinkItem[]; // 使用 LinkItem，但上传前会移除图片数据
  customJsConfigs: CustomJsConfig[];
  deviceId: string;
  deleteRecords: DeleteRecord[];
}

// 数据大小限制（MB）
const MAX_SYNC_SIZE_MB = 5;
const WARNING_SIZE_MB = 2;

// 历史版本信息
export interface HistoryVersion {
  fileName: string;
  date: string;
  timestamp: number;
  size?: number;
}

// 估算数据大小（MB）
export function estimateDataSizeMB(data: unknown): number {
  const jsonString = JSON.stringify(data);
  // UTF-8 编码，每个字符约 1-2 字节，中文约 3 字节
  const bytes = new Blob([jsonString]).size;
  return bytes / 1024 / 1024;
}

// 将 LinkItem 转换为不含图片数据的版本（用于同步）
function stripImageData(links: LinkItem[]): LinkItem[] {
  return links.map(link => {
    const { nearbyImage, screenshot, ...rest } = link;
    return rest as LinkItem;
  });
}

// 检查同步数据大小
export interface SizeCheckResult {
  sizeMB: number;
  isOversized: boolean;
  isWarning: boolean;
  linkCount: number;
  estimatedSyncSizeMB: number;
  message: string;
}

export async function checkDataSize(): Promise<SizeCheckResult> {
  const localLinksJson = await exportLinks();
  const localLinks: LinkItem[] = JSON.parse(localLinksJson);
  
  const fullSizeMB = estimateDataSizeMB(localLinks);
  const syncLinks = stripImageData(localLinks);
  const syncSizeMB = estimateDataSizeMB(syncLinks);
  
  const isOversized = fullSizeMB > MAX_SYNC_SIZE_MB;
  const isWarning = fullSizeMB > WARNING_SIZE_MB;
  
  let message = `当前数据：${localLinks.length} 个链接\n`;
  message += `含图片：${fullSizeMB.toFixed(2)} MB\n`;
  message += `同步大小（不含图片）：${syncSizeMB.toFixed(2)} MB`;
  
  if (isOversized) {
    message += `\n⚠️ 数据过大！建议清理旧截图`;
  } else if (isWarning) {
    message += `\n💡 数据较大，清理截图可提升性能`;
  }
  
  return {
    sizeMB: fullSizeMB,
    isOversized,
    isWarning,
    linkCount: localLinks.length,
    estimatedSyncSizeMB: syncSizeMB,
    message,
  };
}

// 获取设备ID
async function getDeviceId(): Promise<string> {
  const result = await browser.storage.local.get('device_id');
  if (result.device_id) return result.device_id as string;
  
  const newId = 'device_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  await browser.storage.local.set({ device_id: newId });
  return newId;
}

// 获取完整的文件路径
function getFilePath(config: WebDAVConfig, fileName: string): string {
  const folder = config.folderName || DEFAULT_FOLDER;
  const baseUrl = config.url.endsWith('/') ? config.url.slice(0, -1) : config.url;
  return `${baseUrl}/${folder}/${fileName}`;
}

// 创建文件夹（如果服务器支持 MKCOL）
async function tryCreateFolder(url: string, config: WebDAVConfig): Promise<boolean> {
  try {
    const response = await fetch(url, {
      method: 'MKCOL',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
      },
    });
    // 201 成功创建，405 已存在，都算是成功
    return response.status === 201 || response.status === 405;
  } catch (error) {
    return false;
  }
}

// 确保文件夹存在（兼容不支持 MKCOL 的服务器）
async function ensureFolderExists(config: WebDAVConfig): Promise<void> {
  const folder = config.folderName || DEFAULT_FOLDER;
  const baseUrl = config.url.endsWith('/') ? config.url.slice(0, -1) : config.url;
  const folderUrl = `${baseUrl}/${folder}`;

  // 尝试创建主文件夹
  const mainCreated = await tryCreateFolder(folderUrl, config);
  if (!mainCreated) {
    console.warn('[ReadLater] Could not create main folder, server may not support MKCOL');
  }

  // 尝试创建子文件夹（如果服务器不支持 MKCOL，这些会失败，但我们继续）
  const subFolders = [HISTORY_FOLDER, IMAGES_FOLDER, DELETED_IMAGES_FOLDER];
  
  for (const subFolder of subFolders) {
    const subUrl = `${folderUrl}/${subFolder}`;
    const created = await tryCreateFolder(subUrl, config);
    if (!created) {
      console.warn(`[ReadLater] Could not create ${subFolder} folder`);
    }
  }
}

// 从 WebDAV 下载数据
export async function downloadFromWebDAV(config: WebDAVConfig, fileName?: string): Promise<SyncData | null> {
  const targetFile = fileName || DATA_FILE_NAME;
  const fileUrl = getFilePath(config, targetFile);
  
  const response = await fetch(fileUrl, {
    method: 'GET',
    headers: {
      'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
    },
  });

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    throw new Error(`下载失败: HTTP ${response.status}`);
  }

  const text = await response.text();
  return JSON.parse(text) as SyncData;
}

// 上传数据到 WebDAV（带历史版本）
export async function uploadToWebDAV(config: WebDAVConfig, data: SyncData, createHistory: boolean = true): Promise<void> {
  // 确保文件夹存在
  await ensureFolderExists(config);

  const fileUrl = getFilePath(config, DATA_FILE_NAME);
  
  // 如果需要创建历史版本
  if (createHistory) {
    await createHistoryVersion(config, data);
  }
  
  const response = await fetch(fileUrl, {
    method: 'PUT',
    headers: {
      'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(data, null, 2),
  });

  if (!response.ok) {
    throw new Error(`上传失败: HTTP ${response.status}`);
  }
}

// 创建历史版本
async function createHistoryVersion(config: WebDAVConfig, data: SyncData): Promise<void> {
  const keepCount = config.keepHistory || DEFAULT_HISTORY_COUNT;
  const date = new Date();
  const dateStr = date.toISOString().slice(0, 10); // YYYY-MM-DD
  const timeStr = date.toTimeString().slice(0, 5).replace(':', '-'); // HH-MM
  const historyFileName = `${HISTORY_FOLDER}/${dateStr}_${timeStr}.json`;
  const historyUrl = getFilePath(config, historyFileName);

  try {
    // 上传历史版本
    const response = await fetch(historyUrl, {
      method: 'PUT',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(data, null, 2),
    });

    if (!response.ok) {
      console.warn('[ReadLater] Failed to create history version:', response.status);
      return;
    }

    console.log('[ReadLater] History version created:', historyFileName);

    // 清理旧版本
    await cleanupOldHistory(config, keepCount);
  } catch (error) {
    console.warn('[ReadLater] History creation warning:', error);
  }
}

// 获取历史版本列表
export async function getHistoryVersions(config: WebDAVConfig): Promise<HistoryVersion[]> {
  const folder = config.folderName || DEFAULT_FOLDER;
  const baseUrl = config.url.endsWith('/') ? config.url.slice(0, -1) : config.url;
  const historyUrl = `${baseUrl}/${folder}/${HISTORY_FOLDER}/`;

  try {
    const response = await fetch(historyUrl, {
      method: 'PROPFIND',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        'Depth': '1',
      },
    });

    if (!response.ok) {
      return [];
    }

    const text = await response.text();
    const parser = new DOMParser();
    const doc = parser.parseFromString(text, 'text/xml');
    const responses = doc.querySelectorAll('response');

    const versions: HistoryVersion[] = [];

    responses.forEach((resp) => {
      const href = resp.querySelector('href')?.textContent || '';
      const displayName = decodeURIComponent(href.split('/').pop() || '');
      
      // 只处理 .json 文件
      if (!displayName.endsWith('.json')) return;

      // 解析文件名中的日期时间 (YYYY-MM-DD_HH-MM.json)
      const match = displayName.match(/(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})\.json/);
      if (match) {
        const dateStr = match[1];
        const hour = match[2];
        const minute = match[3];
        const timestamp = new Date(`${dateStr}T${hour}:${minute}`).getTime();

        versions.push({
          fileName: displayName,
          date: `${dateStr} ${hour}:${minute}`,
          timestamp,
        });
      }
    });

    // 按时间倒序排列
    return versions.sort((a, b) => b.timestamp - a.timestamp);
  } catch (error) {
    console.warn('[ReadLater] Failed to get history:', error);
    return [];
  }
}

// 清理旧的历史版本
async function cleanupOldHistory(config: WebDAVConfig, keepCount: number): Promise<void> {
  const versions = await getHistoryVersions(config);
  
  if (versions.length <= keepCount) return;

  const toDelete = versions.slice(keepCount);
  
  for (const version of toDelete) {
    try {
      const fileUrl = getFilePath(config, `${HISTORY_FOLDER}/${version.fileName}`);
      await fetch(fileUrl, {
        method: 'DELETE',
        headers: {
          'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        },
      });
      console.log('[ReadLater] Deleted old history:', version.fileName);
    } catch (error) {
      console.warn('[ReadLater] Failed to delete old history:', version.fileName, error);
    }
  }
}

// ============ 图片同步功能 ============

// 上传单个图片
async function uploadImage(
  config: WebDAVConfig,
  linkId: string,
  imageType: 'screenshot' | 'nearby',
  imageData: string
): Promise<boolean> {
  try {
    const fileName = `${linkId}_${imageType}.png`;
    const fileUrl = getFilePath(config, `${IMAGES_FOLDER}/${fileName}`);

    // 将 base64 转换为 blob
    const response = await fetch(imageData);
    const blob = await response.blob();

    const uploadResponse = await fetch(fileUrl, {
      method: 'PUT',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        'Content-Type': 'image/png',
      },
      body: blob,
    });

    return uploadResponse.ok;
  } catch (error) {
    console.warn(`[ReadLater] Failed to upload image ${linkId}_${imageType}:`, error);
    return false;
  }
}

// 下载单个图片
async function downloadImage(
  config: WebDAVConfig,
  linkId: string,
  imageType: 'screenshot' | 'nearby'
): Promise<string | null> {
  try {
    const fileName = `${linkId}_${imageType}.png`;
    const fileUrl = getFilePath(config, `${IMAGES_FOLDER}/${fileName}`);

    const response = await fetch(fileUrl, {
      method: 'GET',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
      },
    });

    if (!response.ok) {
      return null;
    }

    const blob = await response.blob();
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  } catch (error) {
    console.warn(`[ReadLater] Failed to download image ${linkId}_${imageType}:`, error);
    return null;
  }
}

// 同步所有图片（上传本地有但云端没有的图片）
async function syncImages(
  config: WebDAVConfig,
  localLinks: LinkItem[],
  direction: 'upload' | 'download' | 'bidirectional' = 'bidirectional'
): Promise<{ uploaded: number; downloaded: number; failed: number }> {
  const result = { uploaded: 0, downloaded: 0, failed: 0 };

  for (const link of localLinks) {
    // 上传截图
    if (link.screenshot) {
      if (direction === 'upload' || direction === 'bidirectional') {
        const success = await uploadImage(config, link.id, 'screenshot', link.screenshot);
        if (success) result.uploaded++;
        else result.failed++;
      }
    }

    // 上传附近图片
    if (link.nearbyImage) {
      if (direction === 'upload' || direction === 'bidirectional') {
        const success = await uploadImage(config, link.id, 'nearby', link.nearbyImage);
        if (success) result.uploaded++;
        else result.failed++;
      }
    }
  }

  return result;
}

// 确保 deleted 文件夹存在
// 注意：某些 WebDAV 服务器（如群晖）不支持 MKCOL，我们尝试多种方法
async function ensureDeletedFolderExists(config: WebDAVConfig): Promise<boolean> {
  try {
    const folder = config.folderName || DEFAULT_FOLDER;
    const baseUrl = config.url.endsWith('/') ? config.url.slice(0, -1) : config.url;
    const deletedUrl = `${baseUrl}/${folder}/${DELETED_IMAGES_FOLDER}`;
    
    // 方法1: 尝试 MKCOL（标准 WebDAV）
    const response = await fetch(deletedUrl, {
      method: 'MKCOL',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
      },
    });
    
    // 201 创建成功，405 已存在，都是正常情况
    if (response.status === 201 || response.status === 405) {
      return true;
    }
    
    // 方法2: 如果 MKCOL 被禁止 (405)，尝试 PUT 一个空文件再删除
    // 某些服务器允许通过 PUT 创建父文件夹
    if (response.status === 405) {
      console.warn('[ReadLater] MKCOL not supported, trying alternative method');
      
      // 尝试直接移动文件，如果目标文件夹不存在，某些服务器会自动创建
      return false; // 返回 false 表示可能不存在，但让移动操作自己处理
    }
    
    return false;
  } catch (error) {
    console.warn('[ReadLater] Error creating deleted folder:', error);
    return false;
  }
}

// 将图片移动到 images/deleted 文件夹（而不是直接删除）
export async function deleteRemoteImage(
  config: WebDAVConfig,
  linkId: string
): Promise<{ moved: number; failed: number; skipped: number }> {
  const result = { moved: 0, failed: 0, skipped: 0 };
  
  try {
    // 尝试创建目标文件夹（某些服务器不支持 MKCOL）
    const folderCreated = await ensureDeletedFolderExists(config);
    
    const timestamp = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    
    for (const imageType of ['screenshot', 'nearby']) {
      const fileName = `${linkId}_${imageType}.png`;
      const sourceUrl = getFilePath(config, `${IMAGES_FOLDER}/${fileName}`);
      const destUrl = getFilePath(config, `${DELETED_IMAGES_FOLDER}/${timestamp}_${fileName}`);
      
      console.log('[ReadLater] Moving image:', sourceUrl, '->', destUrl);
      
      // 使用 MOVE 方法将图片移动到 images/deleted 文件夹
      const response = await fetch(sourceUrl, {
        method: 'MOVE',
        headers: {
          'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
          'Destination': destUrl,
          'Overwrite': 'T',
        },
      });
      
      if (response.ok) {
        console.log(`[ReadLater] Successfully moved image ${fileName}`);
        result.moved++;
      } else if (response.status === 404) {
        // 源文件不存在，跳过
        console.log(`[ReadLater] Source image not found ${fileName}`);
        result.skipped++;
      } else if (response.status === 409) {
        // 409 Conflict - 目标文件夹不存在且无法自动创建
        console.warn(`[ReadLater] Target folder may not exist for ${fileName}:`, response.status);
        result.failed++;
        
        // 尝试回退方案：复制到新位置然后删除原文件
        // 如果服务器不支持 MOVE 或文件夹不存在，我们只能保留原处
      } else {
        console.warn(`[ReadLater] Failed to move image ${fileName}:`, response.status);
        result.failed++;
      }
    }
    
    // 如果移动失败且文件夹未创建，给出警告
    if (result.failed > 0 && !folderCreated) {
      console.warn('[ReadLater] WebDAV server may not support MKCOL. Images remain in original location.');
    }
    
  } catch (error) {
    console.warn(`[ReadLater] Failed to move remote images for ${linkId}:`, error);
    result.failed++;
  }
  
  return result;
}

// 从回收站还原图片（移回 images 文件夹）
export async function restoreRemoteImage(
  config: WebDAVConfig,
  linkId: string,
  deletedDate: string // YYYY-MM-DD
): Promise<boolean> {
  try {
    let success = false;
    
    for (const imageType of ['screenshot', 'nearby']) {
      const fileName = `${linkId}_${imageType}.png`;
      const sourceUrl = getFilePath(config, `${DELETED_IMAGES_FOLDER}/${deletedDate}_${fileName}`);
      const destUrl = getFilePath(config, `${IMAGES_FOLDER}/${fileName}`);
      
      // 使用 MOVE 方法将图片移回 images 文件夹
      const response = await fetch(sourceUrl, {
        method: 'MOVE',
        headers: {
          'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
          'Destination': destUrl,
          'Overwrite': 'T',
        },
      });
      
      if (response.ok) {
        success = true;
      }
    }
    
    return success;
  } catch (error) {
    console.warn(`[ReadLater] Failed to restore remote images for ${linkId}:`, error);
    return false;
  }
}

// 永久删除回收站中的图片
export async function permanentlyDeleteRemoteImage(
  config: WebDAVConfig,
  linkId: string,
  deletedDate: string // YYYY-MM-DD
): Promise<boolean> {
  try {
    let success = true;
    
    for (const imageType of ['screenshot', 'nearby']) {
      const fileName = `${deletedDate}_${linkId}_${imageType}.png`;
      const fileUrl = getFilePath(config, `${DELETED_IMAGES_FOLDER}/${fileName}`);
      
      const response = await fetch(fileUrl, {
        method: 'DELETE',
        headers: {
          'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        },
      });
      
      if (!response.ok && response.status !== 404) {
        success = false;
      }
    }
    
    return success;
  } catch (error) {
    console.warn(`[ReadLater] Failed to permanently delete remote images for ${linkId}:`, error);
    return false;
  }
}

// 清理旧的已删除图片（保留最近 N 天）
export async function cleanupDeletedImages(
  config: WebDAVConfig,
  keepDays: number = 30
): Promise<{ deleted: number; errors: number }> {
  const result = { deleted: 0, errors: 0 };
  
  try {
    const folder = config.folderName || DEFAULT_FOLDER;
    const baseUrl = config.url.endsWith('/') ? config.url.slice(0, -1) : config.url;
    const deletedUrl = `${baseUrl}/${folder}/${DELETED_IMAGES_FOLDER}/`;
    
    const response = await fetch(deletedUrl, {
      method: 'PROPFIND',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        'Depth': '1',
      },
    });
    
    if (!response.ok) {
      return result;
    }
    
    const text = await response.text();
    const parser = new DOMParser();
    const doc = parser.parseFromString(text, 'text/xml');
    const responses = doc.querySelectorAll('response');
    
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - keepDays);
    
    for (const resp of responses) {
      const href = resp.querySelector('href')?.textContent || '';
      const displayName = decodeURIComponent(href.split('/').pop() || '');
      
      if (!displayName.endsWith('.png')) continue;
      
      // 解析文件名中的日期 (YYYY-MM-DD_linkId_*.png)
      const match = displayName.match(/^(\d{4}-\d{2}-\d{2})_/);
      if (match) {
        const fileDate = new Date(match[1]);
        if (fileDate < cutoffDate) {
          // 删除过期文件
          const fileUrl = getFilePath(config, `${DELETED_IMAGES_FOLDER}/${displayName}`);
          const deleteResponse = await fetch(fileUrl, {
            method: 'DELETE',
            headers: {
              'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
            },
          });
          
          if (deleteResponse.ok) {
            result.deleted++;
          } else {
            result.errors++;
          }
        }
      }
    }
  } catch (error) {
    console.error('[ReadLater] Failed to cleanup deleted images:', error);
    result.errors++;
  }
  
  return result;
}

// 获取回收站中的图片列表
export async function getDeletedImages(
  config: WebDAVConfig
): Promise<{ linkId: string; date: string; hasScreenshot: boolean; hasNearby: boolean }[]> {
  const result: { linkId: string; date: string; hasScreenshot: boolean; hasNearby: boolean }[] = [];
  
  try {
    const folder = config.folderName || DEFAULT_FOLDER;
    const baseUrl = config.url.endsWith('/') ? config.url.slice(0, -1) : config.url;
    const deletedUrl = `${baseUrl}/${folder}/${DELETED_IMAGES_FOLDER}/`;
    
    const response = await fetch(deletedUrl, {
      method: 'PROPFIND',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
        'Depth': '1',
      },
    });
    
    if (!response.ok) {
      return result;
    }
    
    const text = await response.text();
    const parser = new DOMParser();
    const doc = parser.parseFromString(text, 'text/xml');
    const responses = doc.querySelectorAll('response');
    
    const linkMap = new Map<string, { date: string; hasScreenshot: boolean; hasNearby: boolean }>();
    
    for (const resp of responses) {
      const href = resp.querySelector('href')?.textContent || '';
      const displayName = decodeURIComponent(href.split('/').pop() || '');
      
      // 解析文件名: YYYY-MM-DD_linkId_screenshot.png 或 YYYY-MM-DD_linkId_nearby.png
      const match = displayName.match(/^(\d{4}-\d{2}-\d{2})_(.+)_(screenshot|nearby)\.png$/);
      if (match) {
        const date = match[1];
        const linkId = match[2];
        const imageType = match[3];
        
        const existing = linkMap.get(linkId);
        if (existing) {
          if (imageType === 'screenshot') existing.hasScreenshot = true;
          if (imageType === 'nearby') existing.hasNearby = true;
        } else {
          linkMap.set(linkId, {
            date,
            hasScreenshot: imageType === 'screenshot',
            hasNearby: imageType === 'nearby',
          });
        }
      }
    }
    
    for (const [linkId, data] of linkMap) {
      result.push({ linkId, ...data });
    }
    
    // 按日期倒序排列
    return result.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  } catch (error) {
    console.error('[ReadLater] Failed to get deleted images:', error);
    return result;
  }
}

// 恢复到指定历史版本
export async function restoreFromHistory(
  config: WebDAVConfig, 
  version: HistoryVersion
): Promise<{ success: boolean; message: string; imported?: number }> {
  try {
    const filePath = `${HISTORY_FOLDER}/${version.fileName}`;
    const data = await downloadFromWebDAV(config, filePath);
    
    if (!data) {
      return { success: false, message: '无法读取历史版本文件' };
    }

    // 导入数据
    const linksJson = JSON.stringify(data.links);
    const result = await importLinks(linksJson, 'replace');

    // 恢复配置
    if (data.customJsConfigs) {
      for (const cfg of data.customJsConfigs) {
        await saveCustomJsConfig(cfg);
      }
    }

    // 将恢复的数据作为新版本上传
    await uploadToWebDAV(config, data, true);

    return {
      success: true,
      message: `成功恢复到 ${version.date} 的版本`,
      imported: result.imported,
    };
  } catch (error) {
    return {
      success: false,
      message: `恢复失败: ${error instanceof Error ? error.message : '未知错误'}`,
    };
  }
}

// 删除历史版本
export async function deleteHistoryVersion(
  config: WebDAVConfig, 
  version: HistoryVersion
): Promise<boolean> {
  try {
    const fileUrl = getFilePath(config, `${HISTORY_FOLDER}/${version.fileName}`);
    const response = await fetch(fileUrl, {
      method: 'DELETE',
      headers: {
        'Authorization': 'Basic ' + btoa(config.username + ':' + config.password),
      },
    });
    return response.ok || response.status === 404;
  } catch (error) {
    console.warn('[ReadLater] Failed to delete history:', error);
    return false;
  }
}

// 执行同步（双向合并+删除同步模式）
export interface SyncResult {
  success: boolean;
  direction: 'upload' | 'download' | 'merge' | 'none' | 'conflict';
  message: string;
  details?: {
    uploaded?: number;
    downloaded?: number;
    merged?: number;
    deleted?: number;
    imagesUploaded?: number;
    localCount?: number;
    remoteCount?: number;
    totalCount?: number;
  };
}

export async function syncWithWebDAV(config?: WebDAVConfig): Promise<SyncResult> {
  const webdavConfig = config || await getWebDAVConfig();
  
  if (!webdavConfig.enabled || !webdavConfig.url) {
    return { success: false, direction: 'none', message: 'WebDAV 未启用' };
  }

  try {
    // 确保文件夹存在
    await ensureFolderExists(webdavConfig);

    // 准备本地数据
    const localLinksJson = await exportLinks();
    const localLinks: LinkItem[] = JSON.parse(localLinksJson);
    const localConfigs = await getCustomJsConfigs();
    const localDeleteRecords = await getDeleteRecords();
    const deviceId = await getDeviceId();

    // 尝试下载远程数据
    let remoteData: SyncData | null = null;
    try {
      remoteData = await downloadFromWebDAV(webdavConfig);
    } catch (error) {
      console.warn('[ReadLater] Download failed:', error);
    }

    // 如果远程没有数据，直接上传本地数据
    if (!remoteData) {
      // 上传元数据（不含图片）
      const localData: SyncData = {
        version: 2,
        lastModified: Date.now(),
        links: stripImageData(localLinks),
        customJsConfigs: localConfigs,
        deviceId,
        deleteRecords: localDeleteRecords,
      };
      
      await uploadToWebDAV(webdavConfig, localData, true);
      
      // 上传图片文件
      const imageResult = await syncImages(webdavConfig, localLinks, 'upload');
      
      webdavConfig.lastSyncTime = Date.now();
      await saveWebDAVConfig(webdavConfig);

      return {
        success: true,
        direction: 'upload',
        message: `首次同步，已上传 ${localLinks.length} 个链接，${imageResult.uploaded} 张图片`,
        details: {
          uploaded: localLinks.length,
          imagesUploaded: imageResult.uploaded,
          localCount: localLinks.length,
          totalCount: localLinks.length,
        },
      };
    }

    // 合并删除记录
    const remoteDeleteRecords = remoteData.deleteRecords || [];
    const allDeleteRecords = mergeDeleteRecords(localDeleteRecords, remoteDeleteRecords);
    
    // 应用删除操作
    const localLinksAfterDelete = applyDeletions(localLinks, remoteDeleteRecords);
    const remoteLinksAfterDelete = applyDeletions(remoteData.links, localDeleteRecords);
    
    // 合并链接
    const mergedResult = mergeLinks(localLinksAfterDelete, remoteLinksAfterDelete);
    
    const localDeletedCount = localLinks.length - localLinksAfterDelete.length;
    const remoteDeletedCount = remoteData.links.length - remoteLinksAfterDelete.length;
    const totalDeleted = localDeletedCount + remoteDeletedCount;
    
    // 合并配置
    const mergedConfigs = mergeConfigs(localConfigs, remoteData.customJsConfigs || []);

    // 准备合并后的数据（移除图片数据，减小 JSON 体积）
    const mergedData: SyncData = {
      version: 2,
      lastModified: Date.now(),
      links: stripImageData(mergedResult.links),
      customJsConfigs: mergedConfigs,
      deviceId,
      deleteRecords: allDeleteRecords,
    };

    // 上传合并后的元数据（创建历史版本）
    await uploadToWebDAV(webdavConfig, mergedData, true);

    // 同步图片文件（本地图片上传到云端）
    const imageResult = await syncImages(webdavConfig, mergedResult.links, 'upload');

    // 更新本地数据库（保留本地图片）
    await importLinks(JSON.stringify(mergedResult.links) as any, 'replace');

    // 保存合并后的配置
    for (const config of mergedConfigs) {
      await saveCustomJsConfig(config);
    }

    // 清理30天前的删除记录
    const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
    await clearOldDeleteRecords(thirtyDaysAgo);
    
    // 清理30天前的已删除图片
    await cleanupDeletedImages(webdavConfig, 30);

    webdavConfig.lastSyncTime = Date.now();
    await saveWebDAVConfig(webdavConfig);

    const hasChanges = mergedResult.localAdded > 0 || mergedResult.remoteAdded > 0 || totalDeleted > 0 || imageResult.uploaded > 0;

    if (hasChanges) {
      return {
        success: true,
        direction: 'merge',
        message: `同步完成：新增 ${mergedResult.localAdded + mergedResult.remoteAdded} 个，删除 ${totalDeleted} 个，上传 ${imageResult.uploaded} 张图片`,
        details: {
          uploaded: mergedResult.localAdded,
          downloaded: mergedResult.remoteAdded,
          merged: mergedResult.localAdded + mergedResult.remoteAdded,
          deleted: totalDeleted,
          imagesUploaded: imageResult.uploaded,
          localCount: localLinks.length,
          remoteCount: remoteData.links.length,
          totalCount: mergedResult.links.length,
        },
      };
    }

    return {
      success: true,
      direction: 'none',
      message: '数据已是最新，无需同步',
      details: {
        localCount: localLinks.length,
        remoteCount: remoteData.links.length,
        totalCount: mergedResult.links.length,
      },
    };

  } catch (error) {
    console.error('[ReadLater] Sync failed:', error);
    return {
      success: false,
      direction: 'none',
      message: `同步失败: ${error instanceof Error ? error.message : '未知错误'}`,
    };
  }
}

// 合并两个链接列表
interface MergeResult {
  links: LinkItem[];
  localAdded: number;
  remoteAdded: number;
}

function mergeLinks(localLinks: LinkItem[], remoteLinks: LinkItem[]): MergeResult {
  const urlMap = new Map<string, LinkItem>();
  let localAdded = 0;
  let remoteAdded = 0;

  for (const link of localLinks) {
    const normalizedUrl = normalizeUrl(link.url);
    if (!urlMap.has(normalizedUrl)) {
      urlMap.set(normalizedUrl, link);
    }
  }

  for (const link of remoteLinks) {
    const normalizedUrl = normalizeUrl(link.url);
    if (!urlMap.has(normalizedUrl)) {
      urlMap.set(normalizedUrl, link);
      remoteAdded++;
    }
  }

  for (const link of localLinks) {
    const normalizedUrl = normalizeUrl(link.url);
    const existsInRemote = remoteLinks.some(r => normalizeUrl(r.url) === normalizedUrl);
    if (!existsInRemote) {
      localAdded++;
    }
  }

  const mergedLinks = Array.from(urlMap.values());
  mergedLinks.sort((a, b) => b.createdAt - a.createdAt);

  return {
    links: mergedLinks,
    localAdded,
    remoteAdded,
  };
}

// 合并配置
function mergeConfigs(localConfigs: CustomJsConfig[], remoteConfigs: CustomJsConfig[]): CustomJsConfig[] {
  const configMap = new Map<string, CustomJsConfig>();
  
  for (const config of [...localConfigs, ...remoteConfigs]) {
    const existing = configMap.get(config.id);
    if (!existing) {
      configMap.set(config.id, config);
    }
  }

  return Array.from(configMap.values());
}

// 合并删除记录
function mergeDeleteRecords(local: DeleteRecord[], remote: DeleteRecord[]): DeleteRecord[] {
  const recordMap = new Map<string, DeleteRecord>();
  
  for (const record of [...local, ...remote]) {
    const existing = recordMap.get(record.normalizedUrl);
    if (!existing || record.deletedAt > existing.deletedAt) {
      recordMap.set(record.normalizedUrl, record);
    }
  }

  return Array.from(recordMap.values());
}

// 应用删除操作
function applyDeletions(links: LinkItem[], deleteRecords: DeleteRecord[]): LinkItem[] {
  const deletedUrls = new Set(deleteRecords.map(r => r.normalizedUrl));
  return links.filter(link => !deletedUrls.has(normalizeUrl(link.url)));
}

// 强制下载（覆盖本地）
export async function forceDownloadFromWebDAV(config?: WebDAVConfig): Promise<SyncResult> {
  const webdavConfig = config || await getWebDAVConfig();
  
  if (!webdavConfig.enabled || !webdavConfig.url) {
    return { success: false, direction: 'none', message: 'WebDAV 未启用' };
  }

  try {
    const remoteData = await downloadFromWebDAV(webdavConfig);
    
    if (!remoteData) {
      return { success: false, direction: 'none', message: '云端没有数据' };
    }

    const remoteLinksJson = JSON.stringify(remoteData.links);
    const importResult = await importLinks(remoteLinksJson, 'replace');

    if (remoteData.customJsConfigs) {
      for (const config of remoteData.customJsConfigs) {
        await saveCustomJsConfig(config);
      }
    }

    webdavConfig.lastSyncTime = Date.now();
    await saveWebDAVConfig(webdavConfig);

    const deletedCount = remoteData.deleteRecords?.length || 0;

    return {
      success: true,
      direction: 'download',
      message: `已从云端下载 ${importResult.imported} 个链接${deletedCount > 0 ? `（含 ${deletedCount} 条删除记录）` : ''}（覆盖本地）`,
      details: {
        downloaded: importResult.imported,
        deleted: deletedCount,
        totalCount: importResult.imported,
      },
    };

  } catch (error) {
    return {
      success: false,
      direction: 'none',
      message: `下载失败: ${error instanceof Error ? error.message : '未知错误'}`,
    };
  }
}

// 强制上传（覆盖远程）
export async function forceUploadToWebDAV(config?: WebDAVConfig): Promise<SyncResult> {
  const webdavConfig = config || await getWebDAVConfig();
  
  if (!webdavConfig.enabled || !webdavConfig.url) {
    return { success: false, direction: 'none', message: 'WebDAV 未启用' };
  }

  try {
    const localLinksJson = await exportLinks();
    const localLinks: LinkItem[] = JSON.parse(localLinksJson);
    const localConfigs = await getCustomJsConfigs();
    const localDeleteRecords = await getDeleteRecords();
    const deviceId = await getDeviceId();

    // 上传元数据（不含图片）
    const localData: SyncData = {
      version: 2,
      lastModified: Date.now(),
      links: stripImageData(localLinks),
      customJsConfigs: localConfigs,
      deviceId,
      deleteRecords: localDeleteRecords,
    };

    await uploadToWebDAV(webdavConfig, localData, true);

    // 上传图片
    const imageResult = await syncImages(webdavConfig, localLinks, 'upload');

    webdavConfig.lastSyncTime = Date.now();
    await saveWebDAVConfig(webdavConfig);

    return {
      success: true,
      direction: 'upload',
      message: `已上传 ${localLinks.length} 个链接，${imageResult.uploaded} 张图片${localDeleteRecords.length > 0 ? `（含 ${localDeleteRecords.length} 条删除记录）` : ''}到云端（覆盖远程）`,
      details: {
        uploaded: localLinks.length,
        imagesUploaded: imageResult.uploaded,
        deleted: localDeleteRecords.length,
      },
    };

  } catch (error) {
    return {
      success: false,
      direction: 'none',
      message: `上传失败: ${error instanceof Error ? error.message : '未知错误'}`,
    };
  }
}

// 设置自动同步
let syncIntervalId: NodeJS.Timeout | null = null;

export async function setupAutoSync(): Promise<void> {
  if (syncIntervalId) {
    clearInterval(syncIntervalId);
    syncIntervalId = null;
  }

  const config = await getWebDAVConfig();
  
  if (!config.enabled || !config.autoSync || config.syncInterval < 1) {
    return;
  }

  syncIntervalId = setInterval(async () => {
    console.log('[ReadLater] Auto sync started');
    const result = await syncWithWebDAV(config);
    console.log('[ReadLater] Auto sync result:', result);
  }, config.syncInterval * 60 * 1000);

  console.log(`[ReadLater] Auto sync enabled, interval: ${config.syncInterval} minutes`);
}

// 初始化自动同步
export async function initWebDAV(): Promise<void> {
  await setupAutoSync();
}
