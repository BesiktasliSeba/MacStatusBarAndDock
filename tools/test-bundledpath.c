// test-bundledpath.c: which processes the loader gives the app-side parts (common/BundledPath.h): processes inside an .app, .appex or .xpc bundle,
// wherever the bundle lives (the data containers, /Applications, /var/jb, a cryptex, ExtensionKit), never bare daemons, DriverKit drivers or
// names that merely contain ".app"; and the app extensions MixAudio stays out of. Paths as _NSGetExecutablePath gives them (M1 15.6.1, 17.5,
// A12Z 18.5 process lists, memory audit 1 Nov 2026).
#include <stdio.h>
#include "../common/BundledPath.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    check("SpringBoard, a system app, an App Store app (data container): bundled",
          MSBDBundledProcess("/System/Library/CoreServices/SpringBoard.app/SpringBoard") && MSBDBundledProcess("/Applications/Preferences.app/Preferences")
          && MSBDBundledProcess("/private/var/containers/Bundle/Application/0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0/Spotify.app/Spotify"));
    check("a jailbreak app (/var/jb): bundled", MSBDBundledProcess("/private/preboot/1A2B/jb-ABCD/procursus/Applications/Sileo.app/Sileo")
          && MSBDBundledProcess("/var/jb/Applications/Filza.app/Filza"));
    check("Safari from the App cryptex (16+), in both of its path forms: bundled",
          MSBDBundledProcess("/private/preboot/Cryptexes/App/Applications/MobileSafari.app/MobileSafari")
          && MSBDBundledProcess("/System/Cryptexes/App/Applications/MobileSafari.app/MobileSafari"));
    check("WebKit's GPU and WebContent XPC services, framework and cryptex copies: bundled",
          MSBDBundledProcess("/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.GPU.xpc/com.apple.WebKit.GPU")
          && MSBDBundledProcess("/System/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/com.apple.WebKit.WebContent")
          && MSBDBundledProcess("/private/preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.Networking.xpc/com.apple.WebKit.Networking"));
    check("an app's XPC service: bundled", MSBDBundledProcess("/Applications/MobileSlideShow.app/XPCServices/com.apple.photos.ImageConversionService.xpc/com.apple.photos.ImageConversionService"));
    check("app extensions: an app's PlugIns, its Extensions, iOS's ExtensionKit (CollectionsPoster), a framework's PlugIns: bundled",
          MSBDBundledProcess("/private/var/containers/Bundle/Application/0F1E/Spotify.app/PlugIns/SpotifyWidget.appex/SpotifyWidget")
          && MSBDBundledProcess("/Applications/PosterBoard.app/Extensions/EmojiPoster.appex/EmojiPoster")
          && MSBDBundledProcess("/System/Library/ExtensionKit/Extensions/CollectionsPoster.appex/CollectionsPoster")
          && MSBDBundledProcess("/System/Library/PrivateFrameworks/WallpaperKit.framework/PlugIns/WallpaperCollectionsPoster.appex/WallpaperCollectionsPoster"));
    check("bare daemons that link UIKit (runningboardd, mediaserverd, locationd, UniversalControl, CommCenter): not bundled",
          !MSBDBundledProcess("/usr/libexec/runningboardd") && !MSBDBundledProcess("/usr/sbin/mediaserverd") && !MSBDBundledProcess("/usr/libexec/locationd")
          && !MSBDBundledProcess("/usr/libexec/UniversalControl") && !MSBDBundledProcess("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter"));
    check("a daemon in a cryptex: not bundled", !MSBDBundledProcess("/private/preboot/Cryptexes/OS/usr/libexec/webinspectord")
          && !MSBDBundledProcess("/System/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Support/webkitd"));
    check("a DriverKit driver (.dext, the iPad 2's AppleUserHIDDrivers): not bundled",
          !MSBDBundledProcess("/System/Library/DriverExtensions/AppleUserHIDDrivers.dext/AppleUserHIDDrivers"));
    check("names that only contain \".app\" (com.apple.appleseed..., .appd, a framework): not bundled",
          !MSBDBundledProcess("/System/Library/PrivateFrameworks/Seeding.framework/Support/com.apple.appleseed.seedingd")
          && !MSBDBundledProcess("/usr/libexec/com.apple.appd") && !MSBDBundledProcess("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport")
          && !MSBDBundledProcess("/usr/libexec/Foo.app") && !MSBDBundledProcess("/usr/libexec/Bar.xpc") && !MSBDBundledProcess("/usr/libexec/Baz.appex"));
    check("no path, an empty one: not bundled", !MSBDBundledProcess(NULL) && !MSBDBundledProcess(""));
    check("MixAudio's rule: app extensions (PlugIns, Extensions, ExtensionKit) are; the app, SpringBoard, XPC services, daemons are not",
          MSBDAppExtension("/private/var/containers/Bundle/Application/0F1E/Spotify.app/PlugIns/SpotifyWidget.appex/SpotifyWidget")
          && MSBDAppExtension("/System/Library/ExtensionKit/Extensions/CollectionsPoster.appex/CollectionsPoster")
          && !MSBDAppExtension("/private/var/containers/Bundle/Application/0F1E/Spotify.app/Spotify")
          && !MSBDAppExtension("/System/Library/CoreServices/SpringBoard.app/SpringBoard")
          && !MSBDAppExtension("/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.GPU.xpc/com.apple.WebKit.GPU")
          && !MSBDAppExtension("/usr/libexec/runningboardd") && !MSBDAppExtension(NULL));
    if (fails) { printf("test-bundledpath (compiled): FAILED\n"); return 1; }
    printf("test-bundledpath (compiled): all checks pass\n"); return 0;
}
