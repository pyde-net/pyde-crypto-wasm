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

.PHONY: help ci fmt fmt-fix clippy wasm wasm-web wasm-node clean

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

wasm: wasm-node wasm-web ## Both wasm-pack targets (CI gate). wasm-web runs LAST so the committed pkg/ ends up as ESM — the form npm consumers (e.g. pyde-ts-sdk) need.

wasm-web: ## wasm-pack build --target web --release
	wasm-pack build --target web --release

wasm-node: ## wasm-pack build --target nodejs --release
	wasm-pack build --target nodejs --release

clean: ## cargo clean + remove ./pkg
	cargo clean
	rm -rf pkg
