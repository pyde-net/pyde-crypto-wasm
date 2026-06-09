<p align="center">
  <img src="./assets/logo.png" width="120" alt="Pyde logo" />
</p>

<h1 align="center">pyde-crypto-wasm</h1>

<p align="center">
  <em>Post-quantum cryptography for Pyde — in your browser</em>
</p>

---

`pyde-crypto-wasm` exposes
[`pyde-crypto`](https://github.com/pyde-net/pyde-crypto)'s post-quantum
primitives + transaction construction to browser and Node.js
environments, compiled from Rust via `wasm-bindgen`.

If you're writing a Pyde wallet, dApp frontend, browser-extension, or
any JS-targeting tool that needs to sign Pyde transactions or verify
Pyde signatures — this is the package you embed.

It works **standalone** (you can pull just this WASM into any web stack)
or as the cryptography layer underneath the
[pyde-ts-sdk](https://github.com/pyde-net/pyde-ts-sdk).

## Table of contents

- [Install](#install)
- [Quickstart — browser](#quickstart--browser)
- [Quickstart — Node](#quickstart--node)
- [API reference](#api-reference)
  - [Keys + addresses](#keys--addresses)
  - [Signing + verification](#signing--verification)
  - [Hashing + selectors](#hashing--selectors)
  - [Transactions](#transactions)
- [Security model — secret-key handling](#security-model--secret-key-handling)
- [Build targets](#build-targets)
- [Bundle size + browser compat](#bundle-size--browser-compat)
- [Versioning + status](#versioning--status)
- [Building from source](#building-from-source)
- [License](#license)

## Install

> **🚧 Not yet published to npm.** `pyde-crypto-wasm` is still pre-release;
> the npm package will be published once the host-fn ABI freezes for v1
> mainnet. For now, build from source (below) and link locally — that's
> the supported path. The npm-install snippet further down is what the
> install will look like once we publish; don't copy-paste it yet.

### Build from source (works today)

```bash
# Install wasm-pack if you don't have it:
curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

# From this repo's root:
wasm-pack build --target web --release       # for browser use
# OR
wasm-pack build --target nodejs --release    # for Node.js use

# Package output lands under ./pkg
# Link into your app:
cd pkg && npm link
cd /path/to/your-app && npm link pyde-crypto-wasm
```

Requires Rust stable + the `wasm32-unknown-unknown` target installed
(`rustup target add wasm32-unknown-unknown`). See
[Building from source](#building-from-source) further down for the
full target matrix and bundler-specific notes.

### Once published (placeholder — DO NOT use yet)

When the npm release goes live, install will be:

```bash
npm install pyde-crypto-wasm
# or
pnpm add pyde-crypto-wasm
# or
yarn add pyde-crypto-wasm
```

This README + the [pyde-net status page](https://pyde.network/status) will
be updated the moment the package is up on the registry.

## Quickstart — browser

> The `from 'pyde-crypto-wasm'` import path below works once you've
> built locally and linked (see [Install](#install)), or once we
> publish to npm. During pre-release, replace with a relative path to
> your local `pkg/` directory: `import init, { ... } from './pkg/pyde_crypto_wasm.js'`.

```html
<script type="module">
  import init, {
    generateKeypair,
    signMessage,
    verifySignature,
    poseidon2Hash,
  } from 'pyde-crypto-wasm';

  await init();

  const { publicKey, secretKey, address } = generateKeypair();

  const msgHex = '0x' + new TextEncoder().encode('hello pyde')
                          .reduce((a, b) => a + b.toString(16).padStart(2, '0'), '');
  const sig = signMessage(secretKey, msgHex);
  const ok  = verifySignature(publicKey, msgHex, sig);
  console.log('valid?', ok);
</script>
```

## Quickstart — Node

> Same import-path note as the browser quickstart: the `require('pyde-crypto-wasm')`
> line works once you've built locally + linked (`npm link`) or once we
> publish. Pre-release alternative: `require('./pkg/pyde_crypto_wasm')` against
> a local `wasm-pack build --target nodejs` output.

```js
const {
  generateKeypair,
  signMessage,
  verifySignature,
  hashTransaction,
  signTransaction,
} = require('pyde-crypto-wasm');

const { publicKey, secretKey, address } = generateKeypair();

const tx = {
  from: address,
  to:   '0x' + 'a'.repeat(64),  // dummy recipient
  value: '1000000000',           // 1 PYDE = 10^9 quanta
  data: '0x',
  gasLimit: '21000',
  nonce: '0',
  chainId: '1',
  txType: 0,
  accessList: [],
};

const txHash = hashTransaction(tx);
const wire   = signTransaction(tx, secretKey);

console.log({ txHash, wire });
```

## API reference

### Keys + addresses

```ts
generateKeypair(): { publicKey: string; secretKey: string; address: string };

generateKeypairHandle(): number;   // returns opaque u32 handle —
                                   // SK never leaves WASM heap.
                                   // See "Security model" below.

deriveAddress(publicKeyHex: string): string;
                                   // address = Poseidon2(falcon_pk)
```

Addresses are 32-byte Poseidon2 hashes (`0x...` 66 chars total).
Public keys are 897 bytes; secret keys are 1281 bytes.

### Signing + verification

```ts
signMessage(secretKeyHex: string, messageHex: string): string;
verifySignature(publicKeyHex: string, messageHex: string, sigHex: string): boolean;

// Handle variants — SK is never exposed to JS heap:
signMessageWithHandle(handle: number, messageHex: string): string;

dropKeypair(handle: number): void;  // zeroes + frees the handle
```

Signatures are FALCON-512, variable length (typically ~666 bytes).
Both forms (hex SK + handle SK) produce identical outputs.

### Hashing + selectors

```ts
poseidon2Hash(dataHex: string): string;
                                   // 256-bit output (32 bytes hex)

computeSelector(name: string): number;
                                   // FNV-1a 32-bit hash, used for the
                                   // 4-byte Otigen function selector
```

### Transactions

```ts
type TxObject = {
  from: string; to: string; value: string;
  data: string; gasLimit: string; nonce: string;
  chainId: string; txType: number;
  accessList: { address: string; storageKeys: string[]; accessType: number }[];
};

hashTransaction(tx: TxObject): string;        // canonical tx hash
signTransaction(tx: TxObject, secretKeyHex: string): string;
                                              // returns full wire bytes
```

The wire output is the FALCON-signed canonical encoding ready for
`pyde_sendRawTransaction` — no further serialization required.

## Security model — secret-key handling

**Secret-key bytes never enter the JS heap.** Two layers of defense:

**1. Opaque-handle keystore.** `generateKeypairHandle()` keeps the
FALCON secret key inside the WASM module's own heap and returns only a
`u32` handle to JavaScript. `sign*WithHandle()` looks the key up
internally and signs in place. `dropKeypair(handle)` zeroes and removes
the entry.

This is the recommended path for wallets, browser extensions, and any
context where the SK might otherwise be observable. Specifically, an
SK held by handle:
- Never appears in `JSON.stringify(walletState)` output
- Never appears in DevTools memory snapshots of the JS heap
- Never survives in a crash dump as a recoverable hex string
- Never gets accidentally `console.log`-ged

**2. Zeroize-on-drop inside the WASM module.** Inside the Rust
implementation, `FalconSecretKey` derives `ZeroizeOnDrop`. Whether you
use the hex path (`generateKeypair`) or the handle path
(`generateKeypairHandle`), when the key drops out of scope its bytes
are overwritten with zeros before the allocator releases them.

**Threading.** Currently single-threaded (`wasm32` with no
SharedArrayBuffer). The opaque-key Mutex is uncontended in practice;
the design remains forward-compatible with multi-threaded WASM workers
when those mature.

**What this doesn't protect against.** A compromised browser, a
malicious extension with sufficient privileges, or an attacker who can
inject JS into your page — those can still see the public-key and
address. They cannot see the SK bytes (because of the handle keystore)
but can still call `signMessageWithHandle()` with attacker-chosen
messages if your app keeps a handle alive. Standard browser-wallet
threat-model applies.

## Build targets

Built with `wasm-pack` from the Rust source:

```bash
# Browser (ES modules, modern bundlers)
wasm-pack build --target web

# Node.js
wasm-pack build --target nodejs

# Universal bundler (Webpack / Rollup / Vite / Parcel)
wasm-pack build --target bundler
```

Output lands in `pkg/` as a publishable npm package — `.wasm` binary
plus generated TypeScript declarations plus the JS glue.

## Bundle size + browser compat

- **Compressed `.wasm`:** ~250 KB (FALCON + Kyber + Poseidon2 +
  Blake3 + glue). Loadable on any browser since ~2018; specifically
  needs WASM SIMD-free baseline.
- **TypeScript declarations:** generated automatically by
  `wasm-pack`, no extra setup needed in consumers.
- **No `node-gyp` / native bindings.** Pure WASM. Works in Cloudflare
  Workers, Deno, Bun, anywhere WASM runs.

## Versioning + status

Pre-1.0. API may change between minor releases. Currently consumed by
[`pyde-ts-sdk`](https://github.com/pyde-net/pyde-ts-sdk) for its
browser path; production-ready for that path.

**Known constraints:**
- Single-threaded only
- Bundled `ml-kem` is at `0.3.0-rc.0` — same as the underlying
  [`pyde-crypto`](https://github.com/pyde-net/pyde-crypto) (upgrade
  tracked post-NIST-stable)
- No streaming-style API yet (everything is one-shot — fine for
  transaction-signing, less ideal for very large payload encryption)

## Building from source

```bash
# Install wasm-pack if you don't have it:
curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

# Then from this directory:
wasm-pack build --target web --release

# Package output appears under ./pkg
```

Requires Rust stable + `wasm32-unknown-unknown` target installed.

## License

Apache-2.0. See [`LICENSE`](./LICENSE) in this repo, or
[`pyde-net/pyde-crypto`](https://github.com/pyde-net/pyde-crypto) for
the Rust source.
