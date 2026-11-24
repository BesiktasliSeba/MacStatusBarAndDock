# scratch-root.sh: sourced by the Mac tests that run one of the package's shell scripts (layout/DEBIAN/preinst, postinst, prerm, postrm). The tests
# also run on the iPads' own test lanes, where /var/jb and /var/mobile are the owner's real files, so a script must never run with a real path in
# it. Before, each test moved /var/jb (and test-postrm two folders of /var/mobile) into its scratch folder with its own sed, and the postrm's purge
# still named the real sticky notes folder (/var/mobile/Library/Application Support/MacStatusBarAndDock).
# The scratch root stands for "/": EVERY absolute path where a shell word can begin with one (a line's start, after a space, an opening quote, =,
# :, (, a backquote, |, ;, &, {, a comma or >) goes under it, a bare "/" and a bare top folder too ("cd /", "T=/tmp"), quoted or not. Only /bin,
# /sbin and /dev stay (the shell's tools, 2>/dev/null), a URL's "//" and the #! line. Then the copy is checked, by rules of their own, to name
# nothing outside the root: no absolute path left; no top folder glued to an option, a word or a variable ("-C/var", "$X/var", "${X}/var": an
# empty X is the real one); no ~ (~mobile is mobile's real home), no $HOME, $TMPDIR, $PWD or $OLDPWD, no "cd" or "cd -" alone; no ".." part
# (it climbs out of the root); and nothing the copy would have turned from something else into a path (a / in $((...)), awk's '/^x/'): such a
# script is refused, never run changed. The root itself must be a plain absolute path (no "/" alone, no "." or ".." part, nothing the shell would
# split, glob or quote) in a folder of this user's own that no one else may enter (the test's mktemp folder). Nothing here reads the environment
# (1.8.8.4 review: a list narrowed from it weakened the copy). The four package scripts' copies are byte for byte what they were before.
# What no text check can see is a path the script builds from data at run time (decoded, read from a file); on an iPad's lane the tests run as
# uid nobody, which may not write the owner's files, and that is what stops such a path.
#   scratch_copy <script> <root> <copy>: the copy, executable; 0, or 1 with what is wrong on stdout (no copy left then).
#   scratch_left <copy> <root>: what a copy still names outside the root, one per line (nothing: none).
IFS= read -r -d '' SCRATCH_PL <<'PL' || true
use strict; use warnings;
my ($mode, $file, $root) = @ARGV;
my $end = qr{[\s"'`;)|&<>]};                             # (where a path ends)
my $kept = qr{(?:bin|sbin|dev)(?:/|\z|$end)};            # (/bin, /sbin, /dev: the tools, 2>/dev/null)
my $tops = qr{(?:var|private|tmp|usr|Library|System|Applications|etc|Users|opt|cores|Volumes|mnt|Developer|AppleInternal)};
# Does a path begin with the slash at $i of $s? At a line's start, or after a space, an opening quote, =, :, (, a backquote, |, ;, &, {, a comma or
# >. A quote right after a name, a } or a ) closes one ("$S"/.x: the rest of $S's path), so a slash after it goes on from there, as after ${X}.
sub starts {
    my ($s, $i) = @_;
    return 1 if $i == 0;
    my $c = substr($s, $i - 1, 1);
    return 0 unless $c =~ m{[\s"'=:(`|;&\{,>]};
    return !($c =~ /["']/ && $i >= 2 && substr($s, $i - 2, 1) =~ /[A-Za-z0-9_}\])]/);
}
sub url { my ($s, $i) = @_; $i >= 2 && substr($s, $i - 1, 1) eq ':' && substr($s, $i + 1, 1) eq '/' && substr($s, 0, $i - 1) =~ /[A-Za-z][A-Za-z0-9+.-]*\z/ }
sub moved { my ($s, $i) = @_; starts($s, $i) && !url($s, $i) && substr($s, $i + 1) !~ /\A$kept/ }   # (a path the copy puts under the root)
open(my $fh, '<', $file) or die "scratch-root: cannot read $file\n";
my %left; my $n = 0;
while (my $l = <$fh>) {
    $n++;
    if ($n == 1 && $l =~ /\A#!/) { print $l if $mode eq 'copy'; next; }   # (the #! line: an interpreter, never a file written)
    if ($mode eq 'copy') {
        my $o = $l;
        $l =~ s{/}{ moved($o, $-[0]) ? "$root/" : "/" }ge;
        print $l;
        next;
    }
    my $code = $l; $code =~ s{(?:\A|(?<=\s))#.*}{}s;        # (a comment is never run: the rules but the first read the code only)
    $left{"a .. part: $1"} = 1 while $code =~ m{(?:\A|[/\s"'=:(`|;&\{,>])(\.\.)(?=/|\z|$end)}g;
    $left{"a pattern, not a path, moved under the root: $1"} = 1 while $code =~ m{\Q$root\E(/[\^\\\[(?+|][^\s"'`;)|&<>]*)}g;   # (awk's '/^x/')
    $left{"a / in arithmetic (the copy would make it a path)"} = 1 if $code =~ m{\$\(\([^)]*/};
    s{\Q$root\E(?=/|\z|$end)[^\s"'`;)|&<>]*}{\x01}g for $l, $code;   # (under the root: fine as it is)
    while ($l =~ m{/}g) {                                     # (an absolute path, comments too: the copy moved every one)
        my $i = $-[0];
        next unless moved($l, $i);
        my ($path) = substr($l, $i) =~ m{\A([^\s"'`;)|&<>]*)};
        $left{$path} = 1;
    }
    while ($code =~ m{/$tops(?=/|\z|[^A-Za-z0-9_.-])}g) {   # (a top folder glued to an option, a word or a variable: "-C/var", "$X/var")
        my $i = $-[0];
        next if starts($code, $i);
        $left{"a top folder after something: " . substr($code, $i < 12 ? 0 : $i - 12, ($i < 12 ? $i : 12) + length($&))} = 1;
    }
    $left{"a home folder from ~: $1"} = 1 while $code =~ m{(?:\A|[\s"'=:(`|;&\{,>])(~[A-Za-z0-9_./-]*)}g;
    $left{"cd to the home or the last folder: $1"} = 1 while $code =~ m{(?:\A|[\s;&|(`])(cd(?:\s+-)?)\s*(?=\z|[;&|)`])}g;
    $left{"a folder from the environment: $1"} = 1 while $code =~ m{(\$\{?(?:HOME|TMPDIR|TMP|TEMP|PWD|OLDPWD|CFFIXED_USER_HOME)\b)}g;
}
print "$_\n" for sort keys %left;
PL
# (the root: an absolute path of plain names only, its folder a real one of this user's that no one else may enter; a "//" in it is "/", kept
#  as the test wrote it: its own paths compare with the copy's)
scratch_root_ok() {
    perl -e '
        my $r = $ARGV[0];
        print("not an absolute path of plain names: $r\n"), exit 1 unless $r =~ m{\A(?:/+[A-Za-z0-9_+\@%,.-]+)+\z};
        print("a . or .. part: $r\n"), exit 1 if grep { $_ eq "." || $_ eq ".." } split m{/+}, substr($r, 1);
        (my $p = $r) =~ s{/+[^/]+\z}{};
        my @s = lstat($p);
        print("its folder is not a real folder (a link, or nothing): $p\n"), exit 1 unless @s && -d _;
        print("its folder is not this user'"'"'s alone (mode 700): $p\n"), exit 1 unless $s[4] == $> && ($s[2] & 077) == 0;
        if (lstat($r)) { print("there already and not a folder: $r\n"), exit 1 unless -d _; }
        exit 0;' "$1"
}
scratch_left() {   # (its status: 0, or not 0 when the check itself could not run)
    local out
    out=$(perl -e "$SCRATCH_PL" left "$1" "$2") || return 2
    [ -z "$out" ] || printf '%s\n' "$out" | sort -u
}
scratch_copy() {
    local src="$1" root="$2" out="$3" left
    rm -f "$out"
    scratch_root_ok "$root" || return 1
    [ -f "$src" ] || { echo "no such script: $src"; return 1; }
    perl -e "$SCRATCH_PL" copy "$src" "$root" > "$out" || { rm -f "$out"; return 1; }
    chmod +x "$out"
    left=$(scratch_left "$out" "$root") || { echo "the check of the copy could not run"; rm -f "$out"; return 1; }
    [ -z "$left" ] && return 0
    printf '%s\n' "$left"; rm -f "$out"; return 1
}
