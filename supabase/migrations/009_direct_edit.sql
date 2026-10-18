-- 升級：同學修改 / 刪除自己的帖子，分情況決定要不要權益部同意
-- 適用：已經建好的資料庫。全新建立的資料庫直接用 schema.sql 即可，不需要這個檔案。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。

-- 這些情況要權益部同意（走 change_requests）：
--   狀態已經不是「待處理」、權益部回覆過、被做過敏感處理，
--   或有 20 位以上其他同學按了「我也遇到」。
-- 其他情況（剛發、還沒人處理）直接生效。
-- 想調整「我也遇到」的門檻，改下面的 20 再執行一次即可。
create or replace function post_needs_approval(pid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from posts p
    where p.id = pid and (p.author_id = auth.uid() or is_staff())
      and (p.status <> 'pending'
           or p.moderation is not null
           or exists (select 1 from replies r where r.post_id = p.id)
           or (select count(*) from me_too m
               where m.post_id = p.id and m.user_id <> p.author_id) >= 20)
  );
$$;
revoke execute on function post_needs_approval(bigint) from public, anon;
grant execute on function post_needs_approval(bigint) to authenticated;

-- 同學修改 / 刪除自己的帖子都走這裡：
-- 不需要同意就直接改，回傳 'applied'；需要同意就自動送出申請，回傳 'requested'。
-- 在資料庫裡判斷，所以就算畫面停留太久、權益部剛好回覆了，也不會繞過審批。
create or replace function change_my_post(
  pid bigint, k text,
  cat int default null, new_title text default null, new_problem text default null,
  new_suggestion text default null, new_expected text default null, new_help_offer text default null
) returns text
language plpgsql security definer set search_path = public as $$
declare p posts;
begin
  if not is_approved() then
    raise exception '帳號還沒通過審核';
  end if;
  if k not in ('edit', 'delete') then
    raise exception '操作不正確';
  end if;

  select * into p from posts where id = pid for update;
  if not found or p.author_id <> auth.uid() or p.moderation = 'hidden' then
    raise exception '帖子不存在';
  end if;

  if exists (select 1 from change_requests where post_id = pid and status = 'pending') then
    raise exception '這個問題已經有一個等待審批的申請';
  end if;

  if k = 'edit' and (cat is null or coalesce(trim(new_title), '') = '' or coalesce(trim(new_problem), '') = ''
                     or coalesce(trim(new_suggestion), '') = '' or coalesce(trim(new_expected), '') = '') then
    raise exception '請把必填欄位填完整';
  end if;

  if post_needs_approval(pid) then
    insert into change_requests (post_id, requester_id, kind, new_category_id, new_title,
                                 new_problem, new_suggestion, new_expected, new_help_offer)
    values (pid, auth.uid(), k, cat, new_title, new_problem, new_suggestion, new_expected, new_help_offer);
    return 'requested';
  end if;

  if k = 'edit' then
    update posts set
      category_id = cat, title = new_title, problem = new_problem,
      suggestion = new_suggestion, expected = new_expected, help_offer = new_help_offer
    where id = pid;
  else
    delete from posts where id = pid;
  end if;
  return 'applied';
end $$;
revoke execute on function change_my_post(bigint, text, int, text, text, text, text, text) from public, anon;
grant execute on function change_my_post(bigint, text, int, text, text, text, text, text) to authenticated;
