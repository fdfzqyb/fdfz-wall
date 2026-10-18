<script setup>
import { t, message as uiMessage } from '../i18n'
import { ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { formatDate, MODERATION_KIND, STATUS, CATEGORY_ICON } from '../constants'
import { auth, isAdmin } from '../auth'
import TabBar from '../components/TabBar.vue'
import Icon from '../components/Icon.vue'

const tab = ref('accounts')
const accounts = ref([])
const requests = ref([])
const feedbacks = ref([])
const moderations = ref([])
const users = ref([])
const userSearch = ref('')
const message = ref('')

// 待審核帳號，加上已拒絕但重新上傳了照片的帳號
async function loadAccounts() {
  const { data } = await supabase.from('profiles')
    .select('id, full_name, student_id, verify_status, created_at')
    .in('verify_status', ['pending', 'rejected'])
    .order('created_at')
  const list = []
  for (const p of data ?? []) {
    const { data: signed } = await supabase.storage
      .from('id-cards').createSignedUrl(`${p.id}/card.jpg`, 600)
    if (p.verify_status === 'rejected' && !signed) continue
    list.push({ ...p, photo: signed?.signedUrl ?? null })
  }
  accounts.value = list
}

async function review(p, approve) {
  const { error } = await supabase.rpc('review_account', { target: p.id, approve })
  if (error) return (message.value = error.message)
  // 不論通過或拒絕，審核完就刪除學生證照片
  await supabase.storage.from('id-cards').remove([`${p.id}/card.jpg`])
  accounts.value = accounts.value.filter((a) => a.id !== p.id)
  message.value = uiMessage(approve ? '已通過 {name}，照片已刪除' : '已拒絕 {name}，照片已刪除', { name: p.full_name })
}

// 刪除未通過審核的帳號，讓同學可以用同一個學號和 email 重新註冊
async function removeAccount(p) {
  if (!window.confirm(t('確定刪除 {name}（{sid}）的註冊？對方需要重新註冊。', { name: p.full_name, sid: p.student_id }))) return
  await supabase.storage.from('id-cards').remove([`${p.id}/card.jpg`])
  const { error } = await supabase.rpc('delete_unapproved_account', { target: p.id })
  if (error) return (message.value = error.message)
  accounts.value = accounts.value.filter((a) => a.id !== p.id)
  users.value = users.value.filter((u) => u.id !== p.id)
  message.value = uiMessage('已刪除 {name} 的註冊，對方可以重新註冊', { name: p.full_name })
}

async function loadRequests() {
  const { data } = await supabase.from('change_requests')
    .select('*, posts(title, problem, suggestion, expected, help_offer)')
    .eq('status', 'pending').order('created_at')
  requests.value = data ?? []
}

async function decide(r, approve) {
  const { error } = await supabase.rpc('review_change_request', { req_id: r.id, approve })
  if (error) return (message.value = error.message)
  requests.value = requests.value.filter((x) => x.id !== r.id)
  message.value = approve ? '已同意申請' : '已拒絕申請'
}

async function loadModerations() {
  const { data } = await supabase.from('moderation_requests')
    .select('*, posts(title, problem), profiles!created_by(full_name), moderation_votes(staff_id)')
    .eq('status', 'pending').order('created_at')
  moderations.value = data ?? []
}

// 忘記密碼：先用學號查到人，核對身份後再產生臨時密碼
const resetSid = ref('')
const resetTarget = ref(null)
const tempPassword = ref('')

async function findForReset() {
  tempPassword.value = ''
  message.value = ''
  const { data } = await supabase.from('profiles')
    .select('full_name, student_id, role').eq('student_id', resetSid.value.trim()).maybeSingle()
  resetTarget.value = data
  if (!data) message.value = '找不到這個學號'
}

async function resetPassword() {
  if (!window.confirm(t('確定重設 {name} 的密碼？對方原本的密碼會失效。', { name: resetTarget.value.full_name }))) return
  const { data, error } = await supabase.rpc('reset_password', { sid: resetTarget.value.student_id })
  if (error) return (message.value = error.message)
  tempPassword.value = data
}

const votedByMe = (m) => m.moderation_votes.some((v) => v.staff_id === auth.session.user.id)

async function voteModeration(m, approve) {
  const { data, error } = await supabase.rpc('vote_moderation', { req_id: m.id, approve })
  if (error) return (message.value = error.message)
  message.value = data === 'applied' ? '已確認，處理已生效，發布者會收到通知' : data === 'rejected' ? '已駁回申請' : '已確認，還需要另一位權益部確認'
  await loadModerations()
}

async function loadFeedback() {
  const { data } = await supabase.from('feedback')
    .select('id, body, created_at, profiles(full_name, student_id)')
    .order('created_at', { ascending: false }).limit(100)
  feedbacks.value = data ?? []
}

// 以下只有超級管理員用得到；資料庫也會檢查身份，普通權益部呼叫會被拒絕
const ROLE_LABEL = { student: '普通同學', staff: '權益部', admin: '管理員' }
const STATUS_LABEL = { pending: '待審核', approved: '已通過', rejected: '未通過' }

async function loadUsers() {
  const { data } = await supabase.rpc('admin_list_users')
  users.value = data ?? []
}

function filteredUsers() {
  const q = userSearch.value.trim().toLowerCase()
  if (!q) return users.value
  return users.value.filter((u) =>
    [u.full_name, u.student_id, u.email].some((v) => v?.toLowerCase().includes(q)))
}

async function changeRole(u, newRole) {
  const { error } = await supabase.rpc('set_user_role', { target: u.id, new_role: newRole })
  if (error) return (message.value = error.message)
  message.value = uiMessage('已把 {name} 設為{role}', { name: u.full_name, role: uiMessage(ROLE_LABEL[newRole]) })
  await loadUsers()
}

// 導出帖子為 CSV，給權益部整理用（含發布者姓名學號，請勿外傳）
const EXPORT_RANGES = { month: '最近一個月', half: '最近六個月', all: '所有時間' }
const categories = ref([])
const exportRange = ref('month')
const exportCategory = ref('all')
const exporting = ref(false)

async function loadCategories() {
  const { data } = await supabase.from('categories').select('id, name').order('sort_order')
  categories.value = data ?? []
}

function exportSince() {
  if (exportRange.value === 'all') return null
  const d = new Date()
  d.setMonth(d.getMonth() - (exportRange.value === 'month' ? 1 : 6))
  return d.toISOString()
}

const pad = (n) => String(n).padStart(2, '0')
function fullDate(iso, withTime = true) {
  const d = new Date(iso)
  const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  return withTime ? `${day} ${pad(d.getHours())}:${pad(d.getMinutes())}` : day
}

// 每格都加引號；開頭是 = + - @ 的加一個 ' ，避免 Excel 把同學填的內容當成公式執行
function csvCell(v) {
  let s = v == null ? '' : String(v)
  if (/^[=+\-@]/.test(s)) s = `'${s}`
  return `"${s.replace(/"/g, '""')}"`
}

async function exportPosts() {
  exporting.value = true
  message.value = ''
  const since = exportSince()
  const rows = []
  // Supabase 一次最多回傳 1000 筆，分批拿完
  for (let from = 0; ; from += 1000) {
    let q = supabase.from('posts')
      .select('id, title, problem, suggestion, expected, help_offer, status, moderation, created_at, updated_at, categories(name), profiles!author_id(full_name, student_id), replies(body, created_at)')
      .order('created_at').range(from, from + 999)
    if (since) q = q.gte('created_at', since)
    if (exportCategory.value !== 'all') q = q.eq('category_id', exportCategory.value)
    const { data, error } = await q
    if (error) {
      exporting.value = false
      return (message.value = error.message)
    }
    rows.push(...data)
    if (data.length < 1000) break
  }
  exporting.value = false
  if (!rows.length) return (message.value = '這個範圍內沒有帖子')

  const MOD_LABEL = { hidden: '已隱藏', redacted: '涉及個人信息' }
  const header = ['編號', '發帖日期', '分類', '標題', '問題描述', '可行建議', '預期解決效果', '願意付出的努力',
    '處理狀態', '敏感處理', '權益部回覆', '發布者姓名', '學號', '最後更新'].map((h) => t(h))
  const lines = rows.map((p) => [
    p.id,
    fullDate(p.created_at),
    t(p.categories?.name ?? ''),
    p.title,
    p.problem,
    p.suggestion,
    p.expected,
    p.help_offer,
    t(STATUS[p.status]?.label ?? p.status),
    p.moderation ? t(MOD_LABEL[p.moderation]) : '',
    [...p.replies].sort((a, b) => a.created_at.localeCompare(b.created_at))
      .map((r) => `${fullDate(r.created_at)}　${r.body}`).join('\n'),
    p.profiles?.full_name,
    p.profiles?.student_id,
    fullDate(p.updated_at),
  ].map(csvCell).join(','))

  // 開頭加 BOM，Excel 打開才不會變亂碼
  const csv = '\uFEFF' + [header.map(csvCell).join(','), ...lines].join('\r\n')
  const catName = exportCategory.value === 'all'
    ? t('全部分類') : t(categories.value.find((c) => c.id === exportCategory.value)?.name ?? '')
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  a.download = `${t('權益牆帖子')}_${catName}_${t(EXPORT_RANGES[exportRange.value])}_${fullDate(new Date(), false)}.csv`
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 1000)
  message.value = uiMessage('已導出 {count} 個帖子', { count: rows.length })
}

onMounted(() => Promise.all([
  loadCategories(), loadAccounts(), loadRequests(), loadModerations(), loadFeedback(), isAdmin() ? loadUsers() : null,
]))
</script>

<template>
  <header class="topbar"><h1>{{ t('權益部後台') }}</h1></header>
  <div class="page stack">
    <div class="chips">
      <button class="chip" :class="{ on: tab === 'accounts' }" @click="tab = 'accounts'">{{ t('帳號審核') }} {{ accounts.length }}</button>
      <button class="chip" :class="{ on: tab === 'requests' }" @click="tab = 'requests'">{{ t('修改刪除申請') }} {{ requests.length }}</button>
      <button class="chip" :class="{ on: tab === 'moderation' }" @click="tab = 'moderation'">{{ t('敏感帖子') }} {{ moderations.length }}</button>
      <button class="chip" :class="{ on: tab === 'feedback' }" @click="tab = 'feedback'">{{ t('同學建議') }}</button>
      <button class="chip" :class="{ on: tab === 'reset' }" @click="tab = 'reset'">{{ t('重設密碼') }}</button>
      <button class="chip" :class="{ on: tab === 'export' }" @click="tab = 'export'">{{ t('導出帖子') }}</button>
      <button v-if="isAdmin()" class="chip" :class="{ on: tab === 'users' }" @click="tab = 'users'">{{ t('用戶管理') }}</button>
    </div>
    <p v-if="message" class="note">{{ t(message) }}</p>

    <template v-if="tab === 'accounts'">
      <p v-if="!accounts.length" class="muted center">{{ t('沒有待審核的帳號。') }}</p>
      <div v-for="p in accounts" :key="p.id" class="card stack">
        <div>
          <strong>{{ p.full_name }}</strong> · {{ p.student_id }}
          <span v-if="p.verify_status === 'rejected'" class="muted small">{{ t('（曾被拒絕，已重新上傳）') }}</span>
        </div>
        <img v-if="p.photo" :src="p.photo" :alt="t('校園卡')" class="card-photo" />
        <p v-else class="muted small">{{ t('還沒有上傳校園卡照片') }}</p>
        <div class="actions">
          <button class="btn" :disabled="!p.photo" @click="review(p, true)">{{ t('通過') }}</button>
          <button class="btn danger" @click="review(p, false)">{{ t('拒絕') }}</button>
          <button class="btn plain" @click="removeAccount(p)">{{ t('刪除註冊') }}</button>
        </div>
      </div>
    </template>

    <template v-if="tab === 'requests'">
      <p v-if="!requests.length" class="muted center">{{ t('沒有待審批的申請。') }}</p>
      <div v-for="r in requests" :key="r.id" class="card stack">
        <div>
          <span class="status" :class="r.kind === 'delete' ? 'st-wontfix' : 'st-progress'">
            {{ r.kind === 'delete' ? t('申請刪除') : t('申請修改') }}
          </span>
          <router-link :to="`/posts/${r.post_id}`"> {{ r.posts?.title }}</router-link>
        </div>
        <div v-if="r.kind === 'edit'" class="diff">
          <div><h4>{{ t('原內容') }}</h4>
            <p><b>{{ r.posts?.title }}</b></p><p>{{ r.posts?.problem }}</p>
            <p>{{ r.posts?.suggestion }}</p><p>{{ r.posts?.expected }}</p><p>{{ r.posts?.help_offer }}</p>
          </div>
          <div><h4>{{ t('新內容') }}</h4>
            <p><b>{{ r.new_title }}</b></p><p>{{ r.new_problem }}</p>
            <p>{{ r.new_suggestion }}</p><p>{{ r.new_expected }}</p><p>{{ r.new_help_offer }}</p>
          </div>
        </div>
        <div class="actions">
          <button class="btn" @click="decide(r, true)">{{ t('同意') }}</button>
          <button class="btn danger" @click="decide(r, false)">{{ t('不同意') }}</button>
        </div>
      </div>
    </template>

    <template v-if="tab === 'moderation'">
      <p class="muted small">{{ t('每個申請要兩位權益部確認才會生效，提出申請的人算第一位。') }}</p>
      <p v-if="!moderations.length" class="muted center">{{ t('沒有等待確認的敏感帖子。') }}</p>
      <div v-for="m in moderations" :key="m.id" class="card stack">
        <div>
          <span class="status" :class="m.kind === 'hide' ? 'st-wontfix' : 'st-progress'">{{ t(MODERATION_KIND[m.kind].label) }}</span>
          <router-link :to="`/posts/${m.post_id}`"> {{ m.posts?.title }}</router-link>
        </div>
        <p class="body muted small">{{ m.posts?.problem }}</p>
        <p class="body"><b>{{ t('原因：') }}</b>{{ m.reason }}</p>
        <p class="muted small">{{ m.profiles?.full_name }} {{ t('提出') }} · {{ formatDate(m.created_at) }} · {{ t('已確認') }} {{ m.moderation_votes.length }}/2</p>
        <div class="actions">
          <button class="btn" :disabled="votedByMe(m)" @click="voteModeration(m, true)">{{ votedByMe(m) ? t('你已確認') : t('確認') }}</button>
          <button class="btn danger" @click="voteModeration(m, false)">{{ t('駁回') }}</button>
        </div>
      </div>
    </template>

    <template v-if="tab === 'feedback'">
      <p v-if="!feedbacks.length" class="muted center">{{ t('還沒有建議。') }}</p>
      <div v-for="f in feedbacks" :key="f.id" class="card">
        <p class="body">{{ f.body }}</p>
        <span class="muted small">{{ f.profiles?.full_name }}（{{ f.profiles?.student_id }}） · {{ formatDate(f.created_at) }}</span>
      </div>
    </template>

    <template v-if="tab === 'reset'">
      <p class="note">{{ t('同學忘記密碼時，請先當面核對校園卡，確認是本人再重設。') }}</p>
      <form class="search-row" @submit.prevent="findForReset">
        <input v-model="resetSid" inputmode="numeric" :placeholder="t('輸入八位學號')" required />
        <button class="btn small">{{ t('查詢') }}</button>
      </form>
      <div v-if="resetTarget" class="card stack">
        <div><strong>{{ resetTarget.full_name }}</strong> · {{ resetTarget.student_id }} · {{ t(ROLE_LABEL[resetTarget.role]) }}</div>
        <template v-if="tempPassword">
          <p>{{ t('臨時密碼：') }}</p>
          <p class="temp">{{ tempPassword }}</p>
          <p class="muted small">{{ t('請把這組密碼告訴同學。他用學號和臨時密碼登入後，網站會要求他改成自己的密碼。離開這一頁後就看不到這組密碼了。') }}</p>
        </template>
        <button v-else class="btn" @click="resetPassword">{{ t('產生臨時密碼') }}</button>
      </div>
    </template>

    <template v-if="tab === 'export'">
      <p class="note">{{ t('導出的表格包含發布者的姓名和學號，只供權益部內部整理，請不要外傳。') }}</p>
      <div class="card stack">
        <div>
          <h4>{{ t('時間') }}</h4>
          <div class="chips">
            <button v-for="(label, key) in EXPORT_RANGES" :key="key" class="chip" :class="{ on: exportRange === key }" @click="exportRange = key">{{ t(label) }}</button>
          </div>
        </div>
        <div>
          <h4>{{ t('分類') }}</h4>
          <div class="chips">
            <button class="chip" :class="{ on: exportCategory === 'all' }" @click="exportCategory = 'all'">{{ t('全部分類') }}</button>
            <button v-for="c in categories" :key="c.id" class="chip" :class="{ on: exportCategory === c.id }" @click="exportCategory = c.id">
              <Icon v-if="CATEGORY_ICON[c.name]" :name="CATEGORY_ICON[c.name]" :size="16" />{{ t(c.name) }}
            </button>
          </div>
        </div>
        <p class="muted small">{{ t('按發帖日期篩選。表格包含日期、分類、同學填寫的所有內容、處理狀態、權益部回覆，以及發布者姓名學號，可以用 Excel 或 WPS 打開。') }}</p>
        <button class="btn block" :disabled="exporting" @click="exportPosts">{{ exporting ? t('導出中…') : t('導出 CSV') }}</button>
      </div>
    </template>

    <template v-if="tab === 'users' && isAdmin()">
      <p class="note">{{ t('只有管理員看得到這一頁。升為權益部的同學可以看到發帖人和提建議同學的姓名學號，請謹慎操作。') }}</p>
      <input v-model="userSearch" type="search" :placeholder="t('搜尋姓名、學號或 email')" />
      <p class="muted small">{{ t('共 {count} 個帳號', { count: users.length }) }}</p>
      <div v-for="u in filteredUsers()" :key="u.id" class="card user">
        <div>
          <strong>{{ u.full_name }}</strong> · {{ u.student_id }}
          <p class="muted small">{{ u.email }} · {{ t(STATUS_LABEL[u.verify_status]) }} · {{ formatDate(u.created_at) }}</p>
        </div>
        <span v-if="u.role === 'admin' || u.id === auth.session.user.id" class="muted small">{{ t(ROLE_LABEL[u.role]) }}</span>
        <div v-else class="user-actions">
          <select :value="u.role" @change="changeRole(u, $event.target.value)">
            <option value="student">{{ t('普通同學') }}</option>
            <option value="staff">{{ t('權益部') }}</option>
          </select>
          <button v-if="u.role === 'student' && u.verify_status !== 'approved'" class="btn small danger" @click="removeAccount(u)">{{ t('刪除') }}</button>
        </div>
      </div>
    </template>
  </div>
  <TabBar />
</template>

<style scoped>
.user { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.user p { margin: 2px 0 0; }
.user-actions { display: flex; gap: 8px; align-items: center; flex: none; }
.user select { width: auto; flex: none; }
.search-row { display: flex; gap: 10px; }
.search-row .btn { flex: none; }
.temp { font-size: 28px; font-weight: 700; letter-spacing: 3px; color: var(--navy); font-family: ui-monospace, monospace; margin: 0; }
.card-photo { width: 100%; border-radius: 10px; }
.actions { display: flex; gap: 10px; }
.diff { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 14px; }
.diff p, .body { margin: 0 0 6px; white-space: pre-wrap; }
h4 { font-size: 13px; color: var(--muted); margin: 0 0 4px; }
</style>
