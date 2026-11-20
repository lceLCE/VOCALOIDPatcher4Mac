# VOCALOIDPatcher4Mac

[English](README.en.md) · [构建说明](docs/BUILDING.md) · [适配指南 / Porting guide](docs/ADAPTING.md) · [验证与差异](docs/VALIDATION.md)

[IzumiiKonata/VOCALOIDPatcher](https://github.com/IzumiiKonata/VOCALOIDPatcher) 的 macOS 原生移植试用版，使用 Objective-C、AppKit 和本地 Python 转换器。源码按 GPL-3.0 开源，允许构建、修改和按许可再分发。

**当前只验证了 Apple Silicon、macOS 15+、VOCALOID7 Editor 7.0.0 的一个特定构建，尚未达到 Windows 全功能等价。** 版本号相同也可能有不同可执行文件；启动器会检查完整 SHA-256。不匹配时请按[适配指南](docs/ADAPTING.md)核验私有接口，不能只修改哈希。

## 从源码构建

准备 Xcode Command Line Tools、[uv](https://github.com/astral-sh/uv)，以及自行安装的 VOCALOID7 Editor。Python 3.12 和固定依赖由 uv 创建在本地目录。

```sh
git clone https://github.com/lceLCE/VOCALOIDPatcher4Mac.git
cd VOCALOIDPatcher4Mac
./build.command
./conversion/setup.command
./check.command
```

要让原来的 V7 图标默认加载汉化，退出编辑器后执行一次安装：

```sh
python3 install.py install
```

安装后日常直接打开 `/Applications/VOCALOID7 Editor.app`，不用终端或额外启动器。安装会备份原应用，并保留其完整原生包；还原用 `python3 install.py restore`。只支持当前用户，更新编辑器后需要重新验证、安装。

默认编辑器位置为 `/Applications/VOCALOID7 Editor.app`。也可在构建后双击生成的 `VOCALOID7 Patcher.app`。保持生成的 app、动态库、localization/ 和 conversion/ 在完整仓库目录中。启动前先退出已有编辑器；普通方式启动原应用可恢复原生界面。补丁不改写原应用文件。

## 功能范围

- 五语言界面、macOS 顶部菜单和子菜单汉化。
- 音高标签、其他轨道音符轮廓、静音轨道过滤、歌词居中、圆角音符。
- 按声库配置图片、GIF、静音循环视频立绘。
- 歌词批量替换、网格时值量化、调内和声、Swing / Shuffle。
- 工程格式转换、字幕导出、中文转拼音；27 种格式入口，包括 MIDI。
- 定时保存已有 VPRX 工程、实时输出频谱、V6 工具栏配色、波形透明度和 SV 波形样式、预览刷新合并。

AU/VST 宿主、Intel、属性面板右置、部分 Windows 性能补丁和同时选择多个和声级数尚未实现。第三方格式的 V7 专用合成参数不保证无损。详细范围见[验证记录](docs/VALIDATION.md)，不要把编译成功当成新版本适配通过。

## 参与适配

[Compatibility.h](Compatibility.h) 集中当前版本、摘要、Swift 入口地址和原生调用返回地址。[docs/ADAPTING.md](docs/ADAPTING.md) 说明如何核验新目标的 ABI、地址、对象字段和真实工程行为。无需 VOCALOID SDK 即可编译补丁，但运行和验证需要本地编辑器及可用声库；仓库不提供编辑器、声库或测试工程。

提交适配时附上目标版本、CPU、完整摘要、各功能验证结果和已知缺口。修改与再分发请保留 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。
