-- 升級：權益部幫忘記密碼的同學重設臨時密碼
-- 適用：已經建好的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。

-- 忘記密碼：同學當面找權益部核對身份，權益部用學號產生一組臨時密碼告訴他。
-- 同學用臨時密碼登入後，網站會要求他先改成自己的密碼。
-- 權益部只能重設普通同學；管理員還可以重設權益部。不能重設自己和管理員（管理員到 Supabase 後台處理）。
alter table profiles add column if not exists must_change_password boolean not null default false;

create or replace function reset_password(sid text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  p profiles;
  -- 去掉 0/O、1/l/I 這些容易看錯的字元
  chars text := 'abcdefghjkmnpqrstuvwxyz23456789';
  tmp text := '';
begin
  if not is_staff() then
    raise exception '只有權益部可以重設密碼';
  end if;
  select * into p from profiles where student_id = sid;
  if not found then
    raise exception '找不到這個學號';
  end if;
  if p.id = auth.uid() then
    raise exception '不能重設自己的密碼，請到「帳號」頁修改';
  end if;
  if p.role::text = 'admin' or (p.role::text = 'staff' and not is_admin()) then
    raise exception '權益部帳號只能由管理員重設';
  end if;

  for i in 1..8 loop
    tmp := tmp || substr(chars, 1 + get_byte(gen_random_bytes(1), 0) % length(chars), 1);
  end loop;

  update auth.users set encrypted_password = crypt(tmp, gen_salt('bf')), updated_at = now()
  where id = p.id;
  update profiles set must_change_password = true where id = p.id;
  return tmp;
end $$;

-- 同學改好自己的密碼後呼叫，取消「必須改密碼」的提醒
create or replace function password_changed() returns void
language sql security definer set search_path = public as $$
  update profiles set must_change_password = false where id = auth.uid();
$$;

revoke execute on function reset_password(text) from public, anon;
revoke execute on function password_changed() from public, anon;
grant execute on function reset_password(text) to authenticated;
grant execute on function password_changed() to authenticated;
