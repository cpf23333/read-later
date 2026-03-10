<script lang="ts" setup>
import { ref, onMounted } from 'vue';

interface Props {
  message: string;
  type?: 'success' | 'error' | 'warning' | 'info';
  duration?: number;
}

const props = withDefaults(defineProps<Props>(), {
  type: 'info',
  duration: 3000,
});

const visible = ref(false);

onMounted(() => {
  visible.value = true;
  setTimeout(() => {
    visible.value = false;
  }, props.duration);
});

const typeIcon = {
  success: '✅',
  error: '❌',
  warning: '⚠️',
  info: 'ℹ️',
};

const typeClass = {
  success: 'toast-success',
  error: 'toast-error',
  warning: 'toast-warning',
  info: 'toast-info',
};
</script>

<template>
  <Transition name="toast">
    <div v-if="visible" class="toast" :class="typeClass[type]">
      <span class="toast-icon">{{ typeIcon[type] }}</span>
      <span class="toast-message">{{ message }}</span>
    </div>
  </Transition>
</template>

<style scoped>
.toast {
  position: fixed;
  top: 20px;
  right: 20px;
  padding: 12px 20px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  font-weight: 500;
  z-index: 9999;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  min-width: 200px;
  max-width: 400px;
}

.toast-success {
  background: #ecfdf5;
  color: #065f46;
  border: 1px solid #10b981;
}

.toast-error {
  background: #fef2f2;
  color: #991b1b;
  border: 1px solid #ef4444;
}

.toast-warning {
  background: #fffbeb;
  color: #92400e;
  border: 1px solid #f59e0b;
}

.toast-info {
  background: #eff6ff;
  color: #1e40af;
  border: 1px solid #3b82f6;
}

.toast-icon {
  font-size: 16px;
}

.toast-message {
  flex: 1;
}

.toast-enter-active,
.toast-leave-active {
  transition: all 0.3s ease;
}

.toast-enter-from {
  opacity: 0;
  transform: translateX(100%);
}

.toast-leave-to {
  opacity: 0;
  transform: translateX(100%);
}
</style>
