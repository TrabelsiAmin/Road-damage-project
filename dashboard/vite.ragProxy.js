/**
 * Dev-server proxy for the Colab RAG API.
 * The browser calls same-origin /rag/* ; Vite forwards to VITE_RAG_API_URL
 * and adds the ngrok interstitial bypass header. No token is stored here.
 */

export function ragProxyTarget(rawUrl) {
  const value = String(rawUrl || '').trim();
  if (!value) return null;
  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  return url.origin;
}

export function ragDevProxy(rawUrl) {
  const target = ragProxyTarget(rawUrl);
  if (!target) return undefined;

  return {
    '/rag': {
      target,
      changeOrigin: true,
      secure: true,
      timeout: 120000,
      proxyTimeout: 120000,
      rewrite: (path) => path.replace(/^\/rag(?=\/|$)/, '') || '/',
      configure(proxy) {
        proxy.on('proxyReq', (proxyReq) => {
          proxyReq.setHeader('ngrok-skip-browser-warning', 'true');
        });
      },
    },
  };
}
