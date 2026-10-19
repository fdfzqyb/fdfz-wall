<script setup>
import { t } from '../../i18n'
import { ref, onMounted } from 'vue'
import { supabase } from '../../supabase'
import { formatDate } from '../../constants'

const feedbacks = ref([])

onMounted(async () => {
  const { data } = await supabase.from('feedback')
    .select('id, body, created_at, profiles(full_name, student_id)')
    .order('created_at', { ascending: false }).limit(100)
  feedbacks.value = data ?? []
})
</script>

<template>
  <div class="stack">
    <p v-if="!feedbacks.length" class="muted center">{{ t('還沒有建議。') }}</p>
    <div v-for="f in feedbacks" :key="f.id" class="card">
      <p class="body">{{ f.body }}</p>
      <span class="muted small">{{ f.profiles?.full_name }}（{{ f.profiles?.student_id }}） · {{ formatDate(f.created_at) }}</span>
    </div>
  </div>
</template>

<style scoped>
.body { margin: 0 0 6px; white-space: pre-wrap; }
</style>
