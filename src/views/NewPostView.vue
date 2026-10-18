<script setup>
import { t } from '../i18n'
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import Icon from '../components/Icon.vue'

const route = useRoute()
const router = useRouter()
// 帶 ?edit=問題id 時是「申請修改」，送出的是 change_requests 而不是直接改 posts
const editId = route.query.edit ? Number(route.query.edit) : null

const categories = ref([])
const form = ref({ category_id: '', title: '', problem: '', suggestion: '', expected: '', help_offer: '' })
const error = ref('')
const busy = ref(false)

onMounted(async () => {
  const { data } = await supabase.from('categories').select('*').order('sort_order')
  categories.value = data ?? []
  if (editId) {
    const { data: p } = await supabase.from('post_feed').select('*').eq('id', editId).single()
    if (p) {
      form.value = {
        category_id: p.category_id, title: p.title, problem: p.problem,
        suggestion: p.suggestion, expected: p.expected, help_offer: p.help_offer ?? '',
      }
    }
  }
})

async function submit() {
  error.value = ''
  busy.value = true
  const f = form.value
  const helpOffer = f.help_offer.trim() || null
  let result
  if (editId) {
    result = await supabase.from('change_requests').insert({
      post_id: editId, kind: 'edit',
      new_category_id: f.category_id, new_title: f.title.trim(), new_problem: f.problem.trim(),
      new_suggestion: f.suggestion.trim(), new_expected: f.expected.trim(), new_help_offer: helpOffer,
    })
  } else {
    result = await supabase.from('posts').insert({
      category_id: f.category_id, title: f.title.trim(), problem: f.problem.trim(),
      suggestion: f.suggestion.trim(), expected: f.expected.trim(), help_offer: helpOffer,
    }).select('id').single()
  }
  busy.value = false
  if (result.error) {
    error.value = result.error.code === '23505' ? '這個問題已經有一個等待審批的申請' : '送出失敗，請稍後再試'
    return
  }
  router.replace(editId ? `/posts/${editId}` : `/posts/${result.data.id}`)
}
</script>

<template>
  <header class="topbar">
    <button class="back" :aria-label="t('返回')" @click="router.back()"><Icon name="back" :size="24" /></button>
    <h1>{{ editId ? t('申請修改問題') : t('發布問題') }}</h1>
  </header>
  <form class="page stack" @submit.prevent="submit">
    <p v-if="editId" class="note">{{ t('修改需要權益部同意後才會生效。') }}</p>
    <p v-else class="note"><Icon name="eye" :size="18" />{{ t('其他同學看不到你的姓名和學號，只有權益部看得到。') }}</p>
    <label class="field">
      <span>{{ t('問題分類') }}</span>
      <select v-model="form.category_id" required>
        <option value="" disabled>{{ t('請選擇') }}</option>
        <option v-for="c in categories" :key="c.id" :value="c.id">{{ t(c.name) }}</option>
      </select>
    </label>
    <label class="field">
      <span>{{ t('標題') }}</span>
      <input v-model="form.title" maxlength="60" :placeholder="t('一句話說明問題')" required />
    </label>
    <label class="field">
      <span>{{ t('問題描述') }}</span>
      <textarea v-model="form.problem" :placeholder="t('請簡潔清晰地描述你遇到的問題')" required />
    </label>
    <label class="field">
      <span>{{ t('可行建議') }}</span>
      <textarea v-model="form.suggestion" :placeholder="t('針對你的問題，提出有可行性的建議')" required />
    </label>
    <label class="field">
      <span>{{ t('預期解決效果') }}</span>
      <textarea v-model="form.expected" :placeholder="t('你希望問題解決後是什麼樣子')" required />
    </label>
    <label class="field">
      <span>{{ t('願意付出的努力（選填）') }}</span>
      <textarea v-model="form.help_offer" :placeholder="t('如果解決這個問題需要你的幫助，你願意做些什麼')" />
    </label>
    <p v-if="error" class="error">{{ t(error) }}</p>
    <button class="btn block" :disabled="busy">{{ busy ? t('送出中…') : editId ? t('送出修改申請') : t('發布') }}</button>
  </form>
</template>
