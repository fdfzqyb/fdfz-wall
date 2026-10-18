import { readonly, ref } from 'vue'
import { simplified } from './locales/zh-Hans'

const STORAGE_KEY = 'fdfz-wall-language'
const DEFAULT_LOCALE = 'zh-Hans'

function readLocale() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return saved === 'zh-Hans' || saved === 'zh-Hant' ? saved : DEFAULT_LOCALE
  } catch {
    return DEFAULT_LOCALE
  }
}

const currentLocale = ref(readLocale())
export const locale = readonly(currentLocale)

export function setLocale(value) {
  if (value !== 'zh-Hans' && value !== 'zh-Hant') return
  currentLocale.value = value
  try {
    localStorage.setItem(STORAGE_KEY, value)
  } catch {
    // 儲存空間被停用時，仍允許在本次使用期間切換語言。
  }
}

// 保留訊息原文和參數，到顯示時才翻譯，已出現的提示也能隨語言更新。
export const message = (key, params = {}) => ({ key, params })

export function t(value, params = {}) {
  const key = typeof value === 'string' ? value : value?.key ?? ''
  const values = typeof value === 'string' ? params : value?.params ?? {}
  const text = currentLocale.value === 'zh-Hans' && Object.hasOwn(simplified, key)
    ? simplified[key]
    : key
  // 只處理固定文案；參數中的姓名、標題和伺服器回覆不做字體轉換。
  return text.replace(/\{(\w+)\}/g, (token, name) => {
    if (!Object.hasOwn(values, name)) return token
    const value = values[name]
    return value && typeof value === 'object' ? t(value) : String(value)
  })
}

// 僅比對資料庫產生的固定通知格式，標題維持原文；圖標仍依原始訊息判斷。
export function translateNotification(text) {
  const status = text.match(/^你的問題「([\s\S]*)」狀態已更新為：(待處理|處理中|已解決|暫不能解決)$/)
  if (status) return t('你的問題「{title}」狀態已更新為：{status}', { title: status[1], status: t(status[2]) })

  const reply = text.match(/^權益部回覆了你的問題「([\s\S]*)」$/)
  if (reply) return t('權益部回覆了你的問題「{title}」', { title: reply[1] })

  const warning = text.match(/^警告：你的問題「([\s\S]*)」含有暴力、色情、恐嚇或辱罵內容，已被權益部隱藏。請遵守發帖規範，再次違規可能會被停用帳號。$/)
  if (warning) return t('警告：你的問題「{title}」含有暴力、色情、恐嚇或辱罵內容，已被權益部隱藏。請遵守發帖規範，再次違規可能會被停用帳號。', { title: warning[1] })

  const redacted = text.match(/^你的問題「([\s\S]*)」涉及具體個人信息，內容已對其他同學隱藏，只有你和權益部看得到原文。處理狀態不受影響。$/)
  if (redacted) return t('你的問題「{title}」涉及具體個人信息，內容已對其他同學隱藏，只有你和權益部看得到原文。處理狀態不受影響。', { title: redacted[1] })

  return t(text)
}
