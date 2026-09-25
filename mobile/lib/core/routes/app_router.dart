// =========================================================================
// نظام HR Pro v6.0 - موجه ومسارات التطبيق المحدّث (App Router)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../../presentation/shared/widgets/app_widgets.dart';
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

// Splash screen: shown only while the saved session is checked.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after the first frame; there is no artificial delay, the
    // native launch screen already covers start-up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
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
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 84),
              SizedBox(height: 22),
              Text(
                'HR Pro',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'نظام الموارد البشرية وإدارة الدوام',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.darkTextSecondary,
                ),
              ),
              SizedBox(height: 36),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
