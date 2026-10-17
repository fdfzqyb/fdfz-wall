<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { formatDate } from '../constants'
import { auth, isStaff, isAdmin } from '../auth'
import TabBar from '../components/TabBar.vue'
import Icon from '../components/Icon.vue'

// 通知訊息由資料庫觸發器產生（見 schema.sql 第 4 節），按開頭的字分三種圖標
const noticeIcon = (msg) => (msg.includes('狀態已更新') ? 'status' : msg.startsWith('權益部回覆') ? 'chat' : 'check')

const router = useRouter()
const items = ref([])
const feedback = ref('')
const message = ref('')

// 公告：置頂的長期公告在前，短期通知依時間排在後面
const announcements = ref([])
const composing = ref(false)
const draft = ref({ title: '', body: '', audience: 'all', pinned: false })
const posting = ref(false)
const postError = ref('')

async function loadAnnouncements() {
  const { data } = await supabase.from('announcements').select('*')
    .order('pinned', { ascending: false }).order('created_at', { ascending: false })
  announcements.value = data ?? []
}

async function publish() {
  const { title, body, audience, pinned } = draft.value
  // 不用「沒填就停用按鈕」：iPhone 中文輸入法還在選字時，欄位看起來有字、程式卻還收不到，按了會沒反應
  if (!title.trim() || !body.trim()) {
    postError.value = '請填寫標題和內容'
    return
  }
  posting.value = true
  postError.value = ''
  const { error } = await supabase.from('announcements')
    .insert({ title: title.trim(), body: body.trim(), audience, pinned })
  posting.value = false
  if (error) {
    console.error(error)
    postError.value = '發布失敗：' + error.message
    return
  }
  postError.value = ''
  draft.value = { title: '', body: '', audience: 'all', pinned: false }
  composing.value = false
  loadAnnouncements()
}

const canDelete = (a) => isAdmin() || a.author_id === auth.session?.user.id

async function removeAnnouncement(a) {
  if (!window.confirm(`確定刪除公告「${a.title}」？`)) return
  const { error } = await supabase.from('announcements').delete().eq('id', a.id)
  if (!error) announcements.value = announcements.value.filter((x) => x.id !== a.id)
}

async function load() {
  const { data } = await supabase.from('notifications')
    .select('*').order('created_at', { ascending: false }).limit(50)
  items.value = data ?? []
}

async function open(n) {
  if (!n.is_read) await supabase.from('notifications').update({ is_read: true }).eq('id', n.id)
  if (n.post_id) router.push(`/posts/${n.post_id}`)
  else n.is_read = true
}

async function markAllRead() {
  const ids = items.value.filter((n) => !n.is_read).map((n) => n.id)
  if (ids.length) await supabase.from('notifications').update({ is_read: true }).in('id', ids)
  items.value.forEach((n) => (n.is_read = true))
}

async function sendFeedback() {
  const body = feedback.value.trim()
  if (!body) return
  const { error } = await supabase.from('feedback').insert({ body })
  message.value = error ? '送出失敗，請稍後再試' : '謝謝你的建議，權益部會看到'
  if (!error) feedback.value = ''
}

onMounted(() => {
  load()
  loadAnnouncements()
})
</script>

<template>
  <header class="topbar">
    <h1>通知</h1>
    <button class="btn plain small" @click="markAllRead">全部已讀</button>
  </header>
  <div class="page stack">
    <button v-if="isStaff() && !composing" class="btn block" @click="composing = true">
      <Icon name="megaphone" :size="20" /> 發布公告
    </button>

    <form v-if="composing" class="card stack" @submit.prevent="publish">
      <h3>發布公告</h3>
      <input v-model="draft.title" placeholder="標題" maxlength="60" />
      <textarea v-model="draft.body" placeholder="公告內容" />
      <div>
        <p class="muted small">給誰看</p>
        <div class="chips">
          <button type="button" class="chip" :class="{ on: draft.audience === 'all' }" @click="draft.audience = 'all'">全體用戶</button>
          <button type="button" class="chip" :class="{ on: draft.audience === 'staff' }" @click="draft.audience = 'staff'">僅權益部</button>
        </div>
      </div>
      <div>
        <p class="muted small">類型（短期通知兩週後自動消失）</p>
        <div class="chips">
          <button type="button" class="chip" :class="{ on: draft.pinned }" @click="draft.pinned = true">長期置頂</button>
          <button type="button" class="chip" :class="{ on: !draft.pinned }" @click="draft.pinned = false">短期兩週</button>
        </div>
      </div>
      <div class="actions">
        <button type="button" class="btn plain" @click="composing = false">取消</button>
        <button class="btn" :disabled="posting">{{ posting ? '發布中…' : '發布' }}</button>
      </div>
      <p v-if="postError" class="error">{{ postError }}</p>
    </form>

    <article v-for="a in announcements" :key="'a' + a.id" class="card announcement" :class="{ pinned: a.pinned }">
      <div class="ann-head">
        <Icon name="megaphone" :size="22" class="kind" />
        <h3>{{ a.title }}</h3>
      </div>
      <p class="ann-body">{{ a.body }}</p>
      <div class="ann-meta muted small">
        <span v-if="a.pinned" class="tag">置頂</span>
        <span v-if="a.audience === 'staff'" class="tag">僅權益部</span>
        <span>{{ formatDate(a.created_at) }}</span>
        <span v-if="a.expires_at">· {{ formatDate(a.expires_at) }}後消失</span>
        <button v-if="canDelete(a)" class="btn danger small del" @click="removeAnnouncement(a)">刪除</button>
      </div>
    </article>

    <p v-if="!items.length && !announcements.length" class="muted center">目前沒有通知。</p>
    <button v-for="n in items" :key="n.id" class="card item" :class="{ unread: !n.is_read }" @click="open(n)">
      <Icon :name="noticeIcon(n.message)" :size="22" class="kind" />
      <span class="text">{{ n.message }}</span>
      <span class="muted small">{{ formatDate(n.created_at) }}</span>
    </button>

    <form class="card stack" @submit.prevent="sendFeedback">
      <h3>對權益部的工作有什麼建議？</h3>
      <p class="muted small">權益部會看到你的姓名和學號。</p>
      <textarea v-model="feedback" placeholder="寫下你的建議" />
      <button class="btn">送出建議</button>
      <p v-if="message" class="note">{{ message }}</p>
    </form>
  </div>
  <TabBar />
</template>

<style scoped>
.item { display: flex; align-items: flex-start; gap: 12px; color: inherit; border: 0; width: 100%; text-align: left; font: inherit; cursor: pointer; }
.item.unread { border-left: 4px solid var(--orange); font-weight: 600; }
h3 { font-size: 17px; }
.item .text { flex: 1; }
.kind { color: var(--navy); margin-top: 2px; }
.actions { display: flex; justify-content: flex-end; gap: 8px; }
.actions .btn, .btn.block { display: flex; align-items: center; justify-content: center; gap: 6px; }
.announcement.pinned { background: var(--cream-logo); }
.ann-head { display: flex; align-items: center; gap: 10px; }
.ann-body { white-space: pre-wrap; margin: 8px 0; }
.ann-meta { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; }
.tag { background: var(--orange); color: var(--white); border-radius: 999px; padding: 1px 10px; font-size: 12px; font-weight: 700; }
.del { margin-left: auto; }
</style>
