-- 升級：新增公告功能
-- 適用：已經執行過舊版 schema.sql 的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。

-- 公告：權益部和管理員發布，顯示在通知頁最上面
-- 長期公告（pinned = true）置頂，直到手動刪除；短期通知兩週後自動消失
-- 公告是大家共看的一份，新註冊的同學通過審核後也看得到
create table announcements (
  id bigint generated always as identity primary key,
  author_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  title text not null,
  body text not null,
  audience text not null default 'all' check (audience in ('all', 'staff')), -- all：全體用戶；staff：僅權益部和管理員
  pinned boolean not null default false,
  expires_at timestamptz, -- 長期公告為空；短期通知由觸發器設為發布後兩週
  created_at timestamptz not null default now()
);

alter table announcements enable row level security;

-- 已審核的人看得到給全體的公告，權益部另外看得到僅權益部的；過期的看不到
create policy "看公告" on announcements for select
  using (is_approved()
         and (audience = 'all' or is_staff())
         and (expires_at is null or expires_at > now()));
create policy "權益部發公告" on announcements for insert
  with check (is_staff() and author_id = auth.uid());
-- 發布者本人或管理員可以提早刪除
create policy "刪除公告" on announcements for delete
  using ((is_staff() and author_id = auth.uid()) or is_admin());

-- 發布時決定到期時間，並順手清掉已經過期的短期通知
create function announcement_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.expires_at := case when new.pinned then null else now() + interval '14 days' end;
  delete from announcements where expires_at <= now();
  return new;
end $$;

create trigger announcement_before_insert before insert on announcements
  for each row execute function announcement_before_insert();
