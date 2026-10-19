<script setup>
import { t } from '../../i18n'
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../../supabase'
import { formatDate, MODERATION_KIND } from '../../constants'
import { auth } from '../../auth'

const emit = defineEmits(['message', 'count'])
const moderations = ref([])

async function loadModerations() {
  const { data } = await supabase.from('moderation_requests')
    .select('*, posts(title, problem), profiles!created_by(full_name), moderation_votes(staff_id)')
    .eq('status', 'pending').order('created_at')
  moderations.value = data ?? []
}

const votedByMe = (m) => m.moderation_votes.some((v) => v.staff_id === auth.session.user.id)

async function voteModeration(m, approve) {
  const { data, error } = await supabase.rpc('vote_moderation', { req_id: m.id, approve })
  if (error) return emit('message', error.message)
  emit('message', data === 'applied' ? '已確認，處理已生效，發布者會收到通知' : data === 'rejected' ? '已駁回申請' : '已確認，還需要另一位權益部確認')
  await loadModerations()
}

watch(moderations, (list) => emit('count', list.length), { immediate: true })
onMounted(loadModerations)
</script>

<template>
  <div class="stack">
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
  </div>
</template>

<style scoped>
.actions { display: flex; gap: 10px; }
.body { margin: 0 0 6px; white-space: pre-wrap; }
</style>
