<script setup>
import { t } from '../i18n'
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../supabase'
import PostCard from '../components/PostCard.vue'
import TabBar from '../components/TabBar.vue'
import Icon from '../components/Icon.vue'
import { CATEGORY_ICON } from '../constants'
import { categories, loadCategories } from '../categories'

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
  await loadCategories()
})

let timer
watch(search, () => { clearTimeout(timer); timer = setTimeout(load, 300) })
watch([category, sort], load, { immediate: true })
</script>

<template>
  <header class="home-head">
    <div class="brand">
      <img src="/logo.jpg" alt="" class="logo-sm" />
      <h1>{{ t('fdfz權益牆') }}</h1>
    </div>
    <label class="search">
      <Icon name="search" :size="20" />
      <input v-model="search" type="search" :placeholder="t('搜尋問題')" />
    </label>
    <div class="chips">
      <button class="chip" :class="{ on: !category }" @click="category = null">{{ t('全部') }}</button>
      <button v-for="c in categories" :key="c.id" class="chip" :class="{ on: category === c.id }" @click="category = c.id">
        <Icon v-if="CATEGORY_ICON[c.name]" :name="CATEGORY_ICON[c.name]" :size="16" />{{ t(c.name) }}
      </button>
    </div>
  </header>
  <div class="page">
    <div class="toolbar">
      <span class="muted">{{ t('共 {count} 個問題', { count: posts.length }) }}</span>
      <div class="sort">
        <button :class="{ on: sort === 'new' }" @click="sort = 'new'">{{ t('最新') }}</button>
        <button :class="{ on: sort === 'hot' }" @click="sort = 'hot'">{{ t('最多人遇到') }}</button>
      </div>
    </div>
    <p v-if="loading" class="muted center">{{ t('載入中…') }}</p>
    <p v-else-if="!posts.length" class="muted center">{{ t('還沒有問題，來發布第一個吧。') }}</p>
    <div class="stack">
      <PostCard v-for="p in posts" :key="p.id" :post="p" />
    </div>
  </div>
  <router-link to="/new" class="btn fab"><Icon name="megaphone" :size="22" />{{ t('發布問題') }}</router-link>
  <TabBar />
</template>

<style scoped>
.home-head {
  background: var(--cream-logo);
  border-radius: 0 0 24px 24px;
  padding: 12px 20px 14px;
}
.brand { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
.brand h1 { font-size: 22px; }
.search {
  display: flex; align-items: center; gap: 8px;
  height: 44px; border-radius: 22px; background: var(--white); padding: 0 16px; margin-bottom: 12px;
  color: var(--muted);
}
.search input { border: 0; padding: 0; background: none; height: 100%; }
.search input:focus { outline: none; }
.search:focus-within { outline: 2px solid var(--navy); }
.chip { display: inline-flex; align-items: center; gap: 6px; }
.toolbar { display: flex; justify-content: space-between; align-items: center; margin: 12px 0; }
.sort button { font: inherit; border: 0; background: none; color: var(--muted); padding: 4px 10px; border-radius: 8px; cursor: pointer; }
.sort button.on { background: var(--cream-deep); color: var(--ink); font-weight: 700; }
</style>
