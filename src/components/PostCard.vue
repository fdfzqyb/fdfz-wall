<script setup>
import { t } from '../i18n'
import { STATUS, formatDate } from '../constants'
import MeTooButton from './MeTooButton.vue'

defineProps({ post: { type: Object, required: true } })
</script>

<template>
  <router-link :to="`/posts/${post.id}`" class="card post-card">
    <div class="row">
      <span class="muted small">{{ t(post.category_name) }} · {{ formatDate(post.created_at) }}</span>
      <span class="status" :class="STATUS[post.status].cls">{{ t(STATUS[post.status].label) }}</span>
    </div>
    <!-- 涉及個人信息的帖子：其他同學拿到的是提示文字（沒有可行建議），發布者和權益部看到原文加標註 -->
    <h3 :class="{ masked: post.moderation === 'redacted' && post.suggestion === null }">
      <span v-if="post.moderation === 'redacted' && post.suggestion !== null" class="tag">{{ t('涉敏') }}</span>{{ post.moderation === 'redacted' && post.suggestion === null ? t(post.title) : post.title }}
    </h3>
    <p class="excerpt">{{ post.moderation === 'redacted' && post.suggestion === null ? t(post.problem) : post.problem }}</p>
    <div class="row">
      <span class="muted small">{{ post.has_reply ? t('權益部已回覆') : t('尚無回覆') }}</span>
      <MeTooButton :post="post" @click.prevent />
    </div>
  </router-link>
</template>

<style scoped>
.post-card { display: block; color: inherit; }
.row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
h3 { font-size: 18px; margin: 10px 0 4px; }
.tag { background: #fde6d6; color: #a2531f; border-radius: 999px; padding: 1px 8px; font-size: 12px; font-weight: 700; margin-right: 6px; vertical-align: 2px; }
.masked { color: var(--muted); font-size: 16px; }
.excerpt {
  margin: 0 0 12px; color: var(--muted);
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
</style>
