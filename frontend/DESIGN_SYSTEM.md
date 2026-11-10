# LeadFinder admin — design system

A premium, data-focused SaaS look: **indigo on slate**, Inter, an 8 / 12 px radius scale, hairline borders instead of heavy shadows, and a designed **dark mode**. Flutter Web + BLoC; no new dependencies.

## Where things live

| What | Where |
|---|---|
| Palette (light + dark, every color) | `lib/core/theme/app_palette.dart` |
| Tokens, `ThemeData`, type scale, spacing, icons | `lib/core/theme/app_theme.dart` |
| Light / dark / system switch + persistence | `lib/core/theme/theme_controller.dart`, `prefs_storage*.dart` |
| Components | `lib/presentation/design_system/` (import `design_system.dart`) |
| Shell, sidebar, navigation model | `lib/presentation/widgets/{admin_shell,app_sidebar,nav_model}.dart` |
| Tests | `test/design_system/` |

## Rules

1. **No raw colors in widgets.** Use `AppTheme.<token>`. (`grep "Color(0x\|Colors\."` in `lib/presentation` is clean apart from the design system itself.)
2. **Colors are getters, not constants.** `AppTheme.surface` returns the *live* palette's value, so it cannot be used in a `const` expression or a default parameter. Take a nullable parameter and resolve in `build`.
3. **Pick a tone, not a color.** Status/semantic UI takes an `AppTone` (`neutral, primary, success, warning, error, info`); `tone.surface / onSurface / border / solid / track` do the rest.
4. **Text on a solid fill is `AppTheme.onPrimary`** (white in both themes). `AppTheme.surface` is navy in dark mode — never use it as a foreground.

## Tokens

**Surfaces:** `background`, `surface`, `surfaceElevated` (menus, dialogs), `sidebar` (navy in both themes).
**Lines:** `border`, `borderStrong`, `divider`.
**Text:** `textPrimary`, `textSecondary`, `textMuted`, `onPrimary`.
**Brand/semantic:** `primary`, `primaryHover`, `primarySurface`, `secondary`, `success`, `warning`, `error`, `info`.
**Scales** (named by *role*, so the same name works in both themes): `neutral|primary|success|warning|error|info` × `100…900` — `100` faint tint, `500` solid, `600` hover, `700` text on a tint.
**Radius:** `radiusSm 6 · radius 8` (controls) `· radiusMd 10 · radiusCard 12 · radiusLg 16` (dialogs) `· radiusPill` (badges, bars only).
**Elevation:** `shadowCard`, `shadowRaised`, `shadowPopover`; `AppTheme.cardDecoration()` is the standard card.
**Spacing (4-pt):** `AppSpace.xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48`; `pageGutter(width)`, `pageMaxWidth 1280`.
**Breakpoints:** `AppBreakpoints.mobile 760` (sidebar → drawer), `compact 1100` (sidebar → icon rail).
**Type (Inter):** page title `displaySmall` 24/700 · section `headlineSmall` 18/600 · card title `titleMedium` 15/600 · row title `titleSmall` · body `bodyMedium` 13.5 · caption `bodySmall` 12 · buttons `labelLarge` · `AppText.stat` (28, tabular figures) · `AppText.cell` / `columnHeader` for tables.

Both palettes are checked in `theme_controller_test.dart` for WCAG AA (4.5:1) on every text/surface pair.

## Components (`design_system.dart`)

`AppButton` (primary · secondary · outlined · text · destructive; sm/md; icon, loading, full-width) · `AppIconButton` · `AppCard` / `SectionCard` · `StatCard` · `AppBadge` · `AppAlert` · `EmptyState` · `IconTile` · `LoadingView` · `Skeleton` / `SkeletonScope` / `SkeletonRows` · `AppProgressBar` (animated) · `AppTextField` · `AppSearchField` · `AppDropdown` · `AppMultiSelect` · `AppCheckboxTile` · `FieldShell` (label above, helper/validation below) · `showAppDialog` / `AppDialog` / `showConfirmDialog` · `PageHeader` / `AppPage` / `ResponsiveGrid` · `AppDataTable` / `SliverAppTable` / `AppColumn` · `AppBarChart` / `ShareBar` / `RankedBar`.

**Tables.** Columns have a `priority`; when the window is too narrow, the highest-numbered optional columns are dropped first (`fitColumns`) instead of squeezing. `SliverAppTable` builds only visible rows, so lists of thousands stay cheap. Below the mandatory minimum the lead lists fall back to cards. Sorting is by column label, selection is by row key.

**Charts** appear only when real data exists; there is no placeholder data anywhere in production code.

## Theme switching

`ThemeController` (`ThemeMode` light/dark/system) persists to `localStorage` (`leadfinder.themeMode`; the sidebar's collapsed state is `leadfinder.sidebarCollapsed`) through `dart:js_interop`, with an in-memory stub for tests and private windows. Because widgets read `AppTheme.*` rather than `Theme.of(context)`, a switch swaps `AppTheme.palette` and then marks the element tree dirty so every `build` re-runs (state, scroll positions and running scans' pages are kept). Repositories are created once in `_LeadGenerationAppState` for the same reason.

## Navigation

`nav_model.dart` is the single list of sidebar destinations; a test (`nav_model_test.dart`) asserts every one is a real route, so there are no fake entries. Pages that are not state-preserving branches are wrapped by `PlainShell`, so the sidebar is present on every screen. Below 760 px the sidebar is a drawer behind a top bar; 760–1100 px it defaults to an icon rail.

## Screen inventory and status

Rebuilt on the design system (layout + components):
`/` Dashboard · app shell/sidebar · `/leads`, `/website-leads`, `/email-leads`, `/verified` (tables, bulk actions, CSV) · `/scan` (configuration + summary) · `/scan-progress` · `/more` · Jobs Finder header/tabs.

Restyled through tokens, theme and shared cards/dialogs (new colors, type, radii, dark mode, focus/hover) but **still on their original layouts**:
`/archive` · archive leads · `/sales` · `/whatsapp` · `/watchlist` · `/users` · `/clients` · `/salesman-stats` (+ detail) · `/app-update` · `/twilio-test` (+ chat) · `/whatsapp-verified` · `/multi-scan` · `/leads/details` · Jobs tabs (Overview, Search, Scans, Jobs, Tracker, Sources) and `/jobs/:id`.

## Adding a page

```dart
import '../design_system/design_system.dart';

AppPage(
  title: 'Things', subtitle: 'What this page is for.',
  actions: [AppButton.primary(label: 'Add', icon: AppIcons.plus, onPressed: _add)],
  children: [SectionCard(title: 'Details', child: ...)],
)
```

Add its route in `app_router.dart`, and — if it belongs in the sidebar — one `NavItem` in `nav_model.dart`.
