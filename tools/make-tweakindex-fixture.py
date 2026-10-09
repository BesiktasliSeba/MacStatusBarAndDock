#!/usr/bin/env python3
# make-tweakindex-fixture.py <folder>: a made-up /var/jb/Library tree for tools/test-tweakindex.m (common/TweakIndex.h): PreferenceLoader entry
# plists and preference bundles written the ways real tweaks write them (Root.plist, a plist named after the bundle, a page in the entry plist itself,
# strings in Application Support, sub-pages a link row opens, light/dark pairs, pickers, credits and link-outs, filters, a missing bundle, a duplicate
# name, our own pages), with .strings files as binary plists, UTF-8 text and UTF-16 text. Nothing here comes from a real tweak.
import os, plistlib, sys

root = sys.argv[1]
PL = os.path.join(root, 'PreferenceLoader', 'Preferences')
PB = os.path.join(root, 'PreferenceBundles')
AS = os.path.join(root, 'Application Support')
PNG = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
                    '1f15c4890000000d4944415478da63f8ffff3f0005fe02fea7d6a4ab0000000049454e44ae426082')

def w(path, data, binary=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML)

def strings(path, d, enc='utf-8'):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = ''.join('"%s" = "%s";\n' % (k, v) for k, v in d.items())
    with open(path, 'wb') as f:
        f.write(text.encode('utf-16') if enc == 'utf-16' else text.encode('utf-8'))

def raw(path, b):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f: f.write(b)

def entry(name, e, extra=None, sub=None):
    d = {'entry': e}
    if extra: d.update(extra)
    w(os.path.join(PL, sub or '', name + '.plist'), d)

def group(label=None, footer=None):
    d = {'cell': 'PSGroupCell'}
    if label is not None: d['label'] = label
    if footer: d['footerText'] = footer
    return d

def sw(label, key, **k):
    d = {'cell': 'PSSwitchCell', 'label': label, 'key': key, 'defaults': 'com.example.fixture', 'default': False}
    d.update(k); return d

# Alpha: a classic bundle page (Root.plist), localized (en: binary strings, tr: UTF-16 text), with a sub-page, a picker, a slider named by its group,
# a duplicate row name, buttons (one kept, credits dropped), link-outs and headers (dropped), a label with a value placeholder.
entry('Alpha', {'cell': 'PSLinkCell', 'bundle': 'AlphaPrefs', 'detail': 'ALPRootListController', 'isController': True, 'label': 'Alpha', 'icon': 'icon'})
w(os.path.join(PB, 'AlphaPrefs.bundle', 'Info.plist'), {'CFBundleExecutable': 'AlphaPrefs', 'NSPrincipalClass': 'ALPRootListController'})
raw(os.path.join(PB, 'AlphaPrefs.bundle', 'icon@2x.png'), PNG)
w(os.path.join(PB, 'AlphaPrefs.bundle', 'Root.plist'), {'title': 'Alpha', 'items': [
    {'cell': 'PSStaticTextCell', 'cellClass': 'ALPHeaderCell', 'label': 'Alpha by someone'},
    group('GROUP_GENERAL'),
    sw('ENABLED', 'enabled'),
    sw('Hide Labels & Dots', 'hideLabels', id='HIDE_LABELS'),
    group('Speed'),
    {'cell': 'PSSliderCell', 'key': 'speed', 'min': 0, 'max': 1, 'defaults': 'com.example.fixture'},
    {'cell': 'PSLinkListCell', 'label': 'Style', 'key': 'style', 'detail': 'PSListItemsController', 'validValues': [0, 1], 'validTitles': ['A', 'B']},
    {'cell': 'PSLinkCell', 'label': 'Advanced Options', 'detail': 'ALPChildController', 'child': 'Advanced'},
    {'cell': 'PSEditTextCell', 'label': 'Number of Items: %i', 'key': 'items'},
    group('Other'),
    sw('ENABLED', 'enabled2'),
    {'cell': 'PSButtonCell', 'label': 'Respring', 'action': 'respring'},
    {'cell': 'PSButtonCell', 'label': 'Follow me', 'action': 'openTwitter'},
    {'label': 'Our other tweak', 'cellClass': 'HBLinkTableCell', 'url': 'https://example.com'},
    {'cell': 'PSSwitchCell', 'label': 'Old Option', 'key': 'old', 'pl_filter': {'CoreFoundationVersion': [1.0, 2.0]}},
]})
w(os.path.join(PB, 'AlphaPrefs.bundle', 'Advanced.plist'), {'title': 'Advanced', 'items': [group('Tuning'), sw('Turbo Mode', 'turbo')]})
w(os.path.join(PB, 'AlphaPrefs.bundle', 'en.lproj', 'Root.strings'), {'GROUP_GENERAL': 'General', 'ENABLED': 'Enabled'}, binary=True)
strings(os.path.join(PB, 'AlphaPrefs.bundle', 'tr.lproj', 'Root.strings'), {'GROUP_GENERAL': 'Genel', 'ENABLED': 'Etkin'}, enc='utf-16')

# Gamma: an "id" for its row, the page plist named after the bundle, a sub-page found from the controller's class name (UTF-8 strings).
entry('Gamma', {'cell': 'PSLinkCell', 'bundle': 'GammaSettings', 'isController': '1', 'label': 'Gamma Tweak', 'id': 'GAMMA_ID'})
w(os.path.join(PB, 'GammaSettings.bundle', 'GammaSettings.plist'), {'items': [
    group(), sw('Use Gestures', 'gestures'),
    {'cell': 'PSLinkCell', 'label': 'More', 'detail': 'GMSubPageController'},
]})
w(os.path.join(PB, 'GammaSettings.bundle', 'SubPage.plist'), {'items': [group('Deep'), sw('Deep Switch', 'deep')]})
strings(os.path.join(PB, 'GammaSettings.bundle', 'en.lproj', 'GammaSettings.strings'), {'Use Gestures': 'Use Gestures'})

# Delta: labels are keys; the strings live in a bundle in Application Support (as Choicy keeps them); one key has no string at all.
entry('DeltaPrefs', {'cell': 'PSLinkCell', 'bundle': 'DeltaPrefs', 'isController': True, 'label': 'Delta'})
w(os.path.join(PB, 'DeltaPrefs.bundle', 'Root.plist'), {'items': [
    group('PROCESS_CONFIGURATION'), {'cell': 'PSLinkCell', 'label': 'GLOBAL_TWEAK_CONFIGURATION', 'detail': 'DLTGlobalTweakConfigurationController'},
    sw('UNKNOWN_KEY_HERE', 'u'),
]})
w(os.path.join(PB, 'DeltaPrefs.bundle', 'GlobalTweakConfiguration.plist'), {'items': [group('GLOBAL'), sw('DISABLE_EVERYWHERE', 'off')]})
w(os.path.join(AS, 'Delta.bundle', 'en.lproj', 'Localizable.strings'), {'PROCESS_CONFIGURATION': 'Process Configuration', 'GLOBAL_TWEAK_CONFIGURATION': 'Global Configuration', 'DISABLE_EVERYWHERE': 'Disable Everywhere', 'GLOBAL': 'Global'}, binary=True)

# Epsilon: a page made of the entry plist itself, in a folder of its own, with its own Localizable.strings.
entry('Epsilon', {'cell': 'PSLinkCell', 'label': 'Epsilon', 'icon': 'eps.png'}, extra={'items': [group('EPS GROUP'), sw('eps_switch', 'eps')]}, sub='Epsilon')
raw(os.path.join(PL, 'Epsilon', 'eps.png'), PNG)
strings(os.path.join(PL, 'Epsilon', 'en.lproj', 'Localizable.strings'), {'eps_switch': 'Epsilon Switch'})

# Zeta: two page plists and no usual name -> the page only. Eta: a light/dark pair -> the light one. Theta: a code-only page (no plist).
entry('Zeta', {'cell': 'PSLinkCell', 'bundle': 'ZetaPrefs', 'isController': True, 'label': 'Zeta'})
w(os.path.join(PB, 'ZetaPrefs.bundle', 'One.plist'), {'items': [sw('Zeta One', 'z1')]})
w(os.path.join(PB, 'ZetaPrefs.bundle', 'Two.plist'), {'items': [sw('Zeta Two', 'z2')]})
entry('Eta', {'cell': 'PSLinkCell', 'bundle': 'EtaPrefs', 'isController': True, 'label': 'Eta'})
w(os.path.join(PB, 'EtaPrefs.bundle', 'Root-Light.plist'), {'items': [sw('Light Row', 'l')]})
w(os.path.join(PB, 'EtaPrefs.bundle', 'Root-Dark.plist'), {'items': [sw('Dark Row', 'd')]})
entry('Theta', {'cell': 'PSLinkCell', 'bundle': 'ThetaPrefs', 'isController': True, 'label': 'Theta'})
os.makedirs(os.path.join(PB, 'ThetaPrefs.bundle'), exist_ok=True)

# Iota: half an emoji in a tweak's own text (1.4.3 external test H-1): a row label in a binary plist and a title in a UTF-16 .strings file each end
# in a lone UTF-16 surrogate (plistlib writes no such string: the label is written with a snowman and its two bytes swapped for a high surrogate).
entry('Iota', {'cell': 'PSLinkCell', 'bundle': 'IotaPrefs', 'isController': True, 'label': 'Iota'})
iota = os.path.join(PB, 'IotaPrefs.bundle', 'Root.plist')
w(iota, {'items': [group('Cut'), sw('Iota Raw \u2603', 'raw'), sw('IOTA_LOCALIZED', 'loc')]}, binary=True)
b = open(iota, 'rb').read(); assert b.count(b'\x26\x03') == 1
raw(iota, b.replace(b'\x26\x03', b'\xd8\x3d'))
raw(os.path.join(PB, 'IotaPrefs.bundle', 'en.lproj', 'Root.strings'), '"IOTA_LOCALIZED" = "Iota Strings \ud83d";\n'.encode('utf-16', 'surrogatepass'))

# Left out: a filtered entry, a missing bundle, a plist without an entry, a switch put straight into the list, a duplicate name, our own bundle.
entry('Filtered', {'cell': 'PSLinkCell', 'bundle': 'AlphaPrefs', 'isController': True, 'label': 'Filtered'}, extra={'pl_filter': {'CoreFoundationVersion': [99999.0]}})
entry('Missing', {'cell': 'PSLinkCell', 'bundle': 'NoSuchPrefs', 'isController': True, 'label': 'Missing'})
w(os.path.join(PL, 'NotAnEntry.plist'), {'something': 1})
entry('Switchy', {'cell': 'PSSwitchCell', 'label': 'Switchy', 'key': 's'})
entry('ZDuplicate', {'cell': 'PSLinkCell', 'bundle': 'ZetaPrefs', 'isController': True, 'label': 'Alpha'})
entry('OursAgain', {'cell': 'PSLinkCell', 'bundle': 'MacStatusBarPrefs', 'isController': True, 'label': 'Status Bar', 'id': 'MSBD_PL_MacStatusBarPrefs'})

# Our own page (indexed as "own", not from its entry)
w(os.path.join(PB, 'MacStatusBarPrefs.bundle', 'Root.plist'), {'items': [group('Clock'), sw('Show Seconds', 'showSeconds'), group('Search'), sw('Show Spotlight Search', 'showSpotlight')]})
raw(os.path.join(PB, 'MacStatusBarPrefs.bundle', 'icon@2x.png'), PNG)
