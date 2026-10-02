<div align="center">

<img src="icon.svg" width="96" alt="CS2-TTD-Icon">

# omarchy-cs2-ttd

**Deine Counter-Strike-2-Time-to-Damage in der Omarchy-Bar, mit Trend und Verlauf.**
Für [Omarchy](https://omarchy.org) / Hyprland.

[![Omarchy](https://img.shields.io/badge/Omarchy-Shell--Plugin-1793d1?style=for-the-badge&logo=archlinux&logoColor=white)](https://omarchy.org)
[![CS2](https://img.shields.io/badge/Counter--Strike_2-TTD-f59e0b?style=for-the-badge&logo=counterstrike&logoColor=white)](#was-es-zeigt)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-green?style=for-the-badge)](LICENSE)
[![English](https://img.shields.io/badge/read_me-English-black?style=for-the-badge)](README.md)

![Der Report mit Beispielwerten](screenshots/report.png)

</div>

---

## Was es zeigt

**Time to Damage (TTD)** ist die Zeit vom ersten Sehen eines Gegners bis zum ersten Schaden. Weniger ist besser.
Das Widget führt einen Verlauf, damit du siehst, ob du schneller wirst, zum Beispiel seit dem Wechsel auf ein neues Setup.

| | |
|---|---|
| 🎯 **Bar** | Ø-TTD in ms, dazu die Änderung seit dem ersten Snapshot (`↓24` = 24 ms schneller) |
| 📈 **Panel** | Trendlinie, Startwert, scope.gg aktuell / vorher, schnellster Wert, Time to Kill, Leetify-Reaktionszeit, letztes Spiel |
| 📄 **Report** | HTML-Seite mit Diagrammen und dem ganzen Verlauf, optional mit markiertem Datum (z. B. *Omarchy seit …*) |
| 🔄 **Aktualisieren** | Rechtsklick aufs Widget, oder `r` / Enter im Panel |

## Installation

```bash
omarchy plugin add https://github.com/vsvito420/omarchy-cs2-ttd.git --enable
~/.config/omarchy/plugins/vsvito.cs2-ttd/install.sh
```

`install.sh` fragt nach deiner **SteamID64** (17 Ziffern, nachschauen auf [steamid.io](https://steamid.io)) und optional nach einem Datum,
das in den Diagrammen markiert wird. Dann richtet es ein:

- die Config in `~/.config/cs2-ttd/config` (nur auf deinem Rechner, `chmod 600`)
- ein Python-venv mit `curl_cffi` in `~/.local/share/cs2-ttd/venv`
- den systemd-User-Timer `cs2-ttd.timer`, der alle 2 Stunden einen Snapshot macht

Tracker entfernen mit `install.sh --remove`, Widget mit `omarchy plugin remove vsvito.cs2-ttd`.
Config und Verlauf in `~/.local/state/cs2-ttd/` bleiben erhalten.

## So funktioniert's

- **Tracker:** [`tracker/tracker.py`](tracker/tracker.py) liest dein öffentliches Profil von `cs2tracker.gg/api/player/<steamid>`.
  Die Werte kommen von scope.gg und Leetify.
  - eine neue Zeile in `data.jsonl` gibt es nur, wenn sich etwas geändert hat
  - schreibt `widget.json` für die Bar und `report.html` für den Browser
  - `tracker.py show` zeigt den Verlauf im Terminal
- **Widget:** [`CS2TTD.qml`](CS2TTD.qml) beobachtet nur `widget.json` und kostet beim Spielen also nichts.
  Aktualisieren startet sofort `cs2-ttd.service`.

> [!NOTE]
> cs2tracker.gg hat keine offizielle API. Der Tracker nutzt denselben Endpunkt wie die Webseite, mit Chrome-ähnlichem
> TLS-Fingerabdruck (`curl_cffi`), weil Cloudflare einfache Skripte blockt. Das kann jederzeit kaputtgehen. scope.gg
> berechnet TTD nur für Matches, die es analysiert hat, dein Profil muss dort also öffentlich sein.

## Voraussetzungen

- Omarchy mit der Quickshell-Shell (Bar-Widgets über `~/.config/omarchy/plugins/`)
- Python 3 mit `venv`
- ein öffentliches CS2-Profil auf [scope.gg](https://scope.gg) / [Leetify](https://leetify.com)

## Lizenz

[MIT](LICENSE) © 2026 vsvito420
