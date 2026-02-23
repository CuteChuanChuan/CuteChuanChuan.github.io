---
title: "Fixing ErrorProne Warnings Across Apache Iceberg"
date: 2025-06-27T00:00:00+08:00
description: "Resolving ErrorProne static analysis warnings across multiple modules in Apache Iceberg, from primitive hashing to enum immutability."
tags: ["Apache Iceberg", "Java", "ErrorProne", "Open Source", "Code Quality"]
categories: ["Open Source Contributions"]
hero: apache-iceberg.svg
---

## TL;DR

> **Project:** Apache Iceberg
> **PR:** [apache/iceberg#13217](https://github.com/apache/iceberg/pull/13217) — **+94 / -144** across 6 files
> **What:** Fixed 5 distinct ErrorProne warnings across the API, Flink, GCP, and Azure modules.
> **Why:** Eliminated real code quality issues — from unnecessary boxing to unsafe parallel streams — following Iceberg's established patterns.

---

## Background

[Apache Iceberg](https://iceberg.apache.org/) is a high-performance table format for huge analytic datasets, bringing reliability and simplicity to data lakes with schema evolution, partition evolution, and time travel queries.

Iceberg uses [ErrorProne](https://errorprone.info/), Google's static analysis tool for Java, to catch common bugs at compile time. When ErrorProne flags warnings, they indicate real code quality issues that can lead to subtle bugs.

---

## Problem

Five ErrorProne warnings existed across multiple Iceberg modules. Each represented a different category of issue — from trivial style problems to potentially dangerous concurrency patterns.

---

## Solution

### 1. UnnecessaryParentheses (ADLSFileIO)

The simplest fix: removing unnecessary parentheses that added visual noise without changing behavior. Keeps the codebase consistent with the project's style.

### 2. ObjectsHashCodePrimitive (DynamicRecordInternalSerializer)

```java
// Before: boxing a primitive boolean into an Object
Objects.hashCode(booleanValue)

// After: using the primitive-specific method
Boolean.hashCode(booleanValue)
```

`Objects.hashCode()` boxes primitives into their wrapper types before computing the hash. `Boolean.hashCode()` operates directly on the primitive, avoiding unnecessary allocation.

### 3. MixedMutabilityReturnType (DynamicWriter)

```java
// Before: returning a mutable list
return new ArrayList<>(items);

// After: returning an immutable list for a consistent API contract
return ImmutableList.copyOf(items);
```

When a method returns a collection that callers shouldn't modify, using `ImmutableList` makes this contract explicit and prevents accidental mutations.

### 4. ImmutableEnumChecker (Timestamps)

Enum constants should be deeply immutable. The `Timestamps` enum used a `SerializableFunction` field that ErrorProne flagged as potentially mutable. The fix replaced it with a dedicated `@Immutable` `Apply` class, satisfying the immutability checker.

### 5. DangerousParallelStreamUsage (BigQueryMetastoreClientImpl)

```java
// Before: using Java's parallel stream (common ForkJoinPool)
items.parallelStream().forEach(...)

// After: using Iceberg's own concurrent utility
Tasks.foreach(items).executeWith(executorService).run(...)
```

This was the most nuanced fix. Java's `parallelStream()` uses the common ForkJoinPool, which can cause thread starvation in production systems. Iceberg has its own `Tasks.foreach()` utility that provides controlled parallelism with proper error handling.

---

## Testing

Each fix was verified independently:

- **Full build** — `./gradlew clean build -x test -x integrationTest --no-build-cache` — zero ErrorProne warnings
- **BigQuery module** — `./gradlew :iceberg-bigquery:test` — all passing
- **API module** — `./gradlew :iceberg-api:test` — all passing

---

## Takeaways

- Understanding a project's conventions before making changes matters more than just silencing warnings. The `Tasks.foreach()` replacement wasn't obvious from the ErrorProne documentation alone — it came from reading how Iceberg handles concurrency elsewhere.
- Even "simple" static analysis fixes can teach you important patterns about a codebase's design philosophy.
- Grouping related fixes into a single PR (with clear per-fix explanations) makes review more efficient than sending 5 separate one-line PRs.
