// =========================================================================
// HR Pro — daily-cleanup: الحذف الفعلي لملفات سلة المحذوفات من التخزين
// =========================================================================
// تستدعيها مهمة pg_cron اليومية (daily_trash_storage_cleanup) بعد perform_daily_cleanup.
// تُنشر بـ --no-verify-jwt مثل push-notification لأن المهمة لا تحمل مفتاحاً.
// (تدقيق 14/10 BUG-019) تشتغل بس بكود مؤقت تصدره المهمة نفسها بكل تشغيلة (issue_cleanup_token)
// بترويسة x-cleanup-token: الكود ينفع مرة وحدة وخلال ساعة. ماكو كلمة سر تنحفظ بمكان.
// تحذف فقط الملفات التي تجاوزت موعد حذفها المجدول (30 يوماً في السلة) ولم تُسترجع.
// =========================================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKETS: Record<string, string> = {
  avatar: "avatars",
  document: "employee-documents",
  pledge: "loan-pledges",
  logo: "company-logos",
};

// حد أعلى لكل تشغيل: الباقي يُحذف في اليوم التالي
const MAX_FILES_PER_RUN = 500;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // الكود المؤقت من المهمة المجدولة: ينمسح أول ما ينستعمل (ما ينفع مرتين)
    const token = req.headers.get("x-cleanup-token") ?? "";
    if (!/^[0-9a-f-]{36}$/i.test(token)) return json({ error: "unauthorized" }, 401);
    const { data: used, error: tokenError } = await supabase
      .from("cleanup_run_tokens")
      .delete()
      .eq("token", token)
      .gt("created_at", new Date(Date.now() - 3600_000).toISOString())
      .select("token");
    if (tokenError) throw tokenError;
    if (!used || used.length === 0) return json({ error: "unauthorized" }, 401);

    const { data: expired, error } = await supabase
      .from("deleted_files")
      .select("id, file_path, file_type")
      .lte("scheduled_deletion_date", new Date().toISOString())
      .is("restored_at", null)
      .limit(MAX_FILES_PER_RUN);
    if (error) throw error;

    let deleted = 0;
    for (const file of expired ?? []) {
      const bucket = BUCKETS[file.file_type] ?? "employee-documents";
      const { error: storageError } = await supabase.storage.from(bucket).remove([file.file_path]);
      if (storageError) {
        console.error(`daily-cleanup: storage remove failed for ${bucket}/${file.file_path}:`, storageError.message);
        continue;
      }
      const { error: rowError } = await supabase.from("deleted_files").delete().eq("id", file.id);
      if (rowError) {
        console.error(`daily-cleanup: could not delete trash row ${file.id}:`, rowError.message);
        continue;
      }
      deleted++;
    }

    console.log(`daily-cleanup: removed ${deleted}/${expired?.length ?? 0} expired trash files`);
    return json({ success: true, expired: expired?.length ?? 0, deleted });
  } catch (e) {
    console.error("daily-cleanup failed:", e);
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
