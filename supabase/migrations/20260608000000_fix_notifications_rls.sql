-- ==========================================
-- إصلاح سياسات الحماية (RLS) لجدول الإشعارات
-- ==========================================

-- حذف السياسة القديمة التي كانت تمنع إرسال الإشعارات للآخرين
DROP POLICY IF EXISTS "Employees can view and update their own notifications" ON notifications;

-- 1. السماح لأي مستخدم مسجل الدخول بإدراج الإشعارات (لأن الموظف يحتاج إرسال إشعار للمدير والمدير للموظف)
CREATE POLICY "Anyone can insert notifications"
ON notifications FOR INSERT TO authenticated
WITH CHECK (true);

-- 2. السماح للموظف برؤية الإشعارات الخاصة به فقط (أو المدير يرى كل شيء إذا أردنا، لكن الإشعار يرسل لمعرف محدد)
CREATE POLICY "Employees can view their own notifications"
ON notifications FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin());

-- 3. السماح للموظف بتحديث حالة الإشعارات الخاصة به (مثل قراءتها)
CREATE POLICY "Employees can update their own notifications"
ON notifications FOR UPDATE TO authenticated
USING (employee_id = auth.uid());
