#!/usr/bin/env python3
"""Parse Primecare drug formulary PDF text into JSON for seeding."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

FORMS = {
    "tablet", "capsule", "injection", "syrup", "suspension", "gel", "ointment",
    "drops", "cream", "solution", "powder", "lotion", "spray", "patch",
    "suppository", "liquid", "ampoule", "vial", "infusion", "granules",
    "lozenge", "inhaler", "device", "kit", "bag", "pen", "film", "foam",
    "paste", "oil", "enema", "gargle", "mouthwash", "shampoo", "soap",
    "tube", "bottle", "box", "sachet", "strip", "pack", "dropper",
    "cartridge", "inhalation", "invalid",
}

HEADER_RE = re.compile(
    r"Name\s+Generic\s+Strength\s+Form\s+Pack\s+Therapeutic category\s+Active\s+Ctrl\s+"
    r"Unit \(GHS\)\s+Cost \(GHS\)\s+Stock qty\s+Batches\s+ATC\s*"
)


def is_form(token: str) -> bool:
    return token.strip().lower() in FORMS


def clean_category(raw: str) -> str:
    raw = re.sub(r"\s+", " ", raw).strip()
    if " - " in raw:
        return raw.split(" - ", 1)[0].strip()[:80]
    m = re.match(r"^[A-Za-z][A-Za-z\s/&-]{2,60}", raw)
    return (m.group(0).strip() if m else "Pharmacy")[:80]


def parse_lines(lines: list[str]) -> list[dict]:
    drugs: list[dict] = []
    n = len(lines)
    last_end = 0
    i = 0

    while i < n - 5:
        if lines[i] not in ("Yes", "No") or lines[i + 1] not in ("Yes", "No"):
            i += 1
            continue
        try:
            unit = float(lines[i + 2].replace(",", ""))
            cost_val = float(lines[i + 3].replace(",", ""))
            stock_i = int(lines[i + 4])
            int(lines[i + 5])
        except ValueError:
            i += 1
            continue

        active_flag = lines[i] == "Yes"
        body = lines[last_end:i]
        last_end = i + 6
        if last_end < n and re.fullmatch(r"[A-Z0-9]{2,10}", lines[last_end]):
            last_end += 1
        i = last_end

        if len(body) < 3:
            continue

        form_idx = None
        for k in range(len(body) - 1, -1, -1):
            if is_form(body[k]):
                form_idx = k
                break
        if form_idx is None or form_idx < 1:
            continue

        form = body[form_idx].strip().title()
        strength = body[form_idx - 1]
        name = body[0]
        if len(name) < 3 or name.startswith("/") or re.fullmatch(r"[\d.]+", name):
            continue

        generic = " ".join(body[1:form_idx - 1]).strip()
        pack = ""
        cat_start = form_idx + 1
        if cat_start < len(body) and re.fullmatch(r"\d+", body[cat_start]):
            pack = body[cat_start]
            cat_start += 1
        category = clean_category(" ".join(body[cat_start:]))

        display = name
        if strength and strength.lower() not in name.lower() and re.search(r"\d|mg|ml|mcg|g", strength, re.I):
            display = f"{name} {strength}"
        if form.lower() not in display.lower():
            display = f"{display} ({form})"

        price = unit if unit > 0 else (cost_val if cost_val > 0 else 0)
        if price <= 0:
            continue
        if not active_flag:
            continue

        drugs.append(
            {
                "name": display[:180],
                "generic": generic[:180],
                "strength": strength[:80],
                "form": form,
                "pack": pack,
                "category": category or "Pharmacy",
                "unit_price": round(price, 2),
                "stock_qty": max(stock_i, 0),
                "active": active_flag,
            }
        )

    return drugs


def main() -> int:
    pdf_path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else r"c:\Users\user\Downloads\Documents\drug_formulary_20260520_133536.pdf"
    )
    out_path = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else Path(__file__).resolve().parent.parent / "scratch" / "primecare_formulary.json"
    )

    scratch_txt = Path(__file__).resolve().parent.parent / "scratch" / "formulary_raw.txt"
    raw = scratch_txt.read_text(encoding="utf-8")
    raw = HEADER_RE.sub("\n", raw)
    raw = re.sub(r"Drug Formulary.*?Total drugs: \d+\s*", "", raw, flags=re.S)
    lines = [ln.strip() for ln in raw.splitlines() if ln.strip()]

    drugs = parse_lines(lines)
    seen: dict[str, dict] = {}
    for d in drugs:
        key = d["name"].lower()
        prev = seen.get(key)
        if prev is None or (
            d["active"]
            and d["unit_price"] > 0
            and (not prev["active"] or d["stock_qty"] > prev["stock_qty"])
        ):
            seen[key] = d

    final = [
        d
        for d in seen.values()
        if d["active"] and d["unit_price"] > 0 and len(d["name"]) >= 4
    ]
    final.sort(key=lambda x: (x["category"], x["name"]))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(final, indent=2), encoding="utf-8")
    print(f"Parsed {len(drugs)} rows, {len(final)} active priced products -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
