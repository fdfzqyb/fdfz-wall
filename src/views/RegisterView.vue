<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { shrinkImage } from '../image'
import Icon from '../components/Icon.vue'

const router = useRouter()
const form = ref({ name: '', sid: '', email: '', password: '', password2: '' })
const photo = ref(null)
const preview = ref('')
const error = ref('')
const busy = ref(false)

function pickPhoto(e) {
  const file = e.target.files[0]
  if (!file) return
  photo.value = file
  preview.value = URL.createObjectURL(file)
}

async function submit() {
  error.value = ''
  const f = form.value
  if (!/^\d{8}$/.test(f.sid)) return (error.value = '學號要是 8 位數字')
  if (f.password.length < 8) return (error.value = '密碼至少 8 個字元')
  if (f.password !== f.password2) return (error.value = '兩次輸入的密碼不一樣')
  if (!photo.value) return (error.value = '請上傳校園卡照片')

  busy.value = true
  try {
    const { data: taken } = await supabase.rpc('student_id_taken', { sid: f.sid })
    if (taken) throw new Error('這個學號已經註冊過，如有疑問請聯絡權益部')

    const { data, error: signUpError } = await supabase.auth.signUp({
      email: f.email.trim(),
      password: f.password,
      options: {
        data: { full_name: f.name.trim(), student_id: f.sid },
      },
    })
    if (signUpError) throw new Error('註冊失敗：' + signUpError.message)
    // email 已被用過時，Supabase 不會報錯，而是回傳一個沒有 identities 的帳號
    if (!data.user || data.user.identities?.length === 0) {
      throw new Error('這個 email 已經註冊過')
    }

    const blob = await shrinkImage(photo.value)
    // 不能用 upsert：覆蓋需要讀取權限，而新帳號還沒審核、讀不到資料夾
    const { error: uploadError } = await supabase.storage
      .from('id-cards')
      .upload(`${data.user.id}/card.jpg`, blob, { contentType: 'image/jpeg' })
    if (uploadError) {
      throw new Error('帳號已建立，但照片上傳失敗，請登入後在等待頁重新上傳（' + uploadError.message + '）')
    }

    sessionStorage.setItem('registered', JSON.stringify({ name: f.name, sid: f.sid, email: f.email }))
    router.replace('/pending')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <header class="topbar">
    <button class="back" aria-label="返回" @click="router.back()"><Icon name="back" :size="24" /></button>
    <h1>註冊新帳號</h1>
  </header>
  <form class="page stack" @submit.prevent="submit">
    <p class="muted">填寫資料並上傳校園卡照片。經權益部審核後，帳號才會開通。</p>
    <label class="field"><span>姓名</span><input v-model="form.name" required /></label>
    <label class="field">
      <span>學號</span>
      <input v-model="form.sid" inputmode="numeric" maxlength="8" required />
      <small>8 位數字，也可以用來登入</small>
    </label>
    <label class="field">
      <span>Email</span>
      <input v-model="form.email" type="email" autocomplete="email" required />
      <small>任何信箱都可以，用來登入</small>
    </label>
    <label class="field">
      <span>密碼</span>
      <input v-model="form.password" type="password" autocomplete="new-password" required />
      <small>至少 8 個字元</small>
    </label>
    <label class="field">
      <span>確認密碼</span>
      <input v-model="form.password2" type="password" autocomplete="new-password" required />
    </label>
    <label class="field">
      <span>校園卡照片</span>
      <div class="upload">
        <img v-if="preview" :src="preview" alt="校園卡預覽" />
        <template v-else>
          <Icon name="camera" :size="32" />
          <strong>拍照或選擇照片</strong>
          <small class="muted">需看清姓名和學號</small>
        </template>
        <input type="file" accept="image/*" @change="pickPhoto" />
      </div>
    </label>
    <p class="note"><Icon name="lock" :size="18" />照片只有權益部審核時看得到，審核完成後會自動刪除。</p>
    <p v-if="error" class="error">{{ error }}</p>
    <button class="btn block" :disabled="busy">{{ busy ? '提交中…' : '提交註冊' }}</button>
  </form>
</template>

<style scoped>
.upload {
  position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center;
  min-height: 140px; padding: 16px; border: 1.5px dashed var(--border); border-radius: 14px;
  background: var(--white); color: var(--navy); text-align: center;
}
.upload img { max-width: 100%; max-height: 220px; border-radius: 8px; }
.upload input { position: absolute; inset: 0; opacity: 0; cursor: pointer; }
</style>
