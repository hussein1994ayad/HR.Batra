# Migration Naming Convention — HR.Batra

## Format

```
YYYYMMDDHHMMSS_<verb>_<scope>_<subject>.sql
```

- **YYYYMMDDHHMMSS** — timestamp (UTC), determines execution order
- **verb** — one of: `add`, `alter`, `create`, `drop`, `fix`, `refactor`, `seed`, `document`, `enable`, `disable`
- **scope** — the thing being changed: `employees`, `leaves`, `rls`, `storage`, `rpcs`, `indexes`
- **subject** — short specific description in snake_case

## Rules

1. Keep the whole filename **≤ 60 characters** for readability
2. One migration = one atomic change (or a tightly related set)
3. Every migration MUST be idempotent (`IF NOT EXISTS`, `DROP … IF EXISTS`, `ON CONFLICT DO …`)
4. Comment header at the top: date, purpose, related issue/audit-point
5. Never edit an already-applied migration — create a new one instead

## Examples ✅

```
20260920000000_add_audit_log_infrastructure.sql
20260920000100_document_rpcs_with_comments.sql
20260921000000_create_view_attendance_with_employee.sql
20260922000000_enable_rls_on_bonuses_deductions.sql
20260923000000_fix_loan_installments_trigger.sql
```

## Anti-patterns ❌

```
20260604000002_update_notifications_type_constraint.sql   ← too verbose
20260629000000_loan_repayment_trigger.sql                 ← missing verb
20260821000000_comprehensive_audit_fixes.sql              ← "comprehensive" is not a scope
```

## Header template

```sql
-- =========================================================================
-- HR Pro v6.0 - <one-line purpose>
-- Date: 2026-MM-DD
-- Related: audit point N | issue #N | none
-- =========================================================================
--
-- What this migration does:
--   • ...
--   • ...
--
-- Rollback: see the paired `_revert_` migration or manual steps in header.
-- =========================================================================
```
