// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// migrate_cartridges.rs — preserved one-shot migration tool.
//
// Ported from the original Python (estate no-Python policy) but kept
// functional and preserved in tools/ for reference and future re-runs, per
// docs/decisions/ADR-001-taxonomy.adoc.
//
// Copies cartridges from a boj-server cartridges/ tree into this repo's
// cartridges/{domains,cross-cutting,templates}/ layout with domain
// normalisation. Cross-cutting cartridges (agentic, nesy, ml, fleet
// orchestration, health, debug, build) go under cross-cutting/.
//
// Pure std — no external crates (the only thing read from each cartridge.json
// is the `domain` string, so a minimal extractor avoids a serde dependency).
//
// Usage:
//   rustc --edition 2021 tools/migrate_cartridges.rs -o /tmp/migrate_cartridges
//   /tmp/migrate_cartridges [SRC] [DST] [--execute]
// SRC/DST default to the original migration paths when omitted.

use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

// Cartridges that are intrinsically cross-cutting (not bound to one domain).
const CROSS_CUTTING: &[(&str, &str)] = &[
    ("agent-mcp", "agentic"),
    ("claude-agents-power-mcp", "agentic"),
    ("claude-ai-mcp", "agentic"),
    ("local-coord-mcp", "agentic"),
    ("model-router-mcp", "agentic"),
    ("nesy-mcp", "nesy"),
    ("ml-mcp", "nesy"),
    ("fleet-mcp", "fleet"), // fleet orchestration is cross-cutting
    ("boj-health", "health"), // health/observability harness
    ("dap-mcp", "debug"), // generic debug adapter
    ("bsp-mcp", "build"), // generic build server
];

// Canonical scaffold templates (kept under templates/).
const TEMPLATES: &[&str] = &["gossamer-mcp"];

// Domain normalisation map (raw manifest `domain` value -> normalised slug).
const DOMAIN_MAP: &[(&str, &str)] = &[
    ("ai", "ai"), ("AI", "ai"),
    ("agent orchestration", "ai"),
    ("AI/NeSy", "nesy"), // cross-cutting cartridges handled by CROSS_CUTTING
    ("cloud", "cloud"), ("Cloud", "cloud"),
    ("database", "database"), ("Database", "database"),
    ("registry", "registry"), ("Registry", "registry"),
    ("package management", "registry"), ("Package Management", "registry"),
    ("container", "container"), ("Container", "container"),
    ("container orchestration", "container"), ("Container Orchestration", "container"),
    ("ci", "ci-cd"), ("CI/CD", "ci-cd"), ("CI/CD Intelligence", "ci-cd"),
    ("development", "development"), ("Developer Tools", "development"),
    ("code analysis", "code-quality"), ("Code Analysis", "code-quality"),
    ("code quality", "code-quality"), ("Code Quality", "code-quality"),
    ("communications", "communications"), ("Communications", "communications"),
    ("communication", "communications"), ("Communication", "communications"),
    ("compiler", "languages"), ("Compiler", "languages"),
    ("dezig", "languages"),
    ("languages", "languages"), ("Languages", "languages"),
    ("language tools", "languages"), ("Language Tools", "languages"),
    ("lsp", "languages"), ("LSP", "languages"),
    ("security", "security"), ("Security", "security"),
    ("productivity", "productivity"), ("Productivity", "productivity"),
    ("research", "research"), ("Research", "research"),
    ("infrastructure", "infrastructure"), ("Infrastructure", "infrastructure"),
    ("monitoring", "observability"), ("Monitoring", "observability"),
    ("observability", "observability"),
    ("knowledge", "knowledge"), ("Knowledge", "knowledge"),
    ("knowledge & memory", "knowledge"), ("Knowledge & Memory", "knowledge"),
    ("formal verification", "formal-verification"), ("Formal Verification", "formal-verification"),
    ("bioinformatics", "bioinformatics"), ("Bioinformatics", "bioinformatics"),
    ("open data", "open-data"), ("Open Data", "open-data"),
    ("education", "education"), ("Education", "education"),
    ("legal", "legal"),
    ("gaming", "gaming"),
    ("project-management", "project-management"),
    ("community", "community"),
    ("automation", "automation"),
    ("repository management", "repository-management"), ("Repository Management", "repository-management"),
    ("desktop/ui", "desktop-ui"), ("Desktop/UI", "desktop-ui"),
    ("multimodal", "multimodal"),
    ("vector", "vector"),
    ("messaging", "messaging"),
    ("config", "config"), ("configuration", "config"),
    ("web", "web"),
];

// Canonical role suffixes (mirrors the original ROLE_RE; informational only —
// placement does not depend on it, but cartridges lacking one are reported).
const ROLE_SUFFIXES: &[&str] = &[
    "mcp", "lsp", "dap", "bsp", "debug", "format", "lint", "build", "nesy", "agentic", "fleet",
];

fn has_role_suffix(name: &str) -> bool {
    ROLE_SUFFIXES
        .iter()
        .any(|s| name.ends_with(&format!("-{}", s)))
}

/// Minimal extractor for the JSON string field `"domain": "<value>"`.
/// Returns None if the key or its quoted value is absent.
fn extract_domain(json: &str) -> Option<String> {
    let after_key = &json[json.find("\"domain\"")? + "\"domain\"".len()..];
    let after_colon = &after_key[after_key.find(':')? + 1..];
    let after_open = &after_colon[after_colon.find('"')? + 1..];
    let close = after_open.find('"')?;
    Some(after_open[..close].to_string())
}

/// kebab-case fallback for unmapped domain values (mirrors the original
/// `re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-")`).
fn kebab(s: &str) -> String {
    let mut out = String::new();
    let mut prev_dash = false;
    for c in s.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
            prev_dash = false;
        } else if !prev_dash {
            out.push('-');
            prev_dash = true;
        }
    }
    out.trim_matches('-').to_string()
}

fn copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() {
            copy_dir(&from, &to)?;
        } else {
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

fn main() {
    let argv: Vec<String> = env::args().collect();
    let execute = argv.iter().any(|a| a == "--execute");
    let positional: Vec<&str> = argv[1..]
        .iter()
        .filter(|a| !a.starts_with("--"))
        .map(|s| s.as_str())
        .collect();
    let src = PathBuf::from(
        positional
            .get(0)
            .copied()
            .unwrap_or("/home/hyperpolymath/developer/repos/boj-server/cartridges"),
    );
    let dst = PathBuf::from(
        positional
            .get(1)
            .copied()
            .unwrap_or("/tmp/boj-server-cartridges/cartridges"),
    );

    let cross: BTreeMap<&str, &str> = CROSS_CUTTING.iter().copied().collect();
    let domains: BTreeMap<&str, &str> = DOMAIN_MAP.iter().copied().collect();
    let templates: BTreeSet<&str> = TEMPLATES.iter().copied().collect();
    let dst_parent = dst.parent().map(Path::to_path_buf).unwrap_or_else(|| dst.clone());

    let mut entries: Vec<PathBuf> = match fs::read_dir(&src) {
        Ok(rd) => rd.filter_map(|e| e.ok().map(|e| e.path())).collect(),
        Err(e) => {
            eprintln!("ERROR: cannot read SRC {}: {}", src.display(), e);
            std::process::exit(2);
        }
    };
    entries.sort();

    let mut stats: BTreeMap<&str, usize> = BTreeMap::new();
    // (name, Some(relative target) | None for skip, category)
    let mut placements: Vec<(String, Option<String>, String)> = Vec::new();
    let mut unmapped_domains: BTreeSet<String> = BTreeSet::new();
    let mut unmapped_roles: Vec<String> = Vec::new();

    for cart_dir in &entries {
        if !cart_dir.is_dir() {
            continue;
        }
        let name = cart_dir.file_name().unwrap().to_string_lossy().to_string();
        let manifest = cart_dir.join("cartridge.json");
        if !manifest.exists() {
            *stats.entry("skipped_no_manifest").or_insert(0) += 1;
            placements.push((name, None, "SKIP (no cartridge.json)".to_string()));
            continue;
        }
        let data = match fs::read_to_string(&manifest) {
            Ok(s) => s,
            Err(e) => {
                *stats.entry("skipped_bad_json").or_insert(0) += 1;
                placements.push((name, None, format!("SKIP (read error: {})", e)));
                continue;
            }
        };

        if !has_role_suffix(&name) {
            unmapped_roles.push(name.clone());
        }

        let (target, category): (PathBuf, &str) = if templates.contains(name.as_str()) {
            (dst.join("templates").join(&name), "template")
        } else if let Some(sub) = cross.get(name.as_str()) {
            (dst.join("cross-cutting").join(sub).join(&name), "cross-cutting")
        } else {
            let domain_raw = extract_domain(&data).unwrap_or_else(|| "unknown".to_string());
            let domain_norm = match domains.get(domain_raw.as_str()) {
                Some(d) => (*d).to_string(),
                None => {
                    unmapped_domains.insert(domain_raw.clone());
                    let k = kebab(&domain_raw);
                    if k.is_empty() { "unknown".to_string() } else { k }
                }
            };
            (dst.join("domains").join(&domain_norm).join(&name), "domain")
        };

        *stats.entry(category).or_insert(0) += 1;
        let rel = target
            .strip_prefix(&dst_parent)
            .unwrap_or(&target)
            .to_string_lossy()
            .to_string();
        placements.push((name, Some(rel), category.to_string()));
    }

    let bar = "=".repeat(80);
    println!("{bar}");
    println!("PLACEMENT PLAN ({} cartridges)", placements.len());
    println!("{bar}");
    println!("  Templates:     {}", stats.get("template").copied().unwrap_or(0));
    println!("  Cross-cutting: {}", stats.get("cross-cutting").copied().unwrap_or(0));
    println!("  Domain-bound:  {}", stats.get("domain").copied().unwrap_or(0));
    println!("  Skipped (no manifest): {}", stats.get("skipped_no_manifest").copied().unwrap_or(0));
    println!("  Skipped (read error):  {}", stats.get("skipped_bad_json").copied().unwrap_or(0));
    println!();
    if !unmapped_domains.is_empty() {
        let v: Vec<&String> = unmapped_domains.iter().collect();
        println!("Unmapped domain values (kebab-cased as fallback): {v:?}");
    }
    if !unmapped_roles.is_empty() {
        println!("Cartridges without canonical role suffix: {unmapped_roles:?}");
    }
    println!();

    if execute {
        let mut copied = 0usize;
        for (name, target_rel, _cat) in &placements {
            let Some(rel) = target_rel else { continue };
            let from = src.join(name);
            let to = dst_parent.join(rel);
            if let Some(parent) = to.parent() {
                let _ = fs::create_dir_all(parent);
            }
            match copy_dir(&from, &to) {
                Ok(()) => copied += 1,
                Err(e) => eprintln!("WARN: copy {} failed: {}", from.display(), e),
            }
        }
        println!("COPIED {copied} cartridges into {}", dst.display());
    } else {
        let mut by_cat: BTreeMap<&str, Vec<(&String, &String)>> = BTreeMap::new();
        for (n, t, c) in &placements {
            if let Some(t) = t {
                by_cat.entry(c.as_str()).or_default().push((n, t));
            }
        }
        for cat in ["template", "cross-cutting", "domain"] {
            if let Some(rows) = by_cat.get(cat) {
                println!("\n--- {} (first 8) ---", cat.to_uppercase());
                for (n, t) in rows.iter().take(8) {
                    println!("  {n:35} -> {t}");
                }
                if rows.len() > 8 {
                    println!("  ... and {} more", rows.len() - 8);
                }
            }
        }
    }
}
