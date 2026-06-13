# Origin-Inspired UI Redesign — Design

Date: 2026-06-12
Scope: `BudgetTracerSharedUI` (iOS + macOS). No domain, persistence, or backend changes.

## Goal

Replace the current utilitarian look with a minimal, fluid, focused design language modeled
on Origin Finance's web and iOS apps: warm paper canvas, typography-led hierarchy, quiet
surfaces, restrained color, soft motion, and obsessive small details (tabular numerals,
hairlines, pill controls, endpoint dots on charts).

## Design Language

### Color (semantic, light/dark adaptive)

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | warm paper `#F6F4EF` | `#131514` | screen background |
| `surface` | white | `#1E201F` | cards |
| `surfaceSunken` | ink 4% | white 6% | pill tracks, inputs |
| `ink` | `#1C1E1B` | `#F1F0EA` | primary text |
| `inkMuted` | ink 55% | 60% | secondary text |
| `inkFaint` | ink 35% | 40% | axis labels, hints |
| `hairline` | ink 8% | white 10% | borders, dividers |
| `accent` | evergreen `#1E5C4B` | `#5BB596` | brand, actions, spending line |
| `accentSoft` | `#E3EEE7` | accent 16% | tonal chips/fills |
| `positive` | `#2E7B52` | `#62B788` | income |
| `caution` | `#BE5430` | `#D87E5B` | card debt, errors |
| `chartBlue` | `#3567CE` | `#7B9BE8` | checking cash |
| `chartPurple` | `#6757C8` | `#A296E3` | cash minus cards |

### Typography

- Hierarchy from size + weight, not boxes. Money always `.monospacedDigit()`.
- Hero numeral: 44pt semibold, tight tracking, `.contentTransition(.numericText())`.
- Eyebrow labels: caption2, semibold, tracking 1.6, uppercase, `inkMuted`.
- Section headers: title3 semibold (replaces bare `.headline`).

### Surfaces

- Cards: `surface` fill, continuous radius 20–24, 0.5pt hairline, two-layer soft shadow
  (4% blur 20 / 3% blur 2 contact) on iOS; macOS keeps flatter treatment (hairline + 3%
  shadow, no material).
- Lists (Transactions/Accounts/Budgets) become custom rows inside a single card with
  hairline separators instead of system `List` chrome.

### Controls

- `ThemePillPicker`: custom segmented control — capsule track in `surfaceSunken`, selected
  segment is a white capsule sliding via `matchedGeometryEffect` with a spring. Replaces all
  `.segmented` pickers (date range, cash basis, month? month stays a menu).
- Series toggles become tappable legend chips (capsule, tonal when on, ghost when off)
  merging the legend and the toggle rows into one control — fewer rows, more focus.
- Buttons: primary = ink-on-accent capsule; secondary = tonal capsule.

### Charts

- Lines: 2pt, round joins; current period solid, previous period dashed at 35% opacity.
- Gradient area fill under the primary series (accent/blue at 14% → 0%).
- Endpoint dot with soft halo on each visible series; per-day markers shrink to 4pt at 75%.
- Axis: keep sparse top/bottom labels, `inkFaint`; baseline hairline.
- Data changes animate with a gentle spring.

### Motion

- One shared spring: `response 0.42, dampingFraction 0.85`.
- Numeric text transitions on hero and summary values.
- Pill selection slide; legend chip tonal fade.

## Structure Changes

- **iOS root becomes a bottom tab bar** (Overview, Balances, Accounts, Transactions,
  Budgets) — matches Origin iOS and removes the sidebar-push navigation on iPhone.
  macOS keeps `NavigationSplitView` with a styled sidebar.
- `BudgetTracerStyle` is rebuilt as the token set above (same type name, superset API);
  new `ThemeComponents.swift` hosts the pill picker, legend chips, eyebrow text, row, and
  button styles. All views consume tokens only — no inline hex/opacity literals in views.

## Approaches Considered

1. **Restyle in place, token-first (chosen)** — rebuild the style enum into a full token
   set + small component kit, then sweep every view. Low risk, no behavior change, testable.
2. Swift Charts migration for plots — better tooling but a behavior rewrite of bespoke
   plot math (averaged markers, dual-interval overlay); rejected as scope creep.
3. Full navigation redesign on both platforms — macOS sidebar already idiomatic; only iOS
   needs the tab-bar change.

## Error Handling / States

- Connection status moves into a quiet inline status line (icon + caption) instead of a
  boxed banner; failures use `caution`.
- Empty states get centered, muted copy inside the card.

## Testing

- `swift build` + `swift test` (existing suites are behavior-level, no UI-string coupling).
- Visual verification via macOS SwiftPM shell in demo mode.
