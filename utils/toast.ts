import { h, render } from 'vue';
import Toast from '@/components/Toast.vue';

type ToastType = 'success' | 'error' | 'warning' | 'info';

interface ToastOptions {
  duration?: number;
}

export function showToast(message: string, type: ToastType = 'info', options: ToastOptions = {}) {
  const { duration = 3000 } = options;
  
  // 创建容器
  const container = document.createElement('div');
  document.body.appendChild(container);
  
  // 创建 vnode
  const vnode = h(Toast, {
    message,
    type,
    duration,
  });
  
  // 渲染
  render(vnode, container);
  
  // 动画结束后清理
  setTimeout(() => {
    render(null, container);
    document.body.removeChild(container);
  }, duration + 500);
}

export function showSuccess(message: string, options?: ToastOptions) {
  return showToast(message, 'success', options);
}

export function showError(message: string, options?: ToastOptions) {
  return showToast(message, 'error', options);
}

export function showWarning(message: string, options?: ToastOptions) {
  return showToast(message, 'warning', options);
}

export function showInfo(message: string, options?: ToastOptions) {
  return showToast(message, 'info', options);
}
