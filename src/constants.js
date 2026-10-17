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
