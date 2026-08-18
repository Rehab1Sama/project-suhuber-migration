/**
 * حدّ المحاولات للمسارات المفتوحة للعامة (بدون تسجيل دخول).
 * العدّاد محفوظ في قاعدة البيانات لأن الخوادم بلا حالة (stateless).
 */
export function clientIp(request: Request): string {
  const headers = request.headers;
  const forwarded = headers.get("x-forwarded-for");
  return (
    headers.get("cf-connecting-ip") ??
    (forwarded ? forwarded.split(",")[0]!.trim() : null) ??
    headers.get("x-real-ip") ??
    "unknown"
  );
}

/** true = مسموح، false = تجاوز الحد */
export async function checkRateLimit(
  bucket: string,
  identifier: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("rate_limit_hit", {
      _bucket: bucket,
      _identifier: identifier.slice(0, 200),
      _limit: limit,
      _window_seconds: windowSeconds,
    });
    if (error) {
      console.error("[rate-limit] failed", error.message);
      return true;
    }
    return data !== false;
  } catch (e) {
    console.error("[rate-limit] error", e instanceof Error ? e.message : e);
    return true;
  }
}

export function tooManyRequests(): Response {
  return new Response("Too many requests", { status: 429, headers: { "retry-after": "60" } });
}
