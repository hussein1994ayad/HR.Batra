import { useState } from 'react';
import { Clock, Download, LogOut, Pencil, ShieldCheck } from 'lucide-react';
import { Avatar, Badge, Button, Card, CardHeader, DataTable, IconButton, TableEmpty } from '@/components/ui';
import { formatClock } from '@/lib/format';
import { formatHours, needsOfflineReview, punchTimeInfo } from '../logic';
import { getLocalDateStr } from '@/lib/dates';

const todayLocal = () => getLocalDateStr(new Date());
import type { AttendanceRow } from '../types';

type Props = {
  attendanceRows: AttendanceRow[];
  busyKey?: string | null;
  onExport: () => void;
  onEdit: (row: AttendanceRow) => void;
  onForceCheckout: (recordId: string) => void;
  /** «تمت المراجعة» لبصمة بدون إنترنت تحتاج مراجعة */
  onReview: (recordId: string) => void;
};

/** شلون انسجل الوقت: بدون إنترنت (وفرق ساعة الموبايل)، يحتاج مراجعة، تمت المراجعة، أو يدوي. */
function TimeSourceBadge({ time, source, deviceTime }: { time?: string | null; source?: string | null; deviceTime?: string | null }) {
  const info = punchTimeInfo(time, source, deviceTime);
  if (!info) return null;
  const clock = info.clockDiffMinutes !== null && info.clockDiffMinutes >= 2 && deviceTime
    ? ` · ساعة الموبايل ${formatClock(deviceTime)}` : '';
  if (info.kind === 'review') return <Badge tone="amber">بدون إنترنت · تحتاج مراجعة{clock}</Badge>;
  if (info.kind === 'reviewed') return <Badge tone="slate">بدون إنترنت · تمت المراجعة{clock}</Badge>;
  if (info.kind === 'manual') return <Badge tone="slate">يدوي</Badge>;
  return <Badge tone={clock ? 'amber' : 'sky'}>بدون إنترنت{clock}</Badge>;
}

function StatusBadge({ row }: { row: AttendanceRow }) {
  if (row.is_virtual) return <Badge tone="rose">لم يبصم</Badge>;
  if (row.on_leave) return <Badge tone="sky" dot>إجازة</Badge>;
  if (row.status === 'late') return <Badge tone="amber" dot>متأخر</Badge>;
  if (row.status === 'absent') return <Badge tone="rose" dot>غائب</Badge>;
  if (row.status === 'half_day') return <Badge tone="violet" dot>نصف يوم</Badge>;
  return <Badge tone="emerald" dot>حاضر</Badge>;
}

/** جدول سجلات الحضور للفترة المختارة (مع الغائبين بلا بصمة). */
export function AttendanceLogTable({ attendanceRows, busyKey, onExport, onEdit, onForceCheckout, onReview }: Props) {
  // بصمات بدون إنترنت وقتها من ساعة الموبايل: الإدارة تراجعها (تدقيق 14/10 FEATURE-004)
  const toReview = attendanceRows.filter((r) => !r.is_virtual && needsOfflineReview(r));
  const [reviewOnly, setReviewOnly] = useState(false);
  const rows = reviewOnly ? toReview : attendanceRows;
  return (
    <Card>
      <CardHeader
        icon={Clock}
        tone="emerald"
        title="سجل الحضور والانصراف"
        description="البصمات المسجلة للفترة المختارة، مع الموظفين الذين لم يبصموا في أيام دوامهم"
        actions={
          <div className="flex flex-wrap gap-2">
            {(toReview.length > 0 || reviewOnly) && (
              <Button size="sm" variant={reviewOnly ? 'primary' : 'warning'} icon={ShieldCheck} onClick={() => setReviewOnly((v) => !v)}>
                {reviewOnly ? 'كل السجلات' : `${toReview.length} بصمة بدون إنترنت تحتاج مراجعة`}
              </Button>
            )}
            <Button size="sm" variant="soft-success" icon={Download} onClick={onExport}>
              تصدير كشف الانضباط Excel
            </Button>
          </div>
        }
      />
      <DataTable>
        <thead>
          <tr>
            <th>الموظف</th>
            <th>التاريخ</th>
            <th>الحالة</th>
            <th>الدخول</th>
            <th>الخروج</th>
            <th>ساعات العمل</th>
            <th className="!text-left">الإجراءات</th>
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <TableEmpty colSpan={7}>لا توجد سجلات حضور لهذه الفترة</TableEmpty>
          ) : (
            rows.map((log) => (
              <tr key={log.id} className={log.is_virtual ? 'bg-rose-500/[0.03]' : undefined}>
                <td>
                  <div className="flex items-center gap-2.5">
                    <Avatar name={log.employees?.full_name} size="sm" />
                    <span className="font-bold text-white">{log.employees?.full_name || 'موظف'}</span>
                  </div>
                </td>
                <td className="font-mono text-slate-400" dir="ltr">{log.work_date}</td>
                <td><StatusBadge row={log} /></td>
                <td className="font-mono text-emerald-300" dir="ltr">
                  {log.check_in_time ? formatClock(log.check_in_time) : '-'}
                  <div dir="rtl"><TimeSourceBadge time={log.check_in_time} source={log.check_in_time_source} deviceTime={log.check_in_device_time} /></div>
                </td>
                <td className="font-mono text-slate-300" dir="ltr">
                  {log.check_out_time
                    ? formatClock(log.check_out_time)
                    : log.check_in_time
                      ? (log.work_date < todayLocal() ? <Badge tone="amber">بدون انصراف</Badge> : <Badge tone="sky">داخل الدوام</Badge>)
                      : '-'}
                  <div dir="rtl"><TimeSourceBadge time={log.check_out_time} source={log.check_out_time_source} deviceTime={log.check_out_device_time} /></div>
                </td>
                <td className="font-bold text-slate-200">{formatHours(log.check_in_time, log.check_out_time)}</td>
                <td className="!text-left">
                  {!log.is_virtual && (
                    <div className="flex justify-end gap-1.5">
                      {needsOfflineReview(log) && (
                        <IconButton
                          icon={ShieldCheck}
                          label="تمت المراجعة (وقت البصمة من ساعة الموبايل)"
                          tone="amber"
                          loading={busyKey === `review_${log.id}`}
                          onClick={() => onReview(log.id)}
                        />
                      )}
                      <IconButton icon={Pencil} label="تعديل أوقات الدخول والخروج" tone="indigo" onClick={() => onEdit(log)} />
                      {log.check_in_time && !log.check_out_time && (
                        <IconButton
                          icon={LogOut}
                          label="تسجيل خروج الآن"
                          tone="rose"
                          loading={busyKey === `checkout_${log.id}`}
                          onClick={() => onForceCheckout(log.id)}
                        />
                      )}
                    </div>
                  )}
                </td>
              </tr>
            ))
          )}
        </tbody>
      </DataTable>
    </Card>
  );
}
