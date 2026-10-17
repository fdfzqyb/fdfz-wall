<script setup>
import { ref } from 'vue'
import { supabase } from '../supabase'
import Icon from './Icon.vue'

// post 需要有 id、me_too_count、me_too_by_me（來自 post_feed）
const props = defineProps({ post: { type: Object, required: true } })
const busy = ref(false)

async function toggle() {
  if (busy.value) return
  busy.value = true
  const p = props.post
  if (p.me_too_by_me) {
    const { error } = await supabase.from('me_too').delete().eq('post_id', p.id)
    if (!error) { p.me_too_by_me = false; p.me_too_count-- }
  } else {
    const { error } = await supabase.from('me_too').insert({ post_id: p.id })
    if (!error) { p.me_too_by_me = true; p.me_too_count++ }
  }
  busy.value = false
}
</script>

<template>
  <button type="button" class="metoo" :class="{ on: post.me_too_by_me }" @click.stop.prevent="toggle">
    <Icon name="metoo" :size="18" /> 我也遇到 {{ post.me_too_count }}
  </button>
</template>
