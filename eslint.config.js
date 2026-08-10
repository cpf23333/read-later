import { globalIgnores } from 'eslint/config';
import { defineConfigWithVueTs, vueTsConfigs } from '@vue/eslint-config-typescript';
import pluginVue from 'eslint-plugin-vue';
import pluginVitest from '@vitest/eslint-plugin';
import skipFormatting from 'eslint-config-prettier/flat';

export default defineConfigWithVueTs(
  {
    name: 'app/files-to-lint',
    files: ['**/*.{vue,ts,mts,tsx}'],
  },

  globalIgnores([
    '.output/**',
    'node_modules/**',
    'server/node_modules/**',
    'server/dist/**',
    '.wxt/**',
  ]),

  ...pluginVue.configs['flat/essential'],
  vueTsConfigs.recommended,

  {
    ...pluginVitest.configs.recommended,
    files: ['src/**/__tests__/*', 'utils/**/__tests__/*', 'server/src/**/__tests__/*'],
  },

  {
    rules: {
      // 现有代码中使用了 any，先关闭避免大量报错
      '@typescript-eslint/no-explicit-any': 'off',
      // 未使用变量设为 warning，不影响构建
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // 单字组件名先允许
      'vue/multi-word-component-names': 'off',
    },
  },

  skipFormatting
);
