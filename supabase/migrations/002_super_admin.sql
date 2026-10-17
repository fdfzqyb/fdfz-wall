-- 升級：新增「超級管理員」身份，權益部不能再改別人的身份
-- 適用：已經執行過舊版 schema.sql 的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。
-- 執行完，再用最下面那句把你自己設為 admin。

alter type user_role add value if not exists 'admin';

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and verify_status = 'approved'
                   and role::text in ('staff', 'admin'));
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and verify_status = 'approved' and role::text = 'admin');
$$;

-- 舊規則允許權益部直接改任何人的 profiles（包括身份），拿掉
drop policy if exists "權益部審核" on profiles;

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

-- 把自己設為超級管理員（把學號換成你的，然後單獨執行這一句）：
-- update profiles set role = 'admin', verify_status = 'approved' where student_id = '你的學號';
