const employees = [{id: 1, branch_id: 'b1'}, {id: 2, branch_id: 'b1'}];
const selectedBranch = 'all';
const attendanceLogs = [];
const workSchedules = [];
const selectedDate = "2026-06-06";
const leaveRequests = [];

const getLocalDateStr = () => {
  const d = new Date();
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().split('T')[0];
};

const getDecisionsList = () => {
  const list = [];
  employees.forEach(emp => {
    if (selectedBranch !== 'all' && emp.branch_id !== selectedBranch) return;

    const attRecord = attendanceLogs.find(log => log.employee_id === emp.id);

    const empSched = workSchedules.find(s => s.employee_id === emp.id) || 
                     workSchedules.find(s => s.department_id === emp.department_id && !s.employee_id);
    const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];
    
    const dayObj = new Date(selectedDate);
    const weekday = dayObj.getDay();
    const isWorkingDay = workDays.includes(weekday);

    const isDateWithinRange = (dStr, startStr, endStr) => {
      const d = new Date(dStr).getTime();
      const s = new Date(startStr.split('T')[0]).getTime();
      const e = new Date(endStr.split('T')[0]).getTime();
      return d >= s && d <= e;
    };

    const leaveRecord = leaveRequests.find(l => l.employee_id === emp.id && isDateWithinRange(selectedDate, l.start_date, l.end_date));

    if (attRecord) {
      //
    } else {
      if (isWorkingDay && !leaveRecord) {
        const todayStr = getLocalDateStr();
        const isPastOrToday = selectedDate <= todayStr;

        if (isPastOrToday) {
          list.push({
            id: null,
            type: 'virtual_absent',
          });
        }
      }
    }
  });
  return list;
};

console.log("Result:", getDecisionsList());
