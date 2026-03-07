<script lang="ts" setup>
import { ref, onMounted } from 'vue';
import { getLinkCount, isLinkExists, addLink } from '@/utils/storage';

const linkCount = ref(0);
const saving = ref(false);

onMounted(async () => {
  await loadLinkCount();
});

async function loadLinkCount() {
  linkCount.value = await getLinkCount();
}

async function openLinkManager() {
  await browser.runtime.sendMessage({ type: 'OPEN_LINK_MANAGER' });
  window.close();
}

async function openSettings() {
  await browser.runtime.sendMessage({ type: 'OPEN_SETTINGS' });
  window.close();
}

async function saveCurrentPage() {
  saving.value = true;
  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !tab.url) return;

    // 检查是否已存在
    const exists = await isLinkExists(tab.url);
    if (exists) {
      alert('⚠️ 该页面已经在收藏夹中了！');
      return;
    }

    // 获取页面标题
    const titleResult = await browser.runtime.sendMessage({
      type: 'FETCH_TITLE',
      url: tab.url,
    });

    // 获取截图
    const screenshotResult = await browser.runtime.sendMessage({
      type: 'CAPTURE_TAB',
    });

    // 保存链接
    await addLink({
      url: tab.url,
      title: titleResult.data || tab.title || tab.url,
      nearbyImage: null,
      screenshot: screenshotResult.data,
      sourcePage: tab.url,
    });

    await loadLinkCount();
    
    // 显示成功提示
    alert('✅ 当前页面已保存！');
  } catch (error) {
    console.error('Failed to save current page:', error);
    alert('❌ 保存失败，请重试');
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="popup-container">
    <header class="header">
      <h1>UrlMem</h1>
      <span class="badge">{{ linkCount }} 个链接</span>
    </header>

    <main class="main">
      <p class="description">
        右键点击网页中的链接，选择"收藏链接到 UrlMem"即可保存
      </p>

      <div class="actions">
        <button class="btn btn-primary" @click="saveCurrentPage" :disabled="saving">
          {{ saving ? '保存中...' : '收藏当前页面' }}
        </button>
        
        <button class="btn btn-secondary" @click="openLinkManager">
          管理链接
        </button>
        
        <button class="btn btn-default" @click="openSettings">
          设置
        </button>
      </div>

      <div class="tips">
        <h3>使用提示</h3>
        <ul>
          <li>PC端：右键点击链接</li>
          <li>安卓端：长按链接</li>
          <li>自动保存页面截图</li>
          <li>自动提取附近图片</li>
        </ul>
      </div>
    </main>

    <footer class="footer">
      <a href="#" @click.prevent="openSettings">自定义图片提取规则 →</a>
    </footer>
  </div>
</template>

<style scoped>
.popup-container {
  width: 320px;
  background: #fff;
}

.header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 20px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.header h1 {
  font-size: 20px;
  font-weight: 600;
}

.badge {
  background: rgba(255,255,255,0.2);
  padding: 4px 10px;
  border-radius: 20px;
  font-size: 12px;
}

.main {
  padding: 20px;
}

.description {
  font-size: 13px;
  color: #6b7280;
  margin-bottom: 16px;
  line-height: 1.5;
}

.actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-bottom: 20px;
}

.btn {
  padding: 12px 16px;
  border: none;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-primary {
  background: #667eea;
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background: #5568d3;
}

.btn-secondary {
  background: #f3f4f6;
  color: #374151;
}

.btn-secondary:hover {
  background: #e5e7eb;
}

.btn-default {
  background: transparent;
  color: #6b7280;
  border: 1px solid #e5e7eb;
}

.btn-default:hover {
  background: #f9fafb;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.tips {
  background: #f9fafb;
  padding: 16px;
  border-radius: 8px;
}

.tips h3 {
  font-size: 13px;
  font-weight: 600;
  color: #374151;
  margin-bottom: 10px;
}

.tips ul {
  list-style: none;
  font-size: 12px;
  color: #6b7280;
}

.tips li {
  padding: 4px 0;
  padding-left: 16px;
  position: relative;
}

.tips li::before {
  content: '•';
  position: absolute;
  left: 4px;
  color: #667eea;
}

.footer {
  padding: 12px 20px;
  border-top: 1px solid #e5e7eb;
  text-align: center;
}

.footer a {
  font-size: 13px;
  color: #667eea;
  text-decoration: none;
}

.footer a:hover {
  text-decoration: underline;
}
</style>
