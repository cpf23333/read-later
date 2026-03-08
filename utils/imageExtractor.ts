// 图片提取工具 - 支持自定义JS代码获取链接附近的图片

export interface ImageExtractionResult {
  url: string | null;
  base64: string | null;
  error?: string;
}

// 默认的图片提取逻辑
export function defaultImageExtractor(targetElement: HTMLElement): string | null {
  // 1. 尝试获取链接本身的图片（如果是图片链接）
  if (targetElement.tagName === 'IMG') {
    return (targetElement as HTMLImageElement).src;
  }

  // 2. 尝试获取链接内部的图片
  const imgInLink = targetElement.querySelector('img');
  if (imgInLink) {
    return imgInLink.src;
  }

  // 3. 尝试获取父元素中的图片
  const parent = targetElement.parentElement;
  if (parent) {
    const imgInParent = parent.querySelector('img');
    if (imgInParent) {
      return imgInParent.src;
    }
  }

  // 4. 尝试获取相邻兄弟元素中的图片
  const prevSibling = targetElement.previousElementSibling;
  if (prevSibling && prevSibling.tagName === 'IMG') {
    return (prevSibling as HTMLImageElement).src;
  }

  const nextSibling = targetElement.nextElementSibling;
  if (nextSibling && nextSibling.tagName === 'IMG') {
    return (nextSibling as HTMLImageElement).src;
  }

  // 5. 向上查找3层，寻找包含图片的容器
  let current: HTMLElement | null = targetElement;
  for (let i = 0; i < 3 && current; i++) {
    current = current.parentElement;
    if (current) {
      const img = current.querySelector('img');
      if (img) {
        return img.src;
      }
    }
  }

  return null;
}

// 执行自定义JS代码提取图片
export function executeCustomExtractor(
  customCode: string,
  targetElement: HTMLElement,
  url: string
): string | null {
  try {
    // 创建安全的执行环境
    const extractorFn = new Function(
      'element',
      'url',
      'document',
      'window',
      `
        ${customCode}
        // 如果代码定义了 extractImage 函数，则调用它
        if (typeof extractImage === 'function') {
          return extractImage(element, url);
        }
        // 否则返回最后一个表达式的值
        return undefined;
      `
    );

    const result = extractorFn(targetElement, url, document, window);
    
    if (typeof result === 'string') {
      return result;
    }
    
    return null;
  } catch (error) {
    console.error('[ReadLater] Custom image extractor error:', error);
    return null;
  }
}

// 将图片URL转换为base64
export async function imageToBase64(url: string): Promise<string | null> {
  try {
    // 检查是否是data URL
    if (url.startsWith('data:')) {
      return url;
    }

    // 检查是否是blob URL
    if (url.startsWith('blob:')) {
      console.log('[ReadLater] Converting blob URL:', url);
      try {
        // 在内容脚本中可以直接fetch blob URL
        const response = await fetch(url);
        console.log('[ReadLater] Blob fetch response:', response.status, response.type);
        const blob = await response.blob();
        console.log('[ReadLater] Blob size:', blob.size, 'type:', blob.type);
        
        // 检查文件大小
        if (blob.size > 5 * 1024 * 1024) {
          console.warn('[ReadLater] Blob image too large');
          return null;
        }
        
        const result = await new Promise<string | null>((resolve, reject) => {
          const reader = new FileReader();
          reader.onloadend = () => {
            const base64 = reader.result as string;
            console.log('[ReadLater] Blob converted to base64, length:', base64.length);
            resolve(base64);
          };
          reader.onerror = (e) => {
            console.error('[ReadLater] FileReader error:', e);
            reject(e);
          };
          reader.readAsDataURL(blob);
        });
        return result;
      } catch (e) {
        console.warn('[ReadLater] Failed to fetch blob URL:', e);
        return null; // blob URL 无法转换，直接返回 null
      }
    }

    // 使用fetch获取图片
    const response = await fetch(url, {
      mode: 'cors',
      credentials: 'omit',
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const blob = await response.blob();
    
    // 检查文件大小（限制5MB）
    if (blob.size > 5 * 1024 * 1024) {
      console.warn('[ReadLater] Image too large, skipping base64 conversion');
      return url; // 返回原URL
    }

    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  } catch (error) {
    console.warn('[ReadLater] Failed to convert image to base64:', error);
    return url; // 失败时返回原URL
  }
}

// 主提取函数
export async function extractNearbyImage(
  targetElement: HTMLElement,
  url: string,
  customCode?: string | null
): Promise<ImageExtractionResult> {
  let imageUrl: string | null = null;

  // 1. 如果提供了自定义代码，先尝试使用
  if (customCode) {
    try {
      imageUrl = executeCustomExtractor(customCode, targetElement, url);
    } catch (error) {
      console.error('[ReadLater] Custom extractor failed:', error);
    }
  }

  // 2. 如果自定义代码没有返回结果，使用默认逻辑
  if (!imageUrl) {
    imageUrl = defaultImageExtractor(targetElement);
  }

  // 3. 转换图片为base64
  if (imageUrl) {
    const base64 = await imageToBase64(imageUrl);
    return {
      url: imageUrl,
      base64: base64,
    };
  }

  return {
    url: null,
    base64: null,
  };
}

// 预定义的提取器模板
export const EXTRACTOR_TEMPLATES = [
  {
    name: '默认提取器',
    description: '自动查找链接内、父元素或相邻位置的图片',
    code: `// 使用默认逻辑，无需自定义代码
return null;`,
  },
  {
    name: '父容器查找',
    description: '在父容器的所有子元素中查找图片',
    code: `function extractImage(element, url) {
  // 向上查找2层父元素
  let container = element;
  for (let i = 0; i < 2; i++) {
    container = container.parentElement;
    if (!container) break;
  }
  
  if (container) {
    // 在容器内查找所有图片
    const images = container.querySelectorAll('img');
    // 返回最大的一张图片
    let maxSize = 0;
    let bestImg = null;
    images.forEach(img => {
      const size = img.width * img.height;
      if (size > maxSize) {
        maxSize = size;
        bestImg = img;
      }
    });
    return bestImg ? bestImg.src : null;
  }
  return null;
}`,
  },
  {
    name: '懒加载图片支持',
    description: '支持 data-src、data-original 等懒加载属性',
    code: `function extractImage(element, url) {
  // 查找最近的图片元素
  let img = element.querySelector('img');
  if (!img) {
    img = element.parentElement?.querySelector('img');
  }
  
  if (img) {
    // 优先获取懒加载属性
    return img.dataset.src || 
           img.dataset.original || 
           img.dataset.lazy || 
           img.src;
  }
  return null;
}`,
  },
  {
    name: '背景图片提取',
    description: '提取元素的 background-image 样式',
    code: `function extractImage(element, url) {
  // 检查链接自身的背景图
  const style = window.getComputedStyle(element);
  let bgImage = style.backgroundImage;
  
  if (!bgImage || bgImage === 'none') {
    // 检查父元素的背景图
    const parent = element.parentElement;
    if (parent) {
      const parentStyle = window.getComputedStyle(parent);
      bgImage = parentStyle.backgroundImage;
    }
  }
  
  // 提取 URL
  if (bgImage && bgImage !== 'none') {
    const match = bgImage.match(/url\(["']?([^"')]+)["']?\)/);
    if (match) return match[1];
  }
  
  return null;
}`,
  },
  {
    name: '社交媒体卡片',
    description: '提取 Open Graph 或 Twitter Card 图片',
    code: `function extractImage(element, url) {
  // 获取页面中的 meta 标签图片
  const ogImage = document.querySelector('meta[property="og:image"]');
  if (ogImage) {
    return ogImage.content;
  }
  
  const twitterImage = document.querySelector('meta[name="twitter:image"]');
  if (twitterImage) {
    return twitterImage.content;
  }
  
  return null;
}`,
  },
];
