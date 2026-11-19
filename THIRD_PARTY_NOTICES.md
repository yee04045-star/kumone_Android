# 第三方来源与许可说明

本文件是人工核查清单，不是完整依赖许可证清单，也不替代各组件的完整许可证正文。

## Kumone

- 上游：https://github.com/missuo/kumone
- 用途：Swift 原工程 API、模型、播放行为和 UI 信息架构的迁移依据。
- 上游标注：LGPL-3.0-only。
- 保留文件：[LICENSE](LICENSE)、[COPYING](COPYING)。
- Flutter / Android 迁移及界面、平台交互、自定义音源配置属于本工程的修改；并非上游官方 Android 发布。
- 上游 README 另有 learning/personal use 表述，应就其与标准许可证的关系向权利人确认，不在此自行改写标准许可或作商用承诺。

## liquid_glass_easy

- 上游：https://github.com/AhmeedGamil/liquid_glass_easy
- 用途：本地集成的玻璃视觉及交互组件。
- 许可：MIT；Copyright (c) 2025 Ahmed Gamil。
- 完整原文：[packages/liquid_glass_easy/LICENSE](packages/liquid_glass_easy/LICENSE)。
- 本工程包含本地适配，不应将全部本地代码描述为与上游某一版本逐字一致。

## miniaudio_player

- 上游：https://github.com/chomusuke-mk/miniaudio_player
- 原参考版本：pub 3.0.2。
- 用途：双播放器交叉淡入淡出生命周期及等功率曲线参考，见 `lib/core/player/crossfade_curve.dart`。
- 未集成 miniaudio 音频引擎；实际播放仍使用 just_audio。
- 完整 MIT 通知保留在 [third_party/licenses/MINIAUDIO_PLAYER_MIT.txt](third_party/licenses/MINIAUDIO_PLAYER_MIT.txt)。

## decent-player

- 现有源码注释所列上游：https://github.com/Ma145/decent-player
- 涉及 `tooling/just_audio_usb/` 中 USB 设备、独占输出和音频 Sink 等参考／派生代码。
- 许可：MIT；Copyright (c) 2026 Marcelo Silva。已从上游 GitHub API 获取并原样保留完整许可：[third_party/licenses/DECENT_PLAYER_MIT.txt](third_party/licenses/DECENT_PLAYER_MIT.txt)。
- 许可来源：https://api.github.com/repos/Ma145/decent-player/license 。许可 Git blob SHA-1：`cf8da322c0fbb7de78fe6796141d399c5cd7b32c`；已按 Git blob 算法校验下载内容。
- 许可文件 SHA-256：`a2d97c249c413ebdd2f27b4f70e908a2b6c6d09d73e62d7d7ae32778249073e9`。
- 本次查询时的上游提交：`d039f9d6b1ec30901a5cd6edf72c29cde362a549`。这是查询基准，**不是本工程最初引入代码所对应提交的认定**；原始引入提交未记录，仍待补充来源追踪。
- 本工程针对 Flutter / just_audio 的 Android 集成进行了适配，涉及 USB 设备选择、Java 音频 Sink、独占控制、原生输出及构建补丁；并非未经修改的完整上游应用。原源码版权注释保留。发行 APK 时亦需携带适用通知。

## 其他运行与构建依赖

Flutter、Dart、just_audio、audio_service、audio_session、Dio、Provider、安全存储、图片缓存、注音等依赖见 `pubspec.yaml`、`pubspec.lock`；Android 的 Media3、Gradle 等依赖还需在生成工程及最终 APK 上盘点。

发布者应生成依赖清单，收集每个实际分发组件的许可证和通知，确认所需源码、修改说明与二进制通知。Flutter 自动汇集的许可信息不应被假定为覆盖本地补丁、原生依赖和手工集成代码的全部义务。

## 非代码内容

图标、截图、封面、歌词、音乐、名称及商标不能一概按项目代码许可处理。人物彩蛋资源已删除，但剩余九款图标、旧截图和其他图片仍需确认作者与授权。主题颜色名称不表示平台合作或背书。
