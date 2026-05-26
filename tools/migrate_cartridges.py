#!/usr/bin/env python3
"""
One-shot migration: copy 125 cartridges from boj-server/cartridges/ into
boj-server-cartridges/cartridges/domains/<domain>/<role>.cartridge/ with
domain normalisation. Cross-cutting cartridges (agentic, nesy, ml, fleet
orchestration) go to cartridges/cross-cutting/.
"""
import json, os, re, shutil, sys
from pathlib import Path
from collections import defaultdict

SRC = Path("/home/hyperpolymath/developer/repos/boj-server/cartridges")
DST = Path("/tmp/boj-server-cartridges/cartridges")

# Cartridges that are intrinsically cross-cutting (not bound to a single domain)
CROSS_CUTTING = {
    "agent-mcp": "agentic",
    "claude-agents-power-mcp": "agentic",
    "claude-ai-mcp": "agentic",
    "local-coord-mcp": "agentic",
    "model-router-mcp": "agentic",
    "nesy-mcp": "nesy",
    "ml-mcp": "nesy",
    "fleet-mcp": "fleet",  # fleet orchestration is cross-cutting
    "boj-health": "health",  # health/observability harness
    "dap-mcp": "debug",  # generic debug adapter
    "bsp-mcp": "build",  # generic build server
}

# Templates (keep at templates/)
TEMPLATES = {"gossamer-mcp"}  # canonical scaffold

# Domain normalisation map
DOMAIN_MAP = {
    "ai": "ai", "AI": "ai",
    "agent orchestration": "ai",
    "AI/NeSy": "nesy",  # actually cross-cutting; cartridges in this domain handled by CROSS_CUTTING
    "cloud": "cloud", "Cloud": "cloud",
    "database": "database", "Database": "database",
    "registry": "registry", "Registry": "registry",
    "package management": "registry", "Package Management": "registry",
    "container": "container", "Container": "container",
    "container orchestration": "container", "Container Orchestration": "container",
    "ci": "ci-cd", "CI/CD": "ci-cd", "CI/CD Intelligence": "ci-cd",
    "development": "development", "Developer Tools": "development",
    "code analysis": "code-quality", "Code Analysis": "code-quality",
    "code quality": "code-quality", "Code Quality": "code-quality",
    "communications": "communications", "Communications": "communications",
    "communication": "communications", "Communication": "communications",
    "compiler": "languages", "Compiler": "languages",
    "dezig": "languages",
    "languages": "languages", "Languages": "languages",
    "language tools": "languages", "Language Tools": "languages",
    "lsp": "languages", "LSP": "languages",
    "security": "security", "Security": "security",
    "productivity": "productivity", "Productivity": "productivity",
    "research": "research", "Research": "research",
    "infrastructure": "infrastructure", "Infrastructure": "infrastructure",
    "monitoring": "observability", "Monitoring": "observability",
    "observability": "observability",
    "knowledge": "knowledge", "Knowledge": "knowledge",
    "knowledge & memory": "knowledge", "Knowledge & Memory": "knowledge",
    "formal verification": "formal-verification", "Formal Verification": "formal-verification",
    "bioinformatics": "bioinformatics", "Bioinformatics": "bioinformatics",
    "open data": "open-data", "Open Data": "open-data",
    "education": "education", "Education": "education",
    "legal": "legal",
    "gaming": "gaming",
    "project-management": "project-management",
    "community": "community",
    "automation": "automation",
    "repository management": "repository-management", "Repository Management": "repository-management",
    "desktop/ui": "desktop-ui", "Desktop/UI": "desktop-ui",
    "multimodal": "multimodal",
    "vector": "vector",
    "messaging": "messaging",
    "config": "config", "configuration": "config",
    "web": "web",
}

ROLE_RE = re.compile(r"-(mcp|lsp|dap|bsp|debug|format|lint|build|nesy|agentic|fleet)$")

stats = defaultdict(int)
placements = []
unmapped_domains = set()
unmapped_roles = []

for cart_dir in sorted(SRC.iterdir()):
    if not cart_dir.is_dir():
        continue
    name = cart_dir.name
    manifest = cart_dir / "cartridge.json"
    if not manifest.exists():
        # Not a cartridge dir (e.g. plain dir without manifest) — skip with note
        stats["skipped_no_manifest"] += 1
        placements.append((name, None, "SKIP (no cartridge.json)"))
        continue

    try:
        with open(manifest) as f:
            data = json.load(f)
    except Exception as e:
        stats["skipped_bad_json"] += 1
        placements.append((name, None, f"SKIP (bad JSON: {e})"))
        continue

    role_match = ROLE_RE.search(name)
    if not role_match:
        # Allow cartridges without canonical role suffix to flow through; they
        # need renaming in a follow-up but we still place them.
        unmapped_roles.append(name)

    # Cross-cutting check first
    if name in TEMPLATES:
        target = DST / "templates" / name
        category = "template"
    elif name in CROSS_CUTTING:
        target = DST / "cross-cutting" / CROSS_CUTTING[name] / name
        category = "cross-cutting"
    else:
        domain_raw = data.get("domain", "unknown")
        domain_norm = DOMAIN_MAP.get(domain_raw, None)
        if not domain_norm:
            domain_norm = re.sub(r"[^a-z0-9]+", "-", domain_raw.lower()).strip("-") or "unknown"
            unmapped_domains.add(domain_raw)
        # Cartridge dir = original cartridge name under the domain
        target = DST / "domains" / domain_norm / name
        category = "domain"

    stats[category] += 1
    placements.append((name, str(target.relative_to(DST.parent)), category))

# Print summary
print("=" * 80)
print(f"PLACEMENT PLAN ({len(placements)} cartridges)")
print("=" * 80)
print(f"  Templates:     {stats['template']}")
print(f"  Cross-cutting: {stats['cross-cutting']}")
print(f"  Domain-bound:  {stats['domain']}")
print(f"  Skipped (no manifest): {stats['skipped_no_manifest']}")
print(f"  Skipped (bad JSON):    {stats['skipped_bad_json']}")
print(f"  Skipped (bad role):    {stats['skipped_bad_role']}")
print()
if unmapped_domains:
    print(f"Unmapped domain values (kebab-cased as fallback): {sorted(unmapped_domains)}")
if unmapped_roles:
    print(f"Cartridges without canonical role suffix: {unmapped_roles}")
print()

# Execute
if "--execute" in sys.argv:
    for name, target_rel, cat in placements:
        if target_rel is None:
            continue
        src = SRC / name
        dst = DST.parent / target_rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(src, dst)
    print(f"COPIED {sum(1 for _,t,_ in placements if t)} cartridges into {DST}")
else:
    # Dry-run: print first 30 placements + 5 per category
    by_cat = defaultdict(list)
    for n, t, c in placements:
        by_cat[c].append((n, t))
    for cat in ("template", "cross-cutting", "domain"):
        print(f"\n--- {cat.upper()} (first 8) ---")
        for n, t in by_cat[cat][:8]:
            print(f"  {n:35} -> {t}")
        if len(by_cat[cat]) > 8:
            print(f"  ... and {len(by_cat[cat]) - 8} more")
