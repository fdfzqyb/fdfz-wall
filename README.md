# fdfz權益牆

給本校同學反映校園生活問題的網站，取代以前的問卷。同學註冊後要經權益部核對學生證才能使用；普通同學看不到發布者身份，權益部看得到。

- 前端：Vite + Vue，部署在 Cloudflare Pages
- 後端：Supabase（帳號、資料庫、學生證照片儲存）
- 資料庫結構和所有權限規則都在 [`supabase/schema.sql`](supabase/schema.sql)

## 第一次設定 Supabase

1. 到 [supabase.com](https://supabase.com) 建一個新專案。
2. **Storage** → New bucket，名稱 `id-cards`，**不要**勾 Public。可以把檔案大小上限設為 5 MB、只允許 `image/*`。
3. **SQL Editor** → 把 `supabase/schema.sql` 整份貼上 → Run。只需要執行一次。
4. **Authentication → Sign In / Providers → Email**：
   - 保留 Confirm email（同學要點驗證信）
   - Minimum password length 設為 8
5. **Authentication → URL Configuration**：Site URL 填網站網址（本機測試時是 `http://localhost:5173`，上線後改成 Cloudflare 給的 `xxx.pages.dev`）。
6. 正式開放註冊前，到 **Authentication → Emails → SMTP Settings** 接一個寄信服務（例如 Resend）。Supabase 內建的寄信每小時只能寄很少封。

### 建立第一個權益部帳號

先在網站上正常註冊，然後到 SQL Editor 執行（把學號換成你的）：

```sql
update profiles set role = 'staff', verify_status = 'approved' where student_id = '你的學號';
```

之後其他同學的帳號由權益部在網站的「權益部」頁面審核。要把某位同學升為權益部，同樣在 SQL Editor 把他的 `role` 改成 `staff`。

## 在自己電腦上執行

需要先安裝 [Node.js](https://nodejs.org)（選 LTS 版）。

```bash
npm install
cp .env.example .env   # 然後打開 .env，填上 Supabase 的網址和 key
npm run dev            # 瀏覽器打開它顯示的網址
```

`.env` 的兩個值在 Supabase 後台 **Project Settings → API Keys**：專案網址，以及 publishable（或 anon）key。**不要**用 secret / service_role key。

## 部署到 Cloudflare Pages

Cloudflare 控制台 → Workers & Pages → 建立 → Pages → 連接 GitHub，選這個 repository：

- Build command：`npm run build`
- Build output directory：`dist`
- 環境變數：`VITE_SUPABASE_URL`、`VITE_SUPABASE_KEY`（跟 `.env` 一樣）

之後每次推到 `main` 都會自動重新部署。

## 頁面一覽

| 頁面 | 路徑 | 誰能看 |
| --- | --- | --- |
| 登入（學號或 email） | `/login` | 所有人 |
| 註冊（含學生證照片） | `/register` | 所有人 |
| 等待審核 | `/pending` | 註冊後、未通過審核 |
| 問題牆（分類、搜尋、排序、我也遇到） | `/` | 已審核同學 |
| 發布問題 / 申請修改 | `/new` | 已審核同學 |
| 問題詳情、回覆、申請刪除 | `/posts/:id` | 已審核同學 |
| 我的帖子 | `/mine` | 已審核同學 |
| 通知、對權益部的建議 | `/notifications` | 已審核同學 |
| 權益部後台（帳號審核、修改刪除審批、同學建議） | `/admin` | 權益部 |
