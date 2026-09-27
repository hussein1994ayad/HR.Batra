/**
 * Type-safe helper to extract a message from an unknown thrown value.
 * Use with: `catch (err: unknown) { toast.error(errorMessage(err)); }`
 */
export function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'string') return err;
  // أخطاء Supabase (PostgrestError) كائنات عادية فيها message
  if (err && typeof err === 'object' && typeof (err as { message?: unknown }).message === 'string') {
    return (err as { message: string }).message;
  }
  try {
    return JSON.stringify(err);
  } catch {
    return 'حدث خطأ غير متوقع';
  }
}
