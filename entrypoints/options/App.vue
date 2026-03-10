<script lang="ts" setup>
import { ref, onMounted } from 'vue';
import { 
  CustomJsConfig,
} from '@/utils/storage';
import { 
  EXTRACTOR_TEMPLATES 
} from '@/utils/imageExtractor';
import{
  exportLinks,
  importLinks,
} from '@/utils/hybridStorage';
import {
  getServerConfig,
  saveServerConfig,
  testServerConnection,
  getCustomJsConfigs,
  saveCustomJsConfig,
  deleteCustomJsConfig,
} from '@/utils/apiStorage';

type TabType = 'extractor' | 'import' | 'server';
const activeTab = ref<TabType>('server');

// ===== 自定义JS配置 =====
const configs = ref<CustomJsConfig[]>([]);
const showAddModal = ref(false);
const editingConfig = ref<Partial<CustomJsConfig>>({
  name: '',
  code: '',
  enabled: true,
});
const isEditing = ref(false);

// ===== 导入导出 =====
const importFile = ref<File | null>(null);
const importMode = ref<'merge' | 'replace'>('merge');
const importResult = ref<{ imported: number; skipped: number; total: number } | null>(null);
const importing = ref(false);
const exporting = ref(false);

// ===== 服务器配置 =====
interface ServerConfig {
  enabled: boolean;
  url: string;
  apiKey: string;
}
const serverConfig = ref<ServerConfig>({
  enabled: false,
  url: '',
  apiKey: '',
});
const testingServer = ref(false);
const savingServer = ref(false);
const serverStatus = ref<{ success: boolean; message: string } | null>(null);

onMounted(async () => {
  await loadConfigs();
  await loadServerConfig();
});

// ===== 自定义JS配置方法 =====
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

// ===== 导入导出方法 =====
async function handleExport() {
  exporting.value = true;
  try {
    const json = await exportLinks();
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `readlater-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  } finally {
    exporting.value = false;
  }
}

function handleFileSelect(event: Event) {
  const input = event.target as HTMLInputElement;
  if (input.files && input.files[0]) {
    importFile.value = input.files[0];
    importResult.value = null;
  }
}

async function handleImport() {
  if (!importFile.value) {
    alert('请选择要导入的文件');
    return;
  }

  importing.value = true;
  importResult.value = null;

  try {
    const text = await importFile.value.text();
    const result = await importLinks(text, importMode.value);
    importResult.value = result;
    
    if (result.imported > 0) {
      alert(`导入成功！导入了 ${result.imported} 个链接，跳过了 ${result.skipped} 个重复链接。`);
    } else {
      alert(`导入完成，没有新链接被导入（${result.skipped} 个重复链接被跳过）。`);
    }
  } catch (error) {
    alert(`导入失败: ${error instanceof Error ? error.message : '未知错误'}`);
  } finally {
    importing.value = false;
    importFile.value = null;
    // 重置文件输入
    const fileInput = document.getElementById('import-file') as HTMLInputElement;
    if (fileInput) fileInput.value = '';
  }
}

// ===== 服务器配置方法 =====
async function loadServerConfig() {
  serverConfig.value = await getServerConfig();
}

async function testServer() {
  testingServer.value = true;
  serverStatus.value = null;
  
  try {
    const result = await testServerConnection(serverConfig.value.url, serverConfig.value.apiKey);
    serverStatus.value = result;
  } finally {
    testingServer.value = false;
  }
}

async function saveServer() {
  if (serverConfig.value.enabled) {
    if (!serverConfig.value.url.trim()) {
      alert('请输入服务器地址');
      return;
    }
    if (!serverConfig.value.apiKey.trim()) {
      alert('请输入 API Key');
      return;
    }
  }
  
  savingServer.value = true;
  try {
    await saveServerConfig(serverConfig.value);
    alert('服务器配置已保存');
    serverStatus.value = null;
  } finally {
    savingServer.value = false;
  }
}


</script>

<template>
  <div class="settings-container">
    <header class="header">
      <h1>稍后再看 - 设置</h1>
      <p>配置图片提取规则和同步选项</p>
    </header>

    <!-- Tab 导航 -->
    <nav class="tab-nav">
      <button 
        class="tab-btn" 
        :class="{ active: activeTab === 'extractor' }"
        @click="activeTab = 'extractor'"
      >
        图片提取器
      </button>
      <button 
        class="tab-btn" 
        :class="{ active: activeTab === 'import' }"
        @click="activeTab = 'import'"
      >
        导入/导出
      </button>
      <button 
        class="tab-btn" 
        :class="{ active: activeTab === 'server' }"
        @click="activeTab = 'server'"
      >
        🖥️ 服务器
      </button>
    </nav>

    <main class="main">
      <!-- 图片提取器 Tab -->
      <section v-if="activeTab === 'extractor'" class="section">
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

        <div class="help-content">
          <h3>使用说明</h3>
          <p>如果不配置自定义提取器，插件会按照以下顺序查找图片：</p>
          <ol>
            <li>链接自身的图片（如果是图片链接）</li>
            <li>链接内部的图片元素</li>
            <li>父元素中的图片</li>
            <li>相邻兄弟元素中的图片</li>
            <li>向上查找3层容器中的图片</li>
          </ol>
        </div>
      </section>

      <!-- 导入导出 Tab -->
      <section v-if="activeTab === 'import'" class="section">
        <h2>导入/导出数据</h2>
        
        <div class="import-export-grid">
          <!-- 导出 -->
          <div class="card">
            <h3>📥 导出数据</h3>
            <p>将"稍后再看"列表导出为 JSON 文件，用于备份或迁移。</p>
            <button class="btn btn-primary" @click="handleExport" :disabled="exporting">
              {{ exporting ? '导出中...' : '导出备份文件' }}
            </button>
          </div>

          <!-- 导入 -->
          <div class="card">
            <h3>📤 导入数据</h3>
            <p>从 JSON 文件导入链接到"稍后再看"。</p>
            
            <div class="form-group">
              <label>导入模式</label>
              <div class="radio-group">
                <label class="radio">
                  <input type="radio" v-model="importMode" value="merge" />
                  <span>合并（跳过重复链接）</span>
                </label>
                <label class="radio">
                  <input type="radio" v-model="importMode" value="replace" />
                  <span>覆盖（清空现有数据）</span>
                </label>
              </div>
            </div>

            <div class="form-group">
              <label>选择文件</label>
              <input 
                id="import-file"
                type="file" 
                accept=".json"
                @change="handleFileSelect"
              />
            </div>

            <button 
              class="btn btn-primary" 
              @click="handleImport" 
              :disabled="!importFile || importing"
            >
              {{ importing ? '导入中...' : '导入数据' }}
            </button>

            <div v-if="importResult" class="result-box">
              <p>✅ 成功导入 {{ importResult.imported }} 个链接</p>
              <p v-if="importResult.skipped > 0">⏭️ 跳过 {{ importResult.skipped }} 个重复链接</p>
            </div>
          </div>
        </div>
      </section>

      <!-- 服务器配置 Tab -->
      <section v-if="activeTab === 'server'" class="section">
        <h2>🖥️ SQLite 服务器</h2>
        <p class="section-desc">配置自建后端服务器，使用 SQLite 存储数据</p>

        <div class="webdav-form">
          <div class="form-group checkbox-group">
            <label class="checkbox">
              <input type="checkbox" v-model="serverConfig.enabled" />
              <span>启用服务器存储</span>
            </label>
          </div>

          <div class="form-group">
            <label>服务器地址</label>
            <input 
              v-model="serverConfig.url" 
              type="url" 
              placeholder="http://192.168.1.100:3000"
              :disabled="!serverConfig.enabled"
            />
            <span class="hint">例如：http://localhost:3000 或 http://NAS_IP:3000</span>
          </div>

          <div class="form-group">
            <label>API Key <span style="color: #ef4444;">*</span></label>
            <input 
              v-model="serverConfig.apiKey" 
              type="password" 
              placeholder="请输入 API Key"
              :disabled="!serverConfig.enabled"
            />
            <span class="hint">必须与服务端 API_KEY 环境变量一致</span>
          </div>

          <div class="form-actions">
            <button 
              class="btn btn-default" 
              @click="testServer" 
              :disabled="!serverConfig.enabled || !serverConfig.url || testingServer"
            >
              {{ testingServer ? '测试中...' : '测试连接' }}
            </button>
            <button 
              class="btn btn-primary" 
              @click="saveServer" 
              :disabled="savingServer"
            >
              {{ savingServer ? '保存中...' : '保存配置' }}
            </button>
          </div>

          <div v-if="serverStatus" class="connection-status" :class="serverStatus.success ? 'success' : 'error'">
            {{ serverStatus.message }}
          </div>

          <div class="help-content" style="margin-top: 24px;">
            <h3>部署指南</h3>
            <ol>
              <li>在 NAS/服务器上安装 Docker</li>
              <li>下载 server 文件夹到服务器</li>
              <li>运行：<code>docker-compose up -d</code></li>
              <li>数据将保存在 <code>./data</code> 目录</li>
            </ol>
            <p class="hint">相比 WebDAV，服务器模式支持真正的回收站和更快的查询</p>
          </div>
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
  margin-bottom: 20px;
}

.header h1 {
  font-size: 28px;
  margin-bottom: 8px;
}

.header p {
  opacity: 0.9;
}

/* Tab 导航 */
.tab-nav {
  display: flex;
  gap: 8px;
  margin-bottom: 20px;
  background: white;
  padding: 8px;
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
}

.tab-btn {
  flex: 1;
  padding: 12px 20px;
  border: none;
  background: transparent;
  color: #6b7280;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  border-radius: 8px;
  transition: all 0.2s;
}

.tab-btn:hover {
  background: #f3f4f6;
}

.tab-btn.active {
  background: #667eea;
  color: white;
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

.section h2 {
  font-size: 20px;
  color: #333;
  margin-bottom: 8px;
}

.section-desc {
  color: #6b7280;
  margin-bottom: 24px;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

.section-header h2 {
  margin-bottom: 0;
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

.btn-success {
  background: #10b981;
  color: white;
}

.btn-success:hover:not(:disabled) {
  background: #059669;
}

.btn-danger {
  background: #ef4444;
  color: white;
}

.btn-danger:hover:not(:disabled) {
  background: #dc2626;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn-sm {
  padding: 6px 12px;
  font-size: 13px;
}

/* 自定义JS配置 */
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

/* 导入导出 */
.import-export-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 20px;
}

.card {
  background: #f9fafb;
  padding: 24px;
  border-radius: 12px;
}

.card h3 {
  font-size: 18px;
  margin-bottom: 12px;
}

.card p {
  color: #6b7280;
  margin-bottom: 20px;
}

/* WebDAV */
.webdav-form {
  max-width: 600px;
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

.form-group input[type="text"],
.form-group input[type="url"],
.form-group input[type="password"],
.form-group input[type="number"],
.form-group input[type="file"],
.form-group select,
.form-group textarea {
  width: 100%;
  padding: 10px 14px;
  border: 1px solid #d1d5db;
  border-radius: 8px;
  font-size: 14px;
  font-family: inherit;
}

.form-group input:focus,
.form-group select:focus,
.form-group textarea:focus {
  outline: none;
  border-color: #667eea;
}

.form-group .hint {
  display: block;
  margin-top: 6px;
  font-size: 13px;
  color: #6b7280;
  font-weight: normal;
}

.form-group .warning-hint {
  display: block;
  margin-top: 6px;
  font-size: 12px;
  color: #dc2626;
  font-weight: normal;
}

.form-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.checkbox-group {
  margin-bottom: 16px;
}

.checkbox {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  font-weight: normal;
}

.checkbox input {
  width: 18px;
  height: 18px;
  cursor: pointer;
}

.radio-group {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.radio {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  font-weight: normal;
}

.radio input {
  width: 16px;
  height: 16px;
}

.form-actions {
  display: flex;
  gap: 12px;
  margin-top: 24px;
}

.connection-status {
  margin-top: 16px;
  padding: 12px 16px;
  border-radius: 8px;
  font-size: 14px;
}

.connection-status.success {
  background: #d1fae5;
  color: #065f46;
}

.connection-status.error {
  background: #fee2e2;
  color: #991b1b;
}

.sync-actions {
  margin-top: 32px;
  padding-top: 24px;
  border-top: 1px solid #e5e7eb;
}

.sync-actions h4 {
  margin-bottom: 16px;
}

.sync-buttons {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.sync-hint {
  margin-top: 16px;
  font-size: 13px;
  color: #6b7280;
  line-height: 1.6;
}

.result-box {
  margin-top: 16px;
  padding: 16px;
  border-radius: 8px;
  background: #f0fdf4;
  border: 1px solid #86efac;
}

.result-box.error {
  background: #fef2f2;
  border-color: #fca5a5;
}

.result-box .details {
  margin-top: 8px;
  display: flex;
  gap: 16px;
  font-size: 13px;
  color: #6b7280;
}

/* 通用 */
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
  margin-top: 32px;
  padding-top: 24px;
  border-top: 1px solid #e5e7eb;
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

.help-content ul {
  margin-left: 20px;
  margin-bottom: 16px;
}

.help-content li {
  margin-bottom: 8px;
}

.help-content code {
  background: #f3f4f6;
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Monaco', 'Menlo', monospace;
  font-size: 14px;
}

/* 模态框 */
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

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 24px;
}

.spinner {
  width: 32px;
  height: 32px;
  border: 3px solid #e5e7eb;
  border-top-color: #667eea;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin: 0 auto 12px;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.loading {
  text-align: center;
  padding: 40px;
  color: #6b7280;
}

/* 响应式 */
@media (max-width: 640px) {
  .header {
    padding: 24px;
  }

  .tab-nav {
    flex-direction: column;
  }

  .form-row {
    grid-template-columns: 1fr;
  }

  .sync-buttons {
    flex-direction: column;
  }

  .config-item {
    flex-direction: column;
    gap: 12px;
    align-items: flex-start;
  }
}
</style>
