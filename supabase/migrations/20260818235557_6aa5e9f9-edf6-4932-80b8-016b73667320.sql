REVOKE ALL ON FUNCTION public.tenant_plan_limit_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_plan_limit() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tenant_plan_limit_internal(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.enforce_plan_limit() TO service_role;