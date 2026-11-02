// test-audiotitle.c -- Mac test of common/AudioTitle.h (1.7.8): when the menu bar's Audio title shows, from the system audio controller's answer.
// The A12Z's muted Spotify preview (1 Nov): one session listed, the "audio is playing somewhere" flag 0 -- no title. Run by test-audiotitle.sh.
#include <stdio.h>
#include "../common/AudioTitle.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
int main(void) {
    Int("a listed session the flag calls silent (a muted preview: Spotify's home feed, A12Z 18.5) -> no title", MSBDAudioTitlePlaying(0, 1), 0);
    Int("the flag says sound, one session listed (Spotify playing) -> the title", MSBDAudioTitlePlaying(1, 1), 1);
    Int("the flag says sound, no session the list matches to an app (a daemon, web audio not listed) -> the title", MSBDAudioTitlePlaying(1, 0), 1);
    Int("the flag says sound, no list at all -> the title", MSBDAudioTitlePlaying(1, -1), 1);
    Int("silence: the flag 0, nothing listed -> no title", MSBDAudioTitlePlaying(0, 0), 0);
    Int("silence: the flag 0, no list -> no title", MSBDAudioTitlePlaying(0, -1), 0);
    Int("no flag from the controller, a session listed -> the list decides: the title (as before 1.7.8)", MSBDAudioTitlePlaying(-1, 2), 1);
    Int("no flag, nothing listed -> no title", MSBDAudioTitlePlaying(-1, 0), 0);
    Int("no flag, no list -> no title", MSBDAudioTitlePlaying(-1, -1), 0);
    Int("a flag that is not 0 or 1 counts as no answer (the list decides)", MSBDAudioTitlePlaying(7, 0), 0);
    printf("%s: %d/%d\n", fails ? "test-audiotitle FAILED" : "test-audiotitle: all pass", checks - fails, checks);
    return fails ? 1 : 0;
}
