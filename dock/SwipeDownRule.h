// SwipeDownRule.h: a trackpad's two-finger scroll down over the Home Screen behind a window of ours is not the swipe down that opens the App
// Library (KT, 1.8.2; dock/Dock.x, -[SBSearchScrollView gestureRecognizerShouldBegin:]). Plain C, so tools/test-swipescroll.c runs it.
//
// A pointer's scroll (a trackpad's two fingers, a mouse wheel) moves the same pan as a finger: UIKit hands a scroll event to the pans under the
// pointer (-[UIScrollEvent _gestureRecognizersForWindow:]: the window's hit test at the pointer, then each gesture parent up, every enabled pan
// that takes that kind of scroll, -[UIPanGestureRecognizer shouldReceiveEvent:]), so the Home Screen's search view (SBSearchScrollView, whose
// pan takes every scroll) took a two-finger scroll down as Spotlight's pull, and with Swipe Down Opens App Library our hook opened the App
// Library for it -- also over the Home Screen beside a window. Such a pan holds no touch: UIKit moves it by the scroll's deltas
// (-[UIPanGestureRecognizer _scrollingChangedWithEvent:]) and -numberOfTouches counts the touches it holds; a finger's pan holds one at least while
// the finger is down (UIKitCore 17.6.1). Paging left and right is the icon scroll view's own pan: not this one, left as iPadOS has it.
#pragma once

// A pointer's scroll is the pan UIKit's own scroll event drives, where that can be asked of it (scrollAskable: -[UIGestureRecognizer _activeEventOfType:] with
// UIEventTypeScroll, 10 -- UIKitCore 17.6.1, read; on 18.5 the scroll event is there at -gestureRecognizerShouldBegin:); else a pan holding no touch. A finger's
// pan whose begin waited for another recognizer to fail can be asked after the finger has lifted, holding no touch then: by its touches alone a quick flick
// beside a window was taken for a scroll and opened nothing (code review 1.8.2, 13).
static inline int DMPanIsPointerScroll(unsigned long touches, int scrollAskable, int scrollEvent) { return scrollAskable ? scrollEvent != 0 : touches == 0; }
// A downward pan that the swipe down would take is still the swipe down (the App Library), unless it is a pointer's scroll while a window of ours
// is on screen: then nothing happens, as on a Mac's desktop under its windows -- no App Library, and no Spotlight pull in its place. A finger, and a
// pointer's scroll with no window of ours on screen, as before.
static inline int DMSwipeDownTakesPan(unsigned long touches, int scrollAskable, int scrollEvent, int windowOnScreen) { return !(DMPanIsPointerScroll(touches, scrollAskable, scrollEvent) && windowOnScreen); }
