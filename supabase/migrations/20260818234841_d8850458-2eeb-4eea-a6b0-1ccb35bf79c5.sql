-- 1) fix mutable search_path on trigger function
create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 2) revoke execute from anon/authenticated on all helper functions
revoke all on function public.set_updated_at() from anon, authenticated, public;
revoke all on function public.is_platform_owner(uuid) from anon, authenticated, public;
revoke all on function public.is_tenant_member(uuid, uuid) from anon, authenticated, public;
revoke all on function public.is_tenant_manager(uuid, uuid) from anon, authenticated, public;
revoke all on function public.has_tenant_role(uuid, uuid, public.app_role[]) from anon, authenticated, public;
revoke all on function public.can_record_academic(uuid, uuid) from anon, authenticated, public;
revoke all on function public.my_tenant_ids() from anon, authenticated, public;
revoke all on function public.tenant_has_feature(uuid, text) from anon, authenticated, public;
revoke all on function public.tenant_plan_limits(uuid) from anon, authenticated, public;
revoke all on function public.tenant_usage(uuid) from anon, authenticated, public;
revoke all on function public.tenant_within_limit(uuid, text) from anon, authenticated, public;
revoke all on function public.platform_revenue_monthly(integer) from anon, authenticated, public;

-- 3) add authorization checks inside the functions the app calls, then grant only to authenticated
create or replace function public.is_platform_owner(_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null or auth.uid() <> _user_id then false
    else exists (select 1 from public.user_roles r where r.user_id = _user_id and r.role = 'platform_owner')
  end;
$$;

create or replace function public.is_tenant_manager(_user_id uuid, _tenant_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null or auth.uid() <> _user_id then false
    else exists (
      select 1 from public.user_roles r
      where r.user_id = _user_id and r.tenant_id = _tenant_id and r.role in ('tenant_admin','admin_deputy')
    ) or exists (select 1 from public.user_roles r2 where r2.user_id = _user_id and r2.role = 'platform_owner')
  end;
$$;

create or replace function public.tenant_plan_limits(_tenant_id uuid)
returns table (plan_id uuid, plan_name text, max_students integer, max_circles integer, max_teachers integer)
language sql stable security definer set search_path = public as $$
  select p.id as plan_id, p.name_ar as plan_name, p.max_students, p.max_circles, p.max_teachers
  from public.subscriptions s
  join public.plans p on p.id = s.plan_id
  where s.tenant_id = _tenant_id
    and s.status in ('trialing','active','past_due')
    and (
      exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.tenant_id = _tenant_id)
      or exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role = 'platform_owner')
    )
  order by s.created_at desc
  limit 1;
$$;

create or replace function public.tenant_usage(_tenant_id uuid)
returns table (students integer, circles integer, teachers integer)
language sql stable security definer set search_path = public as $$
  select
    (select count(*)::integer from public.students st where st.tenant_id = _tenant_id),
    (select count(*)::integer from public.circles c where c.tenant_id = _tenant_id),
    (select count(*)::integer from public.user_roles r where r.tenant_id = _tenant_id and r.role = 'teacher')
  where exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.tenant_id = _tenant_id)
     or exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role = 'platform_owner');
$$;

create or replace function public.platform_revenue_monthly(_months integer default 12)
returns table (month text, currency text, paid_total numeric, invoice_count integer)
language sql stable security definer set search_path = public as $$
  select
    to_char(date_trunc('month', i.paid_at), 'YYYY-MM') as month,
    i.currency,
    sum(i.amount) as paid_total,
    count(*)::integer as invoice_count
  from public.invoices i
  where i.status = 'paid'
    and i.paid_at is not null
    and i.paid_at >= (date_trunc('month', now()) - (_months || ' months')::interval)
    and exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role = 'platform_owner')
  group by 1, 2
  order by 1 desc;
$$;

revoke all on function public.is_platform_owner(uuid) from anon, authenticated, public;
revoke all on function public.is_tenant_manager(uuid, uuid) from anon, authenticated, public;
revoke all on function public.tenant_plan_limits(uuid) from anon, authenticated, public;
revoke all on function public.tenant_usage(uuid) from anon, authenticated, public;
revoke all on function public.platform_revenue_monthly(integer) from anon, authenticated, public;

grant execute on function public.is_platform_owner(uuid) to authenticated;
grant execute on function public.is_tenant_manager(uuid, uuid) to authenticated;
grant execute on function public.tenant_plan_limits(uuid) to authenticated;
grant execute on function public.tenant_usage(uuid) to authenticated;
grant execute on function public.tenant_within_limit(uuid, text) to authenticated;
grant execute on function public.platform_revenue_monthly(integer) to authenticated;