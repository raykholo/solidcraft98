#!/usr/bin/env python3
"""Convert a VB6 project (.vbp + .frm + .bas) into a twinBASIC source folder.

Usage: vb2tb.py <Project.vbp> <out-folder>

The output folder is what twinBASIC's documented `impexp` tool packs into a
.twinproj (`impexp.py import Project.twinproj <out-folder> --overwrite`),
which `twinBASIC.exe Project.twinproj --buildAndExit32` then compiles.

It does what the twinBASIC IDE's own VBP import does, with no GUI:
  * .bas modules are copied as they are;
  * each .frm becomes <name>.frm.tbform (the designer, as JSON) and
    <name>.frm.twin (the code, wrapped in a Class block);
  * form positions and sizes go from twips to pixels (/15);
  * MSCOMCTL.OCX's TreeView and ListView map to twinBASIC's built-in common
    controls, because the OCX isn't installed on modern Windows.
Stdlib only. GUIDs are derived from names, so the output is reproducible.
"""
import json
import os
import re
import shutil
import sys
import uuid

NS = uuid.UUID("5c1dc4a7-98a0-4c2f-a1e5-536f6c696443")

# VB6 intrinsic controls: twinBASIC keeps VB6's class ids.
VB_CLSID = {
    "Form": "{33AD4F38-6699-11CF-B70C-00AA0060D393}",
    "MDIForm": "{33AD4F70-6699-11CF-B70C-00AA0060D393}",
    "PictureBox": "{33AD4ED0-6699-11CF-B70C-00AA0060D393}",
    "Label": "{33AD4ED8-6699-11CF-B70C-00AA0060D393}",
    "TextBox": "{33AD4EE0-6699-11CF-B70C-00AA0060D393}",
    "Frame": "{33AD4EE8-6699-11CF-B70C-00AA0060D393}",
    "CommandButton": "{33AD4EF0-6699-11CF-B70C-00AA0060D393}",
    "CheckBox": "{33AD4EF8-6699-11CF-B70C-00AA0060D393}",
    "OptionButton": "{33AD4F00-6699-11CF-B70C-00AA0060D393}",
    "ComboBox": "{33AD4F08-6699-11CF-B70C-00AA0060D393}",
    "ListBox": "{33AD4F10-6699-11CF-B70C-00AA0060D393}",
    "HScrollBar": "{33AD4F18-6699-11CF-B70C-00AA0060D393}",
    "VScrollBar": "{33AD4F20-6699-11CF-B70C-00AA0060D393}",
    "Timer": "{33AD4F28-6699-11CF-B70C-00AA0060D393}",
    "Menu": "{33AD4F68-6699-11CF-B70C-00AA0060D393}",
    "Shape": "{33AD4F80-6699-11CF-B70C-00AA0060D393}",
    "Line": "{33AD4F88-6699-11CF-B70C-00AA0060D393}",
    "Image": "{33AD4F90-6699-11CF-B70C-00AA0060D393}",
}

# MSCOMCTL.OCX controls -> twinBASIC's own common controls package.
COMCTL_CLSID = {
    "TreeView": "{606188C0-9C81-493B-8BDE-02BD49B918C5}",
    "ListView": "{ED6464B0-4324-4E2E-8A17-83A81F9D48DD}",
    "ImageList": "{2F75D39C-A8E3-4D5E-844A-252BED31075B}",
}
COMCTL_OCX_GUID = "{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}"

TWIPS = {"Left", "Top", "Width", "Height", "X1", "X2", "Y1", "Y2"}
DOCK = {1: "vbDockTop", 2: "vbDockBottom", 3: "vbDockLeft", 4: "vbDockRight"}
DROP = {"_ExtentX", "_ExtentY", "_Version"}

REF_FORMS = {
    "hasBeenSplit": True,
    "id": "{F50B82D0-DCAB-43FE-9631-11959D4A4728}",
    "isCompilerPackage": True,
    "licence": "MIT",
    "name": "[COMPILER PACKAGE] twinBASIC - VB Compatibility Package (Forms)",
    "path32": "/Packages/WindowsControlsPackage",
    "path64": "/Packages/WindowsControlsPackage",
    "publisher": "TWINBASIC-COMPILER",
    "symbolId": "VB",
    "versionBuild": 0, "versionMajor": 0, "versionMinor": 0, "versionRevision": 31,
}
REF_STDOLE = {
    "id": "{00020430-0000-0000-C000-000000000046}",
    "lcid": 0,
    "name": "OLE Automation",
    "path32": "C:\\Windows\\SysWow64\\stdole2.tlb",
    "path64": "C:\\Windows\\System32\\stdole2.tlb",
    "symbolId": "stdole",
    "versionMajor": 2, "versionMinor": 0,
}
REF_COMCTL = {
    "id": "{D63CB78D-9F5B-42FE-B94C-A545F2B2BFC3}",
    "isCompilerPackage": True,
    "licence": "MIT",
    "name": "[COMPILER PACKAGE] twinBASIC - Common Controls Compatibility Package",
    "publisher": "TWINBASIC-COMPILER",
    "versionBuild": 0, "versionMajor": 0, "versionMinor": 0, "versionRevision": 1,
}


def guid(*parts):
    return "{" + str(uuid.uuid5(NS, "/".join(parts))).upper() + "}"


def read_text(path):
    with open(path, "rb") as f:
        return f.read().decode("cp1252").replace("\r\n", "\n").replace("\r", "\n")


def parse_value(raw):
    """A .frm property value -> Python value."""
    s = raw.strip()
    if s.startswith('"'):
        m = re.match(r'"((?:[^"]|"")*)"', s)
        return m.group(1).replace('""', '"')
    s = re.sub(r"\s+'.*$", "", s).strip()    # trailing  'comment
    m = re.fullmatch(r"&H([0-9A-Fa-f]+)&?", s)
    if m:
        v = int(m.group(1), 16) & 0xFFFFFFFF
        return v - 0x100000000 if v >= 0x80000000 else v
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d*\.\d+(E[+-]?\d+)?", s, re.I):
        return float(s)
    return s                                  # ^N, {F5}, $"x.frx":0000 ...


def parse_frm(path):
    """Returns (root node, code lines, set of OCX guids used)."""
    lines = read_text(path).split("\n")
    ocx = set()
    stack, root, i = [], None, 0
    while i < len(lines):
        ln = lines[i].strip()
        i += 1
        if not ln or ln.startswith("VERSION "):
            continue
        if ln.startswith("Object = "):
            m = re.search(r"\{[0-9A-Fa-f-]+\}", ln)
            if m:
                ocx.add(m.group(0).upper())
            continue
        m = re.match(r"Begin\s+(\w+)\.(\w+)\s+(\w+)", ln)
        if m:
            node = {"_lib": m.group(1), "_class": m.group(2), "Name": m.group(3), "_props": {}, "_kids": []}
            if stack:
                stack[-1]["_kids"].append(node)
            else:
                root = node
            stack.append(node)
            continue
        m = re.match(r"BeginProperty\s+(\w+)", ln)
        if m:
            group, depth = {}, 1
            while i < len(lines) and depth:
                g = lines[i].strip()
                i += 1
                if g.startswith("BeginProperty"):
                    depth += 1
                elif g.startswith("EndProperty"):
                    depth -= 1
                elif depth == 1 and "=" in g:
                    k, v = g.split("=", 1)
                    group[k.strip()] = parse_value(v)
            stack[-1]["_props"]["@" + m.group(1)] = group
            continue
        if ln == "End":
            stack.pop()
            if not stack:
                break
            continue
        if stack and "=" in ln:
            k, v = ln.split("=", 1)
            stack[-1]["_props"][k.strip()] = parse_value(v)
    code = lines[i:]
    while code and not code[-1].strip():
        code.pop()
    return root, code, ocx


def convert_props(node, is_root, dock_order):
    p = dict(node["_props"])
    out = {}
    font = p.pop("@Font", None)
    for k in list(p):
        if k.startswith("@"):
            p.pop(k)     # property groups other than Font (Panels, Buttons...) aren't used here
    for k, v in p.items():
        if k in DROP:
            continue
        if k in TWIPS and isinstance(v, (int, float)) and not is_root:
            v = round(v / 15)
        if k == "Align" and isinstance(v, int):
            if v in DOCK:
                out["Dock"] = DOCK[v]
                out["DockOrder"] = dock_order
            continue
        out[k] = v
    if font:
        out["FontName"] = font.get("Name", "MS Sans Serif")
        out["FontSize"] = font.get("Size", 8.25)
        out["FontCharset"] = font.get("Charset", 0)
        out["FontBold"] = font.get("Weight", 400) >= 700
        out["FontItalic"] = font.get("Italic", 0)
        out["FontUnderline"] = font.get("Underline", 0)
        out["FontStrikethru"] = font.get("Strikethrough", 0)
    out.setdefault("FontName", "MS Sans Serif")
    return out


def convert_control(node, dock_order, ocx_ok):
    lib, cls = node["_lib"], node["_class"]
    if lib == "VB":
        clsid = VB_CLSID.get(cls)
    elif lib == "MSComctlLib":
        clsid = COMCTL_CLSID.get(cls)
    else:
        clsid = None
    if not clsid:
        raise SystemExit(f"vb2tb: no twinBASIC mapping for {lib}.{cls} ({node['Name']})")
    out = convert_props(node, False, dock_order)
    out["_clsid"] = clsid
    out["_className"] = cls
    out["Name"] = node["Name"]
    kids = convert_children(node, ocx_ok)
    if kids:
        out["_children"] = kids
    return out


def convert_children(node, ocx_ok):
    kids, dock = [], 0
    for k in node["_kids"]:
        d = dock
        if isinstance(k["_props"].get("Align"), int) and k["_props"]["Align"] in DOCK:
            dock += 1
        kids.append(convert_control(k, d, ocx_ok))
    kids.reverse()       # the designer stores z-order back to front
    return kids


def convert_form(path, outdir):
    root, code, ocx = parse_frm(path)
    name = root["Name"]
    p = root["_props"]
    form = convert_props(root, True, 0)
    form["_clsid"] = VB_CLSID["MDIForm" if root["_class"] == "MDIForm" else "Form"]
    form["FormDesignerId"] = guid(name, "designer")
    form["Width"] = round(p.get("ClientWidth", 4800) / 15)
    form["Height"] = round(p.get("ClientHeight", 3600) / 15)
    form["Name"] = name
    if "StartUpPosition" in p:
        form["Top"] = round(p.get("ClientTop", 0) / 15)
        form["Left"] = round(p.get("ClientLeft", 0) / 15)
    else:
        form["StartUpPosition"] = "vbStartupWindowsDefault"
    kids = convert_children(root, True)
    if kids:
        form["_children"] = kids
    base = os.path.basename(path)
    with open(os.path.join(outdir, base + ".tbform"), "w", encoding="utf-8", newline="\r\n") as f:
        json.dump([form], f, indent="\t", ensure_ascii=False)
    twin = [
        f'[FormDesignerId("{form["FormDesignerId"][1:-1]}")]',
        f'[ClassId("{guid(name, "class")[1:-1]}")]',
        f'[InterfaceId("{guid(name, "iface")[1:-1]}")]',
        f'[EventInterfaceId("{guid(name, "events")[1:-1]}")]',
        f"Class {name}",
    ]
    twin += [("    " + ln) if ln.strip() else "" for ln in code]
    twin += ["", "End Class", ""]
    with open(os.path.join(outdir, base + ".twin"), "w", encoding="cp1252", newline="\r\n") as f:
        f.write("\n".join(twin))
    return name, ocx


def parse_vbp(path):
    items, props = [], {}
    for ln in read_text(path).split("\n"):
        if "=" not in ln:
            continue
        k, v = ln.split("=", 1)
        k, v = k.strip(), v.strip()
        if k in ("Form", "Module", "Class"):
            items.append((k, v.split(";")[-1].strip()))
        elif k == "Object":
            props.setdefault("_objects", []).append(v)
        else:
            props[k] = v.strip('"')
    return items, props


def main():
    vbp, outdir = sys.argv[1], sys.argv[2]
    srcdir = os.path.dirname(os.path.abspath(vbp))
    items, props = parse_vbp(vbp)
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    sources = os.path.join(outdir, "Sources")
    os.makedirs(sources)
    for d in ("Resources", "References", "Miscellaneous", "ImportedTypeLibraries", "Packages"):
        os.makedirs(os.path.join(outdir, d))

    uses_comctl = any(COMCTL_OCX_GUID in o.upper() for o in props.get("_objects", []))
    for kind, rel in items:
        src = os.path.join(srcdir, rel)
        if kind == "Form":
            name, ocx = convert_form(src, sources)
            uses_comctl |= COMCTL_OCX_GUID in ocx
            print(f"form    {rel} -> {name}")
        else:
            with open(os.path.join(sources, os.path.basename(rel)), "w", encoding="cp1252", newline="\r\n") as f:
                f.write(read_text(src))
            print(f"{kind.lower():7} {rel}")

    name = props.get("Name", "Project1")
    refs = [REF_FORMS, REF_STDOLE] + ([REF_COMCTL] if uses_comctl else [])
    settings = {
        "configuration.inherits": "Defaults",
        "project.id": guid(name, "project"),
        "project.name": name,
        "project.appTitle": props.get("Title", name),
        "project.description": props.get("VersionFileDescription", ""),
        "project.appHelpFile": props.get("HelpFile", ""),
        "project.buildType": "Standard EXE",
        "project.buildPath": "${SourcePath}\\Build\\" + props.get("ExeName32", name + ".exe"),
        "project.startupObject": props.get("Startup", "Sub Main"),
        "project.versionMajor": int(props.get("MajorVer", 1)),
        "project.versionMinor": int(props.get("MinorVer", 0)),
        "project.versionRevision": int(props.get("RevisionVer", 0)),
        "project.versionCompanyName": props.get("VersionCompanyName", ""),
        "project.versionFileDescription": props.get("VersionFileDescription", ""),
        "project.versionLegalCopyright": props.get("VersionLegalCopyright", ""),
        "project.versionProductName": props.get("VersionProductName", ""),
        "project.optionExplicit": False,
        "project.largeAddressAware": True,
        "project.forceDpiAwarenessAtStartup": "NONE",
        "project.references": refs,
        "project.warnings": {"errors": [], "ignored": []},
        "project.settingsVersion": 1,
        "runtime.useUnicodeStandardLibrary": True,
    }
    with open(os.path.join(outdir, "Settings"), "w", encoding="utf-8") as f:
        json.dump(settings, f, indent="\t")
    print(f"settings {name}, {len(refs)} references")


if __name__ == "__main__":
    main()
