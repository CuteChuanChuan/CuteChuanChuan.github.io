---
title: "Refactoring QueryPlanSerde in Apache DataFusion-Comet"
date: 2025-08-09T00:00:00+08:00
description: "Extracting expression serialization logic from a monolithic Scala file into modular traits in Apache DataFusion-Comet."
tags: ["Apache DataFusion-Comet", "Scala", "Refactoring", "Open Source"]
categories: ["Open Source Contributions"]
hero: apache-comet.svg
---

## TL;DR

> **Project:** Apache DataFusion-Comet
> **PRs:** [#2028](https://github.com/apache/datafusion-comet/pull/2028) (+219/-99) and [#2085](https://github.com/apache/datafusion-comet/pull/2085) (+214/-123)
> **What:** Split a monolithic Scala file into modular traits — extracting comparison and datetime expressions into dedicated files.
> **Why:** `QueryPlanSerde` had grown too large to navigate. Part of [tracking issue #2019](https://github.com/apache/datafusion-comet/issues/2019).

---

## Background

[Apache DataFusion-Comet](https://datafusion.apache.org/comet/) is a Spark plugin that accelerates Spark SQL queries by translating Spark's physical plans into DataFusion execution plans. At the heart of this translation is `QueryPlanSerde` — a Scala file responsible for serializing Spark expressions into Protocol Buffer messages that DataFusion can understand.

---

## Problem

`QueryPlanSerde` had grown into a **massive monolithic file** handling serialization for every type of Spark expression — comparisons, datetime operations, string functions, math operations, and more. This made it:

- Hard to navigate and find specific expression handlers
- Difficult to review PRs that touched the file
- Error-prone when adding new expressions

---

## Solution

### Two-PR Strategy

Rather than one massive refactoring PR, I split the work into two focused PRs:

1. **PR #2028** — Extract comparison expressions
2. **PR #2085** — Extract datetime expressions

Each PR moved a logical group of expressions into its own file while maintaining identical behavior.

### PR #2028: Comparison Expressions

#### The ComparisonBase Trait

The key design decision was introducing a reusable trait:

```scala
trait ComparisonBase {
  protected def createComparisonExpr(
    left: Expression,
    right: Expression,
    sparkExpr: BinaryComparison
  ): Option[ExprOuterClass.Expr]
}
```

#### What Moved

Extracted from `QueryPlanSerde` into `comparison.scala`:

- **Binary comparisons** — `GreaterThan`, `GreaterThanOrEqual`, `LessThan`, `LessThanOrEqual`
- **Null checks** — `IsNull`, `IsNotNull`, `IsNaN`
- **Set membership** — `In`

Each became its own class (e.g., `CometGreaterThan`, `CometIsNull`) implementing a common serialization interface.

#### Wiring It Up

The `exprSerdeMap` registry was updated to point to the new classes:

```scala
// Before: inline case statements in a giant match block
case gt: GreaterThan => // 20 lines of serialization code

// After: registered in the map, delegated to dedicated class
classOf[GreaterThan] -> CometGreaterThan
```

### PR #2085: DateTime Expressions

Following the same pattern, the second PR extracted datetime expressions into `datetime.scala` with a `DateTimeBase` trait:

- **Date parts** — `Year`, `Month`, `DayOfMonth`, `DayOfYear`, `Hour`, `Minute`, `Second`
- **Date arithmetic** — `DateAdd`, `DateSub`, `DateDiff`
- **Truncation** — `TruncDate`, `TruncTimestamp`
- **Unix time** — `FromUnixTime`, `UnixTimestamp`

---

## Testing

Since these were **pure refactoring changes** with no functional modifications, the existing test suite was the verification:

- All existing unit tests pass unchanged
- All SQL logic tests pass unchanged
- The `exprSerdeMap` correctly routes to the new classes

No new tests were needed because the behavior was identical — only the code organization changed.

---

## Takeaways

- Splitting large refactoring into multiple focused PRs makes review manageable and reduces merge conflict risk.
- Introducing traits with shared helper methods creates a pattern that future contributors can follow.
- Together, these two PRs reduced `QueryPlanSerde` by ~220 lines and established a template for extracting additional expression groups. Other contributors have since followed the same approach.
