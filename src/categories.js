import { ref } from 'vue'
import { supabase } from './supabase'

// 分類清單幾乎不會變，整個網站只查一次，各頁面共用
export const categories = ref([])
let loading = null

export function loadCategories() {
  if (!loading) {
    loading = supabase.from('categories').select('id, name').order('sort_order').then(({ data, error }) => {
      if (error) loading = null // 失敗了下次再試
      else categories.value = data ?? []
    })
  }
  return loading
}
