import { createRouter, createWebHistory } from 'vue-router'
import { auth, authReady, isApproved, isStaff } from './auth'

// meta.public：不用登入也能看；meta.staff：只有權益部能進
const routes = [
  { path: '/login', component: () => import('./views/LoginView.vue'), meta: { public: true } },
  { path: '/register', component: () => import('./views/RegisterView.vue'), meta: { public: true } },
  { path: '/pending', component: () => import('./views/PendingView.vue'), meta: { public: true } },
  { path: '/', component: () => import('./views/HomeView.vue') },
  { path: '/mine', component: () => import('./views/MyPostsView.vue') },
  { path: '/new', component: () => import('./views/NewPostView.vue') },
  { path: '/posts/:id', component: () => import('./views/PostDetailView.vue') },
  { path: '/notifications', component: () => import('./views/NotificationsView.vue') },
  { path: '/admin', component: () => import('./views/AdminView.vue'), meta: { staff: true } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to) => {
  await authReady
  // 點完驗證連結會回到 /login 並已登入，直接帶進站
  if (to.path === '/login' && auth.session) return isApproved() ? '/' : '/pending'
  if (to.meta.public) return true
  if (!auth.session) return '/login'
  if (!isApproved()) return '/pending'
  if (to.meta.staff && !isStaff()) return '/'
  return true
})
