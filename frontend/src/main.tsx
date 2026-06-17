import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
// Self-hosted IBM Plex (bundled woff2, served from flckd's own origin — never a
// font CDN, which would leak the visitor's IP to a third party and break the
// anonymity model). Latin subset covers en + es. Plex Sans = body/UI; Plex Mono =
// wordmark, instrument labels, and route data.
import '@fontsource/ibm-plex-sans/latin-400.css'
import '@fontsource/ibm-plex-sans/latin-600.css'
import '@fontsource/ibm-plex-sans/latin-700.css'
import '@fontsource/ibm-plex-mono/latin-500.css'
import '@fontsource/ibm-plex-mono/latin-700.css'
import './index.css'
import App from './App.tsx'
import { loadConfig } from './config'

// Fetch runtime deploy config (API + tiles origins) before the first render so
// the very first API/tile request uses the configured hosts. loadConfig always
// resolves — a missing/invalid config.json falls back to same-origin defaults —
// so the app boots regardless.
loadConfig().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
})
