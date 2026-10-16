import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { ragDevProxy } from './vite.ragProxy.js';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  const proxy = ragDevProxy(env.VITE_RAG_API_URL);
  return {
    plugins: [react()],
    server: {
      port: 5173,
      host: true,
      proxy,
    },
    preview: {
      host: true,
      proxy,
    },
  };
});
