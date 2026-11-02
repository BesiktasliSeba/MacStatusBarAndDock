// AudioTitle.h -- when the menu bar shows its Audio title (1.7.8): the system's audio controller's answer, one rule (StatusBar.x
// DMAudioPlayingAnswer). Plain C, so the Mac test (tools/test-audiotitle.c) runs this very code.
//  - playingSomewhere: AVSystemController_AudioIsPlayingSomewhereAttribute -- 1 / 0, or -1 when the controller gave no boolean;
//  - sessions: how many playing sessions it listed (PlayingSessionsDescriptionAttribute), -1 when it gave no list.
// Sound decides: the flag is the system's own "audio is playing somewhere" (YES while Spotify, YouTube, Safari or Twitter play, two at once too:
// M1 15.6.1, KT-tested 23 Sep). A session listed as playing is no proof of sound: Spotify's home feed played a muted preview after Stage Manager
// relaunched it (A12Z 18.5, 1 Nov) -- listed, MediaRemote "playing 1", the flag 0, nothing audible -- and the title showed, because until 1.7.8
// any listed session counted. The list still names the apps in the menu; it decides the title only when the flag is not there.
#pragma once

static inline int MSBDAudioTitlePlaying(int playingSomewhere, long sessions) {
    if (playingSomewhere == 0 || playingSomewhere == 1) return playingSomewhere;
    return sessions > 0;
}
