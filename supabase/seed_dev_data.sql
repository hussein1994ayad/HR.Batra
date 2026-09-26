-- =========================================================================
-- HR Pro v6.0 - Development Seed Data
-- Related: audit point 31
-- =========================================================================
--
-- Purpose: to give any new developer a working local database in one command:
--   psql "$SUPABASE_DB_URL" -f supabase/seed_dev_data.sql
--
-- ⚠️  DO NOT run against production. This clears and repopulates
--     branches / departments / a demo employee row.
--
-- =========================================================================


-- =====================================================================
-- 1) Branches
-- =====================================================================
INSERT INTO branches (id, name, latitude, longitude, radius_meters, address)
VALUES
    ('11111111-1111-1111-1111-111111111111'::uuid,
     'القناة',       33.310000, 44.410000, 100, 'شارع القناة، بغداد'),
    ('11111111-1111-1111-1111-111111111112'::uuid,
     'العكد',         33.320000, 44.420000, 100, 'حي العكد، بغداد'),
    ('11111111-1111-1111-1111-111111111113'::uuid,
     'كمب سارة',       33.330000, 44.430000, 120, 'كمب سارة، بغداد'),
    ('11111111-1111-1111-1111-111111111114'::uuid,
     'بغداد الجديدة', 33.340000, 44.440000, 100, 'بغداد الجديدة، بغداد')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    radius_meters = EXCLUDED.radius_meters,
    address = EXCLUDED.address;


-- =====================================================================
-- 2) Departments
-- =====================================================================
INSERT INTO departments (id, name)
VALUES
    ('22222222-2222-2222-2222-222222222221'::uuid, 'المحاسبة'),
    ('22222222-2222-2222-2222-222222222222'::uuid, 'الموارد البشرية'),
    ('22222222-2222-2222-2222-222222222223'::uuid, 'التسويق'),
    ('22222222-2222-2222-2222-222222222224'::uuid, 'خدمة العملاء'),
    ('22222222-2222-2222-2222-222222222225'::uuid, 'تقنية المعلومات')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;


-- =====================================================================
-- 3) Company settings (one row)
-- =====================================================================
INSERT INTO company_settings (id, name, phone, email, website, tax_number, address)
VALUES
    ('33333333-3333-3333-3333-333333333333'::uuid,
     'شركة Batra للتطوير',
     '+964-XXX-XXX-XXXX',
     'info@batra.iq',
     'https://batra.iq',
     'TAX-DEV-DEMO',
     'بغداد، العراق')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    phone = EXCLUDED.phone;


-- =====================================================================
-- 4) Sample announcement (visible to all employees)
-- =====================================================================
INSERT INTO announcements (title, content, is_pinned)
VALUES
    ('مرحباً بك في نظام HR Pro',
     'هذه بيئة تجريبية. جميع البيانات هنا وهمية لأغراض التطوير.',
     true)
ON CONFLICT DO NOTHING;


-- =====================================================================
-- 5) Notes
-- =====================================================================
--
-- Employees table is not seeded here because rows there must correspond
-- to auth.users. To create a demo employee:
--   1. Sign up an auth user (via Supabase dashboard or app)
--   2. Get the UUID from auth.users
--   3. Run:
--      INSERT INTO employees (id, employee_code, full_name, email,
--          department_id, branch_id, role, is_active, must_change_password)
--      VALUES (
--        '<auth-user-uuid>', 'EMP001', 'موظف تجريبي',
--        'demo@example.com',
--        '22222222-2222-2222-2222-222222222221',
--        '11111111-1111-1111-1111-111111111111',
--        'employee', true, false
--      );
-- =========================================================================
