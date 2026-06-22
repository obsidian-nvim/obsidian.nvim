-- HTML page for the graph view. No external assets or dependencies.

local M = [[
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Obsidian Graph View</title>
<style>
  html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
  body { background: #191919; color: #ddd; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  canvas { display: block; width: 100vw; height: 100vh; cursor: grab; }
  canvas.dragging { cursor: grabbing; }
  #loading, #empty { position: fixed; inset: 0; display: grid; place-items: center; color: #888; font-size: 18px; pointer-events: none; }
  #stats { position: fixed; top: 12px; left: 12px; color: #999; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(25,25,25,.75); padding: 5px 8px; border-radius: 4px; }
  #tip { position: fixed; display: none; max-width: 420px; padding: 6px 9px; border: 1px solid #555; border-radius: 5px; background: #2b2b2b; color: #eee; font-size: 13px; pointer-events: none; white-space: pre; z-index: 5; }
  #controls { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); display: none; gap: 8px; padding: 8px; border: 1px solid #444; border-radius: 8px; background: rgba(43,43,43,.92); }
  button { min-width: 34px; border: 0; border-radius: 4px; background: #444; color: #eee; padding: 6px 10px; font-size: 15px; cursor: pointer; }
  button:hover { background: #555; }

  #settings-toggle { position: fixed; top: 12px; right: 12px; z-index: 11; display: none; }
  #side { position: fixed; top: 0; right: 0; bottom: 0; width: 300px; z-index: 10; box-sizing: border-box; padding: 14px; padding-top: 54px; overflow: auto; background: rgba(31,31,31,.96); border-left: 1px solid #444; transform: translateX(100%); transition: transform .16s ease; box-shadow: -12px 0 30px rgba(0,0,0,.25); }
  #side.open { transform: translateX(0); }
  #side h1 { margin: 0 0 12px; font-size: 18px; font-weight: 650; }
  #side h2 { margin: 18px 0 8px; font-size: 12px; color: #aaa; text-transform: uppercase; letter-spacing: .08em; }
  #side label { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin: 9px 0; font-size: 13px; color: #ddd; }
  #side input[type="text"] { width: 100%; box-sizing: border-box; padding: 7px 8px; border: 1px solid #555; border-radius: 5px; background: #252525; color: #eee; }
  #side input[type="range"] { width: 145px; }
  #side input[type="checkbox"] { accent-color: #7c3aed; }
  .muted { color: #999; font-size: 12px; line-height: 1.35; }
  .pill { display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; box-sizing: border-box; padding: 3px 7px; border: 1px solid #555; border-radius: 999px; background: #262626; color: #ddd; font-size: 12px; }
</style>
</head>
<body>
<div id="loading">Loading graph...</div>
<div id="stats"></div>
<div id="tip"></div>
<button id="settings-toggle">☰</button>
<aside id="side" class="open">
  <h1>Graph view</h1>
  <div id="local-block" style="display:none">
    <div class="muted">Local graph</div>
    <div class="pill" id="root-note"></div>
    <h2>Local</h2>
    <label><span>Depth <b id="depth-value">1</b></span><input id="depth" type="range" min="1" max="5" value="1"></label>
  </div>

  <h2>Filters</h2>
  <input id="search" type="text" placeholder="Search files">
  <label><span>Hide orphans</span><input id="hide-orphans" type="checkbox"></label>

  <h2>Display</h2>
  <label><span>Text fade <b id="text-fade-value">0</b></span><input id="text-fade" type="range" min="-3" max="3" value="0" step="0.1"></label>
  <label><span>Arrows</span><input id="show-arrows" type="checkbox"></label>
  <label><span>Node size</span><input id="node-size" type="range" min="0.5" max="2" value="1" step="0.1"></label>
  <label><span>Link width</span><input id="link-width" type="range" min="0.5" max="3" value="1" step="0.1"></label>

  <h2>Forces</h2>
  <label><span>Repel force</span><input id="repel" type="range" min="100" max="1800" value="700" step="50"></label>
  <label><span>Link distance</span><input id="link-distance" type="range" min="40" max="240" value="105" step="5"></label>
  <label><span>Center force</span><input id="center-force" type="range" min="0" max="30" value="8" step="1"></label>

  <h2>About</h2>
  <div class="muted">MVP settings only: search, orphans, text fade, arrows, sizing, and basic force tuning.</div>
</aside>
<div id="controls"><button id="zin">+</button><button id="zout">-</button><button id="reset">&#x27F2;</button></div>
<canvas id="graph"></canvas>
<script>
(function () {
  var canvas = document.getElementById("graph");
  var ctx = canvas.getContext("2d");
  var loading = document.getElementById("loading");
  var stats = document.getElementById("stats");
  var tip = document.getElementById("tip");
  var controls = document.getElementById("controls");
  var side = document.getElementById("side");
  var settingsToggle = document.getElementById("settings-toggle");
  var localBlock = document.getElementById("local-block");
  var depthSlider = document.getElementById("depth");
  var depthValue = document.getElementById("depth-value");

  var params = new URLSearchParams(window.location.search);
  var localRoot = params.get("note");
  var localMode = localRoot != null;
  var activeId = localRoot;
  var graphToken = "__OBSIDIAN_GRAPH_TOKEN__";
  var rawGraph = null;
  var width = 0, height = 0, dpr = 1;
  var nodes = [], links = [], byId = Object.create(null), neighbors = Object.create(null);
  var transform = { x: 0, y: 0, k: 1 };
  var mouse = { x: 0, y: 0, pan: false };
  var hover = null, drag = null, controlsBound = false, framePending = false;
  var simulationAlpha = 0;
  var simulationAlphaMin = 0.015;
  var simulationDecay = 0.94;
  var settings = {
    search: "",
    hideOrphans: false,
    textFadeThreshold: 0,
    arrows: false,
    nodeSize: 1,
    linkWidth: 1,
    repel: 700,
    linkDistance: 105,
    linkForce: 0.006,
    center: 0.0008
  };

  function resize() {
    dpr = window.devicePixelRatio || 1;
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = width + "px";
    canvas.style.height = height + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function worldX(x) { return (x - transform.x) / transform.k; }
  function worldY(y) { return (y - transform.y) / transform.k; }

  function zoomBy(amount, cx, cy) {
    cx = cx == null ? width / 2 : cx;
    cy = cy == null ? height / 2 : cy;
    var beforeX = worldX(cx), beforeY = worldY(cy);
    transform.k = Math.max(0.1, Math.min(8, transform.k * amount));
    transform.x = cx - beforeX * transform.k;
    transform.y = cy - beforeY * transform.k;
  }

  function resetView() {
    transform.x = 0; transform.y = 0; transform.k = 1;
  }

  function connected(a, b) {
    return a === b || (neighbors[a] && neighbors[a][b]);
  }

  function requestFrame() {
    if (framePending) return;
    framePending = true;
    requestAnimationFrame(frame);
  }

  function stopSimulation() {
    simulationAlpha = 0;
    nodes.forEach(function (n) { n.vx = 0; n.vy = 0; });
  }

  function reheatSimulation(alpha) {
    simulationAlpha = Math.max(simulationAlpha, alpha == null ? 1 : alpha);
    requestFrame();
  }

  function nodeAt(sx, sy) {
    var x = worldX(sx), y = worldY(sy);
    for (var i = nodes.length - 1; i >= 0; i--) {
      var n = nodes[i], dx = x - n.x, dy = y - n.y;
      if (dx * dx + dy * dy <= (n.r + 3) * (n.r + 3)) return n;
    }
    return null;
  }

  function filterLocal(graph, rootId, depth) {
    var allNodes = Object.create(null);
    var adj = Object.create(null);
    (graph.nodes || []).forEach(function (n) {
      allNodes[n.id] = n;
      adj[n.id] = [];
    });
    if (!allNodes[rootId]) return { nodes: [], links: [] };

    (graph.links || []).forEach(function (l) {
      if (adj[l.source] && adj[l.target]) {
        adj[l.source].push(l.target);
        adj[l.target].push(l.source);
      }
    });

    var seen = Object.create(null);
    var queue = [{ id: rootId, depth: 0 }];
    seen[rootId] = true;
    for (var i = 0; i < queue.length; i++) {
      var item = queue[i];
      if (item.depth >= depth) continue;
      adj[item.id].forEach(function (next) {
        if (!seen[next]) {
          seen[next] = true;
          queue.push({ id: next, depth: item.depth + 1 });
        }
      });
    }

    return {
      nodes: Object.keys(seen).map(function (id) { return allNodes[id]; }),
      links: (graph.links || []).filter(function (l) { return seen[l.source] && seen[l.target]; })
    };
  }

  function filteredGraph() {
    var graph = localRoot ? filterLocal(rawGraph, localRoot, Number(depthSlider.value)) : rawGraph;
    var degree = Object.create(null);
    (graph.nodes || []).forEach(function (n) { degree[n.id] = 0; });
    (graph.links || []).forEach(function (l) {
      if (degree[l.source] != null) degree[l.source]++;
      if (degree[l.target] != null) degree[l.target]++;
    });

    var search = settings.search.trim().toLowerCase();
    var keep = Object.create(null);
    var outNodes = (graph.nodes || []).filter(function (n) {
      var text = (n.title + " " + n.id + " " + (n.path || "") + " " + (n.folder || "") + " " + (n.aliases || []).join(" ") + " " + (n.tags || []).join(" ")).toLowerCase();
      var matches = search === "" || text.indexOf(search) !== -1;
      var hasLinks = degree[n.id] > 0 || n.id === localRoot;
      var ok = matches && (!settings.hideOrphans || hasLinks);
      if (ok) keep[n.id] = true;
      return ok;
    });

    return {
      nodes: outNodes,
      links: (graph.links || []).filter(function (l) { return keep[l.source] && keep[l.target]; })
    };
  }

  function step() {
    var alpha = drag ? Math.max(simulationAlpha, 0.08) : simulationAlpha;
    if (alpha <= 0 && !drag) return;

    for (var i = 0; i < links.length; i++) {
      var l = links[i], a = l.source, b = l.target;
      var dx = b.x - a.x, dy = b.y - a.y;
      var dist = Math.sqrt(dx * dx + dy * dy) || 1;
      var force = (dist - settings.linkDistance) * settings.linkForce * alpha;
      var fx = dx / dist * force, fy = dy / dist * force;
      if (!a.fixed) { a.vx += fx; a.vy += fy; }
      if (!b.fixed) { b.vx -= fx; b.vy -= fy; }
    }

    for (var p = 0; p < nodes.length; p++) {
      var n = nodes[p];
      for (var q = p + 1; q < nodes.length; q++) {
        var m = nodes[q];
        var rx = m.x - n.x, ry = m.y - n.y;
        var r2 = Math.max(rx * rx + ry * ry, 25);
        var repulse = Math.min(settings.repel / r2, 3.2) * alpha;
        var r = Math.sqrt(r2);
        var fxr = rx / r * repulse, fyr = ry / r * repulse;
        if (!n.fixed) { n.vx -= fxr; n.vy -= fyr; }
        if (!m.fixed) { m.vx += fxr; m.vy += fyr; }

        var minDist = n.r + m.r + 4;
        if (r < minDist) {
          var collide = (minDist - r) * 0.03 * alpha;
          var cfx = rx / r * collide, cfy = ry / r * collide;
          if (!n.fixed) { n.vx -= cfx; n.vy -= cfy; }
          if (!m.fixed) { m.vx += cfx; m.vy += cfy; }
        }
      }
    }

    for (var j = 0; j < nodes.length; j++) {
      var node = nodes[j];
      if (node.fixed) continue;
      node.vx += (width / 2 - node.x) * settings.center * alpha;
      node.vy += (height / 2 - node.y) * settings.center * alpha;
      node.vx *= 0.86; node.vy *= 0.86;
      node.x += node.vx; node.y += node.vy;
    }

    if (!drag) {
      simulationAlpha *= simulationDecay;
      if (simulationAlpha < simulationAlphaMin) stopSimulation();
    }
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function labelAlpha(node) {
    if (node === hover || node.id === localRoot) return 1;

    // Obsidian-like behavior: -3 shows almost all labels, 3 requires the
    // node to be large on screen (usually from zooming in or many links).
    var screenRadius = node.r * transform.k;
    var cutoff = 3 + ((settings.textFadeThreshold + 3) / 6) * 34;
    return clamp((screenRadius - cutoff + 8) / 8, 0, 1);
  }

  function updateNodeRadii() {
    nodes.forEach(function (n) { n.r = n.baseR * settings.nodeSize; });
  }

  function labelFontSize(node) {
    return clamp(4 + node.r * 0.7, 7, 22);
  }

  function drawArrow(from, to) {
    var dx = to.x - from.x, dy = to.y - from.y;
    var dist = Math.sqrt(dx * dx + dy * dy) || 1;
    var ux = dx / dist, uy = dy / dist;
    var size = 7 / transform.k;
    var x = to.x - ux * (to.r + 2 / transform.k);
    var y = to.y - uy * (to.r + 2 / transform.k);
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x - ux * size - uy * size * 0.55, y - uy * size + ux * size * 0.55);
    ctx.lineTo(x - ux * size + uy * size * 0.55, y - uy * size - ux * size * 0.55);
    ctx.closePath();
    ctx.fill();
  }

  function draw() {
    ctx.save();
    ctx.clearRect(0, 0, width, height);
    ctx.translate(transform.x, transform.y);
    ctx.scale(transform.k, transform.k);

    ctx.lineCap = "round";
    for (var i = 0; i < links.length; i++) {
      var l = links[i];
      var hi = hover && (l.source === hover || l.target === hover);
      var dim = hover && !hi;
      var color = hi ? "rgba(245,158,11,.85)" : dim ? "rgba(100,100,100,.08)" : "rgba(120,120,120,.28)";
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = (hi ? 2.2 : settings.linkWidth) / transform.k;
      ctx.beginPath();
      ctx.moveTo(l.source.x, l.source.y);
      ctx.lineTo(l.target.x, l.target.y);
      ctx.stroke();
      if (settings.arrows) drawArrow(l.source, l.target);
    }

    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (var j = 0; j < nodes.length; j++) {
      var n = nodes[j];
      var isHover = n === hover;
      var isRoot = localRoot && n.id === localRoot;
      var isActive = activeId && n.id === activeId;
      var dimNode = hover && !connected(hover.id, n.id);
      ctx.globalAlpha = dimNode ? 0.18 : 1;
      ctx.fillStyle = isRoot ? "#f59e0b" : isHover ? "#c084fc" : "#7c3aed";
      ctx.strokeStyle = isRoot ? "#fbbf24" : isActive ? "#38bdf8" : "#a78bfa";
      ctx.lineWidth = (isRoot || isActive) ? 2.2 / transform.k : 1.5 / transform.k;
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();

      var alpha = labelAlpha(n);
      if (alpha > 0.03) {
        ctx.globalAlpha = (dimNode ? 0.18 : 1) * alpha;
        var fontSize = labelFontSize(n);
        ctx.fillStyle = "#ddd";
        ctx.font = fontSize + "px sans-serif";
        ctx.fillText(n.title, n.x, n.y - n.r - fontSize * 0.75);
      }
      ctx.globalAlpha = 1;
    }
    ctx.restore();
  }

  function frame() {
    framePending = false;
    if (simulationAlpha > 0 || drag) step();
    draw();
    if (simulationAlpha > 0 || drag) requestFrame();
  }

  function renderGraph(graph) {
    var empty = document.getElementById("empty");
    if (empty) empty.remove();
    hover = null;
    tip.style.display = "none";
    var oldById = byId;
    byId = Object.create(null);
    neighbors = Object.create(null);

    nodes = (graph.nodes || []).map(function (n, i) {
      var old = oldById[n.id];
      var angle = Math.PI * 2 * i / Math.max((graph.nodes || []).length, 1);
      var radius = Math.min(width, height) * 0.25;
      var copy = {
        id: n.id,
        title: n.title,
        path: n.path,
        folder: n.folder || "",
        aliases: n.aliases || [],
        tags: n.tags || [],
        degree: 0,
        x: old ? old.x : width / 2 + Math.cos(angle) * radius,
        y: old ? old.y : height / 2 + Math.sin(angle) * radius,
        vx: old ? old.vx : 0,
        vy: old ? old.vy : 0,
        fixed: false,
        baseR: 5,
        r: 5
      };
      byId[copy.id] = copy;
      neighbors[copy.id] = Object.create(null);
      return copy;
    });

    links = (graph.links || []).map(function (l) {
      var source = byId[l.source], target = byId[l.target];
      if (source && target) {
        source.degree++; target.degree++;
        neighbors[source.id][target.id] = true;
        neighbors[target.id][source.id] = true;
        return { source: source, target: target };
      }
      return null;
    }).filter(Boolean);

    var maxDegree = nodes.reduce(function (max, n) { return Math.max(max, n.degree); }, 1);
    nodes.forEach(function (n) { n.baseR = 5 + (n.degree / maxDegree) * 10; });
    updateNodeRadii();

    if (nodes.length === 0) {
      var div = document.createElement("div");
      div.id = "empty";
      div.textContent = localRoot ? "No notes match the local graph settings" : "No notes match the graph settings";
      document.body.appendChild(div);
    }

    stats.textContent = nodes.length + " nodes · " + links.length + " links" + (localRoot ? " · local: " + localRoot : "");
    reheatSimulation(1);
  }

  function rerender() {
    renderGraph(filteredGraph());
  }

  function bindControls() {
    document.getElementById("search").addEventListener("input", function (e) {
      settings.search = e.target.value;
      rerender();
    });
    document.getElementById("hide-orphans").addEventListener("change", function (e) {
      settings.hideOrphans = e.target.checked;
      rerender();
    });
    document.getElementById("text-fade").addEventListener("input", function (e) {
      settings.textFadeThreshold = Number(e.target.value);
      document.getElementById("text-fade-value").textContent = e.target.value;
      requestFrame();
    });
    document.getElementById("show-arrows").addEventListener("change", function (e) {
      settings.arrows = e.target.checked;
      requestFrame();
    });
    document.getElementById("node-size").addEventListener("input", function (e) {
      settings.nodeSize = Number(e.target.value);
      updateNodeRadii();
      reheatSimulation(0.25);
    });
    document.getElementById("link-width").addEventListener("input", function (e) {
      settings.linkWidth = Number(e.target.value);
      requestFrame();
    });
    document.getElementById("repel").addEventListener("input", function (e) {
      settings.repel = Number(e.target.value);
      reheatSimulation(0.55);
    });
    document.getElementById("link-distance").addEventListener("input", function (e) {
      settings.linkDistance = Number(e.target.value);
      reheatSimulation(0.55);
    });
    document.getElementById("center-force").addEventListener("input", function (e) {
      settings.center = Number(e.target.value) / 10000;
      reheatSimulation(0.55);
    });
    depthSlider.addEventListener("input", function () {
      depthValue.textContent = depthSlider.value;
      resetView();
      rerender();
    });
  }

  function showLocalRoot() {
    if (!localMode) return;
    localBlock.style.display = "block";
    document.getElementById("root-note").textContent = localRoot || "";
    document.title = localRoot ? "Local Graph - " + localRoot : "Local Graph";
  }

  function loadGraph(graph) {
    rawGraph = graph || { nodes: [], links: [] };
    if (loading.parentNode) loading.remove();
    controls.style.display = "flex";
    settingsToggle.style.display = "block";
    showLocalRoot();
    if (!controlsBound) {
      bindControls();
      controlsBound = true;
    }
    rerender();
  }

  function openNode(node, event) {
    var open = "edit";
    if (event && event.shiftKey) open = "split";
    else if (event && (event.metaKey || event.ctrlKey)) open = "vsplit";
    else if (event && event.altKey) open = "tab";

    fetch("/api/open?token=" + encodeURIComponent(graphToken), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: node.id, open: open })
    }).catch(function () {});
  }

  function handleEvent(message) {
    if (!message || !message.type) return;
    if (message.type === "graph:update") {
      loadGraph(message.graph);
    } else if (message.type === "active:set") {
      activeId = message.id;
      requestFrame();
    } else if (message.type === "local:set_root" && localMode) {
      localRoot = message.id;
      activeId = message.id;
      showLocalRoot();
      resetView();
      if (rawGraph) rerender();
    }
  }

  function connectEvents() {
    if (!window.EventSource || graphToken === "") return;
    var source = new EventSource("/events?token=" + encodeURIComponent(graphToken));
    source.onmessage = function (event) {
      try { handleEvent(JSON.parse(event.data)); } catch (_) {}
    };
  }

  window.addEventListener("resize", function () { resize(); reheatSimulation(0.35); });
  settingsToggle.addEventListener("click", function () { side.classList.toggle("open"); });
  canvas.addEventListener("wheel", function (e) {
    e.preventDefault();
    zoomBy(e.deltaY < 0 ? 1.12 : 0.88, e.clientX, e.clientY);
    requestFrame();
  }, { passive: false });

  canvas.addEventListener("mousemove", function (e) {
    if (drag) {
      if (Math.hypot(e.clientX - mouse.downX, e.clientY - mouse.downY) >= 4) mouse.moved = true;
      drag.x = worldX(e.clientX); drag.y = worldY(e.clientY);
      drag.vx = 0; drag.vy = 0;
      requestFrame();
      return;
    }
    if (mouse.pan) {
      if (Math.hypot(e.clientX - mouse.downX, e.clientY - mouse.downY) >= 4) mouse.moved = true;
      transform.x += e.clientX - mouse.x;
      transform.y += e.clientY - mouse.y;
      mouse.x = e.clientX; mouse.y = e.clientY;
      requestFrame();
      return;
    }

    var nextHover = nodeAt(e.clientX, e.clientY);
    if (nextHover !== hover) {
      hover = nextHover;
      requestFrame();
    }
    if (hover) {
      tip.style.display = "block";
      tip.style.left = (e.clientX + 12) + "px";
      tip.style.top = (e.clientY + 12) + "px";
      tip.textContent = hover.title + "\n" + hover.id + (hover.tags.length ? "\n#" + hover.tags.join(" #") : "") + "\n" + hover.degree + " links";
    } else {
      tip.style.display = "none";
    }
  });

  canvas.addEventListener("mousedown", function (e) {
    mouse.x = e.clientX; mouse.y = e.clientY;
    mouse.downX = e.clientX; mouse.downY = e.clientY; mouse.moved = false;
    drag = nodeAt(e.clientX, e.clientY);
    mouse.downNode = drag;
    if (drag) {
      drag.fixed = true;
      requestFrame();
    } else {
      mouse.pan = true;
      canvas.classList.add("dragging");
    }
  });

  window.addEventListener("mouseup", function (e) {
    var clicked = mouse.downNode && !mouse.moved && Math.hypot(e.clientX - mouse.downX, e.clientY - mouse.downY) < 4;
    if (clicked) openNode(mouse.downNode, e);
    if (drag) {
      drag.fixed = false;
      reheatSimulation(0.25);
    }
    drag = null;
    mouse.downNode = null;
    mouse.pan = false;
    canvas.classList.remove("dragging");
  });

  document.getElementById("zin").onclick = function () { zoomBy(1.25); requestFrame(); };
  document.getElementById("zout").onclick = function () { zoomBy(0.8); requestFrame(); };
  document.getElementById("reset").onclick = function () { resetView(); requestFrame(); };

  resize();
  connectEvents();
  fetch("/api/graph?token=" + encodeURIComponent(graphToken))
    .then(function (res) { if (!res.ok) throw new Error(res.statusText); return res.json(); })
    .then(loadGraph)
    .catch(function (err) { loading.textContent = "Failed to load graph: " + err.message; loading.style.color = "#f66"; });
})();
</script>
</body>
</html>
]]

return M
