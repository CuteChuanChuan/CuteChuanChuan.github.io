---
title: "Making gRPC Timeouts Configurable in Apache DataFusion-Ballista"
date: 2025-11-01T00:00:00+08:00
description: "Extending Ballista's distributed query engine with user-configurable gRPC timeout settings for production-ready deployments."
tags: ["Apache DataFusion-Ballista", "Rust", "gRPC", "Distributed Systems", "Open Source"]
categories: ["Open Source Contributions"]
hero: apache-ballista.svg
---

## TL;DR

> **Project:** Apache DataFusion-Ballista
> **PR:** [apache/datafusion-ballista#1337](https://github.com/apache/datafusion-ballista/pull/1337) — **+250 / -54** across 12 files
> **What:** Added 9 user-configurable gRPC timeout settings (5 client-side, 4 server-side) through DataFusion's config system.
> **Why:** Hard-coded timeouts forced operators to accept suboptimal defaults or maintain custom builds.

---

## Background

[Apache DataFusion-Ballista](https://datafusion.apache.org/ballista/) is a distributed query engine built on top of DataFusion. It extends DataFusion's single-node execution to a cluster of executors coordinated by a scheduler, using gRPC for inter-node communication.

A previous PR (#115) introduced gRPC timeout support, but all timeout values were **hard-coded**. In production, different workloads need different timeouts — a long-running aggregation requires different settings than a quick metadata lookup.

---

## Problem

Hard-coded gRPC timeouts meant:

- **No tunability** — Operators couldn't adjust timeouts without modifying source code
- **One-size-fits-all** — The same timeout applied to fast metadata queries and slow aggregation jobs
- **Custom builds required** — Production deployments with specific network conditions needed fork-and-patch workflows

---

## Solution

### 9 New Configuration Options

Added through DataFusion's extensible `BallistaConfig` mechanism:

**Client-side (5 options):**

| Config Key | Purpose |
|---|---|
| `grpc_client_connect_timeout` | Time to wait for initial connection |
| `grpc_client_http2_keep_alive_interval` | HTTP/2 keep-alive ping interval |
| `grpc_client_http2_keep_alive_timeout` | How long to wait for keep-alive response |
| `grpc_client_http2_keep_alive_while_idle` | Whether to ping on idle connections |
| `grpc_client_timeout` | Overall request timeout |

**Server-side (4 options):**

| Config Key | Purpose |
|---|---|
| `grpc_server_http2_keep_alive_interval` | Server-side keep-alive interval |
| `grpc_server_http2_keep_alive_timeout` | Server-side keep-alive timeout |
| `grpc_server_tcp_keepalive` | TCP-level keep-alive |
| `grpc_server_tcp_nodelay` | TCP no-delay flag |

### Modified Core Functions

The two core functions that create gRPC connections were updated to accept configuration:

```rust
// Before: hard-coded timeouts
fn create_grpc_client_connection(addr: String) -> Result<Channel>

// After: configurable via BallistaConfig
fn create_grpc_client_connection(
    addr: String,
    config: &BallistaConfig,
) -> Result<Channel>
```

### Propagating Config Through the System

The most extensive part was threading `BallistaConfig` through all call sites across 12 files:

- **Executor** — Updated gRPC client creation when connecting to the scheduler
- **Scheduler** — Updated both the scheduler's gRPC server and its connections to executors
- **Flight SQL server** — Updated the Arrow Flight SQL endpoint configuration

### Integration with DataFusion's Config System

Rather than a standalone config file, the timeouts integrate with DataFusion's existing `ConfigExtension` trait:

```rust
impl ConfigExtension for BallistaConfig {
    const PREFIX: &'static str = "ballista";
}
```

Users set timeouts through the same mechanism as other DataFusion/Ballista settings:

```
ballista.grpc_client_connect_timeout = 10s
ballista.grpc_client_timeout = 300s
ballista.grpc_server_tcp_nodelay = true
```

---

## Testing

The existing integration test suite validated that:

- Default timeout values match the previous hard-coded behavior (no regression)
- Custom config values propagate correctly to gRPC channels
- Both client and server configurations apply independently

---

## Takeaways

- Integrating with an existing config system (`ConfigExtension`) is better than inventing a new one — users don't need to learn a new mechanism.
- Threading configuration through a distributed system touches many files, but the change at each call site is small and mechanical.
- This transforms Ballista from a development tool with sensible defaults into a **production-configurable system** where operators can tune network behavior for their environment.
