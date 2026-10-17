<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { auth, signOut, loadProfile, isApproved } from '../auth'
import { shrinkImage } from '../image'
import Icon from '../components/Icon.vue'

const router = useRouter()
// 剛註冊完還沒登入時，資料從註冊頁暫存在 sessionStorage
const saved = JSON.parse(sessionStorage.getItem('registered') || 'null')
const loggedIn = computed(() => !!auth.session)
const rejected = computed(() => auth.profile?.verify_status === 'rejected')
const name = computed(() => auth.profile?.full_name ?? saved?.name)
const sid = computed(() => auth.profile?.student_id ?? saved?.sid)
const message = ref('')
// 註冊時照片可能沒傳成功；登入後查一下自己的資料夾，沒有照片就讓他補傳
const hasPhoto = ref(true)

onMounted(async () => {
  if (!auth.session) return
  const { data } = await supabase.storage.from('id-cards').list(auth.session.user.id)
  hasPhoto.value = !!data?.some((f) => f.name === 'card.jpg')
})

async function reupload(e) {
  const file = e.target.files[0]
  if (!file) return
  const blob = await shrinkImage(file)
  const { error } = await supabase.storage
    .from('id-cards')
    .upload(`${auth.session.user.id}/card.jpg`, blob, { upsert: true, contentType: 'image/jpeg' })
  if (error) {
    message.value = '上傳失敗，請稍後再試（' + error.message + '）'
  } else {
    hasPhoto.value = true
    message.value = rejected.value ? '照片已上傳，請等權益部重新審核' : '照片已上傳，請等權益部審核'
  }
}

async function refresh() {
  await loadProfile()
  if (isApproved()) router.replace('/')
}

// 資料填錯或註冊出了問題：刪掉這次註冊，同一個學號和 email 就能重新註冊
async function deleteAccount() {
  if (!window.confirm('確定刪除這次註冊？刪除後要重新填寫資料、上傳學生證。')) return
  const id = auth.session.user.id
  await supabase.storage.from('id-cards').remove([`${id}/card.jpg`])
  const { error } = await supabase.rpc('delete_unapproved_account', { target: id })
  if (error) return (message.value = '刪除失敗：' + error.message)
  // 帳號已經不在了，只清掉這台裝置上的登入狀態
  await supabase.auth.signOut({ scope: 'local' })
  auth.profile = null
  sessionStorage.removeItem('registered')
  router.replace('/register')
}

async function logout() {
  await signOut()
  router.replace('/login')
}
</script>

<template>
  <div class="page pending">
    <div class="clock"><Icon name="clock" :size="34" /></div>
    <template v-if="rejected">
      <h1>審核未通過</h1>
      <p class="muted">權益部無法從照片確認你的身份。請重新上傳一張清楚的學生證照片，或直接聯絡權益部。</p>
    </template>
    <template v-else>
      <h1>正在等待審核</h1>
      <p class="muted">權益部核對你的學生證後，就能開始使用。</p>
    </template>

    <div class="card steps">
      <div class="step done">
        <b><Icon name="check" :size="18" /></b>
        <div><strong>提交資料</strong><p class="muted small" v-if="name">{{ name }} · {{ sid }}</p></div>
      </div>
      <div class="step">
        <b>2</b>
        <div><strong>權益部審核學生證</strong><p class="muted small">通過後就能使用，照片隨即刪除</p></div>
      </div>
    </div>

    <p v-if="loggedIn && !hasPhoto && !rejected" class="note">還沒收到你的學生證照片，請先上傳，權益部才能審核。</p>
    <label v-if="rejected || (loggedIn && !hasPhoto)" class="btn ghost block upload">
      {{ hasPhoto ? '重新上傳學生證照片' : '上傳學生證照片' }}
      <input type="file" accept="image/*" @change="reupload" />
    </label>
    <p v-if="message" class="note">{{ message }}</p>

    <div class="actions">
      <button v-if="loggedIn" class="btn ghost block" @click="refresh">重新檢查審核狀態</button>
      <button v-if="loggedIn" class="btn plain block" @click="logout">登出</button>
      <button v-if="loggedIn" class="btn danger block" @click="deleteAccount">資料填錯了？刪除這次註冊</button>
      <router-link v-else to="/login" class="btn plain block">回到登入頁</router-link>
    </div>
  </div>
</template>

<style scoped>
.pending { padding-top: 48px; }
.clock { width: 64px; height: 64px; border-radius: 50%; background: #dde9f7; display: grid; place-items: center; color: var(--navy); }
h1 { font-size: 26px; margin: 20px 0 8px; }
.steps { margin: 24px 0; display: grid; gap: 18px; }
.step { display: flex; gap: 14px; }
.step b {
  flex: none; width: 30px; height: 30px; border-radius: 50%; display: grid; place-items: center;
  border: 2px solid var(--border); color: var(--muted); font-size: 14px;
}
.step.done b { background: #1e6b3a; border-color: #1e6b3a; color: var(--white); }
.step p { margin: 2px 0 8px; }
.upload { position: relative; }
.upload input { position: absolute; inset: 0; opacity: 0; cursor: pointer; }
.actions { display: grid; gap: 10px; margin-top: 24px; }
</style>
