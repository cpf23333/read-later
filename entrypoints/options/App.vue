<script lang="ts" setup>
import { ref, onMounted } from 'vue';
import { 
  getCustomJsConfigs, 
  saveCustomJsConfig, 
  deleteCustomJsConfig,
  CustomJsConfig,
} from '@/utils/storage';
import { EXTRACTOR_TEMPLATES } from '@/utils/imageExtractor';

const configs = ref<CustomJsConfig[]>([]);
const showAddModal = ref(false);
const editingConfig = ref<Partial<CustomJsConfig>>({
  name: '',
  code: '',
  enabled: true,
});
const isEditing = ref(false);

onMounted(async () => {
  await loadConfigs();
});

async function loadConfigs() {
  configs.value = await getCustomJsConfigs();
}

function openAddModal() {
  editingConfig.value = {
    name: '',
    code: '',
    enabled: true,
  };
  isEditing.value = false;
  showAddModal.value = true;
}

function editConfig(config: CustomJsConfig) {
  editingConfig.value = { ...config };
  isEditing.value = true;
  showAddModal.value = true;
}

function applyTemplate(templateCode: string) {
  editingConfig.value.code = templateCode;
}

async function saveConfig() {
  if (!editingConfig.value.name?.trim()) {
    alert('请输入配置名称');
    return;
  }

  const config: CustomJsConfig = {
    id: isEditing.value ? editingConfig.value.id! : Date.now().toString(),
    name: editingConfig.value.name.trim(),
    code: editingConfig.value.code || '',
    enabled: editingConfig.value.enabled ?? true,
  };

  // 如果启用此配置，禁用其他配置
  if (config.enabled) {
    for (const c of configs.value) {
      if (c.id !== config.id && c.enabled) {
        c.enabled = false;
        await saveCustomJsConfig(c);
      }
    }
  }

  await saveCustomJsConfig(config);
  await loadConfigs();
  showAddModal.value = false;
}

async function deleteConfig(id: string) {
  if (!confirm('确定要删除这个配置吗？')) return;
  await deleteCustomJsConfig(id);
  await loadConfigs();
}

async function toggleConfig(config: CustomJsConfig) {
  config.enabled = !config.enabled;
  
  // 如果启用此配置，禁用其他配置
  if (config.enabled) {
    for (const c of configs.value) {
      if (c.id !== config.id && c.enabled) {
        c.enabled = false;
        await saveCustomJsConfig(c);
      }
    }
  }
  
  await saveCustomJsConfig(config);
  await loadConfigs();
}
</script>

<template>
  <div class="settings-container">
    <header class="header">
      <h1>UrlMem 设置</h1>
      <p>配置自定义图片提取规则</p>
    </header>

    <main class="main">
      <section class="section">
        <div class="section-header">
          <h2>自定义图片提取器</h2>
          <button class="btn btn-primary" @click="openAddModal">
            + 添加配置
          </button>
        </div>

        <div class="config-list" v-if="configs.length > 0">
          <div 
            v-for="config in configs" 
            :key="config.id"
            class="config-item"
            :class="{ active: config.enabled }"
          >
            <div class="config-info">
              <h3>{{ config.name }}</h3>
              <span class="badge" :class="config.enabled ? 'badge-success' : 'badge-default'">
                {{ config.enabled ? '已启用' : '已禁用' }}
              </span>
            </div>
            <div class="config-actions">
              <button 
                class="btn btn-sm"
                :class="config.enabled ? 'btn-success' : 'btn-default'"
                @click="toggleConfig(config)"
              >
                {{ config.enabled ? '禁用' : '启用' }}
              </button>
              <button class="btn btn-sm btn-default" @click="editConfig(config)">
                编辑
              </button>
              <button class="btn btn-sm btn-danger" @click="deleteConfig(config.id)">
                删除
              </button>
            </div>
          </div>
        </div>

        <div class="empty-state" v-else>
          <p>暂无自定义配置</p>
          <p class="hint">点击"添加配置"创建图片提取规则</p>
        </div>
      </section>

      <section class="section">
        <h2>使用说明</h2>
        <div class="help-content">
          <h3>默认提取逻辑</h3>
          <p>如果不配置自定义提取器，插件会按照以下顺序查找图片：</p>
          <ol>
            <li>链接自身的图片（如果是图片链接）</li>
            <li>链接内部的图片元素</li>
            <li>父元素中的图片</li>
            <li>相邻兄弟元素中的图片</li>
            <li>向上查找3层容器中的图片</li>
          </ol>

          <h3>自定义提取器</h3>
          <p>您可以编写 JavaScript 代码来自定义图片提取逻辑。代码需要定义一个 <code>extractImage</code> 函数：</p>
          <pre><code>function extractImage(element, url) {
  // element: 点击的链接元素
  // url: 链接的URL
  // 返回图片的URL字符串，或 null
  
  // 示例：获取父元素中的第一张图片
  const parent = element.parentElement;
  if (parent) {
    const img = parent.querySelector('img');
    if (img) return img.src;
  }
  return null;
}</code></pre>
        </div>
      </section>
    </main>

    <!-- 添加/编辑模态框 -->
    <div v-if="showAddModal" class="modal-overlay" @click.self="showAddModal = false">
      <div class="modal">
        <h3>{{ isEditing ? '编辑配置' : '添加配置' }}</h3>
        
        <div class="form-group">
          <label>配置名称</label>
          <input 
            v-model="editingConfig.name" 
            type="text" 
            placeholder="例如：自定义提取器"
          />
        </div>

        <div class="form-group">
          <label>代码模板</label>
          <select @change="applyTemplate(($event.target as HTMLSelectElement).value)">
            <option value="">选择模板...</option>
            <option 
              v-for="template in EXTRACTOR_TEMPLATES" 
              :key="template.name"
              :value="template.code"
            >
              {{ template.name }} - {{ template.description }}
            </option>
          </select>
        </div>

        <div class="form-group">
          <label>JavaScript 代码</label>
          <textarea 
            v-model="editingConfig.code" 
            rows="15"
            placeholder="在此输入 JavaScript 代码..."
          ></textarea>
        </div>

        <div class="form-group">
          <label class="checkbox">
            <input type="checkbox" v-model="editingConfig.enabled" />
            <span>立即启用此配置</span>
          </label>
        </div>

        <div class="modal-actions">
          <button class="btn btn-default" @click="showAddModal = false">取消</button>
          <button class="btn btn-primary" @click="saveConfig">保存</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.settings-container {
  max-width: 900px;
  margin: 0 auto;
  padding: 20px;
}

.header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 40px;
  border-radius: 12px;
  margin-bottom: 30px;
}

.header h1 {
  font-size: 28px;
  margin-bottom: 8px;
}

.header p {
  opacity: 0.9;
}

.main {
  display: flex;
  flex-direction: column;
  gap: 30px;
}

.section {
  background: white;
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

.section h2 {
  font-size: 20px;
  color: #333;
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

.btn-primary:hover {
  background: #5568d3;
}

.btn-default {
  background: #e5e7eb;
  color: #374151;
}

.btn-default:hover {
  background: #d1d5db;
}

.btn-success {
  background: #10b981;
  color: white;
}

.btn-success:hover {
  background: #059669;
}

.btn-danger {
  background: #ef4444;
  color: white;
}

.btn-danger:hover {
  background: #dc2626;
}

.btn-sm {
  padding: 6px 12px;
  font-size: 13px;
}

.config-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.config-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px;
  background: #f9fafb;
  border-radius: 8px;
  border: 2px solid transparent;
  transition: all 0.2s;
}

.config-item.active {
  border-color: #10b981;
  background: #ecfdf5;
}

.config-info {
  display: flex;
  align-items: center;
  gap: 12px;
}

.config-info h3 {
  font-size: 16px;
  font-weight: 500;
}

.badge {
  padding: 4px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 500;
}

.badge-success {
  background: #d1fae5;
  color: #065f46;
}

.badge-default {
  background: #e5e7eb;
  color: #6b7280;
}

.config-actions {
  display: flex;
  gap: 8px;
}

.empty-state {
  text-align: center;
  padding: 40px;
  color: #6b7280;
}

.empty-state .hint {
  font-size: 14px;
  margin-top: 8px;
}

.help-content {
  color: #4b5563;
}

.help-content h3 {
  font-size: 16px;
  margin: 20px 0 10px;
  color: #111827;
}

.help-content h3:first-child {
  margin-top: 0;
}

.help-content p {
  margin-bottom: 12px;
}

.help-content ol {
  margin-left: 20px;
  margin-bottom: 16px;
}

.help-content li {
  margin-bottom: 6px;
}

.help-content code {
  background: #f3f4f6;
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Monaco', 'Menlo', monospace;
  font-size: 14px;
}

.help-content pre {
  background: #1f2937;
  color: #e5e7eb;
  padding: 16px;
  border-radius: 8px;
  overflow-x: auto;
  margin: 12px 0;
}

.help-content pre code {
  background: none;
  padding: 0;
  color: inherit;
}

.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.modal {
  background: white;
  border-radius: 12px;
  padding: 24px;
  width: 100%;
  max-width: 700px;
  max-height: 90vh;
  overflow-y: auto;
}

.modal h3 {
  margin-bottom: 20px;
  font-size: 20px;
}

.form-group {
  margin-bottom: 20px;
}

.form-group label {
  display: block;
  margin-bottom: 8px;
  font-weight: 500;
  color: #374151;
}

.form-group label.checkbox {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
}

.form-group input[type="text"],
.form-group select,
.form-group textarea {
  width: 100%;
  padding: 10px 14px;
  border: 1px solid #d1d5db;
  border-radius: 8px;
  font-size: 14px;
  font-family: inherit;
}

.form-group textarea {
  font-family: 'Monaco', 'Menlo', 'Consolas', monospace;
  resize: vertical;
  min-height: 200px;
}

.form-group input:focus,
.form-group select:focus,
.form-group textarea:focus {
  outline: none;
  border-color: #667eea;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 24px;
}
</style>
