# Mobile UI Design System — Developer Tools Dark (Glass + Aurora)

This document defines the **single source of truth** for the mobile UI style used in `mobile/`.

## 1. Scope & Goals

- **Dark-only**: The app is intentionally locked to dark mode.
- **Developer-tools aesthetic**: low-light background + glass surfaces + subtle aurora glow.
- **Token-driven**: all colors are derived from `SyntaxTheme` tokens.
- **Consistency-first**: reuse `GlassCard` and avoid ad-hoc `Container` styling.

## 2. Non-goals

- Light mode.
- Multiple themes/skins.
- Pixel-perfect parity with the web demo; we align the *visual language* in a mobile-appropriate way.

## 3. Design Principles

- **Dark by default**
  - Background is near-black.
  - Surfaces are translucent white overlays.
- **Glass surfaces**
  - Use blur (`sigma=24`) + subtle border.
  - Avoid heavy shadows; depth is communicated via blur + border + slight contrast.
- **Aurora background**
  - Soft radial glows using primary (blue) and accent (orange).
  - Never reduce text contrast.
- **Syntax-highlight accents**
  - Use token colors for semantic accents (keyword/string/number/etc.).

## 4. Typography

Aligned to the demo style:

- **Body**: `DM Sans`
- **Headings**: `Space Grotesk`

Implementation lives in:
- `mobile/lib/ui/theme/app_theme.dart`

## 5. Color System (Tokens)

All colors come from `SyntaxTheme`:
- File: `mobile/lib/ui/theme/syntax_theme.dart`

### 5.1 Core Surfaces

- **Background**: `SyntaxTheme.dark.background` = `#0B0B10`
- **Glass Surface (primary)**: `SyntaxTheme.dark.surface` = `#FFFFFF0D` (white @ 5%)
- **Glass Surface (secondary)**: `SyntaxTheme.dark.surface2` = `#FFFFFF14` (white @ 8%)
- **Border**: `SyntaxTheme.dark.border` = `#FFFFFF1A` (white @ 10%)

### 5.2 Primary & Accent

- **Primary (blue)**: `primary` = `#2563EB`
- **Accent (orange)**: `number` = `#F97316` (reused as accent for this style)

### 5.3 Status Colors

- **Success**: `success` = `#22C55E`
- **Warning**: `warning` = `#F59E0B`
- **Danger**: `danger` = `#EF4444`

### 5.4 Syntax Accent Tokens

Use these for semantic text/labels/highlights:
- **Keyword**: `keyword` (purple)
- **String**: `string` (green)
- **Number / Accent**: `number` (orange)
- **Type**: `typeColor` (mint)
- **Function**: `function` (light blue)
- **Variable**: `variable` (pink)
- **Comment**: `comment` (slate)

## 6. Layout, Spacing, Shape

### 6.1 Radius

- **Default card radius**: `16`
- **Input/composer radius**: `18`
- **Pills**: `999`

### 6.2 Spacing

- Page padding: `EdgeInsets.fromLTRB(16, 12, 16, 16)`
- Card padding: `14`
- Vertical rhythm: `8/10/12/14/16`

## 7. Components

### 7.1 GlassCard (Required)

**Use case**:
- Any panel, section, container that would otherwise be `Card`.

Implementation:
- File: `mobile/lib/ui/widgets/glass_card.dart`
- Visual spec:
  - `BackdropFilter blur(24)`
  - `background: SyntaxTheme.surface` (or override)
  - `border: SyntaxTheme.border`

Usage:
```dart
final syntax = SyntaxTheme.of(context);

GlassCard(
  padding: const EdgeInsets.all(14),
  child: ...,
);

GlassCard(
  backgroundColor: syntax.surface2,
  borderRadius: BorderRadius.circular(14),
  padding: const EdgeInsets.all(12),
  child: ...,
);
```

**Do**:
- Use `GlassCard` instead of `Card`.
- Keep borders subtle (white @ 10%).

**Don’t**:
- Use opaque backgrounds.
- Add large drop shadows.

### 7.2 Aurora Background

Location:
- `mobile/lib/ui/app_shell.dart` (`_AuroraBackground`)

Spec:
- Radial gradients:
  - Primary blue glow (top)
  - Orange accent glow (right)
- Must remain `IgnorePointer`.

### 7.3 Glass Bars (AppBar & Bottom Navigation)

Location:
- `mobile/lib/ui/app_shell.dart` (`_GlassBar`)

Spec:
- Blur 24
- Surface: `SyntaxTheme.surface`
- Border: `SyntaxTheme.border`

### 7.4 Buttons

- **Primary action**: `ElevatedButton` (uses `primary`)
- **Secondary action**: `TextButton` (uses `primary`)

Guideline:
- Keep button radius consistent with inputs (`14`), unless it’s a pill.

### 7.5 Inputs

Theme:
- `InputDecorationTheme` in `app_theme.dart`

Guidelines:
- Inputs should sit on glass surface.
- Prefer minimal chrome. When embedded in `GlassCard` compositors (e.g. chat composer), use `InputBorder.none`.

### 7.6 Markdown / Code Blocks (Chat)

Location:
- `mobile/lib/features/chat/chat_screen.dart`

Guidelines:
- Code blocks:
  - background: `surface2`
  - border: `border`
  - text: use `string` for emphasis in code style

## 8. Dark-only Policy

The app is intentionally locked:
- `ThemeMode.dark`
- `theme = AppTheme.dark()`

Rationale:
- Matches product positioning and the developer-tools aesthetic.

## 9. Flutter Implementation Guide

### 9.1 Where tokens come from

- Use `final syntax = SyntaxTheme.of(context);` for colors.
- Never hardcode colors in widgets except for isolated experiments.

### 9.2 Page Template

```dart
class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final syntax = SyntaxTheme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Title', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text('Body', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: syntax.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}
```

### 9.3 Checklist before adding a new screen

- [ ] Uses `ListView` with standard padding
- [ ] Uses `GlassCard` for containers
- [ ] Uses `SyntaxTheme` tokens (no random hex colors)
- [ ] Text contrast is readable over aurora background
- [ ] Focus/pressed states are visible

## 10. QA / Visual Acceptance Checklist

- **Dark-only**
  - [ ] App never switches to light when system changes.
- **Glass consistency**
  - [ ] Surfaces use translucent white overlays.
  - [ ] Borders use subtle white @ ~10%.
  - [ ] Blur is present on key panels.
- **Legibility**
  - [ ] Body text is readable on background + aurora.
  - [ ] Muted text is still readable.
- **Component consistency**
  - [ ] Cards/blocks are `GlassCard`.
  - [ ] Navigation and AppBar have glass treatment.
