import { createApp } from 'vue'
import App from './App.vue'
import { router } from './router'
import { initAuth } from './auth'
import './styles.css'

// 先確認登入狀態，再顯示畫面，避免已登入的人閃一下登入頁
initAuth().then(() => {
  createApp(App).use(router).mount('#app')
})
