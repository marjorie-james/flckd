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
  build: {
    rollupOptions: {
      output: {
        // Keep the heavy, rarely-changing vendor libraries in their own chunks so
        // a routine frontend code change (most of our deploys) doesn't bust them
        // in users' caches. MapLibre alone is ~800 kB; isolating it means the map
        // chunk is downloaded once and reused across deploys. The app's own MapView
        // code is split out separately by the React.lazy import in PlanRoutePage.
        // Vite 8 / rolldown only accepts the function form of manualChunks.
        manualChunks(id) {
          if (id.includes("node_modules/maplibre-gl")) return "maplibre";
          if (id.includes("node_modules/react-dom") || id.includes("node_modules/react/")) {
            return "react";
          }
        },
      },
    },
  },
})
