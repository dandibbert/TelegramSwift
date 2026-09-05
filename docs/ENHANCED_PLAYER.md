# Enhanced Media Player / 播放器增强

This fork keeps Telegram's streaming/cache/decoder backends. It changes player
input, controls and presentation rather than replacing them with mpv.

## 使用

打开视频后即可使用。Telegram 设置中新增「播放器」，视频速度菜单中也有
「播放器设置」。设置窗口有控制、快捷键、窗口三个分页，修改立即保存。

| 默认键 | 操作 |
| --- | --- |
| Space | 播放 / 暂停 |
| ← / → | 后退 / 前进 5 秒 |
| ⌘← / ⌘→ | 精细跳转 1 秒 |
| ⇧← / ⇧→ | 大步跳转 30 秒 |
| ↑ / ↓ | 音量 ±5% |
| M | 静音 / 恢复之前音量 |
| [ / ] | 倍速 ±0.1× |
| \\ | 恢复 1× |
| 按住 Tab | 临时 2×，松开恢复原速 |
| F | 全屏 |
| D | 独立播放器 / 返回媒体浏览器 |
| P | 迷你画中画 / 完整独立窗口 |
| T | 只置顶播放器 |
| ⌥← / ⌥→ | 上一个 / 下一个媒体（媒体浏览器中） |
| ⌘, | 播放器设置 |
| Esc | 先退出全屏，再返回媒体浏览器，最后关闭媒体浏览器 |

所有操作均可重绑，支持组合修饰键（含由 Karabiner 发出的 Hyper），冲突会被提示。
快捷键按物理键位记录；不同键盘布局上的显示名称可能与实际键帽不同。
不安装全局键盘监听，不申请辅助功能或输入监控权限。只有播放器所属窗口收到的
事件会被处理，不会抢走聊天/搜索/设置输入框的方向键。图片浏览保持原来的翻页。

普通/精细/大步跳转、音量/速度步长、临时倍速可调。连续跳转按目标位置累计，
每 70 毫秒最多提交一次 seek；拖动时间轴会取消旧的键盘跳转请求。OSD 显示累计
跳转、时间、音量、速度。滚轮默认调音量，Shift+滚轮调进度，可改或禁用；不接管
惯性滚动。双击可选全屏、暂停、分区跳转或禁用。

独立/迷你窗口复用同一个视频控制器、播放视图和后端，不重新创建解码器。独立
窗口可原生全屏，迷你窗口可聚焦并使用同一套快捷键。窗口大小位置分模式保存，
屏幕变化时拉回可见范围；置顶和所有桌面显示分别可设。关闭聊天窗口不关闭浮动
播放器；关闭播放器暂停，退出整个 Telegram Player 则停止。每次只允许一个浮动
视频会话。浮动窗口中不提供跨消息播放列表，返回浏览器后才能切换媒体。

打开另一个视频会临时暂停浮动视频（沿用 Telegram 的声音协调行为）。广告/受限
控制视频不绕过原有控制限制。临时倍速在松键、失去焦点、打开菜单、改变设置和
销毁播放器时恢复，不写入持久倍速。

## 自用构建与账户隔离

CI 使用 macOS/Xcode 构建。成功的构建才发布 `Telegram-Player-macOS.zip`。
解压获得 `Telegram Player.app`，不需要在自己的 Mac 上安装源码或编译工具。
这是 ad-hoc 签名的自用应用，不是已公证发行版；macOS Gatekeeper 可能要求在
系统设置的「隐私与安全性」中允许打开。不要关闭整个系统的 Gatekeeper。

首次打开在本机填写已有的 API ID / API Hash，保存到登录钥匙串，服务名称为
`io.github.dandibbert.TelegramPlayer.api`。构建不需要 CI Secrets，不要将 API Hash
提交到仓库或日志。取消配置会退出应用，不会使用上游受限的测试 API ID。
凭据修改可在钥匙串访问中删除这一个服务项目后重新启动；不要删除 Telegram
的其他钥匙串项目。

应用 ID：`io.github.dandibbert.TelegramPlayer`。
数据目录：`~/Library/Application Support/TelegramPlayer/<build channel>`。
不会迁移、读取或写入官方 Telegram 的账户数据库，需要单独登录。
官方更新器禁用，避免增强版被官方二进制覆盖。原来的官方 App 可继续并存。

## 源码边界

- `packages/EnhancedMediaPlayer`：独立可测试的偏好、快捷键、seek 累积、AppKit
  事件路由、OSD、设置 UI。相同 Swift 源文件直接加入 Telegram 应用 target。
- `SVideoController` / `SVideoView`：现有播放器接口与控制适配。
- `PIPVideoWindow`：单播放会话的 gallery / detached / mini 窗口管理。
- `MGalleryVideoItem` / `GalleryViewer`：保留暂停状态和关闭生命周期。
- `ApiCredentials` / `AppDelegate`：自用凭据、独立存储和禁用官方更新。

不改 Telegram 协议、加密实现、下载缓存或解码后端；不增加远程凭据服务。
保留上游许可证与归属。尚不包括 mpv 兼容配置、外部字幕、逐帧步进、视频滤镜、
独立窗口播放列表、跨视频单独进度历史和按住方向键自动增加步长。

## 验证

`swift test --package-path packages/EnhancedMediaPlayer` 可单独运行。
测试覆盖设置兼容/冲突/边界、连续 seek、超时/边界、倍速恢复、音量和 AppKit
设置窗口布局。Linux 只运行纯逻辑测试；macOS CI 才编译 AppKit 层。

自动测试不能代替已登录 Telegram 的真实流媒体交互验收。发布前应检查：

- 普通下载视频 / 尚未缓冲的流视频 / HLS 视频，跳转与倍速各自有效。
- gallery → detached → mini → gallery 维持进度、缓冲、声音、暂停状态。
- 连按/长按方向键不切视频，输入框不被截获，临时倍速失焦必恢复。
- 两块屏幕、原生全屏、Spaces、最小化/关闭聊天窗口、删除正在播放的消息。
- 同时打开另一段视频时的暂停/恢复、受限内容/广告的原有控制限制。
- 快捷键全部重绑/清空后行为一致，系统快捷键没有被覆盖。
