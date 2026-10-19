-- 升級：所有分類「待處理」的帖子都只有發帖者和權益部看得到
-- 適用：已經執行過 008_category_visibility.sql 的資料庫。全新建立的資料庫直接用 schema.sql 即可。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。
-- 問題牆、回覆和「我也遇到」都透過這個函數判斷，只要換掉它就生效。

-- 誰看得到哪些帖子（權益部看全部，不經過這裡）：
-- 「待處理」的帖子一律只有發帖者看得到；
-- 食堂、寢室、校區基礎設施在「處理中」「已解決」「暫不能解決」時公開；
-- 課程安排、其它只有「處理中」「已解決」才公開。
create or replace function post_visible_to_me(cat_name text, st post_status, author uuid) returns boolean
language sql stable as $$
  select st in ('in_progress', 'resolved')
      or (st = 'wont_fix' and cat_name in ('食堂', '寢室', '校區基礎設施'))
      or author = auth.uid();
$$;
