<script lang="ts" setup>
import { ref, onMounted, computed, watch } from 'vue';
import { type LinkItem, type DeleteRecord, normalizeUrl } from '@/utils/storage';

import {
  getLinks,
  deleteLink,
  getTrashItems,
  restoreFromTrash,
  permanentlyDeleteFromTrash,
  getStats,
  searchLinks,
  getAllDomains,
  getDomainStats,
  batchAddLinks,
} from '@/utils/hybridStorage';
import { showSuccess, showError } from '@/utils/toast';
import { parseImportFile, type ParsedLink } from '@/utils/importParser';
import ImportPreview from '@/components/ImportPreview.vue';

type SortBy = 'createdAt' | 'title' | 'domain';
type SortOrder = 'asc' | 'desc';
type ViewMode = 'grid' | 'list';
type TabView = 'links' | 'trash';

const links = ref<LinkItem[]>([]);
const total = ref(0);
const currentPage = ref(1);
const pageSize = ref(50);
const searchQuery = ref('');
const loading = ref(false);
const selectedIds = ref<Set<string>>(new Set());
const viewMode = ref<ViewMode>('grid');

// 排序和过滤状态
const sortBy = ref<SortBy>('createdAt');
const sortOrder = ref<SortOrder>('desc');
const domainFilter = ref<string>('');
const domains = ref<string[]>([]);
const domainStats = ref<{ domain: string; count: number }[]>([]);
const showFilters = ref(false);

// 日期过滤
const dateFrom = ref<string>('');
const dateTo = ref<string>('');

// 统计信息
const totalCount = ref(0);
const importInput = ref<HTMLInputElement | null>(null);
const importing = ref(false);

// 导入预览
const showImportPreview = ref(false);
const parsedLinks = ref<ParsedLink[]>([]);
const previewExistingUrls = ref<Set<string>>(new Set());

// 回收站
const currentTab = ref<TabView>('links');
const trashItems = ref<DeleteRecord[]>([]);
const trashLoading = ref(false);
const selectedTrashIds = ref<Set<string>>(new Set());

const totalPages = computed(() => Math.ceil(total.value / pageSize.value));

// 当前过滤描述
const filterDescription = computed(() => {
  const parts: string[] = [];
  if (domainFilter.value) parts.push(`域名: ${domainFilter.value}`);
  if (dateFrom.value) parts.push(`从: ${dateFrom.value}`);
  if (dateTo.value) parts.push(`到: ${dateTo.value}`);
  if (parts.length === 0) return '';
  return ` (${parts.join(', ')})`;
});

onMounted(async () => {
  await loadInitialData();
});

async function loadInitialData() {
  loading.value = true;
  try {
    const [stats, domainList, domainStatsResult] = await Promise.all([
      getStats(),
      getAllDomains(),
      getDomainStats(),
    ]);
    totalCount.value = stats.linkCount;
    domains.value = domainList;
    domainStats.value = domainStatsResult;
    await loadLinks();
  } finally {
    loading.value = false;
  }
}

async function loadLinks() {
  loading.value = true;
  try {
    const result = await getLinks(currentPage.value, pageSize.value, {
      sortBy: sortBy.value,
      sortDesc: sortOrder.value === 'desc',
    });

    // 在客户端进行域名和日期过滤
    let filteredLinks = result.links;

    if (domainFilter.value) {
      filteredLinks = filteredLinks.filter((link) => {
        try {
          const domain = new URL(link.url).hostname;
          return domain === domainFilter.value;
        } catch {
          return false;
        }
      });
    }

    if (dateFrom.value) {
      const fromTime = new Date(dateFrom.value).getTime();
      filteredLinks = filteredLinks.filter((link) => link.createdAt >= fromTime);
    }

    if (dateTo.value) {
      const toTime = new Date(dateTo.value).getTime() + 86400000;
      filteredLinks = filteredLinks.filter((link) => link.createdAt <= toTime);
    }

    links.value = filteredLinks;
    total.value = result.total;
    selectedIds.value.clear();
  } finally {
    loading.value = false;
  }
}

// 当排序或过滤条件改变时重新加载
watch(
  [sortBy, sortOrder, domainFilter, dateFrom, dateTo],
  () => {
    currentPage.value = 1;
    loadLinks();
  },
  { deep: true }
);

async function handleSearch() {
  if (!searchQuery.value.trim()) {
    await loadLinks();
    return;
  }

  loading.value = true;
  try {
    const results = await searchLinks(searchQuery.value);
    // 对搜索结果应用当前排序
    results.sort((a, b) => {
      let comparison = 0;
      switch (sortBy.value) {
        case 'createdAt':
          comparison = a.createdAt - b.createdAt;
          break;
        case 'title':
          comparison = (a.title || '').localeCompare(b.title || '');
          break;
        case 'domain':
          try {
            const domainA = new URL(a.url).hostname;
            const domainB = new URL(b.url).hostname;
            comparison = domainA.localeCompare(domainB);
          } catch {
            comparison = a.url.localeCompare(b.url);
          }
          break;
      }
      return sortOrder.value === 'desc' ? -comparison : comparison;
    });

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

function clearFilters() {
  domainFilter.value = '';
  dateFrom.value = '';
  dateTo.value = '';
  currentPage.value = 1;
  loadLinks();
}

function setSort(field: SortBy) {
  if (sortBy.value === field) {
    // 切换排序方向
    sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortBy.value = field;
    sortOrder.value = field === 'createdAt' ? 'desc' : 'asc';
  }
}

function getSortIcon(field: SortBy): string {
  if (sortBy.value !== field) return '↕️';
  return sortOrder.value === 'asc' ? '↑' : '↓';
}

async function changePage(page: number) {
  if (page < 1 || page > totalPages.value) return;
  currentPage.value = page;
  await loadLinks();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

async function handleDelete(id: string) {
  if (!confirm('确定要删除这个链接吗？（删除后可在回收站还原）')) return;
  console.log('[LinkManager] Deleting link:', id);
  try {
    const result = await deleteLink(id);
    console.log('[LinkManager] Delete result:', result);
    await loadLinks();
    // 更新统计和回收站数据
    const [stats, domainStatsResult] = await Promise.all([getStats(), getDomainStats()]);
    totalCount.value = stats.linkCount;
    domainStats.value = domainStatsResult;
    // 如果回收站已加载，刷新回收站
    if (trashItems.value.length > 0 || currentTab.value === 'trash') {
      await loadTrash();
    }
  } catch (error) {
    console.error('[LinkManager] Delete failed:', error);
    showError('删除失败: ' + (error instanceof Error ? error.message : '未知错误'));
  }
}

async function handleBatchDelete() {
  if (!confirm(`确定要删除选中的 ${selectedIds.value.size} 个链接吗？（删除后可在回收站还原）`))
    return;

  const ids = Array.from(selectedIds.value);

  for (const id of ids) {
    await deleteLink(id);
  }

  selectedIds.value.clear();
  await loadLinks();
  // 更新统计和回收站数据
  const stats = await getStats();
  totalCount.value = stats.linkCount;
  // 如果回收站已加载，刷新回收站
  if (trashItems.value.length > 0 || currentTab.value === 'trash') {
    await loadTrash();
  }
}

// ========== 回收站功能 ==========

async function loadTrash() {
  trashLoading.value = true;
  try {
    trashItems.value = await getTrashItems();
  } finally {
    trashLoading.value = false;
  }
}

function switchTab(tab: TabView) {
  currentTab.value = tab;
  if (tab === 'trash') {
    loadTrash();
  }
}

async function restoreItem(recordId: string) {
  if (!confirm('确定要还原这个链接吗？')) return;

  await restoreFromTrash(recordId);
  await loadTrash();
  // 刷新链接列表和统计
  await loadLinks();
  const [stats, domainStatsResult] = await Promise.all([getStats(), getDomainStats()]);
  totalCount.value = stats.linkCount;
  domainStats.value = domainStatsResult;
}

async function permanentlyDeleteItem(recordId: string) {
  if (!confirm('确定要永久删除这个链接吗？此操作不可撤销！')) return;

  await permanentlyDeleteFromTrash(recordId);
  await loadTrash();
  // 更新统计
  await updateStats();
}

async function emptyTrash() {
  if (!confirm('确定要清空回收站吗？所有项目将被永久删除！')) return;

  for (const item of trashItems.value) {
    await permanentlyDeleteFromTrash(item.id);
  }

  await loadTrash();
  // 更新统计
  await updateStats();
}

function toggleTrashSelection(id: string) {
  if (selectedTrashIds.value.has(id)) {
    selectedTrashIds.value.delete(id);
  } else {
    selectedTrashIds.value.add(id);
  }
}

async function restoreSelected() {
  if (!confirm(`确定要还原选中的 ${selectedTrashIds.value.size} 个链接吗？`)) return;

  for (const id of selectedTrashIds.value) {
    await restoreFromTrash(id);
  }

  selectedTrashIds.value.clear();
  await loadTrash();
  // 刷新链接列表和统计
  await loadLinks();
  const [stats, domainStatsResult] = await Promise.all([getStats(), getDomainStats()]);
  totalCount.value = stats.linkCount;
  domainStats.value = domainStatsResult;
}

async function deleteSelected() {
  if (!confirm(`确定要永久删除选中的 ${selectedTrashIds.value.size} 个链接吗？此操作不可撤销！`))
    return;

  for (const id of selectedTrashIds.value) {
    await permanentlyDeleteFromTrash(id);
  }

  selectedTrashIds.value.clear();
  await loadTrash();
  // 更新统计
  await updateStats();
}

async function updateStats() {
  const stats = await getStats();
  totalCount.value = stats.linkCount;
}

function openExportManager() {
  browser.tabs.create({
    url: browser.runtime.getURL('/export-manager.html'),
  });
}

function triggerImport() {
  importInput.value?.click();
}

async function handleImport(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;

  importing.value = true;
  try {
    const result = await parseImportFile(file);
    parsedLinks.value = result.links;

    // 获取现有链接 URL 用于重复检测（使用统一的标准化逻辑）
    try {
      const { links: existingLinks } = await getLinks(1, 10000);
      const existingSet = new Set(existingLinks.map((link) => normalizeUrl(link.url)));
      previewExistingUrls.value = existingSet;
    } catch {
      previewExistingUrls.value = new Set();
    }

    showImportPreview.value = true;
    showSuccess(`成功解析 ${result.links.length} 个链接，请确认后导入`);
  } catch (error) {
    showError(`解析失败: ${error instanceof Error ? error.message : '未知错误'}`);
  } finally {
    importing.value = false;
    input.value = '';
  }
}

async function confirmImport(selected: ParsedLink[]) {
  importing.value = true;
  try {
    // 自动去重：过滤掉数据库中已存在的链接
    const newLinks = selected.filter(
      (link) => !previewExistingUrls.value.has(normalizeUrl(link.url))
    );
    const skipped = selected.length - newLinks.length;

    if (newLinks.length === 0) {
      showImportPreview.value = false;
      parsedLinks.value = [];
      previewExistingUrls.value = new Set();
      showSuccess(
        skipped > 0 ? `已跳过 ${skipped} 个重复链接，没有新链接需要导入` : '没有新链接需要导入'
      );
      return;
    }

    const result = await batchAddLinks(newLinks);
    showImportPreview.value = false;
    parsedLinks.value = [];
    previewExistingUrls.value = new Set();
    await loadInitialData();

    const parts: string[] = [];
    parts.push(`成功导入 ${result.count} 个链接`);
    if (skipped > 0) parts.push(`已跳过 ${skipped} 个重复链接`);
    if (result.failed > 0) parts.push(`${result.failed} 个失败`);
    showSuccess(parts.join('，'));
  } catch (error) {
    showError(`导入失败: ${error instanceof Error ? error.message : '未知错误'}`);
  } finally {
    importing.value = false;
  }
}

function cancelImport() {
  showImportPreview.value = false;
  parsedLinks.value = [];
  previewExistingUrls.value = new Set();
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
    links.value.forEach((link) => selectedIds.value.add(link.id));
  }
}

function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleString('zh-CN');
}

function formatDateOnly(timestamp: number): string {
  return new Date(timestamp).toLocaleDateString('zh-CN');
}

function truncate(str: string, len: number): string {
  if (!str) return '';
  return str.length > len ? str.slice(0, len) + '...' : str;
}

function getDomain(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
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
          <h1>稍后再看</h1>
          <span class="badge">{{ totalCount }} 个链接</span>
        </div>
        <div class="header-actions">
          <input
            ref="importInput"
            type="file"
            accept=".json,.html,.htm"
            style="display: none"
            @change="handleImport"
          />
          <button class="btn btn-default" @click="triggerImport" :disabled="importing">
            {{ importing ? '导入中...' : '导入' }}
          </button>
          <button class="btn btn-default" @click="openExportManager">导出管理</button>
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

    <ImportPreview
      v-model="showImportPreview"
      :links="parsedLinks"
      :existing-urls="previewExistingUrls"
      @confirm="confirmImport"
      @cancel="cancelImport"
    />

    <main class="main">
      <!-- Tab 导航 -->
      <nav class="tab-nav">
        <button
          class="tab-btn"
          :class="{ active: currentTab === 'links' }"
          @click="switchTab('links')"
        >
          📚 链接列表
        </button>
        <button
          class="tab-btn"
          :class="{ active: currentTab === 'trash' }"
          @click="switchTab('trash')"
        >
          🗑️ 回收站 ({{ trashItems.length }})
        </button>
      </nav>

      <!-- 链接列表视图 -->
      <template v-if="currentTab === 'links'">
        <!-- 搜索和过滤工具栏 -->
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
          <div class="toolbar-right">
            <button
              class="btn btn-default"
              :class="{ active: showFilters }"
              @click="showFilters = !showFilters"
            >
              筛选 {{ filterDescription }}
            </button>
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
        </div>

        <!-- 筛选面板 -->
        <div v-if="showFilters" class="filter-panel">
          <div class="filter-section">
            <h4>排序方式</h4>
            <div class="sort-options">
              <button
                class="btn btn-sm"
                :class="sortBy === 'createdAt' ? 'btn-primary' : 'btn-default'"
                @click="setSort('createdAt')"
              >
                添加时间 {{ getSortIcon('createdAt') }}
              </button>
              <button
                class="btn btn-sm"
                :class="sortBy === 'title' ? 'btn-primary' : 'btn-default'"
                @click="setSort('title')"
              >
                标题 {{ getSortIcon('title') }}
              </button>
              <button
                class="btn btn-sm"
                :class="sortBy === 'domain' ? 'btn-primary' : 'btn-default'"
                @click="setSort('domain')"
              >
                域名 {{ getSortIcon('domain') }}
              </button>
            </div>
          </div>

          <div class="filter-section">
            <h4>域名筛选</h4>
            <div class="domain-tags">
              <button
                class="tag"
                :class="{ active: domainFilter === '' }"
                @click="domainFilter = ''"
              >
                全部 ({{ totalCount }})
              </button>
              <button
                v-for="stat in domainStats.slice(0, 20)"
                :key="stat.domain"
                class="tag"
                :class="{ active: domainFilter === stat.domain }"
                @click="domainFilter = stat.domain"
              >
                {{ truncate(stat.domain, 25) }} ({{ stat.count }})
              </button>
            </div>
            <select v-if="domains.length > 20" v-model="domainFilter" class="domain-select">
              <option value="">选择域名...</option>
              <option v-for="domain in domains" :key="domain" :value="domain">
                {{ domain }}
              </option>
            </select>
          </div>

          <div class="filter-section">
            <h4>日期范围</h4>
            <div class="date-range">
              <input type="date" v-model="dateFrom" :max="dateTo || undefined" />
              <span>至</span>
              <input type="date" v-model="dateTo" :min="dateFrom || undefined" />
            </div>
          </div>

          <div class="filter-actions">
            <button class="btn btn-default" @click="clearFilters">清除筛选</button>
            <button class="btn btn-primary" @click="showFilters = false">应用</button>
          </div>
        </div>

        <!-- 结果信息 -->
        <div class="results-info" v-if="!searchQuery">
          <span v-if="total !== totalCount">
            显示 {{ total }} 个结果（共 {{ totalCount }} 个）
          </span>
          <span v-else> 共 {{ total }} 个链接 </span>
          <span v-if="filterDescription" class="filter-desc">
            {{ filterDescription }}
          </span>
        </div>

        <!-- 全选 -->
        <div class="select-all-bar" v-if="links.length > 0">
          <label class="checkbox">
            <input
              type="checkbox"
              :checked="selectedIds.size === links.length && links.length > 0"
              @change="selectAll"
            />
            <span>全选本页（{{ links.length }} 个）</span>
          </label>
        </div>

        <!-- 链接列表 -->
        <div v-if="loading" class="loading">
          <div class="spinner"></div>
          <p>加载中...</p>
        </div>

        <div v-else-if="links.length === 0" class="empty-state">
          <p>暂无链接</p>
          <p class="hint" v-if="filterDescription">
            当前筛选条件下没有结果，<a href="#" @click.prevent="clearFilters">清除筛选</a>
          </p>
          <p class="hint" v-else>右键或长按网页链接，选择"收好链接（稍后再看）"</p>
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

            <div class="card-image" v-if="link.nearbyImage || link.screenshot">
              <img
                :src="link.nearbyImage || link.screenshot || ''"
                :alt="link.title"
                loading="lazy"
              />
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
                <span class="domain">{{ getDomain(link.url) }}</span>
                <span class="date">{{ formatDateOnly(link.createdAt) }}</span>
              </div>
            </div>

            <div class="card-actions" @click.stop>
              <button class="btn btn-sm btn-primary" @click="openLink(link.url)">打开</button>
              <button class="btn btn-sm btn-danger" @click="handleDelete(link.id)">删除</button>
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
          <span class="page-info"> 第 {{ currentPage }} / {{ totalPages }} 页 </span>
          <button
            class="btn btn-sm btn-default"
            :disabled="currentPage === totalPages"
            @click="changePage(currentPage + 1)"
          >
            下一页
          </button>
        </div>
      </template>

      <!-- 回收站视图 -->
      <template v-if="currentTab === 'trash'">
        <div class="trash-header">
          <h2>🗑️ 回收站</h2>
          <p class="trash-desc">已删除的链接会在这里保留 30 天，之后自动清理</p>
          <div class="trash-actions">
            <button
              class="btn btn-primary"
              @click="restoreSelected"
              :disabled="selectedTrashIds.size === 0"
            >
              还原选中 ({{ selectedTrashIds.size }})
            </button>
            <button
              class="btn btn-danger"
              @click="deleteSelected"
              :disabled="selectedTrashIds.size === 0"
            >
              永久删除选中 ({{ selectedTrashIds.size }})
            </button>
            <button class="btn btn-default" @click="emptyTrash" :disabled="trashItems.length === 0">
              清空回收站
            </button>
          </div>
        </div>

        <div v-if="trashLoading" class="loading">
          <div class="spinner"></div>
          <p>加载中...</p>
        </div>

        <div v-else-if="trashItems.length === 0" class="empty-state">
          <p>回收站是空的</p>
          <p class="hint">删除的链接会出现在这里</p>
        </div>

        <div v-else class="trash-list">
          <div v-for="item in trashItems" :key="item.id" class="trash-item">
            <div class="trash-checkbox">
              <input
                type="checkbox"
                :checked="selectedTrashIds.has(item.id)"
                @change="toggleTrashSelection(item.id)"
              />
            </div>
            <div class="trash-image" v-if="item.nearbyImage || item.screenshot">
              <img
                :src="item.nearbyImage || item.screenshot || ''"
                :alt="item.title"
                loading="lazy"
              />
            </div>
            <div v-else class="trash-image empty">
              <span>无图片</span>
            </div>
            <div class="trash-content">
              <h4 class="trash-title">{{ item.title }}</h4>
              <p class="trash-url">{{ item.url }}</p>
              <div class="trash-meta">
                <span>创建于: {{ formatDate(item.createdAt) }}</span>
                <span>删除于: {{ formatDate(item.deletedAt) }}</span>
                <span v-if="item.nearbyImage || item.screenshot" class="has-image">📷 有图片</span>
              </div>
            </div>
            <div class="trash-actions-row">
              <button class="btn btn-sm btn-primary" @click="restoreItem(item.id)">还原</button>
              <button class="btn btn-sm btn-danger" @click="permanentlyDeleteItem(item.id)">
                永久删除
              </button>
            </div>
          </div>
        </div>
      </template>
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
  background: rgba(255, 255, 255, 0.2);
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
  margin-bottom: 16px;
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

.toolbar-right {
  display: flex;
  gap: 8px;
  align-items: center;
}

.view-toggle {
  display: flex;
  gap: 4px;
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

.btn-default {
  background: #e5e7eb;
  color: #374151;
}

.btn-default:hover:not(:disabled) {
  background: #d1d5db;
}

.btn-default.active {
  background: #667eea;
  color: white;
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

/* 筛选面板 */
.filter-panel {
  background: white;
  border-radius: 12px;
  padding: 20px;
  margin-bottom: 20px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
}

.filter-section {
  margin-bottom: 20px;
}

.filter-section:last-of-type {
  margin-bottom: 0;
}

.filter-section h4 {
  font-size: 14px;
  font-weight: 600;
  color: #374151;
  margin-bottom: 12px;
}

.sort-options {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.domain-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  max-height: 120px;
  overflow-y: auto;
}

.tag {
  padding: 6px 12px;
  border-radius: 20px;
  border: 1px solid #e5e7eb;
  background: #f9fafb;
  color: #374151;
  font-size: 13px;
  cursor: pointer;
  transition: all 0.2s;
}

.tag:hover {
  background: #e5e7eb;
}

.tag.active {
  background: #667eea;
  color: white;
  border-color: #667eea;
}

.domain-select {
  margin-top: 12px;
  padding: 8px 12px;
  border: 1px solid #d1d5db;
  border-radius: 8px;
  font-size: 14px;
  width: 100%;
  max-width: 400px;
}

.date-range {
  display: flex;
  align-items: center;
  gap: 12px;
}

.date-range input {
  padding: 8px 12px;
  border: 1px solid #d1d5db;
  border-radius: 8px;
  font-size: 14px;
}

.date-range span {
  color: #6b7280;
}

.filter-actions {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  padding-top: 16px;
  border-top: 1px solid #e5e7eb;
  margin-top: 16px;
}

/* 结果信息 */
.results-info {
  margin-bottom: 12px;
  font-size: 14px;
  color: #6b7280;
  display: flex;
  gap: 12px;
  align-items: center;
}

.filter-desc {
  color: #667eea;
}

/* 全选 */
.select-all-bar {
  margin-bottom: 16px;
  padding: 12px 16px;
  background: white;
  border-radius: 8px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
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
  margin: 0;
  vertical-align: middle;
}

.checkbox span {
  vertical-align: middle;
  line-height: 18px;
}

/* 加载和空状态 */
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
  to {
    transform: rotate(360deg);
  }
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

.empty-state a {
  color: #667eea;
}

/* 链接列表 */
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
  flex: 1;
  display: flex;
  flex-direction: column;
}

.link-card {
  background: white;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  transition: all 0.2s;
  cursor: pointer;
  position: relative;
  display: flex;
  flex-direction: column;
}

.link-card:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
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
  margin-top: auto;
}

.card-meta .domain {
  color: #667eea;
  background: #eef2ff;
  padding: 2px 8px;
  border-radius: 4px;
}

.card-actions {
  padding: 12px 16px;
  border-top: 1px solid #f3f4f6;
  display: flex;
  gap: 8px;
}

/* 分页 */
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

/* 回收站 */
.tab-nav {
  display: flex;
  gap: 12px;
  margin-bottom: 20px;
  border-bottom: 1px solid #e5e7eb;
  padding-bottom: 12px;
}

.tab-btn {
  padding: 10px 20px;
  border: none;
  background: #f3f4f6;
  border-radius: 8px;
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s;
}

.tab-btn:hover {
  background: #e5e7eb;
}

.tab-btn.active {
  background: #667eea;
  color: white;
}

.trash-header {
  background: white;
  border-radius: 12px;
  padding: 24px;
  margin-bottom: 20px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
}

.trash-header h2 {
  font-size: 20px;
  margin-bottom: 8px;
}

.trash-desc {
  color: #6b7280;
  margin-bottom: 16px;
}

.trash-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.trash-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.trash-item {
  background: white;
  border-radius: 12px;
  padding: 16px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  display: flex;
  align-items: center;
  gap: 16px;
}

.trash-checkbox input {
  width: 20px;
  height: 20px;
}

.trash-image {
  width: 80px;
  height: 60px;
  background: #f3f4f6;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}

.trash-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.trash-image.empty {
  color: #9ca3af;
  font-size: 12px;
}

.trash-content {
  flex: 1;
  min-width: 0;
}

.trash-title {
  font-size: 16px;
  font-weight: 600;
  margin-bottom: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.trash-url {
  font-size: 13px;
  color: #6b7280;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-bottom: 8px;
}

.trash-meta {
  display: flex;
  gap: 16px;
  font-size: 12px;
  color: #9ca3af;
  flex-wrap: wrap;
}

.trash-meta .has-image {
  color: #667eea;
}

.trash-actions-row {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

/* 响应式 */
@media (max-width: 768px) {
  .header-content {
    flex-direction: column;
    gap: 16px;
    text-align: center;
  }

  .toolbar {
    flex-direction: column;
    align-items: stretch;
  }

  .search-box {
    max-width: 100%;
  }

  .toolbar-right {
    justify-content: space-between;
  }

  .filter-panel {
    padding: 16px;
  }

  .sort-options {
    flex-direction: column;
  }

  .date-range {
    flex-direction: column;
    align-items: stretch;
  }

  .links-container.grid {
    grid-template-columns: 1fr;
  }
}
</style>
