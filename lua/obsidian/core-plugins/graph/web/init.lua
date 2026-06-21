-- HTML page for the graph view. Fetches data from /api/graph at load time.

local M = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Obsidian Graph View</title>
<script src="https://d3js.org/d3.v7.min.js"></script>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #1e1e1e; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  svg { width: 100vw; height: 100vh; display: block; }

  .node circle {
    fill: #7c3aed;
    stroke: #a78bfa;
    stroke-width: 1.5;
    cursor: pointer;
    transition: fill 0.2s;
  }
  .node circle:hover {
    fill: #a78bfa;
  }
  .node text {
    fill: #d4d4d4;
    font-size: 10px;
    pointer-events: none;
    text-anchor: middle;
    dominant-baseline: central;
    text-shadow: 0 1px 3px rgba(0,0,0,0.8);
  }
  .link {
    stroke: #4a4a4a;
    stroke-opacity: 0.4;
    stroke-width: 1;
  }

  .node.highlight circle { fill: #f59e0b; stroke: #fbbf24; }
  .node.dim circle { opacity: 0.15; }
  .node.dim text { opacity: 0.1; }
  .link.highlight { stroke: #f59e0b; stroke-opacity: 0.8; stroke-width: 2; }
  .link.dim { stroke-opacity: 0.05; }

  #tooltip {
    position: absolute;
    background: #2d2d2d;
    color: #e0e0e0;
    padding: 6px 10px;
    border-radius: 4px;
    font-size: 13px;
    pointer-events: none;
    border: 1px solid #555;
    display: none;
    z-index: 100;
    white-space: nowrap;
    max-width: 400px;
    word-break: break-all;
  }

  #controls {
    position: absolute;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    gap: 8px;
    background: #2d2d2d;
    padding: 8px 16px;
    border-radius: 8px;
    border: 1px solid #444;
  }
  #controls button {
    background: #4a4a4a;
    color: #e0e0e0;
    border: none;
    padding: 6px 14px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
  }
  #controls button:hover { background: #5a5a5a; }

  #stats {
    position: absolute;
    top: 12px;
    left: 12px;
    color: #888;
    font-size: 12px;
    font-family: monospace;
    background: rgba(30,30,30,0.7);
    padding: 4px 8px;
    border-radius: 4px;
  }

  #loading {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    color: #888;
    font-size: 18px;
  }
</style>
</head>
<body>

<div id="loading">Loading graph data...</div>
<div id="tooltip"></div>
<div id="stats"></div>

<svg id="graph" style="display:none"></svg>

<div id="controls" style="display:none">
  <button id="btn-zoom-in">+</button>
  <button id="btn-zoom-out">-</button>
  <button id="btn-reset">&#x27F2;</button>
</div>

<script>
(function() {
  var width = window.innerWidth;
  var height = window.innerHeight;
  var tooltip = d3.select("#tooltip");

  fetch("/api/graph")
    .then(function(res) { return res.json(); })
    .then(function(graphData) {
      d3.select("#loading").remove();
      d3.select("#graph").style("display", "block");
      d3.select("#controls").style("display", "flex");

      if (!graphData || !graphData.nodes || graphData.nodes.length === 0) {
        d3.select("body").append("div")
          .attr("style", "color:#888;text-align:center;margin-top:40vh;font-size:18px")
          .text("No notes found in vault");
        return;
      }

      var svg = d3.select("#graph")
        .attr("width", width)
        .attr("height", height);

      var g = svg.append("g");

      var zoom = d3.zoom()
        .scaleExtent([0.1, 8])
        .on("zoom", function(event) {
          g.attr("transform", event.transform);
        });

      svg.call(zoom);

      // Count connections for node sizing
      var connCount = {};
      graphData.nodes.forEach(function(n) { connCount[n.id] = 0; });
      graphData.links.forEach(function(l) {
        if (connCount[l.source] !== undefined) connCount[l.source]++;
        if (connCount[l.target] !== undefined) connCount[l.target]++;
      });

      var maxConn = 1;
      graphData.nodes.forEach(function(n) {
        if (connCount[n.id] > maxConn) maxConn = connCount[n.id];
      });

      function nodeRadius(id) {
        return 4 + (connCount[id] / maxConn) * 12;
      }

      // Simulation
      var simulation = d3.forceSimulation(graphData.nodes)
        .force("link", d3.forceLink(graphData.links).id(function(d) { return d.id; }).distance(100))
        .force("charge", d3.forceManyBody().strength(-250))
        .force("center", d3.forceCenter(width / 2, height / 2))
        .force("collision", d3.forceCollide().radius(function(d) { return nodeRadius(d.id) + 6; }));

      var link = g.append("g")
        .selectAll("line")
        .data(graphData.links)
        .join("line")
        .attr("class", "link");

      var node = g.append("g")
        .selectAll("g")
        .data(graphData.nodes)
        .join("g")
        .attr("class", "node")
        .call(d3.drag()
          .on("start", function(event, d) {
            if (!event.active) simulation.alphaTarget(0.3).restart();
            d.fx = d.x;
            d.fy = d.y;
          })
          .on("drag", function(event, d) {
            d.fx = event.x;
            d.fy = event.y;
          })
          .on("end", function(event, d) {
            if (!event.active) simulation.alphaTarget(0);
            d.fx = null;
            d.fy = null;
          })
        );

      node.append("circle")
        .attr("r", function(d) { return nodeRadius(d.id); });

      node.append("text")
        .text(function(d) { return d.title; })
        .style("opacity", function(d) { return connCount[d.id] > 0 ? 1 : 0; })
        .attr("font-size", function(d) { return Math.min(12, 6 + nodeRadius(d.id) * 0.5) + "px"; });

      // Highlight on hover
      node.on("mouseenter", function(event, d) {
        var connected = {};
        connected[d.id] = true;
        graphData.links.forEach(function(l) {
          if (l.source.id === d.id) connected[l.target.id] = true;
          if (l.target.id === d.id) connected[l.source.id] = true;
        });

        node.each(function(n) {
          var el = d3.select(this);
          if (connected[n.id]) {
            el.classed("highlight", n.id === d.id);
            el.classed("dim", false);
          } else {
            el.classed("dim", true);
            el.classed("highlight", false);
          }
        });

        link.each(function(l) {
          var el = d3.select(this);
          if (l.source.id === d.id || l.target.id === d.id) {
            el.classed("highlight", true);
            el.classed("dim", false);
          } else {
            el.classed("dim", true);
            el.classed("highlight", false);
          }
        });

        tooltip
          .style("display", "block")
          .text(d.title + " (" + (connCount[d.id] || 0) + " links)")
          .style("left", (event.offsetX + 12) + "px")
          .style("top", (event.offsetY - 10) + "px");
      });

      node.on("mousemove", function(event) {
        tooltip
          .style("left", (event.offsetX + 12) + "px")
          .style("top", (event.offsetY - 10) + "px");
      });

      node.on("mouseleave", function() {
        node.classed("highlight", false);
        node.classed("dim", false);
        link.classed("highlight", false);
        link.classed("dim", false);
        tooltip.style("display", "none");
      });

      node.on("click", function(event, d) {
        event.stopPropagation();
        tooltip
          .style("display", "block")
          .text(d.title + "\n" + d.id + "\n" + (d.path || ""))
          .style("left", (event.offsetX + 12) + "px")
          .style("top", (event.offsetY - 10) + "px");
      });

      svg.on("click", function() {
        node.classed("highlight", false);
        node.classed("dim", false);
        link.classed("highlight", false);
        link.classed("dim", false);
        tooltip.style("display", "none");
      });

      simulation.on("tick", function() {
        link
          .attr("x1", function(d) { return d.source.x; })
          .attr("y1", function(d) { return d.source.y; })
          .attr("x2", function(d) { return d.target.x; })
          .attr("y2", function(d) { return d.target.y; });

        node.attr("transform", function(d) {
          return "translate(" + d.x + "," + d.y + ")";
        });
      });

      // Controls
      document.getElementById("btn-zoom-in").onclick = function() {
        svg.transition().duration(300).call(zoom.scaleBy, 1.3);
      };
      document.getElementById("btn-zoom-out").onclick = function() {
        svg.transition().duration(300).call(zoom.scaleBy, 0.7);
      };
      document.getElementById("btn-reset").onclick = function() {
        svg.transition().duration(500).call(zoom.transform, d3.zoomIdentity);
      };

      // Resize
      window.addEventListener("resize", function() {
        width = window.innerWidth;
        height = window.innerHeight;
        svg.attr("width", width).attr("height", height);
        simulation.force("center", d3.forceCenter(width / 2, height / 2));
        simulation.alpha(0.3).restart();
      });

      // Stats
      d3.select("#stats")
        .text(graphData.nodes.length + " nodes \u00B7 " + graphData.links.length + " links");
    })
    .catch(function(err) {
      d3.select("#loading")
        .text("Failed to load graph: " + err.message)
        .style("color", "#f44");
    });
})();
</script>
</body>
</html>
]]

return M
