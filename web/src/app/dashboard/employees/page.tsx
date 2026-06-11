'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import imageCompression from 'browser-image-compression';
import { 
  Users, 
  Search, 
  Smartphone, 
  Lock, 
  Unlock, 
  Check, 
  X, 
  AlertCircle,
  TrendingUp,
  Loader2,
  Trash2,
  Plus,
  Edit,
  Building,
  Briefcase,
  DollarSign,
  Phone,
  Mail,
  Upload,
  FileImage
} from 'lucide-react';
import confetti from 'canvas-confetti';

export default function EmployeesPage() {
  const [loading, setLoading] = useState(true);
  const [employees, setEmployees] = useState<any[]>([]);
  const [deviceRequests, setDeviceRequests] = useState<any[]>([]);
  const [branches, setBranches] = useState<any[]>([]);
  const [departments, setDepartments] = useState<any[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedDirectoryBranch, setSelectedDirectoryBranch] = useState('all');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Modal States
  const [showAddModal, setShowAddModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedEmployee, setSelectedEmployee] = useState<any>(null);

  // Archives & Deletions States
  const [activeTab, setActiveTab] = useState<'active' | 'archived'>('active');
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [employeeToDelete, setEmployeeToDelete] = useState<any>(null);
  const [deleteReason, setDeleteReason] = useState('');
  const [deleteType, setDeleteType] = useState<'immediate' | 'archive' | 'scheduled'>('archive');
  const [archivedEmployees, setArchivedEmployees] = useState<any[]>([]);

  // Form Fields
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState('employee');
  const [branchId, setBranchId] = useState('');
  const [monthlySalary, setMonthlySalary] = useState<number>(0);
  const [futureSalary, setFutureSalary] = useState<number>(0);
  const [futureSalaryMonth, setFutureSalaryMonth] = useState('');
  
  // Documents
  const [newDocuments, setNewDocuments] = useState<File[]>([]);
  const [existingDocuments, setExistingDocuments] = useState<string[]>([]);

  useEffect(() => {
    // 1. Try to load cached employees data instantly to avoid blank page or spinners
    const cachedData = localStorage.getItem('batra_cache_employees');
    if (cachedData) {
      try {
        const parsed = JSON.parse(cachedData);
        setEmployees(parsed.employees || []);
        setDeviceRequests(parsed.deviceRequests || []);
        setBranches(parsed.branches || []);
        setArchivedEmployees(parsed.archivedEmployees || []);
        setLoading(false); // Render page immediately!
      } catch (e) {
        console.error('Error parsing employees cache:', e);
      }
    }

    // 2. Fetch fresh data silently in the background
    fetchEmployeesData(!!cachedData);
    fetchArchivedEmployees();
  }, []);

  const fetchEmployeesData = async (hasCache = false) => {
    if (!hasCache) {
      setLoading(true);
    }
    try {
      // Fetch employees, device requests, and branches concurrently using Promise.all
      const [
        { data: emps, error: empsErr },
        { data: reqs, error: reqsErr },
        { data: brs }
      ] = await Promise.all([
        supabase
          .from('employees')
          .select('*, branches(name)')
          .order('full_name', { ascending: true }),
        supabase
          .from('employee_devices')
          .select('*, employees(full_name)')
          .eq('is_approved', false),
        supabase
          .from('branches')
          .select('id, name')
          .order('name')
      ]);

      if (emps) setEmployees(emps);
      if (reqs) setDeviceRequests(reqs);
      if (brs) setBranches(brs);

      // Cache all details for subsequent loads
      const currentArchive = localStorage.getItem('batra_cache_employees');
      let arch = [];
      if (currentArchive) {
        try { arch = JSON.parse(currentArchive).archivedEmployees || []; } catch (e) {}
      }

      localStorage.setItem('batra_cache_employees', JSON.stringify({
        employees: emps || [],
        deviceRequests: reqs || [],
        branches: brs || [],
        archivedEmployees: arch
      }));

    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleToggleDeviceLock = async (empId: string, currentLock: string | null) => {
    setActionLoading(empId);
    try {
      const newLockValue = currentLock ? null : 'force_lock_active';
      const { error } = await supabase
        .from('employees')
        .update({ device_id_lock: newLockValue })
        .eq('id', empId);

      if (error) throw error;

      // Update state locally
      setEmployees(prev => prev.map(emp => {
        if (emp.id === empId) {
          return { ...emp, device_id_lock: newLockValue };
        }
        return emp;
      }));

      confetti({
        particleCount: 50,
        spread: 40,
        colors: ['#0D9488', '#10B981']
      });
    } catch (err) {
      alert('فشل تغيير قفل الجهاز');
    } finally {
      setActionLoading(null);
    }
  };

  const handleResetDeviceBinding = async (empId: string) => {
    if (!confirm('هل تريد فعلاً إلغاء ربط هاتف هذا الموظف بالكامل؟ سيمكنه هذا من تسجيل الدخول من أي هاتف جديد.')) return;
    setActionLoading(empId + '_reset');
    try {
      // 1. مسح تسجيلات الجهاز القديمة
      const { error: delError } = await supabase
        .from('employee_devices')
        .delete()
        .eq('employee_id', empId);

      if (delError) throw delError;

      // 2. تفعيل قفل الدخول للجهاز الجديد القادم
      const { error: updError } = await supabase
        .from('employees')
        .update({ device_id_lock: 'force_lock_active' })
        .eq('id', empId);

      if (updError) throw updError;

      setEmployees(prev => prev.map(emp => {
        if (emp.id === empId) {
          return { ...emp, device_id_lock: 'force_lock_active' };
        }
        return emp;
      }));

      alert('تم فك قفل وربط هاتف الموظف بنجاح ✅');
    } catch (err) {
      alert('فشل فك ربط الهاتف');
    } finally {
      setActionLoading(null);
    }
  };

  const handleProcessDeviceRequest = async (requestId: string, employeeId: string, approve: boolean) => {
    setActionLoading(requestId);
    try {
      if (approve) {
        // Approve device binding
        const { error: updErr } = await supabase
          .from('employee_devices')
          .update({
            is_approved: true,
            approved_at: new Date().toISOString(),
          })
          .eq('id', requestId);

        if (updErr) throw updErr;

        // Fetch device details to bind as locked id
        const { data: dev } = await supabase
          .from('employee_devices')
          .select('device_id')
          .eq('id', requestId)
          .single();

        if (dev) {
          await supabase
            .from('employees')
            .update({ device_id_lock: dev.device_id })
            .eq('id', employeeId);
        }

        // Notify employee
        await supabase.from('notifications').insert({
          employee_id: employeeId,
          title: 'اعتماد جهاز الدخول الجديد 📱',
          body: 'تهانينا! تمت موافقة الإدارة على اعتماد هاتف تسجيل دخولك الجديد.',
          type: 'device',
        });
      } else {
        // Reject and delete request
        await supabase
          .from('employee_devices')
          .delete()
          .eq('id', requestId);
      }

      // Refresh
      await fetchEmployeesData();
      
      confetti({
        particleCount: 70,
        spread: 50,
      });
      alert(approve ? 'تم اعتماد وتثبيت الجهاز بنجاح! ✅' : 'تم رفض وإزالة طلب ربط الجهاز. ❌');
    } catch (err: any) {
      alert(`فشل إتمام العملية: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  // Create new employee auth & profile without logging out active admin
  const handleCreateEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!password || password.length < 6) {
      alert('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }
    setActionLoading('create_emp');
    try {
      // 1. Create a non-persisted client to avoid logging out the current admin
      const { createClient } = await import('@supabase/supabase-js');
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://jgjlmddphhncatrhqrej.supabase.co';
      const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_EjrPBiypg0kR-HMDk0uitw_y1aHc7kP';
      
      const tempClient = createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false
        }
      });

      // 2. Sign up the new user
      const { data: signUpData, error: signUpErr } = await tempClient.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: fullName,
          }
        }
      });

      if (signUpErr) throw signUpErr;
      if (!signUpData.user) throw new Error('فشل إنشاء حساب الموظف في المصادقة');

      const empCode = `EMP-${Math.floor(100 + Math.random() * 900)}`;

      // 3. Compress and upload documents
      let uploadedUrls: string[] = [];
      if (newDocuments.length > 0) {
        for (const file of newDocuments) {
          try {
            const compressedFile = await imageCompression(file, {
              maxSizeMB: 1,
              maxWidthOrHeight: 1920,
              useWebWorker: true,
            });
            const fileExt = file.name.split('.').pop();
            const fileName = `${signUpData.user.id}/${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;
            
            const { error: uploadError } = await supabase.storage.from('documents').upload(fileName, compressedFile);
            if (!uploadError) {
              const { data: { publicUrl } } = supabase.storage
                .from('documents')
                .getPublicUrl(fileName);
              uploadedUrls.push(publicUrl);
            }
          } catch (err) {
            console.error('Failed to compress/upload file:', err);
          }
        }
      }

      // 4. Insert employee profile in employees table
      const { error: insErr } = await supabase.from('employees').insert({
        id: signUpData.user.id,
        employee_code: empCode,
        full_name: fullName,
        email,
        phone: phone || null,
        role,
        branch_id: branchId || null,
        monthly_salary_iqd: monthlySalary || 0,
        plain_password: password,
        is_active: true,
        must_change_password: true,
        document_urls: uploadedUrls
      });

      if (insErr) {
        throw insErr;
      }

      // Reset states
      setFullName('');
      setEmail('');
      setPhone('');
      setPassword('');
      setRole('employee');
      setBranchId('');
      setMonthlySalary(0);
      setNewDocuments([]);
      setShowAddModal(false);

      // Refresh
      await fetchEmployeesData();
      
      confetti({
        particleCount: 80,
        spread: 60,
        colors: ['#0D9488', '#10B981']
      });
      alert('تم إضافة الموظف الجديد بنجاح وإنشاء حسابه الجغرافي! ✅');
    } catch (err: any) {
      alert(`فشل إضافة الموظف: ${err.message || 'حدث خطأ غير متوقع'}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleOpenEditModal = (emp: any) => {
    setSelectedEmployee(emp);
    setFullName(emp.full_name);
    setEmail(emp.email);
    setPhone(emp.phone || '');
    setRole(emp.role);
    setBranchId(emp.branch_id || '');
    setMonthlySalary(emp.monthly_salary_iqd || 0);
    setFutureSalary(emp.future_salary_iqd || 0);
    setFutureSalaryMonth(emp.future_salary_month || '');
    setPassword(emp.plain_password || '');
    setExistingDocuments(emp.document_urls || []);
    setNewDocuments([]);
    setShowEditModal(true);
  };

  const handleUpdateEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedEmployee) return;
    setActionLoading('update_emp');
    try {
      // Update auth credentials safely via RPC
      const { error: rpcErr } = await supabase.rpc('update_employee_credentials', {
        p_employee_id: selectedEmployee.id,
        p_email: email,
        p_password: password,
        p_phone: phone || ''
      });
      if (rpcErr) throw rpcErr;

      // Find deleted documents to remove from storage
      const originalDocs = selectedEmployee.document_urls || [];
      const deletedDocs = originalDocs.filter((url: string) => !existingDocuments.includes(url));
      
      for (const url of deletedDocs) {
        try {
          const pathMatch = url.match(/\/documents\/(.+)$/);
          if (pathMatch && pathMatch[1]) {
            await supabase.storage.from('documents').remove([pathMatch[1]]);
          }
        } catch (err) {
          console.error('Failed to delete old document:', err);
        }
      }

      // Upload new documents
      let newUploadedUrls: string[] = [];
      if (newDocuments.length > 0) {
        for (const file of newDocuments) {
          try {
            const compressedFile = await imageCompression(file, {
              maxSizeMB: 1,
              maxWidthOrHeight: 1920,
              useWebWorker: true,
            });
            const fileExt = file.name.split('.').pop();
            const fileName = `${selectedEmployee.id}/${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;
            
            const { error: uploadError } = await supabase.storage.from('documents').upload(fileName, compressedFile);
            if (!uploadError) {
              const { data: { publicUrl } } = supabase.storage
                .from('documents')
                .getPublicUrl(fileName);
              newUploadedUrls.push(publicUrl);
            }
          } catch (err) {
            console.error('Failed to compress/upload file:', err);
          }
        }
      }

      const finalDocumentUrls = [...existingDocuments, ...newUploadedUrls];

      const { error: updErr } = await supabase
        .from('employees')
        .update({
          full_name: fullName,
          role,
          branch_id: branchId || null,
          monthly_salary_iqd: monthlySalary || 0,
          future_salary_iqd: futureSalary || null,
          future_salary_month: futureSalaryMonth || null,
          document_urls: finalDocumentUrls
        })
        .eq('id', selectedEmployee.id);

      if (updErr) throw updErr;

      setShowEditModal(false);
      setSelectedEmployee(null);
      setNewDocuments([]);
      
      // Refresh
      await fetchEmployeesData();

      confetti({
        particleCount: 50,
        spread: 40,
        colors: ['#3B82F6', '#10B981']
      });
      alert('تم تحديث بيانات الموظف وسجلاته بنجاح! ✅');
    } catch (err: any) {
      alert(`فشل تعديل بيانات الموظف: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const fetchArchivedEmployees = async () => {
    try {
      const { data, error } = await supabase
        .from('archived_employees')
        .select('*')
        .order('archived_at', { ascending: false });
      if (data) {
        setArchivedEmployees(data);
        
        // Cache archive list
        const cached = localStorage.getItem('batra_cache_employees');
        if (cached) {
          try {
            const parsed = JSON.parse(cached);
            parsed.archivedEmployees = data;
            localStorage.setItem('batra_cache_employees', JSON.stringify(parsed));
          } catch (e) {}
        }
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleOpenDeleteModal = (emp: any) => {
    setEmployeeToDelete(emp);
    setDeleteReason('');
    setDeleteType('archive');
    setShowDeleteModal(true);
  };

  const executeDeleteEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!employeeToDelete) return;
    setActionLoading('delete_emp');

    try {
      const { data: { session } } = await supabase.auth.getSession();
      const currentAdminId = session?.user?.id;

      if (deleteType === 'immediate') {
        const { error: delProfileErr } = await supabase
          .from('employees')
          .delete()
          .eq('id', employeeToDelete.id);
        if (delProfileErr) throw delProfileErr;

        const { error: insErr } = await supabase.from('archived_employees').insert({
          employee_id: employeeToDelete.id,
          employee_code: employeeToDelete.employee_code,
          full_name: employeeToDelete.full_name,
          archive_type: 'permanent',
          archive_reason: deleteReason || 'حذف فوري نهائي من لوحة التحكم',
          archived_by: currentAdminId,
          archived_at: new Date().toISOString()
        });
        if (insErr) throw insErr;
      } 
      else if (deleteType === 'archive') {
        const { error: updErr } = await supabase
          .from('employees')
          .update({ is_active: false })
          .eq('id', employeeToDelete.id);
        if (updErr) throw updErr;

        const { error: insErr } = await supabase.from('archived_employees').insert({
          employee_id: employeeToDelete.id,
          employee_code: employeeToDelete.employee_code,
          full_name: employeeToDelete.full_name,
          archive_type: 'archive',
          archive_reason: deleteReason || 'أرشفة وتعطيل الحساب الإداري للموظف',
          archived_by: currentAdminId,
          archived_at: new Date().toISOString()
        });
        if (insErr) throw insErr;
      } 
      else if (deleteType === 'scheduled') {
        const { error: updErr } = await supabase
          .from('employees')
          .update({ is_active: false })
          .eq('id', employeeToDelete.id);
        if (updErr) throw updErr;

        const deletionDate = new Date();
        deletionDate.setDate(deletionDate.getDate() + 30);

        const { error: insErr } = await supabase.from('archived_employees').insert({
          employee_id: employeeToDelete.id,
          employee_code: employeeToDelete.employee_code,
          full_name: employeeToDelete.full_name,
          archive_type: 'scheduled_deletion',
          archive_reason: deleteReason || 'حذف مجدول بعد 30 يوماً من لوحة التحكم',
          scheduled_deletion_date: deletionDate.toISOString(),
          archived_by: currentAdminId,
          archived_at: new Date().toISOString()
        });
        if (insErr) throw insErr;
      }

      setShowDeleteModal(false);
      setEmployeeToDelete(null);
      
      await fetchEmployeesData();
      await fetchArchivedEmployees();

      confetti({
        particleCount: 70,
        spread: 50,
        colors: ['#EF4444', '#F59E0B']
      });
      alert('تم تنفيذ عملية الحذف/الأرشفة المطلوبة للموظف بنجاح! ✅');
    } catch (err: any) {
      alert(`فشل إتمام العملية: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleRestoreArchivedEmployee = async (archRecord: any) => {
    if (!confirm(`هل أنت متأكد من رغبتك في استعادة الموظف (${archRecord.full_name}) وتنشيط حسابه الجغرافي للدوام مجدداً؟`)) return;
    setActionLoading('restore_' + archRecord.id);

    try {
      const { error: updErr } = await supabase
        .from('employees')
        .update({ is_active: true })
        .eq('id', archRecord.employee_id);
      if (updErr) throw updErr;

      const { error: delErr } = await supabase
        .from('archived_employees')
        .delete()
        .eq('id', archRecord.id);
      if (delErr) throw delErr;

      await fetchEmployeesData();
      await fetchArchivedEmployees();

      confetti({
        particleCount: 50,
        spread: 40,
        colors: ['#10B981', '#34D399']
      });
      alert('تم استعادة الموظف وتنشيط حسابه بالكامل بنجاح! ✅');
    } catch (err: any) {
      alert(`فشل استعادة الموظف: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handlePermanentDeleteArchived = async (archRecord: any) => {
    if (!confirm(`تحذير نهائي: هل تريد حقاً حذف الموظف (${archRecord.full_name}) وإتلاف حسابه وسجلاته وبصماته من قاعدة البيانات بشكل كامل ونهائي؟ لا يمكن استعادة البيانات بعد ذلك.`)) return;
    setActionLoading('perm_del_' + archRecord.id);

    try {
      await supabase
        .from('employees')
        .delete()
        .eq('id', archRecord.employee_id);

      const { error: updErr } = await supabase
        .from('archived_employees')
        .update({
          archive_type: 'permanent',
          notes: 'تم الإتلاف النهائي اليدوي للبيانات والحساب من قبل المسؤول.'
        })
        .eq('id', archRecord.id);
      if (updErr) throw updErr;

      await fetchEmployeesData();
      await fetchArchivedEmployees();

      alert('تم إتلاف بيانات وحساب الموظف نهائياً وبنجاح! 🗑️');
    } catch (err: any) {
      alert(`فشل الإتلاف النهائي: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const filteredEmployees = employees.filter(emp => {
    const matchesSearch = (emp.full_name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
                          (emp.email || '').toLowerCase().includes(searchTerm.toLowerCase());
    const matchesBranch = selectedDirectoryBranch === 'all' || emp.branch_id === selectedDirectoryBranch;
    return matchesSearch && matchesBranch;
  });

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      {/* Device binding requests approval alert section */}
      {deviceRequests.length > 0 && (
        <div className="bg-purple-950/20 border border-purple-500/20 rounded-3xl p-6 shadow-xl space-y-4">
          <div className="flex items-center gap-2 text-purple-400">
            <Smartphone className="w-6 h-6 animate-pulse" />
            <h3 className="text-base font-extrabold text-white">طلبات ربط واعتماد الأجهزة المعلقة ({deviceRequests.length})</h3>
          </div>
          <p className="text-xs text-slate-300 leading-relaxed">
            قام الموظفون أدناه بتسجيل الدخول من هواتف جديدة أو طلبوا تغيير جهازهم المقفل. يرجى مراجعة واعتماد طلباتهم لتفعيل تسجيل دوامهم الجغرافي بأمان.
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2">
            {deviceRequests.map((req) => (
              <div 
                key={req.id} 
                className="bg-slate-900/60 backdrop-blur border border-slate-800/80 rounded-2xl p-4 flex flex-col justify-between"
              >
                <div className="mb-4">
                  <div className="flex items-center justify-between mb-2">
                    <h4 className="text-xs font-bold text-white">{req.employees?.full_name || 'موظف'}</h4>
                    <span className="text-[9px] bg-purple-500/20 text-purple-300 px-2 py-0.5 rounded-full border border-purple-500/30">
                      طلب اعتماد
                    </span>
                  </div>
                  <div className="space-y-1 text-[10px] text-slate-400">
                    <p>موديل الجهاز: <span className="text-slate-200 font-bold">{req.device_model || 'غير محدد'}</span></p>
                    <p>نظام التشغيل: <span className="text-slate-200">{req.os_version || 'غير محدد'}</span></p>
                    <p className="font-mono text-purple-300">ID: {req.device_id}</p>
                  </div>
                </div>

                <div className="flex gap-2">
                  <button
                    disabled={actionLoading === req.id}
                    onClick={() => handleProcessDeviceRequest(req.id, req.employee_id, true)}
                    className="flex-1 flex items-center justify-center gap-1.5 py-2 px-3 bg-teal-650 hover:bg-teal-500 text-white rounded-xl text-[10px] font-bold shadow transition-colors cursor-pointer"
                  >
                    <Check className="w-3.5 h-3.5" />
                    <span>اعتماد واعتماد القفل</span>
                  </button>
                  <button
                    disabled={actionLoading === req.id}
                    onClick={() => handleProcessDeviceRequest(req.id, req.employee_id, false)}
                    className="flex-1 flex items-center justify-center gap-1.5 py-2 px-3 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-xl text-[10px] font-bold transition-colors cursor-pointer"
                  >
                    <X className="w-3.5 h-3.5" />
                    <span>رفض الطلب</span>
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Main Employee Directory Directory */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
        
        {/* Tab switch for active vs archived */}
        <div className="flex gap-2 p-1.5 bg-slate-950/80 border border-slate-800 rounded-2xl w-fit mb-4">
          <button
            type="button"
            onClick={() => setActiveTab('active')}
            className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
              activeTab === 'active' 
                ? 'bg-teal-600 text-white shadow-md shadow-teal-500/10' 
                : 'text-slate-400 hover:text-white'
            }`}
          >
            👤 دليل الكوادر النشطة
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('archived')}
            className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
              activeTab === 'archived' 
                ? 'bg-amber-600 text-white shadow-md shadow-amber-500/10' 
                : 'text-slate-400 hover:text-white'
            }`}
          >
            🗄️ الأرشيف والحذف المجدول ({archivedEmployees.length})
          </button>
        </div>

        {activeTab === 'active' ? (
          <>
            {/* Header and search */}
            <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
              <div>
                <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
                  <Users className="w-5 h-5 text-teal-400" />
                  <span>دليل موظفي المؤسسة وإدارة الهواتف</span>
                </h3>
                <p className="text-[11px] text-slate-400">تحديث وتعديل الموظفين، وقرنهم بالفروع والأقسام كلياً</p>
              </div>

              <div className="flex flex-col sm:flex-row gap-3 items-center w-full lg:w-auto flex-1 max-w-2xl justify-end">
                <div className="relative flex-1 min-w-[200px] max-w-sm">
                  <input
                    type="text"
                    placeholder="ابحث باسم الموظف أو البريد..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="w-full bg-slate-950/80 border border-slate-800 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 rounded-2xl py-2.5 px-4 pr-10 text-xs text-white placeholder-slate-500 transition-all outline-none animate-glass"
                  />
                  <Search className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
                </div>

                <div className="flex items-center gap-2 bg-slate-950/80 border border-slate-800 rounded-2xl px-3 py-2.5 min-w-[140px]">
                  <Building className="w-4 h-4 text-teal-400" />
                  <select 
                    value={selectedDirectoryBranch}
                    onChange={(e) => setSelectedDirectoryBranch(e.target.value)}
                    className="bg-transparent border-none text-white text-xs outline-none cursor-pointer w-full"
                  >
                    <option value="all" className="bg-slate-900">جميع الفروع</option>
                    {branches.map(b => (
                      <option key={b.id} value={b.id} className="bg-slate-900">{b.name}</option>
                    ))}
                  </select>
                </div>

                <button
                  type="button"
                  onClick={() => {
                    setFullName('');
                    setEmail('');
                    setPhone('');
                    setPassword('');
                    setRole('employee');
                    setBranchId('');
                    setMonthlySalary(0);
                    setShowAddModal(true);
                  }}
                  className="flex items-center gap-1.5 py-2.5 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-2xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer whitespace-nowrap active:scale-95"
                >
                  <Plus className="w-4 h-4" />
                  <span>إضافة موظف جديد</span>
                </button>
              </div>
            </div>

        {/* Directory table */}
        <div className="overflow-x-auto">
          <table className="w-full text-right border-collapse">
            <thead>
              <tr className="border-b border-slate-800/80 text-slate-400 text-xs font-bold bg-slate-950/30">
                <th className="p-4">اسم الموظف الثلاثي</th>
                <th className="p-4">البريد الإلكتروني للعمل</th>
                <th className="p-4">رقم الهاتف</th>
                <th className="p-4">الرمز السري</th>
                <th className="p-4">الفرع الجغرافي</th>
                <th className="p-4">الدور / الصلاحية</th>
                <th className="p-4">الراتب الأساسي</th>
                <th className="p-4">ربط الهاتف وقفل الجهاز</th>
                <th className="p-4 text-left">إجراءات سريعة</th>
              </tr>
            </thead>
            <tbody>
              {filteredEmployees.length === 0 ? (
                <tr>
                  <td colSpan={9} className="p-8 text-center text-slate-500 text-xs">
                    عذراً، لم نعثر على أي نتائج للبحث المكتوب.
                  </td>
                </tr>
              ) : (
                filteredEmployees.map((emp) => {
                  const isLocked = emp.device_id_lock != null;
                  return (
                    <tr 
                      key={emp.id} 
                      className="border-b border-slate-800/40 hover:bg-slate-900/20 text-slate-300 text-xs transition-colors"
                    >
                      <td className="p-4 font-bold text-white">{emp.full_name}</td>
                      <td className="p-4 font-mono text-slate-400">{emp.email}</td>
                      <td className="p-4 font-mono">{emp.phone || '-'}</td>
                      <td className="p-4 font-mono text-purple-400 bg-purple-500/10 rounded-lg px-2">{emp.plain_password || 'مخفي'}</td>
                      <td className="p-4 font-bold text-teal-400">{emp.branches?.name || '-'}</td>
                      <td className="p-4">
                        <span className={`px-2.5 py-0.5 rounded-full text-[9px] font-bold border ${
                          emp.role === 'admin' 
                            ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' 
                            : emp.role === 'manager' 
                            ? 'bg-amber-500/10 border-amber-500/20 text-amber-400' 
                            : 'bg-blue-500/10 border-blue-500/20 text-blue-400'
                        }`}>
                          {emp.role === 'admin' ? 'مدير عام' : emp.role === 'manager' ? 'مدير موارد' : 'موظف'}
                        </span>
                      </td>
                      <td className="p-4 font-bold text-slate-200">
                        {emp.monthly_salary_iqd ? emp.monthly_salary_iqd.toLocaleString() : '0'} د.ع
                      </td>
                      <td className="p-4">
                        <div className="flex items-center gap-2">
                          {isLocked ? (
                            <span className="flex items-center gap-1 text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-2 py-0.5 rounded-md font-bold text-[9px]">
                              <Lock className="w-3 h-3" />
                              <span>مربوط ومقفل</span>
                            </span>
                          ) : (
                            <span className="flex items-center gap-1 text-slate-400 bg-slate-800/50 border border-slate-700/30 px-2 py-0.5 rounded-md text-[9px]">
                              <Unlock className="w-3 h-3" />
                              <span>غير مربوط حالياً</span>
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="p-4 text-left">
                        <div className="flex justify-end gap-2">
                          <button
                            onClick={() => handleOpenEditModal(emp)}
                            className="flex items-center gap-1.5 px-3 py-2 bg-blue-500/10 border border-blue-500/20 text-blue-400 hover:bg-blue-500/20 rounded-lg transition-all cursor-pointer font-bold text-[10px]"
                            title="تعديل بيانات، راتب، وصلاحيات الموظف"
                          >
                            <Edit className="w-3.5 h-3.5" />
                            <span>تعديل الراتب/الصلاحية</span>
                          </button>

                          <button
                            disabled={actionLoading === emp.id}
                            onClick={() => handleToggleDeviceLock(emp.id, emp.device_id_lock)}
                            className={`p-2 rounded-lg border transition-all cursor-pointer ${
                              isLocked 
                                ? 'bg-amber-500/10 border-amber-500/20 text-amber-400 hover:bg-amber-500/20' 
                                : 'bg-teal-500/10 border-teal-500/20 text-teal-400 hover:bg-teal-500/20'
                            }`}
                            title={isLocked ? 'فك قفل الجهاز مؤقتاً' : 'تفعيل قفل الهاتف الافتراضي'}
                          >
                            {isLocked ? <Unlock className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
                          </button>

                          {isLocked && (
                            <button
                              disabled={actionLoading === emp.id + '_reset'}
                              onClick={() => handleResetDeviceBinding(emp.id)}
                              className="p-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 text-red-400 rounded-lg transition-all cursor-pointer"
                              title="إلغاء وربط هاتف جديد للموظف"
                            >
                              <Smartphone className="w-4 h-4" />
                            </button>
                          )}

                          <button
                            disabled={actionLoading === emp.id}
                            onClick={() => handleOpenDeleteModal(emp)}
                            className="p-2 bg-red-500/10 hover:bg-red-500/25 border border-red-500/20 text-red-400 rounded-lg transition-all cursor-pointer"
                            title="حذف أو أرشفة الموظف"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
        </>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right border-collapse">
              <thead>
                <tr className="border-b border-slate-800/80 text-slate-400 text-xs font-bold bg-slate-950/30">
                  <th className="p-4">اسم الموظف الثلاثي</th>
                  <th className="p-4">رمز الموظف</th>
                  <th className="p-4">طريقة الإجراء</th>
                  <th className="p-4">سبب الإجراء والبيان</th>
                  <th className="p-4">حذف مجدول في</th>
                  <th className="p-4">تاريخ الأرشفة</th>
                  <th className="p-4 text-left">إجراءات استعادة / إتلاف</th>
                </tr>
              </thead>
              <tbody>
                {archivedEmployees.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="p-8 text-center text-slate-500 text-xs">
                      لا يوجد أي موظف في قائمة الأرشيف حالياً. 🗃️
                    </td>
                  </tr>
                ) : (
                  archivedEmployees.map((arch) => {
                    const expiryDate = arch.scheduled_deletion_date ? new Date(arch.scheduled_deletion_date) : null;
                    const daysLeft = expiryDate ? Math.ceil((expiryDate.getTime() - new Date().getTime()) / (1000 * 3600 * 24)) : null;

                    return (
                      <tr 
                        key={arch.id} 
                        className="border-b border-slate-800/40 hover:bg-slate-900/20 text-slate-300 text-xs transition-colors"
                      >
                        <td className="p-4 font-bold text-white">{arch.full_name}</td>
                        <td className="p-4 font-mono text-slate-400">{arch.employee_code || '-'}</td>
                        <td className="p-4">
                          <span className={`px-2.5 py-0.5 rounded-full text-[9px] font-bold border ${
                            arch.archive_type === 'permanent' 
                              ? 'bg-red-500/10 border-red-500/20 text-red-400' 
                              : arch.archive_type === 'scheduled_deletion' 
                              ? 'bg-amber-500/10 border-amber-500/20 text-amber-400 animate-pulse' 
                              : 'bg-blue-500/10 border-blue-500/20 text-blue-400'
                          }`}>
                            {arch.archive_type === 'permanent' 
                              ? 'إتلاف نهائي' 
                              : arch.archive_type === 'scheduled_deletion' 
                              ? 'حذف مجدول بعد 30 يوماً' 
                              : 'أرشفة مؤقتة'}
                          </span>
                        </td>
                        <td className="p-4 max-w-xs truncate" title={arch.archive_reason}>{arch.archive_reason || '-'}</td>
                        <td className="p-4 font-mono">
                          {expiryDate ? (
                            <span className="text-amber-400 font-bold">
                              {expiryDate.toLocaleDateString('ar-IQ')} ({daysLeft} يوم متبقي)
                            </span>
                          ) : '-'}
                        </td>
                        <td className="p-4 text-slate-400 font-mono">
                          {new Date(arch.archived_at).toLocaleDateString('ar-IQ')}
                        </td>
                        <td className="p-4 text-left">
                          <div className="flex justify-end gap-2">
                            {arch.archive_type !== 'permanent' && (
                              <button
                                type="button"
                                disabled={actionLoading === 'restore_' + arch.id}
                                onClick={() => handleRestoreArchivedEmployee(arch)}
                                className="flex items-center gap-1 px-3 py-1.5 bg-teal-600/20 hover:bg-teal-600/30 border border-teal-500/30 text-teal-400 rounded-xl transition-all cursor-pointer font-bold text-[10px]"
                              >
                                <span>إعادة تفعيل الحساب</span>
                              </button>
                            )}
                            <button
                              type="button"
                              disabled={actionLoading === 'perm_del_' + arch.id}
                              onClick={() => handlePermanentDeleteArchived(arch)}
                              className="flex items-center gap-1 px-3 py-1.5 bg-red-500/15 hover:bg-red-500/25 border border-red-500/20 text-red-400 rounded-xl transition-all cursor-pointer font-bold text-[10px]"
                            >
                              <span>إتلاف قطعي</span>
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Add Employee Modal (Glassmorphic) */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md overflow-y-auto">
          <div className="relative w-full max-w-xl bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 animate-glass">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-emerald-500"></div>
            
            <div className="flex items-center gap-2 text-teal-400 mb-6">
              <Plus className="w-6 h-6" />
              <h3 className="text-lg font-bold text-white">إضافة موظف جغرافي جديد للمؤسسة</h3>
            </div>

            <form onSubmit={handleCreateEmployee} className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Users className="w-3.5 h-3.5 text-teal-400" />
                    <span>اسم الموظف الثلاثي</span>
                  </label>
                  <input
                    type="text"
                    required
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    placeholder="محمد علي عبد الحسين"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                  />
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Mail className="w-3.5 h-3.5 text-teal-400" />
                    <span>البريد الإلكتروني للعمل</span>
                  </label>
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="mohammed@hrpro.com"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Phone className="w-3.5 h-3.5 text-teal-400" />
                    <span>رقم الهاتف (العراق)</span>
                  </label>
                  <input
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="077XXXXXXXX"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                    dir="ltr"
                  />
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Lock className="w-3.5 h-3.5 text-teal-400" />
                    <span>كلمة مرور الحساب (6 أحرف فأكثر)</span>
                  </label>
                  <input
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Building className="w-3.5 h-3.5 text-teal-400" />
                    <span>الفرع الجغرافي</span>
                  </label>
                  <select
                    required
                    value={branchId}
                    onChange={(e) => setBranchId(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                  >
                    <option value="">اختر الفرع...</option>
                    {branches.map(b => (
                      <option key={b.id} value={b.id}>{b.name}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Briefcase className="w-3.5 h-3.5 text-teal-400" />
                    <span>الصلاحية</span>
                  </label>
                  <select
                    required
                    value={role}
                    onChange={(e) => setRole(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                  >
                    <option value="employee">موظف عادي</option>
                    <option value="manager">مدير موارد</option>
                    <option value="admin">مدير عام</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                  <DollarSign className="w-3.5 h-3.5 text-teal-400" />
                  <span>الراتب الأساسي الشهري (د.ع)</span>
                </label>
                <input
                  type="text"
                  required
                  value={monthlySalary || ''}
                  onChange={(e) => setMonthlySalary(Number(e.target.value.replace(/\D/g, '')))}
                  placeholder="1500000"
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-2 flex items-center gap-1">
                  <FileImage className="w-3.5 h-3.5 text-teal-400" />
                  <span>المستمسكات الثبوتية (اختياري)</span>
                </label>
                <div className="flex flex-wrap gap-3">
                  {newDocuments.map((file, idx) => (
                    <div key={idx} className="relative group">
                      <img src={URL.createObjectURL(file)} alt="doc" className="w-16 h-16 object-cover rounded-xl border border-slate-700" />
                      <button type="button" onClick={() => setNewDocuments(prev => prev.filter((_, i) => i !== idx))} className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity shadow-md">
                        <X className="w-3 h-3" />
                      </button>
                    </div>
                  ))}
                  <label className="w-16 h-16 flex items-center justify-center border-2 border-dashed border-slate-700 rounded-xl cursor-pointer hover:border-teal-500 hover:bg-slate-800/50 transition-colors">
                    <input type="file" multiple accept="image/*" className="hidden" onChange={(e) => {
                      if (e.target.files) {
                        setNewDocuments(prev => [...prev, ...Array.from(e.target.files as FileList)]);
                      }
                    }} />
                    <Upload className="w-5 h-5 text-slate-500" />
                  </label>
                </div>
                <p className="text-[10px] text-slate-500 mt-2">يمكنك رفع عدة صور. سيتم ضغط الصور تلقائياً وبشكل احترافي قبل الرفع.</p>
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800/80">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={actionLoading === 'create_emp'}
                  className="px-5 py-2.5 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow cursor-pointer active:scale-95 flex items-center gap-1.5"
                >
                  {actionLoading === 'create_emp' ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>جاري التسجيل...</span>
                    </>
                  ) : (
                    <span>تثبيت وتسجيل الموظف 🎯</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Employee Modal (Glassmorphic) */}
      {showEditModal && selectedEmployee && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md overflow-y-auto">
          <div className="relative w-full max-w-xl bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 animate-glass">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-blue-500 to-teal-500"></div>
            
            <div className="flex items-center gap-2 text-blue-400 mb-6">
              <Edit className="w-6 h-6" />
              <h3 className="text-lg font-bold text-white">تعديل ملف موظف: {selectedEmployee.full_name}</h3>
            </div>

            <form onSubmit={handleUpdateEmployee} className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Users className="w-3.5 h-3.5 text-blue-400" />
                    <span>اسم الموظف الثلاثي</span>
                  </label>
                  <input
                    type="text"
                    required
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    placeholder="محمد علي عبد الحسين"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-blue-500 rounded-xl p-3 text-xs text-white outline-none"
                  />
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Mail className="w-3.5 h-3.5 text-blue-400" />
                    <span>البريد الإلكتروني للعمل (اليوزرنيم)</span>
                  </label>
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-blue-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Phone className="w-3.5 h-3.5 text-blue-400" />
                    <span>رقم الهاتف (العراق)</span>
                  </label>
                  <input
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="077XXXXXXXX"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-blue-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                    dir="ltr"
                  />
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Lock className="w-3.5 h-3.5 text-blue-400" />
                    <span>الرمز السري (معلومات الجدول)</span>
                  </label>
                  <input
                    type="text"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full bg-slate-950 border border-slate-800 focus:border-blue-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <DollarSign className="w-3.5 h-3.5 text-emerald-400" />
                    <span>الراتب الأساسي الحالي (د.ع)</span>
                  </label>
                  <input
                    type="text"
                    value={monthlySalary || ''}
                    onChange={(e) => setMonthlySalary(Number(e.target.value.replace(/\D/g, '')))}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-emerald-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
                    dir="ltr"
                    placeholder="1500000"
                  />
                </div>

                <div className="grid grid-cols-2 gap-2 p-2 rounded-xl bg-slate-900 border border-teal-500/20">
                  <div className="col-span-2">
                    <label className="block text-xs text-teal-400 mb-1 font-bold">الراتب المستقبلي (د.ع) وتاريخ التفعيل (اختياري)</label>
                  </div>
                  <div>
                    <input
                      type="text"
                      placeholder="مبلغ الراتب (د.ع)"
                      value={futureSalary || ''}
                      onChange={(e) => setFutureSalary(Number(e.target.value.replace(/\D/g, '')))}
                      className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-lg p-2 text-xs text-white outline-none text-left"
                      dir="ltr"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">تاريخ التفعيل</label>
                    <input
                      type="date"
                      value={futureSalaryMonth || ''}
                      onChange={(e) => setFutureSalaryMonth(e.target.value)}
                      className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-lg p-2 text-xs text-white outline-none text-left"
                      dir="ltr"
                    />
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Building className="w-3.5 h-3.5 text-blue-400" />
                    <span>الفرع الجغرافي</span>
                  </label>
                  <select
                    required
                    value={branchId}
                    onChange={(e) => setBranchId(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-blue-500 rounded-xl p-3 text-xs text-white outline-none"
                  >
                    <option value="">اختر الفرع...</option>
                    {branches.map(b => (
                      <option key={b.id} value={b.id}>{b.name}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                    <Briefcase className="w-3.5 h-3.5 text-blue-400" />
                    <span>الصلاحية / التخصص</span>
                  </label>
                  <select
                    required
                    value={role}
                    onChange={(e) => setRole(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-800 focus:border-blue-500 rounded-xl p-3 text-xs text-white outline-none"
                  >
                    <option value="employee">موظف عادي</option>
                    <option value="manager">مدير موارد</option>
                    <option value="admin">مدير عام (Admin)</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-2 flex items-center gap-1">
                  <FileImage className="w-3.5 h-3.5 text-blue-400" />
                  <span>تعديل وإضافة المستمسكات الثبوتية</span>
                </label>
                <div className="flex flex-wrap gap-3">
                  {existingDocuments.map((url, idx) => (
                    <div key={'ex_'+idx} className="relative group">
                      <img src={url} alt="doc" className="w-16 h-16 object-cover rounded-xl border border-slate-700" />
                      <button type="button" onClick={() => setExistingDocuments(prev => prev.filter((_, i) => i !== idx))} className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity shadow-md">
                        <X className="w-3 h-3" />
                      </button>
                    </div>
                  ))}
                  {newDocuments.map((file, idx) => (
                    <div key={'new_'+idx} className="relative group">
                      <img src={URL.createObjectURL(file)} alt="doc" className="w-16 h-16 object-cover rounded-xl border border-blue-500/50" />
                      <button type="button" onClick={() => setNewDocuments(prev => prev.filter((_, i) => i !== idx))} className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity shadow-md">
                        <X className="w-3 h-3" />
                      </button>
                    </div>
                  ))}
                  <label className="w-16 h-16 flex items-center justify-center border-2 border-dashed border-slate-700 rounded-xl cursor-pointer hover:border-blue-500 hover:bg-slate-800/50 transition-colors">
                    <input type="file" multiple accept="image/*" className="hidden" onChange={(e) => {
                      if (e.target.files) {
                        setNewDocuments(prev => [...prev, ...Array.from(e.target.files as FileList)]);
                      }
                    }} />
                    <Upload className="w-5 h-5 text-slate-500" />
                  </label>
                </div>
                <p className="text-[10px] text-slate-500 mt-2">يمكنك حذف المستمسكات القديمة ورفع جديدة وسيتم إزالتها وإضافتها بشكل تلقائي.</p>
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800/80">
                <button
                  type="button"
                  onClick={() => {
                    setShowEditModal(false);
                    setSelectedEmployee(null);
                  }}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={actionLoading === 'update_emp'}
                  className="px-5 py-2.5 bg-blue-650 hover:bg-blue-600 text-white rounded-xl text-xs font-bold transition-all shadow cursor-pointer active:scale-95 flex items-center gap-1.5"
                >
                  {actionLoading === 'update_emp' ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>جاري حفظ التعديلات...</span>
                    </>
                  ) : (
                    <span>تحديث وحفظ الملف 💾</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Delete / Archive Employee Options Modal */}
      {showDeleteModal && employeeToDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md overflow-y-auto">
          <div className="relative w-full max-w-md bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden animate-glass">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-red-500 to-amber-500"></div>
            
            <div className="flex items-center gap-2 text-red-400 mb-6">
              <Trash2 className="w-6 h-6 animate-pulse" />
              <h3 className="text-lg font-bold text-white">خيارات حذف وأرشفة الموظف</h3>
            </div>

            <p className="text-xs text-slate-300 leading-relaxed mb-4">
              أنت على وشك إلغاء تنشيط أو حذف الموظف <strong className="text-white font-extrabold">{employeeToDelete.full_name}</strong> (رمز الموظف: {employeeToDelete.employee_code || 'غير محدد'}). يرجى تحديد طريقة الإجراء المطلوبة بدقة:
            </p>

            <form onSubmit={executeDeleteEmployee} className="space-y-4">
              
              {/* Deletion / Archiving Radio Options */}
              <div className="space-y-3">
                <label className={`flex gap-3 p-3 rounded-2xl border-2 cursor-pointer transition-all ${
                  deleteType === 'archive' ? 'border-teal-500 bg-teal-500/10' : 'border-slate-800 bg-slate-950/50 hover:bg-slate-900/30'
                }`}>
                  <input 
                    type="radio" 
                    name="deleteType" 
                    checked={deleteType === 'archive'} 
                    onChange={() => setDeleteType('archive')} 
                    className="mt-0.5"
                  />
                  <div>
                    <h4 className="text-xs font-bold text-white">🗃️ أرشفة وتجميد الحساب (موصى به)</h4>
                    <p className="text-[10px] text-slate-400 mt-1">يتم إيقاف تفعيل حساب الموظف ومنعه من التبصيم، مع الحفاظ الكامل على كافة بيانات حضور وسجلات الموظف في الأرشيف للرجوع إليها مستقبلاً.</p>
                  </div>
                </label>

                <label className={`flex gap-3 p-3 rounded-2xl border-2 cursor-pointer transition-all ${
                  deleteType === 'scheduled' ? 'border-amber-500 bg-amber-500/10' : 'border-slate-800 bg-slate-950/50 hover:bg-slate-900/30'
                }`}>
                  <input 
                    type="radio" 
                    name="deleteType" 
                    checked={deleteType === 'scheduled'} 
                    onChange={() => setDeleteType('scheduled')} 
                    className="mt-0.5"
                  />
                  <div>
                    <h4 className="text-xs font-bold text-white">⏳ حذف مجدول بعد 30 يوماً</h4>
                    <p className="text-[10px] text-slate-400 mt-1">تجميد حساب الموظف فوراً، وجدولة حذف ملفه وسجلاته بالكامل بشكل قطعي وتلقائي بعد 30 يوماً. سيتلقى الإدارة إشعار تذكير قبل التنفيذ بأسبوع.</p>
                  </div>
                </label>

                <label className={`flex gap-3 p-3 rounded-2xl border-2 cursor-pointer transition-all ${
                  deleteType === 'immediate' ? 'border-red-500 bg-red-500/10' : 'border-slate-800 bg-slate-950/50 hover:bg-slate-900/30'
                }`}>
                  <input 
                    type="radio" 
                    name="deleteType" 
                    checked={deleteType === 'immediate'} 
                    onChange={() => setDeleteType('immediate')} 
                    className="mt-0.5"
                  />
                  <div>
                    <h4 className="text-xs font-bold text-white">⚠️ حذف فوري كامل ونهائي</h4>
                    <p className="text-[10px] text-red-400 mt-1">حذف حساب الموظف، هويته، كافة بصمات حضوره وانصرافه، طلبات سلفه وإجازاته وسجلاته من قاعدة البيانات نهائياً وبدون أي إمكانية للاسترجاع!</p>
                  </div>
                </label>
              </div>

              {/* Reason input */}
              <div className="space-y-1">
                <label className="block text-xs text-slate-400 font-bold">السبب أو البيان (اختياري)</label>
                <input
                  type="text"
                  placeholder="مثال: استقالة، انتهاء العقد، فصل إداري..."
                  value={deleteReason}
                  onChange={(e) => setDeleteReason(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800/80">
                <button
                  type="button"
                  onClick={() => {
                    setShowDeleteModal(false);
                    setEmployeeToDelete(null);
                  }}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={actionLoading === 'delete_emp'}
                  className={`px-5 py-2.5 rounded-xl text-xs font-bold transition-all shadow cursor-pointer active:scale-95 flex items-center gap-1.5 text-white ${
                    deleteType === 'immediate' ? 'bg-red-600 hover:bg-red-500' : deleteType === 'scheduled' ? 'bg-amber-600 hover:bg-amber-500' : 'bg-teal-650 hover:bg-teal-500'
                  }`}
                >
                  {actionLoading === 'delete_emp' ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>جاري المعالجة والتنفيذ...</span>
                    </>
                  ) : (
                    <span>تأكيد وتنفيذ الإجراء 🚀</span>
                  )}
                </button>
              </div>

            </form>
          </div>
        </div>
      )}
    </div>
  );
}
