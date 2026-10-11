#!/usr/bin/env python3
"""Check the coordinator core's own references (Python 3, standard library only).

    python3 scripts/check-core.py [repo-root]        (Windows: py -3 scripts\\check-core.py)

Fails (exit 1) on:
  - a relative Markdown link to a file that does not exist;
  - a section reference (§4b, CORE §12a, §1.16) to a section that does not exist — sections are the
    `## <id>. ` headings of CORE.md and procedures/*.md, and §1.N must name an existing hard rule.
Run in CI on every pull request and before proposing a core change (CORE §10).
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent)
md_files = sorted(p for p in root.rglob("*.md") if ".git" not in p.parts)

sections = set()
for p in [root / "CORE.md", *sorted((root / "procedures").glob("*.md"))]:
    if p.exists():
        sections |= set(re.findall(r"^## (\d+[a-z]?)\. ", p.read_text(encoding="utf-8"), re.M))

core = (root / "CORE.md").read_text(encoding="utf-8")
rules = re.search(r"^## 1\. .*?(?=^## )", core, re.M | re.S)
hard_rules = len(re.findall(r"^(\d+)\. \*\*", rules.group(0), re.M)) if rules else 0

link = re.compile(r"\]\(([^)\s]+)\)")
ref = re.compile(r"§(\d+[a-z]?)(?:\.(\d+))?")
fence = re.compile(r"^\s*```")
errors = []

for p in md_files:
    rel = p.relative_to(root)
    in_code = False
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if fence.match(line):
            in_code = not in_code
            continue
        if in_code:
            continue
        for target in link.findall(line):
            if re.match(r"[a-z]+:", target) or target.startswith("#"):
                continue
            path = target.split("#", 1)[0]
            if path and not (p.parent / path).exists():
                errors.append(f"{rel}:{n}: broken link {target}")
        for sec, sub in ref.findall(line):
            if sec not in sections:
                errors.append(f"{rel}:{n}: §{sec} does not exist")
            elif sec == "1" and sub and not 1 <= int(sub) <= hard_rules:
                errors.append(f"{rel}:{n}: §1.{sub} does not exist (CORE §1 has {hard_rules} hard rules)")

for e in errors:
    print(e)
print(f"check-core: {len(md_files)} files, {len(sections)} sections, {hard_rules} hard rules, {len(errors)} errors")
sys.exit(1 if errors else 0)
