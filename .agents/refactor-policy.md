# Refactoring policy

- Backwards compatibility is mandatory: preserve public UDP APIs, supported native behavior, and persisted data formats.
- Internal refactors must update all affected in-repository consumers together while preserving native module identity and supported behavior.
- Public or downstream breaks require explicit user approval, a migration plan, and prominent release notes; the 2026-10-27 approval authorizes the standard pnpm/Turbo repository layout while preserving the package name, native APIs and Bob compilation.
