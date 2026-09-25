# HR Pro — Web Dashboard

Admin dashboard for HR Pro (Next.js 16, static export, Supabase). It is deployed as static files to
[hrpro-batra.surge.sh](https://hrpro-batra.surge.sh/dashboard).

## Development

```bash
npm ci
npm run dev          # http://localhost:3000
```

## Checks

| Command              | What it does                                                        |
| -------------------- | ------------------------------------------------------------------- |
| `npm run lint`       | ESLint (Next.js + TypeScript rules)                                 |
| `npm run typecheck`  | TypeScript type check                                               |
| `npm run test:unit`  | Vitest unit tests for payroll, attendance, geo and format helpers   |
| `npm run build`      | Static export to `out/`                                             |
| `npm run test:e2e`   | Playwright tests against `out/` with a mocked Supabase API          |
| `npm run check`      | lint + typecheck + unit tests                                       |

End-to-end tests need a build first (`npm run build`) and a Chromium browser
(`npx playwright install chromium`). To reuse an existing Chromium binary set
`PW_CHROMIUM_PATH=/path/to/chrome`.

## Project layout

- `src/app/dashboard/*` — dashboard pages
- `src/components/ui.tsx` — shared UI kit (cards, buttons, form fields, tables, modals…)
- `src/components/confirm.tsx` — promise-based confirmation dialog (`useConfirm`)
- `src/lib/payroll.ts`, `src/lib/attendance.ts` — pure salary/attendance calculations (unit tested)
- `src/lib/useQuery.ts` — small data-fetching hook with cache-first rendering

## Deployment

The `Web Dashboard` GitHub Actions workflow (`.github/workflows/web.yml`) runs lint, type check,
unit tests, the build and the e2e tests on every pull request. On pushes to `main` it also
publishes `out/` to `hrpro-batra.surge.sh` when the repository secret `SURGE_TOKEN` is set
(generate one locally with `npx surge token`).

Manual deploy:

```bash
npm run build
npx surge ./out hrpro-batra.surge.sh
```
