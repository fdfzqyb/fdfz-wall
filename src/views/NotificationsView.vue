<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { formatDate } from '../constants'
import TabBar from '../components/TabBar.vue'

const router = useRouter()
const items = ref([])
const feedback = ref('')
const message = ref('')

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

onMounted(load)
</script>

<template>
  <header class="topbar">
    <h1>通知</h1>
    <button class="btn plain small" @click="markAllRead">全部已讀</button>
  </header>
  <div class="page stack">
    <p v-if="!items.length" class="muted center">目前沒有通知。</p>
    <button v-for="n in items" :key="n.id" class="card item" :class="{ unread: !n.is_read }" @click="open(n)">
      <span>{{ n.message }}</span>
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
.item { display: flex; justify-content: space-between; gap: 12px; width: 100%; text-align: left; font: inherit; cursor: pointer; }
.item.unread { border-left: 4px solid var(--orange); font-weight: 600; }
h3 { font-size: 17px; }
</style>
