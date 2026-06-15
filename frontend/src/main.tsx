import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
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
