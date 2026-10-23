# App Shelf 设计说明

## 入口与数据

`AppShelfPlugin` 提供 `ShellLauncher`，`OpenAppShelfAction` 保留独立动作 `app_shelf.openApplications`。`AppShelfView` 自行管理搜索、列表、选择、菜单和发送状态，借用宿主搜索焦点，不释放宿主节点。外部位置、过渡和启动捕获仍由宿主管理。

界面按 Windows 10 开始菜单的导航栏、字母列表、磁贴区组织：48 px 导航栏、36 px 行高的惰性列表、右侧最近使用／应用速览磁贴，以及底部搜索框。小于 580 px 或搜索时收起磁贴。列表含固定高度的分组标题，键盘只选择应用，通过 `applicationRows` 把应用索引映射到实际滚动行，菜单键定位同样使用该映射。最近使用磁贴不是持久化固定磁贴；没有增加未接入宿主的电源或账户按钮。

`ApplicationIndex` 在应用列表身份、最近列表身份或查询变化时重算，悬停不参与筛选排序。`LauncherHighlight` 只持有自己的 hover，动画背景与前景分开绘制，边框没有布局内边距；`Motion.pill`、宿主 `durationScale` 和系统关闭动画设置决定反馈时长。文字样式由 `ShellTextTheme.base` 派生，不回退到打包的 Material 默认字体。

面板材质对齐官方 `denial_launcher`：`DecoratedBox` 画 `panelColor(panelBackground)`、`BorderRadius.circular(theme.panelRadius)` 和 `hairline` 描边，内部只放透明 `Material` 供按钮使用，不再自行叠加 `ShellBackdropBlur`。启动器由宿主作为独立窗口合成，桌面背景和玻璃模糊由合成器提供；客户端 `BackdropFilter` 与这套合成叠加时，其取到的背景只覆盖窗口的一部分，`BlendMode.src` 会把其余区域替换成黑色，最终出现“一半壁纸、一半纯黑”的硬边。委托给合成器后，面板保持主题透明度且整块一致，也省掉了一次全屏背景滤镜。文字、搜索框、选中色和圆角分别取 `ShellTextTheme`、`cardColor(surfaceContainerHigh)`、强调色角色和 `panelRadius`。

应用列表、最近记录、图标和正常启动分别直接使用 `LauncherContext` 的 `applications`、`recentApplicationIds`、`buildIcon` 与 `onLaunch`。纯 Dart 的 `launcher_logic.dart` 负责可回归的过滤、排序、选择边界和滚动目标计算。

发送来源从公开 `denial_flutter_sdk/applications.dart` 导出的 `homeGridControllerProvider` 获取，通过公开 `desktopApplicationRecentId` 与上下文不透明 ID 对应。没有路径的内部应用或缺失来源禁用发送；不解析不透明 ID，不按显示名扫描应用目录，不创建第二套服务。

## 文件写入

`ShortcutWriter(environment: ..., runCommand: ...)` 可注入测试环境及发布进程执行器；竞态测试在真实 ln 执行前创建冲突目录或目录符号链接，验证 `-T` 保持目标文件身份。`send(sourcePath)` 返回 `ShortcutResult(status, path)`。`resolveDesktopDirectory(environment)` 解析 XDG 配置，并拒绝禁用目录、非绝对路径、无法理解的变量或 shell 替换。

来源与目标均有读取大小上限，保留 `.desktop` 完整 UTF-8 字节。发送不执行 `Exec`。先写同桌面文件系统的私有暂存目录，再用标准 `ln -T --` 建立独占目标硬链接，完成后移除暂存目录，使目录观察者看到完整文件；同名竞争不会静默替换。普通已有文件逐字节比较，相同返回 `alreadyExists`，不同或符号链接等返回 `conflict`。

不同内容的更新不自动覆盖：当前安全策略是提示先移走旧文件再发送，不依赖隐藏来源元数据推断所有权。文件系统不支持硬链接、权限不足或工具缺失均显示实际失败。

两插件只通过 XDG 桌面文件夹协作，不互相导入。目录中的文件是真实用户文件，桌面图标、打开确认、默认应用、拖动位置等属于 Desk Canvas。

## 异步与输入生命周期

可见性变化和释放使 generation 失效，迟到写入结果不会覆盖重新打开的界面；开始的实际写入仍会完成，关闭不伪装撤销文件操作。发送处理中重复点击禁用。菜单在同一个启动器 Stack 内展示，外部点按关闭并恢复宿主搜索焦点，Esc 分层关闭。隐藏/退出时同时使用 `IgnorePointer` 与 `ExcludeFocus` 隔离输入。

菜单使用启动器局部坐标，横纵约束在可用区域内，内容在低高度滚动。关闭层位于内容下方：再次右键另一个应用会移动菜单而不是只关闭，点按空白区域、搜索框或标题栏则关闭。搜索更改、清空和重新打开会在下一帧安全回到顶部；键盘上下移动单列行，PageUp/PageDown、Home/End 跨段移动，Tab 在搜索框与列表之间切换；Enter 启动，菜单键或 Shift+F10 打开当前应用菜单。

## 已知边界与验证

宿主没有提供显式的应用目录“加载完成但为空”标志，零应用沿用加载提示。SDK 目录排除 `Terminal=true` 的入口，本插件没有私自绕过它。没有实现应用附加动作菜单、固定到任务栏或卸载应用；不存在提前展示的无效菜单项。

无界面回归覆盖文件路径、原文保留、同名竞争、读取上限、错误配置、并发发送、搜索排序与导航计算。控件测试验证悬停反向与前景位置不变；本机缺少 `flutter_tester`，测试尚未运行。焦点/可访问性、原生弹层效果、字体尺度和实际启动由后续用户桌面验证确认；不以静态分析宣称这些效果已经通过。

## 保持视觉参数的第二轮优化

`ApplicationCatalog` 按宿主不可变快照预计算元数据与字母序，`query` 仅筛选搜索结果并提取最多 9 个最近入口。最近记录变化复用完整应用与分组行，不再重复排序；搜索仍保持宿主目录顺序。宿主主题变化时重新转换 Material 主题，稳定期间复用转换结果。

`HighlightDecoration` 使用 Flutter 原有的 `ImplicitlyAnimatedWidgetState` 和 `DecorationTween` 保持中途改向与时长语义，`CustomPainter(repaint: animation)` 只使绘制失效，不调用每帧 `setState`。画笔仍来自原 `BoxDecoration.createBoxPainter`，不简化描边、透明度或圆角。整个入口设绘制边界以拦住背景重绘，静态前景保持独立绘制边界。控件回归新增插值一致和委托身份不变断言；匹配套件的测试引擎仍缺失，尚未执行这些断言。

## 滚动连续性与宿主动画边界

`LauncherScrollController` 用公开 `ScrollPositionWithSingleContext`、`BallisticScrollActivity` 和指针信号 resolver 实现。外侧 `Listener` 记录设备类型，滚动控件原有的 resolver 仍决定谁消费事件；鼠标滚轮分支由临界阻尼 `ScrollMotion` 驱动，不抢夺原生拖动、触控板 pan/zoom、滚动条或外层边缘处理。连续输入累加目标，反向从当前位置设新目标并继承当前速度；新尺寸重新约束模拟，菜单／隐藏停止当前活动。键盘使用待完成目标计算可见性，防止快速反向时旧活动把选择带出视口。完成时落在精确目标，不对文字或图标整体缩放。

`RetainedLauncherEntry` 使用有界 `EntryRetention` 租约及 Flutter 自动 keep-alive，保留 SDK 图标加载器状态；回收离屏租约安排在帧后，避免布局过程中修改 keep-alive 父数据。列表 96、磁贴 12 的预算只限制离屏保留，不移除可见项目。纯 Dart 回归验证租约替换与迟到释放不会误删新实例；控件回归覆盖指针输入、改向、运行中卸载和短程回滚后加载器仍存活，但本机缺少匹配 `flutter_tester`，尚未执行控件断言。

源码对比确认：控制中心／电池面板共用阻尼 `PanelMotion` + `ControlCenterReveal`，启动器由宿主 `DesktopPanelTransition` 包裹，打开使用线性平移或按锚点淡入，关闭使用宿主另一条曲线。公开 launcher 上下文没有过渡控制接口，本插件不能独立移除或替换父层动画，也不叠加另一套开合控制器。完整统一属于宿主接口／宿主实现改动；本轮外层动画保持现状。
