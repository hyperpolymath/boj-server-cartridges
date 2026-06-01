---
name: Feature request
about: Propose a new cartridge, a registry-side improvement, or a schema-mirror change
title: "feat: "
labels: enhancement
assignees: hyperpolymath
---

<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) -->

## Motivation

What does this enable that the current `boj-server-cartridges` does not? Concrete consumer story preferred (e.g. "panll needs an X-mcp cartridge to talk to Y").

## Proposed cartridge (if applicable)

- Name (must match `^[a-z0-9-]+-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$`):
- Domain / cross-cutting category (per [README.md §Taxonomy](../README.md#taxonomy)):
- Role suffix:
- Backend protocol(s):
- Tools / capabilities surface:

## Composition with existing cartridges

How does this slot in alongside the 139 cartridges already in the registry? Does it replace, supplement, or compose with any of the existing domain umbrellas (cloud, database, ci-cd, languages, security, research, agentic, nesy, build, debug, fleet, health)?

## Schema-mirror implications

Does the proposal need a change to the canonical schema at [hyperpolymath/standards](https://github.com/hyperpolymath/standards) (`cartridges/cartridge-v1.json`)? If so, the standards-side change lands first; this repo follows via a [`schemas/PINNED-SHA`](../schemas/PINNED-SHA) bump per [`schemas/SCHEMA-MIRROR.md`](../schemas/SCHEMA-MIRROR.md).

## Refs

<!-- Link related issues / upstream PRs / boj-server consumer issues. -->
