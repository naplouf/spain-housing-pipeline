"""Parse MIVAU "Valor tasado medio de vivienda libre" (table 35101000) into a long table.

Input : data/raw/35101000.XLS  (legacy BIFF .xls, 8 sheets of 4 years each,
        quarterly euros/m2, 1995 Q1 - 2026 Q2)
Output: data/staging/mivau_valor_tasado.parquet       (one row per province x quarter)
        data/staging/mivau_valor_tasado_ccaa.parquet  (MIVAU's own published CCAA
                                                        and TOTAL NACIONAL rows)

Sheet layout (verified on all 8 sheets):
  row 11  "Año YYYY" in the first column of each 4-column year block (merged cells)
  row 13  quarter labels "1º".."4º" (sometimes with trailing spaces); the last
          sheet adds "Trimestral"/"Anual" variation columns, which are dropped
          because they are derivable and are recomputed in dbt
  row 14+ data; column 1 holds the label, hierarchical:
            TOTAL NACIONAL
            <CCAA header>          <- matched against a fixed list
              <province> ...       <- belongs to the most recent CCAA header
          single-province CCAAs have no child rows (the CCAA row IS the province)
  footer  blank row + "n.r: el dato no es representativo..." (sheets 6-8 only)

Cell values: float, "" (no data, e.g. Ceuta/Melilla before 2004) or "n.r"
(not representative). Both non-numeric cases become NULL with a value_flag.
"""
from pathlib import Path
import re
import sys

import pandas as pd
import xlrd

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data" / "raw" / "35101000.XLS"
OUT_PROVINCE = ROOT / "data" / "staging" / "mivau_valor_tasado.parquet"
OUT_CCAA = ROOT / "data" / "staging" / "mivau_valor_tasado_ccaa.parquet"

YEAR_ROW, QUARTER_ROW, FIRST_DATA_ROW, LABEL_COL = 11, 13, 14, 1
NATIONAL_LABEL = "TOTAL NACIONAL"
FOOTNOTE_PREFIX = "n.r:"

# Fixed list of the 17 CCAA + "Ceuta y Melilla" header labels as MIVAU spells them
# (after whitespace normalisation). Any label not in this list is a province.
CCAA_HEADERS = [
    "Andalucía", "Aragón", "Asturias (Principado de)", "Balears (Illes)", "Canarias",
    "Cantabria", "Castilla y León", "Castilla-La Mancha", "Cataluña",
    "Comunidad Valenciana", "Extremadura", "Galicia", "Madrid (Comunidad de)",
    "Murcia (Región de)", "Navarra (Comunidad Foral de)", "País Vasco", "Rioja (La)",
    "Ceuta y Melilla",
]

# Known spelling variants of CCAA header labels, mapped to the canonical label.
# Explicit on purpose: an unknown variant must fail the hierarchy check, not be
# silently misfiled as a province of the previous CCAA.
CCAA_HEADER_ALIASES = {
    "Navarra (Com. Foral de)": "Navarra (Comunidad Foral de)",   # 2015-2018 sheet only
}

# Single-province CCAAs: the CCAA row's value is the province value. Map the CCAA
# label to the province name used downstream. The parser *detects* these
# structurally and asserts the detected set equals this one.
SINGLE_PROVINCE_CCAA = {
    "Asturias (Principado de)": "Asturias",
    "Balears (Illes)": "Balears (Illes)",
    "Cantabria": "Cantabria",
    "Madrid (Comunidad de)": "Madrid",
    "Murcia (Región de)": "Murcia",
    "Navarra (Comunidad Foral de)": "Navarra",
    "Rioja (La)": "Rioja (La)",
}

# Independent reference: Spain's 50 provinces + 2 autonomous cities, grouped the
# way MIVAU groups them (MIVAU spelling). Used only to sanity-check the parse.
REFERENCE_TREE = {
    "Andalucía": ["Almería", "Cádiz", "Córdoba", "Granada", "Huelva", "Jaén", "Málaga", "Sevilla"],
    "Aragón": ["Huesca", "Teruel", "Zaragoza"],
    "Asturias (Principado de)": ["Asturias"],
    "Balears (Illes)": ["Balears (Illes)"],
    "Canarias": ["Palmas (Las)", "Santa Cruz de Tenerife"],
    "Cantabria": ["Cantabria"],
    "Castilla y León": ["Ávila", "Burgos", "León", "Palencia", "Salamanca", "Segovia",
                        "Soria", "Valladolid", "Zamora"],
    "Castilla-La Mancha": ["Albacete", "Ciudad Real", "Cuenca", "Guadalajara", "Toledo"],
    "Cataluña": ["Barcelona", "Girona", "Lleida", "Tarragona"],
    "Comunidad Valenciana": ["Alicante/Alacant", "Castellón/Castelló", "Valencia/València"],
    "Extremadura": ["Badajoz", "Cáceres"],
    "Galicia": ["Coruña (A)", "Lugo", "Ourense", "Pontevedra"],
    "Madrid (Comunidad de)": ["Madrid"],
    "Murcia (Región de)": ["Murcia"],
    "Navarra (Comunidad Foral de)": ["Navarra"],
    "País Vasco": ["Araba/Alava", "Gipuzkoa", "Bizkaia"],
    "Rioja (La)": ["Rioja (La)"],
    "Ceuta y Melilla": ["Ceuta", "Melilla"],
}


def norm_label(value) -> str:
    """Strip, collapse internal whitespace, drop the space MIVAU leaves before ')'."""
    s = re.sub(r"\s+", " ", str(value)).strip().replace(" )", ")")
    return CCAA_HEADER_ALIASES.get(s, s)


def column_periods(sheet) -> list[tuple[int, int, int]]:
    """Return (col_index, year, quarter) for every quarterly data column."""
    periods, year = [], None
    for c in range(LABEL_COL + 1, sheet.ncols):
        y = re.search(r"Año\s+(\d{4})", str(sheet.cell_value(YEAR_ROW, c)))
        if y:
            year = int(y.group(1))
        q = re.fullmatch(r"([1-4])º", str(sheet.cell_value(QUARTER_ROW, c)).strip())
        if q is None:          # "Trimestral" / "Anual" variation columns
            continue
        if year is None:
            sys.exit(f"[{sheet.name}] quarter column {c} has no year above it")
        periods.append((c, year, int(q.group(1))))
    return periods


def to_value(cell) -> tuple[float | None, str | None]:
    if isinstance(cell, float):
        return round(cell, 1), None      # source precision is 1 dp; strips float noise
    text = str(cell).strip()
    if text == "":
        return None, "no_data"
    if text.lower() == "n.r":
        return None, "not_representative"
    sys.exit(f"Unexpected cell value: {cell!r}")


def parse_sheet(sheet):
    """Walk rows top-to-bottom tracking current_ccaa. Returns (province_rows, ccaa_rows, tree)."""
    periods = column_periods(sheet)
    province_rows, ccaa_rows = [], []
    tree: dict[str, list[str]] = {}
    current_ccaa = None

    for r in range(FIRST_DATA_ROW, sheet.nrows):
        label = norm_label(sheet.cell_value(r, LABEL_COL))
        if label == "" or label.startswith(FOOTNOTE_PREFIX):
            break                               # end of data block
        values = [(y, q, *to_value(sheet.cell_value(r, c))) for c, y, q in periods]

        if label == NATIONAL_LABEL:
            ccaa_rows += [("national", label, y, q, v, f) for y, q, v, f in values]
        elif label in CCAA_HEADERS:
            current_ccaa = label
            tree[label] = []
            ccaa_rows += [("ccaa", label, y, q, v, f) for y, q, v, f in values]
        else:
            if current_ccaa is None:
                sys.exit(f"[{sheet.name}] province {label!r} before any CCAA header")
            tree[current_ccaa].append(label)
            province_rows += [(current_ccaa, label, y, q, v, f, sheet.name) for y, q, v, f in values]

    # Single-province CCAAs: header with no children -> its own row is the province row.
    for ccaa, children in tree.items():
        if not children:
            province = SINGLE_PROVINCE_CCAA.get(ccaa)
            if province is None:
                sys.exit(f"[{sheet.name}] {ccaa!r} has no provinces but is not a known single-province CCAA")
            children.append(province)
            province_rows += [(ccaa, province, y, q, v, f, sheet.name)
                              for _, _, y, q, v, f in (r for r in ccaa_rows if r[1] == ccaa)]
    return province_rows, ccaa_rows, tree, periods


def main():
    book = xlrd.open_workbook(SRC)
    print(f"{SRC.name}: {book.nsheets} sheets -> {book.sheet_names()}\n")
    if book.nsheets != 8:
        sys.exit("Expected 8 sheets")

    all_prov, all_ccaa, trees = [], [], []
    for sheet in book.sheets():
        prov, ccaa, tree, periods = parse_sheet(sheet)
        years = sorted({y for _, y, _ in periods})
        print(f"  [{sheet.name}] {len(periods)} quarter cols ({years[0]} Q1 .. {years[-1]} "
              f"Q{max(q for _, y, q in periods if y == years[-1])}), "
              f"{len(tree)} CCAA headers, {sum(map(len, tree.values()))} provinces")
        all_prov += prov
        all_ccaa += ccaa
        trees.append(tree)

    # every sheet must yield the identical hierarchy
    for name, t in zip(book.sheet_names(), trees):
        if t != trees[0]:
            sys.exit(f"Hierarchy on sheet [{name}] differs from sheet 1 - inspect before continuing:\n"
                     f"  only here: { {k: v for k, v in t.items() if trees[0].get(k) != v} }")
    tree = trees[0]

    # ---- the sanity-check print ---------------------------------------------
    n_prov = sum(map(len, tree.values()))
    print(f"\nReconstructed hierarchy (identical on all 8 sheets): "
          f"{len(tree)} CCAA headers -> {n_prov} provinces\n")
    for i, (ccaa, provinces) in enumerate(tree.items(), 1):
        tag = "  [single-province: CCAA row = province]" if ccaa in SINGLE_PROVINCE_CCAA else ""
        print(f"{i:>2}. {ccaa} ({len(provinces)}){tag}")
        for p in provinces:
            print(f"      - {p}")

    detected_single = {c for c, ps in tree.items() if ps == [SINGLE_PROVINCE_CCAA.get(c)]}
    checks = {
        "18 CCAA headers (17 CCAA + 'Ceuta y Melilla')": len(tree) == 18,
        "52 provinces (50 + Ceuta + Melilla)": n_prov == 52,
        "matches reference list of Spanish provinces exactly": tree == REFERENCE_TREE,
        "7 single-province CCAAs detected structurally": detected_single == set(SINGLE_PROVINCE_CCAA),
        "'Ceuta y Melilla' has exactly children Ceuta, Melilla": tree["Ceuta y Melilla"] == ["Ceuta", "Melilla"],
    }
    print("\nChecks:")
    for name, ok in checks.items():
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if not all(checks.values()):
        diff = {k: (tree.get(k), v) for k, v in REFERENCE_TREE.items() if tree.get(k) != v}
        sys.exit(f"Hierarchy check failed: {diff}")

    # ---- build outputs --------------------------------------------------------
    prov = pd.DataFrame(all_prov, columns=["ccaa", "province", "year", "quarter",
                                           "valor_m2", "value_flag", "source_sheet"])
    prov.insert(5, "is_single_province_ccaa", prov.ccaa.isin(SINGLE_PROVINCE_CCAA))
    ccaa = pd.DataFrame(all_ccaa, columns=["geo_level", "ccaa", "year", "quarter",
                                           "valor_m2", "value_flag"])

    assert not prov.duplicated(["province", "year", "quarter"]).any(), "duplicate province-quarter"
    assert not ccaa.duplicated(["ccaa", "year", "quarter"]).any(), "duplicate ccaa-quarter"
    n_periods = prov[["year", "quarter"]].drop_duplicates().shape[0]
    assert len(prov) == 52 * n_periods, (len(prov), n_periods)

    print(f"\nProvince table: {len(prov):,} rows = 52 provinces x {n_periods} quarters "
          f"({prov.year.min()} Q1 - {prov.year.max()} Q{prov[prov.year == prov.year.max()].quarter.max()})")
    print(f"  non-null valor_m2: {prov.valor_m2.notna().sum():,}")
    print("  NULLs by flag:")
    flagged = prov[prov.value_flag.notna()]
    for (flag, p), grp in flagged.groupby(["value_flag", "province"]):
        print(f"    {flag:<19} {p:<10} {len(grp):>3} quarters "
              f"({grp.year.min()} Q{grp[grp.year == grp.year.min()].quarter.min()} .. "
              f"{grp.year.max()} Q{grp[grp.year == grp.year.max()].quarter.max()})")
    print(f"CCAA/national published table: {len(ccaa):,} rows "
          f"({ccaa.ccaa.nunique()} geographies incl. TOTAL NACIONAL)")

    print("\nSpot checks (raw sheet values):")
    for p, y, q in [("Madrid", 2025, 4), ("Málaga", 2026, 2), ("Ceuta", 2004, 1), ("Melilla", 2013, 3)]:
        row = prov.query("province == @p and year == @y and quarter == @q").iloc[0]
        print(f"  {p:<8} {y} Q{q}: valor_m2={row.valor_m2}  flag={row.value_flag}  single={row.is_single_province_ccaa}")

    OUT_PROVINCE.parent.mkdir(parents=True, exist_ok=True)
    prov.to_parquet(OUT_PROVINCE, index=False)
    ccaa.to_parquet(OUT_CCAA, index=False)
    print(f"\nWrote {OUT_PROVINCE.relative_to(ROOT)} and {OUT_CCAA.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
