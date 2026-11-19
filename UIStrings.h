#pragma once
#import <Foundation/Foundation.h>

extern NSString *VPTranslateStaticUIString(NSString *text) __attribute__((weak_import));
static inline NSString *VPUIString(NSString *text) {
    return VPTranslateStaticUIString ? VPTranslateStaticUIString(text) : text;
}
