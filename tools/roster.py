"""Renders docs/roster.html from the game's own tables (`auto-survivors --roster`): every class, its rule, base
numbers, promotion and upgrades, what each class's upgrades cover, and every foe. Build zig-out-dev first."""
import html
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "zig-out-dev" / "bin" / "auto-survivors.exe"
OUT = ROOT / "docs" / "roster.html"

TAG_NAMES = {
    "damage": "Damage", "rate": "Speed", "reach": "Reach", "area": "Area", "count": "Count", "crit": "Crit",
    "survival": "Survival", "healing": "Healing", "control": "Control", "status": "Status",
}


def esc(s):
    return html.escape(str(s))


def num(v, places=2):
    s = f"{v:.{places}f}"
    return s.rstrip("0").rstrip(".") if "." in s else s


def main():
    data = json.loads(subprocess.run([str(EXE), "--roster"], capture_output=True, text=True, check=True).stdout)
    classes, foes, tags = data["classes"], data["foes"], data["tags"]
    most = max(len(c["ups"]) for c in classes)

    gaps = []
    no_branch = [c["name"] for c in classes if not c["branches"]]
    if no_branch:
        gaps.append(("No promotion at level 5", no_branch))
    short = [f'{c["name"]} ({len(c["ups"])})' for c in classes if len(c["ups"]) < most]
    if short:
        gaps.append((f"Fewer upgrades than the most any class has ({most})", short))
    no_dmg = [c["name"] for c in classes if c["dmg"] == 0]
    if no_dmg:
        gaps.append(("Deals no damage of its own", no_dmg))
    for tag in ("survival", "crit", "damage"):
        lacking = [c["name"] for c in classes if not any(u["tag"] == tag for u in c["ups"])]
        if lacking:
            gaps.append((f"No {TAG_NAMES[tag].lower()} upgrade", lacking))

    matrix_head = "".join(f'<th scope="col">{TAG_NAMES[t]}</th>' for t in tags)
    matrix_rows = []
    for c in classes:
        cells = []
        for t in tags:
            n = sum(1 for u in c["ups"] if u["tag"] == t)
            names = ", ".join(u["name"] for u in c["ups"] if u["tag"] == t)
            cells.append(f'<td class="cov" title="{esc(names)}">{"<span class=dot></span>" * n if n else "<span class=none>-</span>"}</td>')
        matrix_rows.append(f'<tr><th scope="row"><span class="chip" style="--c:{c["colour"]}"></span>{esc(c["name"])}</th>{"".join(cells)}<td class="n">{len(c["ups"])}</td></tr>')

    sheets = []
    for c in classes:
        ups = "".join(
            f'<tr><td class="up">{esc(u["name"])}</td><td>{esc(u["desc"])}</td><td><span class="tag">{TAG_NAMES[u["tag"]]}</span></td><td class="n">{u["max"]}</td></tr>'
            for u in c["ups"]
        )
        if c["branches"]:
            branches = "".join(f'<li><b>{esc(b["name"])}</b> {esc(b["desc"])}</li>' for b in c["branches"])
            promo = f'<ul class="branches">{branches}</ul>'
        else:
            promo = '<p class="missing">No promotion</p>'
        base = [("HP", num(c["hp"], 0)), ("Damage", num(c["dmg"], 1)), ("Every", f'{num(c["cd"])} s'), ("Reach", f'{num(c["range"], 1)} cells'), ("Crit", f'{num(c["crit"] * 100, 0)}%')]
        base_html = "".join(f"<div><dt>{k}</dt><dd>{v}</dd></div>" for k, v in base)
        sheets.append(f"""
<section class="sheet" id="{esc(c['name'].lower())}">
  <header><span class="chip big" style="--c:{c['colour']}"></span><h3>{esc(c['name'])}</h3><span class="rule">{esc(c['rule'])}</span></header>
  <p class="ruledesc">{esc(c['rule_desc'])}</p>
  <dl class="base">{base_html}</dl>
  <div class="scroll"><table class="ups"><thead><tr><th>Upgrade</th><th>Effect a rank</th><th>Covers</th><th class="n">Ranks</th></tr></thead><tbody>{ups}</tbody></table></div>
  <h4>Promotion</h4>{promo}
</section>""")

    foe_rows = []
    for f in foes:
        ranged = []
        if f["spit_dmg"]:
            ranged.append(f'spit {num(f["spit_dmg"], 0)}')
        if f["lob_dmg"]:
            ranged.append(f'{"warned " if f["warned"] else ""}blast {num(f["lob_dmg"], 0)} in {num(f["lob_radius"], 1)}')
        traits = []
        if f["armor"]:
            traits.append(f'shrugs off {num(f["armor"] * 100, 0)}%')
        if f["turn"]:
            traits.append(f'turns {num(f["turn"], 1)} rad/s')
        if f["keep"]:
            traits.append(f'keeps {num(f["keep"], 1)} cells off')
        foe_rows.append(
            f'<tr><td class="up">{esc(f["name"].capitalize())}</td><td class="n">{num(f["hp"], 0)}</td><td class="n">{num(f["speed"], 2)}</td>'
            f'<td class="n">{num(f["dmg"], 0)}</td><td>{esc(", ".join(ranged)) or "-"}</td><td>{esc(", ".join(traits)) or "-"}</td>'
            f'<td class="n">{num(f["scales"] * 100, 0)}%</td><td class="n">{num(f["xp"], 0)}</td></tr>'
        )

    gap_html = "".join(f'<li><span class="gapname">{esc(name)}</span> {esc(", ".join(who))}</li>' for name, who in gaps) or "<li>None found</li>"
    toc = "".join(f'<a href="#{esc(c["name"].lower())}"><span class="chip" style="--c:{c["colour"]}"></span>{esc(c["name"])}</a>' for c in classes)

    page = f"""<title>Auto Survivors Roster</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Balthazar&family=Source+Sans+3:wght@400;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
/* A reference sheet: summary of gaps and coverage first, then one sheet per class, then the foes. */
:root {{
  --bg: #eef0f3; --panel: #ffffff; --fg: #1d1f26; --muted: #5b5f6b; --line: #d5d8de; --brass: #8a6a1c; --warn: #a33a2a;
  --display: "Balthazar", Georgia, serif; --body: "Source Sans 3", "Segoe UI", system-ui, sans-serif; --mono: "IBM Plex Mono", Consolas, monospace;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg: #101218; --panel: #171a22; --fg: #e2d9c4; --muted: #9a927e; --line: #2c2f3a; --brass: #c9a24a; --warn: #e0705a; color-scheme: dark; }} }}
:root[data-theme="dark"] {{ --bg: #101218; --panel: #171a22; --fg: #e2d9c4; --muted: #9a927e; --line: #2c2f3a; --brass: #c9a24a; --warn: #e0705a; color-scheme: dark; }}
body {{ background: var(--bg); color: var(--fg); font: 15px/1.5 var(--body); }}
main {{ max-width: 1180px; margin: 0 auto; padding-inline: 16px; padding-block: 28px 64px; display: grid; gap: 36px; }}
h1, h2, h3 {{ font-family: var(--display); font-weight: 400; text-wrap: balance; margin: 0; }}
h1 {{ font-size: 2.4rem; color: var(--brass); }}
h2 {{ font-size: 1.6rem; border-bottom: 1px solid var(--line); padding-bottom: 6px; }}
h3 {{ font-size: 1.45rem; }}
h4 {{ margin: 0; font-size: .78rem; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }}
.lede {{ color: var(--muted); max-width: 68ch; margin: 6px 0 0; }}
.toc {{ display: flex; flex-wrap: wrap; gap: 6px 16px; margin-top: 14px; }}
.toc a {{ color: var(--fg); text-decoration: none; display: inline-flex; align-items: center; gap: 6px; }}
.toc a:hover, .toc a:focus-visible {{ color: var(--brass); }}
a:focus-visible {{ outline: 2px solid var(--brass); outline-offset: 2px; }}
.chip {{ display: inline-block; width: 10px; height: 10px; border-radius: 2px; background: var(--c); box-shadow: 0 0 0 1px color-mix(in srgb, var(--fg) 25%, transparent); }}
.chip.big {{ width: 14px; height: 14px; }}
section {{ display: grid; gap: 14px; min-width: 0; }}
.gaps {{ list-style: none; padding: 0; margin: 0; display: grid; gap: 6px; }}
.gaps li {{ padding: 8px 12px; background: var(--panel); border-left: 3px solid var(--warn); }}
.gapname {{ font-weight: 600; margin-right: 6px; }}
.scroll {{ overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }}
th, td {{ text-align: left; padding: 6px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }}
thead th {{ font-size: .75rem; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); font-weight: 600; white-space: nowrap; }}
.n {{ text-align: right; font-family: var(--mono); font-size: .9rem; }}
.matrix th[scope=row] {{ white-space: nowrap; font-weight: 600; display: flex; align-items: center; gap: 8px; }}
.matrix td.cov {{ text-align: center; white-space: nowrap; }}
.dot {{ display: inline-block; width: 9px; height: 9px; border-radius: 50%; background: var(--brass); margin: 0 1px; }}
.none {{ color: var(--line); }}
.sheets {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 520px), 1fr)); gap: 20px; }}
.sheet {{ background: var(--panel); padding: 16px 18px 18px; border: 1px solid var(--line); align-content: start; }}
.sheet header {{ display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }}
.rule {{ font-family: var(--mono); font-size: .82rem; color: var(--brass); }}
.ruledesc {{ margin: 0; color: var(--muted); }}
.base {{ display: flex; flex-wrap: wrap; gap: 6px 22px; margin: 0; }}
.base dt {{ font-size: .72rem; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); }}
.base dd {{ margin: 0; font-family: var(--mono); }}
.ups .up {{ font-weight: 600; white-space: nowrap; }}
.tag {{ font-family: var(--mono); font-size: .75rem; color: var(--brass); white-space: nowrap; }}
.branches {{ margin: 0; padding-left: 18px; display: grid; gap: 4px; }}
.missing {{ margin: 0; color: var(--warn); }}
.src {{ color: var(--muted); font-size: .85rem; }}
code {{ font-family: var(--mono); font-size: .88em; }}
</style>
<main>
  <header>
    <h1>Auto Survivors Roster</h1>
    <p class="lede">Every class, its formation rule, base numbers, promotion and upgrades, and every foe, read from the game's own tables. Hover a dot in the coverage table to see which upgrades fill it.</p>
    <nav class="toc" aria-label="Classes">{toc}</nav>
  </header>
  <section>
    <h2>Gaps</h2>
    <ul class="gaps">{gap_html}</ul>
  </section>
  <section>
    <h2>Upgrade coverage</h2>
    <div class="scroll"><table class="matrix"><thead><tr><th>Class</th>{matrix_head}<th class="n">Total</th></tr></thead><tbody>{"".join(matrix_rows)}</tbody></table></div>
  </section>
  <section>
    <h2>Classes</h2>
    <div class="sheets">{"".join(sheets)}</div>
  </section>
  <section>
    <h2>Foes</h2>
    <div class="scroll"><table><thead><tr><th>Foe</th><th class="n">HP</th><th class="n">Speed</th><th class="n">Bite</th><th>Ranged</th><th>Traits</th><th class="n">HP growth</th><th class="n">XP</th></tr></thead><tbody>{"".join(foe_rows)}</tbody></table></div>
    <p class="src">Speed is cells a second; the party moves {num(data['party_speed'], 2)}. HP growth is the share of the run's health ramp a foe takes. Regenerate with <code>python tools/roster.py</code>.</p>
  </section>
</main>
"""
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(page, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(classes)} classes, {len(foes)} foes, {len(gaps)} gap lines")


main()
