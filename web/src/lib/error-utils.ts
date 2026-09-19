/**
 * Type-safe helper to extract a message from an unknown thrown value.
 * Use with: `catch (err: unknown) { toast.error(errorMessage(err)); }`
 */
export function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'string') return err;
  try {
    return JSON.stringify(err);
  } catch {
    return 'حدث خطأ غير متوقع';
  }
}
