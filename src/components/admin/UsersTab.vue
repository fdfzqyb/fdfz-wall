<script setup>
import { t, message as uiMessage } from '../../i18n'
import { ref, onMounted } from 'vue'
import { supabase } from '../../supabase'
import { formatDate, ROLE_LABEL, VERIFY_LABEL } from '../../constants'
import { auth } from '../../auth'
import { deleteUnapprovedAccount } from '../../admin'

const emit = defineEmits(['message', 'removed'])
const users = ref([])
const userSearch = ref('')

// 這個分頁只有超級管理員用得到；資料庫也會檢查身份，普通權益部呼叫會被拒絕
async function loadUsers() {
  const { data } = await supabase.rpc('admin_list_users')
  users.value = data ?? []
}

function filteredUsers() {
  const q = userSearch.value.trim().toLowerCase()
  if (!q) return users.value
  return users.value.filter((u) =>
    [u.full_name, u.student_id, u.email].some((v) => v?.toLowerCase().includes(q)))
}

async function changeRole(u, newRole) {
  const { error } = await supabase.rpc('set_user_role', { target: u.id, new_role: newRole })
  if (error) return emit('message', error.message)
  emit('message', uiMessage('已把 {name} 設為{role}', { name: u.full_name, role: uiMessage(ROLE_LABEL[newRole]) }))
  await loadUsers()
}

async function removeAccount(u) {
  const error = await deleteUnapprovedAccount(u)
  if (error === null) return
  if (error) return emit('message', error)
  drop(u.id)
  emit('removed', u.id)
  emit('message', uiMessage('已刪除 {name} 的註冊，對方可以重新註冊', { name: u.full_name }))
}

// 別的分頁刪掉了某個帳號時，這裡也要拿掉
function drop(id) {
  users.value = users.value.filter((u) => u.id !== id)
}
defineExpose({ drop })

onMounted(loadUsers)
</script>

<template>
  <div class="stack">
    <p class="note">{{ t('只有管理員看得到這一頁。升為權益部的同學可以看到發帖人和提建議同學的姓名學號，請謹慎操作。') }}</p>
    <input v-model="userSearch" type="search" :placeholder="t('搜尋姓名、學號或 email')" />
    <p class="muted small">{{ t('共 {count} 個帳號', { count: users.length }) }}</p>
    <div v-for="u in filteredUsers()" :key="u.id" class="card user">
      <div>
        <strong>{{ u.full_name }}</strong> · {{ u.student_id }}
        <p class="muted small">{{ u.email }} · {{ t(VERIFY_LABEL[u.verify_status]) }} · {{ formatDate(u.created_at) }}</p>
      </div>
      <span v-if="u.role === 'admin' || u.id === auth.session.user.id" class="muted small">{{ t(ROLE_LABEL[u.role]) }}</span>
      <div v-else class="user-actions">
        <select :value="u.role" @change="changeRole(u, $event.target.value)">
          <option value="student">{{ t('普通同學') }}</option>
          <option value="staff">{{ t('權益部') }}</option>
        </select>
        <button v-if="u.role === 'student' && u.verify_status !== 'approved'" class="btn small danger" @click="removeAccount(u)">{{ t('刪除') }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.user { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.user p { margin: 2px 0 0; }
.user-actions { display: flex; gap: 8px; align-items: center; flex: none; }
.user select { width: auto; flex: none; }
</style>
