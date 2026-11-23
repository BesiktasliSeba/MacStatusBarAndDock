#!/bin/bash
# test-recentstrip.sh: the recent windows strip (1.8.8.2 F29, KT 20 Nov: "it can be like on macos"). Part 1: its rules (common/RecentStripRule.h:
# the order and the swap, the cap, when it shows and steps aside, the reveal, the place on every iPad size and Dock side, the cover, the pointer, the
# pictures' size and when one is due, the iPadOS) run on the Mac, see test-recentstrip.m. Part 2: site checks in SpringBoard's part
# (statusbar/RecentStrip.h), StatusBar.x, Settings and the crash map. Part 3: made-to-fail copies of the rules, each must be caught.
cd "$(dirname "$0")" || exit 1
TOOLS=$(pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rc=0
R=../common/RecentStripRule.h; H=../statusbar/RecentStrip.h; S=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/MSBRootListController.m
PL=../statusbar/macstatusbarprefs/Resources/Windows.plist; O=../common/OwnPageRows.h; C=crashmap-rules.txt
[ -f "$R" ] && [ -f "$H" ] || { echo "FAIL  no recent windows strip: $R or $H is missing"; exit 1; }

echo "== the rules (test-recentstrip.m)"
clang -fobjc-arc -Wall -Werror -framework Foundation -o "$W/t" test-recentstrip.m || { echo "FAIL  test-recentstrip.m does not build"; exit 1; }
"$W/t" || rc=1

echo "== site checks"
ck() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; rc=1; fi; }
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
fn "$S" 'static void DMSyncWindowsForLibraryBody(void) {' > "$W/watcher"
fn "$H" 'static void DMRStripTick(void) {' > "$W/tick"
fn "$H" 'static BOOL DMRStripOn(void) {' > "$W/on"
fn "$S" 'static void DMMinimizeWindow(UIView *window) {' > "$W/minw"
fn "$S" 'static void DMMinimizeStage(UIView *stage) {' > "$W/mins"
fn "$H" 'static void DMRStripPick(DMRStripCard *card) {' > "$W/pick"
fn "$H" 'static void DMRStripPicture(UIView *stage, NSString *b, NSString *why) {' > "$W/pic"
fn "$H" 'static BOOL DMRStripPictureAsync(UIView *v, double k, void (^done)(UIView *pic, double ms)) {' > "$W/async"
fn "$H" 'static void DMRStripSysHoverUpdate(BOOL want) {' > "$W/hover"
fn "$H" 'static UIView *DMRStripWindowHit(id self, SEL _cmd, CGPoint p, UIEvent *e) {' > "$W/hit"
ck "the strip's step rides the 0.2 s window watcher, right after the window cards' (no timer of its own)" \
   "grep -A1 -F 'DM_PERF(\"wincards\", DMWinCardsTick());' \"$W/watcher\" | grep -qF 'DM_PERF(\"rstrip\", DMRStripTick());'"
ck "  ... and returns at once while it is off, or while no window exists" \
   "head -6 \"$W/tick\" | grep -qF 'if (!DMRStripOn()) {' && grep -qF 'if (!DMWindowWorkNeeded()) { DMRStripShowAs(MSBDRStripHidden, @\"no window\"); DMRStripSysHoverUpdate(NO); return; }' \"$W/tick\""
ck "no timer, display link, timed dispatch or poll in the strip (no new polling)" \
   "! grep -nE 'NSTimer|CADisplayLink|dispatch_source_create|dispatch_after|afterDelay|globalPointerPosition|BKSMousePointerService' $H $R"
ck "no portal: still pictures only (a portal has the server draw the window in every frame)" "! grep -nE '_UIPortalView|DMMSWPortal' $H"
ck "it runs for Aerial, Zetsu and MilkyWay4 only, on the rules' iPadOS, with the pictures that need no waiting" \
   "grep -qF 'if (e != DMEngineAerial && e != DMEngineZetsu && e != DMEngineMilkyWay) return NO;' \"$W/on\" && grep -qF 'os = MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion) ? 1 : 0;' \"$W/on\" \
    && grep -qF 'return os && DMMSWAsyncPicturesOK();' \"$W/on\" && grep -qF 'if (!gRStripPref || gStockBar) return NO;' \"$W/on\""
ck "the order is the rules' step, with the pick" "grep -qF 'MSBDRStripOrderStep(gRStripOrder, was, front, gRStripPicked, present);' \"$W/tick\" && grep -qF 'if (gRStripPicked && now - gRStripPickedAt > 1.5) gRStripPicked = nil;' \"$W/tick\""
ck "when it shows is the rules' answer, the reveal's too" "grep -qF 'MSBDRStripShow show = MSBDRStripShowFor(s);' \"$W/tick\" && grep -qF 'gRStripMayRevealNow = MSBDRStripMayReveal(s);' \"$W/tick\" \
   && grep -qF 'MSBDRStripState s = { 1, (int)items.count, calm, windowsFront, anyShown, covered, gRStripReveal != 0 };' \"$W/tick\""
ck "nothing laid out or measured while it cannot show (one window, something over the windows, the windows behind a full-screen app)" \
   "grep -qF 'BOOL calm = gRStripOrder.count && DMRStripCalm();' \"$W/tick\" && grep -qF 'if (calm && windowsFront && gRStripOrder.count) {' \"$W/tick\" && grep -qF 'if (covered || !items.count) break;' \"$W/tick\""
ck "  ... the windows in front as DMWindowsInFront reads them, a full-screen app behind them covers the edge, every window and Finder's are tested against the cards" \
   "grep -qF 'BOOL windowsFront = calm && DMDesiredWindowLevel() > 10.0;' \"$W/tick\" && grep -qF 'BOOL covered = items.count && DMFrontApp() != nil && DMFullScreenAppInFront();' \"$W/tick\" \
    && grep -qF 'if (MSBDRStripCovers(gRStripSpan, DMRStripRectOf([st convertRect:st.bounds toCoordinateSpace:scr]))) covered = YES;' \"$W/tick\" && grep -qF 'for (DMNativeWindow *nw in gNativeWindows)' \"$W/tick\""
ck "  ... calm: no App Switcher, Mac Switcher, lock, App Library, folder or icon menu fade, Dock menu, keyboard, Guided Access, Spotlight, Notification Center" \
   "fn $H 'static BOOL DMRStripCalm(void) {' > \"$W/calm\" && grep -qF 'if (!DMScreenOnAndUnlocked() || DMSwitcherVisible() || gMSWOpen || gMSWClosing || !DMMSWSessionIdle()) return NO;' \"$W/calm\" \
    && grep -qF 'if (gWindowsHiddenForLibrary || gHomeMenuOpen || gDockMenuOpen || gSoftKeyboardH >= 100.0) return NO;' \"$W/calm\" \
    && grep -qF 'if (MSBDGuidedAccessActive() || DMLibraryVisible() || DMSpotlightShown() || DMCoverSheetShown()) return NO;' \"$W/calm\""
ck "the place, the count and the side are the rules'" "grep -qF 'n = MSBDRStripLayout(sc.width, sc.height, usable, gRStripRight, n, aspect, &gRStripBand, cards);' $H \
   && grep -qF 'gRStripRight = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);' \"$W/tick\" && grep -qF 'items = MSBDRStripItems(gRStripOrder, (NSUInteger)MSBDRStripFit(sc.width, sc.height, usable));' \"$W/tick\" \
   && grep -qF 'MSBDRRect usable = DMRStripRectOf(u);' \"$W/tick\" && grep -qF '{ u = DMUsableArea(); uFor = sc; uDock = gDMDockGen; uPlace = gDMDockPlaceGen; uAt = now; }' \"$W/tick\""
ck "its window just above the windows' level, and only a card takes a touch" \
   "grep -qF 'CGFloat level = DMDesiredWindowLevel() + 0.5;' \"$W/tick\" && grep -qF 'class_addMethod(sub, @selector(hitTest:withEvent:), (IMP)DMRStripWindowHit, \"@@:{CGPoint=dd}@\");' $H \
    && grep -qF 'if ([c pointInside:q withEvent:e]) return c;' \"$W/hit\" && [ \"\$(grep -c 'return' \"$W/hit\")\" = 3 ]"
fn "$H" 'static void DMRStripTurnIn(void) {' > "$W/turn"
fn "$H" 'static void DMRStripShowAs(MSBDRStripShow show, NSString *why) {' > "$W/show"
ck "the turn and the step aside are two views: the root's transform is the turn alone (DMRStripTurnIn), the slide in it steps aside and back (DMRStripShowAs), the cards live in the slide" \
   "grep -qF 'root.transform = turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity;' \"$W/turn\" && grep -qF 'slide.bounds = CGRectMake(0, 0, want.size.width, want.size.height);' \"$W/turn\" \
    && ! grep -qE 'slide\.(transform|alpha) =' \"$W/turn\" && grep -qF 'slide.transform = DMRStripAway();' \"$W/show\" && grep -qF 'slide.transform = CGAffineTransformIdentity; slide.alpha = 1.0;' \"$W/show\" \
    && ! grep -qE 'root\.|gRStripRoot' \"$W/show\" && [ \"\$(grep -cE 'root\.transform =' $H)\" = \"\$(grep -cE 'root\.transform =' \"$W/turn\")\" ] \
    && [ \"\$(grep -cE 'slide\.transform =' $H)\" = \"\$(grep -cE 'slide\.transform =' \"$W/show\")\" ] \
    && grep -qF '[gRStripSlide addSubview:c];' $H && ! grep -qF '[gRStripRoot addSubview:c]' $H"
ck "a pick is a Dock tap's way (shown again if minimized, the engine's own raise), then the swap at once" \
   "grep -qF 'if (!DMSurfaceWindowForApp(b)) DMRaiseStageForBundle(b);' \"$W/pick\" && grep -qF 'gRStripPicked = [b copy]; gRStripPickedAt = CACurrentMediaTime();' \"$W/pick\" \
    && grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{ DMRStripTick(); });' \"$W/pick\""
ck "pictures at the card's size, from the background queue (the Mac Switcher's request, the scale in its transform)" \
   "grep -qF 'double k = MSBDRStripPicScale(bb.size.width, bb.size.height, MSBDRStripCardW(sc.width, sc.height), MSBDRStripCardH(sc.width, sc.height));' \"$W/pic\" \
    && grep -qF 'double s = [UIScreen mainScreen].scale * k;' \"$W/async\" && grep -qF 'dispatch_async(DMMSWPicQueue(), ^{' \"$W/async\" && grep -qF 'ok = gMSWSnapFn(MACH_PORT_NULL, opts);' \"$W/async\" \
    && grep -qF 'opts[gMSWSnapKeyMode] = gMSWSnapModeLayer;' \"$W/async\" && ! grep -q 'snapshotViewAfterScreenUpdates' $H"
ck "  ... the one that left the front once SpringBoard is calm (the window cards' rule), still on screen, never the one in front" \
   "grep -qF 'BOOL calmForPic = !DMSwitcherVisible() && !gMSWOpen && !gMSWClosing && DMMSWSessionIdle() && !DMWinCardBusy();' \"$W/tick\" \
    && grep -qF 'if (DMRStripStageOnScreen(st) && ![b isEqualToString:front]) DMRStripPicture(st, b, @\"it left the front\");' \"$W/tick\" && grep -qF 'gRStripPicDue[was] = @(now + 0.6);' \"$W/tick\""
ck "  ... before every minimize of ours, before its animation (all three engines' minimize)" \
   "grep -B1 -F 'objc_setAssociatedObject(window, kMinimizedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/minw\" | grep -qF 'DMRStripWillMinimize(window);' \
    && grep -B1 -F 'objc_setAssociatedObject(stage, kStageHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/mins\" | grep -qF 'DMRStripWillMinimize(stage);' \
    && fn $H 'static void DMRStripWillMinimize(UIView *stage) {' | grep -qF 'if (!MSBDRStripPicAtMinimize(gRStripPics[b] != nil, at ? CACurrentMediaTime() - at.doubleValue : 1e9, [b isEqualToString:gRStripFront])) return;'"
ck "  ... as the strip shows, one per tick, by the rules' due" "grep -qF 'if (on && MSBDRStripPicDue(gRStripPics[b] != nil, at ? now - at.doubleValue : 1e9, on) && ![gRStripPicAsking containsObject:b]) { DMRStripPicture(st, b, @\"the strip shows\"); break; }' \"$W/tick\""
ck "the pointer: a hover recognizer that only watches (PointerRegion.h's), on the iPad's system gestures window, only while wanted" \
   "grep -qF 'UIHoverGestureRecognizer *h = [[DMPtrHoverRecognizer alloc] initWithTarget:[DMRStripTarget shared] action:@selector(sysHover:)];' \"$W/hover\" \
    && grep -qF 'h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;' \"$W/hover\" && grep -qF 'if (x.screen != [UIScreen mainScreen] || ![NSStringFromClass([x class]) isEqualToString:@\"_UISystemGestureWindow\"]) continue;' \"$W/hover\" \
    && grep -qF 'DMRStripSysHoverUpdate(gDMPointerAttached && (gRStripMayRevealNow || gRStripReveal == 1));' \"$W/tick\" && grep -qF '@interface DMPtrHoverRecognizer : UIHoverGestureRecognizer' ../statusbar/PointerRegion.h"
ck "  ... the edge and the leaving are the rules'" "fn $H 'static void DMRStripSysHoverSeen(UIHoverGestureRecognizer *g) {' > \"$W/seen\" && grep -qF 'if (!gRStripMayRevealNow || !MSBDRStripPointerAtEdge(p.x, s.bounds.size.width, gRStripRight)) return;' \"$W/seen\" \
   && grep -qF 'if (MSBDRStripPointerLeft(p.x, gRStripBand, gRStripRight)) { if (!gRStripPointerOutAt) gRStripPointerOutAt = now; }' \"$W/seen\""
ck "Window > Show Recent Windows with Aerial, Zetsu and MilkyWay4 (the engines' branch of the menu), only while the strip stepped aside with something in it" \
   "fn $S 'static void DMOpenWindowMenu(UIButton *btn) {' > \"$W/menu\"; awk '/if \\(DMActiveEngine\\(\\) != DMEngineNone\\) \\{   \\/\\/ \"Open Apps as Windows\"/,/\\} else if \\(DMSMEngine\\(\\)\\) \\{/' \"$W/menu\" \
    | grep -qF 'if (DMRStripMenuOffered()) [items addObject:[[DMRow alloc] initWithTitle:@\"Show Recent Windows\" enabled:YES handler:DMCloseThen(^{ DMRStripMenuReveal(); })]];' \
    && grep -qF 'static BOOL DMRStripMenuOffered(void) { return DMRStripOn() && gRStripMayRevealNow && gRStripItems.count > 0; }' $H"
ck "the switch: recentStrip, on unless switched off, a boolean only, read with the preferences" \
   "grep -qF 'CFPropertyListRef rs = CFPreferencesCopyValue(CFSTR(\"recentStrip\"), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
    && grep -qF 'BOOL recentStrip = !(rs && CFGetTypeID(rs) == CFBooleanGetTypeID() && !CFBooleanGetValue(rs));' $S && grep -qF 'gRStripPref = recentStrip;' $S \
    && grep -qF 'static BOOL gRStripPref = YES; ' $H"
ck "  ... one default in all four places, on: SpringBoard before and after reading the preferences, the Settings row and the crash guard's target" \
   "python3 -I -c 'import re,sys,plistlib
h=open(\"$H\").read(); s=open(\"$S\").read(); c=open(\"$C\").read()
it=plistlib.load(open(\"$PL\",\"rb\"))[\"items\"]; row=[x for x in it if x.get(\"key\")==\"recentStrip\"]
a=re.findall(r\"^static BOOL gRStripPref = (YES|NO);\", h, re.M)
b=re.findall(r\"BOOL recentStrip = (.*);\", s)
t=re.findall(r\"^target recentStrip pref com.besiktasliseba.macstatusbar recentStrip 0 ([01]) \", c, re.M)
ok = a==[\"YES\"] and len(b)==1 and b[0].startswith(\"!(\") and \"!CFBooleanGetValue(rs)\" in b[0] and len(row)==1 and row[0][\"default\"] is True and t==[\"1\"]
sys.exit(0 if ok else 1)'"
ck "the include: after the window cards (their calm check, the Mac Switcher's pictures)" \
   "grep -A1 -F '#include \"WindowCards.h\"' $S | grep -qF '#include \"RecentStrip.h\"' && grep -qF '#include \"../common/RecentStripRule.h\"' $H"
ck "Settings: Recent Windows Strip right after Recent Apps with Left-Edge Swipe in the Mac Switcher's group, on by default, its sentence in the footer and the page's words" \
   "plutil -convert json -o - $PL | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; ids=[x.get(\"id\") for x in it]; i=ids.index(\"RECENT_STRIP\"); s=it[i]
g=[x for x in it[:i] if x.get(\"cell\")==\"PSGroupCell\"][-1]
f=g[\"footerText\"]
ok = ids[i-1]==\"STRIP_SWIPE\" and s[\"key\"]==\"recentStrip\" and s[\"default\"] is True and s[\"cell\"]==\"PSSwitchCell\" and s[\"label\"]==\"Recent Windows Strip\" and g.get(\"id\")==\"MSW_GROUP\"
p=[x for x in f.split(\"\\n\\n\") if x.startswith(\"Recent Windows Strip:\")]
w=open(\"$P\").read()
ok = ok and len(p)==1 and (\"@\\\"recentStrip\\\": @\\\"\" + p[0] + \"\\\",\") in w and all(c not in f for c in \"\\u2014\\u2013\")
sys.exit(0 if ok else 1)'"
ck "  ... shown only with a working Aerial, Zetsu or MilkyWay4 on the rules' iPadOS, on the page and in the search" \
   "grep -qF 'if ([ident isEqualToString:kMSBDRecentStripRowID] && (!s.engineWorks || s.stageManagerEngine || !s.recentStripOS)) return YES;' $O \
    && grep -qF '    s.recentStripOS = MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion);' ../common/OwnPageState.h \
    && ! grep -n 'kMSBDRecentStripRowID' $O | grep -q 'NSProcessInfo' \
    && grep -qF '#define kMSBDRecentStripRowID @\"RECENT_STRIP\"' $O && grep -qF '#include \"RecentStripRule.h\"' $O \
    && grep -qF 'if ([sp.identifier isEqualToString:kMSBDRecentStripRowID]) continue;   // (Recent Windows Strip: the engines' $P \
    && grep -qF 'if (sm || !MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion)) {' $P \
    && grep -qF 'for (PSSpecifier *sp in _specifiers) if (![sp.identifier isEqualToString:kMSBDRecentStripRowID]) [kept addObject:sp];' $P"
ck "the crash guard: its own switch, the whole strip and its rules (a crash there turns the strip off, nothing else)" \
   "grep -qxF 'target recentStrip pref com.besiktasliseba.macstatusbar recentStrip 0 1 Recent Windows Strip|the recent windows strip' $C \
    && grep -qxF 'file MacStatusBarCore ^RecentStrip(Rule)?\\.h\$ recentStrip' $C \\
    && grep -qxF 'sym MacStatusBarCore ([-+]\\[DMRStrip(Card|Target)\\s|^_*DMRStrip[A-Z]|^_*MSBDR(Strip|ecentStrip|MaxX|MaxY)) recentStrip' $C"
ck "  ... no section of the strip's files names a section rule (they would take its functions first)" \
   "python3 -I -c 'import re,sys
rules=[re.compile(l.split()[2]) for l in open(\"$C\") if l.startswith(\"sec MacStatusBarCore \")]
heads=[l.rstrip() for f in (\"$H\",\"$R\") for l in open(f) if re.match(r\"^(//\\s*(=|-){3,}|%group)\", l)]
sys.exit(1 if any(r.search(h) for r in rules for h in heads) else 0)'"
ck "  ... and no name rule of another target matches a function of the strip" \
   "python3 -I -c 'import re,sys
rules=[(re.compile(l.split()[2]), l.split()[3]) for l in open(\"$C\") if l.startswith(\"sym MacStatusBarCore \") and l.split()[3] != \"recentStrip\"]
names=set(re.findall(r\"^static [^(]*?\\b(DMRStrip\\w+|MSBDR\\w+)\\(\", open(\"$H\").read()+open(\"$R\").read(), re.M))
bad=[(n,t) for n in names for r,t in rules if r.search(\"_\"+n) or r.search(n)]
print(\"  strip functions:\", len(names)); sys.exit(1 if bad or len(names) < 30 else 0)'"
ck "no em or en dash in the strip's files" "! grep -nP '\\x{2014}|\\x{2013}' $H $R test-recentstrip.m test-recentstrip.sh 2>/dev/null && ! LC_ALL=C grep -n \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $H $R test-recentstrip.m test-recentstrip.sh"

echo "== made-to-fail copies of the rules (each must fail)"
mut() {   # $1 what, $2 the text in the rules, $3 its replacement
  local f="$W/rule.$RANDOM.h"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); a,b=sys.argv[2],sys.argv[3]; assert s.count(a)==1, a; open(sys.argv[4],"w").write(s.replace(a,b))' "$TOOLS/$R" "$2" "$3" "$f" || { echo "FAIL  made-to-fail copy \"$1\": its text is not in the rules once"; rc=1; return; }
  if ! clang -fobjc-arc -Wall -Werror -Wno-unknown-warning-option -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -framework Foundation -DRSTRIP_RULE="\"$f\"" -o "$W/m" test-recentstrip.m 2>"$W/m.err"; then echo "FAIL  made-to-fail copy \"$1\" does not build"; rc=1; return; fi
  "$W/m" -q > "$W/m.out"; local r=$?
  if [ $r -gt 0 ]; then echo "PASS  caught: $1 ($r checks fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
}
mut "the one in front always goes to the top (no swap)" '[order insertObject:was atIndex:swap ? slot : 0];' '[order insertObject:was atIndex:0];'
mut "the front one stays in the strip" 'if (now.length) [order removeObject:now];
    if (!was.length' 'if (!was.length'
mut "a closed window stays" 'if (![here containsObject:order[(NSUInteger)i]]) [order removeObjectAtIndex:(NSUInteger)i];' 'if (NO) [order removeObjectAtIndex:(NSUInteger)i];'
mut "brought out only where nothing covers it" 'if (s.revealed) return MSBDRStripOverWindows;' 'if (s.revealed && !s.covered) return MSBDRStripOverWindows;'
mut "shows on the Home Screen with every window minimized" 'if (!s.windowShown || s.covered) return MSBDRStripHidden;' 'if (s.covered) return MSBDRStripHidden;'
mut "shows over a full-screen app in front" 'if (!s.on || s.items <= 0 || !s.calm || !s.windowsFront) return MSBDRStripHidden;' 'if (!s.on || s.items <= 0 || !s.calm) return MSBDRStripHidden;'
mut "no slack in the cover" 'return ox > kMSBDRStripCoverSlack && oy > kMSBDRStripCoverSlack;' 'return ox > 0 && oy > 0;'
mut "always the left edge" 'static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return dockAtLeft; }' 'static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return NO; }'
mut "the edge 1 pt wide" 'return right ? x >= sw - kMSBDRStripEdgeAt : x <= kMSBDRStripEdgeAt;' 'return right ? x >= sw - 1.0 : x <= 1.0;'
mut "8 cards" '#define kMSBDRStripMax        6' '#define kMSBDRStripMax        8'
mut "cards not centred" 'top = usable.y + floor((usable.h - total) / 2.0);' 'top = usable.y + kMSBDRStripEnds;'
mut "a minimized window pictured again" 'return !has || (onScreen && age > kMSBDRStripPicLife);' 'return !has || age > kMSBDRStripPicLife;'
mut "every window pictured again at a minimize" 'return !has || (front && age > kMSBDRStripMinPicLife);' 'return !has || age > kMSBDRStripMinPicLife;'
mut "pictures at the window's size" 'return k > 1.0 ? 1.0 : (k < 0.02 ? 0.02 : k);' 'return 1.0;'
mut "on iPadOS 16 too" 'static inline BOOL MSBDRecentStripOS(long major) { return major == 15; }' 'static inline BOOL MSBDRecentStripOS(long major) { return major >= 15; }'
exit $rc
