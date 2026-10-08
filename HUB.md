# CS2 Time to Damage

<img src="https://raw.githubusercontent.com/vsvito420/omarchy-cs2-ttd/main/icon.svg" width="72" alt="Icon von CS2 Time to Damage">

**Time to Damage (TTD)** ist die Zeit vom ersten Sehen eines Gegners bis zum ersten Schaden – weniger ist besser.
Das Widget holt den Wert alle 2 Stunden und zeigt in der Omarchy-Bar, ob man schneller wird, z. B. seit dem Wechsel auf Omarchy.

![Report mit Beispielwerten](https://raw.githubusercontent.com/vsvito420/omarchy-cs2-ttd/main/screenshots/report.png)

## Was es zeigt

- **Bar** – Ø-TTD in ms plus Änderung seit dem ersten Snapshot (`↓24` = 24 ms schneller)
- **Panel**
  - Trendlinie über die letzten Snapshots (höher = schneller)
  - Startwert, scope.gg aktuell / vorher, schnellster Wert
  - Time to Kill, Leetify-Reaktionszeit, letztes Spiel
- **Report** – HTML-Seite mit Diagrammen und ganzem Verlauf
  - optional mit markiertem Datum, z. B. „Omarchy seit …“

## Bedienung

- **Linksklick** – Panel öffnen
- **Rechtsklick** – sofort neu abrufen
- im Panel: `r` oder Enter aktualisiert, **Report** öffnet die HTML-Seite

## Installieren

```bash
omarchy plugin add https://github.com/vsvito420/omarchy-cs2-ttd.git --enable
~/.config/omarchy/plugins/vsvito.cs2-ttd/install.sh
```

- `install.sh` fragt einmal nach der **SteamID64** (17 Ziffern, z. B. über [steamid.io](https://steamid.io))
  - landet nur lokal in `~/.config/cs2-ttd/config` (`chmod 600`), nie im Repo
- legt ein Python-venv mit `curl_cffi` an und den systemd-User-Timer `cs2-ttd.timer` (alle 2 Stunden)
- entfernen: `install.sh --remove` und `omarchy plugin remove vsvito.cs2-ttd` – Config und Verlauf bleiben

## So funktioniert's

- **Code:** [`tracker.py`](https://github.com/vsvito420/omarchy-cs2-ttd/blob/main/tracker/tracker.py) und [`CS2TTD.qml`](https://github.com/vsvito420/omarchy-cs2-ttd/blob/main/CS2TTD.qml)
- **Tracker:** liest das öffentliche Profil von `cs2tracker.gg/api/player/<steamid>` (Werte von scope.gg und Leetify)
  - neue Zeile in `~/.local/state/cs2-ttd/data.jsonl` nur, wenn sich etwas geändert hat
  - schreibt `widget.json` für die Bar und `report.html` für den Browser
  - `tracker.py show` zeigt den Verlauf im Terminal
- **Widget:** beobachtet nur `widget.json` – kostet beim Spielen nichts

<div class="callout warning" markdown="1">
cs2tracker.gg hat **keine offizielle API**. Der Tracker nutzt denselben Endpunkt wie die Webseite, mit Chrome-ähnlichem
TLS-Fingerabdruck (`curl_cffi`), weil Cloudflare einfache Skripte blockt – kann also jederzeit kaputtgehen.
scope.gg rechnet TTD nur für analysierte Matches, das Profil muss dort öffentlich sein.
</div>

## Siehe auch

- [[Counter-Strike 2]], [[Omarchy]]
- [[CS2 CFG Configurator]], [[Energieprofil-Tacho für die Bar]]
