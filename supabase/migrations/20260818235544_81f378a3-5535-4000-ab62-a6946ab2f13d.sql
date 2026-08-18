-- 1) حدود الباقة كقيد فعلي في قاعدة البيانات
CREATE OR REPLACE FUNCTION public.tenant_plan_limit_internal(_tenant_id uuid, _kind text)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  select case _kind
      when 'students' then p.max_students
      when 'circles' then p.max_circles
      when 'teachers' then p.max_teachers
      else null end
  from public.subscriptions s
  join public.plans p on p.id = s.plan_id
  where s.tenant_id = _tenant_id
    and s.status in ('trialing','active','past_due')
  order by s.created_at desc
  limit 1;
$$;

CREATE OR REPLACE FUNCTION public.enforce_plan_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _kind text := TG_ARGV[0];
  _tenant uuid;
  _limit integer;
  _usage integer;
BEGIN
  IF _kind = 'teachers' THEN
    IF NEW.role <> 'teacher' OR NEW.tenant_id IS NULL THEN RETURN NEW; END IF;
  END IF;

  _tenant := NEW.tenant_id;
  IF _tenant IS NULL THEN RETURN NEW; END IF;

  _limit := public.tenant_plan_limit_internal(_tenant, _kind);
  IF _limit IS NULL OR _limit = 0 THEN RETURN NEW; END IF;

  IF _kind = 'students' THEN
    SELECT count(*) INTO _usage FROM public.students WHERE tenant_id = _tenant;
  ELSIF _kind = 'circles' THEN
    SELECT count(*) INTO _usage FROM public.circles WHERE tenant_id = _tenant;
  ELSE
    SELECT count(*) INTO _usage FROM public.user_roles WHERE tenant_id = _tenant AND role = 'teacher';
  END IF;

  IF _usage >= _limit THEN
    RAISE EXCEPTION 'تم الوصول إلى حد الباقة (%: % من %)', _kind, _usage, _limit
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS enforce_plan_limit_students ON public.students;
CREATE TRIGGER enforce_plan_limit_students
  BEFORE INSERT ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.enforce_plan_limit('students');

DROP TRIGGER IF EXISTS enforce_plan_limit_circles ON public.circles;
CREATE TRIGGER enforce_plan_limit_circles
  BEFORE INSERT ON public.circles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_plan_limit('circles');

DROP TRIGGER IF EXISTS enforce_plan_limit_teachers ON public.user_roles;
CREATE TRIGGER enforce_plan_limit_teachers
  BEFORE INSERT ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_plan_limit('teachers');

-- 2) حد المحاولات للصفحات العامة
CREATE TABLE IF NOT EXISTS public.rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket text NOT NULL,
  identifier text NOT NULL,
  window_start timestamptz NOT NULL,
  count integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (bucket, identifier, window_start)
);

GRANT ALL ON public.rate_limits TO service_role;
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.rate_limit_hit(
  _bucket text,
  _identifier text,
  _limit integer,
  _window_seconds integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _win timestamptz := to_timestamp(floor(extract(epoch from now()) / _window_seconds) * _window_seconds);
  _count integer;
BEGIN
  INSERT INTO public.rate_limits (bucket, identifier, window_start, count)
  VALUES (_bucket, _identifier, _win, 1)
  ON CONFLICT (bucket, identifier, window_start)
  DO UPDATE SET count = public.rate_limits.count + 1
  RETURNING count INTO _count;

  DELETE FROM public.rate_limits WHERE window_start < now() - interval '1 day';

  RETURN _count <= _limit;
END $$;

REVOKE ALL ON FUNCTION public.rate_limit_hit(text, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rate_limit_hit(text, text, integer, integer) TO service_role;