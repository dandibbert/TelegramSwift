# Enhanced Media Player / 播放器增强

This fork keeps Telegram's streaming/cache/decoder backends. It changes player
input, controls and presentation rather than replacing them with mpv.

## 使用

打开视频后即可使用。Telegram 设置中新增「播放器」，视频速度菜单中也有
「播放器设置」。设置采用 Telegram 原生分组列表；快捷键和窗口选项使用与其他设置相同的二级页面。
「打开视频时」可选媒体浏览器、独立播放器或迷你画中画。输入表单支持复制粘贴。

| 默认键 | 操作 |
| --- | --- |
| Space | 播放 / 暂停 |
| ← / → | 后退 / 前进 5 秒 |
| ⌘← / ⌘→ | 精细跳转 1 秒 |
| ⇧← / ⇧→ | 大步跳转 30 秒 |
| ↑ / ↓ | 音量 ±5% |
| M | 静音 / 恢复之前音量 |
| [ / ] | 倍速 ±0.1× |
| 反斜杠键 | 恢复 1× |
| 按住 Tab | 临时 2×，松开恢复原速 |
| F | 全屏 |
| D | 独立播放器 / 返回媒体浏览器 |
| P | 迷你画中画 / 完整独立窗口 |
| T | 只置顶播放器 |
| ⌥← / ⌥→ | 上一个 / 下一个媒体（媒体浏览器中） |
| ⌘, | 播放器设置 |
| Esc | 先退出全屏，再返回媒体浏览器，最后关闭媒体浏览器 |

22 项操作均可重绑、清空、恢复默认，支持组合修饰键（含由 Karabiner 发出的
Hyper）；冲突会被提示。快捷键按物理键位记录；不同键盘布局上的显示名称可能
与实际键帽不同。录入时 Esc 表示取消，不会将 Esc 重新录入为另一个操作。

不安装全局键盘监听，不申请辅助功能或输入监控权限。只有播放器所属窗口收到的
事件会被处理，不抢走聊天、搜索、设置输入框的方向键。预加载但未显示的视频
不会截获按键；清空绑定也不会重新触发旧的媒体翻页快捷键。图片浏览保持原来的
翻页方式。增强视频浏览器失去焦点后不会强行抢回焦点。

普通、精细、大步跳转及音量、速度步长均可调。第一次跳转立即执行；连续按键仅更新最新目标，在后端真正完成前一次跳转后再追到
最新位置，避免每 70 毫秒重启解码。缓冲状态不视为完成；陈旧且卡住的请求可在松键后
被最新目标替换一次。拖动时间轴走同一队列，替换旧键盘目标。OSD 显示累计
跳转、时间、音量、速度。滚轮默认调音量，Shift+滚轮调进度，可改或禁用；
不接管惯性滚动。双击可选全屏、暂停、分区跳转或禁用；启用时先消费第一下
视频画布点击，防止媒体浏览器提前关闭。真正的控制按钮仍可正常点击。

独立、迷你窗口复用同一个视频控制器、播放视图和后端，不重新创建解码器。
独立窗口可原生全屏，迷你窗口可聚焦并使用同一套快捷键。窗口大小位置分模式
保存，屏幕变化时拉回可见范围；置顶和所有桌面显示分别可设。关闭聊天窗口
不关闭浮动播放器；关闭播放器暂停，退出整个 Telegram Player 则停止。
每次只允许一个浮动视频会话。浮动窗口中不提供跨消息播放列表，返回媒体
浏览器后才能切换媒体。迷你窗口使用原生右键菜单，支持速度与播放器操作。

打开另一个视频会临时暂停浮动视频，沿用 Telegram 的声音协调行为。广告和
受限控制视频不绕过原有控制限制。临时倍速在松键、失焦、打开菜单、改变设置
和销毁播放器时恢复，不写入持久倍速。速度范围为 0.25–2.5×，受现有后端限制。

## 自用构建与账户隔离

工作流：`.github/workflows/enhanced-player.yml`。
每次分支提交及 PR 更新运行 macOS 测试；手动 Run workflow，或提交消息包含
`[build app]`，才额外运行完整应用构建。所有编译都可在 GitHub Actions 完成，
不要求使用者在自己的 Mac 上安装源码或 Xcode。

构建固定 Xcode 16.4、CMake 3.31.6 和子模块版本；补齐上游缺失的 FFmpeg 7.1
源码时使用官方发布的固定提交。原生依赖全部成功后才保存缓存，应用构建失败
不会丢掉已经验证完成的原生编译产物。缓存键包含依赖源码与构建脚本版本。

成功构建、签名验证和首次启动冒烟检查后，Artifacts 提供
`Telegram-Player-macOS-<architecture>-<run number>`，内含应用 ZIP、SHA-256、`BUILD.txt` 和本文。
`BUILD.txt` 记录实际构建提交。**只有测试截图或 build-diagnostics 不代表应用
已经构建成功，也不要将它们作为安装包下载。**

解压 `Telegram-Player-macOS.zip` 得到 `Telegram Player.app`。这是 ad-hoc 签名
的自用应用，不是已公证发行版；macOS Gatekeeper 可能要求在系统设置的
「隐私与安全性」中允许打开。不要关闭整个系统的 Gatekeeper。

首次打开在本机填写已有的 API ID / API Hash，保存到登录钥匙串，服务名称为
`io.github.dandibbert.TelegramPlayer.api`。构建不需要 CI Secrets，不要将 API Hash
提交到仓库或日志，也不需要把它发送给开发助手。取消配置会退出应用，不会
使用上游受限的测试 API ID。凭据修改可在钥匙串访问中删除这一个服务项目后
重新启动；不要删除 Telegram 的其他钥匙串项目。

应用 ID：`io.github.dandibbert.TelegramPlayer`。
数据目录：`~/Library/Application Support/TelegramPlayer/<build channel>`。
不会迁移、读取或写入官方 Telegram 的账户数据库，需要单独登录。
官方更新器禁用，避免增强版被官方二进制覆盖。原来的官方 App 可继续并存。

## 源码边界

- `packages/EnhancedMediaPlayer`：独立可测试的偏好、快捷键、seek 累积、AppKit
  事件路由、OSD、设置 UI。相同 Swift 源文件直接加入 Telegram 应用 target。
- `SVideoController` / `SVideoView`：现有播放器接口与控制适配。
- `PIPVideoWindow`：单播放会话的 gallery / detached / mini 窗口管理。
- `MGalleryVideoItem` / `GalleryViewer`：暂停状态、焦点和关闭生命周期。
- `ApiCredentials` / `AppDelegate`：自用凭据、独立存储和禁用官方更新。

不改 Telegram 协议、加密实现、下载缓存或解码后端；不增加远程凭据服务。
保留上游许可证与归属。尚不包括 mpv 兼容配置、外部字幕、逐帧步进、视频滤镜、
独立窗口播放列表、跨视频单独进度历史和按住方向键自动增加步长。

## 验证边界

`swift test --package-path packages/EnhancedMediaPlayer` 可单独运行。测试覆盖
设置兼容、冲突和边界值，连续 seek、倍速恢复、音量、控制器激活、输入事件
路由、文本焦点，以及三页设置在不同宽度和两种滚动条模式下的布局与滚动。
macOS CI 还输出深浅色设置页截图。Linux 只运行纯逻辑测试，不验证 AppKit。

事件路由测试使用真实 AppKit 窗口、视图、事件和 responder；为了使无交互
桌面的 CI 可重复，仅由测试专用窗口模拟 `isKeyWindow`，并同时验证非焦点
窗口不接管按键。这不等于已经做了物理键盘、Karabiner 或完整 Telegram 的
端到端自动操作。

打包步骤还校验签名并运行八秒无凭据启动检查，用于发现缺失动态库、早期崩溃。
它没有登录账号，**不等于真实视频播放已经验收通过**。以下仍须在实际账号和
目标 Mac 上验证，不能以单元测试和 UI 截图替代：

- 普通下载视频、尚未缓冲的流视频、HLS 视频，各自跳转与倍速有效。
- gallery → detached → mini → gallery 维持进度、缓冲、声音、暂停状态。
- 连按、长按方向键不切视频，输入框不被截获，临时倍速失焦必恢复。
- 双屏、原生全屏、Spaces、最小化或关闭聊天窗口、删除正在播放的消息。
- 同时打开另一段视频的暂停和恢复、受限内容与广告原有控制限制。
- 快捷键重绑或清空后的行为一致，系统快捷键不被覆盖。

## 实际使用反馈修复（第二版）

替换了第一版独立 AppKit 设置窗口，改用本应用 TGUIKit 控件、主题、分组和导航。
新增默认窗口模式、原生快捷键录入与数字表单、复制粘贴/全选/撤销的本窗口路由。
菜单操作不再被「菜单打开时禁止键盘」的判断吞掉；快捷键文本放到原生右侧栏。
HUD 改为直接绘制文字的紧凑提示，不在帧布局播放器中嵌套自动布局标签。独立窗口
使用透明标题栏和隐藏标题，画中画保留圆角；不相关设置变化不会意外取消当前置顶。

新增 `--player-ui-smoke <directory>` 仅用于 CI：运行实际构建的应用，呈现原生设置
和 SVideoView，核验菜单回调、即时首次跳转、串行追帧、缓冲状态隔离，并输出截图。
该检查使用确定性的假媒体，不连接 Telegram，也不等于真实网络视频播放测试。
CI 只有这项检查、签名与常规启动检查全部通过才上传可安装包。


## Window readiness and bot topics compatibility

Detached live resize now synchronously relays geometry to the media backend,
including its explicit updateLayout hook. Enhanced video presentation does not
wait for a thumbnail download. Controls use metadata immediately; buffering is
still shown honestly until the media backend is ready.

This native Mac base is the July 2025 public TelegramSwift source, not the recent
Telegram-iOS source used by Swiftgram. This patch is a narrow bot-forum backport,
not a claim of parity with all newer Telegram features. The pinned API layer is
unchanged; peer-based forum methods and compatible response parsers are added
without changing existing channel RPCs. A successful read-only forum listing can
discover the capability when an older user constructor omits it. Create/manage
rights are taken only from server flags, never guessed from the bot's name.

For supported private bot topics the existing native topic sidebar/history are
reused. Select a topic before composing. The New Topic action uses the native
name form, creates the topic first and only then opens it; it does not silently
send an overview draft to General. This is an explicit create-first flow, not a
copy of the newest client's auto-named New Thread composer. No account data is
migrated or deleted. Topic deletion remains scoped to its thread.

The protocol fixture tests exercise actual serializers and parsers; production
smoke checks exercise window geometry and UI with fake media. Neither substitutes
for an authenticated Telegram server test or real streaming-video performance.
