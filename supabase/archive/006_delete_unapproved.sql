-- 升級：讓未通過審核的帳號可以被刪除，方便重新註冊
-- 適用：已經建好的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。

-- 刪除還沒通過審核的帳號（被拒絕、資料填錯、照片沒傳成功），刪掉後同一個學號和 email 可以重新註冊。
-- 權益部可以刪任何未通過的同學帳號；同學自己在審核頁也可以刪掉自己的。已通過的帳號不能用這個刪。
-- 學生證照片由前端先刪，這裡刪 auth.users，profiles 會跟著一起刪掉。
create or replace function delete_unapproved_account(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_staff() or target = auth.uid()) then
    raise exception '只有權益部或本人可以刪除帳號';
  end if;
  if not exists (select 1 from profiles where id = target
                 and role::text = 'student' and verify_status::text <> 'approved') then
    raise exception '帳號不存在，或已經通過審核，不能刪除';
  end if;
  delete from auth.users where id = target;
end $$;
revoke execute on function delete_unapproved_account(uuid) from public, anon;
grant execute on function delete_unapproved_account(uuid) to authenticated;

create policy "未審核本人刪學生證" on storage.objects for delete to authenticated
  using (bucket_id = 'id-cards'
         and (storage.foldername(name))[1] = auth.uid()::text
         and can_upload_card((storage.foldername(name))[1]));
