#!/usr/bin/env python3
"""CS2 Time-to-Damage tracker for the Omarchy bar.

Fetches /api/player/<steamid> from cs2tracker.gg (values come from scope.gg and
Leetify), stores snapshots in data.jsonl and builds widget.json + report.html.

  tracker.py          fetch a snapshot and rebuild everything
  tracker.py show     print the history in the terminal
  tracker.py report   only rebuild widget.json and report.html

Config: ~/.config/cs2-ttd/config (or $CS2_TTD_CONFIG)
  STEAMID=7656119...      your SteamID64 (required)
  SINCE=2026-09-26        optional: date drawn as a marker in the charts
  SINCE_LABEL=Omarchy     optional: label for that marker
State:  ~/.local/state/cs2-ttd/ (or $CS2_TTD_STATE)
"""
import html
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("CS2_TTD_CONFIG", HOME / ".config/cs2-ttd/config"))
STATE = Path(os.environ.get("CS2_TTD_STATE", HOME / ".local/state/cs2-ttd"))
DATA = STATE / "data.jsonl"
LAST_CHECK = STATE / "last_check"
REPORT = STATE / "report.html"
WIDGET = STATE / "widget.json"


def load_config():
    cfg = {}
    if CONFIG.exists():
        for line in CONFIG.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"')
    return cfg


CFG = load_config()
SINCE = CFG.get("SINCE") or None
SINCE_LABEL = CFG.get("SINCE_LABEL") or "Since"


def ms(sec):
    return round(sec * 1000) if isinstance(sec, (int, float)) else None


def fetch():
    steamid = CFG.get("STEAMID", "")
    if not steamid.isdigit():
        sys.exit(f"No valid STEAMID in {CONFIG} – run install.sh or add STEAMID=7656119…")
    from curl_cffi import requests  # looks like Chrome's TLS, otherwise Cloudflare blocks the request

    r = requests.get(f"https://cs2tracker.gg/api/player/{steamid}", impersonate="chrome", timeout=60)
    r.raise_for_status()
    j = r.json()
    ttd = (j.get("scopegg_display") or {}).get("time_to_damage") or {}
    ttk = (j.get("scopegg_display") or {}).get("time_to_kill") or {}
    signals = ((j.get("gauges") or {}).get("cheating_details") or {}).get("signals") or {}
    rating = (j.get("leetify_extra") or {}).get("recentGameRatings") or {}
    games = (j.get("leetify") or {}).get("games") or []
    return {
        "ttd_avg_ms": ms(ttd.get("avg_sec")),
        "ttd_current_ms": ms(ttd.get("current_sec")),
        "ttd_previous_ms": ms(ttd.get("previous_sec")),
        "ttd_fastest_ms": ms(ttd.get("fastest_sec")),
        "ttd_matches": ttd.get("matches_analyzed"),
        "ttk_avg_ms": ms(ttk.get("avg_sec")),
        "ttk_matches": ttk.get("matches_analyzed"),
        "leetify_reaction_ms": (signals.get("leetify_reaction_ms") or {}).get("value"),
        "leetify_aim": rating.get("aim"),
        "leetify_games": rating.get("gamesPlayed"),
        "last_game_at": games[0].get("gameFinishedAt") if games else None,
    }


def load():
    if not DATA.exists():
        return []
    return [json.loads(l) for l in DATA.read_text().splitlines() if l.strip()]


def snapshot():
    rows = load()
    snap = fetch()
    STATE.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    LAST_CHECK.write_text(now + "\n")
    last = {k: v for k, v in rows[-1].items() if k != "ts"} if rows else None
    if snap == last:
        print(f"{now}: unchanged (TTD {snap['ttd_avg_ms']} ms)")
        return rows
    row = {"ts": now, **snap}
    with DATA.open("a") as f:
        f.write(json.dumps(row) + "\n")
    print(f"{now}: new snapshot, TTD {snap['ttd_avg_ms']} ms over {snap['ttd_matches']} matches")
    return rows + [row]


def fmt_delta(a, b):
    if a is None or b is None:
        return "–"
    d = b - a
    return f"{d:+d} ms" if isinstance(d, int) else f"{d:+.1f}"


def show(rows):
    if not rows:
        print("No data yet.")
        return
    print(f"{'Time (UTC)':<20} {'TTD avg':>8} {'TTD cur':>8} {'Matches':>8} {'Reaction':>9}")
    for r in rows:
        print(f"{r['ts'][:16]:<20} {r['ttd_avg_ms'] or '–':>8} {r['ttd_current_ms'] or '–':>8} "
              f"{r['ttd_matches'] or '–':>8} {r['leetify_reaction_ms'] or '–':>9}")
    first, last = rows[0], rows[-1]
    print(f"\nTTD since first snapshot: {fmt_delta(first['ttd_avg_ms'], last['ttd_avg_ms'])} "
          "(negative = faster = better)")


def chart(rows, key, label, color):
    pts = [(r["ts"], r[key]) for r in rows if r.get(key) is not None]
    if len(pts) < 2:
        return f'<p class="muted">{label}: the chart appears with the second changed snapshot.</p>'
    W, H, P = 640, 220, 36
    t = [datetime.fromisoformat(p[0]).timestamp() for p in pts]
    v = [p[1] for p in pts]
    mark = datetime.fromisoformat(SINCE + "T00:00:00+00:00").timestamp() if SINCE else None
    t0, t1 = min(t + ([mark] if mark else [])), max(t)
    lo, hi = min(v), max(v)
    pad = max((hi - lo) * 0.15, 10)
    lo, hi = lo - pad, hi + pad
    x = lambda ts: P + (ts - t0) / max(t1 - t0, 1) * (W - 2 * P)
    y = lambda val: H - P + -(val - lo) / (hi - lo) * (H - 2 * P)
    path = " ".join(f"{'M' if i == 0 else 'L'}{x(a):.1f},{y(b):.1f}" for i, (a, b) in enumerate(zip(t, v)))
    dots = "".join(f'<circle cx="{x(a):.1f}" cy="{y(b):.1f}" r="3" fill="{color}"><title>{b}</title></circle>'
                   for a, b in zip(t, v))
    marker = (f'<line x1="{x(mark):.1f}" x2="{x(mark):.1f}" y1="{P/2}" y2="{H-P}" class="om"/>'
              f'<text x="{x(mark)+4:.1f}" y="{P/2+10}" class="lbl">{html.escape(SINCE_LABEL)}</text>') if mark else ""
    return f'''<figure><figcaption>{label}</figcaption>
<svg viewBox="0 0 {W} {H}" role="img" aria-label="{label}">{marker}
<text x="4" y="{y(hi-pad)+4:.1f}" class="lbl">{max(v)}</text>
<text x="4" y="{y(lo+pad)+4:.1f}" class="lbl">{min(v)}</text>
<path d="{path}" fill="none" stroke="{color}" stroke-width="2"/>{dots}
</svg></figure>'''


def write_widget(rows, last_check):
    """Compact summary for the bar widget (vsvito.cs2-ttd)."""
    last = rows[-1] if rows else {}
    first = rows[0] if rows else {}
    a, b = first.get("ttd_avg_ms"), last.get("ttd_avg_ms")
    WIDGET.write_text(json.dumps({
        "checkedAt": last_check,
        "since": SINCE,
        "sinceLabel": SINCE_LABEL,
        "first": first,
        "last": last,
        "deltaMs": b - a if a is not None and b is not None else None,
        "history": [r["ttd_avg_ms"] for r in rows if r.get("ttd_avg_ms") is not None][-50:],
        "report": str(REPORT),
    }))


def report(rows):
    STATE.mkdir(parents=True, exist_ok=True)
    last_check = LAST_CHECK.read_text().strip() if LAST_CHECK.exists() else "–"
    write_widget(rows, last_check)
    if rows:
        first, last = rows[0], rows[-1]
        d = (last["ttd_avg_ms"] or 0) - (first["ttd_avg_ms"] or 0)
        verdict = "better" if d < 0 else "worse" if d > 0 else "same"
        aim = f'Aim {last["leetify_aim"]:.1f}' if last.get("leetify_aim") is not None else ""
        tiles = f'''
<div class="tiles">
 <div><span>TTD now (avg)</span><b>{last["ttd_avg_ms"]} ms</b><small>{last["ttd_matches"]} matches (scope.gg)</small></div>
 <div><span>Since start</span><b class="{verdict}">{fmt_delta(first["ttd_avg_ms"], last["ttd_avg_ms"])}</b><small>start {first["ttd_avg_ms"]} ms on {first["ts"][:10]}</small></div>
 <div><span>scope.gg current / previous</span><b>{last["ttd_current_ms"]} / {last["ttd_previous_ms"]}</b><small>ms, period as on scope.gg</small></div>
 <div><span>Leetify reaction</span><b>{last["leetify_reaction_ms"]} ms</b><small>{aim}</small></div>
</div>'''
    else:
        tiles = '<p class="muted">No data yet.</p>'
    table = "".join(
        f"<tr><td>{html.escape(r['ts'][:16].replace('T', ' '))}</td><td>{r['ttd_avg_ms']}</td>"
        f"<td>{r['ttd_current_ms']}</td><td>{r['ttd_matches']}</td><td>{r['leetify_reaction_ms']}</td></tr>"
        for r in reversed(rows))
    since = f" · {html.escape(SINCE_LABEL)} since {SINCE}" if SINCE else ""
    REPORT.write_text(f'''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>CS2 TTD Tracker</title>
<style>
:root{{--bg:#f6f6f4;--fg:#1b1b1b;--muted:#6b6b6b;--card:#fff;--line:#ddd;--good:#1a7f37;--bad:#c4321c}}
@media (prefers-color-scheme:dark){{:root{{--bg:#141414;--fg:#eee;--muted:#999;--card:#1f1f1f;--line:#333;--good:#4ac26b;--bad:#ff7b72}}}}
body{{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;margin:0;padding:24px 16px}}
main{{max-width:720px;margin:auto}} h1{{margin:0 0 4px;font-size:22px}} .muted,small,span{{color:var(--muted)}}
.tiles{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:20px 0}}
.tiles div{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;display:flex;flex-direction:column}}
.tiles b{{font-size:22px;font-variant-numeric:tabular-nums}} .better{{color:var(--good)}} .worse{{color:var(--bad)}}
span,small{{font-size:12px}} figure{{margin:20px 0;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px}}
svg{{width:100%;height:auto}} .om{{stroke:var(--muted);stroke-dasharray:4 4}} .lbl{{fill:var(--muted);font-size:11px}}
table{{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:13px}}
td,th{{text-align:right;padding:4px 6px;border-bottom:1px solid var(--line)}} td:first-child,th:first-child{{text-align:left}}
</style></head><body><main>
<h1>CS2 Time to Damage</h1>
<p class="muted">last check {html.escape(last_check[:16].replace("T", " "))} UTC{since} · lower = better</p>
{tiles}
{chart(rows, "ttd_avg_ms", "Time to Damage avg (ms)", "#3b82f6")}
{chart(rows, "leetify_reaction_ms", "Leetify reaction time (ms)", "#f59e0b")}
<table><tr><th>Time (UTC)</th><th>TTD avg</th><th>TTD current</th><th>Matches</th><th>Reaction</th></tr>{table}</table>
</main></body></html>''')


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "fetch"
    if cmd == "show":
        show(load())
    elif cmd == "report":
        report(load())
    else:
        report(snapshot())
