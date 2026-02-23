---
title: "Fixing ErrorProne Warnings Across Apache Iceberg"
date: 2025-06-27T00:00:00+08:00
description: "Resolving ErrorProne static analysis warnings across multiple modules in Apache Iceberg."
tags: ["Apache Iceberg", "Java", "ErrorProne", "Open Source", "Code Quality"]
categories: ["Open Source Contributions"]
hero: apache-iceberg.svg
---

> PR: [apache/iceberg#13217](https://github.com/apache/iceberg/pull/13217)

## Background

[Apache Iceberg](https://iceberg.apache.org/) uses [ErrorProne](https://errorprone.info/), Google's static analysis tool for Java, to catch bugs at compile time. Five warnings existed across the API, Flink, GCP, and Azure modules, each representing a different category of issue.

## Fixes

### 1. UnnecessaryParentheses (ADLSFileIO)

Removal of unnecessary parentheses to align with the project's style conventions.

### 2. ObjectsHashCodePrimitive (DynamicRecordInternalSerializer)

```java
// before: boxes the boolean into an Object
Objects.hashCode(booleanValue)

// after: operates directly on the primitive
Boolean.hashCode(booleanValue)
```

`Objects.hashCode()` wraps primitives in their boxed type before computing the hash. `Boolean.hashCode()` avoids this unnecessary allocation.

### 3. MixedMutabilityReturnType (DynamicWriter)

```java
// before
return new ArrayList<>(items);

// after
return ImmutableList.copyOf(items);
```

When callers should not modify a returned collection, `ImmutableList` makes that contract explicit rather than relying on convention.

### 4. ImmutableEnumChecker (Timestamps)

The `Timestamps` enum contained a `SerializableFunction` field flagged as potentially mutable. It was replaced with a dedicated `@Immutable` `Apply` class, ensuring enum constants remain deeply immutable as the compiler can now verify.

### 5. DangerousParallelStreamUsage (BigQueryMetastoreClientImpl)

```java
// before: shares the common ForkJoinPool across the JVM
items.parallelStream().forEach(...)

// after: controlled parallelism via Iceberg's utility
Tasks.foreach(items).executeWith(executorService).run(...)
```

Java's `parallelStream()` uses the common ForkJoinPool, which can cause thread starvation when multiple components compete for threads. Iceberg provides `Tasks.foreach()` for exactly this purpose — controlled parallelism with proper error handling. The appropriate replacement was identified by examining how concurrency is handled elsewhere in the codebase.

## Testing

Each fix was verified with a full build under ErrorProne (zero warnings) and targeted test runs for the affected modules.
