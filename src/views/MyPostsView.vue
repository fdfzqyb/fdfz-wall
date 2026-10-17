<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import PostCard from '../components/PostCard.vue'
import TabBar from '../components/TabBar.vue'

const posts = ref([])
const loading = ref(true)

onMounted(async () => {
  const { data } = await supabase
    .from('post_feed').select('*').eq('is_mine', true).order('created_at', { ascending: false })
  posts.value = data ?? []
  loading.value = false
})
</script>

<template>
  <header class="topbar"><h1>我的帖子</h1></header>
  <div class="page">
    <p v-if="loading" class="muted center">載入中…</p>
    <p v-else-if="!posts.length" class="muted center">你還沒有發布過問題。</p>
    <div class="stack"><PostCard v-for="p in posts" :key="p.id" :post="p" /></div>
  </div>
  <TabBar />
</template>
