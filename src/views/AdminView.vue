<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { formatDate, MODERATION_KIND } from '../constants'
import { auth, isAdmin } from '../auth'
import TabBar from '../components/TabBar.vue'

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
  message.value = `已${approve ? '通過' : '拒絕'} ${p.full_name}，照片已刪除`
}

// 刪除未通過審核的帳號，讓同學可以用同一個學號和 email 重新註冊
async function removeAccount(p) {
  if (!window.confirm(`確定刪除 ${p.full_name}（${p.student_id}）的註冊？對方需要重新註冊。`)) return
  await supabase.storage.from('id-cards').remove([`${p.id}/card.jpg`])
  const { error } = await supabase.rpc('delete_unapproved_account', { target: p.id })
  if (error) return (message.value = error.message)
  accounts.value = accounts.value.filter((a) => a.id !== p.id)
  users.value = users.value.filter((u) => u.id !== p.id)
  message.value = `已刪除 ${p.full_name} 的註冊，對方可以重新註冊`
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
    .select('*, posts(title, problem), profiles(full_name), moderation_votes(staff_id)')
    .eq('status', 'pending').order('created_at')
  moderations.value = data ?? []
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
  message.value = `已把 ${u.full_name} 設為${ROLE_LABEL[newRole]}`
  await loadUsers()
}

onMounted(() => Promise.all([
  loadAccounts(), loadRequests(), loadModerations(), loadFeedback(), isAdmin() ? loadUsers() : null,
]))
</script>

<template>
  <header class="topbar"><h1>權益部後台</h1></header>
  <div class="page stack">
    <div class="chips">
      <button class="chip" :class="{ on: tab === 'accounts' }" @click="tab = 'accounts'">帳號審核 {{ accounts.length }}</button>
      <button class="chip" :class="{ on: tab === 'requests' }" @click="tab = 'requests'">修改刪除申請 {{ requests.length }}</button>
      <button class="chip" :class="{ on: tab === 'moderation' }" @click="tab = 'moderation'">敏感帖子 {{ moderations.length }}</button>
      <button class="chip" :class="{ on: tab === 'feedback' }" @click="tab = 'feedback'">同學建議</button>
      <button v-if="isAdmin()" class="chip" :class="{ on: tab === 'users' }" @click="tab = 'users'">用戶管理</button>
    </div>
    <p v-if="message" class="note">{{ message }}</p>

    <template v-if="tab === 'accounts'">
      <p v-if="!accounts.length" class="muted center">沒有待審核的帳號。</p>
      <div v-for="p in accounts" :key="p.id" class="card stack">
        <div>
          <strong>{{ p.full_name }}</strong> · {{ p.student_id }}
          <span v-if="p.verify_status === 'rejected'" class="muted small">（曾被拒絕，已重新上傳）</span>
        </div>
        <img v-if="p.photo" :src="p.photo" alt="學生證" class="card-photo" />
        <p v-else class="muted small">還沒有上傳學生證照片</p>
        <div class="actions">
          <button class="btn" :disabled="!p.photo" @click="review(p, true)">通過</button>
          <button class="btn danger" @click="review(p, false)">拒絕</button>
          <button class="btn plain" @click="removeAccount(p)">刪除註冊</button>
        </div>
      </div>
    </template>

    <template v-if="tab === 'requests'">
      <p v-if="!requests.length" class="muted center">沒有待審批的申請。</p>
      <div v-for="r in requests" :key="r.id" class="card stack">
        <div>
          <span class="status" :class="r.kind === 'delete' ? 'st-wontfix' : 'st-progress'">
            {{ r.kind === 'delete' ? '申請刪除' : '申請修改' }}
          </span>
          <router-link :to="`/posts/${r.post_id}`"> {{ r.posts?.title }}</router-link>
        </div>
        <div v-if="r.kind === 'edit'" class="diff">
          <div><h4>原內容</h4>
            <p><b>{{ r.posts?.title }}</b></p><p>{{ r.posts?.problem }}</p>
            <p>{{ r.posts?.suggestion }}</p><p>{{ r.posts?.expected }}</p><p>{{ r.posts?.help_offer }}</p>
          </div>
          <div><h4>新內容</h4>
            <p><b>{{ r.new_title }}</b></p><p>{{ r.new_problem }}</p>
            <p>{{ r.new_suggestion }}</p><p>{{ r.new_expected }}</p><p>{{ r.new_help_offer }}</p>
          </div>
        </div>
        <div class="actions">
          <button class="btn" @click="decide(r, true)">同意</button>
          <button class="btn danger" @click="decide(r, false)">不同意</button>
        </div>
      </div>
    </template>

    <template v-if="tab === 'moderation'">
      <p class="muted small">每個申請要兩位權益部確認才會生效，提出申請的人算第一位。</p>
      <p v-if="!moderations.length" class="muted center">沒有等待確認的敏感帖子。</p>
      <div v-for="m in moderations" :key="m.id" class="card stack">
        <div>
          <span class="status" :class="m.kind === 'hide' ? 'st-wontfix' : 'st-progress'">{{ MODERATION_KIND[m.kind].label }}</span>
          <router-link :to="`/posts/${m.post_id}`"> {{ m.posts?.title }}</router-link>
        </div>
        <p class="body muted small">{{ m.posts?.problem }}</p>
        <p class="body"><b>原因：</b>{{ m.reason }}</p>
        <p class="muted small">{{ m.profiles?.full_name }} 提出 · {{ formatDate(m.created_at) }} · 已確認 {{ m.moderation_votes.length }}/2</p>
        <div class="actions">
          <button class="btn" :disabled="votedByMe(m)" @click="voteModeration(m, true)">{{ votedByMe(m) ? '你已確認' : '確認' }}</button>
          <button class="btn danger" @click="voteModeration(m, false)">駁回</button>
        </div>
      </div>
    </template>

    <template v-if="tab === 'feedback'">
      <p v-if="!feedbacks.length" class="muted center">還沒有建議。</p>
      <div v-for="f in feedbacks" :key="f.id" class="card">
        <p class="body">{{ f.body }}</p>
        <span class="muted small">{{ f.profiles?.full_name }}（{{ f.profiles?.student_id }}） · {{ formatDate(f.created_at) }}</span>
      </div>
    </template>

    <template v-if="tab === 'users' && isAdmin()">
      <p class="note">只有管理員看得到這一頁。升為權益部的同學可以看到發帖人和提建議同學的姓名學號，請謹慎操作。</p>
      <input v-model="userSearch" type="search" placeholder="搜尋姓名、學號或 email" />
      <p class="muted small">共 {{ users.length }} 個帳號</p>
      <div v-for="u in filteredUsers()" :key="u.id" class="card user">
        <div>
          <strong>{{ u.full_name }}</strong> · {{ u.student_id }}
          <p class="muted small">{{ u.email }} · {{ STATUS_LABEL[u.verify_status] }} · {{ formatDate(u.created_at) }}</p>
        </div>
        <span v-if="u.role === 'admin' || u.id === auth.session.user.id" class="muted small">{{ ROLE_LABEL[u.role] }}</span>
        <div v-else class="user-actions">
          <select :value="u.role" @change="changeRole(u, $event.target.value)">
            <option value="student">普通同學</option>
            <option value="staff">權益部</option>
          </select>
          <button v-if="u.role === 'student' && u.verify_status !== 'approved'" class="btn small danger" @click="removeAccount(u)">刪除</button>
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
.card-photo { width: 100%; border-radius: 10px; }
.actions { display: flex; gap: 10px; }
.diff { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 14px; }
.diff p, .body { margin: 0 0 6px; white-space: pre-wrap; }
h4 { font-size: 13px; color: var(--muted); margin: 0 0 4px; }
</style>
