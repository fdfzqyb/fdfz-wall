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
