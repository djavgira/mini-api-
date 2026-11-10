# Runtime observability

This document describes the current Rust implementation only. Python worker stack sampling no longer applies.

The Rust implementation is organized under `gateway-src/observability/` and `gateway-src/storage/`.
Runtime resource and idempotency diagnostics are assembled in `gateway-src/runtime/context.rs`
and exposed by `gateway-src/api/platform.rs`. See [architecture](architecture.md).
