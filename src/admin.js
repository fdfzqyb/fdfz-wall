import { supabase } from './supabase'
import { t } from './i18n'
import { cardPath } from './constants'

// 刪除未通過審核的帳號，讓同學可以用同一個學號和 email 重新註冊。
// 對方不同意（按取消）回傳 null；成功回傳 ''；失敗回傳錯誤訊息。
export async function deleteUnapprovedAccount(p) {
  if (!window.confirm(t('確定刪除 {name}（{sid}）的註冊？對方需要重新註冊。', { name: p.full_name, sid: p.student_id }))) return null
  await supabase.storage.from('id-cards').remove([cardPath(p.id)])
  const { error } = await supabase.rpc('delete_unapproved_account', { target: p.id })
  return error ? error.message : ''
}
