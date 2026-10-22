<script setup>
import { locale, setLocale, t } from '../i18n'
import { computed } from 'vue'
import { auth, signOut } from '../auth'
import { ROLE_LABEL } from '../constants'
import { accountUrl } from '../fdfz'
import TabBar from '../components/TabBar.vue'

const profile = computed(() => auth.profile ?? {})
const email = computed(() => auth.session?.user?.email ?? '')
// 改密碼等帳號設定在帳號中心，改完可以按「回到權益牆」回來
const settingsUrl = accountUrl('/')

async function logout() {
  await signOut()
  window.location.assign(accountUrl('/login', location.origin + '/'))
}
</script>

<template>
  <header class="topbar"><h1>{{ t('帳號') }}</h1></header>
  <div class="page stack">
    <div class="card info">
      <div><span class="muted">{{ t('姓名') }}</span><b>{{ profile.full_name }}</b></div>
      <div><span class="muted">{{ t('學號') }}</span><b>{{ profile.student_id }}</b></div>
      <div><span class="muted">Email</span><b>{{ email }}</b></div>
      <div><span class="muted">{{ t('身份') }}</span><b>{{ t(ROLE_LABEL[profile.role]) }}</b></div>
    </div>

    <section class="card stack" aria-labelledby="language-heading">
      <h2 id="language-heading">{{ t('語言') }}</h2>
      <div class="language-options" role="group" aria-labelledby="language-heading">
        <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hans' }" :aria-pressed="locale === 'zh-Hans'" lang="zh-Hans" @click="setLocale('zh-Hans')">简体中文</button>
        <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hant' }" :aria-pressed="locale === 'zh-Hant'" lang="zh-Hant" @click="setLocale('zh-Hant')">繁體中文</button>
      </div>
      <p class="muted small">{{ t('所有 fdfz.click 網站共用這個設定。') }}</p>
    </section>

    <a :href="settingsUrl" class="btn ghost block">{{ t('帳號設定（改密碼）') }}</a>
    <p class="center muted small">{{ t('所有 fdfz.click 網站共用同一個帳號。') }}</p>

    <button class="btn plain block" @click="logout">{{ t('登出') }}</button>
  </div>
  <TabBar />
</template>

<style scoped>
h2 { font-size: 18px; }
.info { display: grid; gap: 12px; }
.info div { display: flex; justify-content: space-between; gap: 12px; }
.info b { font-weight: 600; text-align: right; word-break: break-all; }
.language-options { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
.language-options .btn { padding: 12px 8px; }
.language-options .btn:focus-visible { outline: 2px solid var(--navy); outline-offset: 3px; }
</style>
