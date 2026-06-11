'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { 
  Settings, 
  Building, 
  ShieldAlert, 
  Save, 
  Loader2, 
  MapPin, 
  Phone, 
  Mail, 
  Globe, 
  CreditCard,
  Clock,
  HardDrive,
  CalendarRange,
  Trash2,
  Plus,
  Megaphone,
  Trash
} from 'lucide-react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';

export default function SettingsPage() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  // Company Settings
  const [companyName, setCompanyName] = useState('مكتب بغداد الرئيسي للخرسانة');
  const [address, setAddress] = useState('العراق، بغداد، شارع الكرادة');
  const [phone, setPhone] = useState('+9647700000000');
  const [email, setEmail] = useState('info@batra-concrete.com');
  const [website, setWebsite] = useState('www.batra-concrete.com');
  const [taxNumber, setTaxNumber] = useState('100-244-555');
  const [logoUrl, setLogoUrl] = useState('');

  // System Settings
  const [trackingDays, setTrackingDays] = useState(180); // Default: 180 days
  const [cycleStartDay, setCycleStartDay] = useState(25);
  const [cycleEndDay, setCycleEndDay] = useState(24);

  // Leave Policy Settings
  const [defaultAnnual, setDefaultAnnual] = useState(21);
  const [defaultSick, setDefaultSick] = useState(15);
  const [leaveTypes, setLeaveTypes] = useState<any[]>([]);
  const [newLeaveTypeId, setNewLeaveTypeId] = useState('');
  const [newLeaveTypeName, setNewLeaveTypeName] = useState('');

  // Announcements Management Settings
  const [announcements, setAnnouncements] = useState<any[]>([]);
  const [loadingAnnouncements, setLoadingAnnouncements] = useState(false);

  // Work Schedules Settings
  const [workSchedules, setWorkSchedules] = useState<any[]>([]);
  const [branchesList, setBranchesList] = useState<any[]>([]);
  const [departmentsList, setDepartmentsList] = useState<any[]>([]);
  const [employeesList, setEmployeesList] = useState<any[]>([]);

  // Work Schedule form states
  const [schedName, setSchedName] = useState('');
  const [schedScope, setSchedScope] = useState<'branch' | 'department' | 'employee'>('branch');
  const [schedTargetId, setSchedTargetId] = useState('');
  const [schedCheckIn, setSchedCheckIn] = useState('09:00');
  const [schedCheckOut, setSchedCheckOut] = useState('17:00');
  const [schedGrace, setSchedGrace] = useState(15);
  const [schedWorkDays, setSchedWorkDays] = useState<number[]>([6, 0, 1, 2, 3, 4]); // Saturday to Thursday
  const [addingSchedule, setAddingSchedule] = useState(false);

  useEffect(() => {
    fetchSettings();
  }, []);

  const fetchAnnouncements = async () => {
    setLoadingAnnouncements(true);
    try {
      const { data, error } = await supabase
        .from('announcements')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      if (data) setAnnouncements(data);
    } catch (err) {
      console.error('Error fetching announcements:', err);
    } finally {
      setLoadingAnnouncements(false);
    }
  };

  const fetchSettings = async () => {
    setLoading(true);
    try {
      // Fetch all system settings, company info, announcements, branches, departments, work schedules, and active employees concurrently
      const [
        { data: comp },
        { data: sys },
        { data: pp },
        { data: lp },
        { data: ann },
        { data: wsData },
        { data: bData },
        { data: dData },
        { data: eData }
      ] = await Promise.all([
        supabase.from('company_settings').select('*').maybeSingle(),
        supabase.from('system_settings').select('*').eq('key', 'archive_policy').maybeSingle(),
        supabase.from('system_settings').select('*').eq('key', 'payroll_policy').maybeSingle(),
        supabase.from('system_settings').select('*').eq('key', 'leave_policy').maybeSingle(),
        supabase.from('announcements').select('*').order('created_at', { ascending: false }),
        supabase.from('work_schedules').select('*'),
        supabase.from('branches').select('id, name'),
        supabase.from('departments').select('id, name'),
        supabase.from('employees').select('id, full_name').eq('is_active', true).order('full_name')
      ]);

      if (comp) {
        setCompanyName(comp.name || '');
        setAddress(comp.address || '');
        setPhone(comp.phone || '');
        setEmail(comp.email || '');
        setWebsite(comp.website || '');
        setTaxNumber(comp.tax_number || '');
        setLogoUrl(comp.logo_url || '');
      }

      if (sys && sys.value) {
        setTrackingDays(sys.value.tracking_archive_days || 180);
      }

      if (pp && pp.value) {
        setCycleStartDay(pp.value.cycle_start_day || 25);
        setCycleEndDay(pp.value.cycle_end_day || 24);
      }

      if (lp && lp.value) {
        setDefaultAnnual(lp.value.default_annual || 21);
        setDefaultSick(lp.value.default_sick || 15);
        setLeaveTypes(lp.value.active_types || []);
      } else {
        // Fallback default leave types
        setLeaveTypes([
          { id: 'annual', name: 'إجازة سنوية' },
          { id: 'sick', name: 'إجازة مرضية' },
          { id: 'emergency', name: 'إجازة طارئة' },
          { id: 'maternity', name: 'إجازة أمومة' },
          { id: 'other', name: 'إجازة أخرى' }
        ]);
      }

      if (ann) {
        setAnnouncements(ann);
      }

      if (wsData) setWorkSchedules(wsData);
      if (bData) setBranchesList(bData || []);
      if (dData) setDepartmentsList(dData || []);
      if (eData) setEmployeesList(eData || []);

    } catch (err) {
      console.error('Error fetching settings:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleAddLeaveType = (e: React.MouseEvent) => {
    e.preventDefault();
    if (!newLeaveTypeId.trim() || !newLeaveTypeName.trim()) {
      toast.error('يرجى كتابة رمز ونوع الإجازة');
      return;
    }
    const cleanId = newLeaveTypeId.trim().toLowerCase().replace(/\s+/g, '_');
    if (leaveTypes.some(t => t.id === cleanId)) {
      toast('رمز الإجازة هذا موجود بالفعل');
      return;
    }
    setLeaveTypes([...leaveTypes, { id: cleanId, name: newLeaveTypeName.trim() }]);
    setNewLeaveTypeId('');
    setNewLeaveTypeName('');
  };

  const handleRemoveLeaveType = (idToRemove: string) => {
    if (['annual', 'sick'].includes(idToRemove)) {
      toast.error('لا يمكن حذف الإجازة السنوية أو المرضية الافتراضية لأنها مرتبطة بنظام الرواتب والأرصدة');
      return;
    }
    setLeaveTypes(leaveTypes.filter(t => t.id !== idToRemove));
  };

  const handleDeleteAnnouncement = async (id: string) => {
    if (!confirm('هل أنت متأكد من رغبتك في حذف هذا التعميم نهائياً من أرشيف لوحة الإعلانات؟ 🗑️')) return;
    try {
      const { error } = await supabase
        .from('announcements')
        .delete()
        .eq('id', id);
      if (error) throw error;
      
      toast.success('تم حذف التعميم بنجاح! ✅');
      fetchAnnouncements();
    } catch (err: any) {
      toast.error(`فشل حذف التعميم: ${err.message}`);
    }
  };

  const handlePurgeAnnouncements = async () => {
    if (!confirm('تحذير: هل أنت متأكد من رغبتك في مسح وإخلاء كافة التعميمات من الأرشيف؟ ⚠️ لا يمكن التراجع عن هذا الإجراء!')) return;
    try {
      const { error } = await supabase
        .from('announcements')
        .delete()
        .gt('created_at', '1970-01-01');
      if (error) throw error;
      
      toast.success('تم إخلاء أرشيف التعميمات بنجاح! 🧹');
      fetchAnnouncements();
    } catch (err: any) {
      toast.error(`فشل إخلاء الأرشيف: ${err.message}`);
    }
  };

  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      // 1. Get or create company settings row
      const { data: existingComp } = await supabase
        .from('company_settings')
        .select('id')
        .maybeSingle();

      const companyData = {
        name: companyName,
        address,
        phone,
        email,
        website,
        tax_number: taxNumber,
        logo_url: logoUrl,
        updated_at: new Date().toISOString()
      };

      if (existingComp) {
        const { error } = await supabase
          .from('company_settings')
          .update(companyData)
          .eq('id', existingComp.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('company_settings')
          .insert(companyData);
        if (error) throw error;
      }

      // 2. Save system settings (archive_policy)
      const { data: existingSys } = await supabase
        .from('system_settings')
        .select('key')
        .eq('key', 'archive_policy')
        .maybeSingle();

      const systemData = {
        key: 'archive_policy',
        value: { tracking_archive_days: Number(trackingDays) },
        description: 'إعدادات أرشفة بيانات تتبع الحضور والمواقع وسلة المحذوفات تلقائياً'
      };

      if (existingSys) {
        const { error } = await supabase
          .from('system_settings')
          .update(systemData)
          .eq('key', 'archive_policy');
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('system_settings')
          .insert(systemData);
        if (error) throw error;
      }

      // 3. Save system settings (leave_policy)
      const { data: existingLP } = await supabase
        .from('system_settings')
        .select('key')
        .eq('key', 'leave_policy')
        .maybeSingle();

      const leavePolicyData = {
        key: 'leave_policy',
        value: { 
          default_annual: Number(defaultAnnual), 
          default_sick: Number(defaultSick), 
          active_types: leaveTypes 
        },
        description: 'سياسة الإجازات العامة وأنواعها المتاحة بالشركة'
      };

      if (existingLP) {
        const { error } = await supabase
          .from('system_settings')
          .update(leavePolicyData)
          .eq('key', 'leave_policy');
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('system_settings')
          .insert(leavePolicyData);
        if (error) throw error;
      }

      // 4. Save system settings (payroll_policy)
      const { data: existingPP } = await supabase
        .from('system_settings')
        .select('key')
        .eq('key', 'payroll_policy')
        .maybeSingle();

      const payrollPolicyData = {
        key: 'payroll_policy',
        value: { 
          cycle_start_day: Number(cycleStartDay), 
          cycle_end_day: Number(cycleEndDay) 
        },
        description: 'إعدادات تحديد دورة الحسابات المالية والرواتب الشهرية'
      };

      if (existingPP) {
        const { error } = await supabase
          .from('system_settings')
          .update(payrollPolicyData)
          .eq('key', 'payroll_policy');
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('system_settings')
          .insert(payrollPolicyData);
        if (error) throw error;
      }

      confetti({
        particleCount: 80,
        spread: 60,
        colors: ['#0D9488', '#10B981']
      });
      toast.success('تم حفظ وتحديث إعدادات النظام والشركة بنجاح! ✅');
      
      // Update app state
      fetchSettings();
    } catch (err: any) {
      toast.error(`فشل حفظ الإعدادات: ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  const getDayNameAr = (dayNum: number) => {
    const days: Record<number, string> = {
      0: 'الأحد',
      1: 'الاثنين',
      2: 'الثلاثاء',
      3: 'الأربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت'
    };
    return days[dayNum] || '';
  };

  const getScheduleTargetName = (sched: any) => {
    if (sched.employee_id) {
      const emp = employeesList.find(e => e.id === sched.employee_id);
      return `👤 موظف: ${emp ? emp.full_name : 'غير معروف'}`;
    }
    if (sched.department_id) {
      const dept = departmentsList.find(d => d.id === sched.department_id);
      return `🏢 قسم: ${dept ? dept.name : 'غير معروف'}`;
    }
    if (sched.branch_id) {
      const branch = branchesList.find(b => b.id === sched.branch_id);
      return `📍 فرع: ${branch ? branch.name : 'غير معروف'}`;
    }
    return 'عام';
  };

  const handleAddSchedule = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!schedName.trim()) {
      toast.error('يرجى إدخال اسم لجدول الدوام');
      return;
    }
    if (!schedTargetId) {
      toast.error('يرجى تحديد الجهة المستهدفة (الفرع/القسم/الموظف)');
      return;
    }
    setAddingSchedule(true);
    try {
      const scheduleData: any = {
        name: schedName.trim(),
        check_in_time: schedCheckIn + ':00',
        check_out_time: schedCheckOut + ':00',
        grace_period_minutes: Number(schedGrace),
        work_days: schedWorkDays,
      };

      if (schedScope === 'branch') {
        scheduleData.branch_id = schedTargetId;
      } else if (schedScope === 'department') {
        scheduleData.department_id = schedTargetId;
      } else if (schedScope === 'employee') {
        scheduleData.employee_id = schedTargetId;
      }

      const { error } = await supabase.from('work_schedules').insert(scheduleData);
      if (error) throw error;

      toast.success('تم إضافة جدول الدوام بنجاح! 📅');
      setSchedName('');
      setSchedTargetId('');
      setSchedCheckIn('09:00');
      setSchedCheckOut('17:00');
      setSchedGrace(15);
      setSchedWorkDays([6, 0, 1, 2, 3, 4]);

      // Refresh settings
      fetchSettings();
    } catch (err: any) {
      toast.error(`فشل إضافة الجدول: ${err.message}`);
    } finally {
      setAddingSchedule(false);
    }
  };

  const handleDeleteSchedule = async (id: string) => {
    if (!confirm('هل أنت متأكد من رغبتك في حذف جدول الدوام هذا؟ 🗑️')) return;
    try {
      const { error } = await supabase
        .from('work_schedules')
        .delete()
        .eq('id', id);
      if (error) throw error;

      toast.success('تم حذف جدول الدوام بنجاح! ✅');
      fetchSettings();
    } catch (err: any) {
      toast.error(`فشل حذف الجدول: ${err.message}`);
    }
  };

  const handleDayToggle = (day: number) => {
    if (schedWorkDays.includes(day)) {
      setSchedWorkDays(schedWorkDays.filter(d => d !== day));
    } else {
      setSchedWorkDays([...schedWorkDays, day].sort());
    }
  };

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      {/* Header */}
      <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h3 className="text-xl font-extrabold text-white flex items-center gap-2 mb-2">
            <Settings className="w-6 h-6 text-teal-400 animate-spin-slow" />
            <span>إعدادات النظام والشركة العامة</span>
          </h3>
          <p className="text-xs text-slate-400">تحديث وتعديل بيانات ومحددات الشركة، وسياسات أرشفة التتبع والملفات</p>
        </div>
      </div>

      <form onSubmit={handleSaveSettings} className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* Left Side: Company Profile info */}
        <div className="lg:col-span-2 space-y-6">
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
            <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850">
              <Building className="w-5 h-5" />
              <h4 className="text-sm font-extrabold text-white">بيانات الشركة الرسمية والترويجية</h4>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                  <span>اسم الشركة / المؤسسة الرسمي</span>
                </label>
                <input
                  type="text"
                  required
                  value={companyName}
                  onChange={(e) => setCompanyName(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                  <span>العنوان والفرع الرئيسي للشركة</span>
                </label>
                <input
                  type="text"
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-mono">
                  <Phone className="w-3.5 h-3.5" />
                  <span>رقم الهاتف المعتمد</span>
                </label>
                <input
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-mono">
                  <Mail className="w-3.5 h-3.5" />
                  <span>البريد الإلكتروني المعتمد للشركة</span>
                </label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                  dir="ltr"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-mono">
                  <Globe className="w-3.5 h-3.5" />
                  <span>الموقع الإلكتروني الرسمي (إن وجد)</span>
                </label>
                <input
                  type="text"
                  value={website}
                  onChange={(e) => setWebsite(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                  <CreditCard className="w-3.5 h-3.5" />
                  <span>الرقم أو الملف الضريبي (اختياري)</span>
                </label>
                <input
                  type="text"
                  value={taxNumber}
                  onChange={(e) => setTaxNumber(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                  dir="ltr"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1">شعار الشركة (رابط الصورة / Logo URL)</label>
              <input
                type="text"
                placeholder="https://example.com/logo.png"
                value={logoUrl}
                onChange={(e) => setLogoUrl(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left font-mono"
                dir="ltr"
              />
            </div>
          </div>

          {/* Leave Policy Settings Card */}
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
            <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850">
              <CalendarRange className="w-5 h-5" />
              <h4 className="text-sm font-extrabold text-white">إعدادات سياسات وأرصدة الإجازات العامة</h4>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-xs text-slate-400 mb-1 font-bold">
                  <span>رصيد الإجازات السنوية الافتراضي (للموظفين الجدد)</span>
                </label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    required
                    value={defaultAnnual}
                    onChange={(e) => setDefaultAnnual(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
                    dir="ltr"
                  />
                  <span className="bg-slate-800 border border-slate-700 px-4 py-3 rounded-xl text-xs text-slate-300 font-bold flex items-center">يوم/سنة</span>
                </div>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 font-bold">
                  <span>رصيد الإجازات المرضية الافتراضي (للموظفين الجدد)</span>
                </label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    required
                    value={defaultSick}
                    onChange={(e) => setDefaultSick(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
                    dir="ltr"
                  />
                  <span className="bg-slate-800 border border-slate-700 px-4 py-3 rounded-xl text-xs text-slate-300 font-bold flex items-center">يوم/سنة</span>
                </div>
              </div>
            </div>

            <div className="space-y-4">
              <h5 className="text-xs font-bold text-slate-300">أنواع الإجازات المتاحة وتصنيفاتها:</h5>
              
              <div className="flex flex-wrap gap-2.5 p-4 bg-slate-950/40 border border-slate-850 rounded-2xl">
                {leaveTypes.length === 0 ? (
                  <span className="text-xs text-slate-500">لا توجد أنواع إجازات مضافة</span>
                ) : (
                  leaveTypes.map((type) => (
                    <div 
                      key={type.id} 
                      className="flex items-center gap-2 px-3 py-1.5 bg-slate-900 border border-slate-800 hover:border-slate-700 text-xs text-slate-200 rounded-xl transition-all"
                    >
                      <span className="font-bold">{type.name}</span>
                      <span className="text-[10px] text-slate-500 font-mono">({type.id})</span>
                      {!['annual', 'sick'].includes(type.id) && (
                        <button
                          type="button"
                          onClick={() => handleRemoveLeaveType(type.id)}
                          className="text-slate-500 hover:text-rose-400 transition-colors p-0.5 rounded cursor-pointer"
                          title="حذف هذا النوع"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </div>
                  ))
                )}
              </div>

              {/* Add leave type form */}
              <div className="bg-slate-950/20 border border-slate-850 p-4 rounded-2xl space-y-4">
                <span className="text-[11px] font-bold text-slate-400 block">إضافة نوع إجازة مخصص جديد:</span>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 items-end">
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">اسم الإجازة بالعربية</label>
                    <input
                      type="text"
                      placeholder="مثال: إجازة زواج"
                      value={newLeaveTypeName}
                      onChange={(e) => setNewLeaveTypeName(e.target.value)}
                      className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">رمز فريد للإجازة (بالإنجليزي)</label>
                    <input
                      type="text"
                      placeholder="مثال: marriage_leave"
                      value={newLeaveTypeId}
                      onChange={(e) => setNewLeaveTypeId(e.target.value)}
                      className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono"
                      dir="ltr"
                    />
                  </div>
                  <button
                    type="button"
                    onClick={handleAddLeaveType}
                    className="flex items-center justify-center gap-1.5 py-2.5 px-4 bg-teal-650/20 hover:bg-teal-650/40 border border-teal-500/30 text-teal-400 rounded-xl text-xs font-bold transition-all cursor-pointer"
                  >
                    <Plus className="w-4 h-4" />
                    <span>أضف للقائمة</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Right Side: System Settings and Policy */}
        <div className="space-y-6">
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
            <div className="flex items-center gap-2 text-amber-400 pb-3 border-b border-slate-850">
              <ShieldAlert className="w-5 h-5" />
              <h4 className="text-sm font-extrabold text-white">سياسة الأرشفة والتتبع الجغرافي</h4>
            </div>

            <div className="space-y-4">
              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-bold">
                  <Clock className="w-4 h-4 text-amber-400" />
                  <span>فترة الاحتفاظ ببيانات التتبع والموقع</span>
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    required
                    value={trackingDays}
                    onChange={(e) => setTrackingDays(Number(e.target.value.replace(/\D/g, '')))}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
                    dir="ltr"
                  />
                  <span className="bg-slate-800 border border-slate-700 px-4 py-3 rounded-xl text-xs text-slate-300 font-bold whitespace-nowrap flex items-center">يوم</span>
                </div>
                <p className="text-[10px] text-slate-500 mt-2 leading-relaxed">
                  سيقوم النظام أوتوماتيكياً بمسح وتصفية إحداثيات ومواقع تتبع الموظفين ومخالفات السياج الجغرافي القديمة التي تتخطى هذه الفترة لضمان سرعة السيرفرات وتنظيف المساحة.
                </p>
              </div>

              <div className="p-4 bg-teal-950/10 border border-teal-500/20 rounded-2xl space-y-2">
                <div className="flex items-center gap-1 text-[10px] text-teal-400 font-bold">
                  <HardDrive className="w-3.5 h-3.5" />
                  <span>سلة المحذوفات للمستندات</span>
                </div>
                <p className="text-[9px] text-slate-400 leading-relaxed">
                  نظام الأمان والملفات يضمن حفظ مستندات الموظفين وسجلات وتعهدات السلف المحذوفة لمدة **30 يوماً** تلقائياً في سلة المحذوفات قبل تصفيتها بشكل نهائي.
                </p>
              </div>
            </div>
          </div>

          {/* Payroll Policy Settings Card */}
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
            <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850">
              <CalendarRange className="w-5 h-5 text-teal-400" />
              <h4 className="text-sm font-extrabold text-white">إعدادات الدورة المالية للرواتب 💸</h4>
            </div>

            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[10px] text-slate-400 mb-1 font-bold">
                    يوم بداية الدورة
                  </label>
                  <input
                    type="number"
                    required
                    min={1}
                    max={31}
                    value={cycleStartDay}
                    onChange={(e) => setCycleStartDay(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white text-center font-bold outline-none"
                  />
                </div>
                <div>
                  <label className="block text-[10px] text-slate-400 mb-1 font-bold">
                    يوم نهاية الدورة
                  </label>
                  <input
                    type="number"
                    required
                    min={1}
                    max={31}
                    value={cycleEndDay}
                    onChange={(e) => setCycleEndDay(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white text-center font-bold outline-none"
                  />
                </div>
              </div>
              <p className="text-[10px] text-slate-505 leading-relaxed text-slate-500">
                حدد يوم البداية ويوم النهاية للشهر المالي. افتراضياً، تبدأ الدورة يوم 25 من الشهر السابق وتنتهي يوم 24 من الشهر الجاري.
              </p>
            </div>
          </div>

          {/* Submit button card */}
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl">
            <button
              type="submit"
              disabled={saving}
              className="w-full flex items-center justify-center gap-2 py-3.5 px-4 bg-gradient-to-l from-teal-650 to-teal-500 hover:from-teal-600 hover:to-teal-400 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 active:scale-95 cursor-pointer"
            >
              {saving ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>جاري التحديث والحفظ...</span>
                </>
              ) : (
                <>
                  <Save className="w-4 h-4" />
                  <span>حفظ إعدادات النظام والشركة 💾</span>
                </>
              )}
            </button>
          </div>
        </div>

      </form>

      {/* Work Schedules Management Section */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 mt-8">
        <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850 font-bold">
          <Clock className="w-5 h-5 text-teal-400" />
          <h4 className="text-sm font-extrabold text-white">إدارة جداول وأوقات العمل بالفروع والأقسام والموظفين 📅</h4>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Add Work Schedule Form */}
          <div className="lg:col-span-1 bg-slate-950/40 border border-slate-850 p-6 rounded-2xl space-y-4 text-right" dir="rtl">
            <h5 className="text-xs font-bold text-teal-400 mb-2">إضافة جدول دوام جديد:</h5>
            <form onSubmit={handleAddSchedule} className="space-y-4">
              <div>
                <label className="block text-[10px] text-slate-400 mb-1">اسم جدول الدوام</label>
                <input
                  type="text"
                  required
                  placeholder="مثال: دوام فرع بغداد المعتاد"
                  value={schedName}
                  onChange={(e) => setSchedName(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none"
                />
              </div>

              <div>
                <label className="block text-[10px] text-slate-400 mb-1">نطاق تطبيق الجدول</label>
                <select
                  value={schedScope}
                  onChange={(e) => {
                    setSchedScope(e.target.value as any);
                    setSchedTargetId('');
                  }}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none"
                >
                  <option value="branch">🏢 تحديد حسب الفرع الجغرافي</option>
                  <option value="department">📂 تحديد حسب القسم الإداري</option>
                  <option value="employee">👤 تحديد لموظف معين بشكل مخصص</option>
                </select>
              </div>

              <div>
                <label className="block text-[10px] text-slate-400 mb-1 font-bold">الجهة المستهدفة بالفرع أو القسم</label>
                <select
                  required
                  value={schedTargetId}
                  onChange={(e) => setSchedTargetId(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none font-bold"
                >
                  <option value="">-- اختر الجهة المحددة --</option>
                  {schedScope === 'branch' && branchesList.map(b => (
                    <option key={b.id} value={b.id}>{b.name}</option>
                  ))}
                  {schedScope === 'department' && departmentsList.map(d => (
                    <option key={d.id} value={d.id}>{d.name}</option>
                  ))}
                  {schedScope === 'employee' && employeesList.map(e => (
                    <option key={e.id} value={e.id}>{e.full_name}</option>
                  ))}
                </select>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[10px] text-slate-400 mb-1">وقت الدخول المعتمد</label>
                  <input
                    type="time"
                    required
                    value={schedCheckIn}
                    onChange={(e) => setSchedCheckIn(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono"
                    dir="ltr"
                  />
                </div>
                <div>
                  <label className="block text-[10px] text-slate-400 mb-1">وقت الخروج المعتمد</label>
                  <input
                    type="time"
                    required
                    value={schedCheckOut}
                    onChange={(e) => setSchedCheckOut(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono"
                    dir="ltr"
                  />
                </div>
              </div>

              <div>
                <label className="block text-[10px] text-slate-400 mb-1">فترة السماح للتأخير بالدقائق</label>
                <input
                  type="number"
                  required
                  min={0}
                  value={schedGrace}
                  onChange={(e) => setSchedGrace(Number(e.target.value))}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono font-bold"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-[10px] text-slate-400 mb-2 font-bold">أيام العمل الأسبوعية النشطة</label>
                <div className="grid grid-cols-3 gap-2 text-right">
                  {[
                    { value: 6, label: 'السبت' },
                    { value: 0, label: 'الأحد' },
                    { value: 1, label: 'الاثنين' },
                    { value: 2, label: 'الثلاثاء' },
                    { value: 3, label: 'الأربعاء' },
                    { value: 4, label: 'الخميس' },
                    { value: 5, label: 'الجمعة' }
                  ].map(day => {
                    const isChecked = schedWorkDays.includes(day.value);
                    return (
                      <label key={day.value} className="flex items-center gap-1.5 text-[10px] text-slate-300 cursor-pointer hover:text-white transition-colors">
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={() => handleDayToggle(day.value)}
                          className="rounded border-slate-850 text-teal-600 focus:ring-teal-500 w-3.5 h-3.5"
                        />
                        <span>{day.label}</span>
                      </label>
                    );
                  })}
                </div>
              </div>

              <button
                type="submit"
                disabled={addingSchedule}
                className="w-full flex items-center justify-center gap-1.5 py-2.5 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer"
              >
                {addingSchedule ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>حفظ جدول الدوام 💾</span>}
              </button>
            </form>
          </div>

          {/* Active Work Schedules List */}
          <div className="lg:col-span-2 space-y-4 text-right">
            <h5 className="text-xs font-bold text-slate-300 mb-2">جداول الدوام المسجلة بالنظام:</h5>
            {workSchedules.length === 0 ? (
              <div className="text-center p-8 bg-slate-950/20 border border-slate-850 rounded-2xl text-slate-500 text-xs">
                لا توجد أي جداول دوام مضافة بالنظام حالياً. سيقوم النظام باعتماد الدوام المعتاد (السبت-الخميس من 9ص إلى 5م).
              </div>
            ) : (
              <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
                <table className="w-full text-right border-collapse">
                  <thead>
                    <tr className="bg-slate-950/80 text-slate-300 text-[10px] font-bold border-b border-slate-800/80">
                      <th className="p-3">اسم الجدول</th>
                      <th className="p-3">الجهة المطبقة</th>
                      <th className="p-3">الأوقات المعتمدة</th>
                      <th className="p-3">أيام الدوام</th>
                      <th className="p-3 text-left">الإجراءات</th>
                    </tr>
                  </thead>
                  <tbody>
                    {workSchedules.map((ws) => (
                      <tr key={ws.id} className="border-b border-slate-800/40 hover:bg-slate-900/20 text-xs transition-colors">
                        <td className="p-3 font-bold text-white">{ws.name}</td>
                        <td className="p-3 text-slate-300 font-medium">
                          {getScheduleTargetName(ws)}
                        </td>
                        <td className="p-3 font-mono text-[10px] text-teal-400">
                          {formatTime12h(ws.check_in_time)} - {formatTime12h(ws.check_out_time)}
                          <span className="text-slate-500 text-[9px] block">سماح: {ws.grace_period_minutes} دقيقة</span>
                        </td>
                        <td className="p-3 max-w-[150px] truncate" title={(ws.work_days || []).map((d: number) => getDayNameAr(d)).join('، ')}>
                          <span className="text-[10px] text-slate-450">
                            {(ws.work_days || []).map((d: number) => getDayNameAr(d)).join('، ')}
                          </span>
                        </td>
                        <td className="p-3 text-left">
                          <button
                            type="button"
                            onClick={() => handleDeleteSchedule(ws.id)}
                            className="p-2 bg-slate-850 hover:bg-rose-500/10 hover:text-rose-400 border border-slate-800 hover:border-rose-500/20 text-slate-400 rounded-xl transition-all cursor-pointer"
                            title="حذف الجدول"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Announcements Management Section */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 mt-8">
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-3 border-b border-slate-850">
          <div className="flex items-center gap-2 text-teal-400">
            <Megaphone className="w-5 h-5" />
            <h4 className="text-sm font-extrabold text-white">أرشيف وإدارة التعاميم والإعلانات الإدارية</h4>
          </div>
          
          {announcements.length > 0 && (
            <button
              type="button"
              onClick={handlePurgeAnnouncements}
              className="flex items-center justify-center gap-1.5 py-2 px-4 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 text-rose-450 rounded-xl text-xs font-bold transition-all cursor-pointer"
            >
              <Trash className="w-4 h-4" />
              <span>إخلاء الأرشيف بالكامل 🧹</span>
            </button>
          )}
        </div>

        {loadingAnnouncements ? (
          <div className="flex justify-center p-6">
            <Loader2 className="w-6 h-6 text-teal-400 animate-spin" />
          </div>
        ) : announcements.length === 0 ? (
          <div className="text-center p-8 text-slate-500 text-xs">
            لا توجد أي تعاميم إدارية في الأرشيف حالياً
          </div>
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
            <table className="w-full text-right border-collapse">
              <thead>
                <tr className="bg-slate-950/80 text-slate-300 text-xs font-bold border-b border-slate-800/80">
                  <th className="p-3">تاريخ النشر</th>
                  <th className="p-3">عنوان الإعلان</th>
                  <th className="p-3">محتوى التعميم</th>
                  <th className="p-3 text-left">الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {announcements.map((ann) => (
                  <tr key={ann.id} className="border-b border-slate-800/40 hover:bg-slate-900/20 text-xs transition-colors">
                    <td className="p-3 text-slate-400 font-mono">
                      {new Date(ann.created_at).toLocaleDateString('ar-IQ', {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit'
                      })}
                    </td>
                    <td className="p-3 font-bold text-white">
                      <div className="flex items-center gap-1.5">
                        <span>{ann.title}</span>
                        {ann.is_pinned && (
                          <span className="px-1.5 py-0.5 bg-teal-500/10 text-teal-400 border border-teal-500/15 rounded text-[8px] font-bold">مثبت</span>
                        )}
                      </div>
                    </td>
                    <td className="p-3 text-slate-350 max-w-sm truncate" title={ann.content}>
                      {ann.content}
                    </td>
                    <td className="p-3 text-left">
                      <button
                        type="button"
                        onClick={() => handleDeleteAnnouncement(ann.id)}
                        className="p-2 bg-slate-850 hover:bg-rose-500/10 hover:text-rose-400 border border-slate-800 hover:border-rose-500/20 text-slate-400 rounded-xl transition-all cursor-pointer"
                        title="حذف التعميم نهائياً"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

const formatTime12h = (timeStr: string | null | undefined): string => {
  if (!timeStr) return '--:--';
  try {
    const parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;
    let hour = parseInt(parts[0], 10);
    const minute = parseInt(parts[1], 10);
    const period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour === 0) hour = 12;
    const minuteStr = minute.toString().padStart(2, '0');
    return `${hour}:${minuteStr} ${period}`;
  } catch (e) {
    return timeStr;
  }
};
