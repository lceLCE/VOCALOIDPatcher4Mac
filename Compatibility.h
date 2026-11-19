// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <stdint.h>

// This is one verified arm64 editor build, not a bypass switch.
// Re-derive every ABI dependency and run the checklist in docs/ADAPTING.md
// before changing the target. Code PCs below are unslid virtual addresses.
#define VP_EDITOR_VERSION @"7.0.0"
#define VP_EDITOR_SHA256 @"eb9440ffedc2bcd00f897dab57007767d59a64032e7489c0cf1a5546c1d0ba92"

// Swift entry points: add the MH_EXECUTE slide before calling.
#define VP_ADDR_NOTE_RECT UINT64_C(0x1001baa84)
#define VP_ADDR_LOCAL_X UINT64_C(0x1001ba9a8)

// Return PCs: subtract the MH_EXECUTE slide from the observed caller.
#define VP_PC_LYRIC_POINT UINT64_C(0x1001bd96c)
#define VP_PC_LYRIC_RECT UINT64_C(0x1001bdfb8)
#define VP_PC_NOTE_RECT_1 UINT64_C(0x10025a834)
#define VP_PC_NOTE_RECT_2 UINT64_C(0x10025a958)
#define VP_PC_NOTE_RECT_3 UINT64_C(0x10025ac3c)
#define VP_PC_NOTE_RECT_4 UINT64_C(0x10025af58)
#define VP_PC_NOTE_FILL_1 UINT64_C(0x10025a454)
#define VP_PC_NOTE_FILL_2 UINT64_C(0x10025a808)
#define VP_PC_NOTE_FILL_3 UINT64_C(0x10025ac54)
#define VP_PC_WAVE_COLOR UINT64_C(0x100100f00)
#define VP_PC_WAVE_VERTICAL UINT64_C(0x100101250)
#define VP_PC_WAVE_CONNECT_1 UINT64_C(0x10010128c)
#define VP_PC_WAVE_CONNECT_2 UINT64_C(0x1001012ac)
#define VP_PC_PREVIEW_REDRAW_1 UINT64_C(0x10025b66c)
#define VP_PC_PREVIEW_REDRAW_2 UINT64_C(0x10025b6d4)
#define VP_PC_PREVIEW_REDRAW_3 UINT64_C(0x10025b704)
