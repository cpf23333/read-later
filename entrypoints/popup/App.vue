<script lang="ts" setup>
import { ref, onMounted } from 'vue';
import { getLinkCount, isLinkExists, addLink } from '@/utils/hybridStorage';
import { showSuccess, showError, showWarning } from '@/utils/toast';
import ThemeToggle from '@/components/ThemeToggle.vue';

const linkCount = ref(0);
const saving = ref(false);

onMounted(async () => {
  await loadLinkCount();
});

async function loadLinkCount() {
  linkCount.value = await getLinkCount();
}

async function openLinkManager() {
  console.log('[Popup] Opening link manager...');
  try {
    await browser.runtime.sendMessage({ type: 'OPEN_LINK_MANAGER' });
    console.log('[Popup] Link manager opened');
    window.close();
  } catch (error) {
    console.error('[Popup] Failed to open link manager:', error);
    showError('打开失败: ' + (error instanceof Error ? error.message : '未知错误'));
  }
}

async function openSettings() {
  console.log('[Popup] Opening settings...');
  try {
    await browser.runtime.sendMessage({ type: 'OPEN_SETTINGS' });
    console.log('[Popup] Settings opened');
    window.close();
  } catch (error) {
    console.error('[Popup] Failed to open settings:', error);
    showError('打开失败: ' + (error instanceof Error ? error.message : '未知错误'));
  }
}

async function saveCurrentPage() {
  saving.value = true;
  try {
    console.log('[Popup] Starting saveCurrentPage...');
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    console.log('[Popup] Got tab:', tab?.id, tab?.url);
    if (!tab?.id || !tab.url) {
      console.warn('[Popup] No tab or URL found');
      return;
    }

    // 检查是否已存在
    console.log('[Popup] Checking if link exists...');
    const exists = await isLinkExists(tab.url);
    console.log('[Popup] Link exists:', exists);
    if (exists) {
      showWarning('该页面已经在"稍后再看"列表中了！');
      return;
    }

    // 获取页面标题
    console.log('[Popup] Fetching title...');
    const titleResult = await browser.runtime.sendMessage({
      type: 'FETCH_TITLE',
      url: tab.url,
    });
    console.log('[Popup] Title result:', titleResult);

    // 获取截图
    console.log('[Popup] Capturing tab...');
    const screenshotResult = await browser.runtime.sendMessage({
      type: 'CAPTURE_TAB',
    });
    console.log('[Popup] Screenshot result:', screenshotResult);
    console.log('[Popup] Screenshot data length:', screenshotResult?.data?.length || 0);

    // 保存链接
    console.log('[Popup] Adding link with data:', {
      url: tab.url,
      screenshot: screenshotResult?.data ? `${screenshotResult.data.substring(0, 50)}...` : null,
    });
    await addLink({
      url: tab.url,
      title: titleResult?.data || tab.title || tab.url,
      nearbyImage: null,
      screenshot: screenshotResult?.data || null,
      sourcePage: tab.url,
    });
    console.log('[Popup] Link added successfully');

    await loadLinkCount();

    // 显示成功提示
    showSuccess('已收好！稍后记得来看哦~');
  } catch (error) {
    console.error('[Popup] Failed to save current page:', error);
    showError('保存失败: ' + (error instanceof Error ? error.message : '未知错误'));
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="popup-container">
    <header class="header">
      <div class="header-left">
        <h1>稍后再看</h1>
        <span class="badge">{{ linkCount }} 个链接</span>
      </div>
      <ThemeToggle />
    </header>

    <main class="main">
      <p class="description">看到好内容来不及看？右键或长按链接收好，稍后有空再看</p>

      <div class="actions">
        <button class="btn btn-primary" @click="saveCurrentPage" :disabled="saving">
          {{ saving ? '收好中...' : '📥 收好当前页面' }}
        </button>

        <button class="btn btn-secondary" @click="openLinkManager">📚 查看列表</button>

        <button class="btn btn-default" @click="openSettings">⚙️ 设置</button>
      </div>

      <div class="tips">
        <h3>💡 使用提示</h3>
        <ul>
          <li>PC端：右键点击链接</li>
          <li>安卓端：长按链接</li>
          <li>自动保存页面截图</li>
          <li>多设备同步随时看</li>
        </ul>
      </div>
    </main>

    <footer class="footer">
      <a href="#" @click.prevent="openSettings">配置服务器同步 →</a>
    </footer>
  </div>
</template>

<style scoped>
.popup-container {
  width: 340px;
  background: var(--rl-bg-elevated);
  border-radius: 0 0 16px 16px;
  overflow: hidden;
}

.header {
  background: linear-gradient(135deg, var(--rl-primary) 0%, var(--rl-secondary) 100%);
  color: white;
  padding: 24px 20px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.header h1 {
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -0.02em;
}

.badge {
  background: rgba(255, 255, 255, 0.25);
  padding: 4px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 500;
  backdrop-filter: blur(4px);
}

.main {
  padding: 20px;
}

.description {
  font-size: 13px;
  color: var(--rl-text-muted);
  margin-bottom: 18px;
  line-height: 1.6;
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
  border-radius: 10px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
}

.btn-primary {
  background: linear-gradient(135deg, var(--rl-primary) 0%, var(--rl-secondary) 100%);
  color: white;
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.35);
}

.btn-primary:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: 0 6px 16px rgba(102, 126, 234, 0.45);
}

.btn-secondary {
  background: var(--rl-bg-hover);
  color: var(--rl-text-secondary);
}

.btn-secondary:hover {
  background: var(--rl-border);
}

.btn-default {
  background: transparent;
  color: var(--rl-text-muted);
  border: 1px solid var(--rl-border);
}

.btn-default:hover {
  background: var(--rl-bg-subtle);
  border-color: var(--rl-border-strong);
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  transform: none;
  box-shadow: none;
}

.tips {
  background: var(--rl-bg-subtle);
  border: 1px solid var(--rl-border);
  padding: 16px;
  border-radius: 12px;
}

.tips h3 {
  font-size: 13px;
  font-weight: 600;
  color: var(--rl-text-secondary);
  margin-bottom: 12px;
  display: flex;
  align-items: center;
  gap: 6px;
}

.tips ul {
  list-style: none;
  font-size: 12px;
  color: var(--rl-text-muted);
}

.tips li {
  padding: 5px 0;
  padding-left: 18px;
  position: relative;
}

.tips li::before {
  content: '✓';
  position: absolute;
  left: 0;
  color: var(--rl-success);
  font-weight: 600;
}

.footer {
  padding: 14px 20px;
  border-top: 1px solid var(--rl-border);
  text-align: center;
  background: var(--rl-bg-subtle);
}

.footer a {
  font-size: 13px;
  color: var(--rl-primary);
  text-decoration: none;
  font-weight: 500;
}

.footer a:hover {
  text-decoration: underline;
}
</style>
