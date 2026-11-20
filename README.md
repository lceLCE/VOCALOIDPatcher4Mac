# VOCALOIDPatcher4Mac

**[完整使用说明](docs/USER-GUIDE.md) · [English](README.en.md) · [安装与恢复](docs/INSTALLING.md) · [版本适配](docs/ADAPTING.md) · [验证与限制](docs/VALIDATION.md)**

[IzumiiKonata/VOCALOIDPatcher](https://github.com/IzumiiKonata/VOCALOIDPatcher) 的 macOS 原生移植试用版。使用 Objective-C、AppKit 和本地 Python 转换器，按 [GPL-3.0](LICENSE) 开源。

安装完成后，**直接打开原来的 VOCALOID7 Editor 图标即可加载汉化和补丁，退出重开仍然生效**。首次从源码构建、安装需要终端，日常使用不需要命令行或另外的启动器。

## 当前支持范围

| 项目 | 已验证目标 |
| --- | --- |
| 芯片 / 系统 | Apple Silicon，macOS 15 或更新版本 |
| 编辑器 | VOCALOID7 Editor 7.0.0 的一个特定原生可执行文件 |
| SHA-256 | `eb9440ffedc2bcd00f897dab57007767d59a64032e7489c0cf1a5546c1d0ba92` |
| 安装范围 | 当前 macOS 用户，默认 `/Applications/VOCALOID7 Editor.app` |
| 发布内容 | 源码、语言包、构建与检查脚本；不含编辑器、声库或预编译完整应用 |

版本号相同也可能是不同构建。摘要不匹配时安装器会拒绝修改；其他版本按[适配指南](docs/ADAPTING.md)核验，不能只改哈希。目前尚未达到 Windows 全功能等价。

## 首次安装

先安装 Xcode Command Line Tools 和 [uv](https://docs.astral.sh/uv/getting-started/installation/)，并自行安装可正常使用的原版编辑器。详细准备、预期结果和故障处理见[完整手册](docs/USER-GUIDE.md)。

```sh
git clone https://github.com/lceLCE/VOCALOIDPatcher4Mac.git
cd VOCALOIDPatcher4Mac
./build.command
./conversion/setup.command
./check.command
```

保存工程并完全退出 V7，然后执行一次：

```sh
conversion/.venv/bin/python install.py install
```

安装器先保留完整原版备份，再安装应用内加载入口；原生编辑器字节不变，应用包执行深度签名校验。补丁和设置复制到当前用户的 Application Support，安装后日常启动不依赖源码目录。**请从原应用图标打开，不要直接打开内部 Native 应用或备份副本。**

## 功能

- 简中、繁中、英语、日语、西语界面；包含 macOS 顶部菜单及子菜单汉化。
- 音高标签、其他轨道音符轮廓、静音轨道过滤、歌词居中、圆角音符。
- 按声库设置图片、GIF、静音循环视频立绘及大小、透明度、位置。
- 批量替换歌词、时值量化、调内和声、八分／十六分 Swing 和 Shuffle。
- 27 个工程／字幕转换入口，另支持 VPRX 导入及 MXL 别名、中文转拼音。
- 已保存 VPRX 的定时保存、实时输出频谱、V6 工具栏配色、波形透明度、SV 波形、预览刷新合并。

每个菜单的操作和参数示例见[完整使用说明](docs/USER-GUIDE.md)。AU/VST 宿主、Intel、属性面板右置、部分 Windows 性能优化和多和声级数同时勾选尚未支持；V7 专用合成参数跨格式不保证无损。

## 更新与恢复

**源码更新不会自动替换已安装补丁。** 保存并退出 V7，按[手册的更新流程](docs/USER-GUIDE.md#更新与恢复)先恢复，再更新源码、构建、检查和安装。升级编辑器之前也应先恢复；新构建需要重新验证。

从本仓库恢复原版：

```sh
conversion/.venv/bin/python install.py restore
```

源码目录已经移走时，使用[独立恢复入口](docs/INSTALLING.md#restore)。恢复保留设置和备份；若应用被外部修改，安装器会拒绝自动覆盖。

## 文档与贡献

- [完整使用说明（中文）](docs/USER-GUIDE.md) / [Full user guide (English)](docs/USER-GUIDE.en.md)
- [构建细节](docs/BUILDING.md)、[安装结构与恢复](docs/INSTALLING.md)
- [新版本适配与 ABI 验证](docs/ADAPTING.md)、[兼容常量](Compatibility.h)
- [验证记录](docs/VALIDATION.md)、[原生性能边界](docs/NATIVE-OPTIONS.md)
- [许可证](LICENSE)、[上游与依赖署名](NOTICE.md)

欢迎提交问题和适配贡献。请附版本、CPU、原生摘要、最小复现和脱敏错误，不要上传编辑器、声库、私人工程、备份或凭据。构建成功并不代表新版本的私有接口已经通过运行时验证。
