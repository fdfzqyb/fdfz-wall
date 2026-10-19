<script setup>
import { t, message as uiMessage } from '../../i18n'
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../../supabase'
import { cardPath } from '../../constants'
import { deleteUnapprovedAccount } from '../../admin'

const emit = defineEmits(['message', 'count', 'removed'])
const accounts = ref([])

// 待審核帳號，加上已拒絕但重新上傳了照片的帳號
async function loadAccounts() {
  const { data } = await supabase.from('profiles')
    .select('id, full_name, student_id, verify_status, created_at')
    .in('verify_status', ['pending', 'rejected'])
    .order('created_at')
  const rows = data ?? []
  // 一次請求取回所有照片網址；沒有照片的帳號 signedUrl 是空的
  const { data: signed } = rows.length
    ? await supabase.storage.from('id-cards').createSignedUrls(rows.map((p) => cardPath(p.id)), 600)
    : { data: [] }
  const urlByPath = new Map((signed ?? []).filter((s) => s.signedUrl).map((s) => [s.path, s.signedUrl]))
  accounts.value = rows
    .map((p) => ({ ...p, photo: urlByPath.get(cardPath(p.id)) ?? null }))
    .filter((p) => p.verify_status !== 'rejected' || p.photo)
}

async function review(p, approve) {
  const { error } = await supabase.rpc('review_account', { target: p.id, approve })
  if (error) return emit('message', error.message)
  // 不論通過或拒絕，審核完就刪除學生證照片
  await supabase.storage.from('id-cards').remove([cardPath(p.id)])
  drop(p.id)
  emit('message', uiMessage(approve ? '已通過 {name}，照片已刪除' : '已拒絕 {name}，照片已刪除', { name: p.full_name }))
}

async function removeAccount(p) {
  const error = await deleteUnapprovedAccount(p)
  if (error === null) return
  if (error) return emit('message', error)
  drop(p.id)
  emit('removed', p.id)
  emit('message', uiMessage('已刪除 {name} 的註冊，對方可以重新註冊', { name: p.full_name }))
}

// 別的分頁刪掉了某個帳號時，這裡也要拿掉
function drop(id) {
  accounts.value = accounts.value.filter((a) => a.id !== id)
}
defineExpose({ drop })

watch(accounts, (list) => emit('count', list.length), { immediate: true })
onMounted(loadAccounts)
</script>

<template>
  <div class="stack">
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
  </div>
</template>

<style scoped>
.card-photo { width: 100%; border-radius: 10px; }
.actions { display: flex; gap: 10px; }
</style>
