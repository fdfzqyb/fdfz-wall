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
create policy "看自己或權益部" on posts for select
  using (author_id = auth.uid() or is_staff());
create policy "已審核可發帖" on posts for insert
  with check (is_approved() and author_id = auth.uid() and status = 'pending');
create policy "權益部改狀態" on posts for update
  using (is_staff());

-- replies
create policy "已審核可看回覆" on replies for select using (is_approved());
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
       p.title, p.problem, p.suggestion, p.expected, p.help_offer,
       p.status, p.created_at, p.updated_at,
       (p.author_id = auth.uid()) as is_mine,
       (select count(*) from me_too m where m.post_id = p.id) as me_too_count,
       exists (select 1 from me_too m
               where m.post_id = p.id and m.user_id = auth.uid()) as me_too_by_me,
       exists (select 1 from replies r where r.post_id = p.id) as has_reply
from posts p
join categories c on c.id = p.category_id
where is_approved();

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
