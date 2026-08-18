-- منح دور مالكة المنصة لبريد يُمرَّر وقت التشغيل (بدون كتابة أي بريد حقيقي هنا).
-- يُضبط قبل التشغيل: SELECT set_config('app.platform_owner_email', '<email>', false);
DO $$
DECLARE
  _email text := nullif(current_setting('app.platform_owner_email', true), '');
BEGIN
  IF _email IS NULL THEN
    RAISE NOTICE 'app.platform_owner_email غير مضبوط — تم تخطي منح الدور';
    RETURN;
  END IF;

  INSERT INTO public.profiles (id, full_name, email)
  SELECT u.id, COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'), u.email
  FROM auth.users u WHERE lower(u.email) = lower(_email)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_roles (user_id, role, tenant_id)
  SELECT u.id, 'platform_owner'::public.app_role, NULL
  FROM auth.users u WHERE lower(u.email) = lower(_email)
    AND NOT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = u.id AND r.role = 'platform_owner');
END $$;
