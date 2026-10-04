// قائمة كل شاشات التطبيق للاختبارات واللقطات.

import 'package:flutter/widgets.dart';
import 'package:hr_pro/presentation/admin/admin_dashboard/admin_dashboard_screen.dart';
import 'package:hr_pro/presentation/admin/admin_live_tracking_screen.dart';
import 'package:hr_pro/presentation/admin/admin_loans/admin_loans_screen.dart';
import 'package:hr_pro/presentation/admin/announcement_screen.dart';
import 'package:hr_pro/presentation/admin/attendance_report_screen.dart';
import 'package:hr_pro/presentation/admin/branch_management_screen.dart';
import 'package:hr_pro/presentation/admin/branch_schedule_screen.dart';
import 'package:hr_pro/presentation/admin/employee_management_screen.dart';
import 'package:hr_pro/presentation/admin/storage_stats_screen.dart';
import 'package:hr_pro/presentation/admin/trash_screen.dart';
import 'package:hr_pro/presentation/auth/change_password_screen.dart';
import 'package:hr_pro/presentation/auth/login_screen.dart';
import 'package:hr_pro/presentation/employee/announcements/announcements_board_screen.dart';
import 'package:hr_pro/presentation/employee/directory/directory_screen.dart';
import 'package:hr_pro/presentation/employee/main_layout.dart';
import 'package:hr_pro/presentation/employee/notifications/notifications_screen.dart';
import 'package:hr_pro/presentation/employee/payslips/payslips_screen.dart';

class ScreenCase {
  const ScreenCase(this.name, this.build, {this.role = 'admin'});
  final String name;
  final Widget Function() build;
  final String role;
}

final List<ScreenCase> kScreens = [
  ScreenCase('01_login', () => const LoginScreen()),
  ScreenCase('02_change_password', () => const ChangePasswordScreen()),
  ScreenCase('03_home', () => const MainLayout(), role: 'employee'),
  ScreenCase('04_attendance', () => const MainLayout(initialTab: 1), role: 'employee'),
  ScreenCase('05_leave', () => const MainLayout(initialTab: 2), role: 'employee'),
  ScreenCase('06_loan', () => const MainLayout(initialTab: 3), role: 'employee'),
  ScreenCase('07_settings_employee', () => const MainLayout(initialTab: 4), role: 'employee'),
  ScreenCase('08_settings_admin', () => const MainLayout(initialTab: 4)),
  ScreenCase('09_notifications', () => const NotificationsScreen(), role: 'employee'),
  ScreenCase('10_payslips', () => const PayslipsScreen(), role: 'employee'),
  ScreenCase('11_directory', () => const EmployeeDirectoryScreen(), role: 'employee'),
  ScreenCase('11b_announcements_board', () => const AnnouncementsBoardScreen(), role: 'employee'),
  ScreenCase('12_admin_dashboard', () => const AdminDashboardScreen()),
  ScreenCase('13_admin_loans', () => const AdminLoansManagementScreen()),
  ScreenCase('14_admin_tracking', () => const AdminLiveTrackingScreen()),
  ScreenCase('15_employee_management', () => const EmployeeManagementScreen()),
  ScreenCase('16_branches', () => const BranchManagementScreen()),
  ScreenCase('17_branch_schedule', () => const BranchScheduleScreen()),
  ScreenCase('18_announcements', () => const AnnouncementScreen()),
  ScreenCase('19_attendance_report', () => const AttendanceReportScreen()),
  ScreenCase('20_trash', () => const TrashScreen()),
  ScreenCase('21_storage', () => const StorageStatsScreen()),
];
