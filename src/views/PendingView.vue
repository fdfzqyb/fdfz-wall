<script setup>
import { ref, computed } from 'vue'
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
const email = computed(() => auth.session?.user.email ?? saved?.email)
const message = ref('')

async function resend() {
  const { error } = await supabase.auth.resend({ type: 'signup', email: email.value })
  message.value = error ? '寄送失敗，請稍後再試' : '驗證信已重新寄出'
}

async function reupload(e) {
  const file = e.target.files[0]
  if (!file) return
  const blob = await shrinkImage(file)
  const { error } = await supabase.storage
    .from('id-cards')
    .upload(`${auth.session.user.id}/card.jpg`, blob, { upsert: true, contentType: 'image/jpeg' })
  message.value = error ? '上傳失敗，請稍後再試' : '照片已上傳，請等權益部重新審核'
}

async function refresh() {
  await loadProfile()
  if (isApproved()) router.replace('/')
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
      <h1>{{ loggedIn ? '正在等待審核' : '註冊申請已提交' }}</h1>
      <p class="muted">
        {{ loggedIn ? '權益部核對你的學生證後，就能開始使用。' : '先到信箱點擊驗證連結，然後等權益部核對你的學生證。' }}
      </p>
    </template>

    <div class="card steps">
      <div class="step done">
        <b><Icon name="check" :size="18" /></b>
        <div><strong>提交資料</strong><p class="muted small" v-if="name">{{ name }} · {{ sid }}</p></div>
      </div>
      <div class="step" :class="{ done: loggedIn }">
        <b><Icon v-if="loggedIn" name="check" :size="18" /><template v-else>2</template></b>
        <div>
          <strong>驗證 Email</strong>
          <p class="muted small" v-if="email">驗證信已寄到 {{ email }}</p>
          <button v-if="!loggedIn && email" class="btn plain small" @click="resend">重新寄送</button>
        </div>
      </div>
      <div class="step">
        <b>3</b>
        <div><strong>權益部審核學生證</strong><p class="muted small">通過後就能使用，照片隨即刪除</p></div>
      </div>
    </div>

    <label v-if="rejected" class="btn ghost block upload">
      重新上傳學生證照片
      <input type="file" accept="image/*" @change="reupload" />
    </label>
    <p v-if="message" class="note">{{ message }}</p>

    <div class="actions">
      <button v-if="loggedIn" class="btn ghost block" @click="refresh">重新檢查審核狀態</button>
      <button v-if="loggedIn" class="btn plain block" @click="logout">登出</button>
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
