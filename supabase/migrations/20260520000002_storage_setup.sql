-- ==========================================
-- نظام HR Pro v6.0 - تهيئة مجلدات التخزين (Storage Buckets)
-- ==========================================

-- 1. إدراج المجلدات في جدول مجلدات التخزين الخاص بـ Supabase
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  (
    'avatars', 
    'avatars', 
    true, 
    1048576, 
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  ), -- 1 ميجابايت للصور الشخصية، وهي عامة
  (
    'documents', 
    'documents', 
    false, 
    10485760, 
    NULL
  ), -- 10 ميجابايت للمستندات والملفات (خاصة ومحمية)
  (
    'loan-pledges', 
    'loan-pledges', 
    false, 
    2097152, 
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  ), -- 2 ميجابايت لتعهد السلفة (خاصة ومحمية)
  (
    'company-logos', 
    'company-logos', 
    true, 
    2097152, 
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  ), -- 2 ميجابايت لشعار الشركة، وهو عام
  (
    'ota-updates', 
    'ota-updates', 
    true, 
    104857600, 
    ARRAY['application/vnd.android.package-archive', 'application/octet-stream']
  ) -- 100 ميجابايت لملفات التحديثات OTA، وهي عامة
ON CONFLICT (id) DO UPDATE SET 
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. سياسات حماية ملفات التخزين (Storage RLS Policies)

-- حذف السياسات القديمة إذا وجدت لتجنب التكرار
DROP POLICY IF EXISTS "Avatars are public" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Admins can manage documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can view own documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can upload own documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can upload loan pledges" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view and manage loan pledges" ON storage.objects;
DROP POLICY IF EXISTS "Logos are public" ON storage.objects;
DROP POLICY IF EXISTS "Only admins can manage company logos" ON storage.objects;
DROP POLICY IF EXISTS "OTA updates are public" ON storage.objects;
DROP POLICY IF EXISTS "Only admins can upload OTA updates" ON storage.objects;

-- سياسات الصور الشخصية (avatars)
CREATE POLICY "Avatars are public" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated users can upload avatars" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "Users can update their own avatars" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'avatars');

-- سياسات الوثائق الرسمية والمستندات (documents)
CREATE POLICY "Admins can manage documents" ON storage.objects
  TO authenticated USING (bucket_id = 'documents' AND is_admin());

CREATE POLICY "Employees can view own documents" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'documents' AND (owner = auth.uid() OR is_admin()));

CREATE POLICY "Employees can upload own documents" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'documents' AND (owner = auth.uid() OR is_admin()));

-- سياسات تعهد السلف (loan-pledges)
CREATE POLICY "Employees can upload loan pledges" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'loan-pledges' AND owner = auth.uid());

CREATE POLICY "Admins can view and manage loan pledges" ON storage.objects
  TO authenticated USING (bucket_id = 'loan-pledges' AND is_admin());

-- سياسات شعار الشركة (company-logos)
CREATE POLICY "Logos are public" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'company-logos');

CREATE POLICY "Only admins can manage company logos" ON storage.objects
  TO authenticated USING (bucket_id = 'company-logos' AND is_admin())
  WITH CHECK (bucket_id = 'company-logos' AND is_admin());

-- سياسات ملفات التحديث اليدوي (ota-updates)
CREATE POLICY "OTA updates are public" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'ota-updates');

CREATE POLICY "Only admins can upload OTA updates" ON storage.objects
  TO authenticated USING (bucket_id = 'ota-updates' AND is_admin())
  WITH CHECK (bucket_id = 'ota-updates' AND is_admin());
