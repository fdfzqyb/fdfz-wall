<script setup>
import { t } from '../i18n'
import { ref, onMounted } from 'vue'
import { loadCategories } from '../categories'
import { isAdmin } from '../auth'
import TabBar from '../components/TabBar.vue'
import AccountsTab from '../components/admin/AccountsTab.vue'
import RequestsTab from '../components/admin/RequestsTab.vue'
import ModerationTab from '../components/admin/ModerationTab.vue'
import FeedbackTab from '../components/admin/FeedbackTab.vue'
import ResetTab from '../components/admin/ResetTab.vue'
import ExportTab from '../components/admin/ExportTab.vue'
import UsersTab from '../components/admin/UsersTab.vue'

// 每個分頁自己載入和處理資料；這裡只管分頁列、提示訊息，以及分頁標籤上的數字。
// 所有分頁一開始就載入（用 v-show 切換），所以標籤上的數字一進來就是對的。
const tab = ref('accounts')
const message = ref('')
const counts = ref({ accounts: 0, requests: 0, moderation: 0 })
const accountsTab = ref(null)
const usersTab = ref(null)

onMounted(loadCategories)
</script>

<template>
  <header class="topbar"><h1>{{ t('權益部後台') }}</h1></header>
  <div class="page stack">
    <div class="chips">
      <button class="chip" :class="{ on: tab === 'accounts' }" @click="tab = 'accounts'">{{ t('帳號審核') }} {{ counts.accounts }}</button>
      <button class="chip" :class="{ on: tab === 'requests' }" @click="tab = 'requests'">{{ t('修改刪除申請') }} {{ counts.requests }}</button>
      <button class="chip" :class="{ on: tab === 'moderation' }" @click="tab = 'moderation'">{{ t('敏感帖子') }} {{ counts.moderation }}</button>
      <button class="chip" :class="{ on: tab === 'feedback' }" @click="tab = 'feedback'">{{ t('同學建議') }}</button>
      <button class="chip" :class="{ on: tab === 'reset' }" @click="tab = 'reset'">{{ t('重設密碼') }}</button>
      <button class="chip" :class="{ on: tab === 'export' }" @click="tab = 'export'">{{ t('導出帖子') }}</button>
      <button v-if="isAdmin()" class="chip" :class="{ on: tab === 'users' }" @click="tab = 'users'">{{ t('用戶管理') }}</button>
    </div>
    <p v-if="message" class="note">{{ t(message) }}</p>

    <AccountsTab v-show="tab === 'accounts'" ref="accountsTab"
      @message="message = $event" @count="counts.accounts = $event" @removed="usersTab?.drop($event)" />
    <RequestsTab v-show="tab === 'requests'" @message="message = $event" @count="counts.requests = $event" />
    <ModerationTab v-show="tab === 'moderation'" @message="message = $event" @count="counts.moderation = $event" />
    <FeedbackTab v-show="tab === 'feedback'" />
    <ResetTab v-show="tab === 'reset'" @message="message = $event" />
    <ExportTab v-show="tab === 'export'" @message="message = $event" />
    <UsersTab v-if="isAdmin()" v-show="tab === 'users'" ref="usersTab"
      @message="message = $event" @removed="accountsTab?.drop($event)" />
  </div>
  <TabBar />
</template>
