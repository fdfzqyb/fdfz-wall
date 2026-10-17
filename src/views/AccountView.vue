<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { auth, signOut, loadProfile } from '../auth'
import TabBar from '../components/TabBar.vue'

const router = useRouter()
const ROLE_LABEL = { student: '普通同學', staff: '權益部', admin: '管理員' }

const profile = computed(() => auth.profile ?? {})
const email = computed(() => auth.session?.user?.email ?? '')

const current = ref('')
const next = ref('')
const again = ref('')
const error = ref('')
const message = ref('')
const saving = ref(false)

async function changePassword() {
  error.value = ''
  message.value = ''
  if (next.value.length < 6) return (error.value = '新密碼至少 6 個字元')
  if (next.value !== again.value) return (error.value = '兩次輸入的新密碼不一樣')
  saving.value = true
  // 先用舊密碼登入一次，確認是本人在操作
  const { error: wrong } = await supabase.auth.signInWithPassword({ email: email.value, password: current.value })
  if (wrong) {
    saving.value = false
    return (error.value = '目前密碼不正確')
  }
  const { error: failed } = await supabase.auth.updateUser({ password: next.value })
  saving.value = false
  if (failed) return (error.value = failed.message.includes('different') ? '新密碼不能和舊密碼一樣' : '修改失敗，請稍後再試')
  if (auth.profile?.must_change_password) {
    await supabase.rpc('password_changed')
    await loadProfile()
  }
  current.value = next.value = again.value = ''
  message.value = '密碼已修改，下次請用新密碼登入'
}

async function logout() {
  await signOut()
  router.push('/login')
}
</script>

<template>
  <header class="topbar"><h1>帳號</h1></header>
  <div class="page stack">
    <div class="card info">
      <div><span class="muted">姓名</span><b>{{ profile.full_name }}</b></div>
      <div><span class="muted">學號</span><b>{{ profile.student_id }}</b></div>
      <div><span class="muted">Email</span><b>{{ email }}</b></div>
      <div><span class="muted">身份</span><b>{{ ROLE_LABEL[profile.role] }}</b></div>
    </div>

    <p v-if="profile.must_change_password" class="note">你正在使用權益部給的臨時密碼，請先改成自己的密碼，才能使用其他功能。</p>

    <form class="card stack" @submit.prevent="changePassword">
      <h2>修改密碼</h2>
      <label class="field">
        <span>{{ profile.must_change_password ? '臨時密碼' : '目前密碼' }}</span>
        <input v-model="current" type="password" autocomplete="current-password" required />
      </label>
      <label class="field">
        <span>新密碼</span>
        <input v-model="next" type="password" autocomplete="new-password" required />
        <small>至少 6 個字元</small>
      </label>
      <label class="field">
        <span>再輸入一次新密碼</span>
        <input v-model="again" type="password" autocomplete="new-password" required />
      </label>
      <p v-if="error" class="error">{{ error }}</p>
      <p v-if="message" class="note">{{ message }}</p>
      <button class="btn block" :disabled="saving">{{ saving ? '修改中…' : '確認修改' }}</button>
    </form>

    <button class="btn plain block" @click="logout">登出</button>
  </div>
  <TabBar />
</template>

<style scoped>
h2 { font-size: 18px; }
.info { display: grid; gap: 12px; }
.info div { display: flex; justify-content: space-between; gap: 12px; }
.info b { font-weight: 600; text-align: right; word-break: break-all; }
</style>
