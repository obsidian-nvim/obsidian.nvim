---
title: "Graph view"
site: "Obsidian Help"
source: "https://obsidian.md/help/plugins/graph"
domain: "obsidian.md"
language: "en"
description: "Graph view is a core plugin that lets you visualize the relationships between the notes in your vault."
word_count: 655
---

Graph view is a [[Core plugins|core plugin]] that lets you visualize the relationships between the notes in your vault.

To open the Graph view, click **Open graph view** in the [[Ribbon]].

- Circles represent notes, or _nodes_.
- Lines represent [[Internal links]] between two nodes.

The more nodes that reference a given node, the bigger it gets.

To interact with notes in the graph:

- Hover over each circle to highlight that note's connections.
- Click a note in the graph to open that note.
- Right-click a note to open a context menu with the actions available for that note.

To navigate around the graph:

- Zoom in and out using the scroll wheel on your mouse, or using the `+` and `-` keys.
- Move the graph around by dragging it with your mouse cursor, or using the arrow keys.

You can hold Shift while using the keyboard to speed up the movements.

## Settings

To open the graph settings, click the cog icon in the upper-right corner of the graph view.

Click **Restore default settings** in the upper-right corner of the settings box to reset any changes you make.

### Filters

This section controls what nodes to show in the graph.

- **Search files** lets you filter notes based on a search term. To learn about how you can write more advanced search terms, refer to [[Search]].
- **Tags** toggles whether to show tags in the graph.
- **Attachments** toggles whether to show attachments in the graph.
- **Existing files only** toggles whether to show notes that exists in your vault. Since a note doesn't need to exist to link to it, this can help limit your graph to notes that you actually have in your vault.
- **Orphans** toggles whether to show notes without any links.

> [!info] Excluded files
> Files matching your [[Settings#Excluded files|Excluded files]] patterns will not appear in Graph view.

### Groups

Create groups of notes to distinguish them from each other using color.

To create a new group:

1. Click **New group**.
2. In the search box, type a search term for the notes you want to add to the group.
3. Click the colored circle to give the group a color.

To learn about how you can write more advanced search terms, refer to [[Search]].

### Display

This section controls how to visualize nodes and links in the graph.

- **Arrows** toggles whether to show the direction of each link.
- **Text fade threshold** controls the text transparency for the name of each note.
- **Node size** controls the size of the circle representing each note.
- **Link thickness** controls the line width for each link.
- **Animate** starts a [[#Start a time-lapse animation|time-lapse animation]].

### Forces

This section controls the forces that act on each node in the graph.

- **Center force** controls how compact the graph is. A higher value creates a more circular graph.
- **Repel force** controls how much a node pushes other nodes away from it.
- **Link force** controls the pull on each link. If the link was a rubber band, the link force controls how tight or loose the band is.
- **Link distance** controls the length of the lines between each note.

## Start a time-lapse animation

Notes and attachments appear in chronological order based on their creation time.

![[obsidian-graph-view.png#interface]]

## Local Graph

To open a local Graph view, use the **Open local graph** command. While the Graph view shows all notes in your vault, a local Graph view shows you notes connected to the active note.

The local Graph view can use all of the [[#Settings]] available to the global Graph view. Additionally, you can change the depth of the local graph. Each level of depth will show notes connected to the notes revealed at the previous depth. To control local Graph depth, use the slider at the top of the local Graph Filter Settings panel.