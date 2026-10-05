import React from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { isFiveM } from './runtime'
import './styles.css'

if (isFiveM) document.documentElement.classList.add('fivem-runtime')

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
