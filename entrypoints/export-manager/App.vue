<script lang="ts" setup>
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { createExport, getExports, downloadExport, deleteExport } from '@/utils/hybridStorage';
import type { ExportTask } from '@/utils/storage';
import { showSuccess, showError } from '@/utils/toast';

const tasks = ref<ExportTask[]>([]);
const loading = ref(false);
const creating = ref(false);
const refreshInterval = ref<number | null>(null);
const deletingId = ref<string | null>(null);
const confirmDeleteId = ref<string | null>(null);

const hasRunningTask = computed(() => tasks.value.some((t) => t.status === 'running'));

onMounted(async () => {
  await loadTasks();
  startAutoRefresh();
});

onUnmounted(() => {
  stopAutoRefresh();
});

function startAutoRefresh() {
  if (refreshInterval.value) return;
  refreshInterval.value = window.setInterval(() => {
    if (hasRunningTask.value) {
      loadTasks();
    }
  }, 3000);
}

function stopAutoRefresh() {
  if (refreshInterval.value) {
    clearInterval(refreshInterval.value);
    refreshInterval.value = null;
  }
}

async function loadTasks() {
  loading.value = true;
  try {
    tasks.value = await getExports();
  } catch (error) {
    console.error('Failed to load export tasks:', error);
  } finally {
    loading.value = false;
  }
}

async function handleCreateExport() {
  creating.value = true;
  try {
    const result = await createExport();
    showSuccess(`导出任务已创建: ${result.taskId}`);
    await loadTasks();
    startAutoRefresh();
  } catch (error) {
    showError(`创建导出任务失败: ${error instanceof Error ? error.message : '未知错误'}`);
  } finally {
    creating.value = false;
  }
}

async function handleDownload(task: ExportTask) {
  if (!task.id || task.status !== 'completed' || !task.filename) return;
  try {
    const blob = await downloadExport(task.id);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = task.filename;
    a.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    showError(`下载失败: ${error instanceof Error ? error.message : '未知错误'}`);
  }
}

function promptDelete(id: string) {
  confirmDeleteId.value = id;
}

function cancelDelete() {
  confirmDeleteId.value = null;
}

async function handleConfirmDelete() {
  if (!confirmDeleteId.value) return;
  deletingId.value = confirmDeleteId.value;
  try {
    await deleteExport(confirmDeleteId.value);
    showSuccess('导出任务已删除');
    await loadTasks();
  } catch (error) {
    showError(`删除失败: ${error instanceof Error ? error.message : '未知错误'}`);
  } finally {
    deletingId.value = null;
    confirmDeleteId.value = null;
  }
}

function formatDate(ts: number): string {
  return new Date(ts).toLocaleString('zh-CN');
}

function formatSize(bytes: number | null): string {
  if (!bytes) return '-';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function getStatusLabel(status: string): string {
  switch (status) {
    case 'running':
      return '进行中';
    case 'completed':
      return '已完成';
    case 'failed':
      return '失败';
    default:
      return status;
  }
}

function getStatusClass(status: string): string {
  switch (status) {
    case 'running':
      return 'status-running';
    case 'completed':
      return 'status-completed';
    case 'failed':
      return 'status-failed';
    default:
      return '';
  }
}

function goBack() {
  window.close();
}
</script>

<template>
  <div class="export-manager">
    <header class="header">
      <div class="header-content">
        <div class="logo">
          <button class="back-btn" @click="goBack">← 返回</button>
          <h1>📦 导出管理</h1>
        </div>
        <button class="btn btn-primary" @click="handleCreateExport" :disabled="creating">
          {{ creating ? '创建中...' : '➕ 新建导出' }}
        </button>
      </div>
    </header>

    <main class="main">
      <div v-if="loading && tasks.length === 0" class="loading">
        <div class="spinner"></div>
        <p>加载中...</p>
      </div>

      <div v-else-if="tasks.length === 0" class="empty-state">
        <p>暂无导出任务</p>
        <p class="hint">点击"新建导出"创建完整备份（包含数据库和图片）</p>
      </div>

      <div v-else class="task-list">
        <div class="task-header">
          <span>共 {{ tasks.length }} 个任务</span>
          <span v-if="hasRunningTask" class="refreshing">🔄 自动刷新中</span>
        </div>

        <div
          v-for="task in tasks"
          :key="task.id"
          class="task-card"
          :class="{ 'task-running': task.status === 'running' }"
        >
          <div class="task-info">
            <div class="task-id" :title="task.id">ID: {{ task.id.slice(0, 24) }}...</div>
            <div class="task-meta">
              <span class="task-date">创建于: {{ formatDate(task.createdAt) }}</span>
              <span v-if="task.completedAt" class="task-date">
                完成于: {{ formatDate(task.completedAt) }}
              </span>
            </div>
          </div>

          <div class="task-status">
            <span class="status-badge" :class="getStatusClass(task.status)">
              {{ getStatusLabel(task.status) }}
            </span>
            <span v-if="task.fileSize" class="file-size">
              {{ formatSize(task.fileSize) }}
            </span>
          </div>

          <div class="task-actions">
            <button
              v-if="task.status === 'completed'"
              class="btn btn-sm btn-primary"
              @click="handleDownload(task)"
            >
              ⬇️ 下载
            </button>
            <button
              class="btn btn-sm btn-danger"
              :disabled="deletingId === task.id"
              @click="promptDelete(task.id)"
            >
              {{ deletingId === task.id ? '删除中...' : '🗑️ 删除' }}
            </button>
          </div>

          <div v-if="task.error" class="task-error">错误: {{ task.error }}</div>
        </div>
      </div>
    </main>

    <!-- 删除确认对话框 -->
    <Teleport to="body">
      <Transition name="dialog-fade">
        <div v-if="confirmDeleteId" class="dialog-overlay" @click.self="cancelDelete">
          <div class="dialog">
            <h3>⚠️ 确认删除</h3>
            <p>确定要删除这个导出任务吗？</p>
            <p class="dialog-hint">压缩包文件将同时被删除，此操作不可撤销。</p>
            <div class="dialog-actions">
              <button class="btn btn-default" @click="cancelDelete">取消</button>
              <button class="btn btn-danger" @click="handleConfirmDelete">确认删除</button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.export-manager {
  min-height: 100vh;
  background: #f9fafb;
}

.header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 20px 0;
}

.header-content {
  max-width: 900px;
  margin: 0 auto;
  padding: 0 20px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.logo {
  display: flex;
  align-items: center;
  gap: 16px;
}

.back-btn {
  background: rgba(255, 255, 255, 0.2);
  border: none;
  color: white;
  padding: 8px 14px;
  border-radius: 8px;
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s;
}

.back-btn:hover {
  background: rgba(255, 255, 255, 0.3);
}

.logo h1 {
  font-size: 22px;
  margin: 0;
}

.main {
  max-width: 900px;
  margin: 0 auto;
  padding: 24px 20px;
}

.btn {
  padding: 10px 20px;
  border: none;
  border-radius: 8px;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s;
  white-space: nowrap;
}

.btn-primary {
  background: #667eea;
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background: #5568d3;
}

.btn-danger {
  background: #ef4444;
  color: white;
}

.btn-danger:hover:not(:disabled) {
  background: #dc2626;
}

.btn-default {
  background: #e5e7eb;
  color: #374151;
}

.btn-default:hover {
  background: #d1d5db;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-sm {
  padding: 6px 14px;
  font-size: 13px;
}

.loading {
  text-align: center;
  padding: 80px 20px;
  color: #6b7280;
}

.spinner {
  width: 40px;
  height: 40px;
  border: 3px solid #e5e7eb;
  border-top-color: #667eea;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin: 0 auto 16px;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.empty-state {
  text-align: center;
  padding: 80px 20px;
  color: #6b7280;
  background: white;
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
}

.empty-state .hint {
  font-size: 14px;
  margin-top: 12px;
}

.task-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.task-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 14px;
  color: #6b7280;
  margin-bottom: 8px;
}

.refreshing {
  color: #667eea;
  font-size: 13px;
}

.task-card {
  background: white;
  border-radius: 12px;
  padding: 20px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  align-items: center;
  justify-content: space-between;
  transition: all 0.2s;
}

.task-running {
  border-left: 4px solid #667eea;
}

.task-info {
  flex: 1;
  min-width: 0;
}

.task-id {
  font-size: 13px;
  font-family: monospace;
  color: #374151;
  margin-bottom: 6px;
  word-break: break-all;
}

.task-meta {
  display: flex;
  gap: 16px;
  flex-wrap: wrap;
}

.task-date {
  font-size: 13px;
  color: #9ca3af;
}

.task-status {
  display: flex;
  align-items: center;
  gap: 12px;
}

.status-badge {
  padding: 4px 12px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 500;
}

.status-running {
  background: #eef2ff;
  color: #667eea;
}

.status-completed {
  background: #d1fae5;
  color: #065f46;
}

.status-failed {
  background: #fee2e2;
  color: #991b1b;
}

.file-size {
  font-size: 13px;
  color: #6b7280;
  font-family: monospace;
}

.task-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.task-error {
  width: 100%;
  font-size: 12px;
  color: #991b1b;
  background: #fef2f2;
  padding: 8px 12px;
  border-radius: 6px;
  margin-top: 4px;
}

/* 对话框 */
.dialog-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.dialog {
  background: white;
  border-radius: 12px;
  padding: 24px;
  width: 100%;
  max-width: 400px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
}

.dialog h3 {
  margin: 0 0 12px;
  font-size: 18px;
  color: #111827;
}

.dialog p {
  color: #4b5563;
  margin: 0 0 8px;
}

.dialog-hint {
  font-size: 13px;
  color: #9ca3af;
}

.dialog-actions {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 20px;
}

.dialog-fade-enter-active,
.dialog-fade-leave-active {
  transition: opacity 0.2s ease;
}

.dialog-fade-enter-from,
.dialog-fade-leave-to {
  opacity: 0;
}

/* 响应式 */
@media (max-width: 640px) {
  .header-content {
    flex-direction: column;
    gap: 12px;
    text-align: center;
  }

  .task-card {
    flex-direction: column;
    align-items: stretch;
  }

  .task-actions {
    width: 100%;
    justify-content: stretch;
  }

  .task-actions .btn {
    flex: 1;
  }
}
</style>
