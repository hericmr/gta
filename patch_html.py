#!/usr/bin/env python3
"""Roda depois de cada export do Godot para injetar o service worker no HTML."""

SW = ("<script>if ('serviceWorker' in navigator && !crossOriginIsolated) "
      "{ navigator.serviceWorker.register('coi-serviceworker.js')"
      ".then(function() { window.location.reload(); }); }</script>")

with open("santos-gta.html", "r") as f:
    html = f.read()

if SW in html:
    print("service worker já presente, nada a fazer.")
else:
    html = html.replace("</head>", SW + "\n</head>", 1)
    with open("santos-gta.html", "w") as f:
        f.write(html)
    print("service worker injetado em santos-gta.html.")
