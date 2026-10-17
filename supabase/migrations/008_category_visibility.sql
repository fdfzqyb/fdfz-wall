-- 升級：課程安排、其它兩類帖子只在「處理中」「已解決」時公開
-- 適用：已經建好的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。

-- 誰看得到哪些帖子（權益部看全部，不經過這裡）：
-- 食堂、寢室、校區基礎設施全面公開；
-- 課程安排、其它只有「處理中」「已解決」才公開，「待處理」「暫不能解決」只有發帖者看得到。
create or replace function post_visible_to_me(cat_name text, st post_status, author uuid) returns boolean
language sql stable as $$
  select cat_name in ('食堂', '寢室', '校區基礎設施')
      or st in ('in_progress', 'resolved')
      or author = auth.uid();
$$;
create or replace function post_visible(pid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from posts p join categories c on c.id = p.category_id
                 where p.id = pid and p.moderation is distinct from 'hidden'
                   and post_visible_to_me(c.name, p.status, p.author_id));
$$;

-- 回覆跟著帖子：看不到帖子，也看不到它的回覆
drop policy if exists "已審核可看回覆" on replies;
create policy "已審核可看回覆" on replies for select
  using (is_staff() or (is_approved() and post_visible(post_id)));

-- 看不到的帖子也不能按「我也遇到」
drop policy if exists "按我也遇到" on me_too;
create policy "按我也遇到" on me_too for insert
  with check (is_approved() and user_id = auth.uid() and (is_staff() or post_visible(post_id)));

-- 問題牆
create or replace view post_feed as
select p.id, p.category_id, c.name as category_name,
       case when v.masked then '（此帖涉及個人信息，內容已隱藏）' else p.title end as title,
       case when v.masked then '權益部已隱藏這個帖子的內容，處理進度仍會更新。' else p.problem end as problem,
       case when v.masked then null else p.suggestion end as suggestion,
       case when v.masked then null else p.expected end as expected,
       case when v.masked then null else p.help_offer end as help_offer,
       p.status, p.created_at, p.updated_at,
       (p.author_id = auth.uid()) as is_mine,
       (select count(*) from me_too m where m.post_id = p.id) as me_too_count,
       exists (select 1 from me_too m
               where m.post_id = p.id and m.user_id = auth.uid()) as me_too_by_me,
       exists (select 1 from replies r where r.post_id = p.id) as has_reply,
       p.moderation
from posts p
join categories c on c.id = p.category_id
cross join lateral (
  select p.moderation = 'redacted' and p.author_id is distinct from auth.uid() and not is_staff() as masked
) v
where is_approved() and p.moderation is distinct from 'hidden'
  and (is_staff() or post_visible_to_me(c.name, p.status, p.author_id));

revoke all on post_feed from anon;
grant select on post_feed to authenticated;
