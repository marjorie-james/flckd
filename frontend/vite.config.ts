import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
//
// Local development is Docker-only: the dev server runs in the `frontend`
// compose service and proxies same-origin /api and /tiles calls to the
// self-hosted services over the private compose network (never a third party).
// Targets are overridable via env for other topologies.
export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    // In Docker on macOS, filesystem events don't propagate through the bind mount,
    // so Vite's watcher misses edits and HMR goes silent. The compose `frontend`
    // service sets VITE_USE_POLLING=true to fall back to polling; native (e.g. Linux)
    // dev leaves it unset, since polling is CPU-heavier and unnecessary there.
    watch: process.env.VITE_USE_POLLING === 'true' ? { usePolling: true, interval: 120 } : undefined,
    proxy: {
      '/api': {
        target: process.env.VITE_API_PROXY || 'http://backend:3000',
        changeOrigin: true,
      },
      // Requires the `tileserver` service to be enabled (see docker-compose).
      '/tiles': {
        target: process.env.VITE_TILES_PROXY || 'http://tileserver:8080',
        changeOrigin: true,
      },
    },
  },
  preview: {
    host: true,
    port: 4173,
  },
})
