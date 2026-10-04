// =========================================================================
// نظام HR Pro v6.0 - خدمة توليد وتصدير ملفات Excel الاحترافية
// =========================================================================

import 'dart:io';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../logic/attendance_report.dart';
import '../models/loan_model.dart';
import '../utils/app_log.dart';
import 'excel/attendance_report_excel.dart';
import 'excel/loan_statement_excel.dart';
import 'share_helper.dart';

class ExcelExportService {
  /// توليد كشف حساب سلفة تفصيلي واحترافي بصيغة Excel (.xlsx) — التفاصيل في excel/loan_statement_excel.dart
  static Future<String> generateLoanStatementExcel(LoanRecord record) => buildAndSaveLoanStatementExcel(record);

  /// تقرير حضور يومي: ورقة "يوم بيوم" (سطر لكل موظف في كل يوم) وورقة "ملخص الموظفين".
  static Future<String> generateAttendanceReportExcel({
    required List<ReportRow> rows,
    required DateTime from,
    required DateTime to,
    String scopeLabel = 'كل الفروع',
  }) async {
    final bytes = buildAttendanceReportBytes(rows: rows, from: from, to: to, scopeLabel: scopeLabel);
    final fileName = 'تقرير_الحضور_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx';
    return _saveExcel(bytes, fileName);
  }

  /// محتوى ملف تقرير الحضور (بدون حفظ) — قابل للاختبار. التفاصيل في excel/attendance_report_excel.dart
  static List<int> buildAttendanceReportBytes({
    required List<ReportRow> rows,
    required DateTime from,
    required DateTime to,
    String scopeLabel = 'كل الفروع',
  }) =>
      buildAttendanceReportExcelBytes(rows: rows, from: from, to: to, scopeLabel: scopeLabel);

  static Future<String> _saveExcel(List<int> bytes, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (downloadDir.existsSync()) {
          await File('${downloadDir.path}/$fileName').writeAsBytes(bytes, flush: true);
        }
      }
    } catch (_) {}
    return file.path;
  }

  /// فتح ملف Excel بواسطة تطبيق جداول البيانات المثبت على الجهاز (Excel أو Google Sheets)
  static Future<void> openExcelFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        await shareExcelFile(filePath);
      }
    } catch (e) {
      appLog('تعذر فتح ملف Excel عبر OpenFilex: $e');
      await shareExcelFile(filePath);
    }
  }

  /// مشاركة ملف Excel عبر واتساب أو تيليغرام أو التطبيقات
  static Future<void> shareExcelFile(String filePath, {String? text}) async {
    try {
      await ShareHelper.shareParams(ShareParams(
        files: [XFile(filePath)],
        text: text ?? 'كشف حساب سلفة الموظف - HR Pro Batra',
      ));
    } catch (e) {
      appLog('تعذر مشاركة ملف Excel: $e');
    }
  }
}
