-- Keep the RLS helper functions out of the exposed API schema (policies reference them by OID)
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
alter function public.is_active_user() set schema private;
alter function public.is_admin() set schema private;
revoke execute on function private.is_active_user() from public, anon;
revoke execute on function private.is_admin() from public, anon;
grant execute on function private.is_active_user() to authenticated;
grant execute on function private.is_admin() to authenticated;
