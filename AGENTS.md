# Repository guidance

This separate Git repository uses a private pnpm 9.15.4/Turbo tooling root. Its
reusable library is `packages/react-native-udp-ios`. Preserve public UDP APIs,
native source behavior, module names and supported data. Use normal reviewed
commits and pushes. Do not amend, rebase, force-push, merge, publish, sign or release
for this migration. Keep RoboRev configuration and hooks local.

## Build and verification

Install with `pnpm install --frozen-lockfile` in this owning root. Run `pnpm build`
for the existing Bob CommonJS, ESM and declaration targets, then `pnpm typecheck`.
Package commands are also available through `pnpm --filter react-native-udp-ios`.
The package prepare lifecycle still runs Bob; installation and downstream file
refresh remain explicit owner preparation stages. Do not borrow enclosing app
workspace dependencies or expose partial output after failed preparation.

The native compiler options and Bob targets are unchanged. Verify a normal packed
consumer's public declarations and packaged native files. Jest currently has no
test cases. Report that honestly without inventing a passing suite. Portable
builds do not qualify an iOS/Android host or live UDP traffic. Hold successful
outputs stable while downstream owners refresh file packages.

## Sources consumers

Cross-repository consumers select this Git owner with Sources and allowlist
`react-native-udp-ios:build`. After activating their owner-selected checkout,
install this private tooling root with its native frozen lock before querying or
executing that task through Sources. The root supplies local Turbo for child task
graph queries. The selected package build owns `lib/**`, and Turbo hashes its
normal source/configuration inputs and this root lock. Consumers declare the
Sources-provided foreign build hash in their actual consuming Turbo task. Build
first, then refresh their native `file:` dependency targeting
`sources/<udp-source>/packages/react-native-udp-ios`. Source activation, build and
consumer installation are separate stages. No hash wrapper or manual module link
is used. Follow the locally installed Sources skills for selected preparation.

## Repository-local skills and refactoring

Prefer repository-local skills when the same skill is also installed globally.
Apply `.agents/refactor-policy.md`. Existing public package paths, supported
behavior and persisted formats remain compatible under the approved layout move.
