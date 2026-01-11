# mobile

A new Flutter project.

## Backend configuration

The chat screen talks to `agent-backend`.

- Default base URL: `http://127.0.0.1:8000`
- Override with:
  - `--dart-define=AGENT_BACKEND_BASE_URL=http://<host>:8000`

Example (iOS simulator / Android emulator may require host mapping):

- `flutter run --dart-define=AGENT_BACKEND_BASE_URL=http://127.0.0.1:8000`

The streaming endpoint used by the app is:

- `POST /chat/stream` (SSE)

## Strategy trade cards (MVP)

The app can render a strategy trade card after receiving the SSE `done` event.

Required `done` payload fields:

- `assistant_text: string`
- `session_id: string`
- `strategy_type: string | null`
  - actionable demo types: `start_dca`, `start_grid`, `start_mean_reversion`, `start_martingale`
- `strategy_label: string | null`
- `actions: array`
- `execution_preview: object | null`
  - must include `requires_confirmation: true` for card rendering

User actions:

- Execute: opens a confirmation Bottom Sheet (preview-only MVP)
- Observe: keeps the card visible but disables both buttons (grey + non-clickable) and does not send any follow-up request

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
