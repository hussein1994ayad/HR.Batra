// =========================================================================
// نظام HR Pro v6.0 - موجه ومسارات التطبيق المحدّث (App Router)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/change_password_screen.dart';
import '../../presentation/employee/main_layout.dart';
import '../../presentation/employee/directory_screen.dart';
import '../../presentation/employee/notifications_screen.dart';
import '../../presentation/employee/admin_dashboard_screen.dart';
import '../../presentation/employee/trash_screen.dart';
import '../../presentation/employee/storage_stats_screen.dart';
import '../../presentation/employee/branch_schedule_screen.dart';
import '../../presentation/employee/employee_management_screen.dart';
import '../../presentation/employee/branch_management_screen.dart';
import '../../presentation/employee/announcement_screen.dart';
import '../../presentation/employee/attendance_report_screen.dart';
import '../../presentation/employee/payslips_screen.dart';

// تعريف المسارات كمسميات
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String changePassword = '/change-password';
  
  // مسارات الموظف (كلها تؤدي للهيكل المشترك وتفعّل التبويب المناسب)
  static const String employeeHome = '/employee/home';
  static const String employeeAttendance = '/employee/attendance';
  static const String employeeLeave = '/employee/leave';
  static const String employeeLoan = '/employee/loan';
  static const String employeeDirectory = '/employee/directory';
  static const String employeeNotifications = '/employee/notifications';
  static const String employeePayslips = '/employee/payslips';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminTrash = '/admin/trash';
  static const String adminStorage = '/admin/storage';
  static const String adminBranchSchedule = '/admin/branch-schedule';
  static const String adminEmployeeManagement = '/admin/employee-management';
  static const String adminBranchManagement = '/admin/branch-management';
  static const String adminAnnouncement = '/admin/announcement';
  static const String adminAttendanceReport = '/admin/attendance-report';
  static const String settings = '/settings';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  
  // حارس التوجيه لحماية المسارات والتحقق من تسجيل الدخول (Route Guard)
  redirect: (BuildContext context, GoRouterState state) {
    final bool loggedIn = SupabaseService.isAuthenticated;
    final bool loggingIn = state.matchedLocation == AppRoutes.login;
    final bool isSplash = state.matchedLocation == AppRoutes.splash;

    if (!loggedIn && !loggingIn && !isSplash) {
      return AppRoutes.login;
    }
    
    if (loggedIn && loggingIn) {
      return AppRoutes.employeeHome;
    }
    
    return null;
  },
  
  routes: <RouteBase>[
    // 1. شاشة البداية والتحميل (Splash Screen)
    GoRoute(
      path: AppRoutes.splash,
      builder: (BuildContext context, GoRouterState state) {
        return const SplashScreen();
      },
    ),
    
    // 2. شاشة تسجيل الدخول (Login Screen)
    GoRoute(
      path: AppRoutes.login,
      builder: (BuildContext context, GoRouterState state) {
        return const LoginScreen();
      },
    ),

    // 3. شاشة تغيير كلمة المرور الإلزامية
    GoRoute(
      path: AppRoutes.changePassword,
      builder: (BuildContext context, GoRouterState state) {
        return const ChangePasswordScreen();
      },
    ),
    
    // 4. مسارات الموظف وهيكله الرئيسي المشترك (Main Navigation tabs)
    GoRoute(
      path: AppRoutes.employeeHome,
      builder: (BuildContext context, GoRouterState state) {
        return const MainLayout(initialTab: 0);
      },
    ),
    
    GoRoute(
      path: AppRoutes.employeeAttendance,
      builder: (BuildContext context, GoRouterState state) {
        return const MainLayout(initialTab: 1);
      },
    ),
    
    GoRoute(
      path: AppRoutes.employeeLeave,
      builder: (BuildContext context, GoRouterState state) {
        return const MainLayout(initialTab: 2);
      },
    ),
    
    GoRoute(
      path: AppRoutes.employeeLoan,
      builder: (BuildContext context, GoRouterState state) {
        return const MainLayout(initialTab: 3);
      },
    ),

    GoRoute(
      path: AppRoutes.settings,
      builder: (BuildContext context, GoRouterState state) {
        return const MainLayout(initialTab: 4);
      },
    ),
    
    // شاشات فرعية للموظف
    GoRoute(
      path: AppRoutes.employeeDirectory,
      builder: (BuildContext context, GoRouterState state) {
        return const EmployeeDirectoryScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.employeeNotifications,
      builder: (BuildContext context, GoRouterState state) {
        return const NotificationsScreen();
      },
    ),

    GoRoute(
      path: AppRoutes.employeePayslips,
      builder: (BuildContext context, GoRouterState state) {
        return const PayslipsScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminDashboard,
      builder: (BuildContext context, GoRouterState state) {
        return const AdminDashboardScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminTrash,
      builder: (BuildContext context, GoRouterState state) {
        return const TrashScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminStorage,
      builder: (BuildContext context, GoRouterState state) {
        return const StorageStatsScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminBranchSchedule,
      builder: (BuildContext context, GoRouterState state) {
        return const BranchScheduleScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminEmployeeManagement,
      builder: (BuildContext context, GoRouterState state) {
        return const EmployeeManagementScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminBranchManagement,
      builder: (BuildContext context, GoRouterState state) {
        return const BranchManagementScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminAnnouncement,
      builder: (BuildContext context, GoRouterState state) {
        return const AnnouncementScreen();
      },
    ),
    
    GoRoute(
      path: AppRoutes.adminAttendanceReport,
      builder: (BuildContext context, GoRouterState state) {
        return const AttendanceReportScreen();
      },
    ),
  ],
);

// شاشة البداية الذكية والمتحركة (Splash Screen Component)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // محاكاة تأخير بسيط لإظهار شعار الشركة الأنيق وتجهيز الاتصال بـ Supabase
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (SupabaseService.isAuthenticated) {
      // نتحقق من ضرورة تغيير كلمة المرور للموظف عند الدخول
      final mustChange = await AuthService.checkMustChangePassword();
      if (!mounted) return;

      if (mustChange) {
        context.go(AppRoutes.changePassword);
      } else {
        context.go(AppRoutes.employeeHome);
      }
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryTeal.withAlpha(50),
                      blurRadius: 24,
                      spreadRadius: 4,
                    )
                  ],
                ),
                child: const Icon(Icons.business_center, size: 72, color: AppTheme.primaryTeal),
              ),
              const SizedBox(height: 24),
              const Text(
                'HR Pro v6.0',
                style: TextStyle(
                  fontSize: 26, 
                  fontWeight: FontWeight.w900, 
                  color: AppTheme.primaryTeal,
                  fontFamily: 'Cairo',
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'نظام الموارد البشرية وإدارة الدوام المتقدم',
                style: TextStyle(
                  fontSize: 12, 
                  color: Colors.grey,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppTheme.primaryTeal,
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
