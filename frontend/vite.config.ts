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
