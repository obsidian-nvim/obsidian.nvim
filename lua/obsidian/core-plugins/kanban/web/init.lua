-- HTML page for the Kanban view. No external assets or dependencies.

local M = [==[
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Obsidian Kanban</title>
<style>
  :root { color-scheme: dark; --bg:#191919; --panel:#202020; --panel2:#282828; --card:#303030; --line:#3d3d3d; --text:#ddd; --muted:#999; --accent:#7c3aed; }
  html, body { margin:0; width:100%; height:100%; overflow:hidden; }
  body { background:var(--bg); color:var(--text); font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
  header { height:48px; display:flex; align-items:center; gap:10px; padding:0 14px; box-sizing:border-box; border-bottom:1px solid var(--line); background:#161616; }
  h1 { margin:0; font-size:16px; font-weight:650; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  button { border:0; border-radius:6px; background:#3a3a3a; color:var(--text); padding:7px 10px; cursor:pointer; }
  button:hover { background:#4a4a4a; }
  main { height:calc(100vh - 48px); overflow:auto; }
  #board { display:flex; align-items:flex-start; gap:14px; min-height:100%; padding:14px; box-sizing:border-box; }
  .column { flex:0 0 310px; max-height:calc(100vh - 78px); display:flex; flex-direction:column; border:1px solid var(--line); border-radius:10px; background:var(--panel); }
  .column header { height:auto; min-height:42px; padding:10px; border:0; border-bottom:1px solid var(--line); background:transparent; }
  .column-title { flex:1; font-weight:650; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .count { color:var(--muted); font-size:12px; }
  .cards { flex:1; min-height:70px; overflow:auto; padding:10px; }
  .card { display:block; margin-bottom:9px; padding:10px; border:1px solid #454545; border-radius:8px; background:var(--card); box-shadow:0 1px 2px rgba(0,0,0,.18); cursor:grab; transition:transform .12s ease, opacity .12s ease; }
  .card.dragging { opacity:.45; border-color:var(--accent); }
  .card.done .card-line:first-child .line-text { color:#999; text-decoration:line-through; }
  .card input { flex:0 0 auto; margin-top:2px; accent-color:var(--accent); }
  .card-line { display:flex; align-items:flex-start; gap:8px; min-height:21px; line-height:1.35; }
  .line-marker { flex:0 0 16px; color:var(--muted); text-align:center; }
  .line-text { white-space:pre-wrap; overflow-wrap:anywhere; min-width:0; }
  .line-text a { color:#a78bfa; text-decoration:none; cursor:pointer; }
  .line-text a:hover { text-decoration:underline; }
  .add-card { margin:0 10px 10px; color:var(--muted); background:transparent; text-align:left; }
  .add-card:hover { color:var(--text); background:#333; }
  #empty, #loading, #error { padding:32px; color:var(--muted); }
  #error { color:#ff8a8a; }
  .warn { color:#d8b4fe; font-size:12px; }
  .spacer { flex:1; }
</style>
</head>
<body>
<header>
  <h1 id="title">Kanban</h1>
  <div class="spacer"></div>
  <span id="compat" class="warn"></span>
  <button id="refresh">Refresh</button>
  <button id="add-column">+ Column</button>
</header>
<main>
  <div id="loading">Loading board...</div>
  <div id="error" style="display:none"></div>
  <div id="empty" style="display:none">No Kanban columns found. Add a column to start a board.</div>
  <div id="board" style="display:none"></div>
</main>
<script>
(function () {
  var token = "__OBSIDIAN_KANBAN_TOKEN__";
  var board = null;
  var draggingCardId = null;
  var els = {
    title: document.getElementById("title"),
    compat: document.getElementById("compat"),
    refresh: document.getElementById("refresh"),
    addColumn: document.getElementById("add-column"),
    loading: document.getElementById("loading"),
    error: document.getElementById("error"),
    empty: document.getElementById("empty"),
    board: document.getElementById("board")
  };

  function request(path, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ "Content-Type": "application/json" }, opts.headers || {});
    return fetch(path + "?token=" + encodeURIComponent(token), opts).then(function (res) {
      return res.text().then(function (text) {
        var data = text ? JSON.parse(text) : {};
        if (!res.ok || data.ok === false) throw new Error(data.error || res.statusText);
        return data;
      });
    });
  }

  function showError(err) {
    els.loading.style.display = "none";
    els.board.style.display = "none";
    els.empty.style.display = "none";
    els.error.style.display = "block";
    els.error.textContent = err && err.message ? err.message : String(err);
  }

  function setBoard(next) {
    board = next;
    render();
  }

  function load() {
    els.loading.style.display = "block";
    els.error.style.display = "none";
    return request("/api/board").then(function (data) { setBoard(data.board); }).catch(showError);
  }

  function mutate(path, payload) {
    return request(path, { method: "POST", body: JSON.stringify(payload || {}) })
      .then(function (data) { setBoard(data.board); })
      .catch(showError);
  }

  function openTarget(target) {
    return request("/api/open-link", { method: "POST", body: JSON.stringify({ target: target }) }).catch(showError);
  }

  function appendTextWithLinks(parent, text) {
    var re = /(!?\[([^\]]+)\]\(([^)]+)\))|(\[\[([^\]]+)\]\])/g;
    var pos = 0;
    var match;
    while ((match = re.exec(text)) !== null) {
      if (match.index > pos) parent.appendChild(document.createTextNode(text.slice(pos, match.index)));
      if (match[1] && match[1].charAt(0) === "!") {
        parent.appendChild(document.createTextNode(match[1]));
      } else {
        var target = match[3] || (match[5] || "").split("|")[0];
        var label = match[2] || (match[5] || "").split("|").pop();
        var a = document.createElement("a");
        a.href = "#";
        a.textContent = label || target;
        a.onclick = function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          openTarget(this.dataset.target);
        };
        a.dataset.target = target;
        parent.appendChild(a);
      }
      pos = match.index + match[0].length;
    }
    if (pos < text.length) parent.appendChild(document.createTextNode(text.slice(pos)));
  }

  function parseCardLine(line) {
    var match = line.match(/^(\s*)[-*+]\s+\[([ xX-])\]\s*(.*)$/);
    if (match) return { indent: match[1].length, checkbox: true, checked: match[2].toLowerCase() === "x", text: match[3] };
    match = line.match(/^(\s*)[-*+]\s+(.*)$/);
    if (match) return { indent: match[1].length, bullet: true, text: match[2] };
    match = line.match(/^(\s*)(.*)$/);
    return { indent: match[1].length, text: match[2] };
  }

  function renderCardLines(item, card) {
    var lines = card.lines && card.lines.length ? card.lines : ["- [" + (card.checked ? "x" : " ") + "] " + (card.text || "")];
    lines.forEach(function (raw, idx) {
      var parsed = parseCardLine(raw);
      var line = document.createElement("div");
      line.className = "card-line";
      line.style.marginLeft = (Math.floor(parsed.indent / 2) * 18) + "px";

      if (parsed.checkbox) {
        var check = document.createElement("input");
        check.type = "checkbox";
        check.checked = parsed.checked;
        check.onclick = function (ev) { ev.stopPropagation(); };
        if (idx === 0) {
          check.onchange = function () { mutate("/api/toggle", { card_id: card.id, checked: check.checked }); };
        } else {
          check.disabled = true;
        }
        line.appendChild(check);
      } else {
        var marker = document.createElement("span");
        marker.className = "line-marker";
        marker.textContent = parsed.bullet ? "•" : "";
        line.appendChild(marker);
      }

      var text = document.createElement("span");
      text.className = "line-text";
      appendTextWithLinks(text, parsed.text || "");
      line.appendChild(text);
      item.appendChild(line);
    });
  }

  function dragAfterElement(cardsEl, y) {
    var cards = Array.prototype.slice.call(cardsEl.querySelectorAll(".card:not(.dragging)"));
    var closest = { offset: Number.NEGATIVE_INFINITY, element: null };
    cards.forEach(function (card) {
      var rect = card.getBoundingClientRect();
      var offset = y - rect.top - rect.height / 2;
      if (offset < 0 && offset > closest.offset) closest = { offset: offset, element: card };
    });
    return closest.element;
  }

  function moveDraggedCard(cardsEl, y) {
    var dragging = document.querySelector(".card.dragging");
    if (!dragging) return;
    var after = dragAfterElement(cardsEl, y);
    if (after) cardsEl.insertBefore(dragging, after);
    else cardsEl.appendChild(dragging);
  }

  function dropIndex(cardsEl) {
    var cards = Array.prototype.slice.call(cardsEl.querySelectorAll(".card"));
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].dataset.cardId === draggingCardId) return i + 1;
    }
    return cards.length + 1;
  }

  function render() {
    els.loading.style.display = "none";
    els.error.style.display = "none";
    els.title.textContent = board.title || "Kanban";
    els.compat.textContent = board.is_kanban ? "" : "Not marked kanban-plugin: board";
    els.board.innerHTML = "";

    if (!board.columns || board.columns.length === 0) {
      els.board.style.display = "none";
      els.empty.style.display = "block";
      return;
    }

    els.empty.style.display = "none";
    els.board.style.display = "flex";

    board.columns.forEach(function (column) {
      var col = document.createElement("section");
      col.className = "column";
      col.dataset.columnId = column.id;

      var head = document.createElement("header");
      var title = document.createElement("div");
      title.className = "column-title";
      title.textContent = column.title;
      title.title = "Double-click to rename";
      title.ondblclick = function () {
        var next = prompt("Column title", column.title);
        if (next != null) mutate("/api/rename-column", { column_id: column.id, title: next });
      };
      var count = document.createElement("div");
      count.className = "count";
      count.textContent = (column.cards || []).length;
      head.appendChild(title);
      head.appendChild(count);
      col.appendChild(head);

      var cards = document.createElement("div");
      cards.className = "cards";
      cards.ondragover = function (ev) {
        ev.preventDefault();
        moveDraggedCard(cards, ev.clientY);
      };
      cards.ondrop = function (ev) {
        ev.preventDefault();
        if (!draggingCardId) return;
        mutate("/api/move", { card_id: draggingCardId, to_column_id: column.id, to_index: dropIndex(cards) });
      };

      (column.cards || []).forEach(function (card) {
        var item = document.createElement("article");
        item.className = "card" + (card.checked ? " done" : "");
        item.draggable = true;
        item.dataset.cardId = card.id;
        item.ondragstart = function () {
          draggingCardId = card.id;
          item.classList.add("dragging");
        };
        item.ondragend = function () {
          draggingCardId = null;
          item.classList.remove("dragging");
        };

        renderCardLines(item, card);
        cards.appendChild(item);
      });
      col.appendChild(cards);

      var add = document.createElement("button");
      add.className = "add-card";
      add.textContent = "+ Add card";
      add.onclick = function () {
        var text = prompt("Card text");
        if (text != null) mutate("/api/add-card", { column_id: column.id, text: text });
      };
      col.appendChild(add);
      els.board.appendChild(col);
    });
  }

  els.refresh.onclick = load;
  els.addColumn.onclick = function () {
    var title = prompt("Column title");
    if (title != null) mutate("/api/add-column", { title: title });
  };
  load();
})();
</script>
</body>
</html>
]==]

return M
