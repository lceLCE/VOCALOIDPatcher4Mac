# 原生布局与性能选项调查

目标程序为本机 VOCALOID7 Editor 7.0.0 universal 可执行文件，SHA-256 为 `eb9440ffedc2bcd00f897dab57007767d59a64032e7489c0cf1a5546c1d0ba92`。以下结果来自上游提交 `e3208fd798d432ae1bf1141bf8f741fbd6fac30f`、本机符号清单、已采集的 Objective-C 运行时 ABI。调查不改变编辑器的授权或音频引擎行为。

## 本模块实现

`NSMenu *installNativeOptions(NSString *root)` 提供“V6 深色工具栏与标题栏”开关，默认关闭。使用与上游一致的 `#171819` 工具栏背景和 `#2D2D30` 标题栏背景。NSWindow 使用系统 Dark Aqua 外观。原生工具栏已观察到的 `backgroundColor` 强 NSColor 字段由 ARC 更新，恢复时写回原颜色。仅精确匹配的主工具栏和编辑器工具栏参与修改。原程序摘要不匹配时整个模块不安装。

状态存储在补丁目录 `native-options.json`。当前编译验证通过，实际工具栏覆盖范围、标题栏显示和切回后的视觉结果仍需独立运行时 QA。macOS 系统菜单栏由系统管理，Windows DWM 标题栏接口没有对应调用。

## Inspector 右置：未支持，已从交付移除

真实 VOCALOID7 UI 验收失败。实验版本在 Inspector 轨道/音符内容切换、Browser 开关、文件面板之后出现左侧空白、track/piano header 缩到17/0 pt；后续保护措施又导致 header 扩大到约1204/1207 pt，遮住时间尺或钢琴网格。独立 NSSplitView/mock 检查通过，无法代表真实原生布局正确。

当前交付源已彻底删除 Inspector 菜单、设置读写、布局 swizzle、divider/约束映射、重排和诊断定时路径，不提供隐藏开关或实验开关。旧 inspectorOnRight 配置字段不再读取。外层原生布局完全交回 VOCALOID。失败的实验实现不包含在此稳定源码中。该项仍是 Windows 功能对齐的明确缺口。

## 波形选项

波形透明度已实现精确的 CGContextSetRGBStrokeColor interpose，原生 piano drawRenderedWave 的调用返回 PC 固定为 `0x100100f00`，只在此点将 alpha 乘用户设置的 0–1 比例，其他绘图调用不变。主程序 slide 通过查找 MH_EXECUTE 取得，避免 DYLD 插件成为 image 0 时取错 slide。默认保持 1，支持百分比输入与持久化，修改后使钢琴窗重绘。

SV 波形样式已实现，默认关闭。已在真实编辑器中验证组基线和实际映射日志。静态反汇编确认原生 waveCenterY 在 `0x10010133c` 通过 sampleIndex/256 取得当前帧 score 首个 float（pitch），用 float32 `(pitch + 6900) / 100` 得到当前音符行。Windows SV 规则会预扫描所有帧，分成音高跨度不超过 7 个半音的组，以组最低音下方 3.5 行为基线。新实现复用原采样及原生已选择的帧，通过 scoped scoreAtIndex 捕获帧号和 pitch，并且只重映射 `0x100101250`、`0x10010128c`、`0x1001012ac` 三处原生 waveform stroke path 的坐标。组边界断开连接并绘制前后 24 像素淡出重影。

分组缓存以 scoreList 弱引用、rawState、帧数和 renderer/activePart 通知 generation 失效。4,000,000 帧上限与上游一致。原生几何缺失、score 缺失或乐段尚未形成有效 rendered wave 时保留原生绘制。波形幅度保留 Mac 原生尺度，上游源代码没有 RenderedWaveHeight 与 KeyBaseHeight 的常量定义，幅度尺度尚未验证与 Windows 一致。生成过程中使用的部分 score 仍由原生路径显示，直到完整 rendered wave 有效。

几何使用另一个模块导出的 VPRenderingNoteRect。已验证原生 rectOf 返回 rowTop+1 和 rowHeight-2，以此恢复行中心。原生初始三音符截图中波形分别位于 C3、D3、E3，符合逐帧音高定位的静态分析，不能将原生波形直接算作 SV 样式等价。

## 性能清单

所有性能项仍需测量和独立验收，以下静态发现不代表 Windows 补丁已移植，也不代表两端性能相等。

| Windows 选项 | 上游作用 | 本机证据与当前状态 |
| --- | --- | --- |
| 加快工程加载 | 后台加载伴奏缓冲、取消过期任务，部分界面延迟刷新 | 存在 `AudioPartCacheManager.addAllAudioBuffer(vsmSequence:)` 与 `audioBuffers`。没有验证加载线程与取消语义，保持原生实现。 |
| 释放音频 PCM 缓存 | 清空 .NET WaveFile 原始数据并改用已有缩略数据 | Mac `AugmentedAudioBuffer` 有 `pcmBufferL/R` 与 `thumbsMin/MaxL/R`。Swift 数组所有权和消费者仍未验证，未释放任何原生缓冲。 |
| 优化轨道区域渲染 | 合并、缓存 WPF 轨道控件重绘 | Mac 使用 `VETrackBodyView` 和 AppKit 绘制。未建立相同热点和失效语义，未加入替代缓存。 |
| 加快选区清除 | 避免遍历未选中的 WIVSM 时间/速度/断点对象 | 原生 `ComYamahaVSM7WrapOCIVSMNote.select:` 已有接口。跨类型选区跟踪与撤销语义仍待验证。 |
| 延后参数面板刷新 | 通过 WPF Dispatcher 合并 ActiveTrack/ActivePart Changed | Mac 有多个图形与 Inspector 控制器。未确认可安全合并的通知载荷和顺序。 |
| 已渲染波形缓存 | 以路径和乐段为键后台加载，维护 1/4 条 LRU | Mac 本来具有 `RenderedWaveCacheManager.waveDictionary` 和 `sampleEnumerator(part:)`。方法0x10006c720–9ac实际验证hasValidRenderedWave、part.unwrap和waveFilePath，命中同path返回缓存，无效时removeValue，miss同步加载，成功后清空原字典再插入当前entry。因此确认原生capacity1缓存复用，后台加载/4条LRU增强仍未移植。 |
| 加快乐段切换 | 按变化类型选择性重绘 WPF 图层 | Mac 已有不同 drawRect 与 renderer/selection 通知入口。没有对真实乐段切换的绘制次数做测量。 |
| 平滑播放指示条 | 将 WPF DispatcherTimer 改为 CompositionTarget.Rendering | 原生复用。beginAudioPlayObserving在0x10020c8a8–944创建1/60秒NSTimer并加入mainRunLoop CommonModes。refreshSongPosition只在standalone播放且engine currentTime改变时将time换算tick并更新sequence currentPosition，无音频start/stop调用。需播放拖动视觉验收。 |
| 优化合成预览刷新 | 将 OnRendererBlockRendered 限制到 30 fps | 已实现Mac等价选项。原生通知处理完整执行，仅对0x10025b668/6d0/700三处setNeedsDisplay:YES合并30fps刷新。保留末次延迟刷新，renderComplete/cancel/activePart立即flush，直接交互不节流。 |

## 编译验证

已执行 `xcrun clang -fobjc-arc -Wall -Wextra -Werror -c NativeOptions.m -o .check-build/NativeOptions.o`，通过且没有警告。

本模块使用系统框架，不修改原 App 文件。

额外原生断言检查已通过。使用合成 scoreList 对实际 VPSVBuildCache 执行 7 半音分组、unused frame 保留、rawState 改变失效、renderer generation 改变失效，以及超过 4M 帧拒绝检查。运行产物为 .check-build/NativeOptions-check，可直接重跑。此检查不启动编辑器，也不代表绘制或布局运行时验收。

## 补充性能证据与边界

- RenderedWaveCacheManager.sampleEnumerator(part:) 的命中路径为0x10006c79c–808，key是part.unwrap，比较缓存path与当前waveFilePath。无效波形0x10006c844–898移除entry。miss 0x10006c8c8–8f4同步加载AugmentedAudioBuffer(path:)，成功0x10006c900–910清空旧缓存后插入，因此是实际容量1。
- ScoreCache.scoreFile(part:) 0x10004438c–614具有对应的hasValidRenderedScore、scoreFilePath、unwrap key查找、同path复用、无效removeValue和miss loadScoreFile路径。新score成功时也清空旧字典再写当前entry。
- AudioPartCacheManager.addAllAudioBuffer(vsmSequence:) 0x10014b29c–644遍历音轨/乐段并同步调用AugmentedAudioBuffer(path:)。没有在这条路径看到后台dispatch。直接把整个方法转到后台会与未加锁的Swift audioBuffers字典消费者并发，需要先建立全部读写边界。
- Mac AugmentedAudioBuffer字段包含L/R PCM缓冲、四组缩略数组、sampleRate、channelCount和path，没有Windows补丁针对的WaveFile.waveData持有字段。初始化方法0x10004cc90–7bc使用临时AVAudioFile、转换输入PCMBuffer和输出L/R PCMBuffer，退出0x10004d6e8–704释放临时文件/转换对象。尚未证明每个AVAudioFile框架内部是否提前释放解码缓存，不能据此声称所有活跃PCM均可释放。
- 新增手动“释放闲置堆内存”，调用macOS公开malloc_zone_pressure_relief(NULL,0)，报告分配器返回字节数。它回收allocator已空闲页，不能算作Windows活跃PCM缓存释放补丁的完全等价。
- preview合并的实际函数已用独立原生断言检查验证。30个紧接请求共用一个trailing flush，首次leading flush保留，完成时flush及重复flush幂等。运行时计数API为VPPreviewCoalescedRequests。

## 保留功能的独立检查

可复现检查源为 `check_native_options.m`，仅检查当前交付实现中的 SV 分组、缓存失效、帧数上限和预览合并/最终 flush。已删除不具运行时代表性的 Inspector mock 检查。

```sh
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework AppKit -framework CoreGraphics -framework QuartzCore check_native_options.m -o .check-build/NativeOptions-check
.check-build/NativeOptions-check
```

移除布局代码后，严格编译和全部保留断言再次通过；该检查不启动编辑器，不替代实际 UI 验收。
