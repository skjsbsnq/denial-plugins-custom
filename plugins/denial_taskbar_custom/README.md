# Custom Taskbar

基于官方 Denial Taskbar 的自定义插件，包名为 `denial_taskbar_custom`，面板 ID 为 `denial_taskbar_custom.panel`。所属项目的结构和新增插件约定见[集合说明](../../README.md)。

## 任务栏

保留上游的应用分组、窗口预览、固定应用、拖动排序、启动器、时间日期和显示桌面功能。任务栏固定在屏幕底部，高度为 52 个逻辑像素，并为窗口预留相应工作区。

应用图标只有一个窗口时，点击当前活动且未最小化的窗口会最小化；点击后台或已最小化窗口会激活或恢复。多窗口组仍通过预览选择窗口。右键菜单包含固定／取消固定、**新窗口**和**全部关闭**；新窗口通过宿主启动入口发起，具体是否允许多窗口由应用决定，没有启动项时禁用。全部关闭向该任务栏分组内的窗口逐一发送正常关闭请求，保留应用自己的未保存确认。

右侧顺序为：**托盘收纳 → 网络上下行 → 控制中心 → 电池 → 时间日期 → 显示桌面**。当前托盘图标统一放入收纳弹层。最右侧的透明窄条用于显示或还原桌面。

网络速率以两行文字显示：`↑ 上传`、`↓ 下载`，保持两行读数，点击可打开独立网络面板，字体与颜色跟随任务栏。网速区域按实际字体和文字缩放预留完整数值、方向箭头与单位的宽度，覆盖 `1000.0 KB/s` 等进位临界值，不缩小文字或使用省略号；读数变化时保持预留宽度稳定，窄屏使用任务栏已有的横向滚动。每秒读取 Linux 只读流量计数器，按实际采样间隔计算，单位为 B/s、KB/s、MB/s 等（十进制字节每秒）；首次采样和读取失败时显示 `—`。优先汇总物理网卡，避免重复统计桥接和 VPN 接口；没有物理网卡时汇总非回环接口。多屏共享同一份采样数据。

## 网络面板

点击任务栏的上下行读数打开 Stats 风格网络卡片，宽度为 360 逻辑像素，沿用 Denial 外观、模糊、字体、圆角与面板动画，支持 Esc、点击外部关闭及关闭后的焦点恢复。不包含 Top Processes 或其他进程排行。

- 顶部显示下载／上传实时速率，单位为十进制字节每秒。
- 流量历史显示最近 60 次共享采样，上半部为下载、下半部为上传，使用相同峰值尺度；读取失败保留断点，不用假零补齐。新打开面板可查看任务栏此前已经采集的历史。
- 联网历史按 SDK 的连接状态显示已联网、未联网和未知；服务初始化或不可用时不假定已经联网。
- 累计上下行采用当前参与统计的网卡内核字节计数，通常自开机或网卡计数重置起累计，并非插件启动后的会话用量。接口移除、重置或统计范围变化可能使累计值变小。
- 网卡详情包含接口名、运行状态、当前物理地址、链路速率（设备提供时）和本机 IPv4／IPv6 地址；详情行根据实际文字宽度排版，长名称或地址使用完整行宽，IPv4 和 IPv6 分开显示。超长内容保留单行并支持横向滚动、选中复制和悬停查看，不缩小字体或省略内容；Wi-Fi 名称、信号、频率和安全性取自 SDK 共享状态。

面板与任务栏、多屏共用同一份流量采样和有界历史，不再增加计时器。网卡元数据只在面板打开、手动刷新、接口集合变化或 SDK 网络事件后刷新。只读补充适配器从 Linux `/sys/class/net` 和 Dart 本机网卡枚举读取信息；按 [Linux 网卡接口契约](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-class-net)处理链路速率与物理地址，缺失数据保留 `—`。不额外探测公网 IP、延迟或抖动，不主动请求外部服务器。

## 电池卡片与时钟面板

参考用户提供的 Stats 源码和截图重建 Battery 与 Clock 布局：面板基准宽度为 360 逻辑像素，使用更宽的内边距和明细行、38 像素高的日历日期按钮，便于阅读和点击，保留居中标题、大电池图形、状态标签、细线分区、左右对齐明细，以及月历和本地时间卡片。颜色、字体、面板圆角、透明度、模糊、强调色和开合动画使用 Denial 设置；不固定为 macOS 配色。

点击控制中心与时间之间的电池图标打开电池卡片，电量和充电状态使用 SDK 的共享实时读数，未知电量显示 `—`。详情通过共享 UPower 状态在打开时读取，也可点击左上角图标刷新，提供电源来源、预估剩余／充满时间、满充与设计容量、功率、电压、健康度、循环次数和温度。多电池分别列出明细，顶部电量沿用 SDK 的汇总值。UPower 容量单位为 Wh，不将其伪装成 mAh；电流优先使用只读系统接口的实测值，缺失时通过功率／电压估算并明确标注。缺失数据保留 `—`，读取失败显示错误。

性能模式保留 **省电、均衡、性能**，通过 SDK 的系统性能模式语义操作切换。读取或切换期间禁用操作，系统不支持时提示，失败时显示后端错误；未读到真实模式时不默认选中均衡。不会单独修改 PBO 或 GPU 配置。模式选择使用带滑动选中底色的三段按钮，点击目标显示等待标记，只有系统确认成功后才更新选中状态；失败保留原模式并在按钮下方显示错误，等待期间防止重复操作。

电源电气读数通过集中只读适配器补充读取 `/sys/class/power_supply` 的 `power_now`、`current_now`、`voltage_now`，按 [Linux 电源接口单位](https://docs.kernel.org/power/power_supply_class.html)换算为 W、mA 和 V。只采纳在线适配器和在位系统电池，忽略离线 USB 接口、外设电池及缺席电池；不把 `*_max`、设计值或限流值当作实际读数。功率或电流缺失时可用另外两项推导，推导值标注“估算”；缺失电压不会除以零。

有适配器实测值时优先显示，并标注设备来源。本机 ADP1 仅上报接电状态，未提供适配器电气数据，因此明确显示“电池充电侧”的功率、电压与估算电流，不将它们冒充充电器输入。没有可用读数时保留 `—`，读取错误仍有提示。多电池分别列出，不混合电压。电气快照在打开面板、手动刷新和宿主共享电池状态变化时更新，不增加轮询；读取期间不把旧快照继续当作新读数。

已移除整个耗电进程区块。UPower 详情以打开和手动刷新时的快照为准，基础电量持续跟随宿主共享状态。

点击任务栏的时间日期打开时钟面板：六行月历含前后月份补位日期、今天的强调色标记、选中日期边框、上／下月切换，点击月份标题返回今天。切月时月份标题和日期网格使用短距离水平位移与边界裁切，旧月份退出期间不接收点击或键盘焦点。快速切月不会因底部时钟的秒级刷新重启动画。星期顺序跟随本地化设置；底部显示模拟时钟、本地日期时间（秒）和 GMT 偏移。秒级重绘仅在面板挂载期间运行，关闭后释放，不创建后台系统服务。

上述交互过渡默认约 220ms，跟随 Denial 动画时长倍率和移动距离；开启减少动画或倍率为零时直接更新，等待标记也使用静态图标。

两张卡片沿用控制中心的屏幕边界处理、窄屏收缩、内容滚动、Esc 与点击外部关闭、焦点恢复和可反向动画。桌面视觉效果由用户确认。

## 独立控制中心

点击任务栏上的滑杆图标打开本插件的控制中心，位置在当前显示器右下角、任务栏上方，边距为 8 个逻辑像素。支持键盘、Esc、点击外部关闭及中英文提示。

外观跟随 Denial 的明暗、强调色、字体、圆角、透明度和背景模糊设置。背景模糊与前景文字、图标分开绘制；文字保持原尺寸，面板静止位置对齐物理像素。

- **顶部栏**：用户头像和名称、通知、设置、电源。设置按钮打开独立的 `denial-settings` 程序，尊重 `DENIAL_SETTINGS_BINARY` 配置；已有设置窗口时切换到该窗口。
- **声音**：音量调节及输出设备选择。打开时读取原生音量，读取完成前显示占位并禁用滑块；静音时显示有效输出为 0%，防止延迟读取或旧回包覆盖刚拖动的值。
- **亮度**：调节当前显示器亮度。
- **快捷操作**：Wi-Fi、蓝牙、明暗外观、截图、锁屏和电源设置。
- **Wi-Fi 与蓝牙二级菜单**：主按钮负责开关，右下角角标进入详情。Wi-Fi 支持刷新、选择网络、输入密码和断开；蓝牙支持搜索、配对确认、连接和断开。
- **通知**：查看历史、移除或清空通知、切换勿扰。普通铃铛配圆点表示未读；带斜线铃铛表示已开启勿扰，两者同时存在时保留未读圆点。
- **电源与会话**：锁屏、注销、挂起、重启和关机，使用 SDK 的能力检查与确认流程，不显示休眠。

不包含保持唤醒、麦克风控制、夜灯和取色器。网络和设备操作使用 SDK 的共享状态与权限检查，不可用或正在切换时禁用对应操作，并显示后端错误。

用户资料通过只读适配器读取参考桌面的 schema-1 profile 文件，无效或缺失时回退到账户名；重新打开面板时刷新，不修改官方桌面的用户资料。

### 动画

控制中心整体从任务栏上方短距离滑出并逐步显露，退出向下收回，不对整块面板做淡入淡出或文字缩放。临界阻尼过渡在中途反向时接续当前位置和速度，重复关闭请求共享同一段动画。

二级菜单参考官方仪表盘通知卡片，从角标所在位置展开为内容卡片，返回时沿原路径收回。展开约 250ms、收回约 200ms，分别采用强调减速与强调加速曲线；保留当前滚动位置，运动中使用连续轨迹，静止端点对齐物理像素。

动画遵循 Denial 的时长倍率、移动距离及减少动画设置。二级菜单将固定的前景、焦点与滚动内容移出逐帧构建，移除不使用约束的布局回调；控制区和详情复用已有透明度合成层，避免重复增加图层；信息卡片的前景隔离重绘，切月时复用文字与日历的绘制指令。时钟每秒只更新底部时间区，日期变化时才重建月历，并继续响应宿主时钟事件。保留原有曲线、时长、位移、显隐、圆角、背景模糊与端点像素对齐，不引入位图截图或文字缩放。

实际帧率与视觉效果由用户在桌面确认；上述优化减少重复构建与绘制工作，不代表已经完成桌面性能测量。

## 安装与更新

从 GitHub 安装时，在插件管理器中添加仓库并指定本插件目录，或执行：

```sh
denial-plugins prepare
denial-plugins --path plugins/denial_taskbar_custom add https://github.com/skjsbsnq/denial-plugins-custom.git
denial-plugins plan
```

从项目根目录添加本地插件：

```sh
denial-plugins --local add "$PWD/plugins/denial_taskbar_custom"
denial-plugins plan
```

在插件管理器中选择 **Custom Taskbar**，关闭原来的 **Taskbar**，避免重复任务栏和工作区提供者冲突。根据 `plan` 返回的实际候选 ID 构建：

```sh
denial-plugins build CANDIDATE_ID
```

构建完成后在插件管理器中应用，或运行 `denial-plugins activate CANDIDATE_ID`。修改源码后也需要重新生成候选、构建并应用。

## 任务栏偏好

当前实现沿用上游的配置文件：

```text
$XDG_CONFIG_HOME/denial/plugins/denial_taskbar.json
```

未配置 `XDG_CONFIG_HOME` 时，通常为 `~/.config/denial/plugins/denial_taskbar.json`。当前自定义包与官方任务栏使用同一偏好路径。

应用图标默认居中。设置为左对齐：

```json
{"iconAlignment": "left"}
```

使用 `"center"` 或删除该选项恢复默认。固定应用保存于同一文件的 `pinnedApplications` 数组；插件会保留其他配置项。偏好在 shell 生命周期开始时读取，手动编辑后需要重新加载 shell bundle。

## 开发与检查

进入本插件目录执行检查，SDK 和编译工具使用当前 Denial 安装匹配的版本。本机路径写在被忽略的 `pubspec_overrides.yaml`，不写入 `pubspec.yaml`。更详细的 SDK 准备流程见[上游开发说明](https://github.com/denialwm/denial-plugins/blob/4b7adf998852b09b9a91c1cfab48be58debf2e80/docs/DEVELOPMENT.md)。

```sh
cd plugins/denial_taskbar_custom
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
dart test/window_groups_test.dart
dart test/preview_emphasis_test.dart
dart test/taskbar_preferences_test.dart
dart test/control_center_layout_test.dart
dart test/control_center_profile_test.dart
dart test/volume_presentation_test.dart
dart test/panel_motion_test.dart
dart test/network_speed_test.dart
dart test/network_telemetry_test.dart
dart test/network_detail_layout_test.dart
dart test/battery_presentation_test.dart
dart test/window_activation_test.dart
dart test/calendar_dates_test.dart
dart test/power_supply_readings_test.dart
# 需要匹配版本工具包含 flutter_tester：
flutter test --no-pub test/widget
```

这些检查覆盖分组、预览交互、偏好、定位与像素对齐、只读用户资料、音量同步、动画反向切换、网络速率计算、性能模式初始化与切换状态、窗口激活／最小化判定、日历跨年与闰年、时区偏移、缺失电气读数及紧凑卡片边界，网络历史上限、失败恢复与网卡元数据，详情行长值与窄屏排版，以及电源微单位换算、实测／推导优先级、来源选择、离线设备过滤与限长读取。组件回归测试使用假的系统性能服务和时钟服务，不操作真实设备，覆盖切月反向、旧页输入隔离、减少动画、模式切换等待与失败，以及秒级更新不重建日历、二级菜单的固定前景绘制复用、滚动保留和过渡输入隔离、网速完整单位在等宽字体及大字号下的预留宽度。当前本机发行编译套件缺少 `flutter_tester`，因此该组件测试暂时无法运行；已有 Dart 无界面检查仍可独立执行。无界面检查与构建不能代替桌面视觉验证。

## 来源与许可证

- 上游：[denialwm/denial-plugins](https://github.com/denialwm/denial-plugins)，路径 `plugins/denial_taskbar`。
- 复制来源提交：`4b7adf998852b09b9a91c1cfab48be58debf2e80`。
- 原始参考源码：[plugins/denial_taskbar](https://github.com/denialwm/denial-plugins/tree/4b7adf998852b09b9a91c1cfab48be58debf2e80/plugins/denial_taskbar)；本地可选的 `upstream/` 参考副本不上传 Git。
- 保留原版权与 [LICENSE](LICENSE)，按 GPL-3.0-or-later 条款使用和分发。

### Stats 布局参考

- 来源：用户提供的本地 `stats-master` 归档，对应 [exelban/stats](https://github.com/exelban/stats)。参考 `Modules/Battery/popup.swift`、`Modules/Clock/popup.swift`、`Modules/Net/popup.swift` 和 `Kit/constants.swift`；以 Dart／Flutter 重建布局，没有引入 macOS 服务。
- 归档不含 `.git`，无法确认来源提交。用于标识该参考版本的 SHA-256：Battery popup 为 `b5df954190485f34f5e270933a2e0ae0c8899fb39f606b4043123419ea29a6ad`；Clock popup 为 `6177cd66bccec916c47930b79fee411f2a14d3808d45aad3bace075058e6bf1b`。
- Network popup 参考文件的 SHA-256 为 `fc4f9414782579038805b7e7d64d1c9bb6ee74e727757ffb2480cfde3391ec3e`。
- Stats 版权为 Serhiy Mytrovtsiy，MIT 许可证副本见 [third_party/stats-LICENSE](third_party/stats-LICENSE)。本插件原有 GPL 许可证继续保留。
