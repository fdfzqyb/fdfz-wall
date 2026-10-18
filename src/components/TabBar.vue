<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabase'
import { auth, isStaff } from '../auth'
import Icon from './Icon.vue'

const route = useRoute()
const unread = ref(0)

async function loadUnread() {
  const { count } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', auth.session.user.id)
    .eq('is_read', false)
  unread.value = count ?? 0
}

// 每次換頁都重新算一次未讀數
watch(() => route.fullPath, loadUnread, { immediate: true })
</script>

<template>
  <nav class="tabbar">
    <router-link to="/"><span class="icon"><Icon name="home" :size="24" /></span>首頁</router-link>
    <router-link to="/mine"><span class="icon"><Icon name="posts" :size="24" /></span>我的帖子</router-link>
    <router-link to="/notifications">
      <span class="icon"><Icon name="bell" :size="24" /><span v-if="unread" class="badge">{{ unread }}</span></span>通知
    </router-link>
    <router-link v-if="isStaff()" to="/admin"><span class="icon"><Icon name="review" :size="24" /></span>權益部</router-link>
    <router-link to="/account"><span class="icon"><Icon name="user" :size="24" /></span>帳號</router-link>
  </nav>
</template>
