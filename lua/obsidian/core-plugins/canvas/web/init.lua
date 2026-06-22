return [=[<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Obsidian Canvas</title>
<style>
  :root { color-scheme: dark; --bg:#111318; --panel:#1d2028; --text:#e7eaf0; --muted:#9aa4b2; --border:#343946; --accent:#7aa2ff; }
  html, body { margin:0; width:100%; height:100%; overflow:hidden; background:var(--bg); color:var(--text); font:14px/1.4 system-ui, -apple-system, Segoe UI, sans-serif; }
  #toolbar { position:fixed; z-index:10; left:12px; top:12px; display:flex; gap:8px; align-items:center; max-width:calc(100vw - 24px); padding:8px; border:1px solid var(--border); border-radius:10px; background:rgba(29,32,40,.92); box-shadow:0 10px 30px rgba(0,0,0,.25); backdrop-filter:blur(8px); }
  #title { max-width:42vw; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; color:var(--muted); }
  button { border:1px solid var(--border); border-radius:8px; padding:5px 10px; color:var(--text); background:#252a35; cursor:pointer; }
  button:hover { border-color:var(--accent); }
  button.primary { background:#2d4675; border-color:#456da8; }
  button.active { border-color:#8b5cf6; box-shadow:0 0 0 1px #8b5cf6 inset; }
  #status { color:var(--muted); }
  #viewport { position:fixed; inset:0; cursor:grab; background-image:radial-gradient(circle, rgba(255,255,255,.08) 1px, transparent 1px); background-size:24px 24px; }
  #viewport.dragging { cursor:grabbing; }
  #scene { position:absolute; left:0; top:0; transform-origin:0 0; width:1px; height:1px; }
  #edges { position:absolute; left:0; top:0; overflow:visible; pointer-events:none; }
  path.edge { pointer-events:stroke; cursor:pointer; }
  path.edge:hover, path.edge.selected { stroke:#8b5cf6; stroke-width:4; }
  .node { position:absolute; box-sizing:border-box; border:1px solid var(--border); border-radius:12px; background:var(--panel); box-shadow:0 8px 22px rgba(0,0,0,.25); overflow:hidden; user-select:none; }
  .node::after { content:""; position:absolute; inset:0; border:2px solid #8b5cf6; border-radius:12px; opacity:0; pointer-events:none; transition:opacity .12s ease; z-index:4; }
  .node:hover { cursor:grab; }
  .node:hover::after, .node.selected::after { opacity:1; }
  .node.group { background:rgba(255,255,255,.04); border-style:dashed; box-shadow:none; z-index:0; }
  .node:not(.group) { z-index:2; }
  .node-body { padding:10px; white-space:pre-wrap; overflow:auto; height:100%; box-sizing:border-box; }
  .node.file .node-body { padding:0; }
  .node.group .node-body { color:var(--muted); font-size:13px; font-weight:600; }
  .resize-handle { position:absolute; right:0; bottom:0; width:16px; height:16px; cursor:nwse-resize; background:linear-gradient(135deg, transparent 50%, rgba(255,255,255,.28) 50%); z-index:3; }
  .file-path, .link-url { color:var(--accent); overflow-wrap:anywhere; }
  .attachment-preview { width:100%; height:100%; min-height:40px; border-radius:8px; overflow:hidden; background:rgba(0,0,0,.18); display:flex; align-items:center; justify-content:center; }
  .attachment-preview img, .attachment-preview video { width:100%; height:100%; object-fit:contain; }
  .attachment-preview iframe, .attachment-preview object { width:100%; height:100%; border:0; background:#fff; pointer-events:none; }
  .attachment-preview audio { width:92%; }
  .web-preview { width:100%; height:100%; border:0; background:#fff; pointer-events:none; }
  .note-preview { display:block; width:100%; height:100%; margin:0; padding:10px; box-sizing:border-box; overflow:auto; white-space:pre-wrap; color:var(--text); font:13px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  a { color:var(--accent); }
  #error { position:fixed; right:12px; bottom:12px; max-width:min(620px, calc(100vw - 24px)); white-space:pre-wrap; color:#ffd6d6; background:#4a1f26; border:1px solid #8f3b48; border-radius:10px; padding:12px; display:none; z-index:20; }
</style>
</head>
<body>
  <div id="toolbar">
    <button id="reload">Reload</button>
    <button id="fit">Fit</button>
    <button id="add-text">Text</button>
    <button id="add-file">File</button>
    <button id="add-link">Link</button>
    <button id="add-group">Group</button>
    <button id="connect">Arrow</button>
    <button id="save" class="primary">Save</button>
    <span id="title"></span>
    <span id="status"></span>
  </div>
  <div id="viewport"><div id="scene"><svg id="edges"><defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="currentColor"></path></marker></defs></svg></div></div>
  <div id="error"></div>
<script>
(function () {
  var token = "__OBSIDIAN_CANVAS_TOKEN__";
  var params = new URLSearchParams(location.search);
  var canvasPath = params.get("path") || "";
  var viewport = document.getElementById("viewport");
  var scene = document.getElementById("scene");
  var edges = document.getElementById("edges");
  var title = document.getElementById("title");
  var status = document.getElementById("status");
  var errorBox = document.getElementById("error");
  var data = { nodes: [], edges: [] };
  var scale = 1, tx = 0, ty = 0, dirty = false, selectedId = null, selectedEdgeId = null, connectFromId = null;
  var nodeEls = Object.create(null);
  var colorMap = { "1":"#e06c75", "2":"#d19a66", "3":"#e5c07b", "4":"#98c379", "5":"#56b6c2", "6":"#c678dd" };

  function api(path) { return path + "?token=" + encodeURIComponent(token) + "&path=" + encodeURIComponent(canvasPath); }
  function setStatus(msg) { status.textContent = msg || ""; }
  function showError(err) { errorBox.style.display = err ? "block" : "none"; errorBox.textContent = err || ""; }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>'"]/g, function (c) { return {"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]; }); }
  function color(c, fallback) { if (!c) return fallback; if (colorMap[c]) return colorMap[c]; if (/^#[0-9a-f]{3,8}$/i.test(c)) return c; return fallback; }
  function nodes() { if (!Array.isArray(data.nodes)) data.nodes = []; return data.nodes; }
  function edgeList() { if (!Array.isArray(data.edges)) data.edges = []; return data.edges; }
  function nodeById(id) { return nodes().find(function (n) { return n.id === id; }); }
  function makeId(prefix) { return prefix + "-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 7); }
  function worldCenter() { return screenToWorld(window.innerWidth / 2, window.innerHeight / 2); }
  function setConnectMode(on) { connectFromId = on ? connectFromId : null; document.getElementById("connect").classList.toggle("active", !!on); if (on) setStatus("connect: pick source"); }
  function connectMode() { return document.getElementById("connect").classList.contains("active"); }
  function fileUrl(n) { return api("/api/file") + "&file=" + encodeURIComponent(n.file || ""); }
  function fileExt(file) { return String(file || "").split(/[?#]/)[0].split(".").pop().toLowerCase(); }
  function attachmentKind(file) {
    var ext = fileExt(file);
    if (["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "ico"].indexOf(ext) >= 0) return "image";
    if (ext === "pdf") return "pdf";
    if (["md", "markdown"].indexOf(ext) >= 0) return "note";
    if (["mp3", "wav", "ogg", "flac", "m4a"].indexOf(ext) >= 0) return "audio";
    if (["mp4", "webm", "mov"].indexOf(ext) >= 0) return "video";
    return "";
  }
  function attachmentHtml(n) {
    var src = esc(fileUrl(n)), kind = attachmentKind(n.file);
    if (kind === "image") return '<div class="attachment-preview"><img src="' + src + '" alt=""></div>';
    if (kind === "pdf") return '<div class="attachment-preview"><iframe src="' + src + '#toolbar=0"></iframe></div>';
    if (kind === "note") return '<div class="attachment-preview"><pre class="note-preview" data-src="' + src + '">Loading…</pre></div>';
    if (kind === "audio") return '<div class="attachment-preview"><audio controls src="' + src + '"></audio></div>';
    if (kind === "video") return '<div class="attachment-preview"><video controls src="' + src + '"></video></div>';
    return "";
  }
  function webPreviewHtml(url) {
    if (!/^https?:\/\//i.test(url || "")) return "";
    return '<iframe class="web-preview" src="' + esc(url) + '" loading="lazy" referrerpolicy="no-referrer"></iframe>';
  }
  function num(v, d) { return typeof v === "number" && isFinite(v) ? v : d; }
  function defaultWidth(n) { return n.type === "text" ? 260 : 250; }
  function defaultHeight(n) { return n.type === "text" ? 44 : 120; }
  function minWidth(n) { return n.type === "text" ? 120 : 20; }
  function minHeight(n) { return n.type === "text" ? 38 : 20; }
  function rect(n) { return { x:num(n.x,0), y:num(n.y,0), w:Math.max(minWidth(n),num(n.width,defaultWidth(n))), h:Math.max(minHeight(n),num(n.height,defaultHeight(n))) }; }
  function markDirty() { dirty = true; setStatus("modified"); }
  function applyTransform() { scene.style.transform = "translate(" + tx + "px," + ty + "px) scale(" + scale + ")"; }
  function screenToWorld(x, y) { return { x:(x - tx) / scale, y:(y - ty) / scale }; }

  function anchor(n, side, other) {
    var r = rect(n), cx = r.x + r.w / 2, cy = r.y + r.h / 2;
    if (!side && other) {
      var or = rect(other), ox = or.x + or.w / 2, oy = or.y + or.h / 2;
      side = Math.abs(ox - cx) > Math.abs(oy - cy) ? (ox > cx ? "right" : "left") : (oy > cy ? "bottom" : "top");
    }
    if (side === "top") return { x:cx, y:r.y, side:side };
    if (side === "bottom") return { x:cx, y:r.y + r.h, side:side };
    if (side === "left") return { x:r.x, y:cy, side:side };
    return { x:r.x + r.w, y:cy, side:"right" };
  }

  function control(a, b) {
    var dx = Math.max(80, Math.abs(b.x - a.x) * 0.45), dy = Math.max(80, Math.abs(b.y - a.y) * 0.45);
    if (a.side === "left") return { x:a.x - dx, y:a.y };
    if (a.side === "right") return { x:a.x + dx, y:a.y };
    if (a.side === "top") return { x:a.x, y:a.y - dy };
    return { x:a.x, y:a.y + dy };
  }

  function loadNotePreview(el) {
    Array.from(el.querySelectorAll(".note-preview")).forEach(function (pre) {
      fetch(pre.getAttribute("data-src")).then(function (r) {
        if (!r.ok) return r.text().then(function (t) { throw new Error(t); });
        return r.text();
      }).then(function (text) {
        pre.textContent = text;
      }).catch(function (err) {
        pre.textContent = String(err && err.message || err);
      });
    });
  }

  function drawEdges() {
    Array.from(edges.querySelectorAll("path.edge,text.edge-label")).forEach(function (el) { el.remove(); });
    edgeList().forEach(function (e) {
      var from = nodeById(e.fromNode), to = nodeById(e.toNode);
      if (!from || !to) return;
      var a = anchor(from, e.fromSide, to), b = anchor(to, e.toSide, from), c1 = control(a, b), c2 = control(b, a);
      var p = document.createElementNS("http://www.w3.org/2000/svg", "path");
      p.setAttribute("class", "edge" + (e.id === selectedEdgeId ? " selected" : ""));
      p.setAttribute("d", "M " + a.x + " " + a.y + " C " + c1.x + " " + c1.y + ", " + c2.x + " " + c2.y + ", " + b.x + " " + b.y);
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", color(e.color, "#8792a2"));
      p.setAttribute("stroke-width", "2");
      if (e.toEnd !== "none") p.setAttribute("marker-end", "url(#arrow)");
      if (e.fromEnd === "arrow") p.setAttribute("marker-start", "url(#arrow)");
      p.addEventListener("mousedown", function (ev) { ev.stopPropagation(); selectedEdgeId = e.id; selectedId = null; render(); });
      edges.appendChild(p);
      if (e.label) {
        var t = document.createElementNS("http://www.w3.org/2000/svg", "text");
        t.setAttribute("class", "edge-label");
        t.setAttribute("x", (a.x + b.x) / 2); t.setAttribute("y", (a.y + b.y) / 2 - 8);
        t.setAttribute("fill", "#c7ccd6"); t.setAttribute("font-size", "13"); t.setAttribute("text-anchor", "middle");
        t.textContent = e.label;
        edges.appendChild(t);
      }
    });
  }

  function renderNode(n) {
    var r = rect(n), el = document.createElement("div");
    el.className = "node " + esc(n.type || "unknown") + (n.id === selectedId ? " selected" : "");
    el.style.left = r.x + "px"; el.style.top = r.y + "px"; el.style.width = r.w + "px"; el.style.height = r.h + "px";
    el.style.borderColor = color(n.color, "");
    if (n.type === "group") {
      el.innerHTML = '<div class="node-body">' + esc(n.label || "Group") + '</div>';
      el.style.background = n.background ? color(n.background, n.background) : "";
    } else if (n.type === "file") {
      var preview = attachmentHtml(n);
      el.innerHTML = '<div class="node-body">' + (preview || '<div class="file-path">' + esc(n.file || "") + esc(n.subpath || "") + '</div>') + '</div>';
      loadNotePreview(el);
    } else if (n.type === "link") {
      var url = esc(n.url || ""), previewHtml = webPreviewHtml(n.url || "");
      el.innerHTML = '<div class="node-body">' + (previewHtml || '<a class="link-url" target="_blank" rel="noreferrer" href="' + url + '">' + url + '</a>') + '</div>';
    } else {
      el.innerHTML = '<div class="node-body">' + esc(n.text || "") + '</div>';
      if (n.type === "text") {
        el.addEventListener("dblclick", function () { var next = prompt("Text", n.text || ""); if (next != null) { n.text = next; markDirty(); render(); } });
      }
    }
    var handle = document.createElement("div");
    handle.className = "resize-handle";
    handle.addEventListener("mousedown", function (ev) { startNodeResize(ev, n, el); });
    el.appendChild(handle);
    el.addEventListener("mousedown", function (ev) {
      if (ev.target.classList.contains("resize-handle")) return;
      if (connectMode()) { ev.stopPropagation(); ev.preventDefault(); handleConnectNode(n); return; }
      startNodeDrag(ev, n, el);
    }, true);
    nodeEls[n.id] = el;
    scene.appendChild(el);
  }

  function render() {
    Object.keys(nodeEls).forEach(function (id) { nodeEls[id].remove(); });
    nodeEls = Object.create(null);
    nodes().filter(function (n) { return n.type === "group"; }).forEach(renderNode);
    nodes().filter(function (n) { return n.type !== "group"; }).forEach(renderNode);
    drawEdges();
  }

  function sideBetween(a, b, from) {
    var ar = rect(a), br = rect(b), ax = ar.x + ar.w / 2, ay = ar.y + ar.h / 2, bx = br.x + br.w / 2, by = br.y + br.h / 2;
    if (Math.abs(bx - ax) > Math.abs(by - ay)) return from ? (bx > ax ? "right" : "left") : (bx > ax ? "left" : "right");
    return from ? (by > ay ? "bottom" : "top") : (by > ay ? "top" : "bottom");
  }

  function addEdge(from, to) {
    if (!from || !to || from.id === to.id) return;
    edgeList().push({ id:makeId("edge"), fromNode:from.id, toNode:to.id, fromSide:sideBetween(from, to, true), toSide:sideBetween(from, to, false), toEnd:"arrow" });
    selectedEdgeId = edgeList()[edgeList().length - 1].id; selectedId = null; markDirty(); render();
  }

  function handleConnectNode(n) {
    if (!connectFromId) { connectFromId = n.id; selectedId = n.id; selectedEdgeId = null; setStatus("connect: pick target"); render(); return; }
    addEdge(nodeById(connectFromId), n); connectFromId = null; setConnectMode(false);
  }

  function addNode(type) {
    var c = worldCenter(), n = { id:makeId(type), type:type, x:Math.round(c.x - 130), y:Math.round(c.y - 40), width:type === "group" ? 360 : 260, height:type === "text" ? 44 : 160 };
    if (type === "text") n.text = prompt("Text", "") || "";
    if (type === "file") { n.file = prompt("File path", "") || ""; if (!n.file) return; }
    if (type === "link") { n.url = prompt("URL", "https://") || ""; if (!n.url) return; }
    if (type === "group") n.label = prompt("Group label", "Group") || "Group";
    nodes().push(n); selectedId = n.id; selectedEdgeId = null; markDirty(); render();
  }

  function startNodeDrag(ev, n, el) {
    ev.stopPropagation(); selectedId = n.id; selectedEdgeId = null; render(); el = nodeEls[n.id];
    var startX = ev.clientX, startY = ev.clientY, ox = num(n.x, 0), oy = num(n.y, 0);
    function move(e) { n.x = Math.round(ox + (e.clientX - startX) / scale); n.y = Math.round(oy + (e.clientY - startY) / scale); el.style.left = n.x + "px"; el.style.top = n.y + "px"; drawEdges(); markDirty(); }
    function up() { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); }
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
  }

  function startNodeResize(ev, n, el) {
    ev.stopPropagation(); ev.preventDefault();
    selectedId = n.id; selectedEdgeId = null;
    var r = rect(n), startX = ev.clientX, startY = ev.clientY;
    function move(e) {
      n.width = Math.round(Math.max(minWidth(n), r.w + (e.clientX - startX) / scale));
      n.height = Math.round(Math.max(minHeight(n), r.h + (e.clientY - startY) / scale));
      el.style.width = n.width + "px"; el.style.height = n.height + "px";
      drawEdges(); markDirty();
    }
    function up() { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); }
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
  }

  function deleteSelection() {
    if (selectedEdgeId) { data.edges = edgeList().filter(function (e) { return e.id !== selectedEdgeId; }); selectedEdgeId = null; markDirty(); render(); return; }
    if (selectedId) {
      data.nodes = nodes().filter(function (n) { return n.id !== selectedId; });
      data.edges = edgeList().filter(function (e) { return e.fromNode !== selectedId && e.toNode !== selectedId; });
      selectedId = null; markDirty(); render();
    }
  }

  function load() {
    showError(""); setStatus("loading"); title.textContent = canvasPath;
    fetch(api("/api/canvas")).then(function (r) { if (!r.ok) return r.text().then(function (t) { throw new Error(t); }); return r.json(); }).then(function (json) {
      data = json || { nodes: [], edges: [] }; dirty = false; setStatus(nodes().length + " nodes, " + edgeList().length + " edges"); render(); if (!params.has("view")) fit();
    }).catch(function (err) { showError(String(err && err.message || err)); setStatus("error"); });
  }

  function save() {
    showError(""); setStatus("saving");
    fetch(api("/api/canvas"), { method:"POST", body:JSON.stringify(data), headers:{ "Content-Type":"application/json" } }).then(function (r) { if (!r.ok) return r.text().then(function (t) { throw new Error(t); }); return r.json(); }).then(function () { dirty = false; setStatus("saved"); }).catch(function (err) { showError(String(err && err.message || err)); setStatus("error"); });
  }

  function fit() {
    if (!nodes().length) { tx = innerWidth / 2; ty = innerHeight / 2; scale = 1; applyTransform(); return; }
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes().forEach(function (n) { var r = rect(n); minX = Math.min(minX, r.x); minY = Math.min(minY, r.y); maxX = Math.max(maxX, r.x + r.w); maxY = Math.max(maxY, r.y + r.h); });
    var pad = 80, sx = innerWidth / Math.max(1, maxX - minX + pad * 2), sy = innerHeight / Math.max(1, maxY - minY + pad * 2);
    scale = Math.max(.15, Math.min(1.4, Math.min(sx, sy))); tx = (innerWidth - (minX + maxX) * scale) / 2; ty = (innerHeight - (minY + maxY) * scale) / 2; applyTransform();
  }

  viewport.addEventListener("wheel", function (ev) {
    ev.preventDefault(); var before = screenToWorld(ev.clientX, ev.clientY); scale = Math.max(.1, Math.min(3, scale * Math.exp(-ev.deltaY * 0.001))); tx = ev.clientX - before.x * scale; ty = ev.clientY - before.y * scale; applyTransform();
  }, { passive:false });
  viewport.addEventListener("mousedown", function (ev) {
    if (ev.button !== 0) return; if (ev.target === viewport || ev.target === scene) { selectedId = null; selectedEdgeId = null; render(); }
    viewport.classList.add("dragging"); var sx = ev.clientX, sy = ev.clientY, otx = tx, oty = ty;
    function move(e) { tx = otx + e.clientX - sx; ty = oty + e.clientY - sy; applyTransform(); }
    function up() { viewport.classList.remove("dragging"); window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); }
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
  });
  document.getElementById("reload").addEventListener("click", load);
  document.getElementById("fit").addEventListener("click", fit);
  document.getElementById("add-text").addEventListener("click", function () { addNode("text"); });
  document.getElementById("add-file").addEventListener("click", function () { addNode("file"); });
  document.getElementById("add-link").addEventListener("click", function () { addNode("link"); });
  document.getElementById("add-group").addEventListener("click", function () { addNode("group"); });
  document.getElementById("connect").addEventListener("click", function () { setConnectMode(!connectMode()); });
  document.getElementById("save").addEventListener("click", save);
  window.addEventListener("keydown", function (ev) { if (ev.key === "Delete" || ev.key === "Backspace") deleteSelection(); if (ev.key === "Escape") setConnectMode(false); });
  window.addEventListener("beforeunload", function (e) { if (dirty) { e.preventDefault(); e.returnValue = ""; } });
  applyTransform(); load();
}());
</script>
</body>
</html>]=]
