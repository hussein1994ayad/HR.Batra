'use client';

import React, { useState } from 'react';
import type { BranchInput } from '../api';
import { resolveMapUrl } from '../mapUrl';
import { Loader2 } from 'lucide-react';

interface BranchFormModalProps {
  mode: 'create' | 'edit';
  initial: BranchInput;
  saving: boolean;
  onClose: () => void;
  onSubmit: (input: BranchInput) => void;
}

/** إضافة فرع أو تعديله، مع استخراج الإحداثيات من رابط خرائط جوجل. */
export function BranchFormModal({ mode, initial, saving, onClose, onSubmit }: BranchFormModalProps) {
  const isEdit = mode === 'edit';
  const [branchName, setBranchName] = useState(initial.name);
  const [latVal, setLatVal] = useState<number>(initial.latitude);
  const [lngVal, setLngVal] = useState<number>(initial.longitude);
  const [radiusVal, setRadiusVal] = useState<number>(initial.radius_meters);
  const [addressVal, setAddressVal] = useState<string>(initial.address ?? '');
  const [mapUrlInput, setMapUrlInput] = useState('');
  const [resolvingUrl, setResolvingUrl] = useState(false);

  const handleMapUrlChange = async (value: string) => {
    setMapUrlInput(value);
    if (!value) return;
    setResolvingUrl(true);
    try {
      const coords = await resolveMapUrl(value);
      if (coords) {
        setLatVal(coords.lat);
        setLngVal(coords.lng);
      }
    } catch (err) {
      console.error('Error resolving map url:', err);
    } finally {
      setResolvingUrl(false);
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({ name: branchName, latitude: latVal, longitude: lngVal, radius_meters: radiusVal, address: addressVal });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 text-right animate-glass">
        <div className={`absolute top-0 inset-x-0 h-1 bg-gradient-to-r ${isEdit ? 'from-blue-500 to-teal-500' : 'from-teal-500 to-blue-500'}`}></div>
        <h3 className="text-lg font-bold text-white mb-4">{isEdit ? '✏️ تعديل بيانات الفرع الجغرافي ونطاق البصمة' : '🏢 إضافة وتخطيط فرع جغرافي جديد'}</h3>
        
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs text-slate-400 mb-1">{isEdit ? 'اسم الفرع الجغرافي' : 'اسم الفرع الجغرافي الجديد'}</label>
            <input
              type="text"
              required
              value={branchName}
              onChange={(e) => setBranchName(e.target.value)}
              placeholder={isEdit ? 'مثال: فرع الكرادة الرئيسي' : 'فرع المنصور - مكتب الأثاث'}
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
              onClick={onClose}
              className="px-4 py-2 text-xs text-slate-400 hover:text-white"
            >
              إلغاء
            </button>
            <button
              type="submit"
              disabled={saving}
              className={`px-5 py-2.5 text-white rounded-xl text-xs font-bold transition-all shadow-md cursor-pointer flex items-center gap-1.5 ${isEdit ? 'bg-blue-600 hover:bg-blue-500 shadow-blue-500/20' : 'bg-teal-650 hover:bg-teal-600 shadow-teal-500/20'}`}
            >
              {saving ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>{isEdit ? 'جاري التحديث...' : 'جاري الحفظ والإنشاء...'}</span>
                </>
              ) : (
                <span>{isEdit ? 'تحديث وحفظ الفرع 💾' : 'تثبيت الفرع الجغرافي 🎯'}</span>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
