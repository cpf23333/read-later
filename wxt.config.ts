import { defineConfig } from 'wxt';
import { config as dotenvConfig } from 'dotenv';

// 加载 .env 文件（基础配置）
dotenvConfig();

// 从环境变量读取扩展固定 ID 的 Key
const extensionKey = process.env.EXTENSION_KEY;

// See https://wxt.dev/api/config.html
export default defineConfig({
  modules: ['@wxt-dev/module-vue'],
  vite: (env) => {
    return {
      build: {
        sourcemap: false,
      },
    };
  },
  manifest: {
    name: '稍后再看',
    description: '右键或长按保存链接，自动记录页面标题、截图和附近图片，支持多设备同步',
    version: '0.9.0',
    author: { email: 'cpf23333@example.com' },
    homepage_url: 'https://github.com/cpf23333/read-later',
    default_locale: 'zh_CN',
    // 固定扩展 ID（开发时稳定）
    ...(extensionKey && { key: extensionKey }),
    permissions: ['contextMenus', 'storage', 'activeTab', 'tabs', 'alarms'],
    host_permissions: ['<all_urls>'],
    action: {
      default_popup: 'popup.html',
      default_icon: {
        '16': 'icon/16.png',
        '32': 'icon/32.png',
        '48': 'icon/48.png',
        '128': 'icon/128.png',
      },
    },
    icons: {
      '16': 'icon/16.png',
      '32': 'icon/32.png',
      '48': 'icon/48.png',
      '128': 'icon/128.png',
    },
    options_page: 'options.html',
  },
  debug: false,
});
