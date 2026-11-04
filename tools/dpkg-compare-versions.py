# dpkg-compare-versions.py <a> <op> <b>: "dpkg --compare-versions" for the Mac tests of the package scripts (test-prerm.sh, test-postinst.sh: no
# dpkg on this Mac). dpkg's own order (lib/dpkg/version.c: the epoch, then verrevcmp of the version and of the revision; "~" sorts before
# everything, even the end): exit 0 when "a op b" holds, 1 when not. An empty version is earlier than any other (lt le eq ne ge gt), as in dpkg.
import sys


def order(c):
    if c.isdigit():
        return 0
    if c.isalpha():
        return ord(c)
    if c == '~':
        return -1
    return ord(c) + 256 if c else 0


def verrevcmp(a, b):
    i = j = 0
    while i < len(a) or j < len(b):
        first_diff = 0
        while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
            ac = order(a[i]) if i < len(a) else 0
            bc = order(b[j]) if j < len(b) else 0
            if ac != bc:
                return ac - bc
            i += 1
            j += 1
        while i < len(a) and a[i] == '0':
            i += 1
        while j < len(b) and b[j] == '0':
            j += 1
        while i < len(a) and a[i].isdigit() and j < len(b) and b[j].isdigit():
            if not first_diff:
                first_diff = ord(a[i]) - ord(b[j])
            i += 1
            j += 1
        if i < len(a) and a[i].isdigit():
            return 1
        if j < len(b) and b[j].isdigit():
            return -1
        if first_diff:
            return first_diff
    return 0


def parse(v):
    epoch, rest = (v.split(':', 1) if ':' in v else ('0', v))
    version, revision = (rest.rsplit('-', 1) if '-' in rest else (rest, ''))
    return int(epoch or 0), version, revision


def compare(a, b):
    if not a or not b:
        return (0 if a == b else -1 if not a else 1)
    ea, va, ra = parse(a)
    eb, vb, rb = parse(b)
    if ea != eb:
        return ea - eb
    return verrevcmp(va, vb) or verrevcmp(ra, rb)


def main(argv):
    if len(argv) != 4:
        print('usage: dpkg-compare-versions.py <a> <op> <b>', file=sys.stderr)
        return 2
    a, op, b = argv[1], argv[2], argv[3]
    c = compare(a, b)
    ops = {'lt': c < 0, 'le': c <= 0, 'eq': c == 0, 'ne': c != 0, 'ge': c >= 0, 'gt': c > 0}
    if op not in ops:
        print('unknown op %s' % op, file=sys.stderr)
        return 2
    return 0 if ops[op] else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
