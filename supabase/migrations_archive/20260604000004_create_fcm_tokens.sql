-- ==========================================
-- جدول رموز FCM للإشعارات الخارجية للهاتف
-- ==========================================

CREATE TABLE IF NOT EXISTS fcm_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  device_platform TEXT DEFAULT 'android',  -- 'android' | 'ios'
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employee_id, token)
);

-- RLS: كل موظف يرى ويعدّل رمزه فقط
ALTER TABLE fcm_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Employee can manage own FCM token"
  ON fcm_tokens FOR ALL
  USING (employee_id = auth.uid())
  WITH CHECK (employee_id = auth.uid());

-- Index للبحث السريع عند إرسال الإشعارات
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_employee_id ON fcm_tokens(employee_id);
