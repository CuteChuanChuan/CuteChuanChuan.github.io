---
title: "Implementing Spark-Compatible json_tuple in Apache DataFusion"
date: 2026-02-20T00:00:00+08:00
description: "How I implemented the json_tuple function in Rust for Apache DataFusion, enabling Spark SQL compatibility for the DataFusion-Comet project."
tags: ["Apache DataFusion", "Rust", "Open Source", "Spark"]
categories: ["Open Source Contributions"]
hero: apache-datafusion.svg
---

## TL;DR

> **Project:** Apache DataFusion
> **PR:** [apache/datafusion#20412](https://github.com/apache/datafusion/pull/20412) — **+415 / -2** across 5 files
> **What:** Implemented `json_tuple`, a Spark-compatible UDF that extracts multiple JSON fields in a single call, returning a Struct.
> **Why:** Enables [DataFusion-Comet](https://datafusion.apache.org/comet/) to offload Spark's `json_tuple` to DataFusion natively.

---

## Background

[Apache DataFusion](https://datafusion.apache.org/) is an extensible query execution framework written in Rust, using Apache Arrow as its in-memory format. It powers projects like [DataFusion-Comet](https://datafusion.apache.org/comet/), a Spark plugin that accelerates queries by offloading execution to DataFusion.

To achieve full Spark SQL compatibility, DataFusion needs to implement many of Spark's built-in functions. One such function is `json_tuple` — commonly used in ETL pipelines to extract structured data from JSON columns without parsing the entire document into a nested schema.

---

## Problem

DataFusion-Comet needed `json_tuple` support ([Comet issue #3160](https://github.com/apache/datafusion-comet/issues/3160)), but the function didn't exist in DataFusion. Without it, any Spark query using `json_tuple` would fall back to Spark's native (slower) execution path.

The challenge: DataFusion's `ScalarUDF` interface returns **exactly one value per row**, but `json_tuple` conceptually returns **multiple columns**.

---

## Solution

### Returning a Struct

I chose to return a **Struct** type, where each field corresponds to a requested JSON key:

```
json_tuple(json_string, key1, key2, ...) -> Struct<c0: Utf8, c1: Utf8, ...>
```

The caller (DataFusion-Comet) destructures the struct fields into separate columns. This keeps the UDF interface clean while preserving the multi-column semantics Spark users expect.

### Field Name Convention

Following Spark's behavior, struct fields are named `c0`, `c1`, `c2`, etc. — positional names matching what Spark returns in a `SELECT` clause.

---

## Key Code Changes

The implementation lives in the `datafusion-spark` crate and involves four key pieces:

- **Function registration** — Registering `json_tuple` as a `ScalarUDF` with variadic arguments (minimum 2: the JSON string plus at least one key)
- **Return type inference** — Dynamically building the return `Struct` type based on the number of key arguments
- **JSON parsing** — Using `serde_json` to parse each row's JSON string and extract the requested fields
- **NULL handling** — Returning `NULL` for the entire struct if the input JSON is `NULL`, and `NULL` for individual fields if a key doesn't exist

### Example Behavior

```sql
SELECT json_tuple('{"f1":"value1","f2":"value2","f3":3}', 'f1', 'f2', 'f3');
-- Result: {c0: value1, c1: value2, c2: 3}

SELECT json_tuple('{"f1":"value1"}', 'f1', 'f2');
-- Result: {c0: value1, c1: NULL}

SELECT json_tuple(NULL, 'f1');
-- Result: NULL
```

---

## Testing

The test suite covers both unit and integration levels:

- **Unit tests** — Validating the `return_field_from_args` shape and error cases (e.g., too few arguments)
- **SQL logic tests** — A dedicated `json_tuple.slt` file with test cases derived from Spark's own `JsonExpressionsSuite`, ensuring behavioral parity

---

## Takeaways

- DataFusion's `ScalarUDF` interface is flexible enough to handle multi-value returns through Struct types — no special framework changes needed.
- Deriving test cases from Spark's own test suite is the most reliable way to ensure behavioral parity.
- This PR is part of the broader [#15914](https://github.com/apache/datafusion/issues/15914) tracking issue for Spark function support in DataFusion.
