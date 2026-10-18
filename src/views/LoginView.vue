<script setup>
import { t } from '../i18n'
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { signIn, loadProfile, isApproved } from '../auth'

const router = useRouter()
const account = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

async function submit() {
  error.value = ''
  busy.value = true
  const msg = await signIn(account.value, password.value)
  if (msg) {
    error.value = msg
    busy.value = false
    return
  }
  await loadProfile()
  busy.value = false
  router.replace(isApproved() ? '/' : '/pending')
}
</script>

<template>
  <div class="page login">
    <img src="/logo.jpg" :alt="t('權益部 logo')" class="logo" />
    <h1 class="center">{{ t('fdfz權益牆') }}</h1>
    <p class="center muted">{{ t('把校園生活裡遇到的問題告訴權益部。') }}<br />{{ t('僅限本校已驗證的同學登入。') }}</p>

    <form class="stack" @submit.prevent="submit">
      <label class="field">
        <span>{{ t('學號或 Email') }}</span>
        <input v-model="account" autocomplete="username" required />
      </label>
      <label class="field">
        <span>{{ t('密碼') }}</span>
        <input v-model="password" type="password" autocomplete="current-password" required />
      </label>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <button class="btn block" :disabled="busy">{{ busy ? t('登入中…') : t('登入') }}</button>
    </form>
    <p class="center muted small">{{ t('忘記密碼？請帶校園卡找權益部重設。') }}</p>

    <p class="center muted" style="margin-top: 40px">{{ t('還沒有帳號？') }}</p>
    <router-link to="/register" class="btn ghost block">{{ t('註冊新帳號') }}</router-link>
    <p class="center muted small">{{ t('註冊需經權益部審核，通過後才能瀏覽和發帖。') }}</p>
  </div>
</template>

<style scoped>
/* 背景用 logo 的底色，讓方形 logo 融進頁面；陰影向兩側鋪滿整個視窗寬度 */
.login {
  padding-top: 40px; min-height: 100vh;
  background: var(--cream-logo);
  box-shadow: 0 0 0 100vmax var(--cream-logo);
  clip-path: inset(0 -100vmax);
}
.logo { display: block; width: 168px; height: 168px; margin: 0 auto 20px; border-radius: 24px; object-fit: cover; }
h1 { font-size: 30px; }
</style>
