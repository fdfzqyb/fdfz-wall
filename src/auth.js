import { reactive } from 'vue'
import { supabase } from './supabase'

// 全站共用的登入狀態：session 是 Supabase 的登入資訊，profile 是 profiles 表裡自己那一筆
export const auth = reactive({
  ready: false,
  session: null,
  profile: null,
  error: '', // 連不上 Supabase 時顯示給同學看的訊息
})

let markReady
// 路由會等這個 Promise，確認完登入狀態才決定要去哪一頁
export const authReady = new Promise((resolve) => (markReady = resolve))

export async function loadProfile() {
  if (!auth.session) {
    auth.profile = null
    return
  }
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', auth.session.user.id)
    .maybeSingle()
  auth.profile = data
}

async function loadSession() {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  auth.session = data.session
  await loadProfile()
}

// 在別的 fdfz.click 站登入或登出後，cookie 變了，但這個分頁不會收到通知；
// 所以每次切回這個分頁都重新讀一次，換了人或被登出就重新載入，讓路由重新判斷該去哪
async function recheck() {
  if (document.visibilityState !== 'visible') return
  const { data } = await supabase.auth.getSession()
  if (data.session?.user.id !== auth.session?.user.id) location.reload()
}

export async function initAuth() {
  // 網路很慢時不要一直空白：15 秒還沒好就先提示，之後連上了照樣會進站
  const slow = setTimeout(() => {
    auth.error = '連線很慢，還在嘗試連上伺服器…'
  }, 15000)
  try {
    await loadSession()
    auth.error = ''
  } catch (e) {
    console.error(e)
    auth.error = '連不上伺服器，請檢查網路後重新整理。'
    return
  } finally {
    clearTimeout(slow)
  }
  auth.ready = true
  markReady()

  supabase.auth.onAuthStateChange((_event, session) => {
    auth.session = session
    // 不能在這個回呼裡直接 await Supabase 查詢，所以放到下一輪執行
    setTimeout(loadProfile, 0)
  })
  document.addEventListener('visibilitychange', recheck)
}

export const isApproved = () => auth.profile?.verify_status === 'approved'
// admin（超級管理員）擁有權益部的全部權限，另外可以改別人的身份
export const isStaff = () => isApproved() && ['staff', 'admin'].includes(auth.profile?.role)
export const isAdmin = () => isApproved() && auth.profile?.role === 'admin'

export async function signOut() {
  await supabase.auth.signOut()
  auth.profile = null
}
