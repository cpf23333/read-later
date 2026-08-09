<script lang="ts" setup>
import { ref, computed, watch } from 'vue';
import { normalizeUrl } from '@/utils/storage';
import { fetchOpenGraphImage, withConcurrencyLimit } from '@/utils/fetchOpenGraph';
import type { ParsedLink } from '@/utils/importParser';

interface Props {
  modelValue: boolean;
  links: ParsedLink[];
  existingUrls?: Set<string>;
}

const props = withDefaults(defineProps<Props>(), {
  existingUrls: () => new Set(),
});

const emit = defineEmits<{
  'update:modelValue': [value: boolean];
  confirm: [links: ParsedLink[]];
  cancel: [];
}>();

// 本地可修改的链接副本（用于补充图片）
const localLinks = ref<ParsedLink[]>([]);
const selectedIndexes = ref<Set<number>>(new Set());
const searchQuery = ref('');
const fetchingImages = ref(false);
const fetchProgress = ref({ current: 0, total: 0 });

watch(
  () => props.links,
  (newLinks) => {
    localLinks.value = newLinks.map((link) => ({ ...link }));
    selectedIndexes.value = new Set(newLinks.map((_, i) => i));
  },
  { immediate: true }
);

const filteredLinks = computed(() => {
  if (!searchQuery.value.trim()) return localLinks.value;
  const q = searchQuery.value.toLowerCase();
  return localLinks.value.filter(
    (link) =>
      link.title.toLowerCase().includes(q) ||
      link.url.toLowerCase().includes(q)
  );
});

const filteredIndexes = computed(() => {
  if (!searchQuery.value.trim()) return localLinks.value.map((_, i) => i);
  const q = searchQuery.value.toLowerCase();
  return localLinks.value
    .map((link, i) => ({ link, i }))
    .filter(
      ({ link }) =>
        link.title.toLowerCase().includes(q) ||
        link.url.toLowerCase().includes(q)
    )
    .map(({ i }) => i);
});

const allFilteredSelected = computed(() => {
  if (filteredIndexes.value.length === 0) return false;
  return filteredIndexes.value.every((i) => selectedIndexes.value.has(i));
});

const selectedCount = computed(() => selectedIndexes.value.size);
const duplicateCount = computed(() => {
  return Array.from(selectedIndexes.value).filter((i) =>
    props.existingUrls.has(normalizeUrl(localLinks.value[i].url))
  ).length;
});

// 是否有已选中但无图片的链接
const hasSelectedWithoutImage = computed(() => {
  return Array.from(selectedIndexes.value).some(
    (i) => !localLinks.value[i].nearbyImage
  );
});

function toggleIndex(index: number) {
  const next = new Set(selectedIndexes.value);
  if (next.has(index)) {
    next.delete(index);
  } else {
    next.add(index);
  }
  selectedIndexes.value = next;
}

function toggleSelectAllFiltered() {
  const next = new Set(selectedIndexes.value);
  if (allFilteredSelected.value) {
    for (const i of filteredIndexes.value) {
      next.delete(i);
    }
  } else {
    for (const i of filteredIndexes.value) {
      next.add(i);
    }
  }
  selectedIndexes.value = next;
}

async function fetchImages() {
  const targets = Array.from(selectedIndexes.value)
    .filter((i) => !localLinks.value[i].nearbyImage)
    .map((i) => ({ index: i, link: localLinks.value[i] }));

  if (targets.length === 0) return;

  fetchingImages.value = true;
  fetchProgress.value = { current: 0, total: targets.length };

  await withConcurrencyLimit(targets, 3, async ({ index, link }) => {
    const base64 = await fetchOpenGraphImage(link.url);
    if (base64) {
      localLinks.value[index].nearbyImage = base64;
    }
    fetchProgress.value.current++;
  });

  fetchingImages.value = false;
}

function handleConfirm() {
  if (selectedCount.value === 0) return;
  const selected = Array.from(selectedIndexes.value)
    .sort((a, b) => a - b)
    .map((i) => localLinks.value[i]);
  emit('confirm', selected);
}

function handleCancel() {
  emit('cancel');
  emit('update:modelValue', false);
}

function getDomain(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

function isDuplicate(link: ParsedLink): boolean {
  return props.existingUrls.has(normalizeUrl(link.url));
}

function truncate(str: string, len: number): string {
  if (!str) return '';
  return str.length > len ? str.slice(0, len) + '...' : str;
}

function formatDate(ts: number | undefined): string {
  if (!ts) return '';
  return new Date(ts).toLocaleDateString('zh-CN');
}
</script>

<template>
  <Teleport to="body">
    <Transition name="preview-fade">
      <div v-if="modelValue" class="preview-overlay" @click.self="handleCancel">
        <div class="preview-dialog">
          <div class="preview-header">
            <h2>📥 导入预览</h2>
            <p class="preview-subtitle">
              共解析到 {{ localLinks.length }} 个链接，已选
              <strong>{{ selectedCount }}</strong> 个
              <span v-if="duplicateCount > 0" class="duplicate-warning">
                （其中 {{ duplicateCount }} 个可能已存在）
              </span>
            </p>
            <button class="close-btn" @click="handleCancel" title="关闭">×</button>
          </div>

          <div class="preview-toolbar">
            <div class="preview-search">
              <input
                v-model="searchQuery"
                type="text"
                placeholder="搜索标题或 URL..."
              />
            </div>
            <label class="checkbox">
              <input
                type="checkbox"
                :checked="allFilteredSelected"
                @change="toggleSelectAllFiltered"
              />
              <span>全选当前</span>
            </label>
          </div>

          <div class="preview-list">
            <div
              v-for="link in filteredLinks"
              :key="localLinks.indexOf(link)"
              class="preview-item"
              :class="{
                selected: selectedIndexes.has(localLinks.indexOf(link)),
                duplicate: isDuplicate(link),
              }"
              @click="toggleIndex(localLinks.indexOf(link))"
            >
              <div class="item-checkbox">
                <input
                  type="checkbox"
                  :checked="selectedIndexes.has(localLinks.indexOf(link))"
                  @click.stop
                  @change="toggleIndex(localLinks.indexOf(link))"
                />
              </div>
              <div class="item-image" v-if="link.nearbyImage">
                <img :src="link.nearbyImage" :alt="link.title" />
              </div>
              <div v-else class="item-image empty">
                <span>无图片</span>
              </div>
              <div class="item-content">
                <div class="item-title" :title="link.title">
                  {{ truncate(link.title, 60) }}
                </div>
                <div class="item-url" :title="link.url">
                  {{ truncate(link.url, 80) }}
                </div>
                <div class="item-meta">
                  <span class="domain">{{ getDomain(link.url) }}</span>
                  <span v-if="link.createdAt" class="date">{{ formatDate(link.createdAt) }}</span>
                  <span v-if="isDuplicate(link)" class="duplicate-tag">已存在</span>
                </div>
              </div>
            </div>

            <div v-if="filteredLinks.length === 0" class="preview-empty">
              没有匹配的链接
            </div>
          </div>

          <div class="preview-footer">
            <div class="footer-info">
              <span v-if="selectedCount === 0" class="hint">请至少选择一项</span>
              <span v-else-if="fetchingImages">
                正在获取图片 {{ fetchProgress.current }} / {{ fetchProgress.total }}...
              </span>
              <span v-else>
                将导入 <strong>{{ selectedCount }}</strong> 个链接
                <span v-if="duplicateCount > 0" class="duplicate-hint">
                  （{{ duplicateCount }} 个重复）
                </span>
              </span>
            </div>
            <div class="footer-actions">
              <button class="btn btn-default" @click="handleCancel">取消</button>
              <button
                v-if="hasSelectedWithoutImage && !fetchingImages"
                class="btn btn-primary btn-img"
                @click="fetchImages"
              >
                📷 获取选中图片
              </button>
              <button
                class="btn btn-primary"
                :disabled="selectedCount === 0 || fetchingImages"
                @click="handleConfirm"
              >
                导入选中 ({{ selectedCount }})
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.preview-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.preview-dialog {
  background: white;
  border-radius: 16px;
  width: 100%;
  max-width: 720px;
  max-height: 85vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  overflow: hidden;
}

.preview-header {
  padding: 20px 24px;
  border-bottom: 1px solid #e5e7eb;
  position: relative;
}

.preview-header h2 {
  margin: 0;
  font-size: 18px;
  color: #111827;
}

.preview-subtitle {
  margin: 6px 0 0;
  font-size: 13px;
  color: #6b7280;
}

.duplicate-warning {
  color: #f59e0b;
  font-weight: 500;
}

.close-btn {
  position: absolute;
  top: 16px;
  right: 20px;
  width: 32px;
  height: 32px;
  border: none;
  background: #f3f4f6;
  border-radius: 8px;
  font-size: 20px;
  line-height: 1;
  color: #6b7280;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}

.close-btn:hover {
  background: #e5e7eb;
  color: #111827;
}

.preview-toolbar {
  padding: 12px 24px;
  border-bottom: 1px solid #e5e7eb;
  display: flex;
  gap: 16px;
  align-items: center;
  justify-content: space-between;
}

.preview-search {
  flex: 1;
}

.preview-search input {
  width: 100%;
  max-width: 320px;
  padding: 8px 14px;
  border: 1px solid #d1d5db;
  border-radius: 8px;
  font-size: 14px;
}

.preview-search input:focus {
  outline: none;
  border-color: #667eea;
}

.preview-list {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
}

.preview-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 16px;
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.15s;
  margin-bottom: 4px;
}

.preview-item:hover {
  background: #f9fafb;
}

.preview-item.selected {
  background: #eef2ff;
}

.preview-item.duplicate {
  border-left: 3px solid #f59e0b;
}

.item-checkbox {
  flex-shrink: 0;
}

.item-checkbox input {
  width: 18px;
  height: 18px;
  cursor: pointer;
}

.item-image {
  width: 80px;
  height: 60px;
  border-radius: 8px;
  background: #f3f4f6;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}

.item-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.item-image.empty {
  color: #9ca3af;
  font-size: 12px;
}

.item-content {
  flex: 1;
  min-width: 0;
}

.item-title {
  font-size: 14px;
  font-weight: 500;
  color: #111827;
  margin-bottom: 4px;
  word-break: break-all;
}

.item-url {
  font-size: 12px;
  color: #6b7280;
  word-break: break-all;
  margin-bottom: 6px;
}

.item-meta {
  display: flex;
  gap: 10px;
  align-items: center;
  flex-wrap: wrap;
}

.item-meta .domain {
  font-size: 12px;
  color: #667eea;
  background: #eef2ff;
  padding: 2px 8px;
  border-radius: 4px;
}

.item-meta .date {
  font-size: 12px;
  color: #9ca3af;
}

.duplicate-tag {
  font-size: 11px;
  color: #b45309;
  background: #fef3c7;
  padding: 2px 8px;
  border-radius: 4px;
  font-weight: 500;
}

.preview-empty {
  text-align: center;
  padding: 40px;
  color: #9ca3af;
  font-size: 14px;
}

.preview-footer {
  padding: 16px 24px;
  border-top: 1px solid #e5e7eb;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  flex-wrap: wrap;
}

.footer-info {
  font-size: 14px;
  color: #6b7280;
}

.footer-info .hint {
  color: #9ca3af;
}

.duplicate-hint {
  color: #f59e0b;
}

.footer-actions {
  display: flex;
  gap: 12px;
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

.btn-default:hover {
  background: #d1d5db;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.checkbox {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  font-size: 14px;
  color: #374151;
  white-space: nowrap;
}

.checkbox input {
  width: 18px;
  height: 18px;
  cursor: pointer;
  margin: 0;
}

/* Transition */
.preview-fade-enter-active,
.preview-fade-leave-active {
  transition: opacity 0.2s ease;
}

.preview-fade-enter-from,
.preview-fade-leave-to {
  opacity: 0;
}

/* 响应式 */
@media (max-width: 640px) {
  .preview-overlay {
    padding: 0;
    align-items: flex-end;
  }

  .preview-dialog {
    max-height: 92vh;
    border-radius: 16px 16px 0 0;
  }

  .preview-toolbar {
    flex-direction: column;
    align-items: stretch;
    gap: 10px;
  }

  .preview-search input {
    max-width: 100%;
  }

  .preview-footer {
    flex-direction: column;
    align-items: stretch;
  }

  .footer-actions {
    width: 100%;
    justify-content: stretch;
  }

  .footer-actions .btn {
    flex: 1;
  }
}
</style>
