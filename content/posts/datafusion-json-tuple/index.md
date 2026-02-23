---
title: "Implementing Spark-Compatible json_tuple in Apache DataFusion"
date: 2026-02-20T00:00:00+08:00
description: "Implementing the json_tuple function in Rust for Apache DataFusion, enabling Spark SQL compatibility for the DataFusion-Comet project."
tags: ["Apache DataFusion", "Rust", "Open Source", "Spark"]
categories: ["Open Source Contributions"]
hero: apache-datafusion.svg
---

> PR: [apache/datafusion#20412](https://github.com/apache/datafusion/pull/20412)

## Background

[DataFusion-Comet](https://datafusion.apache.org/comet/) accelerates Spark queries by offloading execution to [Apache DataFusion](https://datafusion.apache.org/). For this to work, DataFusion needs to support the Spark built-in functions that Comet encounters. `json_tuple` is one of them — it is commonly used in ETL pipelines to extract fields from JSON columns without defining a full schema.

Comet had an [open issue](https://github.com/apache/datafusion-comet/issues/3160) requesting this. Without native support, queries using `json_tuple` would fall back to Spark's own execution path, defeating the purpose of using Comet.

## Design

DataFusion's `ScalarUDF` interface returns exactly one value per row, but `json_tuple` conceptually produces multiple columns — one per requested key. To work within this constraint, the function was implemented to return a Struct where each field maps to a requested key:

```
json_tuple('{"a":1, "b":2}', 'a', 'b') -> {c0: 1, c1: 2}
```

Struct fields follow Spark's naming convention: `c0`, `c1`, `c2`, etc. Comet then destructures the struct into separate columns on its end. This keeps the UDF interface unchanged while preserving the multi-column semantics.

## Implementation

The function is registered as a variadic `ScalarUDF` requiring at minimum the JSON string and one key. At runtime, it:

1. Infers the return Struct type from the number of key arguments
2. Parses each row's JSON string via `serde_json`
3. Looks up each requested key and places the value into the corresponding struct field
4. Returns NULL for the entire struct if the input is NULL, or NULL for individual fields when a key is absent

```sql
SELECT json_tuple('{"f1":"value1","f2":"value2"}', 'f1', 'f2');
-- {c0: value1, c1: value2}

SELECT json_tuple('{"f1":"value1"}', 'f1', 'f2');
-- {c0: value1, c1: NULL}

SELECT json_tuple(NULL, 'f1');
-- NULL
```

## Testing

Unit tests cover return type inference and edge cases such as insufficient arguments. A dedicated `json_tuple.slt` SQL logic test file was added with cases derived from Spark's own `JsonExpressionsSuite` to ensure behavioral parity.
