#!/usr/bin/env python3
"""Check a contract against CONTRACT.md before it is delegated (Python 3, standard library only).

    python3 scripts/check-contract.py <contract.md|contract.yaml> ...   (Windows: py -3 scripts\\check-contract.py)

The contract is the YAML header between `---` lines, or a top-level `contract:` block.
ERROR (exit 1) — the contract must not go out:
  - id, title, intent, acceptance, non_goals or do_not_decide missing; intent empty;
  - an acceptance criterion without `check`, with a check other than oracle / review / owner, or an
    `oracle` check without `how` (a criterion with no nameable check is a planning gap, CONTRACT.md);
  - non_goals without the two default lines (no changes beyond the fix …, do not weaken … tests …).
WARN — allowed, but say why in the brief:
  - budget.model, budget.escalate_to or touches missing; no criterion with an oracle check.
Reads the structure line by line (no YAML library needed), so keep the CONTRACT.md layout.
"""
import pathlib
import re
import sys


def block(lines):
    """The contract's lines, de-indented: the front matter, or the body of a top-level `contract:`."""
    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), len(lines))
        return lines[1:end]
    for i, l in enumerate(lines):
        if l.rstrip() == "contract:":
            body = []
            for m in lines[i + 1:]:
                if m.strip() and not m.startswith((" ", "\t")):
                    break
                body.append(m)
            ind = min((len(m) - len(m.lstrip()) for m in body if m.strip()), default=0)
            return [m[ind:] for m in body]
    return lines


def top_keys(lines):
    """{key: [the lines of its value]} for unindented `key:` lines."""
    keys, cur = {}, None
    for l in lines:
        m = re.match(r"^([a-z_]+):\s*(.*)$", l)
        if m:
            cur = m.group(1)
            keys[cur] = [m.group(2)] if m.group(2) else []
        elif cur is not None:
            keys[cur].append(l)
    return keys


def value(text):
    return re.sub(r"\s+#.*$", "", text).strip()


def check(path):
    errs, warns = [], []
    k = top_keys(block(path.read_text(encoding="utf-8").splitlines()))
    for key in ("id", "title", "intent", "acceptance", "non_goals", "do_not_decide"):
        if key not in k:
            errs.append(f"missing `{key}`")
    intent = " ".join(value(l) for l in k.get("intent", [])).replace(">", "").replace("|", "").strip()
    if "intent" in k and not intent:
        errs.append("`intent` is empty")

    items, cur = [], None
    for l in k.get("acceptance", []):
        m = re.match(r"^\s*-\s*\{?\s*criterion:\s*(.*)$", l)
        if m:
            cur = {"criterion": value(m.group(1)).rstrip("}")}
            items.append(cur)
            inline = dict(re.findall(r"(check|how):\s*([^,}]+)", m.group(1)))
            cur.update({a: value(b) for a, b in inline.items()})
            continue
        m = re.match(r"^\s+(check|how):\s*(.*)$", l)
        if m and cur is not None:
            cur[m.group(1)] = value(m.group(2))
    if "acceptance" in k and not items:
        errs.append("`acceptance` has no criteria")
    for n, it in enumerate(items, 1):
        c = it.get("check")
        if not c:
            errs.append(f"criterion {n} has no `check` ({it['criterion'][:60]})")
        elif c not in ("oracle", "review", "owner"):
            errs.append(f"criterion {n}: check `{c}` is not oracle / review / owner")
        elif c == "oracle" and not it.get("how"):
            errs.append(f"criterion {n}: oracle check without `how`")
    if items and not any(it.get("check") == "oracle" for it in items):
        warns.append("no criterion has an oracle check: everything rests on opinion")

    ng = " ".join(k.get("non_goals", [])).lower()
    if "non_goals" in k:
        if "beyond the fix" not in ng:
            errs.append("non_goals lacks the default 'no changes beyond the fix, its diagnostics and its test'")
        if "weaken" not in ng:
            errs.append("non_goals lacks the default 'do not weaken or loosen tests, timeouts or tolerances'")

    budget = "\n".join(k.get("budget", []))
    if not re.search(r"^\s+model:\s*\S", budget, re.M):
        warns.append("budget.model missing (CORE §7)")
    if not re.search(r"^\s+escalate_to:\s*\S", budget, re.M):
        warns.append("budget.escalate_to missing (no stronger model to retry on)")
    if not "".join(value(l) for l in k.get("touches", [])).strip("[] "):
        warns.append("touches missing or empty (no conflict foresight, CORE §4a)")
    return errs, warns


failed = False
for arg in sys.argv[1:] or sys.exit(__doc__):
    errs, warns = check(pathlib.Path(arg))
    for e in errs:
        print(f"{arg}: ERROR {e}")
    for w in warns:
        print(f"{arg}: WARN  {w}")
    print(f"{arg}: {'FAIL' if errs else 'OK'} ({len(errs)} errors, {len(warns)} warnings)")
    failed |= bool(errs)
sys.exit(1 if failed else 0)
