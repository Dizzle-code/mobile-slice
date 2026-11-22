#!/usr/bin/env python3
"""Resolve OrcaSlicer vendor profiles ("inherits"/"include") into standalone JSON files plus catalog.json."""
import argparse
import json
from pathlib import Path

META_KEYS = {"inherits", "include", "instantiation"}


def index_profiles(vendor_dir: Path, kind: str) -> dict:
    profiles = {}
    for path in sorted((vendor_dir / kind).rglob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        name = data.get("name")
        if not name:
            continue
        if name in profiles:
            raise SystemExit(f"Doppelter Profilname in {kind}: {name}")
        profiles[name] = data
    return profiles


def resolve(profiles: dict, name: str, chain=()) -> dict:
    if name in chain:
        raise SystemExit(f"Zyklische Vererbung: {' -> '.join(chain + (name,))}")
    if name not in profiles:
        raise SystemExit(f"Profil nicht gefunden: {name}")
    own = profiles[name]
    merged = {}
    parents = [own["inherits"]] if own.get("inherits") else []
    includes = own.get("include") or []
    for parent in parents + list(includes):
        merged.update(resolve(profiles, parent, chain + (name,)))
    merged.update({k: v for k, v in own.items() if k not in META_KEYS})
    return merged


def first(value):
    return value[0] if isinstance(value, list) and value else value


def number(value):
    value = first(value)
    if isinstance(value, str):
        value = value.rstrip("%")
    return float(value)


def flatten(profiles: dict, name: str, printer: str, kind: str) -> dict:
    profile = resolve(profiles, name)
    profile["name"] = name
    profile["from"] = "system"
    profile["inherits"] = ""
    compatible = profile.get("compatible_printers")
    if kind != "printer" and compatible and printer not in compatible:
        raise SystemExit(f"{name} ist nicht mit {printer} kompatibel")
    return profile


def write(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vendor_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--selection", type=Path, required=True)
    args = parser.parse_args()
    selection = json.loads(args.selection.read_text(encoding="utf-8"))
    printer_name = selection["printer"]

    out = args.output_dir
    for stale in ("process.json", "filament.json"):
        (out / stale).unlink(missing_ok=True)
    for folder in ("process", "filament"):
        for old in (out / folder).glob("*.json") if (out / folder).is_dir() else []:
            old.unlink()

    machines = index_profiles(args.vendor_dir, "machine")
    printer = flatten(machines, printer_name, printer_name, "printer")
    write(out / "printer.json", printer)
    model_id = ""
    for path in (args.vendor_dir / "machine").glob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("type") == "machine_model" and data.get("name") == printer.get("printer_model"):
            model_id = data.get("model_id", "")
    if not model_id:
        raise SystemExit(f"model_id für {printer.get('printer_model')} nicht gefunden")
    xs = [float(p.split("x")[0]) for p in printer["printable_area"]]
    ys = [float(p.split("x")[1]) for p in printer["printable_area"]]
    catalog = {
        "printer": {
            "name": printer_name,
            "model": printer.get("printer_model"),
            "modelId": model_id,
            "nozzle": number(printer["nozzle_diameter"]),
            "bed": [max(xs) - min(xs), max(ys) - min(ys)],
            "height": number(printer["printable_height"]),
            "file": "printer.json",
        },
        "defaultProcess": selection["defaultProcess"],
        "defaultFilament": selection["defaultFilament"],
        "processes": [],
        "filaments": [],
    }

    processes = index_profiles(args.vendor_dir, "process")
    for entry in selection["processes"]:
        profile = flatten(processes, entry["name"], printer_name, "process")
        file = f"process/{entry['id']}.json"
        write(out / file, profile)
        catalog["processes"].append({
            "id": entry["id"], "label": entry["label"], "name": entry["name"], "file": file,
            "layerHeight": number(profile["layer_height"]),
            "infill": number(profile.get("sparse_infill_density", "15%")),
            "walls": int(number(profile.get("wall_loops", "2"))),
        })

    filaments = index_profiles(args.vendor_dir, "filament")
    for entry in selection["filaments"]:
        profile = flatten(filaments, entry["name"], printer_name, "filament")
        file = f"filament/{entry['id']}.json"
        write(out / file, profile)
        catalog["filaments"].append({
            "id": entry["id"], "label": entry["label"], "name": entry["name"], "file": file,
            "type": first(profile.get("filament_type", "PLA")),
            "vendor": first(profile.get("filament_vendor", "Generic")),
            "color": first(profile.get("default_filament_colour") or profile.get("filament_colour") or "#FFFFFF") or "#FFFFFF",
            "density": number(profile.get("filament_density", "1.24")),
            "nozzleTemp": int(number(profile.get("nozzle_temperature", "220"))),
            "bedTemp": int(number(profile.get("textured_plate_temp", profile.get("hot_plate_temp", "60")))),
        })

    write(out / "catalog.json", catalog)
    print(f"Drucker {printer_name} ({model_id}), {len(catalog['processes'])} Prozesse, "
          f"{len(catalog['filaments'])} Filamente -> {out}")


if __name__ == "__main__":
    main()
