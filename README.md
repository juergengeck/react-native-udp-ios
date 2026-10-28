# React Native UDP workspace

The reusable `react-native-udp-ios` package is under
[`packages/react-native-udp-ios`](packages/react-native-udp-ios/README.md).
The private root owns pnpm, its frozen lock and Turbo task orchestration.

```sh
pnpm install --frozen-lockfile
pnpm build
pnpm typecheck
```

Bob still produces CommonJS, ESM and TypeScript declarations. The native module
identity, podspec name and public package entry paths are unchanged. File consumers
install the library directory after its owner build, rather than this tooling root.
No automated behavior suite is currently supplied. Portable qualification is
limited to build, TypeScript and packed native-payload checks; it makes no
device or live-UDP claim.
