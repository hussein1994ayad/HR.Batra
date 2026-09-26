-- Minimal Supabase platform stubs so the repo migrations can run on PGlite.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

CREATE SCHEMA auth;
CREATE SCHEMA storage;
CREATE SCHEMA extensions;
CREATE SCHEMA cron;
CREATE SCHEMA net;

CREATE TABLE auth.users (
  instance_id uuid, id uuid PRIMARY KEY, aud text, role text, email text,
  encrypted_password text, email_confirmed_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  is_super_admin boolean, is_sso_user boolean, is_anonymous boolean,
  phone text, phone_confirmed_at timestamptz,
  created_at timestamptz, updated_at timestamptz
);
CREATE TABLE auth.identities (
  id uuid PRIMARY KEY, provider_id text, user_id uuid, identity_data jsonb,
  provider text, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz
);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.role', true), '')::text $$;

CREATE TABLE storage.buckets (
  id text PRIMARY KEY, name text, public boolean, file_size_limit bigint,
  allowed_mime_types text[], created_at timestamptz DEFAULT now()
);
CREATE TABLE storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text, name text,
  owner uuid, metadata jsonb, created_at timestamptz DEFAULT now(), updated_at timestamptz
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS
$$ SELECT (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;

CREATE FUNCTION extensions.gen_salt(text) RETURNS text LANGUAGE sql AS $$ SELECT 'salt' $$;
CREATE FUNCTION extensions.crypt(text, text) RETURNS text LANGUAGE sql AS $$ SELECT md5($1) $$;

CREATE FUNCTION cron.schedule(text, text, text) RETURNS bigint LANGUAGE sql AS $$ SELECT 1::bigint $$;
CREATE FUNCTION cron.unschedule(text) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE TABLE cron.job (jobid bigint, jobname text);
CREATE FUNCTION net.http_post(url text, headers jsonb DEFAULT '{}', body jsonb DEFAULT '{}') RETURNS bigint
  LANGUAGE sql AS $$ SELECT 1::bigint $$;

CREATE PUBLICATION supabase_realtime;

GRANT USAGE ON SCHEMA public, auth, storage TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth, storage TO anon, authenticated, service_role;
