// MSBAcknowledgementsController.m -- Settings > Status Bar > Acknowledgements (1.8.5): the work of others this tweak is built on, each with its
// license. Today: KeyPilot by wanghuangjie (MIT), the base of Custom Shortcuts (common/CustomShortcutsRule.h); its license text as the package
// carries it (third_party/KeyPilot/LICENSE, installed at /usr/lib/MacStatusBarAndDock/third_party/KeyPilot/LICENSE).
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "MSBAcknowledgementsController.h"

// The license as installed (the package's copy), or nil when it can't be read.
static NSString *MSBAckLicense(NSString *name) {
	for (NSString *root in @[@"/var/jb", @""]) {
		NSString *p = [NSString stringWithFormat:@"%@/usr/lib/MacStatusBarAndDock/third_party/%@/LICENSE", root, name];
		NSString *t = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
		if (!t.length) continue;
		// (the file wraps at 80 columns; a footer wraps by itself: each paragraph's lines joined, the paragraphs kept)
		NSMutableArray *paras = [NSMutableArray array];
		for (NSString *p in [[t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@"\n\n"]) {
			NSArray *lines = [p componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
			NSString *one = [[lines componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (one.length) [paras addObject:one];
		}
		return [paras componentsJoinedByString:@"\n\n"];
	}
	return nil;
}

@implementation MSBAcknowledgementsController
- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *s = [NSMutableArray array];
		PSSpecifier *kp = [PSSpecifier groupSpecifierWithID:@"ACK_KEYPILOT"];
		[kp setProperty:@"KeyPilot" forKey:@"label"];
		[kp setName:@"KeyPilot"];
		NSString *lic = MSBAckLicense(@"KeyPilot");
		NSString *text = @"Custom Shortcuts in Settings > Keyboard is based on KeyPilot by wanghuangjie, used under the MIT License.";
		if (lic) text = [text stringByAppendingFormat:@"\n\n%@", lic];
		[kp setProperty:text forKey:@"footerText"];
		[s addObject:kp];
		PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"KeyPilot on GitHub" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
		link.identifier = @"ACK_KEYPILOT_LINK";
		link.buttonAction = @selector(msb_openKeyPilot:);
		[s addObject:link];
		_specifiers = s;
	}
	return _specifiers;
}
- (void)msb_openKeyPilot:(PSSpecifier *)specifier {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/wanghuangjie/KeyPilot"] options:@{} completionHandler:nil];
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Acknowledgements";
}
@end
