// Supabase يرجع 1000 صف كحد أقصى للطلب الواحد وبدون أي تحذير، فالتقارير الطويلة
// (سنة × كل الموظفين) كانت تنقص بصمت. هذه الدالة تجلب الصفحات حتى النهاية.

type Page<T> = PromiseLike<{ data: T[] | null; error: unknown }>;

/**
 * `page(from, to)` يبني الاستعلام من جديد لكل صفحة ويطبّق `.range(from, to)`،
 * ويجب أن يكون مرتّباً ترتيباً ثابتاً (مثلاً `.order('id')`) حتى لا تتكرر الصفوف أو تضيع.
 */
export async function fetchAllRows<T>(page: (from: number, to: number) => Page<T>, pageSize = 1000): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await page(from, from + pageSize - 1);
    if (error) throw error;
    rows.push(...(data ?? []));
    if (!data || data.length < pageSize) return rows;
  }
}
