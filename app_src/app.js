"use strict";

// icon: game sprite cropped from a render (icons/*.png); null = text-only button
const CHAMBERS = [
  { key: "gadget", label: "Gadgets", color: "#f2c14e", ranked: true, icon: "gadget" },
  { key: "supplement", label: "Supplements", color: "#ef7d57", ranked: true, icon: "supplement" },
  { key: "relic", label: "Relic", color: "#5fd3a5", ranked: false, icon: "relic" },
  { key: "relic_switch", label: "Relic switches", color: "#f07fb0", ranked: false, icon: "relic_switch" },
];
const FIELDS = [
  { key: "iron", label: "Iron", color: "#e0894a", icon: "iron" },
  { key: "water", label: "Water", color: "#3fa7e0", icon: "water" },
  { key: "cobalt", label: "Cobalt", color: "#a77ae8", icon: "cobalt" },
  { key: "in_map", label: "Map footprint", color: "#9fb8d8", icon: null },
];
const ROOM_COLOR = "#f25f5c";
const ROOM_NAMES = {
  mushroom: "Mushroom", bomb: "Bomb", helmet: "Helmet", seed: "Seed", drone: "Drone",
  scanner: "Scanner", cobalt: "Cobalt", water: "Water", iron: "Iron tree", portal: "Portal",
  seed_assignment: "Tree farm seed", nest: "Nest", drillbert: "Drillbert", lunar: "Dragon",
  halloween: "Skeleton",
};
const roomName = (id) => ROOM_NAMES[id] || id;
// rooms that hold a resource reuse its icon; the rest are cut from the room scenes (room_icons.gd)
const roomIcon = (id) => ({ iron: "iron", water: "water", cobalt: "cobalt" })[id] || `room_${id}`;
const GROUP_ORDER = ["Guild assignment", "Relic Hunt", "Co-op (2 players)", "Prestige"];
const SIZE_ORDER = ["small", "medium", "large", "huge"];
const ORDINAL = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"];

const $ = (id) => document.getElementById(id);
const state = {
  index: [], data: null, decoded: {}, tag: null,
  active: { gadget: true, supplement: true, relic: false, relic_switch: false },
  fields: { iron: false, water: false, cobalt: false, in_map: false }, opacity: 1, showMap: true, smooth: true,
  view: { s: 1, tx: 0, ty: 0 }, hover: null, sample: 0,
  rooms: {}, nest: true,
};
const pending = {};

window.DK = {
  index(list) { state.index = list; initControls(); },
  version(v) {
    $("version").textContent = `game ${v.game} · Steam build ${v.steam_build}`;
    $("version").title = "Dome Keeper version the maps were generated and rendered with";
  },
  register(data) {
    state.decoded[data.tag] = decodeLayers(data);
    if (pending[data.tag]) { pending[data.tag](data); delete pending[data.tag]; }
  },
};

function decodeLayers(data) {
  const out = {};
  for (const [k, v] of Object.entries(data.layers)) {
    const bin = atob(v.data);
    const vals = new Float32Array(bin.length);
    const scale = v.vmax / 255;
    for (let i = 0; i < bin.length; i++) vals[i] = bin.charCodeAt(i) * scale;
    out[k] = { vals, vmax: v.vmax };
  }
  const caves = {};
  for (const [variant, c] of Object.entries(data.caves || {})) {
    caves[variant] = {};
    for (const [k, v] of Object.entries(c.layers)) caves[variant][k] = decodeLayer(v);
  }
  return { data, layers: out, caves, roomSums: {} };
}

function decodeLayer(v) {
  const bin = atob(v.data);
  const vals = new Float32Array(bin.length);
  const scale = v.vmax / 255;
  for (let i = 0; i < bin.length; i++) vals[i] = bin.charCodeAt(i) * scale;
  return { vals, vmax: v.vmax };
}

function loadTag(tag) {
  if (state.decoded[tag]) return Promise.resolve(state.decoded[tag].data);
  return new Promise((resolve, reject) => {
    pending[tag] = resolve;
    const s = document.createElement("script");
    s.src = `data/${tag}.js`;
    s.onerror = () => reject(new Error(`missing data/${tag}.js`));
    document.body.appendChild(s);
  });
}

/* ---------- mode controls ---------- */

function entriesOf(group) { return state.index.filter((e) => e.group === group); }

function initControls() {
  const groups = GROUP_ORDER.filter((g) => entriesOf(g).length);
  fillSelect($("mode"), groups.map((g) => [g, g]));

  const challenges = [];
  for (const e of entriesOf("Guild assignment")) {
    for (const c of e.challenges || []) challenges.push([`${e.tag}|${c.id}`, c.title]);
  }
  challenges.sort((a, b) => a[1].localeCompare(b[1]));
  fillSelect($("challenge"), challenges);
  fillSelect($("prestige"), entriesOf("Prestige").map((e) => [e.tag, e.archetype.replace("prestige-", "") + " tiles"]));

  buildChips();

  const fromHash = decodeURIComponent(location.hash.slice(1));
  const hashEntry = state.index.find((e) => e.tag === fromHash.split("|")[0]);
  if (hashEntry) {
    $("mode").value = hashEntry.group;
    if (hashEntry.group === "Guild assignment") {
      const opt = [...$("challenge").options].find((o) => o.value === fromHash) ||
        [...$("challenge").options].find((o) => o.value.startsWith(hashEntry.tag + "|"));
      if (opt) $("challenge").value = opt.value;
    }
  } else {
    const proj = [...$("challenge").options].find((o) => o.value.endsWith("|projectilehell"));
    if (proj) $("challenge").value = proj.value;
  }
  onModeChange(hashEntry);

  for (const id of ["mode"]) $(id).addEventListener("change", () => onModeChange());
  for (const id of ["challenge", "size", "modifier", "prestige"]) $(id).addEventListener("change", selectFromControls);
  $("opacity").addEventListener("input", () => { state.opacity = +$("opacity").value; drawOverlay(); });
  $("show-map").addEventListener("change", () => { state.showMap = $("show-map").checked; updateBackground(); });
  $("smooth").addEventListener("change", () => { state.smooth = $("smooth").checked; drawOverlay(); });
  $("nest").addEventListener("change", () => { state.nest = $("nest").checked; fillRooms(); redraw(); });
}

/* ---------- rooms ---------- */

function roomRules(settings) {
  const get = (k, dflt) => { const m = settings.match(new RegExp(k + "=(\\S+)")); return m ? +m[1] : dflt; };
  const per = get("max_per_biome", 1), dist = get("min_dist", 10);
  return `At most ${per === 1 ? "one room" : per + " rooms"} per biome layer` +
    (dist > 0 ? `, at least ${dist} tiles left or right of the dome.` : ".");
}

function roomVariant() {
  const c = state.data.caves || {};
  return state.nest && c.nest ? "nest" : c.base ? "base" : null;
}

function fillRooms() {
  const c = state.data.caves || {};
  $("ctl-nest").hidden = !c.nest;
  const v = roomVariant();
  const ids = v ? Object.keys(c[v].per_map).sort((a, b) => roomName(a).localeCompare(roomName(b))) : [];
  for (const id of ids) if (!(id in state.rooms)) state.rooms[id] = false;
  makeToggleRow($("room-chips"), ids.map((id) => ({
    key: id, label: roomName(id), color: ROOM_COLOR, icon: roomIcon(id),
    title: `${roomName(id)} room: on ${fmtP(c[v].per_map[id].any)} of maps`,
  })), state.rooms);
  if (!ids.length) $("room-chips").innerHTML = `<div class="about">No rooms on this map type.</div>`;
}

function selectedRooms() {
  const v = roomVariant();
  return v ? Object.keys(state.data.caves[v].per_map).filter((id) => state.rooms[id]).sort() : [];
}

function roomLayer() {
  const v = roomVariant(), ids = selectedRooms();
  if (!ids.length) return null;
  const dec = state.decoded[state.tag];
  if (ids.length === 1) return dec.caves[v][ids[0]];
  const key = v + ":" + ids.join(",");
  if (!dec.roomSums[key]) {
    const layers = ids.map((id) => dec.caves[v][id]);
    const vals = new Float32Array(layers[0].vals.length);
    for (const l of layers) for (let i = 0; i < vals.length; i++) vals[i] += l.vals[i];
    dec.roomSums[key] = { vals, vmax: vals.reduce((m, x) => Math.max(m, x), 0) };
  }
  return dec.roomSums[key];
}


function fillSelect(sel, items) {
  sel.innerHTML = "";
  for (const [v, label] of items) {
    const o = document.createElement("option");
    o.value = v; o.textContent = label;
    sel.appendChild(o);
  }
}

function onModeChange(preset) {
  const group = $("mode").value;
  const show = { challenge: false, size: false, modifier: false, prestige: false };
  if (group === "Guild assignment") show.challenge = true;
  if (group === "Relic Hunt") { show.size = true; show.modifier = true; }
  if (group === "Co-op (2 players)") show.size = true;
  if (group === "Prestige") show.prestige = true;
  for (const k of Object.keys(show)) $(`ctl-${k}`).hidden = !show[k];

  if (show.size) {
    const sizes = [...new Set(entriesOf(group).map((e) => e.size))].sort((a, b) => SIZE_ORDER.indexOf(a) - SIZE_ORDER.indexOf(b));
    fillSelect($("size"), sizes.map((s) => [s, s[0].toUpperCase() + s.slice(1)]));
    if (preset && preset.size) $("size").value = preset.size;
  }
  if (show.modifier) {
    const mods = [...new Set(entriesOf(group).map((e) => e.modifier || ""))];
    mods.sort((a, b) => (a === "" ? -1 : b === "" ? 1 : a.localeCompare(b)));
    fillSelect($("modifier"), mods.map((m) => [m, m || "None"]));
    if (preset) $("modifier").value = preset.modifier || "";
  }
  if (show.prestige && preset && preset.group === "Prestige") $("prestige").value = preset.tag;
  selectFromControls();
}

function selectFromControls() {
  const group = $("mode").value;
  let tag = null, hash = null;
  if (group === "Guild assignment") { hash = $("challenge").value; tag = hash.split("|")[0]; }
  else if (group === "Relic Hunt") {
    const e = entriesOf(group).find((x) => x.size === $("size").value && (x.modifier || "") === $("modifier").value);
    tag = e && e.tag;
  } else if (group === "Co-op (2 players)") {
    const e = entriesOf(group).find((x) => x.size === $("size").value);
    tag = e && e.tag;
  } else if (group === "Prestige") tag = $("prestige").value;
  if (!tag) return;
  history.replaceState(null, "", "#" + encodeURIComponent(hash || tag));
  showTag(tag);
}

function buildChips() {
  makeToggleRow($("chamber-chips"), CHAMBERS, state.active);
  makeToggleRow($("field-chips"), FIELDS, state.fields);
}

function makeToggleRow(box, items, flags) {
  box.innerHTML = "";
  for (const c of items) {
    const b = document.createElement("button");
    b.className = "chip";
    b.type = "button";
    b.setAttribute("aria-pressed", String(flags[c.key]));
    const icon = c.icon ? `<img class="ico" src="icons/${c.icon}.png" alt="">` : `<span class="ico-blank"></span>`;
    if (c.title) b.title = c.title;
    b.innerHTML = `${icon}<span>${c.label}</span><span class="sw" style="background:${c.color}" title="overlay colour"></span>`;
    b.addEventListener("click", () => {
      flags[c.key] = !flags[c.key];
      b.setAttribute("aria-pressed", String(flags[c.key]));
      redraw();
    });
    box.appendChild(b);
  }
}

/* ---------- loading a config ---------- */

async function showTag(tag) {
  $("loading").hidden = false;
  const firstLoad = state.tag === null;
  const prevData = state.data;
  try {
    const data = await loadTag(tag);
    state.tag = tag;
    state.data = data;
    const img = $("bg");
    state.sample = 0;
    await updateBackground();
    const W = data.w * data.px, H = data.h * data.px;
    for (const el of [img, $("overlay")]) { el.style.width = W + "px"; el.style.height = H + "px"; }
    $("overlay").width = data.w * data.px;
    $("overlay").height = data.h * data.px;
    $("hover-tile").style.width = $("hover-tile").style.height = data.px + "px";
    fillRooms();
    if (firstLoad || !prevData || prevData.w !== data.w || prevData.h !== data.h || prevData.px !== data.px) fit();
    redraw();
  } catch (err) {
    $("loading").textContent = String(err.message || err);
    return;
  }
  $("loading").hidden = true;
}

/* ---------- background map ---------- */

function updateBackground() {
  const d = state.data, img = $("bg");
  const s = d.samples[state.sample];
  $("sample-label").textContent = s ? `map seed ${s.seed}` : "no rendered map";
  img.classList.toggle("hidden", !state.showMap || !s);
  if (!s) return Promise.resolve();
  return new Promise((resolve) => {
    img.onload = resolve;
    img.onerror = resolve;
    img.src = `maps/${d.tag}/${s.k}.png`;
  });
}

/* ---------- overlay ---------- */

function activeLayers() {
  const L = state.decoded[state.tag].layers;
  const out = [];
  for (const f of FIELDS) {
    if (state.fields[f.key] && L[f.key]) out.push({ key: f.key, label: f.label, color: f.color, layer: L[f.key], field: true });
  }
  for (const c of CHAMBERS) {
    if (!state.active[c.key]) continue;
    if (L[c.key]) out.push({ key: c.key, label: c.label, color: c.color, layer: L[c.key], field: false });
  }
  const room = roomLayer();
  if (room) {
    const ids = selectedRooms();
    const label = ids.length === 1 ? roomName(ids[0]) : "Rooms: " + ids.map(roomName).join(", ");
    out.push({ key: "room", label, color: ROOM_COLOR, layer: room, field: false, room: true });
  }
  return out;
}

function hexRgb(h) { return [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)); }

function drawOverlay() {
  if (!state.data) return;
  const { w, h } = state.data;
  const scratch = drawOverlay.scratch || (drawOverlay.scratch = document.createElement("canvas"));
  scratch.width = w;
  scratch.height = h;
  const sctx = scratch.getContext("2d");
  const img = sctx.createImageData(w, h);
  const px = img.data;
  const acc = new Float32Array(w * h * 4);
  for (const a of activeLayers()) {
    const [r, g, b] = hexRgb(a.color);
    const vals = a.layer.vals, vmax = a.layer.vmax || 1;
    const op = state.opacity * (a.field ? 0.8 : 1);
    for (let i = 0; i < w * h; i++) {
      const v = vals[i] / vmax;
      if (v <= 0) continue;
      const al = op * Math.pow(v, 0.6);
      const j = i * 4;
      acc[j] = r * al + acc[j] * (1 - al);
      acc[j + 1] = g * al + acc[j + 1] * (1 - al);
      acc[j + 2] = b * al + acc[j + 2] * (1 - al);
      acc[j + 3] = al + acc[j + 3] * (1 - al);
    }
  }
  for (let i = 0; i < w * h; i++) {
    const j = i * 4, al = acc[j + 3];
    if (al <= 0) continue;
    px[j] = acc[j] / al; px[j + 1] = acc[j + 1] / al; px[j + 2] = acc[j + 2] / al; px[j + 3] = al * 255;
  }
  sctx.putImageData(img, 0, 0);
  const cv = $("overlay");
  const ctx = cv.getContext("2d");
  ctx.clearRect(0, 0, cv.width, cv.height);
  ctx.imageSmoothingEnabled = state.smooth;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(scratch, 0, 0, cv.width, cv.height);
}

function redraw() {
  drawOverlay();
  renderLegend();
  renderStats();
  drawRulers();
  if (state.hover) showHover(state.hover.i, state.hover.j, state.hover.mx, state.hover.my);
}

/* ---------- panel ---------- */

function fmtP(p) {
  if (p >= 0.1) return (p * 100).toFixed(0) + "%";
  if (p >= 0.01) return (p * 100).toFixed(1) + "%";
  if (p > 0) return (p * 100).toFixed(2) + "%";
  return "0%";
}

function fmtLayer(a, v) { return fmtP(v); }

function renderLegend() {
  const box = $("legend");
  const items = activeLayers();
  if (!items.length) { box.innerHTML = `<h3>Layers</h3><div class="about">No layer selected.</div>`; return; }
  box.innerHTML = "<h3>Layers</h3>" + items.map((a) => {
    const [r, g, b] = hexRgb(a.color);
    const what = a.field ? (a.key === "in_map" ? "chance tile is inside the map" : "chance tile holds this resource")
      : a.room ? "chance tile is part of the room" : "chance tile is part of this chamber";
    return `<div class="legend-item">
      <div class="lbl"><span class="sw" style="background:${a.color}"></span>${a.label}</div>
      <div class="ramp" style="background:linear-gradient(90deg, rgba(${r},${g},${b},0.05), rgba(${r},${g},${b},1))"></div>
      <div class="scale"><span>0</span><span>${what}</span><span>${fmtLayer(a, a.layer.vmax)}</span></div>
    </div>`;
  }).join("");
}

function renderStats() {
  const d = state.data;
  const blocks = [];
  for (const c of CHAMBERS.filter((x) => x.ranked)) {
    const rows = (d.ranks[c.key] || []).filter((r) => r.frac_maps >= 0.01);
    if (!rows.length) {
      blocks.push(`<div class="stats-block"><div class="t"><span class="sw" style="background:${c.color}"></span>${c.label}</div><div class="about">None on this map type.</div></div>`);
      continue;
    }
    blocks.push(`<div class="stats-block">
      <div class="t"><span class="sw" style="background:${c.color}"></span>${c.label} · ${(d.per_map[c.key] || 0).toFixed(2)} per map</div>
      <table class="stats-table">
        <tr><th title="order by depth: 1st is the shallowest">#</th><th title="median depth below the surface, in tiles">avg. depth</th><th title="median distance left or right of the dome, in tiles">avg x offset</th><th title="share of maps where it is left of the dome">left</th><th title="share of maps where it is on the opposite side from the previous one">opposite side</th></tr>
        ${rows.map((r) => `<tr><td>${ORDINAL[r.rank - 1]}</td><td>${r.y_median.toFixed(0)}</td><td>${r.absx_median.toFixed(0)}</td><td>${fmtP(r.p_left)}</td><td>${r.p_opposite_prev == null ? "—" : fmtP(r.p_opposite_prev)}</td></tr>`).join("")}
      </table></div>`);
  }
  const relic = d.per_map.relic || 0, sw = d.per_map.relic_switch || 0;
  blocks.push(`<div class="about" style="margin-bottom:14px">Relic: ${relic.toFixed(2)} per map · Relic switches: ${sw.toFixed(2)} per map. Switches sit 7–14 tiles from the relic.</div>`);
  const v = roomVariant();
  if (v) {
    const pm = d.caves[v].per_map;
    const ids = Object.keys(pm).sort((a, b) => pm[b].any - pm[a].any);
    blocks.push(`<div class="stats-block">
      <div class="t"><span class="sw" style="background:${ROOM_COLOR}"></span>Rooms · ${ids.reduce((t, k) => t + pm[k].mean, 0).toFixed(1)} per map</div>
      <table class="stats-table">
        <tr><th title="room type; ×n = average count per map when more than one">room</th><th title="share of maps with at least one of this room">maps</th></tr>
        ${ids.map((k) => `<tr><td>${roomName(k)}${pm[k].mean > 1.05 ? ` ×${pm[k].mean.toFixed(1)}` : ""}</td><td>${fmtP(pm[k].any)}</td></tr>`).join("")}
      </table>
      <div class="about">${roomRules(d.caves[v].settings)} Which rooms appear follows the map seed; where in the layer is random every run.${d.caves.nest ? " With pets left to find, the nest takes one room's place." : ""}${(state.index.find((x) => x.tag === state.tag) || {}).group === "Prestige" ? " Prestige “cave order” (pro setting) fixes the order instead." : ""}</div>
    </div>`);
  }
  $("stats").innerHTML = "<h3>Placement</h3>" + blocks.join("");

  const nRooms = v ? d.caves[v].n_maps : d.n_maps;
  $("about").innerHTML = `Odds computed from ${d.n_maps.toLocaleString()} generated maps` +
    (nRooms !== d.n_maps ? ` (rooms: ${nRooms.toLocaleString()}).` : ".");
}

/* ---------- view: pan / zoom ---------- */

function applyView() {
  const { s, tx, ty } = state.view;
  $("stage").style.transform = `translate(${tx}px, ${ty}px) scale(${s})`;
  drawRulers();
}

function viewportSize() { const r = $("viewport").getBoundingClientRect(); return [r.width, r.height]; }

function sLimits() {
  const d = state.data;
  const [vw, vh] = viewportSize();
  const fitS = Math.min(vw / (d.w * d.px), vh / (d.h * d.px));
  return [fitS * 0.5, 64 / d.px];
}

function fit() {
  const d = state.data;
  if (!d) return;
  const [vw, vh] = viewportSize();
  const s = Math.min(vw / (d.w * d.px), vh / (d.h * d.px)) * 0.96;
  state.view = { s, tx: (vw - d.w * d.px * s) / 2, ty: (vh - d.h * d.px * s) / 2 };
  applyView();
}

function zoomAt(factor, mx, my) {
  const [lo, hi] = sLimits();
  const v = state.view;
  const s2 = Math.min(hi, Math.max(lo, v.s * factor));
  const k = s2 / v.s;
  state.view = { s: s2, tx: mx - (mx - v.tx) * k, ty: my - (my - v.ty) * k };
  applyView();
}

function setupInteraction() {
  const vp = $("viewport");
  vp.addEventListener("wheel", (ev) => {
    if (!state.data) return;
    ev.preventDefault();
    const r = vp.getBoundingClientRect();
    zoomAt(Math.exp(-ev.deltaY * 0.0015), ev.clientX - r.left, ev.clientY - r.top);
    onHover(ev);
  }, { passive: false });

  let drag = null;
  const pointers = new Map();
  vp.addEventListener("pointerdown", (ev) => {
    vp.setPointerCapture(ev.pointerId);
    pointers.set(ev.pointerId, [ev.clientX, ev.clientY]);
    drag = { x: ev.clientX, y: ev.clientY, tx: state.view.tx, ty: state.view.ty, pinch: null };
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      drag.pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]), s: state.view.s };
    }
    vp.classList.add("dragging");
  });
  vp.addEventListener("pointermove", (ev) => {
    if (pointers.has(ev.pointerId)) pointers.set(ev.pointerId, [ev.clientX, ev.clientY]);
    if (drag && pointers.size === 2 && drag.pinch) {
      const [a, b] = [...pointers.values()];
      const r = vp.getBoundingClientRect();
      const d = Math.hypot(a[0] - b[0], a[1] - b[1]);
      zoomAt((drag.pinch.s * d / drag.pinch.d) / state.view.s, (a[0] + b[0]) / 2 - r.left, (a[1] + b[1]) / 2 - r.top);
    } else if (drag && pointers.size === 1) {
      state.view.tx = drag.tx + ev.clientX - drag.x;
      state.view.ty = drag.ty + ev.clientY - drag.y;
      applyView();
    }
    onHover(ev);
  });
  const end = (ev) => {
    pointers.delete(ev.pointerId);
    if (pointers.size === 0) { drag = null; vp.classList.remove("dragging"); }
  };
  vp.addEventListener("pointerup", end);
  vp.addEventListener("pointercancel", end);
  vp.addEventListener("pointerleave", () => { state.hover = null; $("tooltip").hidden = true; $("hover-tile").style.display = "none"; drawRulers(); });

  $("zoom-in").addEventListener("click", () => { const [w, h] = viewportSize(); zoomAt(1.5, w / 2, h / 2); });
  $("zoom-out").addEventListener("click", () => { const [w, h] = viewportSize(); zoomAt(1 / 1.5, w / 2, h / 2); });
  $("zoom-fit").addEventListener("click", fit);
  window.addEventListener("resize", () => { drawRulers(); });
}

/* ---------- hover ---------- */

function onHover(ev) {
  if (!state.data) return;
  const r = $("viewport").getBoundingClientRect();
  const mx = ev.clientX - r.left, my = ev.clientY - r.top;
  const d = state.data, v = state.view;
  const i = Math.floor((mx - v.tx) / v.s / d.px), j = Math.floor((my - v.ty) / v.s / d.px);
  if (i < 0 || j < 0 || i >= d.w || j >= d.h) {
    state.hover = null; $("tooltip").hidden = true; $("hover-tile").style.display = "none"; drawRulers();
    return;
  }
  state.hover = { i, j, mx, my };
  showHover(i, j, mx, my);
}

function showHover(i, j, mx, my) {
  const d = state.data;
  const L = state.decoded[state.tag].layers;
  const ht = $("hover-tile");
  ht.style.display = "block";
  ht.style.left = i * d.px + "px";
  ht.style.top = j * d.px + "px";
  const idx = j * d.w + i;
  const x = i + d.x0, y = j + d.y0;
  const rows = [];
  for (const a of activeLayers()) rows.push([a.color, a.label, fmtLayer(a, a.layer.vals[idx])]);
  const shown = new Set(activeLayers().map((a) => a.key));
  for (const c of CHAMBERS) {
    if (!shown.has(c.key) && L[c.key] && L[c.key].vals[idx] > 0) rows.push([c.color, c.label + " (any)", fmtP(L[c.key].vals[idx])]);
  }
  if (!shown.has("in_map")) rows.push(["#9fb8d8", "Inside map", fmtP(L.in_map.vals[idx])]);
  const rv = roomVariant();
  if (rv && selectedRooms().length > 1) {
    const C = state.decoded[state.tag].caves[rv];
    const top = selectedRooms().map((k) => [k, C[k].vals[idx]]).filter(([, p]) => p > 0)
      .sort((a, b) => b[1] - a[1]).slice(0, 4);
    for (const [k, p] of top) rows.push([ROOM_COLOR, "· " + roomName(k), fmtP(p)]);
  }

  const tt = $("tooltip");
  tt.innerHTML = `<div class="tt-head">x ${x >= 0 ? "+" + x : "−" + -x} · depth ${y}</div>` +
    rows.map(([c, l, v]) => `<div class="tt-row"><span class="sw" style="background:${c}"></span>${l}<span class="v">${v}</span></div>`).join("");
  tt.hidden = false;
  const [vw, vh] = viewportSize();
  const tw = tt.offsetWidth, th = tt.offsetHeight;
  tt.style.left = Math.min(vw - tw - 8, mx + 16) + "px";
  tt.style.top = Math.min(vh - th - 8, my + 16) + "px";
  drawRulers();
}

/* ---------- rulers ---------- */

function prepCanvas(cv) {
  const dpr = window.devicePixelRatio || 1;
  const r = cv.getBoundingClientRect();
  if (cv.width !== Math.round(r.width * dpr) || cv.height !== Math.round(r.height * dpr)) {
    cv.width = Math.round(r.width * dpr);
    cv.height = Math.round(r.height * dpr);
  }
  const ctx = cv.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, r.width, r.height);
  return [ctx, r.width, r.height];
}

function niceStep(minPx, ts, steps) {
  for (const s of steps) if (s * ts >= minPx) return s;
  return steps[steps.length - 1];
}

function drawRuler(cv, horizontal) {
  const [ctx, W, H] = prepCanvas(cv);
  const d = state.data;
  if (!d) return;
  const css = getComputedStyle(document.documentElement);
  const v = state.view;
  const ts = d.px * v.s;
  const minor = niceStep(5, ts, [1, 2, 5, 10, 20, 50, 100]);
  const major = niceStep(34, ts, [1, 2, 5, 10, 20, 50, 100, 200]);
  const origin = horizontal ? v.tx : v.ty;
  const len = horizontal ? W : H;
  const thick = horizontal ? H : W;
  const off = horizontal ? d.x0 : d.y0;
  const n = horizontal ? d.w : d.h;

  const hi = state.hover ? (horizontal ? state.hover.i : state.hover.j) : null;
  if (hi != null) {
    ctx.fillStyle = css.getPropertyValue("--ruler-hl");
    const p = origin + hi * ts;
    if (horizontal) ctx.fillRect(p, 0, ts, H); else ctx.fillRect(0, p, W, ts);
  }

  ctx.strokeStyle = css.getPropertyValue("--ruler-tick");
  ctx.fillStyle = css.getPropertyValue("--ink-muted");
  ctx.font = `10px ${css.getPropertyValue("--mono")}`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  const i0 = Math.max(0, Math.floor(-origin / ts) - 1), i1 = Math.min(n - 1, Math.ceil((len - origin) / ts) + 1);
  ctx.beginPath();
  for (let i = i0; i <= i1; i++) {
    const c = i + off;
    if (c % minor !== 0) continue;
    const p = Math.round(origin + (i + 0.5) * ts) + 0.5;
    const isMajor = c % major === 0;
    const tl = isMajor ? thick * 0.45 : thick * 0.2;
    if (horizontal) { ctx.moveTo(p, H); ctx.lineTo(p, H - tl); } else { ctx.moveTo(W, p); ctx.lineTo(W - tl, p); }
  }
  ctx.stroke();
  for (let i = i0; i <= i1; i++) {
    const c = i + off;
    if (c % major !== 0 || i === hi) continue;
    const p = origin + (i + 0.5) * ts;
    if (horizontal) ctx.fillText(String(c), p, H * 0.32);
    else { ctx.save(); ctx.translate(W * 0.36, p); ctx.fillText(String(c), 0, 0); ctx.restore(); }
  }
  if (hi != null) {
    const c = hi + off, p = origin + (hi + 0.5) * ts;
    ctx.fillStyle = css.getPropertyValue("--ink");
    ctx.font = `600 11px ${css.getPropertyValue("--mono")}`;
    if (horizontal) ctx.fillText(String(c), p, H * 0.32);
    else ctx.fillText(String(c), W * 0.4, p);
  }
}

function drawRulers() {
  drawRuler($("ruler-top"), true);
  drawRuler($("ruler-left"), false);
}

setupInteraction();
