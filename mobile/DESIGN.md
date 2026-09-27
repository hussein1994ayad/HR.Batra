# HR Pro — Design system (design-v2)

Dark-only, calm and consistent. Every screen takes its colors, spacing, type and
components from one place. **Do not write `Color(0x…)`, `Colors.white…`, font
sizes or radii directly in screens.**

```dart
import '../shared/ui/ui.dart'; // tokens + components in one import
```

## 1. Tokens — `lib/core/design/`

| File | What |
|---|---|
| `app_colors.dart` | `AppColors` (bg, surface1–3, border, text, brand, status colors) and `AppTone` (color + light container) |
| `app_tokens.dart` | `AppSpace` (4pt grid, `touch` = 48), `AppRadius`, `AppElevation`, `AppMotion` (150–300 ms, respects *reduce motion*), `AppBreakpoints` / `WindowSize` |
| `app_typography.dart` | `AppText` — Cairo (bundled, no network) with comfortable Arabic line heights; `AppText.number` uses tabular figures |
| `formatters.dart` | `Fmt.iqd(1500000)` → `1.500.000 د.ع`, `Fmt.time`, `Fmt.timeOfDay('08:00:00')` → `8:00 ص`, `Fmt.date`, `Fmt.dateWithDay`, `Fmt.relative` → `قبل 5 دقائق`, `Fmt.days`, `Fmt.monthCount`, `Fmt.greeting` |
| `app_haptics.dart` | `AppHaptics.success / submit / error / select` |

### Colors
- Surfaces step up in lightness: `bg` → `surface1` (cards) → `surface2` (inputs, raised) → `surface3` (menus, snackbars).
- Text: `textPrimary`, `textSecondary`, `textMuted`, `textDisabled`.
- Status: `success`, `warning`, `danger`, `info`, plus `accent` for admin/secondary categories. Each has a `…Container` for soft backgrounds.
- All text colors pass **WCAG AA (≥ 4.5:1)** on `bg`, `surface1`, `surface2` and their own containers — enforced by `test/unit/theme_test.dart`.
- Text on a filled status color uses `AppColors.onStatus`; on brand uses `AppColors.onBrand`.

### Motion
Use `AppMotion.of(context, AppMotion.normal)` for durations — it returns zero when the
user enabled *reduce motion*.

## 2. Components — `lib/presentation/shared/ui/`

| Component | Use |
|---|---|
| `AppPage` | Page scaffold: large title, actions, pull-to-refresh, max content width on tablets. Pass `slivers:` for lists. |
| `AppCard` | Flat card; `onTap`, optional `tone:` for a tinted status card. |
| `AppButton` / `.secondary` / `.ghost` | 48 dp minimum, variants `primary, secondary, ghost, danger, success, warning`, `loading:` shows a spinner and blocks double taps, `expand:` for full width. One primary button per view. |
| `AppIconButton` | 48 dp icon button with tooltip (screen readers) and optional badge. |
| `AppTextField` | Label above the field, inline validation on interaction. |
| `AppPickerField` | Looks like a field, opens a date/time/list picker. |
| `AppChoiceChips<T>` | Chip choices (leave type, filters). `scrollable: true` for one line. |
| `AppSwitchTile` | Adaptive switch row (Cupertino style on iOS). |
| `StatusBadge` / `StatusBadge.request(status)` | Pending / approved / rejected badges. |
| `ToneIcon`, `AppAvatar` | Icon in a soft square; avatar with initials fallback and cached, resized network image. |
| `KpiTile`, `AnimatedNumber`, `MiniBarChart`, `AppProgressBar`, `KeyValueRow` | Dashboards and details. |
| `SectionHeader`, `AppListTile`, `ResponsiveGrid`, `ContentWidth` | Layout. `ResponsiveGrid` picks the column count from the width, so tiles never squash. |
| `EmptyView`, `ErrorView`, `Skeleton`, `SkeletonList`, `FadeSlideIn` | Loading, empty and error states; staggered entrance. Use skeletons, not spinners, for page loads. |
| `showAppSheet`, `showAppConfirm`, `AppSnack` | Bottom sheets, adaptive confirmation (Cupertino on iOS), snackbars (`success`, `error`, `info`, `undo`). |

Global: `AppChrome` (in `main.dart`) shows the offline banner above every screen and caps
text scaling at 1.3.

## 3. Layout and responsiveness

| Width | Navigation | Layout |
|---|---|---|
| < 600 dp (phones) | Bottom `NavigationBar` | One column |
| 600–840 dp | `NavigationRail` | Content centered, max 720 dp |
| ≥ 840 dp | Extended rail | Two panes where useful (home, attendance map + panel) |

- Minimum touch target 48 dp. Forms are limited to 560 dp wide.
- RTL: use `EdgeInsetsDirectional` / `AlignmentDirectional`; forward chevron is `Icons.chevron_right_rounded` (it mirrors in RTL).
- Do not use emoji or unicode arrows in UI text; they render inconsistently. Use icons.
- No `BackdropFilter`/blur and no heavy shadows inside lists.
- Android is edge-to-edge with transparent system bars; predictive back is enabled. iOS uses Cupertino page transitions (swipe back).

## 4. Tests

```bash
flutter test                                   # everything (unit + screens)
flutter test test/screens/responsive_test.dart # 21 screens × 7 sizes × text 1.0/1.3
flutter test test/screens/screenshots_test.dart --dart-define=CAPTURE=after
```

- `test/support/fake_backend.dart` is an in-memory Supabase (REST, RPC, auth, storage), so screens render with realistic data and never touch the real database. Fixtures are in `test/support/fixtures.dart`.
- Any overflow fails the responsive test.
- Screenshots are written to `design/screenshots/<set>/`; `before/` is the app before this redesign, `after/` is the result.

## 5. Adding a screen

1. Start from `AppPage` (or `Scaffold` + `AppBar` for tabbed screens).
2. Loading → `SkeletonList`; error → `ErrorView(onRetry:)`; empty → `EmptyView`.
3. Add pull-to-refresh (`onRefresh:`).
4. Confirm destructive actions with `showAppConfirm(destructive: true)`; report results with `AppSnack`.
5. Add the screen to `test/support/screens.dart` so it is covered by the responsive matrix.
