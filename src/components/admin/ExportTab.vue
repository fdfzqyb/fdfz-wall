<script setup>
import { t, message as uiMessage } from '../../i18n'
import { ref } from 'vue'
import { supabase } from '../../supabase'
import { STATUS, CATEGORY_ICON } from '../../constants'
import { categories } from '../../categories'
import Icon from '../Icon.vue'

const emit = defineEmits(['message'])

// 導出帖子為 CSV，給權益部整理用（含發布者姓名學號，請勿外傳）
const EXPORT_RANGES = { month: '最近一個月', half: '最近六個月', all: '所有時間' }
const exportRange = ref('month')
const exportCategory = ref('all')
const exporting = ref(false)

function exportSince() {
  if (exportRange.value === 'all') return null
  const d = new Date()
  d.setMonth(d.getMonth() - (exportRange.value === 'month' ? 1 : 6))
  return d.toISOString()
}

const pad = (n) => String(n).padStart(2, '0')
function fullDate(iso, withTime = true) {
  const d = new Date(iso)
  const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  return withTime ? `${day} ${pad(d.getHours())}:${pad(d.getMinutes())}` : day
}

// 每格都加引號；開頭是 = + - @ 的加一個 ' ，避免 Excel 把同學填的內容當成公式執行
function csvCell(v) {
  let s = v == null ? '' : String(v)
  if (/^[=+\-@]/.test(s)) s = `'${s}`
  return `"${s.replace(/"/g, '""')}"`
}

async function exportPosts() {
  exporting.value = true
  emit('message', '')
  const since = exportSince()
  const rows = []
  // Supabase 一次最多回傳 1000 筆，分批拿完
  for (let from = 0; ; from += 1000) {
    let q = supabase.from('posts')
      .select('id, title, problem, suggestion, expected, help_offer, status, moderation, created_at, updated_at, categories(name), profiles!author_id(full_name, student_id), replies(body, created_at)')
      .order('created_at').range(from, from + 999)
    if (since) q = q.gte('created_at', since)
    if (exportCategory.value !== 'all') q = q.eq('category_id', exportCategory.value)
    const { data, error } = await q
    if (error) {
      exporting.value = false
      return emit('message', error.message)
    }
    rows.push(...data)
    if (data.length < 1000) break
  }
  exporting.value = false
  if (!rows.length) return emit('message', '這個範圍內沒有帖子')

  const MOD_LABEL = { hidden: '已隱藏', redacted: '涉及個人信息' }
  const header = ['編號', '發帖日期', '分類', '標題', '問題描述', '可行建議', '預期解決效果', '願意付出的努力',
    '處理狀態', '敏感處理', '權益部回覆', '發布者姓名', '學號', '最後更新'].map((h) => t(h))
  const lines = rows.map((p) => [
    p.id,
    fullDate(p.created_at),
    t(p.categories?.name ?? ''),
    p.title,
    p.problem,
    p.suggestion,
    p.expected,
    p.help_offer,
    t(STATUS[p.status]?.label ?? p.status),
    p.moderation ? t(MOD_LABEL[p.moderation]) : '',
    [...p.replies].sort((a, b) => a.created_at.localeCompare(b.created_at))
      .map((r) => `${fullDate(r.created_at)}　${r.body}`).join('\n'),
    p.profiles?.full_name,
    p.profiles?.student_id,
    fullDate(p.updated_at),
  ].map(csvCell).join(','))

  // 開頭加 BOM，Excel 打開才不會變亂碼
  const csv = '﻿' + [header.map(csvCell).join(','), ...lines].join('\r\n')
  const catName = exportCategory.value === 'all'
    ? t('全部分類') : t(categories.value.find((c) => c.id === exportCategory.value)?.name ?? '')
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  a.download = `${t('權益牆帖子')}_${catName}_${t(EXPORT_RANGES[exportRange.value])}_${fullDate(new Date(), false)}.csv`
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 1000)
  emit('message', uiMessage('已導出 {count} 個帖子', { count: rows.length }))
}
</script>

<template>
  <div class="stack">
    <p class="note">{{ t('導出的表格包含發布者的姓名和學號，只供權益部內部整理，請不要外傳。') }}</p>
    <div class="card stack">
      <div>
        <h4>{{ t('時間') }}</h4>
        <div class="chips">
          <button v-for="(label, key) in EXPORT_RANGES" :key="key" class="chip" :class="{ on: exportRange === key }" @click="exportRange = key">{{ t(label) }}</button>
        </div>
      </div>
      <div>
        <h4>{{ t('分類') }}</h4>
        <div class="chips">
          <button class="chip" :class="{ on: exportCategory === 'all' }" @click="exportCategory = 'all'">{{ t('全部分類') }}</button>
          <button v-for="c in categories" :key="c.id" class="chip" :class="{ on: exportCategory === c.id }" @click="exportCategory = c.id">
            <Icon v-if="CATEGORY_ICON[c.name]" :name="CATEGORY_ICON[c.name]" :size="16" />{{ t(c.name) }}
          </button>
        </div>
      </div>
      <p class="muted small">{{ t('按發帖日期篩選。表格包含日期、分類、同學填寫的所有內容、處理狀態、權益部回覆，以及發布者姓名學號，可以用 Excel 或 WPS 打開。') }}</p>
      <button class="btn block" :disabled="exporting" @click="exportPosts">{{ exporting ? t('導出中…') : t('導出 CSV') }}</button>
    </div>
  </div>
</template>

<style scoped>
h4 { font-size: 13px; color: var(--muted); margin: 0 0 4px; }
</style>
