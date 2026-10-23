import { createRouter, createWebHistory } from 'vue-router'
import { auth, authReady, isApproved, isStaff } from './auth'
import { accountUrl } from './fdfz'

// 登入、註冊、等待審核、改密碼都在帳號中心 account.fdfz.click，這裡舊的網址直接轉過去
const toAccount = (path) => () => {
  window.location.assign(accountUrl(path, location.origin + '/'))
  return false
}

// meta.staff：只有權益部能進
const routes = [
  { path: '/login', beforeEnter: toAccount('/login'), component: {} },
  { path: '/register', beforeEnter: toAccount('/register'), component: {} },
  { path: '/pending', beforeEnter: toAccount('/pending'), component: {} },
  { path: '/', component: () => import('./views/HomeView.vue') },
  { path: '/mine', component: () => import('./views/MyPostsView.vue') },
  { path: '/new', component: () => import('./views/NewPostView.vue') },
  { path: '/posts/:id', component: () => import('./views/PostDetailView.vue') },
  { path: '/notifications', component: () => import('./views/NotificationsView.vue') },
  { path: '/account', component: () => import('./views/AccountView.vue') },
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
  if (['/login', '/register', '/pending'].includes(to.path)) return true
  // 沒登入、還沒通過審核、權益部重設成臨時密碼：都送到帳號中心處理，好了會回到這一頁
  const back = location.origin + to.fullPath
  const fix = !auth.session ? '/login' : !isApproved() ? '/pending' : auth.profile?.must_change_password ? '/' : null
  if (fix) {
    window.location.assign(accountUrl(fix, back))
    return false
  }
  if (to.meta.staff && !isStaff()) return '/'
  return true
})
