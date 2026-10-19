export const STATUS = {
  pending: { label: '待處理', cls: 'st-pending' },
  in_progress: { label: '處理中', cls: 'st-progress' },
  resolved: { label: '已解決', cls: 'st-resolved' },
  wont_fix: { label: '暫不能解決', cls: 'st-wontfix' },
}

export function formatDate(iso) {
  const d = new Date(iso)
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

// 分類名稱對應的圖標（src/icons/ 裡的檔名）
export const CATEGORY_ICON = {
  食堂: 'cat-canteen',
  寢室: 'cat-dorm',
  校區基礎設施: 'cat-campus',
  課程安排: 'cat-course',
  其它: 'cat-other',
}

// 敏感帖子的兩種處理方式（都需要兩位權益部確認）
export const MODERATION_KIND = {
  hide: { label: '隱藏', hint: '暴力、色情、恐嚇、辱罵：帖子直接消失，發布者收到警告' },
  redact: { label: '涉及個人信息', hint: '保留帖子和處理狀態，其他同學只看到涉敏提示' },
}

// 身份和帳號審核狀態的顯示文字
export const ROLE_LABEL = { student: '普通同學', staff: '權益部', admin: '管理員' }
export const VERIFY_LABEL = { pending: '待審核', approved: '已通過', rejected: '未通過' }

// 校園卡照片在 id-cards 儲存空間裡的位置：每人一個以帳號 id 命名的資料夾
export const CARD_FILE = 'card.jpg'
export const cardPath = (userId) => `${userId}/${CARD_FILE}`
