import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { ragDevProxy } from './vite.ragProxy.js';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  const proxy = ragDevProxy(env.VITE_RAG_API_URL);
  return {
    plugins: [react()],
    build: {
      chunkSizeWarningLimit: 600,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (id.includes('node_modules')) {
              if (id.includes('leaflet')) return 'leaflet';
              if (id.includes('@supabase')) return 'supabase';
              if (id.includes('lucide-react')) return 'icons';
              if (id.includes('react') || id.includes('react-dom')) return 'vendor';
            }
          },
        },
      },
    },
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
