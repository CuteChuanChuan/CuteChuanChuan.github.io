---
title: "Making gRPC Timeouts Configurable in Apache DataFusion-Ballista"
date: 2025-11-01T00:00:00+08:00
description: "Adding user-configurable gRPC timeout settings to Ballista's distributed query engine."
tags: ["Apache DataFusion-Ballista", "Rust", "gRPC", "Distributed Systems", "Open Source"]
categories: ["Open Source Contributions"]
hero: apache-ballista.svg
---

> PR: [apache/datafusion-ballista#1337](https://github.com/apache/datafusion-ballista/pull/1337)

## Background

[Ballista](https://datafusion.apache.org/ballista/) is a distributed query engine built on DataFusion. It coordinates executors through a scheduler, with all inter-node communication going over gRPC.

A previous PR (#115) had introduced gRPC timeout support, but all values were hard-coded. In production environments, different workloads require different timeout behavior — a long-running aggregation needs different settings than a quick metadata fetch. Without configuration options, the only recourse was to modify the source code directly.

## Configuration options

Nine new settings were added, split between client and server:

**Client-side:**

| Config Key | Description |
|---|---|
| `grpc_client_connect_timeout` | Initial connection timeout |
| `grpc_client_http2_keep_alive_interval` | HTTP/2 keep-alive ping interval |
| `grpc_client_http2_keep_alive_timeout` | Keep-alive response timeout |
| `grpc_client_http2_keep_alive_while_idle` | Ping on idle connections |
| `grpc_client_timeout` | Overall request timeout |

**Server-side:**

| Config Key | Description |
|---|---|
| `grpc_server_http2_keep_alive_interval` | Keep-alive interval |
| `grpc_server_http2_keep_alive_timeout` | Keep-alive timeout |
| `grpc_server_tcp_keepalive` | TCP-level keep-alive |
| `grpc_server_tcp_nodelay` | TCP no-delay flag |

## Implementation

The two core functions responsible for creating gRPC connections were updated to accept `BallistaConfig`:

```rust
// before
fn create_grpc_client_connection(addr: String) -> Result<Channel>

// after
fn create_grpc_client_connection(
    addr: String,
    config: &BallistaConfig,
) -> Result<Channel>
```

This required propagating the config through all call sites — the executor connecting to the scheduler, the scheduler connecting to executors, and the Flight SQL server endpoint.

Rather than introducing a standalone configuration mechanism, the settings were integrated into DataFusion's existing `ConfigExtension` trait. Users configure timeouts the same way they set any other Ballista option:

```
ballista.grpc_client_connect_timeout = 10s
ballista.grpc_client_timeout         = 300s
ballista.grpc_server_tcp_nodelay     = true
```

## Testing

The existing integration tests were used to verify that default values match the previous hard-coded behavior and that custom values propagate correctly to the gRPC channels.
