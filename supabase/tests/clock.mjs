// ساعة الفحوص ثابتة: "الآن" يبدي من يوم معروف ويمشي منه طبيعي (الثواني تتقدم).
// الفحوص بيها تواريخ ثابتة (الشهر العاشر والحادي عشر 2026) مخلوطة ويا "اليوم"، فلما الوقت الحقيقي يتقدم
// تتعارض وتفشل وحدها بدون أي تغيير بالكود (7/11/2026: ثلاث ملفات). قاعدة البيانات التجريبية (PGlite)
// تاخذ now() من نفس ساعة Node، فالاثنين يشوفون نفس اليوم.
// لازم ينستورد قبل أي شي ثاني بملف الفحص (أول سطر). يوم ثاني للتجربة: TEST_NOW=2026-11-07T10:00:00+03:00
const RealDate = Date;
const start = process.env.TEST_NOW ?? '2026-10-20T10:00:00+03:00';
const offset = RealDate.parse(start) - RealDate.now();
if (Number.isNaN(offset)) throw new Error(`TEST_NOW غير صالح: ${start}`);

class TestDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) super(RealDate.now() + offset);
    else super(...args);
  }
  static now() {
    return RealDate.now() + offset;
  }
}
globalThis.Date = TestDate;
