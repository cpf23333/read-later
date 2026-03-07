<script lang="ts" setup>
import { ref, onMounted, computed } from 'vue';
import { 
  getLinks, 
  deleteLink, 
  deleteLinks,
  searchLinks,
  exportLinks,
  getLinkCount,
  LinkItem,
} from '@/utils/storage';

const links = ref<LinkItem[]>([]);
const total = ref(0);
const currentPage = ref(1);
const pageSize = ref(50);
const searchQuery = ref('');
const loading = ref(false);
const selectedIds = ref<Set<string>>(new Set());
const viewMode = ref<'grid' | 'list'>('grid');

const totalPages = computed(() => Math.ceil(total.value / pageSize.value));

onMounted(async () => {
  await loadLinks();
});

async function loadLinks() {
  loading.value = true;
  try {
    const result = await getLinks(currentPage.value, pageSize.value);
    links.value = result.links;
    total.value = result.total;
  } finally {
    loading.value = false;
  }
}

async function handleSearch() {
  if (!searchQuery.value.trim()) {
    await loadLinks();
    return;
  }
  
  loading.value = true;
  try {
    const results = await searchLinks(searchQuery.value);
    links.value = results;
    total.value = results.length;
    currentPage.value = 1;
  } finally {
    loading.value = false;
  }
}

function clearSearch() {
  searchQuery.value = '';
  loadLinks();
}

async function changePage(page: number) {
  if (page < 1 || page > totalPages.value) return;
  currentPage.value = page;
  await loadLinks();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

async function handleDelete(id: string) {
  if (!confirm('确定要删除这个链接吗？')) return;
  await deleteLink(id);
  await loadLinks();
}

async function handleBatchDelete() {
  if (!confirm(`确定要删除选中的 ${selectedIds.value.size} 个链接吗？`)) return;
  await deleteLinks(Array.from(selectedIds.value));
  selectedIds.value.clear();
  await loadLinks();
}

async function handleExport() {
  const json = await exportLinks();
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `urlmem-backup-${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  URL.revokeObjectURL(url);
}

function toggleSelection(id: string) {
  if (selectedIds.value.has(id)) {
    selectedIds.value.delete(id);
  } else {
    selectedIds.value.add(id);
  }
}

function selectAll() {
  if (selectedIds.value.size === links.value.length) {
    selectedIds.value.clear();
  } else {
    links.value.forEach(link => selectedIds.value.add(link.id));
  }
}

function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleString('zh-CN');
}

function truncate(str: string, len: number): string {
  if (!str) return '';
  return str.length > len ? str.slice(0, len) + '...' : str;
}

function openLink(url: string) {
  window.open(url, '_blank');
}

// 键盘快捷键
onMounted(() => {
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      selectedIds.value.clear();
    }
  });
});
</script>

<template>
  <div class="manager-container">
    <header class="header">
      <div class="header-content">
        <div class="logo">
          <h1>UrlMem</h1>
          <span class="badge">{{ total }} 个链接</span>
        </div>
        <div class="header-actions">
          <button class="btn btn-default" @click="handleExport">
            导出备份
          </button>
          <button 
            class="btn btn-danger" 
            @click="handleBatchDelete"
            :disabled="selectedIds.size === 0"
          >
            删除选中 ({{ selectedIds.size }})
          </button>
        </div>
      </div>
    </header>

    <main class="main">
      <!-- 搜索栏 -->
      <div class="toolbar">
        <div class="search-box">
          <input 
            v-model="searchQuery"
            type="text"
            placeholder="搜索链接或标题..."
            @keyup.enter="handleSearch"
          />
          <button class="btn btn-primary" @click="handleSearch">搜索</button>
          <button v-if="searchQuery" class="btn btn-default" @click="clearSearch">清除</button>
        </div>
        <div class="view-toggle">
          <button 
            class="btn btn-sm"
            :class="viewMode === 'grid' ? 'btn-primary' : 'btn-default'"
            @click="viewMode = 'grid'"
          >
            网格
          </button>
          <button 
            class="btn btn-sm"
            :class="viewMode === 'list' ? 'btn-primary' : 'btn-default'"
            @click="viewMode = 'list'"
          >
            列表
          </button>
        </div>
      </div>

      <!-- 全选 -->
      <div class="select-all-bar" v-if="links.length > 0">
        <label class="checkbox">
          <input 
            type="checkbox" 
            :checked="selectedIds.size === links.length && links.length > 0"
            @change="selectAll"
          />
          <span>全选本页</span>
        </label>
      </div>

      <!-- 链接列表 -->
      <div v-if="loading" class="loading">
        <div class="spinner"></div>
        <p>加载中...</p>
      </div>

      <div v-else-if="links.length === 0" class="empty-state">
        <p>暂无链接</p>
        <p class="hint">右键点击网页中的链接，选择"收藏链接到 UrlMem"</p>
      </div>

      <div v-else :class="['links-container', viewMode]">
        <div 
          v-for="link in links" 
          :key="link.id"
          :class="['link-card', { selected: selectedIds.has(link.id) }]"
          @click="toggleSelection(link.id)"
        >
          <div class="card-checkbox">
            <input 
              type="checkbox" 
              :checked="selectedIds.has(link.id)"
              @click.stop
              @change="toggleSelection(link.id)"
            />
          </div>

          <div class="card-image" v-if="link.nearbyImage">
            <img :src="link.nearbyImage" :alt="link.title" loading="lazy" />
          </div>
          <div v-else class="card-image empty">
            <span>无图片</span>
          </div>

          <div class="card-content">
            <h3 class="card-title" :title="link.title">
              {{ truncate(link.title, 60) }}
            </h3>
            <p class="card-url" :title="link.url">
              {{ truncate(link.url, 80) }}
            </p>
            <div class="card-meta">
              <span class="source">{{ truncate(link.sourcePage, 40) }}</span>
              <span class="date">{{ formatDate(link.createdAt) }}</span>
            </div>
          </div>

          <div class="card-actions" @click.stop>
            <button class="btn btn-sm btn-primary" @click="openLink(link.url)">
              打开
            </button>
            <button class="btn btn-sm btn-danger" @click="handleDelete(link.id)">
              删除
            </button>
          </div>
        </div>
      </div>

      <!-- 分页 -->
      <div v-if="totalPages > 1" class="pagination">
        <button 
          class="btn btn-sm btn-default" 
          :disabled="currentPage === 1"
          @click="changePage(currentPage - 1)"
        >
          上一页
        </button>
        <span class="page-info">
          第 {{ currentPage }} / {{ totalPages }} 页
        </span>
        <button 
          class="btn btn-sm btn-default" 
          :disabled="currentPage === totalPages"
          @click="changePage(currentPage + 1)"
        >
          下一页
        </button>
      </div>
    </main>
  </div>
</template>

<style scoped>
.manager-container {
  min-height: 100vh;
}

.header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 20px 0;
  position: sticky;
  top: 0;
  z-index: 100;
}

.header-content {
  max-width: 1400px;
  margin: 0 auto;
  padding: 0 20px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.logo {
  display: flex;
  align-items: center;
  gap: 12px;
}

.logo h1 {
  font-size: 24px;
}

.logo .badge {
  background: rgba(255,255,255,0.2);
  padding: 4px 12px;
  border-radius: 20px;
  font-size: 13px;
}

.header-actions {
  display: flex;
  gap: 12px;
}

.main {
  max-width: 1400px;
  margin: 0 auto;
  padding: 24px 20px;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
  gap: 16px;
  flex-wrap: wrap;
}

.search-box {
  display: flex;
  gap: 8px;
  flex: 1;
  max-width: 500px;
}

.search-box input {
  flex: 1;
  padding: 10px 16px;
  border: 1px solid #d1d5db;
  border-radius: 8px;
  font-size: 14px;
}

.search-box input:focus {
  outline: none;
  border-color: #667eea;
}

.view-toggle {
  display: flex;
  gap: 4px;
}

.select-all-bar {
  margin-bottom: 16px;
  padding: 12px 16px;
  background: white;
  border-radius: 8px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
}

.checkbox {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  font-size: 14px;
}

.checkbox input {
  width: 18px;
  height: 18px;
  cursor: pointer;
}

.btn {
  padding: 10px 20px;
  border: none;
  border-radius: 8px;
  font-size: 14px;
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

.btn-default {
  background: #e5e7eb;
  color: #374151;
}

.btn-default:hover:not(:disabled) {
  background: #d1d5db;
}

.btn-danger {
  background: #ef4444;
  color: white;
}

.btn-danger:hover:not(:disabled) {
  background: #dc2626;
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
  padding: 60px;
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
  to { transform: rotate(360deg); }
}

.empty-state {
  text-align: center;
  padding: 80px 20px;
  color: #6b7280;
}

.empty-state .hint {
  font-size: 14px;
  margin-top: 12px;
}

.links-container {
  display: grid;
  gap: 16px;
}

.links-container.grid {
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
}

.links-container.list {
  grid-template-columns: 1fr;
}

.links-container.list .link-card {
  display: grid;
  grid-template-columns: auto 120px 1fr auto;
  align-items: center;
}

.links-container.list .card-image {
  height: 80px;
}

.links-container.list .card-content {
  padding: 16px;
}

.link-card {
  background: white;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  transition: all 0.2s;
  cursor: pointer;
  position: relative;
}

.link-card:hover {
  box-shadow: 0 4px 12px rgba(0,0,0,0.12);
  transform: translateY(-2px);
}

.link-card.selected {
  border: 2px solid #667eea;
}

.card-checkbox {
  position: absolute;
  top: 12px;
  left: 12px;
  z-index: 10;
}

.card-checkbox input {
  width: 20px;
  height: 20px;
  cursor: pointer;
}

.card-image {
  height: 180px;
  background: #f3f4f6;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}

.card-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.card-image.empty {
  color: #9ca3af;
  font-size: 14px;
}

.card-content {
  padding: 16px;
}

.card-title {
  font-size: 15px;
  font-weight: 600;
  color: #111827;
  margin-bottom: 8px;
  line-height: 1.4;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.card-url {
  font-size: 13px;
  color: #6b7280;
  margin-bottom: 12px;
  word-break: break-all;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.card-meta {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  color: #9ca3af;
}

.card-meta .source {
  max-width: 60%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.card-actions {
  padding: 12px 16px;
  border-top: 1px solid #f3f4f6;
  display: flex;
  gap: 8px;
}

.pagination {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 16px;
  margin-top: 32px;
  padding: 20px;
}

.page-info {
  font-size: 14px;
  color: #6b7280;
}

@media (max-width: 768px) {
  .header-content {
    flex-direction: column;
    gap: 16px;
    text-align: center;
  }

  .links-container.grid {
    grid-template-columns: 1fr;
  }

  .search-box {
    max-width: 100%;
  }
}
</style>
