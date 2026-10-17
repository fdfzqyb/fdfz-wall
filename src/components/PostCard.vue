<script setup>
import { STATUS, formatDate } from '../constants'
import MeTooButton from './MeTooButton.vue'

defineProps({ post: { type: Object, required: true } })
</script>

<template>
  <router-link :to="`/posts/${post.id}`" class="card post-card">
    <div class="row">
      <span class="muted small">{{ post.category_name }} · {{ formatDate(post.created_at) }}</span>
      <span class="status" :class="STATUS[post.status].cls">{{ STATUS[post.status].label }}</span>
    </div>
    <h3>{{ post.title }}</h3>
    <p class="excerpt">{{ post.problem }}</p>
    <div class="row">
      <span class="muted small">{{ post.has_reply ? '權益部已回覆' : '尚無回覆' }}</span>
      <MeTooButton :post="post" @click.prevent />
    </div>
  </router-link>
</template>

<style scoped>
.post-card { display: block; color: inherit; }
.row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
h3 { font-size: 18px; margin: 10px 0 4px; }
.excerpt {
  margin: 0 0 12px; color: var(--muted);
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
</style>
