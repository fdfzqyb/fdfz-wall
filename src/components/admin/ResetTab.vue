<script setup>
import { t } from '../../i18n'
import { ref } from 'vue'
import { supabase } from '../../supabase'
import { ROLE_LABEL } from '../../constants'

const emit = defineEmits(['message'])

// 忘記密碼：先用學號查到人，核對身份後再產生臨時密碼
const resetSid = ref('')
const resetTarget = ref(null)
const tempPassword = ref('')

async function findForReset() {
  tempPassword.value = ''
  emit('message', '')
  const { data } = await supabase.from('profiles')
    .select('full_name, student_id, role').eq('student_id', resetSid.value.trim()).maybeSingle()
  resetTarget.value = data
  if (!data) emit('message', '找不到這個學號')
}

async function resetPassword() {
  if (!window.confirm(t('確定重設 {name} 的密碼？對方原本的密碼會失效。', { name: resetTarget.value.full_name }))) return
  const { data, error } = await supabase.rpc('reset_password', { sid: resetTarget.value.student_id })
  if (error) return emit('message', error.message)
  tempPassword.value = data
}
</script>

<template>
  <div class="stack">
    <p class="note">{{ t('同學忘記密碼時，請先當面核對校園卡，確認是本人再重設。') }}</p>
    <form class="search-row" @submit.prevent="findForReset">
      <input v-model="resetSid" inputmode="numeric" :placeholder="t('輸入八位學號')" required />
      <button class="btn small">{{ t('查詢') }}</button>
    </form>
    <div v-if="resetTarget" class="card stack">
      <div><strong>{{ resetTarget.full_name }}</strong> · {{ resetTarget.student_id }} · {{ t(ROLE_LABEL[resetTarget.role]) }}</div>
      <template v-if="tempPassword">
        <p>{{ t('臨時密碼：') }}</p>
        <p class="temp">{{ tempPassword }}</p>
        <p class="muted small">{{ t('請把這組密碼告訴同學。他用學號和臨時密碼登入後，網站會要求他改成自己的密碼。離開這一頁後就看不到這組密碼了。') }}</p>
      </template>
      <button v-else class="btn" @click="resetPassword">{{ t('產生臨時密碼') }}</button>
    </div>
  </div>
</template>

<style scoped>
.search-row { display: flex; gap: 10px; }
.search-row .btn { flex: none; }
.temp { font-size: 28px; font-weight: 700; letter-spacing: 3px; color: var(--navy); font-family: ui-monospace, monospace; margin: 0; }
</style>
