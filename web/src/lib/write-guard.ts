// تعديل أو حذف ما أثّر على ولا سطر = خطأ واضح (تدقيق 14/10 CODE-009).
// سياسات القاعدة (RLS) تمنع بصمت: الطلب ينجح بدون خطأ وما يتغير شي، فالأدمن يظن انحفظ.

export class NothingChangedError extends Error {
  constructor() {
    super('ما تغيّر شي: يمكن ما عندك صلاحية، أو السجل انحذف أو تغيّر. حدّث الصفحة وجرب.');
    this.name = 'NothingChangedError';
  }
}

/** ينتظر تعديل/حذف بـ `.select('id')` ويرمي إذا ما أثّر على أي سطر. */
export async function ensureChanged<T>(query: PromiseLike<{ data: T[] | null; error: unknown }>): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw error;
  if (!data || data.length === 0) throw new NothingChangedError();
  return data;
}
