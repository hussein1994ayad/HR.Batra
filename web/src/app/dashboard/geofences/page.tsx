'use client';

import React, { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import MapComponent from '@/components/MapComponent';
import { 
  Building, 
  Plus, 
  MapPin, 
  Trash2, 
  Loader2,
  Globe,
  Navigation,
  Edit,
  Users,
  ExternalLink,
  CheckCircle
} from 'lucide-react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';

export default function GeofencesPage() {
  const [loading, setLoading] = useState(true);
  const [branches, setBranches] = useState<any[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Selection & Map Focus States
  const [selectedBranchId, setSelectedBranchId] = useState<string | null>(null);
  const [mapCenter, setMapCenter] = useState<[number, number]>([33.3152, 44.3661]);
  const [mapZoom, setMapZoom] = useState<number>(12);
  
  // Attendance States
  const [todayLogs, setTodayLogs] = useState<any[]>([]);
  const [loadingAttendance, setLoadingAttendance] = useState(false);

  // Async URL resolution loading states
  const [resolvingUrl, setResolvingUrl] = useState(false);
  const [editResolvingUrl, setEditResolvingUrl] = useState(false);

  // Add Branch Form Fields
  const [branchName, setBranchName] = useState('');
  const [latVal, setLatVal] = useState<number>(33.3152);
  const [lngVal, setLngVal] = useState<number>(44.3661);
  const [radiusVal, setRadiusVal] = useState<number>(150);
  const [addressVal, setAddressVal] = useState<string>(''); 
  const [mapUrlInput, setMapUrlInput] = useState('');

  // Edit Branch Form Fields & Modal State
  const [showEditModal, setShowEditModal] = useState(false);
  const [editBranchId, setEditBranchId] = useState('');
  const [editBranchName, setEditBranchName] = useState('');
  const [editLatVal, setEditLatVal] = useState<number>(33.3152);
  const [editLngVal, setEditLngVal] = useState<number>(44.3661);
  const [editRadiusVal, setEditRadiusVal] = useState<number>(150);
  const [editAddressVal, setEditAddressVal] = useState<string>(''); 
  const [editMapUrlInput, setEditMapUrlInput] = useState('');

  const extractCoordsFromText = (text: string) => {
    if (!text) return null;
    let decoded = text;
    try {
      decoded = decodeURIComponent(text);
    } catch (e) {}

    // Regex 1: look for @latitude,longitude (most common google maps format)
    const regexAt = /@(-?\d+\.\d+),(-?\d+\.\d+)/;
    const matchAt = decoded.match(regexAt);
    if (matchAt) {
      return { lat: parseFloat(matchAt[1]), lng: parseFloat(matchAt[2]) };
    }

    // Regex 2: look for q=latitude,longitude or ll=latitude,longitude
    const regexQ = /[?&](q|ll|query|saddr|daddr)=(-?\d+\.\d+),(-?\d+\.\d+)/;
    const matchQ = decoded.match(regexQ);
    if (matchQ) {
      return { lat: parseFloat(matchQ[2]), lng: parseFloat(matchQ[3]) };
    }

    // Regex 3: look for place/latitude,longitude
    const regexPlace = /\/place\/(-?\d+\.\d+)(?:\+|,)(-?\d+\.\d+)/;
    const matchPlace = decoded.match(regexPlace);
    if (matchPlace) {
      return { lat: parseFloat(matchPlace[1]), lng: parseFloat(matchPlace[2]) };
    }

    // Regex 4: Generic scan in Iraq bounds (lat: 29 to 38, lng: 38 to 49)
    const regexGeneric = /(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)/g;
    let genericMatch;
    while ((genericMatch = regexGeneric.exec(decoded)) !== null) {
      const lat = parseFloat(genericMatch[1]);
      const lng = parseFloat(genericMatch[2]);
      if (lat >= 29 && lat <= 38 && lng >= 38 && lng <= 49) {
        return { lat, lng };
      }
    }
    return null;
  };

  const resolveMapUrlWithFallback = async (urlStr: string): Promise<{ lat: number, lng: number } | null> => {
    const trimmed = urlStr.trim();
    
    // 1. Try local parsing first (for coordinates, long urls, etc.)
    const local = extractCoordsFromText(trimmed);
    if (local) return local;

    if (!trimmed.startsWith('http') && !trimmed.includes('maps') && !trimmed.includes('goo.gl')) {
      return null;
    }

    // 2. Proxies List to bypass CORS
    const proxies = [
      // Proxy A: AllOrigins (JSON proxy wrapper)
      async (u: string) => {
        const response = await fetch(`https://api.allorigins.win/get?url=${encodeURIComponent(u)}`);
        if (!response.ok) throw new Error('AllOrigins fail');
        const data = await response.json();
        return {
          url: data.status?.url || '',
          body: data.contents || ''
        };
      },
      // Proxy B: Codetabs (Direct CORS proxy)
      async (u: string) => {
        const response = await fetch(`https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(u)}`);
        if (!response.ok) throw new Error('Codetabs fail');
        const text = await response.text();
        return { url: '', body: text };
      },
      // Proxy C: ThingProxy (Fallback direct CORS proxy)
      async (u: string) => {
        const response = await fetch(`https://thingproxy.freeboard.io/fetch/${encodeURIComponent(u)}`);
        if (!response.ok) throw new Error('ThingProxy fail');
        const text = await response.text();
        return { url: '', body: text };
      }
    ];

    for (let i = 0; i < proxies.length; i++) {
      try {
        console.log(`Bypassing CORS via Proxy ${i + 1}...`);
        const { url: resolvedUrl, body } = await proxies[i](trimmed);

        if (resolvedUrl) {
          const coords = extractCoordsFromText(resolvedUrl);
          if (coords) return coords;
        }

        if (body) {
          // Check og:url meta
          const ogMatch = body.match(/property="og:url"\s+content="([^"]+)"/) || body.match(/content="([^"]+)"\s+property="og:url"/);
          if (ogMatch) {
            const coords = extractCoordsFromText(ogMatch[1]);
            if (coords) return coords;
          }

          // Check canonical
          const canonicalMatch = body.match(/rel="canonical"\s+href="([^"]+)"/) || body.match(/href="([^"]+)"\s+rel="canonical"/);
          if (canonicalMatch) {
            const coords = extractCoordsFromText(canonicalMatch[1]);
            if (coords) return coords;
          }

          // Check window.APP_INITIALIZATION_STATE
          const initMatch = body.match(/window\.APP_INITIALIZATION_STATE=\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)/) || body.match(/APP_INITIALIZATION_STATE=\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)/);
          if (initMatch) {
            return {
              lat: parseFloat(initMatch[2]),
              lng: parseFloat(initMatch[1])
            };
          }

          // Scan body
          const coords = extractCoordsFromText(body);
          if (coords) return coords;
        }
      } catch (err) {
        console.warn(`Proxy ${i + 1} bypass warn:`, err);
      }
    }
    return null;
  };

  const handleMapUrlChange = async (value: string) => {
    setMapUrlInput(value);
    if (!value) return;

    setResolvingUrl(true);
    try {
      const coords = await resolveMapUrlWithFallback(value);
      if (coords) {
        setLatVal(coords.lat);
        setLngVal(coords.lng);
      }
    } catch (err) {
      console.error('Error in handleMapUrlChange:', err);
    } finally {
      setResolvingUrl(false);
    }
  };

  const handleEditMapUrlChange = async (value: string) => {
    setEditMapUrlInput(value);
    if (!value) return;

    setEditResolvingUrl(true);
    try {
      const coords = await resolveMapUrlWithFallback(value);
      if (coords) {
        setEditLatVal(coords.lat);
        setEditLngVal(coords.lng);
      }
    } catch (err) {
      console.error('Error in handleEditMapUrlChange:', err);
    } finally {
      setEditResolvingUrl(false);
    }
  };

  useEffect(() => {
    // 1. Try to load cached branches and today logs instantly
    const cachedData = localStorage.getItem('batra_cache_geofences');
    if (cachedData) {
      try {
        const parsed = JSON.parse(cachedData);
        setBranches(parsed.branches || []);
        setTodayLogs(parsed.todayLogs || []);
        setLoading(false); // Instant render layout!
      } catch (e) {
        console.error('Error parsing geofences cache:', e);
      }
    }

    // 2. Fetch fresh data silently
    fetchBranches(!!cachedData);
    fetchTodayAttendance();
  }, []);

  const fetchBranches = async (hasCache = false) => {
    if (!hasCache) {
      setLoading(true);
    }
    try {
      const { data, error } = await supabase
        .from('branches')
        .select('*')
        .order('created_at', { ascending: false });

      if (data) {
        setBranches(data);
        
        // Cache branches and existing todayLogs
        const currentLogs = localStorage.getItem('batra_cache_geofences');
        let logs = [];
        if (currentLogs) {
          try { logs = JSON.parse(currentLogs).todayLogs || []; } catch (e) {}
        }
        localStorage.setItem('batra_cache_geofences', JSON.stringify({
          branches: data,
          todayLogs: logs
        }));
      }
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const fetchTodayAttendance = async () => {
    setLoadingAttendance(true);
    try {
      const todayStr = new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD in local time
      const { data, error } = await supabase
        .from('attendance')
        .select('*, employees!employee_id(full_name, phone, email, branch_id)')
        .eq('work_date', todayStr);

      if (data) {
        setTodayLogs(data);

        // Update todayLogs in cache
        const cached = localStorage.getItem('batra_cache_geofences');
        if (cached) {
          try {
            const parsed = JSON.parse(cached);
            parsed.todayLogs = data;
            localStorage.setItem('batra_cache_geofences', JSON.stringify(parsed));
          } catch (e) {}
        }
      }
    } catch (err) {
      console.error('Error fetching today attendance:', err);
    } finally {
      setLoadingAttendance(false);
    }
  };

  // Haversine formula to compute distance in meters between two coordinates
  const getDistanceMeters = (lat1: number, lon1: number, lat2: number, lon2: number) => {
    const R = 6371e3; // Earth radius in meters
    const phi1 = lat1 * Math.PI / 180;
    const phi2 = lat2 * Math.PI / 180;
    const deltaPhi = (lat2 - lat1) * Math.PI / 180;
    const deltaLambda = (lon2 - lon1) * Math.PI / 180;

    const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
              Math.cos(phi1) * Math.cos(phi2) *
              Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c; // distance in meters
  };

  const getEmployeesInSelectedBranch = () => {
    if (!selectedBranchId) return [];
    const selectedBranch = branches.find(b => b.id === selectedBranchId);
    if (!selectedBranch) return [];

    return todayLogs.filter(log => {
      // 1. Check if the attendance directly references this branch
      if (log.branch_id === selectedBranchId) return true;
      if (log.employees?.branch_id === selectedBranchId) return true;

      // 2. Check by geographic distance if coordinates are present
      if (log.check_in_lat && log.check_in_lng) {
        const distance = getDistanceMeters(
          Number(log.check_in_lat),
          Number(log.check_in_lng),
          Number(selectedBranch.latitude),
          Number(selectedBranch.longitude)
        );
        return distance <= (selectedBranch.radius_meters || 150);
      }

      return false;
    }).map(log => {
      let distanceText = '';
      if (log.check_in_lat && log.check_in_lng) {
        const distance = getDistanceMeters(
          Number(log.check_in_lat),
          Number(log.check_in_lng),
          Number(selectedBranch.latitude),
          Number(selectedBranch.longitude)
        );
        distanceText = `على بُعد ${Math.round(distance)} متر`;
      } else {
        distanceText = 'بصمة موجهة يدوياً للفرع';
      }

      return {
        id: log.id,
        name: log.employees?.full_name || 'موظف غير معروف',
        phone: log.employees?.phone || 'بلا هاتف',
        checkInTime: log.check_in_time ? new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
        distanceText
      };
    });
  };

  const handleSelectBranch = (branchId: string) => {
    setSelectedBranchId(branchId);
    const branch = branches.find(b => b.id === branchId);
    if (branch && branch.latitude && branch.longitude) {
      setMapCenter([branch.latitude, branch.longitude]);
      setMapZoom(16);
    }
  };

  const handleOpenEditModal = (b: any) => {
    setEditBranchId(b.id);
    setEditBranchName(b.name);
    setEditLatVal(b.latitude);
    setEditLngVal(b.longitude);
    setEditRadiusVal(b.radius_meters || 150);
    setEditAddressVal(b.address || '');
    setEditMapUrlInput('');
    setShowEditModal(true);
  };

  const handleDeleteBranch = async (branchId: string) => {
    if (!confirm('تحذير: هل أنت متأكد من رغبتك في حذف هذا الفرع الجغرافي بالكامل؟ سيؤدي هذا لإلغاء تبعية الموظفين المربوطين به وقد يؤثر على صلاحية تبصيم الحضور.')) return;
    setActionLoading(branchId + '_delete');
    try {
      const { error } = await supabase
        .from('branches')
        .delete()
        .eq('id', branchId);

      if (error) throw error;

      setBranches(prev => prev.filter(b => b.id !== branchId));
      if (selectedBranchId === branchId) {
        setSelectedBranchId(null);
      }
      toast.success('تم حذف الفرع الجغرافي ونطاق البصمة الخاص به بنجاح 🗑️');
    } catch (err: any) {
      toast.error(`فشل حذف الفرع: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleCreateBranch = async (e: React.FormEvent) => {
    e.preventDefault();
    setActionLoading('create');
    
    try {
      if (radiusVal <= 0) {
        throw new Error('يجب أن يكون مدى البصمة (نصف القطر) أكبر من 0 متر');
      }

      const { error } = await supabase.from('branches').insert({
        name: branchName,
        latitude: latVal,
        longitude: lngVal,
        radius_meters: radiusVal,
        address: addressVal,
      });

      if (error) throw error;

      // Reset Form
      setBranchName('');
      setLatVal(33.3152);
      setLngVal(44.3661);
      setRadiusVal(150);
      setAddressVal('');
      setMapUrlInput('');
      setShowAddModal(false);

      // Refresh list
      await fetchBranches();

      confetti({
        particleCount: 100,
        spread: 80,
        colors: ['#0D9488', '#3B82F6']
      });

      toast.success('تم إضافة الفرع الجغرافي الجديد ورسم حدود بصمته بنجاح! 🏢');
    } catch (err: any) {
      toast.error(err.message || 'حدث خطأ غير متوقع');
    } finally {
      setActionLoading(null);
    }
  };

  const handleUpdateBranch = async (e: React.FormEvent) => {
    e.preventDefault();
    setActionLoading('update');
    
    try {
      if (editRadiusVal <= 0) {
        throw new Error('يجب أن يكون مدى البصمة (نصف القطر) أكبر من 0 متر');
      }

      const { error } = await supabase
        .from('branches')
        .update({
          name: editBranchName,
          latitude: editLatVal,
          longitude: editLngVal,
          radius_meters: editRadiusVal,
          address: editAddressVal,
        })
        .eq('id', editBranchId);

      if (error) throw error;

      setShowEditModal(false);
      
      // Refresh list
      await fetchBranches();
      
      if (selectedBranchId === editBranchId) {
        setMapCenter([editLatVal, editLngVal]);
      }

      confetti({
        particleCount: 80,
        spread: 60,
        colors: ['#0D9488', '#00FF66']
      });

      toast.success('تم تحديث بيانات الفرع ونطاق البصمة بنجاح! 💾');
    } catch (err: any) {
      toast.error(err.message || 'حدث خطأ غير متوقع');
    } finally {
      setActionLoading(null);
    }
  };

  const getMapCircles = () => {
    return branches
      .filter((b) => b.latitude && b.longitude)
      .map((b) => ({
        id: b.id,
        name: b.name,
        lat: b.latitude,
        lng: b.longitude,
        radius: b.radius_meters || 150
      }));
  };

  if (loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  const mapCircles = getMapCircles();

  return (
    <div className="space-y-8 pb-12">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* Branch zones directory */}
        <div className="lg:col-span-1 bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 flex flex-col justify-between">
          <div className="space-y-6">
            <div className="flex justify-between items-center">
              <div>
                <h3 className="text-sm font-extrabold text-white flex items-center gap-2">
                  <Building className="w-5 h-5 text-teal-400" />
                  <span>الفروع الجغرافية المعتمدة ({branches.length})</span>
                </h3>
                <p className="text-[10px] text-slate-500">إضافة وتعديل فروع الشركة وحدود بصماتها</p>
              </div>
              <button
                onClick={() => {
                  setBranchName('');
                  setLatVal(33.3152);
                  setLngVal(44.3661);
                  setRadiusVal(150);
                  setAddressVal('');
                  setMapUrlInput('');
                  setShowAddModal(true);
                }}
                className="p-2 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer"
                title="إضافة فرع جديد"
              >
                <Plus className="w-4 h-4" />
              </button>
            </div>

            <div className="space-y-4 max-h-[380px] overflow-y-auto pr-1">
              {branches.length === 0 ? (
                <div className="text-center py-8 text-slate-500 text-xs">
                  لم يتم إضافة أي فروع جغرافية للشركة بعد.
                </div>
              ) : (
                branches.map((b) => (
                  <div 
                    key={b.id} 
                    onClick={() => handleSelectBranch(b.id)}
                    className={`p-4 border rounded-2xl flex items-center justify-between transition-all text-right cursor-pointer ${
                      selectedBranchId === b.id 
                        ? 'bg-teal-950/20 border-teal-500/50 shadow-md shadow-teal-500/5' 
                        : 'bg-slate-950/40 border-slate-850 hover:border-slate-800'
                    }`}
                  >
                    <div className="space-y-1 min-w-[65%]">
                      <span className="text-xs font-bold text-white block truncate">{b.name}</span>
                      <span className="text-[10px] text-slate-400 block truncate">{b.address || 'لا يوجد عنوان نصي'}</span>
                      <span className="text-[9px] text-teal-400 block font-mono">
                        مدى البصمة: {b.radius_meters} متر
                      </span>
                    </div>
                    <div className="flex gap-2">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleOpenEditModal(b);
                        }}
                        className="p-2 bg-blue-500/15 border border-blue-500/20 text-blue-400 hover:bg-blue-500/25 rounded-lg transition-colors cursor-pointer"
                        title="تعديل الفرع"
                      >
                        <Edit className="w-4 h-4" />
                      </button>
                      <button
                        disabled={actionLoading === b.id + '_delete'}
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDeleteBranch(b.id);
                        }}
                        className="p-2 bg-red-500/15 border border-red-500/20 text-red-400 hover:bg-red-500/25 rounded-lg transition-colors cursor-pointer"
                        title="حذف الفرع نهائياً"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>

          <div className="pt-6 border-t border-slate-900 mt-6 bg-slate-950/20 p-4 rounded-2xl border border-slate-900">
            <span className="text-[10px] text-slate-400 block leading-relaxed text-right">
              📢 <strong>ملاحظة هامة:</strong> النطاق الجغرافي (مدى البصمة بالامتار) يمثل دائرة قطرها يحيط بموقع الفرع. لن يتمكن الموظف التابع لهذا الفرع من تسجيل حضوره أو انصرافه عبر التطبيق إلا إذا كان متواجداً جغرافياً داخل هذا النطاق وبإنترنت فعال.
            </span>
          </div>
        </div>

        {/* Live Geofence Mapping */}
        <div className="lg:col-span-2 bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col justify-between min-h-[500px]">
          <div className="mb-4">
            <h3 className="text-sm font-extrabold text-white flex items-center gap-1.5">
              <Globe className="w-5 h-5 text-teal-400" />
              <span>مخطط الفروع الجغرافية التفاعلي (Geofence Circles)</span>
            </h3>
            <p className="text-[10px] text-slate-400">انقر على الخريطة لتحديد إحداثيات الفرع وتعبئة الحقول فوراً، أو اضغط على دائرة الفرع لعرض تفاصيلها</p>
          </div>

          <div className="flex-grow relative h-full">
            <MapComponent 
              circles={mapCircles}
              selectedCircleId={selectedBranchId}
              center={mapCenter}
              zoom={mapZoom}
              onCircleClick={handleSelectBranch}
              onMapClick={(lat, lng) => {
                setLatVal(lat);
                setLngVal(lng);
                setShowAddModal(true);
              }}
            />
          </div>
        </div>

      </div>

      {/* Selected Branch details & Employees panel */}
      {selectedBranchId && (() => {
        const branch = branches.find(b => b.id === selectedBranchId);
        if (!branch) return null;
        const attendees = getEmployeesInSelectedBranch();

        return (
          <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 text-right animate-fadeIn">
            <div className="border-b border-slate-800 pb-4">
              <h3 className="text-sm font-extrabold text-white flex items-center gap-2">
                <MapPin className="w-5 h-5 text-teal-400" />
                <span>تفاصيل الفرع المحدد: {branch.name}</span>
              </h3>
              <p className="text-[10px] text-slate-400 mt-1">تأكيد النطاق وتفاصيل التواجد للموظفين داخل المدى الجغرافي حالياً</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
              {/* Branch Stats & Verification */}
              <div className="space-y-4 bg-slate-950/30 p-5 rounded-2xl border border-slate-850 flex flex-col justify-between">
                <div className="space-y-4">
                  <div className="p-3 bg-teal-500/10 border border-teal-500/10 text-teal-350 rounded-xl text-xs flex items-start gap-2">
                    <CheckCircle className="w-4 h-4 text-teal-450 mt-0.5 flex-shrink-0" />
                    <div>
                      <strong className="block text-[11px] text-white">📍 تأكيد الموقع المعتمد (هاي النقطة هنا صايرة)</strong>
                      <span className="text-[10px] opacity-90 leading-relaxed block mt-1">
                        يقع هذا الفرع جغرافياً عند خط عرض <span className="font-mono text-teal-400 font-bold">{branch.latitude}</span> وخط طول <span className="font-mono text-teal-400 font-bold">{branch.longitude}</span>.
                        {branch.address && ` العنوان المعتمد: "${branch.address}".`}
                      </span>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div className="p-3 bg-slate-900/50 rounded-xl border border-slate-800">
                      <span className="text-[10px] text-slate-500 block">نطاق البصمة المسموح</span>
                      <span className="text-xs font-bold text-white mt-1 block font-mono text-teal-400">
                        {branch.radius_meters || 150} متر
                      </span>
                    </div>
                    <div className="p-3 bg-slate-900/50 rounded-xl border border-slate-800">
                      <span className="text-[10px] text-slate-500 block">إجمالي المتواجدين اليوم</span>
                      <span className="text-xs font-bold text-white mt-1 block font-mono text-teal-400">
                        {attendees.length} موظف
                      </span>
                    </div>
                  </div>
                </div>

                <div className="pt-4 border-t border-slate-850 mt-4">
                  <a
                    href={`https://www.google.com/maps/search/?api=1&query=${branch.latitude},${branch.longitude}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="w-full py-2.5 bg-slate-950 hover:bg-slate-900 text-white rounded-xl text-xs font-bold transition-all border border-slate-800 flex items-center justify-center gap-2"
                  >
                    <ExternalLink className="w-3.5 h-3.5 text-teal-400" />
                    <span>عرض النقطة على خرائط جوجل 🌐</span>
                  </a>
                </div>
              </div>

              {/* Employees Checked-in inside this geofence */}
              <div className="space-y-4">
                <h4 className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
                  <Users className="w-4 h-4 text-teal-400" />
                  <span>الموظفون المتواجدون داخل محيط الفرع ({attendees.length})</span>
                </h4>

                <div className="space-y-3 max-h-[220px] overflow-y-auto pr-1">
                  {attendees.length === 0 ? (
                    <div className="text-center py-10 bg-slate-950/20 border border-slate-900 rounded-2xl text-slate-500 text-xs leading-relaxed">
                      لا يوجد أي موظفين قاموا بالتبصيم داخل نطاق هذا الفرع اليوم حتى الآن. 😴
                    </div>
                  ) : (
                    attendees.map((emp) => (
                      <div
                        key={emp.id}
                        className="p-3 bg-slate-950/50 border border-slate-850 hover:border-slate-800 transition-colors rounded-xl flex justify-between items-center text-xs"
                      >
                        <div className="space-y-1">
                          <strong className="text-white block">{emp.name}</strong>
                          <span className="text-[10px] text-slate-500 block">الهاتف: {emp.phone}</span>
                        </div>
                        <div className="text-left space-y-1">
                          <span className="px-2 py-0.5 bg-teal-500/10 border border-teal-500/15 text-teal-400 rounded-md text-[9px] font-bold inline-block">
                            بصم دخول: {emp.checkInTime}
                          </span>
                          <span className="text-[9px] text-slate-400 block font-mono">
                            📍 {emp.distanceText}
                          </span>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          </div>
        );
      })()}

      {/* Add Branch modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
          <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 text-right animate-glass">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-blue-500"></div>
            <h3 className="text-lg font-bold text-white mb-4">🏢 إضافة وتخطيط فرع جغرافي جديد</h3>
            
            <form onSubmit={handleCreateBranch} className="space-y-4">
              <div>
                <label className="block text-xs text-slate-400 mb-1">اسم الفرع الجغرافي الجديد</label>
                <input
                  type="text"
                  required
                  value={branchName}
                  onChange={(e) => setBranchName(e.target.value)}
                  placeholder="فرع المنصور - مكتب الأثاث"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center justify-between">
                  <span className={`text-[10px] font-bold transition-colors ${resolvingUrl ? 'text-yellow-400 animate-pulse' : 'text-teal-400'}`}>
                    {resolvingUrl ? 'جاري الاستخراج وفك التشفير... ⚡' : 'استخراج تلقائي ⚡'}
                  </span>
                  <span>رابط موقع جوجل ماب أو خطوط العرض والطول السريعة</span>
                </label>
                <input
                  type="text"
                  value={mapUrlInput}
                  disabled={resolvingUrl}
                  onChange={(e) => handleMapUrlChange(e.target.value)}
                  placeholder={resolvingUrl ? "الرجاء الانتظار جاري استخراج الاحداثيات..." : "الصق رابط موقع جوجل ماب أو خطوط العرض والطول هنا (مثال: 33.3152, 44.3661)"}
                  className={`w-full bg-slate-950 border rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none transition-all ${resolvingUrl ? 'border-yellow-500/50 opacity-70 cursor-wait' : 'border-slate-800'}`}
                />
                <span className="text-[9px] text-slate-500 block mt-1">
                  * انسخ الرابط من خرائط جوجل والصقه هنا، وسيقوم النظام بملء حقلي خط الطول والعرض تلقائياً وبدقة!
                </span>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 block text-right">إحداثي خط العرض (Latitude)</label>
                  <input
                    type="number"
                    step="0.000000001"
                    required
                    value={latVal}
                    onChange={(e) => setLatVal(Number(e.target.value))}
                    placeholder="33.3152"
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                    dir="ltr"
                  />
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 block text-right">إحداثي خط الطول (Longitude)</label>
                  <input
                    type="number"
                    step="0.000000001"
                    required
                    value={lngVal}
                    onChange={(e) => setLngVal(Number(e.target.value))}
                    placeholder="44.3661"
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">مدى البصمة الجغرافية المعتمد بالامتار (Radius in Meters)</label>
                <input
                  type="number"
                  required
                  value={radiusVal}
                  onChange={(e) => setRadiusVal(Number(e.target.value))}
                  placeholder="150"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">العنوان أو الوصف النصي للفرع (اختياري)</label>
                <textarea
                  value={addressVal}
                  onChange={(e) => setAddressVal(e.target.value)}
                  placeholder="مثال: بغداد، شارع المنصور، مجاور مول المنصور، الطابق الثاني"
                  rows={2}
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none resize-none"
                />
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
                  disabled={actionLoading === 'create'}
                  className="px-5 py-2.5 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/20 cursor-pointer flex items-center gap-1.5"
                >
                  {actionLoading === 'create' ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>جاري الحفظ والإنشاء...</span>
                    </>
                  ) : (
                    <span>تثبيت الفرع الجغرافي 🎯</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Branch modal */}
      {showEditModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
          <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 text-right animate-glass">
            <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-blue-500 to-teal-500"></div>
            <h3 className="text-lg font-bold text-white mb-4">✏️ تعديل بيانات الفرع الجغرافي ونطاق البصمة</h3>
            
            <form onSubmit={handleUpdateBranch} className="space-y-4">
              <div>
                <label className="block text-xs text-slate-400 mb-1">اسم الفرع الجغرافي</label>
                <input
                  type="text"
                  required
                  value={editBranchName}
                  onChange={(e) => setEditBranchName(e.target.value)}
                  placeholder="مثال: فرع الكرادة الرئيسي"
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1 flex items-center justify-between">
                  <span className={`text-[10px] font-bold transition-colors ${editResolvingUrl ? 'text-yellow-400 animate-pulse' : 'text-teal-400'}`}>
                    {editResolvingUrl ? 'جاري الاستخراج وفك التشفير... ⚡' : 'استخراج تلقائي ⚡'}
                  </span>
                  <span>رابط موقع جوجل ماب أو خطوط العرض والطول السريعة</span>
                </label>
                <input
                  type="text"
                  value={editMapUrlInput}
                  disabled={editResolvingUrl}
                  onChange={(e) => handleEditMapUrlChange(e.target.value)}
                  placeholder={editResolvingUrl ? "الرجاء الانتظار جاري استخراج الاحداثيات..." : "الصق رابط موقع جوجل ماب أو خطوط العرض والطول هنا لتحديث الإحداثيات تلقائياً"}
                  className={`w-full bg-slate-950 border rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none transition-all ${editResolvingUrl ? 'border-yellow-500/50 opacity-70 cursor-wait' : 'border-slate-800'}`}
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs text-slate-400 mb-1 block text-right">إحداثي خط العرض (Latitude)</label>
                  <input
                    type="number"
                    step="0.000000001"
                    required
                    value={editLatVal}
                    onChange={(e) => setEditLatVal(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                    dir="ltr"
                  />
                </div>

                <div>
                  <label className="block text-xs text-slate-400 mb-1 block text-right">إحداثي خط الطول (Longitude)</label>
                  <input
                    type="number"
                    step="0.000000001"
                    required
                    value={editLngVal}
                    onChange={(e) => setEditLngVal(Number(e.target.value))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                    dir="ltr"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">مدى البصمة الجغرافية المعتمد بالامتار (Radius in Meters)</label>
                <input
                  type="number"
                  required
                  value={editRadiusVal}
                  onChange={(e) => setEditRadiusVal(Number(e.target.value))}
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                  dir="ltr"
                />
              </div>

              <div>
                <label className="block text-xs text-slate-400 mb-1">العنوان أو الوصف النصي للفرع (اختياري)</label>
                <textarea
                  value={editAddressVal}
                  onChange={(e) => setEditAddressVal(e.target.value)}
                  placeholder="مثال: بغداد، الكرادة، قرب ساحة التحريات"
                  rows={2}
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none resize-none"
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800/80">
                <button
                  type="button"
                  onClick={() => setShowEditModal(false)}
                  className="px-4 py-2 text-xs text-slate-400 hover:text-white"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={actionLoading === 'update'}
                  className="px-5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-blue-500/20 cursor-pointer flex items-center gap-1.5"
                >
                  {actionLoading === 'update' ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>جاري التحديث...</span>
                    </>
                  ) : (
                    <span>تحديث وحفظ الفرع 💾</span>
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
