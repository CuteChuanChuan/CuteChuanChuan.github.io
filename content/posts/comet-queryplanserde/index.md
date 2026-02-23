---
title: "Refactoring QueryPlanSerde in Apache DataFusion-Comet"
date: 2025-08-09T00:00:00+08:00
description: "Splitting a monolithic Scala file into modular traits in Apache DataFusion-Comet."
tags: ["Apache DataFusion-Comet", "Scala", "Refactoring", "Open Source"]
categories: ["Open Source Contributions"]
hero: apache-comet.svg
---

> PRs: [#2028](https://github.com/apache/datafusion-comet/pull/2028) and [#2085](https://github.com/apache/datafusion-comet/pull/2085) — part of [tracking issue #2019](https://github.com/apache/datafusion-comet/issues/2019)

## Background

[DataFusion-Comet](https://datafusion.apache.org/comet/) translates Spark physical plans into DataFusion execution plans. The core of this translation lives in `QueryPlanSerde`, a Scala file responsible for serializing Spark expressions into Protocol Buffer messages.

Over time, `QueryPlanSerde` had accumulated serialization logic for every expression type — comparisons, datetime operations, string functions, math — all in a single file. This made navigation difficult, PR reviews cumbersome, and adding new expressions error-prone.

## Approach

The refactoring was split into two focused PRs to keep reviews manageable and reduce merge conflict risk.

### PR #2028: Comparison expressions

A `ComparisonBase` trait was introduced as a shared foundation:

```scala
trait ComparisonBase {
  protected def createComparisonExpr(
    left: Expression,
    right: Expression,
    sparkExpr: BinaryComparison
  ): Option[ExprOuterClass.Expr]
}
```

All comparison-related logic was extracted into `comparison.scala` — binary comparisons (`GreaterThan`, `LessThan`, etc.), null checks (`IsNull`, `IsNotNull`, `IsNaN`), and set membership (`In`). Each expression was given its own class implementing the trait.

The existing match block was replaced with a clean map lookup:

```scala
// before: inline serialization logic
case gt: GreaterThan => ...

// after: delegated to dedicated class
classOf[GreaterThan] -> CometGreaterThan
```

### PR #2085: DateTime expressions

The same pattern was applied to datetime operations. A `DateTimeBase` trait was introduced, and expressions were moved into `datetime.scala` — date parts (`Year`, `Month`, `Hour`, etc.), date arithmetic (`DateAdd`, `DateSub`, `DateDiff`), truncation, and unix time conversions.

## Testing

These were pure refactoring changes with no functional modifications. The existing unit tests and SQL logic tests passed without any changes, confirming that the new class routing was wired correctly.
