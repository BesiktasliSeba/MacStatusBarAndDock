// DMLog: the debug log (/tmp/dockmag.log), in DEBUG builds only (release hardening plan, section 1). In a release (FINALPACKAGE=1) build the call
// and its argument are compiled away; the argument is still type-checked and counts as used, so -Werror sees no unused variables.
#import <Foundation/Foundation.h>
#if DEBUG
void DMLogWrite(NSString *line);
#define DMLog(...) DMLogWrite(__VA_ARGS__)   // (variadic: the commas inside [NSString stringWithFormat:...] are not macro-argument separators)
#else
#define DMLog(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#endif
