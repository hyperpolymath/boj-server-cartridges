// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// hypatia: allow cicd_rules/javascript_detected -- static-site interactivity; no AS binding for DOM yet
// cartridges.boj-server.net — cartridge registry browser. Zero dependencies.
(() => {
  "use strict";
  const REGISTRY = "https://github.com/hyperpolymath/boj-server-cartridges";
  const state = { catalog: [], filtered: [] };

  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function cardTemplate(c) {
    const srcHref = REGISTRY + "/tree/main/" + c.path;
    const protocols = (c.protocols || []).map(p => `<span>${esc(p)}</span>`).join("");
    return `<li class="card">
  <div class="card-top">
    <span class="card-name">${esc(c.name)}</span>
    <span class="card-tier">${esc(c.tier)}</span>
  </div>
  <p class="card-desc">${esc(c.description)}</p>
  <div class="card-meta">
    <span>${esc(c.domain)}</span>
    <span>${esc(c.bucket)}</span>
    ${c.auth && c.auth !== "none" ? `<span>auth:${esc(c.auth)}</span>` : ""}
    <span>${c.toolCount} tool${c.toolCount !== 1 ? "s" : ""}</span>
    ${protocols}
  </div>
  <div class="card-actions">
    <a class="card-src" href="${esc(srcHref)}" target="_blank" rel="noreferrer">source ↗</a>
  </div>
</li>`;
  }

  function applyFilters() {
    const q = (document.getElementById("q").value || "").toLowerCase();
    const group = document.getElementById("filter-group").value;
    const tier = document.getElementById("filter-tier").value;
    state.filtered = state.catalog.filter(c => {
      if (tier && c.tier !== tier) return false;
      if (group && c.group !== group) return false;
      if (q && !c.name.toLowerCase().includes(q) && !c.description.toLowerCase().includes(q)) return false;
      return true;
    });
    document.getElementById("cards").innerHTML = state.filtered.map(cardTemplate).join("");
    const status = document.getElementById("cat-status");
    status.textContent = state.filtered.length === state.catalog.length
      ? `Showing all ${state.catalog.length} cartridges`
      : `Showing ${state.filtered.length} of ${state.catalog.length} cartridges`;
  }

  function populateGroups() {
    const groups = [...new Set(state.catalog.map(c => c.group))].sort();
    const sel = document.getElementById("filter-group");
    groups.forEach(g => {
      const opt = document.createElement("option");
      opt.value = g;
      opt.textContent = g;
      sel.appendChild(opt);
    });
  }

  async function loadCatalogue() {
    try {
      const res = await fetch("/catalog.json", { cache: "no-cache" });
      const data = await res.json();
      state.catalog = (data.cartridges || []).sort((a, b) => a.name.localeCompare(b.name));
      const total = document.getElementById("total-count");
      if (total) total.textContent = state.catalog.length;
      populateGroups();
      applyFilters();
    } catch (err) {
      document.getElementById("cards").innerHTML =
        `<li style="color:var(--fg-dim);padding:1rem;">Failed to load catalogue: ${esc(String(err))}</li>`;
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    document.getElementById("q").addEventListener("input", applyFilters);
    document.getElementById("filter-group").addEventListener("change", applyFilters);
    document.getElementById("filter-tier").addEventListener("change", applyFilters);
    loadCatalogue();
  });
})();
