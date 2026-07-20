/* Gameglass matrix page: loads api/games.json once and does all filtering,
   sorting and pagination client-side. Filter state lives in the URL. */
(() => {
  "use strict";

  const PER_PAGE = 50;
  const STREAM_STATUSES = ["free", "included", "purchase"];
  const STATUS_META = {
    included: { symbol: "✓", label: "Included" },
    purchase: { symbol: "$", label: "Purchase" },
    free: { symbol: "⊛", label: "Free" },
    unavailable: { symbol: "✗", label: "Unavailable" },
  };

  const $ = (id) => document.getElementById(id);
  let data = null;

  const state = {
    search: "",
    streamable_on: "",
    purchase_on: "",
    f2p: false,
    added: false,
    changed: false,
    removed: false,
    page: 1,
  };

  function readUrl() {
    const q = new URLSearchParams(location.search);
    state.search = q.get("search") || "";
    state.streamable_on = q.get("streamable_on") || "";
    state.purchase_on = q.get("purchase_on") || "";
    state.f2p = q.get("f2p_only") === "true";
    state.added = q.get("recently_added") === "true";
    state.changed = q.get("recently_changed") === "true";
    state.removed = q.get("removed") === "true";
    state.page = Math.max(parseInt(q.get("page") || "1", 10) || 1, 1);
  }

  function writeUrl() {
    const q = new URLSearchParams();
    if (state.search) q.set("search", state.search);
    if (state.streamable_on) q.set("streamable_on", state.streamable_on);
    if (state.purchase_on) q.set("purchase_on", state.purchase_on);
    if (state.f2p) q.set("f2p_only", "true");
    if (state.added) q.set("recently_added", "true");
    if (state.changed) q.set("recently_changed", "true");
    if (state.removed) q.set("removed", "true");
    if (state.page > 1) q.set("page", String(state.page));
    const qs = q.toString();
    history.replaceState(null, "", qs ? `?${qs}` : location.pathname);
  }

  /* --- filtering / sorting ------------------------------------------------ */

  function recent(iso) {
    if (!iso) return false;
    return Date.now() - Date.parse(iso) <= data.recent_days * 86400e3;
  }

  function filtered() {
    const search = state.search.trim().toLowerCase();
    return data.games.filter((g) => {
      if (state.removed ? g.streamable : !g.streamable) return false;
      if (search && !(g.title || "").toLowerCase().includes(search)) return false;
      if (state.f2p && !g.is_free) return false;
      if (state.streamable_on && !STREAM_STATUSES.includes(g.tiers[state.streamable_on]))
        return false;
      if (state.purchase_on && g.tiers[state.purchase_on] !== "purchase") return false;
      if (state.added && !recent(g.added_at)) return false;
      if (state.changed && !recent(g.last_changed_at)) return false;
      return true;
    });
  }

  const ts = (iso) => (iso ? Date.parse(iso) : 0);

  function sorted(games) {
    const byTitle = (a, b) => (a.title || "").localeCompare(b.title || "");
    if (state.removed) {
      return games.sort((a, b) => ts(b.removed_at) - ts(a.removed_at) || byTitle(a, b));
    }
    // Genuine adds first (newest), then baseline games by first seen, then title.
    return games.sort(
      (a, b) =>
        ts(b.added_at) - ts(a.added_at) ||
        ts(b.first_seen_at) - ts(a.first_seen_at) ||
        byTitle(a, b)
    );
  }

  /* --- rendering ------------------------------------------------------------ */

  const esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]
    );

  function humanize(iso) {
    if (!iso) return "—";
    const days = Math.floor((Date.now() - Date.parse(iso)) / 86400e3);
    if (days <= 0) return "today";
    if (days === 1) return "yesterday";
    if (days < 30) return `${days}d ago`;
    return new Date(iso).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  }

  function badge(status, withLabel) {
    const meta = STATUS_META[status];
    const label = withLabel ? `<span class="badge-label">${meta.label}</span>` : "";
    return `<span class="badge ${esc(status)}" title="${meta.label}">${meta.symbol}${label}</span>`;
  }

  function addedCell(g) {
    if (state.removed) {
      return `<span class="date-cell removed" title="${esc(g.removed_at)}">${humanize(g.removed_at)}</span>`;
    }
    if (!g.added_at) {
      return `<span class="date-cell baseline" title="Present since Gameglass began tracking; true add date unknown">since launch</span>`;
    }
    return `<span class="date-cell" title="${esc(g.added_at)}">${humanize(g.added_at)}</span>`;
  }

  function row(g) {
    const img = g.image_url
      ? `<img src="${esc(g.image_url)}" alt="" loading="lazy" />`
      : "";
    const tierCells = data.tiers
      .map((t) => `<td>${badge(g.tiers[t.key], true)}</td>`)
      .join("");

    return `<tr class="${state.removed ? "removed-row" : ""}">
      <td class="game-cell">
        <div class="game-info">${img}
          <div>
            <div class="game-title" title="${esc(g.title)}">${esc(g.title)}</div>
            <div class="game-pub">${esc(g.publisher || "")}</div>
          </div>
        </div>
      </td>
      ${tierCells}
      <td class="num">${esc(g.price_formatted || "—")}</td>
      <td class="num">${addedCell(g)}</td>
      <td class="links-cell">
        <a href="${esc(g.links.play_new)}" target="_blank" rel="noopener" title="Stream on play.xbox.com (new client)">☁</a>
        <a href="${esc(g.links.play_legacy)}" target="_blank" rel="noopener" title="Stream on xbox.com/play (legacy client)">▶</a>
        <a href="${esc(g.links.store)}" target="_blank" rel="noopener" title="View in the Xbox Store">⌂</a>
      </td>
    </tr>`;
  }

  function shortTier(name) {
    return name.replace(/^Game Pass /, "");
  }

  function activeFilters() {
    return (
      state.search !== "" ||
      state.streamable_on !== "" ||
      state.purchase_on !== "" ||
      state.f2p ||
      state.added ||
      state.changed
    );
  }

  function renderMeta() {
    const run = data.last_run;
    let html = "Not yet scanned";
    if (run) {
      if (run.status === "failed") {
        html = `<span class="scan-failed">Last scan failed ${humanize(run.finished_at)}</span> · Data updated ${humanize(data.generated_at)}`;
      } else {
        html = `Updated ${humanize(run.finished_at)}`;
        if (run.added > 0) html += ` <span class="added-count">· +${run.added} added</span>`;
        if (run.removed > 0) html += ` <span class="removed-count">· −${run.removed} removed</span>`;
      }
    }
    $("updated").innerHTML = html;
    $("stat-games").textContent = data.count.toLocaleString();

    $("legend").innerHTML = Object.keys(STATUS_META)
      .map((s) => `${badge(s, true)}`)
      .join(" ");

    $("head-row").innerHTML =
      `<th>Game</th>` +
      data.tiers.map((t) => `<th>${esc(shortTier(t.name))}</th>`).join("") +
      `<th class="num">Price</th><th class="num" id="date-head"></th><th class="num">Links</th>`;
  }

  function render() {
    const games = sorted(filtered());
    const totalPages = Math.max(Math.ceil(games.length / PER_PAGE), 1);
    state.page = Math.min(state.page, totalPages);
    const pageGames = games.slice((state.page - 1) * PER_PAGE, state.page * PER_PAGE);

    $("date-head").textContent = state.removed ? "Removed" : "Added";

    $("rows").innerHTML = pageGames.length
      ? pageGames.map(row).join("")
      : `<tr><td class="empty" colspan="${data.tiers.length + 4}">No games match these filters.</td></tr>`;

    $("result-count").textContent =
      `${games.length.toLocaleString()} ${games.length === 1 ? "result" : "results"}`;

    const removedTotal = data.games.filter((g) => !g.streamable).length;
    const toggle = $("toggle-removed");
    toggle.textContent = state.removed ? "↩ Back to catalog" : `Show removed (${removedTotal})`;
    toggle.classList.toggle("active", state.removed);

    $("clear-filters").classList.toggle("hidden", !activeFilters());

    $("pager").classList.toggle("hidden", totalPages <= 1);
    $("page-label").textContent = `Page ${state.page} of ${totalPages}`;
    $("prev").disabled = state.page <= 1;
    $("next").disabled = state.page >= totalPages;

    writeUrl();
  }

  /* --- wiring ------------------------------------------------------------- */

  function syncControls() {
    $("f-search").value = state.search;
    $("f-streamable").value = state.streamable_on;
    $("f-purchase").value = state.purchase_on;
    $("f-f2p").checked = state.f2p;
    $("f-added").checked = state.added;
    $("f-changed").checked = state.changed;
  }

  function onChange(key, value) {
    state[key] = value;
    state.page = 1;
    render();
  }

  function wire() {
    let debounce;
    $("f-search").addEventListener("input", (e) => {
      clearTimeout(debounce);
      debounce = setTimeout(() => onChange("search", e.target.value), 300);
    });
    $("f-streamable").addEventListener("change", (e) => onChange("streamable_on", e.target.value));
    $("f-purchase").addEventListener("change", (e) => onChange("purchase_on", e.target.value));
    $("f-f2p").addEventListener("change", (e) => onChange("f2p", e.target.checked));
    $("f-added").addEventListener("change", (e) => onChange("added", e.target.checked));
    $("f-changed").addEventListener("change", (e) => onChange("changed", e.target.checked));
    $("toggle-removed").addEventListener("click", () => onChange("removed", !state.removed));
    $("clear-filters").addEventListener("click", () => {
      Object.assign(state, {
        search: "",
        streamable_on: "",
        purchase_on: "",
        f2p: false,
        added: false,
        changed: false,
        page: 1,
      });
      syncControls();
      render();
    });
    $("prev").addEventListener("click", () => {
      state.page -= 1;
      render();
      scrollTo({ top: 0 });
    });
    $("next").addEventListener("click", () => {
      state.page += 1;
      render();
      scrollTo({ top: 0 });
    });
    $("filters").addEventListener("submit", (e) => e.preventDefault());
  }

  async function init() {
    readUrl();
    try {
      const response = await fetch("api/games.json");
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      data = await response.json();
    } catch {
      $("updated").textContent = "Failed to load api/games.json";
      return;
    }

    for (const sel of ["f-streamable", "f-purchase"]) {
      for (const tier of data.tiers) {
        const opt = document.createElement("option");
        opt.value = tier.key;
        opt.textContent = shortTier(tier.name);
        $(sel).appendChild(opt);
      }
    }

    syncControls();
    wire();
    renderMeta();
    render();
  }

  init();
})();
