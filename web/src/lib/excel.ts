// ملفات Excel بالموقع (مكتبة write-excel-file بدل xlsx القديمة اللي عليها تنبيهات أمنية بدون إصلاح).
// الملف ينبني بالمتصفح وينزل مباشرة؛ نفس الشيتات والأعمدة والترتيب اللي چانت تطلع من xlsx.

import writeExcelFile from 'write-excel-file/universal';
import type { Cell, CellObject, Row, SheetData } from 'write-excel-file/universal';

export type { Cell, Row, SheetData };
export type ExcelValue = string | number | boolean | null | undefined;
export type ExcelRecord = Record<string, ExcelValue>;

export interface ExcelSheet {
  name: string;
  data: SheetData;
  /** عرض كل عمود بعدد الحروف (مثل wch بالمكتبة القديمة). */
  columns?: { width: number }[];
  rightToLeft?: boolean;
}

/** قيمة خلية: الأرقام تبقى أرقام والنصوص نصوص؛ الفارغ = خلية فارغة. */
export function excelCell(v: ExcelValue): Cell {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : String(v);
  return v;
}

/** خلية عنوان تمتد على [span] عمود (مثل دمج الخلايا A1:M1). */
export function spanningCell(value: string, span: number): CellObject & { columnSpan: number } {
  return { value, columnSpan: span };
}

/** صفوف كائنات ← جدول: سطر العناوين (مفاتيح الصفوف بترتيب ظهورها) ثم القيم. نفس json_to_sheet القديمة. */
export function recordsToRows(records: ExcelRecord[]): SheetData {
  const header: string[] = [];
  for (const r of records) for (const k of Object.keys(r)) if (!header.includes(k)) header.push(k);
  if (header.length === 0) return [];
  return [header, ...records.map((r) => header.map((k) => excelCell(r[k])))];
}

/** محتوى ملف xlsx (شيت أو أكثر). */
export function excelBlob(sheets: ExcelSheet[]): Promise<Blob> {
  return writeExcelFile(
    sheets.map((s) => ({
      sheet: s.name,
      // شيت فارغ (ماكو سجلات) يبقى موجود بالملف مثل قبل
      data: s.data.length > 0 ? s.data : [[null]],
      columns: s.columns,
      rightToLeft: s.rightToLeft,
    })),
  ).toBlob();
}

/** يبني الملف وينزّله باسم [fileName]. يرمي إذا فشل، حتى اللي يعتمد عليه (مثل حذف السلفة) يوكف. */
export async function downloadExcel(fileName: string, sheets: ExcelSheet[]): Promise<void> {
  const blob = await excelBlob(sheets);
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    a.remove();
  } finally {
    // المتصفح يبدي التنزيل فوراً؛ نحرر الرابط بعدين
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
  }
}
