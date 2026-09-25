'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { imageCompression } from '@/lib/lazy';
import { 
  Users, 
  MapPin, 
  ShieldAlert, 
  CalendarRange, 
  Coins, 
  Smartphone, 
  ArrowUpRight, 
  HardDrive,
  UserPlus,
  Send,
  AlertTriangle,
  Clock,
  CheckCircle,
  FileSpreadsheet,
  Loader2,
  X,
  Upload,
  FileImage,
  RefreshCw,
  Banknote,
  ChevronLeft,
  Building2,
  Search,
  ShieldCheck,
  Sparkles
} from 'lucide-react';
import { confetti } from '@/lib/lazy';
import Link from 'next/link';
import toast from 'react-hot-toast';

export default function DashboardPage() {
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    employees: 0,
    presentToday: 0,
    absentToday: 0,
    pendingLeaves: 0,
    pendingLoans: 0,
    pendingDevices: 0,
    securityIncidents: 0,
    totalStorageBytes: 0,
  });

  const [securityLogs, setSecurityLogs] = useState<any[]>([]);
  const [announcement, setAnnouncement] = useState('');
  const [showAnnounceModal, setShowAnnounceModal] = useState(false);
  const [showAddEmployeeModal, setShowAddEmployeeModal] = useState(false);
  const [absentList, setAbsentList] = useState<any[]>([]);
  // Targeted Announcements States
  const [targetType, setTargetType] = useState<'all' | 'branch' | 'employee'>('all');
  const [targetBranchId, setTargetBranchId] = useState('');
  const [targetEmployeeIds, setTargetEmployeeIds] = useState<string[]>([]);
  const [employeesList, setEmployeesList] = useState<any[]>([]);
  const [empSearchTerm, setEmpSearchTerm] = useState('');

  // Form fields for new employee
  const [newEmpEmail, setNewEmpEmail] = useState('');
  const [newEmpPassword, setNewEmpPassword] = useState('');
  const [newEmpName, setNewEmpName] = useState('');
  const [newEmpPhone, setNewEmpPhone] = useState('');
  const [newEmpRole, setNewEmpRole] = useState('employee');
  const [newEmpSalary, setNewEmpSalary] = useState(600000);
  const [newEmpBranch, setNewEmpBranch] = useState('');
  const [newEmpDept, setNewEmpDept] = useState('');
  const [newDocuments, setNewDocuments] = useState<File[]>([]);
  const [branches, setBranches] = useState<any[]>([]);
  const [departments, setDepartments] = useState<any[]>([]);
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [adminName, setAdminName] = useState('');
  const [lastSynced, setLastSynced] = useState<Date | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [absentSearch, setAbsentSearch] = useState('');
  const [, setNowTick] = useState(0);

  // Re-render periodically so the "last synced" label stays accurate
  useEffect(() => {
    const t = setInterval(() => setNowTick((n) => n + 1), 30000);
    return () => clearInterval(t);
  }, []);

  // Close modals with Escape
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setShowAnnounceModal(false);
        setShowAddEmployeeModal(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    // 1. Try to load cached dashboard stats instantly to bypass blocking spinners
    try {
      const cachedAdmin = JSON.parse(localStorage.getItem('batra_cache_admin') || 'null');
      if (cachedAdmin?.name) setAdminName(cachedAdmin.name);
    } catch {}

    const cachedData = localStorage.getItem('batra_cache_dashboard');
    if (cachedData) {
      try {
        const parsed = JSON.parse(cachedData);
        if (parsed) {
          if (parsed.stats) setStats(parsed.stats);
          setSecurityLogs((parsed.securityLogs || []).filter((l: any) => l && l.id));
          setBranches((parsed.branches || []).filter((b: any) => b && b.id));
          setDepartments((parsed.departments || []).filter((d: any) => d && d.id));
          setEmployeesList((parsed.employeesList || []).filter((e: any) => e && e.id));
          setAbsentList((parsed.absentList || []).filter((e: any) => e && e.id));
          if (parsed.syncedAt) setLastSynced(new Date(parsed.syncedAt));
          setLoading(false); // Instant render!
        }
      } catch (e) {
        console.error('Error parsing dashboard cache:', e);
      }
    }

    // 2. Fetch fresh data silently in the background
    fetchDashboardData(!!cachedData);
  }, []);

  const fetchDashboardData = async (hasCache = false) => {
    if (!hasCache) {
      setLoading(true);
    }
    try {
      // 0. Trigger database daily cleanup & future salary activation silently in the background
      supabase.rpc('perform_daily_cleanup').then(({ error }) => {
        if (error) console.error('Error running daily cleanup:', error);
      });

      const d = new Date();
      d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
      const todayStr = d.toISOString().split('T')[0];

      // Execute all main data fetching concurrently using Promise.all to drastically reduce load time and prevent freezing
      const [
        { count: empCount },
        { data: attToday },
        { count: leaveCount },
        { count: loanCount },
        { count: deviceCount },
        { count: mockCount },
        { count: geoCount },
        { data: delFiles },
        { data: statsData },
        { data: mockAttempts },
        { data: geoViolations },
        { data: branchList },
        { data: deptList },
        { data: empList },
        { data: leavesData },
        { data: workSchedulesData }
      ] = await Promise.all([
        supabase.from('employees').select('*', { count: 'exact', head: true }),
        supabase.from('attendance').select('status, employee_id').eq('work_date', todayStr),
        supabase.from('leave_requests').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('employee_devices').select('*', { count: 'exact', head: true }).eq('is_approved', false),
        supabase.from('mock_gps_attempts').select('*', { count: 'exact', head: true }),
        supabase.from('geofence_violations').select('*', { count: 'exact', head: true }),
        supabase.from('deleted_files').select('file_size_bytes').is('restored_at', null),
        supabase.rpc('get_storage_stats'),
        supabase.from('mock_gps_attempts').select('*, employees(full_name)').order('timestamp', { ascending: false }).limit(5),
        supabase.from('geofence_violations').select('*, employees(full_name), geofence_zones(name)').order('timestamp', { ascending: false }).limit(5),
        supabase.from('branches').select('id, name'),
        supabase.from('departments').select('id, name'),
        supabase.from('employees').select('id, full_name, branch_id, department_id').eq('is_active', true).order('full_name'),
        supabase.from('leave_requests').select('*').eq('status', 'approved'),
        supabase.from('work_schedules').select('*')
      ]);

      const [year, month, day] = todayStr.split('-');
      const dayObj = new Date(Number(year), Number(month) - 1, Number(day));
      const weekday = dayObj.getDay();

      let present = 0;
      let absent = 0;
      const presentEmpIds = new Set<string>();
      const calculatedAbsentList: any[] = [];

      if (attToday) {
        attToday.forEach(r => {
          if (['present', 'late', 'half_day'].includes(r.status)) {
            present++;
            presentEmpIds.add(r.employee_id);
          } else if (r.status === 'absent') {
            const emp = empList?.find((e: any) => e.id === r.employee_id);
            const empSched = workSchedulesData?.find((s: any) => s.employee_id === r.employee_id) || 
                             workSchedulesData?.find((s: any) => s.department_id === emp?.department_id && !s.employee_id) ||
                             workSchedulesData?.find((s: any) => s.branch_id === emp?.branch_id && !s.employee_id && !s.department_id);
            const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];
            const isWorkingDay = workDays.includes(weekday);

            if (isWorkingDay) {
              absent++;
              presentEmpIds.add(r.employee_id);
              if (emp) calculatedAbsentList.push(emp);
            }
          }
        });
      }

      // Helper for leaves
      const isDateWithinRange = (dStr: string, startStr: string, endStr: string) => {
        const d = new Date(dStr).getTime();
        const s = new Date(startStr.split('T')[0]).getTime();
        const e = new Date(endStr.split('T')[0]).getTime();
        return d >= s && d <= e;
      };

      // Calculate virtual absentees
      if (empList) {
        empList.forEach((emp: any) => {
          if (presentEmpIds.has(emp.id)) return; // Already checked in or explicitly absent
          
          // Check if on leave
          const isOnLeave = leavesData?.some((l: any) => l.employee_id === emp.id && isDateWithinRange(todayStr, l.start_date, l.end_date));
          if (!isOnLeave) {
            const empSched = workSchedulesData?.find((s: any) => s.employee_id === emp.id) || 
                             workSchedulesData?.find((s: any) => s.department_id === emp.department_id && !s.employee_id) ||
                             workSchedulesData?.find((s: any) => s.branch_id === emp.branch_id && !s.employee_id && !s.department_id);
            const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];
            const isWorkingDay = workDays.includes(weekday);

            if (isWorkingDay) {
              absent++;
              calculatedAbsentList.push(emp);
            }
          }
        });
      }

      let trashBytes = 0;
      if (delFiles) {
        delFiles.forEach(f => {
          if (f.file_size_bytes) trashBytes += Number(f.file_size_bytes);
        });
      }

      let actualStorageBytes = 0;
      if (statsData) {
        statsData.forEach((stat: any) => {
          actualStorageBytes += Number(stat.total_size || 0);
        });
      }
      
      const combinedTotalStorage = trashBytes + actualStorageBytes;

      // Format combined security logs
      const combinedLogs: any[] = [];
      if (mockAttempts) {
        mockAttempts.forEach(log => {
          combinedLogs.push({
            id: log.id,
            type: 'mock_gps',
            name: log.employees?.full_name || 'موظف غير معروف',
            timestamp: new Date(log.timestamp),
            details: `محاولة تزييف موقع باستخدام: ${log.app_used || 'تطبيق غير معروف'}`,
            coords: `${log.latitude}, ${log.longitude}`,
          });
        });
      }
      if (geoViolations) {
        geoViolations.forEach(log => {
          combinedLogs.push({
            id: log.id,
            type: 'geofence',
            name: log.employees?.full_name || 'موظف غير معروف',
            timestamp: new Date(log.timestamp),
            details: `${log.violation_type === 'entry' ? 'دخول' : 'خروج'} غير مصرح به في منطقة: ${log.geofence_zones?.name || 'مجهولة'}`,
            coords: '',
          });
        });
      }
      combinedLogs.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

      const finalStats = {
        employees: empCount || 0,
        presentToday: present,
        absentToday: absent,
        pendingLeaves: leaveCount || 0,
        pendingLoans: loanCount || 0,
        pendingDevices: deviceCount || 0,
        securityIncidents: (mockCount || 0) + (geoCount || 0),
        totalStorageBytes: combinedTotalStorage,
      };

      const finalLogs = combinedLogs.slice(0, 5);

      setStats(finalStats);
      setSecurityLogs(finalLogs);

      if (branchList) setBranches(branchList);
      if (deptList) setDepartments(deptList);
      if (empList) setEmployeesList(empList);
      setAbsentList(calculatedAbsentList);
      const syncedAt = new Date();
      setLastSynced(syncedAt);

      // Cache all results
      localStorage.setItem('batra_cache_dashboard', JSON.stringify({
        stats: finalStats,
        securityLogs: finalLogs,
        branches: branchList || [],
        departments: deptList || [],
        employeesList: empList || [],
        absentList: calculatedAbsentList,
        syncedAt: syncedAt.toISOString()
      }));

    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const handleRefresh = () => {
    if (refreshing) return;
    setRefreshing(true);
    fetchDashboardData(true);
  };

  const handlePostAnnouncement = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!announcement.trim()) return;
    setActionLoading(true);
    try {
      let targets: string[] = [];

      if (targetType === 'all') {
        const { data: emps } = await supabase.from('employees').select('id').eq('is_active', true);
        if (emps) targets = emps.map(emp => emp.id);
      } else if (targetType === 'branch') {
        if (!targetBranchId) {
          toast.error('يرجى اختيار الفرع المستهدف أولاً');
          setActionLoading(false);
          return;
        }
        const { data: emps } = await supabase.from('employees').select('id').eq('branch_id', targetBranchId).eq('is_active', true);
        if (emps) targets = emps.map(emp => emp.id);
      } else if (targetType === 'employee') {
        if (targetEmployeeIds.length === 0) {
          toast.error('يرجى اختيار موظف واحد على الأقل');
          setActionLoading(false);
          return;
        }
        targets = targetEmployeeIds;
      }

      if (targets.length === 0) {
        toast('لم يتم العثور على موظفين مستهدفين لإرسال هذا التعميم');
        setActionLoading(false);
        return;
      }

      // 1. Insert rows into notifications table
      const notifications = targets.map(empId => ({
        employee_id: empId,
        title: 'تعميم إداري هام 📢',
        body: announcement,
        type: 'memo',
        is_read: false
      }));
      
      const { error: notifErr } = await supabase.from('notifications').insert(notifications);
      if (notifErr) throw notifErr;

      // 2. Log in announcements table
      const { data: { session } } = await supabase.auth.getSession();
      await supabase.from('announcements').insert({
        title: 'تعميم إداري هام 📢',
        content: announcement,
        is_pinned: false,
        created_by: session?.user?.id || null,
      });

      // Reset
      setAnnouncement('');
      setTargetType('all');
      setTargetBranchId('');
      setTargetEmployeeIds([]);
      setEmpSearchTerm('');
      setShowAnnounceModal(false);

      confetti({
        particleCount: 80,
        spread: 60,
        origin: { y: 0.8 }
      });
      toast.success('تم إرسال وبث التعميم الإداري بنجاح! 🚀');
    } catch (err: any) {
      toast.error(`فشل إرسال التعميم: ${err.message || err}`);
    } finally {
      setActionLoading(false);
    }
  };

  const handleAddEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    setActionLoading(true);
    setActionError(null);

    try {
      // 1. Create user in Supabase auth system via standard signup
      // Note: In Next.js Web Dashboard, registering employees triggers Supabase SignUp
      const { data: authData, error: authErr } = await supabase.auth.signUp({
        email: newEmpEmail,
        password: newEmpPassword,
      });

      if (authErr) throw new Error(`خطأ في التسجيل: ${authErr.message}`);
      if (!authData.user) throw new Error('فشل تسجيل حساب الموظف.');

      const newEmpId = authData.user.id;

      // 2. Upload Documents if any
      let uploadedDocs: string[] = [];
      if (newDocuments.length > 0) {
        for (const file of newDocuments) {
          try {
            // Compress image
            const options = {
              maxSizeMB: 1,
              maxWidthOrHeight: 1024,
              useWebWorker: true,
            };
            const compressedFile = await imageCompression(file, options);
            
            const fileExt = file.name.split('.').pop();
            const fileName = `${newEmpId}/${Math.random()}.${fileExt}`;

            const { error: uploadErr } = await supabase.storage
              .from('employee-documents')
              .upload(fileName, compressedFile, { cacheControl: '3600', upsert: false });

            if (uploadErr) throw uploadErr;

            const { data: { publicUrl } } = supabase.storage
              .from('employee-documents')
              .getPublicUrl(fileName);

            uploadedDocs.push(publicUrl);
          } catch (uploadE: any) {
            console.error('Error uploading document:', uploadE);
            throw new Error(`فشل رفع إحدى المستمسكات: ${uploadE.message}`);
          }
        }
      }

      // 3. Insert record in employees table
      const { error: dbErr } = await supabase.from('employees').insert({
        id: newEmpId,
        employee_code: 'EMP-' + Math.floor(1000 + Math.random() * 9000),
        email: newEmpEmail,
        full_name: newEmpName,
        phone: newEmpPhone || null,
        role: newEmpRole,
        monthly_salary_iqd: newEmpSalary,
        branch_id: newEmpBranch || null,
        department_id: newEmpDept || null,
        document_urls: uploadedDocs,
        device_id_lock: null, // First device to login locks automatically
      });

      if (dbErr) throw new Error(`خطأ في قاعدة البيانات: ${dbErr.message}`);

      // Reset
      setNewEmpEmail('');
      setNewEmpPassword('');
      setNewEmpName('');
      setNewEmpPhone('');
      setNewEmpSalary(600000);
      setNewEmpBranch('');
      setNewEmpDept('');
      setNewDocuments([]);
      setShowAddEmployeeModal(false);
      fetchDashboardData();
      
      confetti({
        particleCount: 100,
        spread: 80,
        colors: ['#0D9488', '#3B82F6']
      });

      toast.success('تم إضافة الموظف الجديد وتوليد بياناته بنجاح! 🎉');
    } catch (err: any) {
      setActionError(err.message || 'حدث خطأ أثناء الإضافة');
    } finally {
      setActionLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <div className="skeleton h-44 rounded-3xl" />
        <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
          {Array.from({ length: 6 }).map((_, i) => <div key={i} className="skeleton h-32 rounded-2xl" />)}
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="skeleton h-80 rounded-3xl lg:col-span-2" />
          <div className="skeleton h-80 rounded-3xl" />
        </div>
      </div>
    );
  }

  const tracked = stats.presentToday + stats.absentToday;
  const attendanceRate = tracked > 0 ? Math.round((stats.presentToday / tracked) * 100) : 0;
  const firstName = (adminName || '').trim().split(/\s+/)[0];
  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'صباح الخير' : 'مساء الخير';
  const pendingTotal = stats.pendingLeaves + stats.pendingLoans + stats.pendingDevices;
  const heroSummary = [
    pendingTotal > 0 ? `لديك ${pendingTotal} طلب بانتظار قرارك` : 'لا توجد طلبات معلقة حالياً',
    stats.absentToday > 0 ? `و${stats.absentToday} موظف لم يسجلوا حضورهم بعد.` : 'والجميع سجلوا حضورهم اليوم.',
  ].join(pendingTotal > 0 ? '، ' : ' ');

  const statCards: StatCardProps[] = [
    { title: 'إجمالي الكادر', value: stats.employees, subtitle: 'الموظفون المسجلون', icon: Users, tone: 'indigo', href: '/dashboard/employees' },
    { title: 'حاضر اليوم', value: stats.presentToday, subtitle: 'سجلوا بصمة الحضور', icon: CheckCircle, tone: 'emerald', href: '/dashboard/tracking' },
    { title: 'غياب اليوم', value: stats.absentToday, subtitle: 'لم يسجلوا بصمة دخول', icon: AlertTriangle, tone: 'rose', href: '#absent-section', attention: stats.absentToday > 0 },
    { title: 'إجازات معلقة', value: stats.pendingLeaves, subtitle: 'بانتظار المراجعة', icon: CalendarRange, tone: 'amber', href: '/dashboard/leaves', attention: stats.pendingLeaves > 0 },
    { title: 'سلف مطلوبة', value: stats.pendingLoans, subtitle: 'بانتظار الاعتماد المالي', icon: Coins, tone: 'sky', href: '/dashboard/loans', attention: stats.pendingLoans > 0 },
    { title: 'اعتماد الأجهزة', value: stats.pendingDevices, subtitle: 'هواتف بانتظار الموافقة', icon: Smartphone, tone: 'violet', href: '/dashboard/employees', attention: stats.pendingDevices > 0 },
  ];

  const quickActions = [
    { label: 'إضافة موظف', hint: 'حساب وهوية جديدة', icon: UserPlus, tone: 'indigo' as Tone, onClick: () => setShowAddEmployeeModal(true) },
    { label: 'بث تعميم', hint: 'إشعار فوري للموبايل', icon: Send, tone: 'violet' as Tone, onClick: () => setShowAnnounceModal(true) },
    { label: 'الرواتب', hint: 'احتساب وصرف', icon: Banknote, tone: 'emerald' as Tone, href: '/dashboard/payroll' },
    { label: 'تقرير الحضور', hint: 'تصدير Excel', icon: FileSpreadsheet, tone: 'sky' as Tone, href: '/dashboard/tracking' },
  ];

  const q = absentSearch.trim().toLowerCase();
  const filteredAbsent = q ? absentList.filter((e) => (e.full_name || '').toLowerCase().includes(q)) : absentList;
  const absentGroups = [
    ...branches.map((b) => ({ id: b.id, name: b.name, members: filteredAbsent.filter((e) => e.branch_id === b.id) })),
    { id: '__none', name: 'بدون فرع', members: filteredAbsent.filter((e) => !e.branch_id) },
  ].filter((g) => g.members.length > 0);

  return (
    <div className="space-y-6 pb-12">
      {/* Hero */}
      <section className="relative overflow-hidden rounded-3xl border border-slate-800/70 bg-gradient-to-bl from-indigo-600/25 via-slate-900/70 to-slate-950 p-6 md:p-8">
        <div className="absolute inset-0 bg-grid opacity-60 pointer-events-none" />
        <div className="absolute -top-24 -right-16 w-72 h-72 rounded-full bg-violet-500/20 blur-3xl pointer-events-none" />
        <div className="relative flex flex-col lg:flex-row lg:items-center gap-8">
          <div className="flex-1 min-w-0">
            <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/5 border border-white/10 text-[11px] font-semibold text-indigo-200 mb-4">
              <Sparkles className="w-3.5 h-3.5" />
              ملخص اليوم
            </div>
            <h2 className="text-2xl md:text-3xl font-extrabold text-white tracking-tight">
              {greeting}{firstName ? `، ${firstName}` : ''} 👋
            </h2>
            <p className="text-sm text-slate-300/80 mt-2 max-w-xl leading-relaxed">
              {heroSummary}
            </p>

            <div className="flex flex-wrap items-center gap-2.5 mt-6">
              <button
                onClick={() => setShowAddEmployeeModal(true)}
                className="inline-flex items-center gap-2 h-10 px-4 rounded-xl bg-white text-slate-900 text-xs font-bold hover:bg-indigo-50 active:scale-[0.98] transition-all cursor-pointer shadow-lg shadow-black/20"
              >
                <UserPlus className="w-4 h-4" />
                إضافة موظف
              </button>
              <button
                onClick={() => setShowAnnounceModal(true)}
                className="inline-flex items-center gap-2 h-10 px-4 rounded-xl bg-white/10 border border-white/10 text-white text-xs font-bold hover:bg-white/15 active:scale-[0.98] transition-all cursor-pointer"
              >
                <Send className="w-4 h-4" />
                بث تعميم
              </button>
              <button
                onClick={handleRefresh}
                disabled={refreshing}
                className="inline-flex items-center gap-2 h-10 px-3 rounded-xl text-slate-300 text-[11px] font-semibold hover:text-white hover:bg-white/5 transition-colors cursor-pointer disabled:opacity-60"
                title="تحديث البيانات"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin' : ''}`} />
                <span>{refreshing ? 'جاري التحديث...' : `آخر تحديث ${timeAgo(lastSynced)}`}</span>
              </button>
            </div>
          </div>

          {/* Attendance ring */}
          <div className="flex items-center gap-6 lg:pl-2">
            <AttendanceRing percent={attendanceRate} />
            <div className="space-y-3 min-w-[150px]">
              <LegendRow color="bg-emerald-400" label="حاضرون" value={stats.presentToday} />
              <LegendRow color="bg-rose-400" label="غائبون" value={stats.absentToday} />
              <LegendRow color="bg-slate-500" label="إجمالي الكادر" value={stats.employees} />
            </div>
          </div>
        </div>
      </section>

      {/* KPI cards */}
      <section className="grid grid-cols-2 lg:grid-cols-3 gap-3 md:gap-4">
        {statCards.map((card) => <StatCard key={card.title} {...card} />)}
      </section>

      {/* Main operations */}
      <section className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Security center */}
        <div className="lg:col-span-2 surface rounded-3xl p-5 md:p-6 flex flex-col">
          <div className="flex items-start justify-between gap-3 mb-5">
            <div>
              <h3 className="text-base font-extrabold text-white flex items-center gap-2">
                <ShieldAlert className="w-[18px] h-[18px] text-rose-400" />
                مركز المراقبة الأمنية
              </h3>
              <p className="text-[11px] text-slate-500 mt-1">أحدث محاولات تزييف المواقع وخروقات السياج الجغرافي</p>
            </div>
            <span className={`shrink-0 px-2.5 py-1 rounded-full text-[10px] font-bold border ${
              stats.securityIncidents > 0 ? 'bg-rose-500/10 border-rose-500/20 text-rose-300' : 'bg-emerald-500/10 border-emerald-500/20 text-emerald-300'
            }`}>
              {stats.securityIncidents} خرق مرصود
            </span>
          </div>

          <div className="flex-grow">
            {securityLogs.length === 0 ? (
              <div className="h-56 flex flex-col items-center justify-center text-center rounded-2xl border border-dashed border-slate-800">
                <div className="p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 mb-3">
                  <ShieldCheck className="w-6 h-6" />
                </div>
                <p className="text-sm font-bold text-slate-200">كل شيء آمن</p>
                <p className="text-xs text-slate-500 mt-1">لا توجد خروقات مسجلة حالياً</p>
              </div>
            ) : (
              <ol className="relative space-y-3 before:absolute before:top-2 before:bottom-2 before:right-[19px] before:w-px before:bg-slate-800">
                {securityLogs.map((log) => {
                  const isMock = log.type === 'mock_gps';
                  return (
                    <li key={log.id} className="relative flex items-start gap-4">
                      <div className={`relative z-10 w-10 h-10 shrink-0 rounded-xl border flex items-center justify-center ${
                        isMock ? 'bg-rose-950 border-rose-500/30 text-rose-400' : 'bg-amber-950 border-amber-500/30 text-amber-400'
                      }`}>
                        {isMock ? <MapPin className="w-[18px] h-[18px]" /> : <AlertTriangle className="w-[18px] h-[18px]" />}
                      </div>
                      <div className="flex-1 min-w-0 p-3.5 rounded-2xl bg-slate-900/50 border border-slate-800/70 hover:border-slate-700/70 transition-colors">
                        <div className="flex items-center justify-between gap-2 mb-1">
                          <h4 className="text-[13px] font-bold text-white truncate">{log.name}</h4>
                          <span className="shrink-0 text-[10px] text-slate-500 flex items-center gap-1" dir="ltr">
                            <Clock className="w-3 h-3" />
                            {formatLogTime(log.timestamp)}
                          </span>
                        </div>
                        <p className="text-xs text-slate-400 leading-relaxed">{log.details}</p>
                        {log.coords && (
                          <span className="inline-block mt-2 text-[10px] bg-slate-950 border border-slate-800 px-2 py-0.5 rounded-md font-mono text-slate-400" dir="ltr">
                            {log.coords}
                          </span>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ol>
            )}
          </div>
        </div>

        {/* Side column */}
        <div className="flex flex-col gap-6">
          <div className="surface rounded-3xl p-5 md:p-6">
            <h3 className="text-base font-extrabold text-white">إجراءات سريعة</h3>
            <p className="text-[11px] text-slate-500 mt-1 mb-4">الوصول المباشر لأكثر المهام استخداماً</p>
            <div className="grid grid-cols-2 gap-3">
              {quickActions.map((a) => {
                const t = TONES[a.tone];
                const inner = (
                  <>
                    <div className={`w-9 h-9 rounded-xl border flex items-center justify-center mb-3 ${t.chip} group-hover:scale-105 transition-transform`}>
                      <a.icon className="w-[18px] h-[18px]" />
                    </div>
                    <p className="text-xs font-bold text-slate-100">{a.label}</p>
                    <p className="text-[10px] text-slate-500 mt-0.5">{a.hint}</p>
                  </>
                );
                const cls = `group text-right p-3.5 rounded-2xl bg-slate-900/60 border border-slate-800/80 hover:border-slate-700 hover:bg-slate-800/40 transition-colors cursor-pointer`;
                return a.href ? (
                  <Link key={a.label} href={a.href} className={cls}>{inner}</Link>
                ) : (
                  <button key={a.label} onClick={a.onClick} className={cls}>{inner}</button>
                );
              })}
            </div>
          </div>

          <Link href="/dashboard/storage" className="group surface rounded-3xl p-5 md:p-6 flex items-center gap-4 hover:border-slate-700 transition-colors">
            <div className="w-11 h-11 rounded-xl border flex items-center justify-center bg-sky-500/10 border-sky-500/20 text-sky-400">
              <HardDrive className="w-5 h-5" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-slate-500 font-semibold">المساحة التخزينية المستخدمة</p>
              <p className="text-lg font-extrabold text-white mt-0.5" dir="ltr">{formatBytes(stats.totalStorageBytes)}</p>
            </div>
            <ChevronLeft className="w-5 h-5 text-slate-600 group-hover:text-slate-300 group-hover:-translate-x-0.5 transition-all" />
          </Link>
        </div>
      </section>

      {/* Absentees */}
      <section id="absent-section" className="surface rounded-3xl p-5 md:p-6 scroll-mt-24">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-5">
          <div>
            <h3 className="text-base font-extrabold text-white flex items-center gap-2">
              <AlertTriangle className="w-[18px] h-[18px] text-rose-400" />
              غيابات اليوم
              <span className="px-2 py-0.5 rounded-full bg-rose-500/10 border border-rose-500/20 text-rose-300 text-[10px] font-bold">{stats.absentToday}</span>
            </h3>
            <p className="text-[11px] text-slate-500 mt-1">موظفون لم يسجلوا دخولهم اليوم وغير مجازين، مقسمون حسب الفروع</p>
          </div>
          {absentList.length > 0 && (
            <div className="relative md:w-64">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
              <input
                value={absentSearch}
                onChange={(e) => setAbsentSearch(e.target.value)}
                placeholder="ابحث عن موظف..."
                className="w-full h-9 bg-slate-950/60 border border-slate-800 focus:border-indigo-500 rounded-xl pr-9 pl-3 text-xs text-white placeholder-slate-500 outline-none"
              />
            </div>
          )}
        </div>

        {absentList.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 rounded-2xl border border-dashed border-slate-800">
            <div className="p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 mb-3">
              <CheckCircle className="w-6 h-6" />
            </div>
            <span className="text-sm font-bold text-slate-200">الجميع حاضرون!</span>
            <span className="text-xs text-slate-500 mt-1">لا توجد غيابات مسجلة لهذا اليوم.</span>
          </div>
        ) : absentGroups.length === 0 ? (
          <p className="py-10 text-center text-xs text-slate-500">لا توجد نتائج مطابقة للبحث</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {absentGroups.map((group) => (
              <div key={group.id} className="rounded-2xl bg-slate-950/40 border border-slate-800/70 overflow-hidden flex flex-col">
                <div className="px-4 py-3 border-b border-slate-800/70 flex justify-between items-center">
                  <span className="font-bold text-[13px] text-white flex items-center gap-2 min-w-0">
                    <Building2 className="w-4 h-4 text-indigo-400 shrink-0" />
                    <span className="truncate">{group.name}</span>
                  </span>
                  <span className="shrink-0 text-[10px] font-bold text-rose-300 bg-rose-500/10 px-2 py-0.5 rounded-md">
                    {group.members.length} غائب
                  </span>
                </div>
                <ul className="p-2 space-y-0.5 overflow-y-auto max-h-[240px]">
                  {group.members.map((emp) => (
                    <li key={emp.id} className="px-2.5 py-2 rounded-xl flex items-center gap-3 hover:bg-slate-800/40 transition-colors">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center text-[11px] font-bold shrink-0 ${avatarColor(emp.full_name)}`}>
                        {initials(emp.full_name)}
                      </div>
                      <p className="text-xs font-semibold text-slate-200 truncate">{emp.full_name}</p>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Announcement broadcast modal */}
      {showAnnounceModal && (
        <Modal
          title="بث تعميم إداري"
          subtitle="يصل التعميم فوراً كإشعار على هواتف الموظفين المستهدفين"
          icon={Send}
          onClose={() => setShowAnnounceModal(false)}
        >
          <form onSubmit={handlePostAnnouncement} className="space-y-4">
            <Field label="المستلمون المستهدفون">
              <div className="grid grid-cols-3 gap-2">
                {([
                  { v: 'all', l: 'الكل' },
                  { v: 'branch', l: 'فرع معين' },
                  { v: 'employee', l: 'موظفون محددون' },
                ] as const).map((opt) => (
                  <button
                    key={opt.v}
                    type="button"
                    onClick={() => setTargetType(opt.v)}
                    className={`h-10 rounded-xl text-xs font-bold border transition-colors cursor-pointer ${
                      targetType === opt.v
                        ? 'bg-indigo-500/15 border-indigo-400/40 text-indigo-200'
                        : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:text-slate-200 hover:border-slate-700'
                    }`}
                  >
                    {opt.l}
                  </button>
                ))}
              </div>
            </Field>

            {targetType === 'branch' && (
              <Field label="الفرع المستهدف">
                <select
                  value={targetBranchId}
                  onChange={(e) => setTargetBranchId(e.target.value)}
                  required
                  className={inputCls}
                >
                  <option value="">اختر الفرع...</option>
                  {branches.map(b => (
                    <option key={b.id} value={b.id}>{b.name}</option>
                  ))}
                </select>
              </Field>
            )}

            {targetType === 'employee' && (
              <Field label={`الموظفون المستهدفون (${targetEmployeeIds.length} محدد)`}>
                <input
                  type="text"
                  placeholder="ابحث باسم الموظف..."
                  value={empSearchTerm}
                  onChange={(e) => setEmpSearchTerm(e.target.value)}
                  className={`${inputCls} mb-2`}
                />
                <div className="max-h-[170px] overflow-y-auto border border-slate-800 rounded-xl p-1.5 bg-slate-950/50">
                  {employeesList
                    .filter(emp => emp && (emp.full_name || '').toLowerCase().includes(empSearchTerm.toLowerCase()))
                    .map(emp => {
                      const isChecked = targetEmployeeIds.includes(emp.id);
                      return (
                        <label key={emp.id} className={`flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-xs cursor-pointer transition-colors ${isChecked ? 'bg-indigo-500/10 text-white' : 'text-slate-300 hover:bg-slate-800/50'}`}>
                          <input
                            type="checkbox"
                            checked={isChecked}
                            onChange={() => {
                              if (isChecked) {
                                setTargetEmployeeIds(prev => prev.filter(id => id !== emp.id));
                              } else {
                                setTargetEmployeeIds(prev => [...prev, emp.id]);
                              }
                            }}
                            className="w-4 h-4 rounded"
                          />
                          <span>{emp.full_name}</span>
                        </label>
                      );
                    })}
                </div>
              </Field>
            )}

            <Field label="نص التعميم">
              <textarea
                value={announcement}
                onChange={(e) => setAnnouncement(e.target.value)}
                required
                rows={4}
                placeholder="اكتب نص التعميم هنا..."
                className={`${inputCls} resize-none leading-relaxed`}
              />
            </Field>

            <ModalFooter
              onCancel={() => setShowAnnounceModal(false)}
              loading={actionLoading}
              submitLabel="إرسال التعميم"
              loadingLabel="جاري الإرسال..."
            />
          </form>
        </Modal>
      )}

      {/* Add employee modal */}
      {showAddEmployeeModal && (
        <Modal
          title="إضافة موظف جديد"
          subtitle="إنشاء حساب دخول للموظف وتسجيل بياناته الوظيفية"
          icon={UserPlus}
          onClose={() => setShowAddEmployeeModal(false)}
        >
          {actionError && (
            <div className="flex items-start gap-2 p-3 bg-rose-500/10 border border-rose-500/20 text-rose-300 rounded-xl text-xs mb-4 animate-shake">
              <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{actionError}</span>
            </div>
          )}

          <form onSubmit={handleAddEmployee} className="space-y-4">
            <Field label="الاسم الكامل">
              <input
                type="text"
                required
                value={newEmpName}
                onChange={(e) => setNewEmpName(e.target.value)}
                placeholder="محمد علي حسين"
                className={inputCls}
              />
            </Field>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="البريد الإلكتروني">
                <input
                  type="email"
                  required
                  value={newEmpEmail}
                  onChange={(e) => setNewEmpEmail(e.target.value)}
                  placeholder="name@company.com"
                  className={`${inputCls} text-left`}
                  dir="ltr"
                />
              </Field>
              <Field label="كلمة المرور الافتراضية">
                <input
                  type="password"
                  required
                  value={newEmpPassword}
                  onChange={(e) => setNewEmpPassword(e.target.value)}
                  placeholder="••••••••"
                  className={`${inputCls} text-left`}
                  dir="ltr"
                />
              </Field>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="رقم الهاتف">
                <input
                  type="tel"
                  value={newEmpPhone}
                  onChange={(e) => setNewEmpPhone(e.target.value)}
                  placeholder="077XXXXXXXX"
                  className={`${inputCls} text-left`}
                  dir="ltr"
                />
              </Field>
              <Field label="الراتب الشهري (د.ع)">
                <input
                  type="number"
                  required
                  value={newEmpSalary}
                  onChange={(e) => setNewEmpSalary(Number(e.target.value))}
                  className={`${inputCls} text-left font-mono`}
                  dir="ltr"
                />
              </Field>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <Field label="الفرع">
                <select value={newEmpBranch} onChange={(e) => setNewEmpBranch(e.target.value)} className={inputCls}>
                  <option value="">اختر الفرع</option>
                  {branches.map(b => (
                    <option key={b.id} value={b.id}>{b.name}</option>
                  ))}
                </select>
              </Field>
              <Field label="القسم">
                <select value={newEmpDept} onChange={(e) => setNewEmpDept(e.target.value)} className={inputCls}>
                  <option value="">اختر القسم</option>
                  {departments.map(d => (
                    <option key={d.id} value={d.id}>{d.name}</option>
                  ))}
                </select>
              </Field>
              <Field label="الصلاحية">
                <select value={newEmpRole} onChange={(e) => setNewEmpRole(e.target.value)} className={inputCls}>
                  <option value="employee">موظف</option>
                  <option value="manager">مدير</option>
                  <option value="admin">مسؤول النظام</option>
                </select>
              </Field>
            </div>

            <Field label="المستمسكات الثبوتية (اختياري)">
              <label className="flex flex-col items-center justify-center w-full py-6 border border-slate-800 border-dashed rounded-xl cursor-pointer bg-slate-950/50 hover:bg-slate-900/60 hover:border-indigo-500/40 transition-colors">
                <Upload className="w-6 h-6 text-indigo-400 mb-2" />
                <p className="text-xs text-slate-300">
                  <span className="font-bold text-indigo-300">اضغط لاختيار الصور</span>
                </p>
                <p className="text-[10px] text-slate-500 mt-1">تُضغط الصور تلقائياً (حتى 1MB)</p>
                <input
                  type="file"
                  className="hidden"
                  multiple
                  accept="image/*"
                  onChange={(e) => {
                    if (e.target.files) {
                      setNewDocuments(prev => [...prev, ...Array.from(e.target.files!)]);
                    }
                  }}
                />
              </label>

              {newDocuments.length > 0 && (
                <div className="mt-3 flex flex-wrap gap-2">
                  {newDocuments.map((file, idx) => (
                    <div key={idx} className="bg-slate-900 border border-slate-700/80 rounded-lg py-1 pr-2 pl-1 flex items-center gap-2">
                      <FileImage className="w-3.5 h-3.5 text-indigo-400" />
                      <span className="text-[10px] text-slate-300 max-w-[110px] truncate" dir="ltr">{file.name}</span>
                      <button
                        type="button"
                        onClick={() => setNewDocuments(prev => prev.filter((_, i) => i !== idx))}
                        className="p-1 hover:bg-rose-500/20 text-slate-500 hover:text-rose-400 rounded-md transition-colors cursor-pointer"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </Field>

            <ModalFooter
              onCancel={() => setShowAddEmployeeModal(false)}
              loading={actionLoading}
              submitLabel="إضافة الموظف"
              loadingLabel="جاري إنشاء الحساب..."
            />
          </form>
        </Modal>
      )}
    </div>
  );
}

/* ----------------------------- UI helpers ----------------------------- */

type Tone = 'indigo' | 'emerald' | 'rose' | 'amber' | 'sky' | 'violet';

const TONES: Record<Tone, { chip: string; glow: string; value: string }> = {
  indigo: { chip: 'bg-indigo-500/10 border-indigo-500/20 text-indigo-300', glow: 'from-indigo-500/15', value: 'text-white' },
  emerald: { chip: 'bg-emerald-500/10 border-emerald-500/20 text-emerald-300', glow: 'from-emerald-500/15', value: 'text-white' },
  rose: { chip: 'bg-rose-500/10 border-rose-500/20 text-rose-300', glow: 'from-rose-500/15', value: 'text-white' },
  amber: { chip: 'bg-amber-500/10 border-amber-500/20 text-amber-300', glow: 'from-amber-500/15', value: 'text-white' },
  sky: { chip: 'bg-sky-500/10 border-sky-500/20 text-sky-300', glow: 'from-sky-500/15', value: 'text-white' },
  violet: { chip: 'bg-violet-500/10 border-violet-500/20 text-violet-300', glow: 'from-violet-500/15', value: 'text-white' },
};

const inputCls =
  'w-full bg-slate-950/70 border border-slate-800 hover:border-slate-700 focus:border-indigo-500 rounded-xl px-3.5 py-2.5 text-[13px] text-white placeholder-slate-600 outline-none';

interface StatCardProps {
  title: string;
  value: number;
  subtitle: string;
  icon: React.ComponentType<any>;
  tone: Tone;
  href: string;
  attention?: boolean;
}

function StatCard({ title, value, subtitle, icon: Icon, tone, href, attention }: StatCardProps) {
  const t = TONES[tone];
  return (
    <Link
      href={href}
      className="group relative overflow-hidden surface rounded-2xl p-4 md:p-5 hover:border-slate-700 hover:-translate-y-0.5 transition-all duration-200"
    >
      <div className={`absolute inset-0 bg-gradient-to-bl ${t.glow} to-transparent to-60% opacity-0 group-hover:opacity-100 transition-opacity duration-300 pointer-events-none`} />
      <div className="relative flex items-start justify-between gap-2">
        <div className={`w-10 h-10 rounded-xl border flex items-center justify-center ${t.chip}`}>
          <Icon className="w-5 h-5" />
        </div>
        {attention ? (
          <span className="flex items-center gap-1 text-[10px] font-bold text-amber-300 bg-amber-400/10 border border-amber-400/20 px-2 py-0.5 rounded-full">
            <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
            <span className="hidden sm:inline">يتطلب إجراء</span>
          </span>
        ) : (
          <ChevronLeft className="w-4 h-4 text-slate-600 group-hover:text-slate-300 group-hover:-translate-x-0.5 transition-all" />
        )}
      </div>
      <div className="relative mt-4">
        <p className={`text-2xl md:text-3xl font-extrabold tracking-tight ${t.value}`}>{value.toLocaleString('en-US')}</p>
        <p className="text-xs font-bold text-slate-300 mt-1">{title}</p>
        <p className="text-[10px] md:text-[11px] text-slate-500 mt-0.5 truncate">{subtitle}</p>
      </div>
    </Link>
  );
}

function AttendanceRing({ percent }: { percent: number }) {
  const r = 52;
  const c = 2 * Math.PI * r;
  const offset = c - (Math.min(Math.max(percent, 0), 100) / 100) * c;
  return (
    <div className="relative w-36 h-36 shrink-0">
      <svg viewBox="0 0 128 128" className="w-full h-full -rotate-90">
        <defs>
          <linearGradient id="ringGrad" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#34D399" />
            <stop offset="100%" stopColor="#22D3EE" />
          </linearGradient>
        </defs>
        <circle cx="64" cy="64" r={r} fill="none" stroke="rgb(255 255 255 / 0.08)" strokeWidth="10" />
        <circle
          cx="64"
          cy="64"
          r={r}
          fill="none"
          stroke="url(#ringGrad)"
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 0.9s cubic-bezier(0.16, 1, 0.3, 1)' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-3xl font-extrabold text-white" dir="ltr">{percent}%</span>
        <span className="text-[10px] font-semibold text-slate-400">نسبة الحضور</span>
      </div>
    </div>
  );
}

function LegendRow({ color, label, value }: { color: string; label: string; value: number }) {
  return (
    <div className="flex items-center gap-3">
      <span className={`w-2.5 h-2.5 rounded-full ${color}`} />
      <span className="flex-1 text-xs text-slate-300">{label}</span>
      <span className="text-sm font-extrabold text-white">{value.toLocaleString('en-US')}</span>
    </div>
  );
}

function Modal({
  title,
  subtitle,
  icon: Icon,
  onClose,
  children,
}: {
  title: string;
  subtitle?: string;
  icon: React.ComponentType<any>;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-start sm:items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto" onMouseDown={onClose}>
      <div
        className="relative w-full max-w-xl surface-solid rounded-3xl my-8 animate-glass text-right"
        onMouseDown={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        <div className="flex items-start gap-3 p-5 md:p-6 border-b border-slate-800/80">
          <div className="w-10 h-10 shrink-0 rounded-xl bg-gradient-to-br from-indigo-500 to-violet-600 text-white flex items-center justify-center shadow-lg shadow-indigo-500/25">
            <Icon className="w-5 h-5" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="text-base font-extrabold text-white">{title}</h3>
            {subtitle && <p className="text-[11px] text-slate-500 mt-0.5">{subtitle}</p>}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-2 -m-1 rounded-lg text-slate-500 hover:text-white hover:bg-slate-800 transition-colors cursor-pointer"
            aria-label="إغلاق"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-5 md:p-6">{children}</div>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="block text-[11px] font-bold text-slate-400 mb-1.5">{label}</label>
      {children}
    </div>
  );
}

function ModalFooter({
  onCancel,
  loading,
  submitLabel,
  loadingLabel,
}: {
  onCancel: () => void;
  loading: boolean;
  submitLabel: string;
  loadingLabel: string;
}) {
  return (
    <div className="flex items-center justify-end gap-2 pt-4 mt-2 border-t border-slate-800/80">
      <button
        type="button"
        onClick={onCancel}
        className="h-10 px-4 rounded-xl text-xs font-bold text-slate-400 hover:text-white hover:bg-slate-800 transition-colors cursor-pointer"
      >
        إلغاء
      </button>
      <button
        type="submit"
        disabled={loading}
        className="h-10 px-5 rounded-xl bg-gradient-to-l from-indigo-500 to-violet-600 hover:from-indigo-400 hover:to-violet-500 text-white text-xs font-bold shadow-lg shadow-indigo-500/25 active:scale-[0.98] transition-all cursor-pointer disabled:opacity-60 flex items-center gap-2"
      >
        {loading && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
        {loading ? loadingLabel : submitLabel}
      </button>
    </div>
  );
}

const AVATAR_COLORS = [
  'bg-indigo-500/15 text-indigo-300',
  'bg-violet-500/15 text-violet-300',
  'bg-sky-500/15 text-sky-300',
  'bg-emerald-500/15 text-emerald-300',
  'bg-amber-500/15 text-amber-300',
  'bg-rose-500/15 text-rose-300',
];

function avatarColor(name: string = '') {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}

function initials(name: string = '') {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].substring(0, 2);
  return parts[0][0] + parts[1][0];
}

function formatBytes(bytes: number) {
  if (!bytes) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / Math.pow(1024, i)).toFixed(i >= 2 ? 1 : 0)} ${units[i]}`;
}

function formatLogTime(ts: any) {
  if (!ts) return 'غير محدد';
  const d = new Date(ts);
  if (isNaN(d.getTime())) return 'وقت غير صالح';
  const sameDay = d.toDateString() === new Date().toDateString();
  const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
  return sameDay ? time : `${d.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit' })} · ${time}`;
}

function timeAgo(date: Date | null) {
  if (!date) return 'الآن';
  const mins = Math.floor((Date.now() - date.getTime()) / 60000);
  if (mins < 1) return 'الآن';
  if (mins < 60) return `منذ ${mins} دقيقة`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `منذ ${hours} ساعة`;
  return `منذ ${Math.floor(hours / 24)} يوم`;
}
