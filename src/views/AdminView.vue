<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { formatDate } from '../constants'
import TabBar from '../components/TabBar.vue'

const tab = ref('accounts')
const accounts = ref([])
const requests = ref([])
const feedbacks = ref([])
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
  const { error } = await supabase.from('profiles')
    .update({ verify_status: approve ? 'approved' : 'rejected' }).eq('id', p.id)
  if (error) return (message.value = '更新失敗')
  // 不論通過或拒絕，審核完就刪除學生證照片
  await supabase.storage.from('id-cards').remove([`${p.id}/card.jpg`])
  accounts.value = accounts.value.filter((a) => a.id !== p.id)
  message.value = `已${approve ? '通過' : '拒絕'} ${p.full_name}，照片已刪除`
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

async function loadFeedback() {
  const { data } = await supabase.from('feedback')
    .select('id, body, created_at, profiles(full_name, student_id)')
    .order('created_at', { ascending: false }).limit(100)
  feedbacks.value = data ?? []
}

onMounted(() => Promise.all([loadAccounts(), loadRequests(), loadFeedback()]))
</script>

<template>
  <header class="topbar"><h1>權益部後台</h1></header>
  <div class="page stack">
    <div class="chips">
      <button class="chip" :class="{ on: tab === 'accounts' }" @click="tab = 'accounts'">帳號審核 {{ accounts.length }}</button>
      <button class="chip" :class="{ on: tab === 'requests' }" @click="tab = 'requests'">修改刪除申請 {{ requests.length }}</button>
      <button class="chip" :class="{ on: tab === 'feedback' }" @click="tab = 'feedback'">同學建議</button>
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

    <template v-if="tab === 'feedback'">
      <p v-if="!feedbacks.length" class="muted center">還沒有建議。</p>
      <div v-for="f in feedbacks" :key="f.id" class="card">
        <p class="body">{{ f.body }}</p>
        <span class="muted small">{{ f.profiles?.full_name }}（{{ f.profiles?.student_id }}） · {{ formatDate(f.created_at) }}</span>
      </div>
    </template>
  </div>
  <TabBar />
</template>

<style scoped>
.card-photo { width: 100%; border-radius: 10px; }
.actions { display: flex; gap: 10px; }
.diff { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 14px; }
.diff p, .body { margin: 0 0 6px; white-space: pre-wrap; }
h4 { font-size: 13px; color: var(--muted); margin: 0 0 4px; }
</style>
