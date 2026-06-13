# pyde-crypto-wasm — developer Makefile.
#
# Mirrors the GitHub Actions workflow at .github/workflows/ci.yml so
# `make ci` locally exercises the same gates a pushed branch hits in
# CI. Lets contributors verify before they push — important here
# because the sibling-repo path-deps (pyde-crypto, pyde-rust-sdk) make
# CI partially red while those repos stay private; local-green +
# `--admin` merge is the established convention until they go public.
#
# Run `make help` for the full target list.

.PHONY: help ci fmt fmt-fix clippy wasm wasm-bundler wasm-web wasm-node clean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "} \
	     /^[a-zA-Z0-9_-]+:.*?##/ { \
	       printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 \
	     }' $(MAKEFILE_LIST)

ci: fmt clippy wasm ## Run every gate the GH Actions ci.yml runs (fmt + clippy + wasm-pack web + nodejs)

fmt: ## cargo fmt --check (CI gate)
	cargo fmt --all -- --check

fmt-fix: ## cargo fmt — apply formatting in place
	cargo fmt --all

clippy: ## cargo clippy --lib -- -D warnings (CI gate; --lib only — see ci.yml note on pyde-rust-sdk dev-dep)
	cargo clippy --lib -- -D warnings

wasm: wasm-node wasm-web wasm-bundler ## All three wasm-pack targets (CI gate). wasm-bundler runs LAST so the committed pkg/ is the npm-publishable form — auto-initialises via bundler magic (Vite / Webpack / tsup / esbuild / Rollup all handle `import "./pyde_crypto_wasm_bg.wasm"` transparently). The other two targets are tested in CI but their output is overwritten.

wasm-bundler: ## wasm-pack build --target bundler --release (the npm-publishable form — auto-inits, ESM, no __wbg_init() call required from consumers)
	wasm-pack build --target bundler --release

wasm-web: ## wasm-pack build --target web --release (browser <script type=module> direct use — requires explicit await __wbg_init() before first call)
	wasm-pack build --target web --release

wasm-node: ## wasm-pack build --target nodejs --release (CJS auto-init for plain Node scripts without a bundler)
	wasm-pack build --target nodejs --release

clean: ## cargo clean + remove ./pkg
	cargo clean
	rm -rf pkg
