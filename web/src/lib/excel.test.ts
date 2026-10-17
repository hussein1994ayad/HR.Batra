// ملفات Excel الجديدة (write-excel-file): نفس شكل الصفوف القديم (json_to_sheet)، والملف نفسه سليم:
// أسماء الشيتات، الاتجاه العربي، دمج خلايا العنوان، وعرض الأعمدة.

import { strFromU8, unzipSync } from 'fflate';
import { describe, expect, it } from 'vitest';
import { excelBlob, excelCell, recordsToRows, spanningCell } from './excel';

async function unzip(blob: Blob): Promise<Record<string, string>> {
  const files = unzipSync(new Uint8Array(await blob.arrayBuffer()));
  return Object.fromEntries(Object.entries(files).map(([name, bytes]) => [name, strFromU8(bytes)]));
}

describe('recordsToRows', () => {
  it('header from the keys in order of appearance, then the values', () => {
    expect(recordsToRows([
      { 'البند': 'رقم السلفة', 'القيمة': 'L-0001' },
      { 'البند': 'المبلغ', 'القيمة': 500000, 'ملاحظة': 'جديد' },
    ])).toEqual([
      ['البند', 'القيمة', 'ملاحظة'],
      ['رقم السلفة', 'L-0001', null],
      ['المبلغ', 500000, 'جديد'],
    ]);
  });

  it('no records = empty sheet', () => {
    expect(recordsToRows([])).toEqual([]);
  });

  it('numbers stay numbers, empty values are empty cells', () => {
    expect([excelCell(12.5), excelCell(''), excelCell(null), excelCell(undefined), excelCell('نص'), excelCell(true)])
      .toEqual([12.5, null, null, null, 'نص', true]);
    expect(excelCell(Number.NaN)).toBe('NaN');
  });
});

describe('excelBlob', () => {
  it('writes every sheet with its name, an empty sheet included', async () => {
    const files = await unzip(await excelBlob([
      { name: 'ملخص السلفة', data: recordsToRows([{ 'البند': 'المبلغ', 'القيمة': 750000 }]) },
      { name: 'الأقساط', data: [] },
    ]));
    expect(files['xl/workbook.xml']).toContain('name="ملخص السلفة"');
    expect(files['xl/workbook.xml']).toContain('name="الأقساط"');
    const all = Object.values(files).join('\n');
    expect(all).toContain('750000');
    expect(all).toContain('المبلغ');
  });

  it('the tracking report: right-to-left, title merged across 13 columns, column widths', async () => {
    const files = await unzip(await excelBlob([{
      name: 'كشف الانضباط والتتبع',
      data: [[spanningCell('كشف المراقبة', 13)], [null], ...recordsToRows([{ 'ت': 1, 'اسم الموظف': 'زينب' }])],
      columns: [{ width: 6 }, { width: 28 }],
      rightToLeft: true,
    }]));
    const sheet = files['xl/worksheets/sheet1.xml'];
    expect(sheet).toMatch(/rightToLeft="(1|true)"/);
    expect(sheet).toContain('<mergeCell ref="A1:M1"');
    expect(sheet).toMatch(/<col [^>]*width="28"/);
  });
});
