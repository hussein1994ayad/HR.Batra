'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import imageCompression from 'browser-image-compression';
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
  FileImage
} from 'lucide-react';
import confetti from 'canvas-confetti';
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

  useEffect(() => {
    // 1. Try to load cached dashboard stats instantly to bypass blocking spinners
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

      // Cache all results
      localStorage.setItem('batra_cache_dashboard', JSON.stringify({
        stats: finalStats,
        securityLogs: finalLogs,
        branches: branchList || [],
        departments: deptList || [],
        employeesList: empList || []
      }));

    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
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
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-indigo-400 animate-spin" />
      </div>
    );
  }

  const statCards = [
    { title: 'إجمالي الكادر', value: stats.employees, subtitle: 'الموظفين النشطين', icon: Users, color: 'text-indigo-400 bg-indigo-500/10 border-indigo-500/20', href: '/dashboard/employees' },
    { title: 'حاضر اليوم', value: stats.presentToday, subtitle: 'سجلوا الحضور اليوم', icon: CheckCircle, color: 'text-violet-400 bg-violet-500/10 border-violet-500/20', href: '/dashboard/tracking' },
    { title: 'غياب اليوم', value: stats.absentToday, subtitle: 'لم يسجلوا بصمة دخول', icon: AlertTriangle, color: 'text-rose-400 bg-rose-500/10 border-rose-500/20', href: '#absent-section' },
    { title: 'طلبات الإجازة المعلقة', value: stats.pendingLeaves, subtitle: 'تحت التدقيق الإداري', icon: CalendarRange, color: 'text-amber-400 bg-amber-500/10 border-amber-500/20', href: '/dashboard/leaves' },
    { title: 'السلف المطلوبة', value: stats.pendingLoans, subtitle: 'بانتظار الاعتماد المالي', icon: Coins, color: 'text-sky-400 bg-sky-500/10 border-sky-500/20', href: '/dashboard/loans' },
    { title: 'طلبات اعتماد الأجهزة', value: stats.pendingDevices, subtitle: 'تغيير أو قفل هواتف الموظفين', icon: Smartphone, color: 'text-purple-400 bg-purple-500/10 border-purple-500/20', href: '/dashboard/employees' },
  ];

  return (
    <div className="space-y-8 pb-12">
      {/* Quick Visual Hero Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        {statCards.map((card, i) => (
          <Link 
            key={i} 
            href={card.href}
            className="group relative bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl hover:border-slate-700/60 hover:-translate-y-0.5 transition-all duration-300 block cursor-pointer"
          >
            <div className="flex items-center justify-between">
              <div>
                <span className="text-xs text-slate-400 font-bold block mb-1.5">{card.title}</span>
                <span className="text-3xl font-extrabold text-white tracking-tight">{card.value}</span>
                <span className="text-[10px] text-slate-500 font-medium block mt-1.5">{card.subtitle}</span>
              </div>
              <div className={`p-4 rounded-2xl border ${card.color} group-hover:scale-110 transition-transform duration-300`}>
                <card.icon className="w-6 h-6 shrink-0" />
              </div>
            </div>
          </Link>
        ))}
      </div>

      {/* Main Operations Block */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* Security Incident Center */}
        <div className="lg:col-span-2 bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
                <ShieldAlert className="w-5 h-5 text-rose-500" />
                <span>مركز المراقبة وسجلات الأمان لليوم</span>
              </h3>
              <p className="text-[11px] text-slate-400">سجل محاولات تزييف المواقع والخروقات المباشرة</p>
            </div>
            <div className="px-3 py-1 bg-rose-500/10 border border-rose-500/20 text-rose-400 rounded-full text-[10px] font-bold">
              {stats.securityIncidents} خرق مرصود
            </div>
          </div>

          <div className="flex-grow space-y-4">
            {securityLogs.length === 0 ? (
              <div className="h-48 flex flex-col items-center justify-center text-slate-500 text-xs">
                <CheckCircle className="w-10 h-10 text-emerald-500/40 mb-2 animate-bounce" />
                <span>كل شيء آمن اليوم! لا توجد خروقات مسجلة.</span>
              </div>
            ) : (
              securityLogs.map((log) => (
                <div 
                  key={log.id} 
                  className={`flex items-start gap-4 p-4 border rounded-2xl transition-all ${
                    log.type === 'mock_gps' 
                      ? 'bg-rose-500/5 border-rose-500/10 hover:bg-rose-500/10' 
                      : 'bg-amber-500/5 border-amber-500/10 hover:bg-amber-500/10'
                  }`}
                >
                  <div className={`p-2.5 rounded-xl border shrink-0 ${
                    log.type === 'mock_gps' ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-amber-500/10 border-amber-500/20 text-amber-400'
                  }`}>
                    <AlertTriangle className="w-5 h-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between mb-1">
                      <h4 className="text-sm font-bold text-white truncate">{log.name}</h4>
                      <span className="text-[9px] text-slate-400 flex items-center gap-1">
                        <Clock className="w-3.5 h-3.5" />
                        {(() => {
                          if (!log.timestamp) return 'غير محدد';
                          const d = new Date(log.timestamp);
                          return isNaN(d.getTime()) ? 'وقت غير صالح' : d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
                        })()}
                      </span>
                    </div>
                    <p className="text-xs text-slate-300 mb-1">{log.details}</p>
                    {log.coords && (
                      <span className="text-[10px] bg-slate-950 px-2 py-0.5 rounded font-mono text-rose-400">
                        {log.coords}
                      </span>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Quick Operations panel */}
        <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 flex flex-col justify-between">
          <div>
            <h3 className="text-lg font-extrabold text-white mb-1">لوحة الإجراءات الفورية</h3>
            <p className="text-slate-400 text-xs mb-6">مجموع الإجراءات الإدارية المباشرة للأدمن</p>

            <div className="space-y-4">
              <button
                onClick={() => setShowAddEmployeeModal(true)}
                className="w-full flex items-center justify-between p-4 bg-gradient-to-l from-slate-800/80 to-slate-900/80 border border-slate-800 hover:border-indigo-500/40 rounded-2xl text-white transition-all duration-300 group cursor-pointer"
              >
                <div className="flex items-center gap-3">
                  <div className="p-2.5 bg-indigo-500/10 rounded-xl text-indigo-400 border border-indigo-500/20 group-hover:scale-110 transition-transform">
                    <UserPlus className="w-5 h-5" />
                  </div>
                  <div className="text-right">
                    <span className="text-xs font-bold block text-slate-200">إضافة موظف جديد</span>
                    <span className="text-[10px] text-slate-500 block">تسجيل حساب وتوليد الهوية</span>
                  </div>
                </div>
                <ArrowUpRight className="w-5 h-5 text-slate-500 group-hover:text-indigo-400 transition-colors" />
              </button>

              <button
                onClick={() => setShowAnnounceModal(true)}
                className="w-full flex items-center justify-between p-4 bg-gradient-to-l from-slate-800/80 to-slate-900/80 border border-slate-800 hover:border-violet-500/40 rounded-2xl text-white transition-all duration-300 group cursor-pointer"
              >
                <div className="flex items-center gap-3">
                  <div className="p-2.5 bg-violet-500/10 rounded-xl text-violet-400 border border-violet-500/20 group-hover:scale-110 transition-transform">
                    <Send className="w-5 h-5" />
                  </div>
                  <div className="text-right">
                    <span className="text-xs font-bold block text-slate-200">بث تعميم إداري</span>
                    <span className="text-[10px] text-slate-500 block">إعلان فوري في شريط الموبايل</span>
                  </div>
                </div>
                <ArrowUpRight className="w-5 h-5 text-slate-500 group-hover:text-violet-400 transition-colors" />
              </button>
            </div>
          </div>

          <div className="pt-6 border-t border-slate-800/60 mt-6">
            <div className="flex items-center justify-between text-xs text-slate-400">
              <span>آخر مزامنة قاعدة بيانات</span>
              <span className="font-mono text-teal-400">منذ دقيقة</span>
            </div>
          </div>
        </div>

      </div>

      {/* Absentees List By Branch Section */}
      <div id="absent-section" className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl scroll-mt-24">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-rose-500" />
              <span>قائمة غيابات اليوم (لم يسجلوا بصمة)</span>
            </h3>
            <p className="text-[11px] text-slate-400">قائمة بالموظفين الذين لم يسجلوا دخولهم اليوم وغير مجازين، مقسمة حسب الفروع</p>
          </div>
          <div className="px-3 py-1 bg-rose-500/10 border border-rose-500/20 text-rose-400 rounded-full text-[10px] font-bold">
            {stats.absentToday} غائب
          </div>
        </div>

        {absentList.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-10 bg-slate-950/30 rounded-2xl border border-slate-800/40">
            <CheckCircle className="w-12 h-12 text-emerald-500/40 mb-3" />
            <span className="text-sm font-bold text-slate-300">الجميع حاضرون!</span>
            <span className="text-xs text-slate-500">لا يوجد غيابات مسجلة لهذا اليوم.</span>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {branches.map(branch => {
              const branchAbsentees = absentList.filter(emp => emp.branch_id === branch.id);
              if (branchAbsentees.length === 0) return null;
              
              return (
                <div key={branch.id} className="bg-slate-950/50 border border-slate-800/60 rounded-2xl overflow-hidden flex flex-col">
                  <div className="bg-slate-900 px-4 py-3 border-b border-slate-800/60 flex justify-between items-center">
                    <span className="font-bold text-sm text-white flex items-center gap-2">
                      <MapPin className="w-4 h-4 text-blue-400" />
                      {branch.name}
                    </span>
                    <span className="bg-rose-500/20 text-rose-400 text-[10px] font-bold px-2 py-0.5 rounded-md">
                      {branchAbsentees.length} غائب
                    </span>
                  </div>
                  <div className="p-2 space-y-1 overflow-y-auto max-h-[250px] custom-scrollbar">
                    {branchAbsentees.map(emp => (
                      <div key={emp.id} className="px-3 py-2 bg-slate-900/30 rounded-lg border border-slate-800/30 flex items-center gap-3 hover:bg-slate-800/50 transition-colors">
                        <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center text-slate-400 border border-slate-700/50 shrink-0">
                          <Users className="w-4 h-4" />
                        </div>
                        <div className="min-w-0">
                          <p className="text-xs font-bold text-slate-200 truncate">{emp.full_name}</p>
                          <p className="text-[10px] text-slate-500">غير متواجد حالياً</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
            
            {/* For employees with no branch */}
            {absentList.filter(emp => !emp.branch_id).length > 0 && (
              <div className="bg-slate-950/50 border border-slate-800/60 rounded-2xl overflow-hidden flex flex-col">
                <div className="bg-slate-900 px-4 py-3 border-b border-slate-800/60 flex justify-between items-center">
                  <span className="font-bold text-sm text-white flex items-center gap-2">
                    <MapPin className="w-4 h-4 text-slate-400" />
                    غير محدد (بدون فرع)
                  </span>
                  <span className="bg-rose-500/20 text-rose-400 text-[10px] font-bold px-2 py-0.5 rounded-md">
                    {absentList.filter(emp => !emp.branch_id).length} غائب
                  </span>
                </div>
                <div className="p-2 space-y-1 overflow-y-auto max-h-[250px] custom-scrollbar">
                  {absentList.filter(emp => !emp.branch_id).map(emp => (
                    <div key={emp.id} className="px-3 py-2 bg-slate-900/30 rounded-lg border border-slate-800/30 flex items-center gap-3 hover:bg-slate-800/50 transition-colors">
                      <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center text-slate-400 border border-slate-700/50 shrink-0">
                        <Users className="w-4 h-4" />
                      </div>
                      <div className="min-w-0">
                        <p className="text-xs font-bold text-slate-200 truncate">{emp.full_name}</p>
                        <p className="text-[10px] text-slate-500">غير متواجد حالياً</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Announcement broadcast modal */}
      {showAnnounceModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
          <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 animate-glass text-right">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-blue-500 to-teal-500"></div>
            
            <h3 className="text-lg font-bold text-white mb-6 flex items-center gap-2">
              <span>بث تعميم وإعلان إداري هام 📢</span>
            </h3>
            
            <form onSubmit={handlePostAnnouncement} className="space-y-4">
              
              {/* Target Type Selector */}
              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold block text-right">المستلمون المستهدفون (نطاق الإرسال)</label>
                <select
                  value={targetType}
                  onChange={(e) => setTargetType(e.target.value as any)}
                  className="w-full bg-slate-950 border border-slate-850 text-white rounded-xl p-3 text-xs focus:border-blue-500 outline-none"
                >
                  <option value="all">📢 الكل (جميع موظفي الشركة)</option>
                  <option value="branch">🏢 موظفي فرع معين</option>
                  <option value="employee">👤 موظفين محددين (شخص أو أشخاص)</option>
                </select>
              </div>

              {/* Specific Branch Selector */}
              {targetType === 'branch' && (
                <div className="space-y-1.5 animate-glass">
                  <label className="text-xs text-slate-400 font-bold block text-right">اختر الفرع المستهدف</label>
                  <select
                    value={targetBranchId}
                    onChange={(e) => setTargetBranchId(e.target.value)}
                    required
                    className="w-full bg-slate-950 border border-slate-850 text-white rounded-xl p-3 text-xs focus:border-blue-500 outline-none"
                  >
                    <option value="">اختر الفرع...</option>
                    {branches.map(b => (
                      <option key={b.id} value={b.id}>{b.name}</option>
                    ))}
                  </select>
                </div>
              )}

              {/* Specific Employees Selector */}
              {targetType === 'employee' && (
                <div className="space-y-2 animate-glass">
                  <label className="text-xs text-slate-400 font-bold block text-right">اختر الموظفين المستهدفين ({targetEmployeeIds.length} محدد)</label>
                  
                  {/* Employee search filter */}
                  <input
                    type="text"
                    placeholder="ابحث باسم الموظف لتحديده..."
                    value={empSearchTerm}
                    onChange={(e) => setEmpSearchTerm(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-850 text-white rounded-xl px-3 py-2 text-xs focus:border-blue-500 outline-none"
                  />
                  
                  <div className="max-h-[160px] overflow-y-auto border border-slate-800 rounded-xl p-3 bg-slate-950/50 space-y-2 text-right" dir="rtl">
                    {employeesList
                      .filter(emp => emp && (emp.full_name || '').toLowerCase().includes(empSearchTerm.toLowerCase()))
                      .map(emp => {
                        const isChecked = targetEmployeeIds.includes(emp.id);
                        return (
                          <label key={emp.id} className="flex items-center gap-2.5 text-xs text-slate-300 cursor-pointer hover:text-white transition-colors">
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
                              className="rounded border-slate-800 text-blue-600 focus:ring-blue-500"
                            />
                            <span>{emp.full_name}</span>
                          </label>
                        );
                      })}
                  </div>
                </div>
              )}

              {/* Announcement Content */}
              <div className="space-y-1.5">
                <label className="text-xs text-slate-400 font-bold block text-right">نص التعميم الإداري</label>
                <textarea
                  value={announcement}
                  onChange={(e) => setAnnouncement(e.target.value)}
                  required
                  rows={4}
                  placeholder="اكتب الإعلان أو التعميم إداري هنا وسيصل الموظفون فوراً رنين إشعار متوهج على شاشاتهم..."
                  className="w-full bg-slate-950 border border-slate-850 rounded-2xl p-4 text-xs text-white placeholder-slate-500 focus:border-blue-500 outline-none resize-none"
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800/80">
                <button
                  type="button"
                  onClick={() => setShowAnnounceModal(false)}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-blue-500/20 cursor-pointer active:scale-95 flex items-center gap-1.5"
                >
                  {actionLoading ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>جاري إرسال التعميم...</span>
                    </>
                  ) : (
                    <span>بث التعميم المستهدف فوراً 🚀</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Add employee modal */}
      {showAddEmployeeModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
          <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-blue-500"></div>
            <h3 className="text-lg font-bold text-white mb-4">إضافة حساب موظف جديد لكادر الشركة 👤</h3>
            
            {actionError && (
              <div className="p-3 bg-rose-500/10 border border-rose-500/20 text-rose-300 rounded-xl text-xs mb-4">
                {actionError}
              </div>
            )}

            <form onSubmit={handleAddEmployee} className="space-y-4">
              <div>
                <label className="block text-xs text-slate-400 mb-1">الاسم الكامل للموظف الثلاثي</label>
                <input
                  type="text"
                  required
                  value={newEmpName}
                  onChange={(e) => setNewEmpName(e.target.value)}
                  placeholder="محمد علي حسين"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">البريد الإلكتروني للعمل</label>
                <input
                  type="email"
                  required
                  value={newEmpEmail}
                  onChange={(e) => setNewEmpEmail(e.target.value)}
                  placeholder="name@company.com"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">كلمة مرور الحساب الافتراضية</label>
                <input
                  type="password"
                  required
                  value={newEmpPassword}
                  onChange={(e) => setNewEmpPassword(e.target.value)}
                  placeholder="••••••••••••"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">رقم الهاتف للاتصال</label>
                <input
                  type="text"
                  value={newEmpPhone}
                  onChange={(e) => setNewEmpPhone(e.target.value)}
                  placeholder="077XXXXXXXX"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1">فرع العمل والموقع الجغرافي</label>
                  <select
                    value={newEmpBranch}
                    onChange={(e) => setNewEmpBranch(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
                  >
                    <option value="">-- اختر الفرع --</option>
                    {branches.map(b => (
                      <option key={b.id} value={b.id}>{b.name}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1">القسم الإداري للموظف</label>
                  <select
                    value={newEmpDept}
                    onChange={(e) => setNewEmpDept(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
                  >
                    <option value="">-- اختر القسم --</option>
                    {departments.map(d => (
                      <option key={d.id} value={d.id}>{d.name}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1">الدور الإداري والصلاحية</label>
                  <select
                    value={newEmpRole}
                    onChange={(e) => setNewEmpRole(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
                  >
                    <option value="employee">موظف (كادر اعتيادي)</option>
                    <option value="manager">مدير قسم / مدير موارد</option>
                    <option value="admin">مسؤول أدمن النظام كاملاً</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1">الراتب الشهري الأساسي (د.ع)</label>
                  <input
                    type="number"
                    required
                    value={newEmpSalary}
                    onChange={(e) => setNewEmpSalary(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-2">المستمسكات الثبوتية للموظف (اختياري)</label>
                <label className="flex flex-col items-center justify-center w-full h-32 border-2 border-slate-800 border-dashed rounded-xl cursor-pointer bg-slate-950 hover:bg-slate-900 transition-colors">
                  <div className="flex flex-col items-center justify-center pt-5 pb-6">
                    <Upload className="w-8 h-8 text-teal-500 mb-2" />
                    <p className="mb-2 text-xs text-slate-400">
                      <span className="font-semibold text-teal-400">اضغط لرفع الصور</span> أو اسحبها وأفلتها هنا
                    </p>
                    <p className="text-[10px] text-slate-500">يتم ضغط الصور تلقائياً (Max 1MB)</p>
                  </div>
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
                      <div key={idx} className="relative group bg-slate-900 border border-slate-700 rounded-lg p-1.5 flex items-center gap-2 pr-2">
                        <FileImage className="w-4 h-4 text-teal-500" />
                        <span className="text-[10px] text-slate-300 max-w-[100px] truncate" dir="ltr">{file.name}</span>
                        <button
                          type="button"
                          onClick={() => setNewDocuments(prev => prev.filter((_, i) => i !== idx))}
                          className="p-1 hover:bg-rose-500/20 text-rose-400 rounded-md transition-colors"
                        >
                          <X className="w-3 h-3" />
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="flex justify-end gap-3 pt-4">
                <button
                  type="button"
                  onClick={() => setShowAddEmployeeModal(false)}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-5 py-2.5 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/20 cursor-pointer"
                >
                  {actionLoading ? 'جاري إنشاء الحساب...' : 'إضافة الموظف الآن 👥'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
