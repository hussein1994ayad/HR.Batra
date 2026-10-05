'use client';

// جلسة المدير بإطار اللوحة: التحقق من الدخول والصلاحية، عدّادات الطلبات المعلّقة وإشعارات النظام،
// وتحديثها لحظياً (Realtime) مع نغمة عند طلب/إشعار جديد.
//
// للسرعة: آخر جلسة تُحفظ في localStorage (batra_cache_admin) فتظهر اللوحة فوراً، ثم يُتحقق من
// السيرفر. كاش مستخدم آخر على نفس المتصفح يُمسح قبل عرض أي شيء منه.

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { User } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import { isDashboardRole, type DashboardRole } from '@/lib/role';
import type { AppNotification } from '@/lib/db-types';
import { clearLocalCaches } from '@/lib/local-cache';

/** نغمة قصيرة (Web Audio) بدون ملف صوت. */
function playBeep() {
  try {
    const AudioContextClass =
      window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    const osc = ctx.createOscillator();
    const gainNode = ctx.createGain();
    osc.connect(gainNode);
    gainNode.connect(ctx.destination);
    osc.type = 'sine';
    osc.frequency.setValueAtTime(880, ctx.currentTime);
    gainNode.gain.setValueAtTime(0.1, ctx.currentTime);
    osc.start();
    gainNode.gain.exponentialRampToValueAtTime(0.00001, ctx.currentTime + 0.5);
    osc.stop(ctx.currentTime + 0.5);
  } catch (e) {
    console.log('Audio playback failed:', e);
  }
}

export function useAdminSession() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [adminUser, setAdminUser] = useState<User | null>(null);
  const [adminName, setAdminName] = useState<string>('مدير النظام');
  const [role, setRole] = useState<DashboardRole>('admin');
  const [pendingLeaves, setPendingLeaves] = useState(0);
  const [pendingLoans, setPendingLoans] = useState(0);
  const [systemNotifs, setSystemNotifs] = useState<AppNotification[]>([]);

  useEffect(() => {
    const checkAuth = async () => {
      try {
        // 1. Try to load cached admin session instantly to avoid blocking UI
        const cachedAdmin = localStorage.getItem('batra_cache_admin');
        if (cachedAdmin) {
          try {
            const parsed = JSON.parse(cachedAdmin);
            if (parsed) {
              if (parsed.user) setAdminUser(parsed.user);
              if (parsed.name) setAdminName(parsed.name);
              if (parsed.role === 'manager') setRole('manager');
              setPendingLeaves(parsed.pendingLeaves || 0);
              setPendingLoans(parsed.pendingLoans || 0);
              setLoading(false); // Render layout instantly!
            }
          } catch (e) {
            console.error('Error parsing admin cache:', e);
          }
        }

        const { data: { session } } = await supabase.auth.getSession();
        // كاش مستخدم آخر على نفس المتصفح: يُمسح قبل عرض أي شيء منه
        if (session && cachedAdmin && !cachedAdmin.includes(session.user.id)) clearLocalCaches();
        if (!session) {
          clearLocalCaches();
          router.replace('/login');
          return;
        }

        // Verify role in employee table
        const { data: emp, error } = await supabase
          .from('employees')
          .select('full_name, role')
          .eq('id', session.user.id)
          .single();

        if (error || !emp || !isDashboardRole(emp.role)) {
          clearLocalCaches();
          await supabase.auth.signOut();
          router.replace('/login');
          return;
        }

        setAdminUser(session.user);
        setAdminName(emp.full_name);
        setRole(emp.role === 'manager' ? 'manager' : 'admin');

        // Fetch notification counts and unread notifications concurrently
        const [
          { count: leavesCount },
          { count: loansCount },
          { data: unreadNotifs }
        ] = await Promise.all([
          supabase.from('leave_requests').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
          supabase.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
          supabase.from('notifications').select('*').eq('employee_id', session.user.id).eq('is_read', false).order('created_at', { ascending: false })
        ]);

        setPendingLeaves(leavesCount || 0);
        setPendingLoans(loansCount || 0);
        if (unreadNotifs) setSystemNotifs(unreadNotifs);

        // Save session cache for next instant rendering
        localStorage.setItem('batra_cache_admin', JSON.stringify({
          user: session.user,
          name: emp.full_name,
          role: emp.role,
          pendingLeaves: leavesCount || 0,
          pendingLoans: loansCount || 0
        }));

        setLoading(false);
      } catch (err) {
        console.error('Auth check failed:', err);
        clearLocalCaches();
        router.replace('/login');
      }
    };

    checkAuth();
  }, [router]);

  useEffect(() => {
    if (!adminUser) return;

    const channelLeaves = supabase
      .channel('schema-db-changes-leaves')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'leave_requests'
        },
        async (payload) => {
          const { count } = await supabase
            .from('leave_requests')
            .select('*', { count: 'exact', head: true })
            .eq('status', 'pending');
          setPendingLeaves(count || 0);

          if (payload.eventType === 'INSERT') {
            playBeep();
          }
        }
      )
      .subscribe();

    const channelLoans = supabase
      .channel('schema-db-changes-loans')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'loans'
        },
        async (payload) => {
          const { count } = await supabase
            .from('loans')
            .select('*', { count: 'exact', head: true })
            .eq('status', 'pending');
          setPendingLoans(count || 0);

          if (payload.eventType === 'INSERT') {
            playBeep();
          }
        }
      )
      .subscribe();

    const channelNotifs = supabase
      .channel('schema-db-changes-notifications')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'notifications',
          filter: `employee_id=eq.${adminUser.id}`
        },
        async (payload) => {
          if (payload.new) {
            setSystemNotifs(prev => [payload.new as AppNotification, ...prev]);
            playBeep();
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channelLeaves);
      supabase.removeChannel(channelLoans);
      supabase.removeChannel(channelNotifs);
    };
  }, [adminUser]);

  const logout = async () => {
    clearLocalCaches();
    await supabase.auth.signOut();
    router.replace('/login');
  };

  const markAllNotifsRead = async () => {
    if (!adminUser || systemNotifs.length === 0) return;
    const ids = systemNotifs.map((n) => n.id).filter(Boolean);
    setSystemNotifs([]);
    if (ids.length > 0) {
      const { error } = await supabase.from('notifications').update({ is_read: true }).in('id', ids);
      if (error) console.error('Failed to mark notifications as read:', error);
    }
  };

  return { loading, adminName, role, pendingLeaves, pendingLoans, systemNotifs, logout, markAllNotifsRead };
}
