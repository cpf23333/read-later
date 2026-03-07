import { defineConfig } from 'wxt';

// See https://wxt.dev/api/config.html
export default defineConfig({
  modules: ['@wxt-dev/module-vue'],
  manifest: {
    name: 'UrlMem - 链接收藏夹',
    description: '右键或长按保存链接，自动记录页面标题、截图和附近图片',
    version: '1.0.0',
    permissions: [
      'contextMenus',
      'storage',
      'activeTab',
      'tabs',
    ],
    host_permissions: [
      '<all_urls>',
    ],
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
});
