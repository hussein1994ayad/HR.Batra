import { Clock, Download, LogOut, Pencil } from 'lucide-react';
import { Avatar, Badge, Button, Card, CardHeader, DataTable, IconButton, TableEmpty } from '@/components/ui';
import { formatClock } from '@/lib/format';
import { formatHours } from '../logic';
import type { AttendanceRow } from '../types';

type Props = {
  attendanceRows: AttendanceRow[];
  busyKey?: string | null;
  onExport: () => void;
  onEdit: (row: AttendanceRow) => void;
  onForceCheckout: (recordId: string) => void;
};

function StatusBadge({ row }: { row: AttendanceRow }) {
  if (row.is_virtual) return <Badge tone="rose">لم يبصم</Badge>;
  if (row.status === 'late') return <Badge tone="amber" dot>متأخر</Badge>;
  if (row.status === 'absent') return <Badge tone="rose" dot>غائب</Badge>;
  if (row.status === 'half_day') return <Badge tone="violet" dot>نصف يوم</Badge>;
  return <Badge tone="emerald" dot>حاضر</Badge>;
}

/** جدول سجلات الحضور للفترة المختارة (مع الغائبين بلا بصمة). */
export function AttendanceLogTable({ attendanceRows, busyKey, onExport, onEdit, onForceCheckout }: Props) {
  return (
    <Card>
      <CardHeader
        icon={Clock}
        tone="emerald"
        title="سجل الحضور والانصراف"
        description="البصمات المسجلة للفترة المختارة، مع الموظفين الذين لم يبصموا في أيام دوامهم"
        actions={
          <Button size="sm" variant="soft-success" icon={Download} onClick={onExport}>
            تصدير كشف الانضباط Excel
          </Button>
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
          {attendanceRows.length === 0 ? (
            <TableEmpty colSpan={7}>لا توجد سجلات حضور لهذه الفترة</TableEmpty>
          ) : (
            attendanceRows.map((log) => (
              <tr key={log.id} className={log.is_virtual ? 'bg-rose-500/[0.03]' : undefined}>
                <td>
                  <div className="flex items-center gap-2.5">
                    <Avatar name={log.employees?.full_name} size="sm" />
                    <span className="font-bold text-white">{log.employees?.full_name || 'موظف'}</span>
                  </div>
                </td>
                <td className="font-mono text-slate-400" dir="ltr">{log.work_date}</td>
                <td><StatusBadge row={log} /></td>
                <td className="font-mono text-emerald-300" dir="ltr">{log.check_in_time ? formatClock(log.check_in_time) : '-'}</td>
                <td className="font-mono text-slate-300" dir="ltr">
                  {log.check_out_time ? formatClock(log.check_out_time) : log.check_in_time ? <Badge tone="sky">داخل الدوام</Badge> : '-'}
                </td>
                <td className="font-bold text-slate-200">{formatHours(log.check_in_time, log.check_out_time)}</td>
                <td className="!text-left">
                  {!log.is_virtual && (
                    <div className="flex justify-end gap-1.5">
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
