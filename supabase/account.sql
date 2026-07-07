-- ============================================================
-- Lock-In — self-serve account deletion (Apple App Store requirement)
-- Paste into the Supabase SQL Editor and Run (one time).
-- Lets a signed-in user delete their own auth account. Because every
-- table cascades from auth.users, this erases all of their data too.
-- ============================================================

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
