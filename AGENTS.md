# Repository guide

- Keep all MongoDB access in backend repositories/services and never ship a MongoDB URI in mobile code.
- Do not add sample fuel prices to production responses. Empty and unavailable states must stay explicit.
- Use UTC for storage and Vietnamese labels for user visible text.
- Keep prices from one source separate; only compare compatible units.
- Validate upstream values before writing them and keep synchronization idempotent.
- Run backend formatting, type checking and tests after backend changes; run `dart format`, `flutter analyze` and `flutter test` after mobile changes when Flutter is available.
- Never commit `.env`, service account files or signing keys.
