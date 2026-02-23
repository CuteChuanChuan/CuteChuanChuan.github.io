#!/usr/bin/env bash
set -euo pipefail

# Updates projects.yaml (star counts) and contributions/index.md (merged PRs)
# Requires: gh CLI authenticated, yq

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS_FILE="$REPO_ROOT/data/en/sections/projects.yaml"
CONTRIBUTIONS_FILE="$REPO_ROOT/content/posts/contributions/index.md"

GITHUB_USER="CuteChuanChuan"

# ── Repos to track ──────────────────────────────────────────────────
REPOS=(
  "apache/datafusion"
  "apache/datafusion-comet"
  "apache/datafusion-ballista"
  "apache/iceberg"
  "apache/ozone"
)

DISPLAY_NAMES=(
  "Apache DataFusion"
  "Apache DataFusion-Comet"
  "Apache DataFusion-Ballista"
  "Apache Iceberg"
  "Apache Ozone"
)

# ── Fetch star counts and update projects.yaml ──────────────────────
echo "Fetching star counts..."
for repo in "${REPOS[@]}"; do
  stars=$(gh api "repos/$repo" --jq '.stargazers_count' 2>/dev/null || echo "")
  if [ -n "$stars" ]; then
    short_name=$(echo "$repo" | cut -d/ -f2)
    # Format star count (e.g., 7234 -> 7.2k)
    if [ "$stars" -ge 1000 ]; then
      formatted=$(awk "BEGIN {printf \"%.1fk\", $stars/1000}")
    else
      formatted="$stars"
    fi
    echo "  $repo: $formatted stars"
  fi
done

# ── Fetch merged PRs and regenerate contributions page ──────────────
echo "Fetching merged PRs..."

cat > "$CONTRIBUTIONS_FILE" << 'FRONTMATTER'
---
title: "Open Source Contributions"
date: 2026-02-23T00:00:00+08:00
description: "A complete list of my merged pull requests across Apache open-source projects."
tags: ["Open Source", "Apache", "Contributions"]
categories: ["Open Source Contributions"]
---

## Overview

Merged pull requests across Apache open-source projects: DataFusion, DataFusion-Comet, DataFusion-Ballista, Iceberg, and Ozone. Contributions span new features, code quality improvements, documentation fixes, and refactoring.
FRONTMATTER

for i in "${!REPOS[@]}"; do
  repo="${REPOS[$i]}"
  display="${DISPLAY_NAMES[$i]}"

  echo "  Fetching PRs from $repo..."

  # Fetch merged PRs
  prs=$(gh search prs --author "$GITHUB_USER" --repo "$repo" --merged --json number,title,closedAt --limit 100 2>/dev/null || echo "[]")

  pr_count=$(echo "$prs" | jq 'length')
  if [ "$pr_count" -eq 0 ]; then
    continue
  fi

  # Fetch star count for section header
  stars=$(gh api "repos/$repo" --jq '.stargazers_count' 2>/dev/null || echo "0")
  if [ "$stars" -ge 1000 ]; then
    star_display=$(awk "BEGIN {printf \"%.1fk\", $stars/1000}")
  else
    star_display="$stars"
  fi

  cat >> "$CONTRIBUTIONS_FILE" << EOF

## $display

![GitHub stars](https://img.shields.io/github/stars/$repo?style=flat-square&color=0077B6) ![My PRs](https://img.shields.io/badge/my_PRs-${pr_count}-00B4D8?style=flat-square)

| PR | Title | Type | Date |
|----|-------|------|------|
EOF

  # Sort by date descending and format each PR
  echo "$prs" | jq -r 'sort_by(.closedAt) | reverse | .[] | [.number, .title, .closedAt] | @tsv' | while IFS=$'\t' read -r number title date; do
    # Determine type from title
    type="chore"
    lower_title=$(echo "$title" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_title" | grep -qiE "implement|support|add.*function|add.*feature|new"; then
      type="feat"
    elif echo "$lower_title" | grep -qiE "fix|correct|resolve|bug"; then
      type="fix"
    elif echo "$lower_title" | grep -qiE "refactor|extract|move|split|reorganize"; then
      type="refactor"
    elif echo "$lower_title" | grep -qiE "doc|typo|readme|comment|spec\.md"; then
      type="docs"
    elif echo "$lower_title" | grep -qiE "test|enforce.*test"; then
      type="test"
    elif echo "$lower_title" | grep -qiE "format|benchmark|lint|style"; then
      type="chore"
    elif echo "$lower_title" | grep -qiE "remove.*unused|dead.code|cleanup"; then
      type="refactor"
    fi

    # Format date
    formatted_date=$(echo "$date" | cut -c1-10)

    echo "| [#${number}](https://github.com/${repo}/pull/${number}) | ${title} | ${type} | ${formatted_date} |" >> "$CONTRIBUTIONS_FILE"
  done
done

# Add footer
cat >> "$CONTRIBUTIONS_FILE" << 'EOF'

---

[View all contributions on GitHub](https://github.com/pulls?q=is%3Apr+author%3ACuteChuanChuan+is%3Amerged)
EOF

echo "Done. Updated: $CONTRIBUTIONS_FILE"
