<script setup>
import { t } from '../i18n'
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { isStaff } from '../auth'
import { STATUS, MODERATION_KIND, formatDate } from '../constants'
import MeTooButton from '../components/MeTooButton.vue'
import Icon from '../components/Icon.vue'

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
// 敏感內容處理（只有權益部用得到）
const moderation = ref(null)      // 這個帖子等待確認的申請
const modKind = ref('')
const modReason = ref('')

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
      .select('profiles!author_id(full_name, student_id)').eq('id', id).single()
    author.value = data?.profiles
    const { data: m } = await supabase.from('moderation_requests')
      .select('kind, reason, moderation_votes(staff_id)').eq('post_id', id).eq('status', 'pending').maybeSingle()
    moderation.value = m
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

async function requestModeration() {
  const { error } = await supabase.rpc('request_moderation', { pid: id, k: modKind.value, why: modReason.value })
  if (error) return (message.value = error.message)
  message.value = '已送出，需要另一位權益部在後台「敏感帖子」確認後才會生效'
  modKind.value = ''
  modReason.value = ''
  await load()
}

onMounted(load)
</script>

<template>
  <header class="topbar">
    <button class="back" :aria-label="t('返回')" @click="router.back()"><Icon name="back" :size="24" /></button>
    <h1>{{ t('問題詳情') }}</h1>
  </header>
  <div class="page">
    <p v-if="loading" class="muted center">{{ t('載入中…') }}</p>
    <p v-else-if="!post" class="muted center">{{ t('找不到這個問題，可能已被刪除。') }}</p>
    <div v-else class="stack">
      <div class="card stack">
        <div class="row">
          <span class="muted small">{{ t(post.category_name) }} · {{ formatDate(post.created_at) }}</span>
          <span class="status" :class="STATUS[post.status].cls">{{ t(STATUS[post.status].label) }}</span>
        </div>
        <h2>{{ post.moderation === 'redacted' && post.suggestion === null ? t(post.title) : post.title }}</h2>
        <p v-if="author" class="note"><Icon name="user" :size="18" />{{ t('發布者：') }}{{ author.full_name }}（{{ author.student_id }}）</p>
        <p v-if="post.moderation === 'redacted' && (post.is_mine || isStaff())" class="note warn">
          {{ t('涉及個人信息：其他同學看不到這個帖子的內容，只有發布者和權益部看得到。') }}
        </p>
        <section><h4>{{ t('問題描述') }}</h4><p>{{ post.moderation === 'redacted' && post.suggestion === null ? t(post.problem) : post.problem }}</p></section>
        <section v-if="post.suggestion"><h4>{{ t('可行建議') }}</h4><p>{{ post.suggestion }}</p></section>
        <section v-if="post.expected"><h4>{{ t('預期解決效果') }}</h4><p>{{ post.expected }}</p></section>
        <section v-if="post.help_offer"><h4>{{ t('願意付出的努力') }}</h4><p>{{ post.help_offer }}</p></section>
        <div><MeTooButton :post="post" /></div>
      </div>

      <div class="card stack">
        <h3>{{ t('權益部回覆') }}</h3>
        <p v-if="!replies.length" class="muted">{{ t('尚無回覆') }}</p>
        <div v-for="r in replies" :key="r.id" class="reply">
          <p>{{ r.body }}</p>
          <span class="muted small">{{ formatDate(r.created_at) }}</span>
        </div>
        <form v-if="isStaff()" class="stack" @submit.prevent="sendReply">
          <textarea v-model="replyText" :placeholder="t('以權益部身份回覆')" />
          <button class="btn">{{ t('送出回覆') }}</button>
        </form>
      </div>

      <div v-if="isStaff()" class="card stack">
        <h3>{{ t('處理狀態') }}</h3>
        <select :value="post.status" @change="changeStatus">
          <option v-for="(s, key) in STATUS" :key="key" :value="key">{{ t(s.label) }}</option>
        </select>
      </div>

      <div v-if="isStaff()" class="card stack">
        <h3>{{ t('敏感內容處理') }}</h3>
        <template v-if="moderation">
          <p class="note">
            {{ t('已申請「{kind}」，原因：{reason}。已確認 {count}/2，請另一位權益部到後台「敏感帖子」確認。', { kind: t(MODERATION_KIND[moderation.kind].label), reason: moderation.reason, count: moderation.moderation_votes.length }) }}
          </p>
        </template>
        <template v-else>
          <p class="muted small">{{ t('需要兩位權益部確認才會生效，你提出申請算第一位。') }}</p>
          <div class="chips">
            <button type="button" class="chip" :class="{ on: modKind === 'hide' }" @click="modKind = 'hide'">{{ t('隱藏') }}</button>
            <button v-if="post.moderation !== 'redacted'" type="button" class="chip" :class="{ on: modKind === 'redact' }" @click="modKind = 'redact'">{{ t('涉及個人信息') }}</button>
          </div>
          <template v-if="modKind">
            <p class="muted small">{{ t(MODERATION_KIND[modKind].hint) }}</p>
            <textarea v-model="modReason" :placeholder="t('原因（只有權益部看得到）')" />
            <button class="btn danger" @click="requestModeration">{{ t('申請{kind}', { kind: t(MODERATION_KIND[modKind].label) }) }}</button>
          </template>
        </template>
      </div>

      <div v-if="post.is_mine" class="card stack">
        <h3>{{ t('我的問題') }}</h3>
        <p v-if="pendingRequest" class="note">
          {{ t('{kind}申請審核中，權益部同意後才會生效。', { kind: t(pendingRequest.kind === 'edit' ? '修改' : '刪除') }) }}
        </p>
        <template v-else>
          <p class="muted small">{{ t('修改或刪除需要權益部同意。') }}</p>
          <div class="actions">
            <router-link :to="`/new?edit=${id}`" class="btn ghost">{{ t('申請修改') }}</router-link>
            <button v-if="!confirmDelete" class="btn danger" @click="confirmDelete = true">{{ t('申請刪除') }}</button>
            <button v-else class="btn danger" @click="requestDelete">{{ t('確定申請刪除') }}</button>
          </div>
        </template>
      </div>

      <p v-if="message" class="note">{{ t(message) }}</p>
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
.warn { background: #fde6d6; color: #a2531f; }
</style>
