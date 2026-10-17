-- fdfz權益牆 資料庫結構
-- 用法：在 Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。
-- 執行前請先在 Storage 建一個名叫 id-cards 的 Private bucket。

-------------------------------------------------------------------------------
-- 1. 資料表
-------------------------------------------------------------------------------

create type post_status as enum ('pending', 'in_progress', 'resolved', 'wont_fix');
-- student = 普通同學，staff = 權益部，admin = 超級管理員（擁有權益部全部權限，另外可以改別人的身份）
create type user_role as enum ('student', 'staff', 'admin');
create type verify_state as enum ('pending', 'approved', 'rejected');

-- 每個帳號的個人資料（email 和密碼由 Supabase Auth 管理）
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text not null,
  student_id text not null unique check (student_id ~ '^[0-9]{8}$'),
  role user_role not null default 'student',
  verify_status verify_state not null default 'pending',
  created_at timestamptz not null default now()
);

create table categories (
  id serial primary key,
  name text not null,
  sort_order int not null default 0
);

insert into categories (name, sort_order) values
  ('食堂', 1), ('寢室', 2), ('校區基礎設施', 3), ('課程安排', 4), ('其它', 5);

-- 同學發布的問題
create table posts (
  id bigint generated always as identity primary key,
  author_id uuid not null default auth.uid() references profiles(id),
  category_id int not null references categories(id),
  title text not null check (char_length(title) between 1 and 60),
  problem text not null,      -- 問題描述
  suggestion text not null,   -- 可行建議
  expected text not null,     -- 預期解決效果
  help_offer text,            -- 願意付出的努力（選填）
  status post_status not null default 'pending',
  moderation text check (moderation in ('hidden', 'redacted')), -- 敏感處理，見第 7 節
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 權益部的回覆
create table replies (
  id bigint generated always as identity primary key,
  post_id bigint not null references posts on delete cascade,
  staff_id uuid not null default auth.uid() references profiles(id),
  body text not null,
  created_at timestamptz not null default now()
);

-- 「我也遇到」
create table me_too (
  post_id bigint references posts on delete cascade,
  user_id uuid default auth.uid() references profiles(id),
  primary key (post_id, user_id)
);

-- 同學的修改 / 刪除申請（要權益部同意）
create table change_requests (
  id bigint generated always as identity primary key,
  post_id bigint not null references posts on delete cascade,
  requester_id uuid not null default auth.uid() references profiles(id),
  kind text not null check (kind in ('edit', 'delete')),
  new_category_id int references categories(id),
  new_title text,
  new_problem text,
  new_suggestion text,
  new_expected text,
  new_help_offer text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

-- 同一個問題同時只能有一個等待中的申請
create unique index one_pending_request on change_requests (post_id) where status = 'pending';

-- 通知欄
create table notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  post_id bigint references posts on delete set null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- 對權益部工作的建議（權益部看得到姓名和學號）
create table feedback (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references profiles(id),
  body text not null,
  created_at timestamptz not null default now()
);

-------------------------------------------------------------------------------
-- 2. 權限（RLS）
-------------------------------------------------------------------------------

create function is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and verify_status = 'approved');
$$;

create function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and verify_status = 'approved'
                   and role::text in ('staff', 'admin'));
$$;

create function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and verify_status = 'approved' and role::text = 'admin');
$$;

alter table profiles        enable row level security;
alter table categories      enable row level security;
alter table posts           enable row level security;
alter table replies         enable row level security;
alter table me_too          enable row level security;
alter table change_requests enable row level security;
alter table notifications   enable row level security;
alter table feedback        enable row level security;

-- profiles：看自己；權益部看全部。
-- 沒有任何 update 規則：審核帳號只能透過 review_account()，改身份只能透過 set_user_role()（只有 admin）。
create policy "看自己或權益部" on profiles for select
  using (id = auth.uid() or is_staff());

-- categories
create policy "已審核可看分類" on categories for select using (is_approved());

-- posts：同學只看得到自己的（問題牆改讀 post_feed），權益部看全部、改狀態
-- 被隱藏的敏感帖子，發布者自己也看不到
create policy "看自己或權益部" on posts for select
  using ((author_id = auth.uid() and moderation is distinct from 'hidden') or is_staff());
create policy "已審核可發帖" on posts for insert
  with check (is_approved() and author_id = auth.uid() and status = 'pending');
create policy "權益部改狀態" on posts for update
  using (is_staff());

-- replies
-- 被隱藏帖子的回覆也一併隱藏（權益部除外）
-- 同學讀不到別人的 posts，所以用 security definer 函數來查帖子有沒有被隱藏
create function post_not_hidden(pid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from posts where id = pid and moderation is distinct from 'hidden');
$$;
create policy "已審核可看回覆" on replies for select
  using (is_staff() or (is_approved() and post_not_hidden(post_id)));
create policy "權益部回覆" on replies for insert
  with check (is_staff() and staff_id = auth.uid());

-- me_too
create policy "看自己的" on me_too for select using (user_id = auth.uid());
create policy "按我也遇到" on me_too for insert
  with check (is_approved() and user_id = auth.uid());
create policy "取消我也遇到" on me_too for delete using (user_id = auth.uid());

-- change_requests
create policy "看自己的申請或權益部" on change_requests for select
  using (requester_id = auth.uid() or is_staff());
create policy "對自己的問題提申請" on change_requests for insert
  with check (is_approved() and requester_id = auth.uid() and status = 'pending'
              and exists (select 1 from posts where id = post_id and author_id = auth.uid()));

-- notifications
create policy "看自己的通知" on notifications for select using (user_id = auth.uid());
create policy "標為已讀" on notifications for update using (user_id = auth.uid());

-- feedback
create policy "提交建議" on feedback for insert
  with check (is_approved() and user_id = auth.uid());
create policy "看自己的或權益部" on feedback for select
  using (user_id = auth.uid() or is_staff());

-- 問題牆：給所有已審核同學看的版本，沒有 author_id
-- 視圖以建立者身份執行，會繞過 posts 的 RLS；最後的 where is_approved() 是它的門禁，不能拿掉。
create view post_feed as
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

revoke all on post_feed from anon;
grant select on post_feed to authenticated;

-------------------------------------------------------------------------------
-- 3. 註冊、學號登入、學生證照片
-------------------------------------------------------------------------------

-- 新帳號自動建 profiles（姓名、學號從註冊時的 options.data 帶進來）
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name, student_id)
  values (new.id,
          new.raw_user_meta_data->>'full_name',
          new.raw_user_meta_data->>'student_id');
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- 註冊前檢查學號是否已被使用（只回答是或否，不透露其他資料）
create function student_id_taken(sid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where student_id = sid);
$$;
grant execute on function student_id_taken(text) to anon, authenticated;

-- 學號 + 密碼正確時才回傳 email，讓前端用 email 登入
create function login_email(sid text, pw text) returns text
language sql security definer set search_path = public, extensions as $$
  select u.email
  from auth.users u join profiles p on p.id = u.id
  where p.student_id = sid
    and u.encrypted_password = crypt(pw, u.encrypted_password);
$$;
grant execute on function login_email(text, text) to anon, authenticated;

-- 學生證照片：註冊時還沒驗證 email、沒有登入狀態，所以允許「尚未通過審核的帳號」
-- 把照片放進自己的資料夾（資料夾名是帳號 id，只有註冊的人自己知道）。
create function can_upload_card(folder text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id::text = folder and verify_status <> 'approved');
$$;
grant execute on function can_upload_card(text) to anon, authenticated;

create policy "未審核帳號上傳學生證" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'id-cards' and can_upload_card((storage.foldername(name))[1]));
create policy "未審核帳號覆蓋學生證" on storage.objects for update to anon, authenticated
  using (bucket_id = 'id-cards' and can_upload_card((storage.foldername(name))[1]))
  with check (bucket_id = 'id-cards' and can_upload_card((storage.foldername(name))[1]));
create policy "本人或權益部可看" on storage.objects for select to authenticated
  using (bucket_id = 'id-cards'
         and ((storage.foldername(name))[1] = auth.uid()::text or is_staff()));
create policy "權益部可刪" on storage.objects for delete to authenticated
  using (bucket_id = 'id-cards' and is_staff());

-------------------------------------------------------------------------------
-- 4. 通知與修改刪除審批
-------------------------------------------------------------------------------

create function notify_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into notifications (user_id, post_id, message)
    values (new.author_id, new.id,
            '你的問題「' || new.title || '」狀態已更新為：' ||
            case new.status
              when 'pending'     then '待處理'
              when 'in_progress' then '處理中'
              when 'resolved'    then '已解決'
              else '暫不能解決'
            end);
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger posts_status_notify
  before update on posts
  for each row execute function notify_status_change();

create function notify_reply() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, post_id, message)
  select author_id, id, '權益部回覆了你的問題「' || title || '」'
  from posts where id = new.post_id;
  return new;
end $$;

create trigger replies_notify
  after insert on replies
  for each row execute function notify_reply();

create function review_change_request(req_id bigint, approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r change_requests;
begin
  if not is_staff() then
    raise exception '只有權益部可以審批';
  end if;

  select * into r from change_requests
  where id = req_id and status = 'pending' for update;
  if not found then
    raise exception '申請不存在或已處理';
  end if;

  if approve and r.kind = 'edit' then
    update posts set
      category_id = r.new_category_id, title = r.new_title,
      problem = r.new_problem, suggestion = r.new_suggestion,
      expected = r.new_expected, help_offer = r.new_help_offer
    where id = r.post_id;
  end if;

  update change_requests
  set status = case when approve then 'approved' else 'rejected' end,
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = req_id;

  insert into notifications (user_id, post_id, message)
  values (r.requester_id,
          case when approve and r.kind = 'delete' then null else r.post_id end,
          '你的' || case r.kind when 'edit' then '修改' else '刪除' end
          || '申請' || case when approve then '已通過' else '未通過' end);

  if approve and r.kind = 'delete' then
    delete from posts where id = r.post_id;
  end if;
end $$;

revoke execute on function review_change_request(bigint, boolean) from public, anon;
grant execute on function review_change_request(bigint, boolean) to authenticated;

-------------------------------------------------------------------------------
-- 5. 帳號審核與超級管理員
-------------------------------------------------------------------------------

-- 權益部審核帳號：只能處理待審核或被拒絕的普通同學，不能動權益部或管理員
create or replace function review_account(target uuid, approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then
    raise exception '只有權益部可以審核帳號';
  end if;

  update profiles
  set verify_status = case when approve then 'approved' else 'rejected' end::verify_state
  where id = target
    and role::text = 'student'
    and verify_status::text in ('pending', 'rejected');

  if not found then
    raise exception '帳號不存在或不需要審核';
  end if;
end $$;

-- 超級管理員改別人的身份（student 或 staff）。不能改自己，也不能改其他管理員。
-- 升為權益部時同時視為已審核。
create or replace function set_user_role(target uuid, new_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    raise exception '只有管理員可以修改身份';
  end if;
  if new_role not in ('student', 'staff') then
    raise exception '身份只能設為 student 或 staff';
  end if;
  if target = auth.uid() then
    raise exception '不能修改自己的身份';
  end if;

  update profiles
  set role = new_role::user_role,
      verify_status = case when new_role = 'staff' then 'approved'::verify_state else verify_status end
  where id = target and role::text <> 'admin';

  if not found then
    raise exception '帳號不存在，或對方是管理員';
  end if;
end $$;

-- 超級管理員看所有用戶（含 email）
create or replace function admin_list_users()
returns table (id uuid, full_name text, student_id text, email text,
               role text, verify_status text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then
    raise exception '只有管理員可以查看所有用戶';
  end if;
  return query
    select p.id, p.full_name, p.student_id, u.email::text,
           p.role::text, p.verify_status::text, p.created_at
    from profiles p join auth.users u on u.id = p.id
    order by p.created_at desc;
end $$;

revoke execute on function review_account(uuid, boolean) from public, anon;
revoke execute on function set_user_role(uuid, text) from public, anon;
revoke execute on function admin_list_users() from public, anon;
grant execute on function review_account(uuid, boolean) to authenticated;
grant execute on function set_user_role(uuid, text) to authenticated;
grant execute on function admin_list_users() to authenticated;

-------------------------------------------------------------------------------
-- 6. 公告
-------------------------------------------------------------------------------

-- 公告：權益部和管理員發布，顯示在通知頁最上面
-- 表名用 gonggao 而不是 announcements：瀏覽器的廣告攔截會擋掉網址裡有 announcement 的請求
-- 長期公告（pinned = true）置頂，直到手動刪除；短期通知兩週後自動消失
-- 公告是大家共看的一份，新註冊的同學通過審核後也看得到
create table gonggao (
  id bigint generated always as identity primary key,
  author_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  title text not null,
  body text not null,
  audience text not null default 'all' check (audience in ('all', 'staff')), -- all：全體用戶；staff：僅權益部和管理員
  pinned boolean not null default false,
  expires_at timestamptz, -- 長期公告為空；短期通知由觸發器設為發布後兩週
  created_at timestamptz not null default now()
);

alter table gonggao enable row level security;

-- 已審核的人看得到給全體的公告，權益部另外看得到僅權益部的；過期的看不到
create policy "看公告" on gonggao for select
  using (is_approved()
         and (audience = 'all' or is_staff())
         and (expires_at is null or expires_at > now()));
create policy "權益部發公告" on gonggao for insert
  with check (is_staff() and author_id = auth.uid());
-- 發布者本人或管理員可以提早刪除
create policy "刪除公告" on gonggao for delete
  using ((is_staff() and author_id = auth.uid()) or is_admin());

-- 發布時決定到期時間，並順手清掉已經過期的短期通知
create function announcement_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.expires_at := case when new.pinned then null else now() + interval '14 days' end;
  delete from gonggao where expires_at <= now();
  return new;
end $$;

create trigger announcement_before_insert before insert on gonggao
  for each row execute function announcement_before_insert();

-------------------------------------------------------------------------------
-- 7. 敏感帖子處理
-------------------------------------------------------------------------------

-- 敏感帖子處理：兩種都要至少兩位權益部確認才生效
--   hide   ：暴力、色情、恐嚇、辱罵。帖子從問題牆和「我的帖子」消失，發布者在通知欄收到警告。
--            資料仍留在資料庫，權益部後台查得到，方便日後查證。
--   redact ：涉及具體個人信息。帖子格子和處理狀態保留，其他同學只看到涉敏提示；
--            發布者本人和權益部仍看得到原文，並有標註。
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
