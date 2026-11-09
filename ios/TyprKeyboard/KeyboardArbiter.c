// Switches on UIKit's keyboard arbiter client, which knows the app a keyboard is serving
// (by process ID and bundle ID) but stays off inside a keyboard unless
// `+[_UIKeyboardArbiterClient enabled]` answers YES. UIKit decides once, early, whether the
// client exists, so this runs as the keyboard binary loads (Dictus measured a later swizzle
// working once and then never). Private API, resolved by name: any missing step is a clean
// return, and the keyboard then simply cannot name its host (`KeyboardHost`).
//
// Translated from iikb's `KeyboardArbiter.c` (https://github.com/AVGVSTVS96/iikb, MIT) and
// Dictus's `HostArbiterActivation.m` (https://github.com/getdictus/dictus-ios, MIT).
//
// This runs before Swift starts: no allocation beyond the runtime's, no logging, no I/O.
// This file is only part of the TyprKeyboard target.

#include <objc/runtime.h>
#include <stdbool.h>

static BOOL TyprArbiterEnabled(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return YES;
}

static bool TyprEnableKeyboardArbiter(void) {
    Class arbiter = objc_getClass("_UIKeyboardArbiterClient");
    if (!arbiter) return false;
    Method method = class_getClassMethod(arbiter, sel_registerName("enabled"));
    if (!method) return false;
    method_setImplementation(method, (IMP)TyprArbiterEnabled);
    return true;
}

__attribute__((constructor)) static void TyprEnableKeyboardArbiterAtLoad(void) {
    TyprEnableKeyboardArbiter();
}
