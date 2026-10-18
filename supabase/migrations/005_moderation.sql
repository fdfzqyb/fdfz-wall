-- 升級：新增敏感帖子處理（隱藏 / 涉及個人信息），需要兩位權益部確認
-- 適用：已經建好的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。

-- 敏感帖子處理：兩種都要至少兩位權益部確認才生效
--   hide   ：暴力、色情、恐嚇、辱罵。帖子從問題牆和「我的帖子」消失，發布者在通知欄收到警告。
--            資料仍留在資料庫，權益部後台查得到，方便日後查證。
--   redact ：涉及具體個人信息。帖子格子和處理狀態保留，其他同學只看到涉敏提示；
--            發布者本人和權益部仍看得到原文，並有標註。
alter table posts add column moderation text check (moderation in ('hidden', 'redacted'));

create table moderation_requests (
  id bigint generated always as identity primary key,
  post_id bigint not null references posts on delete cascade,
  kind text not null check (kind in ('hide', 'redact')),
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

-- 同一個帖子同時只能有一個等待確認的申請
create unique index one_pending_moderation on moderation_requests (post_id) where status = 'pending';

-- 每位權益部對每個申請只能確認一次；提出申請的人自動算第一票
create table moderation_votes (
  request_id bigint not null references moderation_requests on delete cascade,
  staff_id uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  primary key (request_id, staff_id)
);

alter table moderation_requests enable row level security;
alter table moderation_votes    enable row level security;

-- 只有權益部看得到；新增和確認都只能透過下面的函數
create policy "權益部看敏感申請" on moderation_requests for select using (is_staff());
create policy "權益部看確認紀錄" on moderation_votes for select using (is_staff());

-- 權益部不能直接改 posts.moderation 繞過兩人確認，只有 vote_moderation() 可以
create function guard_moderation() returns trigger
language plpgsql as $$
begin
  if new.moderation is distinct from old.moderation
     and coalesce(current_setting('app.moderating', true), '') <> 'on' then
    raise exception '敏感處理需要兩位權益部確認，請到權益部後台操作';
  end if;
  return new;
end $$;

create trigger posts_guard_moderation
  before update on posts
  for each row execute function guard_moderation();

-- 提出申請（提出者自動算第一位確認）
create function request_moderation(pid bigint, k text, why text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  cur text;
  new_id bigint;
begin
  if not is_staff() then
    raise exception '只有權益部可以處理敏感帖子';
  end if;
  if k not in ('hide', 'redact') then
    raise exception '處理方式不正確';
  end if;
  if coalesce(trim(why), '') = '' then
    raise exception '請填寫原因';
  end if;

  select moderation into cur from posts where id = pid;
  if not found then
    raise exception '帖子不存在';
  end if;
  if cur = 'hidden' or (cur = 'redacted' and k = 'redact') then
    raise exception '這個帖子已經處理過了';
  end if;

  insert into moderation_requests (post_id, kind, reason) values (pid, k, trim(why))
  returning id into new_id;
  insert into moderation_votes (request_id, staff_id) values (new_id, auth.uid());
  return new_id;
exception
  when unique_violation then
    raise exception '這個帖子已經有等待確認的申請';
end $$;

-- 確認或駁回；第二位權益部確認時生效
create function vote_moderation(req_id bigint, approve boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  r moderation_requests;
  t text;
  votes int;
begin
  if not is_staff() then
    raise exception '只有權益部可以處理敏感帖子';
  end if;

  select * into r from moderation_requests where id = req_id and status = 'pending' for update;
  if not found then
    raise exception '申請不存在或已處理';
  end if;

  if not approve then
    update moderation_requests set status = 'rejected', decided_at = now() where id = req_id;
    return 'rejected';
  end if;

  if exists (select 1 from moderation_votes where request_id = req_id and staff_id = auth.uid()) then
    raise exception '你已經確認過了，需要另一位權益部確認';
  end if;
  insert into moderation_votes (request_id, staff_id) values (req_id, auth.uid());

  select count(*) into votes from moderation_votes where request_id = req_id;
  if votes < 2 then
    return 'waiting';
  end if;

  perform set_config('app.moderating', 'on', true);
  update posts set moderation = case r.kind when 'hide' then 'hidden' else 'redacted' end
  where id = r.post_id
  returning title into t;
  perform set_config('app.moderating', 'off', true);

  update moderation_requests set status = 'approved', decided_at = now() where id = req_id;

  insert into notifications (user_id, post_id, message)
  select author_id,
         case r.kind when 'hide' then null else id end,
         case r.kind
           when 'hide' then '警告：你的問題「' || t || '」含有暴力、色情、恐嚇或辱罵內容，已被權益部隱藏。請遵守發帖規範，再次違規可能會被停用帳號。'
           else '你的問題「' || t || '」涉及具體個人信息，內容已對其他同學隱藏，只有你和權益部看得到原文。處理狀態不受影響。'
         end
  from posts where id = r.post_id;

  return 'applied';
end $$;

revoke execute on function request_moderation(bigint, text, text) from public, anon;
revoke execute on function vote_moderation(bigint, boolean) from public, anon;
grant execute on function request_moderation(bigint, text, text) to authenticated;
grant execute on function vote_moderation(bigint, boolean) to authenticated;

-- 問題牆：隱藏的帖子誰都看不到；涉及個人信息的帖子，除了發布者和權益部，其他人只看到提示
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
where is_approved() and p.moderation is distinct from 'hidden';

-- 被隱藏的帖子，發布者自己也不能再讀到
drop policy "看自己或權益部" on posts;
create policy "看自己或權益部" on posts for select
  using ((author_id = auth.uid() and moderation is distinct from 'hidden') or is_staff());

-- 被隱藏帖子的回覆也一併隱藏（權益部除外）
-- 同學讀不到別人的 posts，所以用 security definer 函數來查帖子有沒有被隱藏
create function post_not_hidden(pid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from posts where id = pid and moderation is distinct from 'hidden');
$$;
drop policy "已審核可看回覆" on replies;
create policy "已審核可看回覆" on replies for select
  using (is_staff() or (is_approved() and post_not_hidden(post_id)));
