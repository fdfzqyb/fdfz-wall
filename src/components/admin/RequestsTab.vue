<script setup>
import { t } from '../../i18n'
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../../supabase'

const emit = defineEmits(['message', 'count'])
const requests = ref([])

async function loadRequests() {
  const { data } = await supabase.from('change_requests')
    .select('*, posts(title, problem, suggestion, expected, help_offer)')
    .eq('status', 'pending').order('created_at')
  requests.value = data ?? []
}

async function decide(r, approve) {
  const { error } = await supabase.rpc('review_change_request', { req_id: r.id, approve })
  if (error) return emit('message', error.message)
  requests.value = requests.value.filter((x) => x.id !== r.id)
  emit('message', approve ? '已同意申請' : '已拒絕申請')
}

watch(requests, (list) => emit('count', list.length), { immediate: true })
onMounted(loadRequests)
</script>

<template>
  <div class="stack">
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
  </div>
</template>

<style scoped>
.actions { display: flex; gap: 10px; }
.diff { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 14px; }
.diff p { margin: 0 0 6px; white-space: pre-wrap; }
h4 { font-size: 13px; color: var(--muted); margin: 0 0 4px; }
</style>
