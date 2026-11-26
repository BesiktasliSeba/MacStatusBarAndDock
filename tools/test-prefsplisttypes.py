#!/usr/bin/env python3
# test-prefsplisttypes.py <sources dir>... -- <plist>... (from test-prefsplisttypes.sh): every specifier in our settings pages' plists has
# each key in the type iPadOS's Preferences reads it as, and names classes and methods our pages have. Prints one line per problem and
# exits 1 if there is one.
#
# Why (1.8.9 RC 1, KT 26 Nov): MacLockScreen.plist's Name field had autoCaps as <integer>0</integer>. Settings reads autoCaps with
# +[PSSpecifier autoCapsTypeForString:], which sends it isEqualToString:, so opening Status Bar > Mac Lock Screen crashed Settings
# (NSInvalidArgumentException, -[__NSCFNumber isEqualToString:]).
#
# The types: the 1.8.9 RC 2 probe ran SpecifiersFromPlist (what a page's loadSpecifiersFromPlistName calls) on iPadOS 15.6.1, 16.7.7, 17.5.1
# and 18.5 with each key in the right type and in every other plist type. The same on all four:
#  - THROW_IF_NOT_STRING: any other type throws while the page loads (cell, get, set, detail, cellClass, autoCaps, keyboard, bestGuess,
#    action, confirmationAction, icon, bundle).
#  - an array or a dictionary for isIP / isURL / isNumeric / isDecimalPad / isEmail / isEmailAddressing throws (they are read by boolValue);
#  - validTitles, shortTitles and validValues must be arrays (else it throws), requiredCapabilities an array or a dictionary;
#  - autoCaps: only "sentences", "words" and "all" change anything ("None", and also "Sentences" or "Words", give no capitals);
#    keyboard: only "numbers" and "phone" ("Numbers" gives the plain keyboard).
# The other keys are read later (a cell's text, the preference read): a wrong type does not throw while loading, so they are held to the
# type their use needs here, on the Mac, before any iPad sees them.
import os
import plistlib
import re
import subprocess
import sys

THROW_IF_NOT_STRING = {"cell", "get", "set", "detail", "cellClass", "autoCaps", "keyboard", "bestGuess", "action", "confirmationAction",
                       "icon", "bundle"}
STRING = THROW_IF_NOT_STRING | {"label", "id", "key", "defaults", "PostNotification", "footerText", "headerText", "staticTextMessage",
                                "placeholder", "titlesDataSource", "valuesDataSource", "leftImage", "rightImage", "prompt", "okTitle",
                                "cancelTitle", "lineName", "msbGuardTitle"}
BOOL = {"noAutoCorrect", "isIP", "isURL", "isNumeric", "isDecimalPad", "isEmail", "isEmailAddressing", "showValue", "isSegmented", "negate",
        "enabled", "isController", "hasIcon", "isStaticText", "stockHides", "useSearchBar", "showIdentifiersAsSubtitle",
        "defaultApplicationSwitchValue", "hideSearchBarWhileScrolling"}
NUMBER = {"min", "max", "height", "alignment", "footerAlignment"}
STRING_LIST = {"validTitles", "shortTitles"}
OTHER = {"validValues", "requiredCapabilities", "sections", "default"}   # (checked below by their own rules)
KNOWN = STRING | BOOL | NUMBER | STRING_LIST | OTHER
AUTOCAPS = {"None", "sentences", "words", "all"}          # (the probe: "None" = no capitals, as any string but the three)
KEYBOARD = {"numbers", "phone"}
CELLS = {"PSGroupCell", "PSLinkCell", "PSLinkListCell", "PSListItemCell", "PSTitleValueCell", "PSSliderCell", "PSSwitchCell",
         "PSStaticTextCell", "PSEditTextCell", "PSSecureEditTextCell", "PSSegmentCell", "PSGiantIconCell", "PSGiantCell", "PSButtonCell",
         "PSEditTextViewCell", "PSSpinnerCell"}
SYSTEM_CLASSES = {"PSListItemsController", "PSListController", "PSSetupController", "PSDetailController", "PSViewController",
                  "PSTableCell", "PSSwitchTableCell", "PSSliderTableCell", "PSEditableTableCell",
                  "ATLApplicationListMultiSelectionController", "ATLApplicationListSelectionController",
                  "ATLApplicationListSubcontrollerController", "ATLApplicationListControllerBase"}   # (Preferences.framework, AltList)
SCALAR = (str, int, float, bool)


def sources(dirs):
    classes, sels = set(), set()
    for d in dirs:
        for root, _, files in os.walk(d):
            for f in files:
                if not f.endswith((".m", ".x", ".xm", ".h", ".mm")):
                    continue
                text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                classes |= set(re.findall(r"@implementation\s+(\w+)", text))
                for m in re.finditer(r"(?m)^[-+]\s*\([^)]*\)\s*([^{;]+)", text):
                    sig = m.group(1)
                    parts = re.findall(r"(\w+)\s*:", sig)
                    sels.add("".join(p + ":" for p in parts) if parts else sig.strip().split()[0])
    return classes, sels


def check(path, classes, sels, out):
    try:
        d = plistlib.loads(subprocess.run(["plutil", "-convert", "xml1", "-o", "-", path], check=True, capture_output=True).stdout)
    except Exception as e:
        out.append("%s: not a readable plist (%s)" % (path, e))
        return
    if not isinstance(d, dict) or not isinstance(d.get("items"), list):
        out.append("%s: no items array (not a settings page)" % path)
        return
    if "title" in d and not isinstance(d["title"], str):
        out.append("%s: title is %s, not a string" % (path, type(d["title"]).__name__))
    name = os.path.basename(path)
    for i, it in enumerate(d["items"]):
        where = "%s item %d (%s)" % (name, i, it.get("id") or it.get("label") or it.get("key") if isinstance(it, dict) else "?")
        if not isinstance(it, dict):
            out.append("%s: not a dictionary" % where)
            continue
        cell = it.get("cell")
        for k, v in it.items():
            t = type(v).__name__
            if k not in KNOWN:
                out.append("%s: key %s is not in this test's list: add it with the type Preferences reads it as" % (where, k))
            elif k in STRING and not isinstance(v, str):
                out.append("%s: %s is %s, not a string%s" % (where, k, t, " (Preferences throws while the page loads)" if k in THROW_IF_NOT_STRING else ""))
            elif k in BOOL and not isinstance(v, bool):
                out.append("%s: %s is %s, not <true/> / <false/>" % (where, k, t))
            elif k in NUMBER and (isinstance(v, bool) or not isinstance(v, (int, float))):
                out.append("%s: %s is %s, not a number" % (where, k, t))
            elif k in STRING_LIST and not (isinstance(v, list) and all(isinstance(x, str) for x in v)):
                out.append("%s: %s is not an array of strings" % (where, k))
        if not isinstance(cell, str) or cell not in CELLS:
            out.append("%s: cell %r is not one of Preferences' cell types" % (where, cell))
        if isinstance(it.get("autoCaps"), str) and it["autoCaps"] not in AUTOCAPS:
            out.append("%s: autoCaps %r is read as no capitals; write None, sentences, words or all" % (where, it["autoCaps"]))
        if isinstance(it.get("keyboard"), str) and it["keyboard"] not in KEYBOARD:
            out.append("%s: keyboard %r gives the plain keyboard; write numbers or phone, or leave it out" % (where, it["keyboard"]))
        vv, vt = it.get("validValues"), it.get("validTitles")
        if "validValues" in it and not (isinstance(vv, list) and all(isinstance(x, SCALAR) for x in vv)):
            out.append("%s: validValues is not an array of plain values" % where)
        if isinstance(vv, list) and isinstance(vt, list) and len(vv) != len(vt):
            out.append("%s: %d validValues but %d validTitles" % (where, len(vv), len(vt)))
        if isinstance(vv, list) and isinstance(it.get("shortTitles"), list) and len(it["shortTitles"]) != len(vv):
            out.append("%s: %d shortTitles for %d validValues" % (where, len(it["shortTitles"]), len(vv)))
        if cell in ("PSLinkListCell", "PSSegmentCell") and isinstance(vv, list) and "default" in it and it["default"] not in vv:
            out.append("%s: default %r is not one of its validValues" % (where, it["default"]))
        if "requiredCapabilities" in it and not isinstance(it["requiredCapabilities"], (list, dict)):
            out.append("%s: requiredCapabilities is not an array or a dictionary" % where)
        if "sections" in it and not (isinstance(it["sections"], list) and all(isinstance(x, dict) for x in it["sections"])):
            out.append("%s: sections is not an array of dictionaries" % where)
        dv = it.get("default")
        if "default" in it:
            if cell == "PSSwitchCell" and not isinstance(dv, bool):
                out.append("%s: a switch's default is %s, not <true/> / <false/>" % (where, type(dv).__name__))
            if cell == "PSSliderCell" and (isinstance(dv, bool) or not isinstance(dv, (int, float))):
                out.append("%s: a slider's default is %s, not a number" % (where, type(dv).__name__))
            if cell in ("PSEditTextCell", "PSSecureEditTextCell") and not isinstance(dv, str):
                out.append("%s: a text field's default is %s, not a string" % (where, type(dv).__name__))
        if cell == "PSSliderCell":
            lo, hi = it.get("min"), it.get("max")
            if not all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in (lo, hi)):
                out.append("%s: a slider needs min and max numbers" % where)
            elif not lo < hi or (isinstance(dv, (int, float)) and not isinstance(dv, bool) and not lo <= dv <= hi):
                out.append("%s: slider min %r, max %r, default %r out of order" % (where, lo, hi, dv))
        if it.get("key") is not None and not isinstance(it.get("defaults"), str) and cell not in ("PSGroupCell", "PSButtonCell") \
                and "get" not in it:
            out.append("%s: a key with no defaults domain and no getter" % where)
        for k in ("detail", "cellClass"):
            v = it.get(k)
            if isinstance(v, str) and v not in SYSTEM_CLASSES and v not in classes:
                out.append("%s: %s %s is no class of our pages (nor Preferences' / AltList's)" % (where, k, v))
        for k in ("action", "get", "set", "confirmationAction", "titlesDataSource", "valuesDataSource", "bestGuess"):
            v = it.get(k)
            if isinstance(v, str) and v not in sels:
                out.append("%s: %s %s is no method of our pages" % (where, k, v))


def code(paths):
    """Specifiers our code makes or changes: a literal number or bool set under a key that must be a string, or a literal string under a
    bool or number key (setProperty:@YES forKey:@"autoCaps" would throw as the plist did)."""
    out = []
    pat = re.compile(r'setProperty:\s*(@(?:YES|NO|-?\d[\d.]*|\(\s*-?\d[^)]*\)|"[^"]*"))\s+forKey:\s*@"(\w+)"')
    for p in paths:
        for n, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
            for m in pat.finditer(line):
                v, k = m.groups()
                if k in STRING and not v.startswith('@"'):
                    out.append("%s:%d: %s set to %s, not a string" % (p, n, k, v))
                elif (k in BOOL or k in NUMBER) and v.startswith('@"'):
                    out.append("%s:%d: %s set to the string %s" % (p, n, k, v))
    return out


def main():
    a = sys.argv[1:]
    if a and a[0] == "--code":
        out = code(a[1:])
        for line in out:
            print("    " + line)
        return 1 if out else 0
    cut = a.index("--")
    classes, sels = sources(a[:cut])
    out = []
    for p in a[cut + 1:]:
        check(p, classes, sels, out)
    for line in out:
        print("    " + line)
    return 1 if out else 0


if __name__ == "__main__":
    sys.exit(main())
