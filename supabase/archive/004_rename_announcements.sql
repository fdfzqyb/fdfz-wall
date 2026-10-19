-- 升級：把公告表從 announcements 改名為 gonggao
-- 原因：Vivaldi 等瀏覽器內建的廣告攔截會擋掉網址裡有 announcement 的請求，公告發不出去也讀不到
-- 適用：已經執行過 003_announcements.sql 的資料庫。全新建立的資料庫直接用 schema.sql 即可。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。
-- 改名會連同資料、權限規則和觸發器一起保留。

alter table announcements rename to gonggao;

create or replace function announcement_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.expires_at := case when new.pinned then null else now() + interval '14 days' end;
  delete from gonggao where expires_at <= now();
  return new;
end $$;
