# Repository guidance

This React Native UDP library is a separate Git repository. The current migration
scope is the compiler prerequisite repair, not a package-boundary migration.
Preserve unrelated edits, native source behavior, public APIs and module names.
Use normal reviewed commits and pushes; do not amend, rebase, force-push, merge,
publish, sign or release for this task. Keep RoboRev configuration and hooks local.

## Build and verification

The three TypeScript source modules use this library's explicit compiler options.
The prerequisite repair removes undeclared Expo preset inheritance without
changing those options, dependency versions, native source or public declarations.

- Use the declared npm10.9.0 toolchain and this repository's dependency installation. Do not borrow dependencies from an enclosing application workspace.
- Run `npm run build` for the default Bob CommonJS, module and declaration targets, then `npm run typecheck`.
- Inventory and run available existing tests. The declared Jest command is not evidence that test cases exist; report an empty suite explicitly.
- Verify the actual public declaration entry with a normal installed consumer. A portable type check does not qualify an iOS/Android host or live UDP traffic.
- Do not expose partial output from a failed build as a qualified producer artifact. Hold successful outputs stable during downstream file-copy windows.

## Repository-local skills and refactoring

- When the same skill name is available from multiple locations, always use the repository-local skill under `$REPO_ROOT/.agents/skills/`. Repository-local skills take precedence over user-global skills. Do not load or apply the corresponding skill from `$HOME/.agents/skills/` when a repository-local version exists.
- Consider the repository's current publication state and backwards-compatibility requirements recorded in `.agents/refactor-policy.md` in all interactions.
