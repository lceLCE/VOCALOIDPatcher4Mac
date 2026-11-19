#import "Compatibility.h"
#import <AppKit/AppKit.h>
static NSString *VPTranslate(NSString *text);
#define VPUIString(text) VPTranslate(text)
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>
extern BOOL VPSupportedEditor(void);

typedef struct {
  int64_t value;
} VPTick;
@protocol VPNote
- (id)parent;
- (BOOL)isSelected;
- (BOOL)isProtected;
- (NSString *)lyric;
- (BOOL)setLyric:(NSString *)value;
- (NSInteger)noteNumber;
- (BOOL)setNoteNumber:(NSInteger)value;
- (VPTick)posTick;
- (VPTick)duration;
- (BOOL)setDuration:(VPTick)value;
@end
@protocol VPPart <NSObject>
- (NSUInteger)numNote;
- (id<VPNote>)note:(NSUInteger)i;
- (VPTick)absPosTick;
- (VPTick)duration;
- (id)parentTrack;
- (BOOL)removeNote:(id<VPNote>)note;
- (id<VPNote>)duplicateNote:(VPTick)position note:(id<VPNote>)note;
- (BOOL)moveNote:(VPTick)position note:(id<VPNote>)note;
@end
@protocol VPTrack <NSObject>
- (int)type;
- (NSUInteger)numPart;
- (id<VPPart>)part:(NSUInteger)i;
- (id<VPPart>)duplicatePart:(VPTick)position part:(id<VPPart>)part;
- (NSString *)voiceBankID;
- (BOOL)setVoiceBankID:(NSString *)bank;
@end
@protocol VPSequence
- (BOOL)isStaged;
- (BOOL)isDirty;
- (BOOL)commit;
- (BOOL)rollback;
- (void)notify;
- (NSUInteger)numTrack;
- (id<VPTrack>)track:(NSUInteger)i;
- (NSUInteger)maxNumTrack;
- (id<VPTrack>)insertMidiTrack:(NSUInteger)i
                          name:(NSString *)name
                          type:(int)type;
@end

// Only object references in the pinned 7.0.0 ABI are read. No Swift value
// layout is assumed.
static id VPObjectIvar(id object, const char *name) {
  if (!object)
    return nil;
  Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
  if (!ivar)
    return nil;
  void *pointer = NULL;
  memcpy(&pointer, (__bridge const void *)object + ivar_getOffset(ivar),
         sizeof(pointer));
  return (__bridge id)pointer;
}
NSDocument *VPCurrentDocument(void) {
  NSDocumentController *controller =
      NSDocumentController.sharedDocumentController;
  NSArray *preferred = @[
    controller.currentDocument ?: NSNull.null,
    NSApp.mainWindow.windowController.document ?: NSNull.null
  ];
  for (id candidate in preferred)
    if ([NSStringFromClass([candidate class])
            isEqualToString:@"VOCALOID7_Editor.VEDocument"])
      return candidate;
  for (NSDocument *candidate in controller.documents.reverseObjectEnumerator)
    if ([NSStringFromClass(candidate.class)
            isEqualToString:@"VOCALOID7_Editor.VEDocument"])
      return candidate;
  return nil;
}
static id VPModel(void) {
  return VPObjectIvar(VPCurrentDocument(), "sequence");
}
static id<VPSequence> VPSequenceObject(void) {
  return VPObjectIvar(VPModel(), "vsmSequence");
}
static NSArray<id<VPNote>> *VPSelected(void) {
  id<VPPart> part = VPObjectIvar(VPModel(), "activePart");
  if (![part respondsToSelector:@selector(numNote)])
    return @[];
  NSMutableArray *notes = [NSMutableArray array];
  for (NSUInteger i = 0; i < [part numNote]; i++) {
    id<VPNote> note = [part note:i];
    if ([note isSelected])
      [notes addObject:note];
  }
  return notes;
}
static void VPAlert(NSString *message) {
  NSAlert *alert = [NSAlert new];
  alert.messageText = @"VOCALOID Patcher";
  alert.informativeText = message;
  [alert runModal];
}
static NSString *VPAsk(NSString *title, NSString *value) {
  NSAlert *alert = [NSAlert new];
  alert.messageText = title;
  NSTextField *input =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
  input.stringValue = value;
  alert.accessoryView = input;
  [alert addButtonWithTitle:VPUIString(@"确定")];
  [alert addButtonWithTitle:VPUIString(@"取消")];
  [alert.window setInitialFirstResponder:input];
  return [alert runModal] == NSAlertFirstButtonReturn ? input.stringValue : nil;
}
static BOOL VPEdit(NSString *name, BOOL includeAllWhenUnselected,
                   BOOL (^edit)(NSArray *)) {
  id<VPSequence> sequence = VPSequenceObject();
  NSArray *notes = VPSelected();
  if (!notes.count && includeAllWhenUnselected) {
    id<VPPart> part = VPObjectIvar(VPModel(), "activePart");
    NSMutableArray *all = [NSMutableArray array];
    if ([part respondsToSelector:@selector(numNote)])
      for (NSUInteger i = 0; i < [part numNote]; i++)
        [all addObject:[part note:i]];
    notes = all;
  }
  if (!sequence || !notes.count) {
    VPAlert(VPUIString(@"请在钢琴窗中选中需要处理的音符。"));
    return NO;
  }
  if ([sequence isStaged]) {
    VPAlert(VPUIString(@"编辑器正在处理另一个操作，请完成后重试。"));
    return NO;
  }
  BOOL success = NO;
  @try {
    success = edit(notes);
    if (success)
      success = [sequence commit];
  } @catch (NSException *exception) {
    success = NO;
  }
  if (!success)
    [sequence rollback];
  [sequence notify];
  if (!success)
    VPAlert(
        [name stringByAppendingString:VPUIString(@"失败，已撤销本次修改。")]);
  return success;
}
static NSView *VPGridButton(NSView *view) {
  NSView *result =
      [NSStringFromClass(view.class)
          isEqualToString:@"VOCALOID7_Editor.VEQuantizePopUpButton"]
          ? view
          : nil;
  for (NSView *child in view.subviews) {
    NSView *candidate = VPGridButton(child);
    if (candidate)
      result = candidate;
  }
  return result;
}
static NSInteger VPCurrentGrid(void) {
  NSView *button = VPGridButton(
      VPCurrentDocument().windowControllers.firstObject.window.contentView);
  Ivar quantize = class_getInstanceVariable(button.class, "quantize");
  if (!quantize)
    return 120;
  // The pinned Quantize.title getter decodes the note value in byte 0 and
  // triplet flag in bit 8.
  uint16_t value = 0;
  memcpy(&value, (__bridge const void *)button + ivar_getOffset(quantize),
         sizeof(value));
  unsigned kind = value & 255;
  if (kind < 1 || kind > 7 || value > 511)
    return 120;
  NSInteger ticks = 1920 / (1 << (kind - 1));
  return value & 256 ? ticks * 2 / 3 : ticks;
}
static NSString *VPRoot;
static NSMutableDictionary *VPSettings(void) {
  NSDictionary *stored = [NSDictionary
      dictionaryWithContentsOfFile:
          [VPRoot stringByAppendingPathComponent:@"settings.plist"]];
  return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}
static void VPStoreSetting(NSString *key, id value) {
  NSMutableDictionary *settings = VPSettings();
  settings[key] = value;
  if (![settings
          writeToFile:[VPRoot stringByAppendingPathComponent:@"settings.plist"]
           atomically:YES])
    VPAlert(VPUIString(@"无法保存补丁设置，请检查目录写入权限。"));
}
static NSString *VPTranslate(NSString *s);
static NSDictionary *VPTranslations;
static NSDictionary *VPKeyTranslations;
static os_unfair_lock VPTranslationLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, NSString *> *VPStringMap(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path];
  id raw = data ? [NSJSONSerialization JSONObjectWithData:data
                                                  options:0
                                                    error:nil]
                : nil;
  if (![raw isKindOfClass:NSDictionary.class])
    return @{};
  NSMutableDictionary *strings = [NSMutableDictionary dictionary];
  for (id key in raw)
    if ([key isKindOfClass:NSString.class] && [key length] &&
        [raw[key] isKindOfClass:NSString.class])
      strings[key] = raw[key];
  return strings;
}
static void VPLoadLanguage(NSString *language) {
  if (![@[ @"en", @"zh-Hans", @"zh-Hant", @"ja", @"es" ]
          containsObject:language])
    return;
  NSString *maps = [VPRoot stringByAppendingPathComponent:@"localization/maps"];
  NSDictionary *target = VPStringMap([maps
      stringByAppendingPathComponent:[language
                                         stringByAppendingString:@".json"]]);
  if (!target.count)
    return;
  NSMutableDictionary *translated = [target mutableCopy];
  for (NSString *source in @[ @"en", @"zh-Hans", @"zh-Hant", @"ja", @"es" ]) {
    NSDictionary *aliases = VPStringMap([maps
        stringByAppendingPathComponent:[source
                                           stringByAppendingString:@".json"]]);
    for (NSString *key in aliases)
      if (target[key] && [aliases[key] length])
        translated[aliases[key]] = target[key];
  }
  if ([language isEqualToString:@"zh-Hans"]) {
    [translated addEntriesFromDictionary:
                    VPStringMap([maps
                        stringByAppendingPathComponent:@"ja-to-zh-Hans.json"])];
    [translated addEntriesFromDictionary:@{
      @"ファイル" : @"文件",
      @"編集" : @"编辑",
      @"ジョブ" : @"任务",
      @"トランスポート" : @"播放控制",
      @"表示" : @"视图",
      @"ウインドウ" : @"窗口",
      @"ヘルプ" : @"帮助"
    }];
  }
  translated[@"ボタン"] = @"";
  translated[@"Button"] = @"";
  NSDictionary *keyTranslations =
      VPStringMap([maps stringByAppendingPathComponent:
                            [language stringByAppendingString:@".keys.json"]]);
  // Background engine errors can request localized text while the UI switches
  // language.
  os_unfair_lock_lock(&VPTranslationLock);
  VPTranslations = translated;
  VPKeyTranslations = keyTranslations;
  os_unfair_lock_unlock(&VPTranslationLock);
}

static IMP VPBundleOriginal;
static NSString *VPLocalize(id self, SEL cmd, NSString *key, NSString *value,
                            NSString *table) {
  NSString *original = ((id (*)(id, SEL, id, id, id))VPBundleOriginal)(
      self, cmd, key, value, table);
  BOOL isMain = self == NSBundle.mainBundle;
  os_unfair_lock_lock(&VPTranslationLock);
  NSString *mapped = isMain && key ? VPKeyTranslations[key] : nil;
  os_unfair_lock_unlock(&VPTranslationLock);
  return mapped ?: VPTranslate(original);
}
static NSString *VPTranslate(NSString *s) {
  if (!s)
    return @"";
  os_unfair_lock_lock(&VPTranslationLock);
  NSString *translated = VPTranslations[s] ?: s;
  os_unfair_lock_unlock(&VPTranslationLock);
  return translated;
}
NSString *VPTranslateStaticUIString(NSString *text) {
  return VPTranslate(text);
}
static void VPTranslateMenu(NSMenu *menu) {
  NSString *menuTitle = VPTranslate(menu.title);
  if (![menuTitle isEqualToString:menu.title]) menu.title = menuTitle;
  for (NSMenuItem *item in menu.itemArray) {
    NSString *title = VPTranslate(item.title);
    if (![title isEqualToString:item.title])
      item.title = title;
    if (item.submenu)
      VPTranslateMenu(item.submenu);
  }
}
static void VPTranslateView(NSView *view) {
  if (view.toolTip.length) {
    NSString *tooltip = VPTranslate(view.toolTip);
    if (![tooltip isEqualToString:view.toolTip])
      view.toolTip = tooltip;
  }
  if ([view isKindOfClass:NSPopUpButton.class])
    VPTranslateMenu(((NSPopUpButton *)view).menu);
  if ([view isKindOfClass:NSSegmentedControl.class]) {
    NSSegmentedControl *segments = (NSSegmentedControl *)view;
    for (NSInteger i = 0; i < segments.segmentCount; i++) {
      NSString *label = [segments labelForSegment:i];
      if (!label.length)
        continue;
      NSString *translated = VPTranslate(label);
      if (![translated isEqualToString:label])
        [segments setLabel:translated forSegment:i];
    }
  }
  if ([view isKindOfClass:NSTabView.class]) {
    for (NSTabViewItem *item in ((NSTabView *)view).tabViewItems) {
      NSString *label = VPTranslate(item.label);
      if (![label isEqualToString:item.label])
        item.label = label;
    }
  }
  if ([view isKindOfClass:NSTableView.class]) {
    for (NSTableColumn *column in ((NSTableView *)view).tableColumns) {
      NSString *label = VPTranslate(column.headerCell.stringValue);
      if (![label isEqualToString:column.headerCell.stringValue])
        column.headerCell.stringValue = label;
    }
  }
  if ([view isKindOfClass:NSButton.class]) {
    NSButton *button = (NSButton *)view;
    NSString *title = VPTranslate(button.title);
    if (![title isEqualToString:button.title])
      button.title = title;
  }
  if ([view isKindOfClass:NSTextField.class] &&
      !((NSTextField *)view).editable) {
    NSTextField *field = (NSTextField *)view;
    NSString *value = VPTranslate(field.stringValue);
    if (![value isEqualToString:field.stringValue])
      field.stringValue = value;
  }
  for (NSView *child in view.subviews)
    VPTranslateView(child);
}
// Match the upstream .NET midpoint-to-even rule for quantization and swing.
static int64_t VPRoundToEven(double value) {
  return (int64_t)__builtin_roundeven(value);
}
static NSInteger VPHarmonyPitch(NSInteger pitch, NSInteger root,
                                NSInteger degree) {
  if (degree == 7 || degree == -7)
    return pitch + degree / 7 * 12;
  const int scale[] = {0, 2, 4, 5, 7, 9, 11};
  NSInteger relative = pitch - root, octave = (NSInteger)floor(relative / 12.0),
            pc = relative - octave * 12;
  NSInteger index = 0;
  for (NSInteger i = 1; i < 7; i++)
    if (abs((int)pc - scale[i]) < abs((int)pc - scale[index]))
      index = i;
  NSInteger target = index + degree,
            targetOctave = (NSInteger)floor(target / 7.0),
            targetIndex = target - targetOctave * 7;
  return root + (octave + targetOctave) * 12 + scale[targetIndex];
}
extern NSMenu *installRendering(NSString *root);
extern NSMenu *installConversion(NSString *root);
extern NSMenu *installNativeOptions(NSString *root);
extern NSMenuItem *installSpectrum(void);

@interface VPPatcher : NSObject
@property NSTimer *timer;
@property NSTimer *saveTimer;
@property BOOL autosaveBusy;
@property NSMenu *menu;
@end
@implementation VPPatcher
- (void)replaceLyrics:(id)sender {
  NSString *text = VPAsk(VPUIString(@"将选中音符的歌词全部替换为"), @"a");
  if (!text.length)
    return;
  VPEdit(VPUIString(@"歌词替换"), NO, ^BOOL(NSArray *notes) {
    for (id<VPNote> note in notes)
      if (![note setLyric:text])
        return NO;
    return YES;
  });
}
- (void)quantize:(id)sender {
  NSString *text =
      VPAsk(VPUIString(@"量化时值，输入网格 tick（四分=480）、强度百分比"),
            [NSString stringWithFormat:@"%ld,100", (long)VPCurrentGrid()]);
  if (!text)
    return;
  NSArray *components = [text componentsSeparatedByString:@","];
  NSScanner *scanner =
      [NSScanner scannerWithString:components.firstObject ?: @""];
  long long grid;
  NSScanner *strengthScanner =
      [NSScanner scannerWithString:components.count == 2 ? components[1] : @""];
  double strength;
  if (components.count != 2 || ![scanner scanLongLong:&grid] ||
      !scanner.isAtEnd || grid < 1 || grid > 1920 ||
      ![strengthScanner scanDouble:&strength] || !strengthScanner.isAtEnd ||
      !isfinite(strength) || strength < 0 || strength > 100) {
    VPAlert(VPUIString(@"网格请输入 1 到 1920 的整数，强度请输入 0 到 100。"));
    return;
  }
  VPEdit(VPUIString(@"量化时值"), NO, ^BOOL(NSArray *notes) {
    for (id<VPNote> note in notes) {
      int64_t duration = [note duration].value;
      int64_t quantized =
          MAX(grid, VPRoundToEven((double)duration / grid) * grid);
      VPTick target = {MAX(1, VPRoundToEven(duration + (quantized - duration) *
                                                           strength / 100))};
      if (![note setDuration:target])
        return NO;
    }
    return YES;
  });
}
- (void)swing:(NSMenuItem *)sender {
  NSInteger unit = (sender.tag < 2 ? 240 : 120);
  double ratio = (sender.tag % 2 ? 2.0 / 3.0 : 0.6);
  VPEdit(VPUIString(@"摇摆"), NO, ^BOOL(NSArray *notes) {
    NSArray *ordered = [notes sortedArrayUsingComparator:^NSComparisonResult(
                                  id<VPNote> a, id<VPNote> b) {
      return [a posTick].value > [b posTick].value ? NSOrderedAscending
                                                   : NSOrderedDescending;
    }];
    double (^map)(int64_t) = ^double(int64_t tick) {
      int64_t pair = unit * 2, base = tick / pair * pair, offset = tick - base;
      return base + (offset < unit ? offset * ratio * 2
                                   : unit * ratio * 2 +
                                         (offset - unit) * (1 - ratio) * 2);
    };
    for (id<VPNote> note in ordered) {
      int64_t tick = [note posTick].value, end = tick + [note duration].value;
      VPTick target = {VPRoundToEven(map(tick))},
             duration = {MAX(1, VPRoundToEven(map(end)) - target.value)};
      if (![(id<VPPart>)[note parent] moveNote:target note:note] ||
          ![note setDuration:duration])
        return NO;
    }
    return YES;
  });
}
- (void)harmony:(id)sender {
  NSString *text = VPAsk(VPUIString(@"和声，根音 MIDI、级数偏移（2 至 7 或 -2 "
                                    @"至 -7）、新轨道=1/空闲轨道=0"),
                         @"60,2,1");
  if (!text)
    return;
  NSArray *items = [text componentsSeparatedByString:@","];
  long long values[3];
  BOOL valid = items.count == 3;
  for (NSUInteger i = 0; valid && i < 3; i++) {
    NSScanner *s = [NSScanner scannerWithString:items[i]];
    valid = [s scanLongLong:&values[i]] && s.isAtEnd;
  }
  if (!valid || values[0] < 0 || values[0] > 127 || labs(values[1]) < 2 ||
      labs(values[1]) > 7 || values[2] < 0 || values[2] > 1) {
    VPAlert(VPUIString(@"请输入有效参数。级数偏移可用 ±2 至 ±7。"));
    return;
  }
  NSInteger root = values[0], degree = values[1];
  BOOL forceNew = values[2] != 0;
  VPEdit(VPUIString(@"生成和声"), YES, ^BOOL(NSArray *notes) {
    id<VPPart> source = VPObjectIvar(VPModel(), "activePart");
    id<VPTrack> sourceTrack = [source parentTrack];
    id<VPSequence> seq = VPSequenceObject();
    id<VPTrack> target = nil;
    int64_t lo = [source absPosTick].value, hi = lo + [source duration].value;
    if (!forceNew)
      for (NSUInteger i = 0; i < [seq numTrack]; i++) {
        id<VPTrack> candidate = [seq track:i];
        if ([candidate isEqual:sourceTrack] ||
            ![candidate respondsToSelector:@selector(voiceBankID)])
          continue;
        BOOL overlap = NO;
        for (NSUInteger j = 0; j < [candidate numPart]; j++) {
          id<VPPart> p = [candidate part:j];
          int64_t begin = [p absPosTick].value;
          if (begin < hi && begin + [p duration].value > lo) {
            overlap = YES;
            break;
          }
        }
        if (!overlap) {
          target = candidate;
          break;
        }
      }
    if (!target) {
      if ([seq numTrack] >= [seq maxNumTrack])
        return NO;
      target = [seq insertMidiTrack:[seq numTrack]
                               name:VPUIString(@"和声")
                               type:[sourceTrack type]];
      if (!target || ![target setVoiceBankID:[sourceTrack voiceBankID]])
        return NO;
    }
    id<VPPart> harmony = [target duplicatePart:[source absPosTick] part:source];
    if (!harmony)
      return NO;
    NSMutableSet *keep = [NSMutableSet set];
    for (id<VPNote> n in notes)
      [keep addObject:[NSString stringWithFormat:@"%lld/%ld", [n posTick].value,
                                                 (long)[n noteNumber]]];
    for (NSUInteger j = [harmony numNote]; j > 0; j--) {
      id<VPNote> n = [harmony note:j - 1];
      NSString *key = [NSString stringWithFormat:@"%lld/%ld", [n posTick].value,
                                                 (long)[n noteNumber]];
      if (![keep containsObject:key]) {
        if (![harmony removeNote:n])
          return NO;
        continue;
      }
      NSInteger pitch =
          MAX(0, MIN(127, VPHarmonyPitch([n noteNumber], root, degree)));
      if (![n setNoteNumber:pitch])
        return NO;
    }
    return YES;
  });
}
- (void)snapshot:(id)sender {
  NSDocument *doc = VPCurrentDocument();
  if (!doc) {
    VPAlert(VPUIString(@"请先打开工程。"));
    return;
  }
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.nameFieldStringValue = @"Patcher-snapshot.vprx";
  if ([panel runModal] != NSModalResponseOK)
    return;
  NSError *error = nil;
  if (![doc writeToURL:panel.URL ofType:doc.fileType error:&error])
    VPAlert(error.localizedDescription ?: VPUIString(@"保存副本失败。"));
}
- (void)changeLanguage:(NSMenuItem *)item {
  NSString *language = item.representedObject;
  VPLoadLanguage(language);
  VPStoreSetting(@"language", language);
  for (NSMenuItem *other in item.menu.itemArray)
    other.state =
        other == item ? NSControlStateValueOn : NSControlStateValueOff;
  [self refresh:nil];
}
- (void)toggleAutosave:(NSMenuItem *)item {
  [self.saveTimer invalidate];
  self.saveTimer = nil;
  if (item.state == NSControlStateValueOn) {
    item.state = NSControlStateValueOff;
    VPStoreSetting(@"autoSaveMinutes", @0);
    return;
  }
  NSString *text = VPAsk(VPUIString(@"自动保存间隔（分钟）"), @"5");
  if (!text)
    return;
  NSScanner *scanner = [NSScanner scannerWithString:text];
  double minutes;
  if (![scanner scanDouble:&minutes] || !scanner.isAtEnd ||
      !isfinite(minutes) || minutes < 1 || minutes > 120) {
    VPAlert(VPUIString(@"请输入 1 到 120 分钟。"));
    return;
  }
  self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:minutes * 60
                                                    target:self
                                                  selector:@selector(autosave:)
                                                  userInfo:nil
                                                   repeats:YES];
  item.state = NSControlStateValueOn;
  VPStoreSetting(@"autoSaveMinutes", @(minutes));
}
- (void)autosave:(id)sender {
  NSDocument *doc = VPCurrentDocument();
  id<VPSequence> sequence = VPObjectIvar(VPObjectIvar(doc, "sequence"), "vsmSequence");
  if (getenv("VOCALOID_PATCHER_TEST_PROJECT"))
    NSLog(@"VP_AUTOSAVE_TEST file=%d dirty=%d staged=%d modal=%d sheet=%d", doc.fileURL != nil,
          [sequence isDirty], [sequence isStaged], NSApp.modalWindow != nil,
          NSApp.keyWindow.attachedSheet != nil || NSApp.keyWindow.sheetParent != nil);
  if (self.autosaveBusy || !doc.fileURL ||
      ![doc.fileURL.pathExtension.lowercaseString isEqualToString:@"vprx"] ||
      ![sequence isDirty] || [sequence isStaged] || NSApp.modalWindow ||
      NSApp.keyWindow.attachedSheet || NSApp.keyWindow.sheetParent)
    return;
  for (NSWindowController *controller in doc.windowControllers)
    if (controller.window.attachedSheet) return;
  self.autosaveBusy = YES;
  [doc saveToURL:doc.fileURL ofType:doc.fileType forSaveOperation:NSSaveOperation
      completionHandler:^(NSError *error) {
        self.autosaveBusy = NO;
        if (getenv("VOCALOID_PATCHER_TEST_PROJECT")) NSLog(@"VP_AUTOSAVE_TEST completed=%d", error == nil);
        if (error) VPAlert(error.localizedDescription);
      }];
}
- (void)refresh:(id)sender {
  if (VPTranslations) {
    VPTranslateMenu(NSApp.mainMenu);
    for (NSWindow *window in NSApp.windows)
      VPTranslateView(window.contentView);
  }
}
- (void)install {
  self.menu = [[NSMenu alloc] initWithTitle:@"VOCALOID Patcher"];
  NSArray *titles = @[
    VPUIString(@"界面语言"), VPUIString(@"替换选中音符歌词…"),
    VPUIString(@"量化选中音符时值…"), VPUIString(@"生成和声…"),
    VPUIString(@"八分音符 Swing"), VPUIString(@"八分音符 Shuffle"),
    VPUIString(@"十六分音符 Swing"), VPUIString(@"十六分音符 Shuffle"),
    VPUIString(@"自动保存…"), VPUIString(@"保存工程副本…")
  ];
  SEL actions[] = {@selector(changeLanguage:), @selector(replaceLyrics:),
                   @selector(quantize:),       @selector(harmony:),
                   @selector(swing:),          @selector(swing:),
                   @selector(swing:),          @selector(swing:),
                   @selector(toggleAutosave:), @selector(snapshot:)};
  for (NSUInteger i = 0; i < titles.count; i++) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i]
                                                  action:actions[i]
                                           keyEquivalent:@""];
    item.target = self;
    item.tag = i >= 4 && i <= 7 ? i - 4 : i;
    [self.menu addItem:item];
  }
  NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"VOCALOID Patcher"
                                                action:nil
                                         keyEquivalent:@""];
  root.submenu = self.menu;
  NSMenu *languages = [[NSMenu alloc] initWithTitle:VPUIString(@"界面语言")];
  NSArray *languageCodes = @[ @"zh-Hans", @"zh-Hant", @"en", @"ja", @"es" ];
  NSArray *languageNames = @[
    VPUIString(@"简体中文"), VPUIString(@"繁體中文"), @"English",
    VPUIString(@"日本語"), @"Español"
  ];
  for (NSUInteger i = 0; i < languageCodes.count; i++) {
    NSMenuItem *item =
        [[NSMenuItem alloc] initWithTitle:languageNames[i]
                                   action:@selector(changeLanguage:)
                            keyEquivalent:@""];
    item.target = self;
    item.representedObject = languageCodes[i];
    [languages addItem:item];
  }
  [self.menu itemAtIndex:0].submenu = languages;
  for (NSMenu *submenu in @[
         installRendering(VPRoot) ?: [NSMenu new],
         installConversion(VPRoot) ?: [NSMenu new],
         installNativeOptions(VPRoot) ?: [NSMenu new]
       ]) {
    if (!submenu.numberOfItems)
      continue;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:submenu.title
                                                  action:nil
                                           keyEquivalent:@""];
    item.submenu = submenu;
    [self.menu addItem:item];
  }
  [self.menu addItem:installSpectrum()];
  [NSApp.mainMenu addItem:root];
  NSNumber *storedMinutes = VPSettings()[@"autoSaveMinutes"];
  if ([storedMinutes isKindOfClass:NSNumber.class] &&
      isfinite(storedMinutes.doubleValue) && storedMinutes.doubleValue >= 1 &&
      storedMinutes.doubleValue <= 120) {
    self.saveTimer =
        [NSTimer scheduledTimerWithTimeInterval:storedMinutes.doubleValue * 60
                                         target:self
                                       selector:@selector(autosave:)
                                       userInfo:nil
                                        repeats:YES];
    [self.menu itemAtIndex:8].state = NSControlStateValueOn;
  }
  self.timer = [NSTimer scheduledTimerWithTimeInterval:1
                                                target:self
                                              selector:@selector(refresh:)
                                              userInfo:nil
                                               repeats:YES];
  NSLog(@"VOCALOIDPatcher macOS loaded on %@", VP_EDITOR_VERSION);
}
@end
static VPPatcher *VPPatcherInstance;
__attribute__((constructor)) static void VPInitialize(void) {
  @autoreleasepool {
    NSString *version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isEqualToString:VP_EDITOR_VERSION] || !VPSupportedEditor())
      return;
    const char *root = getenv("VOCALOID_PATCHER_ROOT");
    if (!root)
      return;
    VPRoot = [NSString stringWithUTF8String:root];
    NSDictionary *settings = [NSDictionary
        dictionaryWithContentsOfFile:
            [VPRoot stringByAppendingPathComponent:@"settings.plist"]];
    NSString *language = [@[ @"zh-Hans", @"zh-Hant", @"en", @"ja", @"es" ]
                             containsObject:settings[@"language"]]
                             ? settings[@"language"]
                             : @"zh-Hans";
    VPLoadLanguage(language);
    Method localized = class_getInstanceMethod(
        NSBundle.class, @selector(localizedStringForKey:value:table:));
    VPBundleOriginal = method_setImplementation(localized, (IMP)VPLocalize);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                     if (NSApp.mainMenu) {
                       VPPatcherInstance = [VPPatcher new];
                       [VPPatcherInstance install];
                     }
                   });
  }
}
