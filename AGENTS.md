# 給 AI 編程助手（Codex 等）和協作者的說明

這是 fdfz權益牆網站（Vite + Vue 前端，Supabase 後台，部署在 Cloudflare Workers）。
合併到 `main` 後會自動部署到正式網站 wall.fdfz.click，所以所有改動都要走「分支 + Pull Request」，由 repo 擁有者 @fdfzqyb 審核後合併。

## 協作者的工作範圍：只改前端介面文字

可以改：

- `src/views/*.vue`、`src/components/*.vue` 裡 `<template>` 中顯示給使用者看的文字（標題、按鈕、提示、說明）
- `<script>` 裡只用來顯示的字串內容（例如錯誤提示、確認訊息），只改引號裡的文字
- `src/constants.js` 裡的 `label` 和 `hint` 文字
- `src/locales/zh-Hans.js` 的簡體對照

不要動：

- `supabase/`：資料庫結構和權限規則，改了也不會生效，只有擁有者能在 Supabase 後台執行
- `.env*`、`wrangler.jsonc`、`package.json`、`package-lock.json`、`vite.config.js`
- `src/supabase.js`、`src/auth.js`、`src/router.js`、`src/image.js`、`src/main.js`
- 程式邏輯、變數名、函式名、CSS class 名、路由路徑、圖標檔案，以及 `src/i18n.js` 的切換邏輯
- 分類名稱（食堂、寢室、校區基礎設施、課程安排、其它）：來自資料庫，`src/constants.js` 的 `CATEGORY_ICON` 鍵名必須和資料庫一致
- `src/views/NotificationsView.vue` 裡用來比對的字串（`'狀態已更新'`、`'權益部回覆'`）：通知內容由資料庫產生，前端靠這些字判斷圖標
- 不要新增套件（`npm install xxx`）

如果某個文字改動需要碰到上面的檔案，先停下來，在 PR 說明裡寫清楚，交給擁有者處理。

## 文字風格

- 網站有簡體（預設）和繁體兩種介面，在帳號頁切換。程式裡的文字一律寫**繁體**，包在 `t('…')` 裡，再到 `src/locales/zh-Hans.js` 加一行「繁體: 簡體」對照；只改了繁體沒改對照表，簡體模式下那句會變回繁體
- 改了某句繁體文字，要把 `zh-Hans.js` 裡舊的鍵一起改成新文字
- 用詞和現有一致（例如「校園卡」不是「學生證」，「權益部」，「同學」）
- 同學發的內容、姓名、伺服器回傳的錯誤訊息不要轉換
- 不要用 emoji，網站使用自繪 SVG 圖標
- 語氣簡短、口語、友善

## 提交方式

1. 從最新的 `main` 開新分支，名稱例如 `text/登入頁文案`
2. 改完執行 `npm install`（第一次）和 `npm run build`，確定能建置成功
3. 推上分支，開 Pull Request 到 `main`，說明寫「改了哪一頁的哪些文字」，最好附前後對照
4. 不要自己合併 PR，不要直接推到 `main`，不要 force push
