<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { isStaff } from '../auth'
import { STATUS, formatDate } from '../constants'
import MeTooButton from '../components/MeTooButton.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)

const post = ref(null)
const replies = ref([])
const author = ref(null)        // 只有權益部拿得到
const pendingRequest = ref(null) // 自己的問題有沒有等待中的修改 / 刪除申請
const confirmDelete = ref(false)
const replyText = ref('')
const message = ref('')
const loading = ref(true)

async function load() {
  const [{ data: p }, { data: r }] = await Promise.all([
    supabase.from('post_feed').select('*').eq('id', id).maybeSingle(),
    supabase.from('replies').select('id, body, created_at').eq('post_id', id).order('created_at'),
  ])
  post.value = p
  replies.value = r ?? []

  if (p?.is_mine) {
    const { data } = await supabase.from('change_requests')
      .select('kind').eq('post_id', id).eq('status', 'pending').maybeSingle()
    pendingRequest.value = data
  }
  if (isStaff()) {
    const { data } = await supabase.from('posts')
      .select('profiles(full_name, student_id)').eq('id', id).single()
    author.value = data?.profiles
  }
  loading.value = false
}

async function requestDelete() {
  const { error } = await supabase.from('change_requests').insert({ post_id: id, kind: 'delete' })
  confirmDelete.value = false
  message.value = error ? '送出失敗，請稍後再試' : '刪除申請已送出，等權益部同意後就會刪除'
  if (!error) pendingRequest.value = { kind: 'delete' }
}

async function changeStatus(e) {
  const { error } = await supabase.from('posts').update({ status: e.target.value }).eq('id', id)
  message.value = error ? '更新失敗' : '狀態已更新，發布者會收到通知'
  if (!error) post.value.status = e.target.value
}

async function sendReply() {
  const body = replyText.value.trim()
  if (!body) return
  const { error } = await supabase.from('replies').insert({ post_id: id, body })
  if (error) {
    message.value = '回覆失敗'
    return
  }
  replyText.value = ''
  await load()
}

onMounted(load)
</script>

<template>
  <header class="topbar">
    <button class="back" @click="router.back()">‹</button>
    <h1>問題詳情</h1>
  </header>
  <div class="page">
    <p v-if="loading" class="muted center">載入中…</p>
    <p v-else-if="!post" class="muted center">找不到這個問題，可能已被刪除。</p>
    <div v-else class="stack">
      <div class="card stack">
        <div class="row">
          <span class="muted small">{{ post.category_name }} · {{ formatDate(post.created_at) }}</span>
          <span class="status" :class="STATUS[post.status].cls">{{ STATUS[post.status].label }}</span>
        </div>
        <h2>{{ post.title }}</h2>
        <p v-if="author" class="note">發布者：{{ author.full_name }}（{{ author.student_id }}）</p>
        <section><h4>問題描述</h4><p>{{ post.problem }}</p></section>
        <section><h4>可行建議</h4><p>{{ post.suggestion }}</p></section>
        <section><h4>預期解決效果</h4><p>{{ post.expected }}</p></section>
        <section v-if="post.help_offer"><h4>願意付出的努力</h4><p>{{ post.help_offer }}</p></section>
        <div><MeTooButton :post="post" /></div>
      </div>

      <div class="card stack">
        <h3>權益部回覆</h3>
        <p v-if="!replies.length" class="muted">尚無回覆</p>
        <div v-for="r in replies" :key="r.id" class="reply">
          <p>{{ r.body }}</p>
          <span class="muted small">{{ formatDate(r.created_at) }}</span>
        </div>
        <form v-if="isStaff()" class="stack" @submit.prevent="sendReply">
          <textarea v-model="replyText" placeholder="以權益部身份回覆" />
          <button class="btn">送出回覆</button>
        </form>
      </div>

      <div v-if="isStaff()" class="card stack">
        <h3>處理狀態</h3>
        <select :value="post.status" @change="changeStatus">
          <option v-for="(s, key) in STATUS" :key="key" :value="key">{{ s.label }}</option>
        </select>
      </div>

      <div v-if="post.is_mine" class="card stack">
        <h3>我的問題</h3>
        <p v-if="pendingRequest" class="note">
          {{ pendingRequest.kind === 'edit' ? '修改' : '刪除' }}申請審核中，權益部同意後才會生效。
        </p>
        <template v-else>
          <p class="muted small">修改或刪除需要權益部同意。</p>
          <div class="actions">
            <router-link :to="`/new?edit=${id}`" class="btn ghost">申請修改</router-link>
            <button v-if="!confirmDelete" class="btn danger" @click="confirmDelete = true">申請刪除</button>
            <button v-else class="btn danger" @click="requestDelete">確定申請刪除</button>
          </div>
        </template>
      </div>

      <p v-if="message" class="note">{{ message }}</p>
    </div>
  </div>
</template>

<style scoped>
.row { display: flex; justify-content: space-between; align-items: center; gap: 8px; }
h2 { font-size: 22px; }
h3 { font-size: 17px; }
h4 { font-size: 14px; color: var(--muted); margin: 0 0 2px; }
section p, .reply p { margin: 0; white-space: pre-wrap; }
.reply { border-left: 3px solid var(--orange); padding-left: 12px; }
.actions { display: flex; gap: 10px; }
</style>
