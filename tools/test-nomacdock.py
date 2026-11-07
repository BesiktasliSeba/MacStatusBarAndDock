#!/usr/bin/env python3
# test-nomacdock.py <plists|code> (from test-nomacdock.sh, run in the repo's root): the file names to look at on stdin; prints each place that
# shows "MacDock" to the user and exits 1 if there is one.
#  plists: every string under a key that is not an identifier (label, footerText, staticTextMessage, validTitles, title, ...).
#  code:   every string literal; one naming MacDock may be the line's name itself ("MacDock"), a file name or a path, or a log line's or a
#          focus-lock reason's (never shown).
import plistlib, re, subprocess, sys

IDS = {"lineName", "key", "id", "defaults", "PostNotification", "cell", "detail", "get", "set", "action", "bundle", "validValues",
       "Bundles", "Executables", "Classes", "Filter", "Label", "Program", "ProgramArguments", "MachServices", "CFBundleExecutable",
       "CFBundleIdentifier", "CFBundleName", "NSPrincipalClass", "requiredCapabilities", "isController"}
FILE_NAME = re.compile(r'[\w.+-]+\.(h|m|x|c|dylib|plist|disabled|txt|log)')
NOT_SHOWN = re.compile(r'\b(ELog|DMLog|NSLog|MSBDLog|NoticeLog|os_log\w*|fprintf|printf|syslog)\s*\(|[Ff]ocusLock|lockSel')


def plists(paths):
    bad = []

    def walk(v, path, key):
        if isinstance(v, dict):
            for k, x in v.items():
                walk(x, path, k)
        elif isinstance(v, list):
            for x in v:
                walk(x, path, key)
        elif isinstance(v, str) and "MacDock" in v and key not in IDS:
            bad.append("%s: %s = %r" % (path, key, v))

    for p in paths:   # (plutil reads the old text format too, as the filters' plists are)
        walk(plistlib.loads(subprocess.run(["plutil", "-convert", "xml1", "-o", "-", p], check=True, capture_output=True).stdout), p, None)
    return bad


def literals(text):
    # The string literals of C / Objective-C source with their line numbers, comments left out (// and /* */, which may span lines).
    out, i, n, line = [], 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1; i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            line += text.count("\n", i, j); i = j
        elif c == "'":
            j = i + 1
            while j < n and text[j] != "'" and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            i = j + 1
        elif c == '"':
            j, start = i + 1, line
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append((start, text[i + 1:j])); i = j + 1
        else:
            i += 1
    return out


def code(paths):
    bad = []
    for p in paths:
        with open(p, encoding="utf-8", errors="replace") as f:
            text = f.read()
        if "MacDock" not in text:
            continue
        lines = text.split("\n")
        for n, s in literals(text):
            if "MacDock" not in s:
                continue
            if s == "MacDock" or "/" in s or FILE_NAME.fullmatch(s):
                continue   # (the line's name, a file or a path)
            if NOT_SHOWN.search(lines[n - 1]):
                continue   # (a log line, a focus-lock reason)
            bad.append("%s:%d: %s" % (p, n, s))
    return bad


if __name__ == "__main__":
    files = sys.stdin.read().split()
    found = plists(files) if sys.argv[1] == "plists" else code(files)
    for b in found:
        print("    " + b)
    sys.exit(1 if found else 0)
