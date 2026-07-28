#!/usr/bin/env bash
set -euo pipefail

ROOT=/Users/jackgreenberg/Desktop/rank-and-rent
S=$ROOT/David/clones/scripts
PROJ=$ROOT/mineral-rights/royaltybuyerusa.com
REFHOST=cesiumastro-com
VOICE=$PROJ/site-voice.json
PAGES="home=https://www.cesiumastro.com/,about=https://www.cesiumastro.com/about,contact=https://www.cesiumastro.com/contact,index=https://www.cesiumastro.com/newsroom,slug=https://www.cesiumastro.com/products/vireo/ka-576"
CFG=$PROJ/home.config.json
MAP=$S/relabel-map-$REFHOST.json
CAP=$ROOT/David/clones/_captures/$REFHOST

[ -f "$CFG" ] || { echo "MISSING $CFG"; exit 1; }
[ -f "$MAP" ] || { echo "MISSING $MAP"; exit 1; }
[ -f "$VOICE" ] || { echo "MISSING $VOICE"; exit 1; }

if [ ! -f "$CAP/public/home.html.ref" ]; then
  node "$S/faithful-home.mjs" --src "https://www.cesiumastro.com/" --pages "$PAGES" --dir "$CAP"
fi

mkdir -p "$PROJ/public" "$PROJ/qa-out"
cp "$CAP"/public/*.html.ref "$PROJ/public/" 2>/dev/null || true
rm -rf "$PROJ/public/assets-f"
cp -R "$CAP/public/assets-f" "$PROJ/public/"
cp "$CAP"/qa-out/ref-*.png "$PROJ/qa-out/" 2>/dev/null || true

python3 "$PROJ/scripts/institutionalize_content.py"
python3 "$S/normalize_content.py" "$PROJ" --voice "$VOICE"

python3 - "$PROJ" <<'PY'
import os
import shutil
import sys

project = sys.argv[1]
source = os.path.join(project, "images")
target = os.path.join(project, "public", "ours")
if os.path.isdir(source):
    shutil.copytree(source, target, dirs_exist_ok=True)
PY

python3 "$S/relabel_engine.py" --config "$CFG" --map "$MAP" --voice "$VOICE"
python3 "$S/verify_site.py" "$PROJ" --map "$MAP" --json "$PROJ/qa-out/verify.json"
rm -f "$PROJ/public/"*.html.ref

python3 - "$PROJ" <<'PY'
import pathlib
import shutil
import sys

project = pathlib.Path(sys.argv[1])
assets = project / "public" / "assets-f"
removed = []
for dirname in ("img", "js", "media", "misc"):
    directory = assets / dirname
    if directory.is_dir():
        removed.extend(path for path in directory.rglob("*") if path.is_file())
        shutil.rmtree(directory)

for path in assets.rglob("*"):
    if not path.is_file():
        continue
    head = path.read_bytes()[:4096].lstrip().lower()
    if head.startswith(b"<!doctype html") or head.startswith(b"<html") or b"<html" in head[:512]:
        removed.append(path)
        path.unlink()

print(
    f"ASSET CLEANUP: removed {len(set(removed))} unused donor media/runtime files "
    "and HTML capture impostors"
)
PY

python3 - "$PROJ" <<'PY'
import pathlib
import re
import sys
from bs4 import BeautifulSoup

project = pathlib.Path(sys.argv[1])
pages = sorted(project.joinpath("public").rglob("*.html"))
failures = []
map_count = 0
address_fragments = (
    "601 N Marienfeld",
    "N Marienfeld St, Midland",
    "Midland, TX 79701",
)
donor_terms = (
    "CesiumAstro",
    "Connect. Detect. Defend.",
    "Mission Systems",
    "Communication Systems",
    "Space Systems",
    "Vireo",
    "Skylark",
    "Nightingale",
    "Shey Sabripour",
    "Robert Myhill",
)

for page in pages:
    soup = BeautifulSoup(page.read_text(errors="ignore"), "html.parser")
    visible = " ".join(soup.get_text(" ", strip=True).split())
    first_person = re.search(r"\b(i|me|my|myself)\b", visible, flags=re.I)
    if first_person:
        failures.append(
            f"{page.relative_to(project)}: singular first-person copy: {first_person.group(0)}"
        )
    for forbidden in address_fragments + donor_terms:
        if forbidden.lower() in visible.lower():
            failures.append(f"{page.relative_to(project)}: visible forbidden text: {forbidden}")
    footer = soup.select_one("footer")
    if footer and footer.select("img,picture,svg,video,canvas,iframe,source"):
        failures.append(f"{page.relative_to(project)}: footer media must be zero")
    for image in soup.select("img"):
        try:
            width = int(str(image.get("width", "0")).strip() or "0")
            height = int(str(image.get("height", "0")).strip() or "0")
        except ValueError:
            width = height = 0
        if (width and width <= 32) or (height and height <= 32):
            failures.append(
                f"{page.relative_to(project)}: miniature image regression: {image.get('src', '')}"
            )
        src = str(image.get("src", ""))
        if src and not src.startswith(("/ours/", "data:")):
            failures.append(f"{page.relative_to(project)}: non-mapped image source: {src}")
    maps = soup.select('iframe[src*="google.com/maps"]')
    map_count += len(maps)
    if page.name == "contact.html" and len(maps) != 1:
        failures.append(f"{page.relative_to(project)}: expected exactly one Google Maps embed")

home = BeautifulSoup(
    project.joinpath("public", "home.html").read_text(errors="ignore"),
    "html.parser",
)
home_h1 = [" ".join(node.get_text(" ", strip=True).split()) for node in home.select("h1")]
if (
    len(home_h1) != 1
    or "royalty buyer" not in home_h1[0].lower()
    or "midland" not in home_h1[0].lower()
    or "texas" not in home_h1[0].lower()
):
    failures.append(f"homepage SEO H1 is invalid: {home_h1}")
hero = home.select_one("body > .c-section-2.full-h:first-of-type .background-video")
hero_style = str(hero.get("style", "")) if hero else ""
if "/ours/" not in hero_style or "background-image" not in hero_style:
    failures.append("homepage hero must contain a mapped, nonblank local background image")

if map_count != 1:
    failures.append(f"sitewide Google Maps embed count is {map_count}, expected 1")

if failures:
    print("COMPLIANCE FAIL:")
    print("\n".join(f"  {failure}" for failure in failures))
    raise SystemExit(1)

print(
    f"COMPLIANCE: PASS — {len(pages)} pages, one SEO hero H1, mapped hero image, "
    "zero singular first-person copy, zero visible addresses, zero footer media, "
    "zero miniature image regressions, one map embed"
)
PY

QA_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
node "$S/qa_shots.mjs" "$PROJ" --port "$QA_PORT"
echo "BUILD COMPLETE — gates green. Human QA: open $PROJ/qa-out/CONTACT-SHEET.html"
