<script setup>
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../supabase'
import PostCard from '../components/PostCard.vue'
import TabBar from '../components/TabBar.vue'

const categories = ref([])
const posts = ref([])
const category = ref(null) // null = 全部
const sort = ref('new')    // new = 最新，hot = 最多人遇到
const search = ref('')
const loading = ref(true)

async function load() {
  loading.value = true
  let q = supabase.from('post_feed').select('*')
  if (category.value) q = q.eq('category_id', category.value)
  // 去掉會破壞查詢語法的符號
  const s = search.value.trim().replace(/[,()%*\\]/g, '')
  if (s) q = q.or(`title.ilike.%${s}%,problem.ilike.%${s}%`)
  q = sort.value === 'hot'
    ? q.order('me_too_count', { ascending: false }).order('created_at', { ascending: false })
    : q.order('created_at', { ascending: false })
  const { data } = await q.limit(100)
  posts.value = data ?? []
  loading.value = false
}

onMounted(async () => {
  const { data } = await supabase.from('categories').select('*').order('sort_order')
  categories.value = data ?? []
})

let timer
watch(search, () => { clearTimeout(timer); timer = setTimeout(load, 300) })
watch([category, sort], load, { immediate: true })
</script>

<template>
  <header class="topbar">
    <img src="/logo.jpg" alt="" class="logo-sm" />
    <h1>fdfz權益牆</h1>
  </header>
  <div class="page">
    <input v-model="search" type="search" placeholder="🔍 搜尋問題" class="search" />
    <div class="chips">
      <button class="chip" :class="{ on: !category }" @click="category = null">全部</button>
      <button v-for="c in categories" :key="c.id" class="chip" :class="{ on: category === c.id }" @click="category = c.id">
        {{ c.name }}
      </button>
    </div>
    <div class="toolbar">
      <span class="muted">共 {{ posts.length }} 個問題</span>
      <div class="sort">
        <button :class="{ on: sort === 'new' }" @click="sort = 'new'">最新</button>
        <button :class="{ on: sort === 'hot' }" @click="sort = 'hot'">最多人遇到</button>
      </div>
    </div>
    <p v-if="loading" class="muted center">載入中…</p>
    <p v-else-if="!posts.length" class="muted center">還沒有問題，來發布第一個吧。</p>
    <div class="stack">
      <PostCard v-for="p in posts" :key="p.id" :post="p" />
    </div>
  </div>
  <router-link to="/new" class="btn fab">＋ 發布問題</router-link>
  <TabBar />
</template>

<style scoped>
.search { background: var(--cream-deep); border-color: transparent; margin-bottom: 12px; }
.toolbar { display: flex; justify-content: space-between; align-items: center; margin: 12px 0; }
.sort button { font: inherit; border: 0; background: none; color: var(--muted); padding: 4px 10px; border-radius: 8px; cursor: pointer; }
.sort button.on { background: var(--cream-deep); color: var(--ink); font-weight: 700; }
</style>
