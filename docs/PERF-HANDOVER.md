# 性能问题交接（未解决，待继续）

状态：**未解决**。已排除若干路径、修掉了几处确定的额外工作，但用户仍报告拖动窗口时 CPU 明显爆发。本文档记录已确认的事实、测量方法、已改内容与剩余假设，供下一个代理直接接手。

## 1. 用户报告的症状

启用 `desk_canvas`（桌面图标/快捷方式）与 `app_shelf`（启动器）之后出现：

1. 显存占用变高；
2. 鼠标始终有一点点不丝滑；
3. CPU 基线比原来高一点；
4. **拖动窗口移动时 CPU 大幅上升**（主要矛盾）；
5. 鼠标左右晃动时 CPU 小幅度上升。

环境：`deniald`（Denial 合成器/外壳，PID 会变）跑在 `/dev/dri/card1`（NVIDIA `0x10de:0x2820`）；`card0` 是 AMD 核显但未用于会话。属真实 GPU，不是软件渲染。

## 2. 复现与工具环境

- 工作区：`/home/wwt/项目/denial插件`，远端 `https://github.com/skjsbsnq/denial-plugins-custom.git`，分支 `main`。
- 编译套件与 SDK（只读参考，含宿主组合根）：
  `/home/wwt/.local/state/denial/plugins/build-kits/4d69d87ef7d6b197c0dd34d74a1926ca16eb067fa4b43d90489c2048b764715c/`
  - `runtime/packages/denial_flutter_sdk`、`runtime/packages/denial_sdk`：公开 SDK
  - `runtime/plugins/denial_desktop`：参考桌面组合（宿主行为的最佳推断来源）
  - `runtime/plugins/denial_launcher`：参考启动器
- 工具：`dart` = `/opt/dart-sdk/bin/dart`（3.13.5）；flutter = 上述套件的 `flutter/bin/flutter`。
- **该套件没有 `flutter_tester`**，所有 `testWidgets` 无法执行（`interaction_highlight_test`、`desktop_interaction_test`、`smooth_scroll_test` 等都不能跑，不能当作通过）。
- 插件管理器：`denial-plugins`（`/usr/bin/denial-plugins`）。
- 只用公开 SDK，不跨包引用 `src/`。

### 必须知道的坑

1. **`denial-plugins plan` 是异步的**：命令返回时计划还没跑完，紧接着读 `status` 或 `build` 会拿到**上一轮的计划**。已经因此编出过一次旧源码。正确做法：
   ```sh
   denial-plugins plan; sleep 25
   denial-plugins status | jq -r .plan.id          # 等 status 变成 planned 再取 id
   denial-plugins build <PLAN_ID>
   # 构建后必须校验候选里真的是新代码：
   grep -c <新增符号> ~/.local/state/denial/plugins/candidates/<ID>/packages/desk_canvas/lib/src/desktop_canvas.dart
   ```
2. 候选目录里是**源码快照**（`candidates/<id>/packages/<pkg>/...`），可以用来确认构建内容。
3. 管理器有时会自行激活新构建（`active.nativeGeneration` 会增加）。**不要假定“构建完就没生效”**，用 `denial-plugins status | jq -c '{built:.build.id, active:.active.id, gen:.active.nativeGeneration}'` 核对，并到激活候选的 `packages/` 里 grep 验证。
4. 任何情况下不要：重启/停止图形会话、截图、修改用户的插件选择、手改管理器内部状态文件、在未授权时激活候选。

## 3. 测量方法与已得到的数字（最重要）

用户无法给出火焰图，但线程级采样足够定位。合成器进程内 Flutter 线程名为：
`io.flutter.ui`（Dart 逻辑）、`io.flutter.rast…`（**comm 被截断到 15 字符，实际是 `io.flutter.raster`**）、`io.flutter.io`、`deniald`（含合成器主线程）。

### 3.1 一次性快照差分

```sh
P=$(pgrep -x deniald | head -1)
ps -L -p "$P" -o tid=,time=,comm= > /tmp/t1
# 让用户在这期间做动作
ps -L -p "$P" -o tid=,time=,comm= > /tmp/t2
# 对比 TIME 列的增量
```

### 3.2 逐秒采样（推荐，能把 CPU 曲线和动作对上）

脚本（本次用过的版本，可重写）：

```sh
#!/bin/sh
P=$(pgrep -x deniald | head -1)
[ -z "$P" ] && exit 1
: > /tmp/denial-cpu.raw
i=0
while [ "$i" -lt 90 ]; do
  i=$((i+1))
  vals=""
  for d in /proc/$P/task/*; do
    name=$(cat "$d/comm" 2>/dev/null)
    case "$name" in
      io.flutter.ui) key=ui ;;
      "io.flutter.rast"*) key=raster ;;
      deniald) key=main ;;
      "volition-kms") key=kms ;;
      *) continue ;;
    esac
    v=$(awk '{n=split($0,a,")"); split(a[2],f," "); print f[12]+f[13]}' "$d/stat" 2>/dev/null)
    vals="$vals $key=$v"
  done
  echo "$i$vals" >> /tmp/denial-cpu.raw
  sleep 1
done
```

用 `setsid nohup sh /tmp/sampler.sh >/dev/null 2>&1 &` 后台跑，然后让用户在指定秒数区间做动作。数值是**累计 CPU ticks（100/s）**，相邻行相减即该秒占单核百分比。

### 3.3 已测结果

- **完全空闲**：所有线程 `0.0%`。可以排除常驻 ticker / 周期定时器。
- 120 秒聚合（含拖动约 30 s、晃鼠标、开关启动器）：`raster` +17 s、`ui` +9 s、`deniald` 主线程 +4 s、`volition-kms` +1 s、一个 `DartWorker` +2 s；期间新出现 6 个 `DartWorker` 线程。
- **逐秒、拖动窗口 34 秒（第 25–59 s）**：

  | 线程 | 拖动期间（单核占比） | 松手后（31 s 平均） |
  | --- | --- | --- |
  | `io.flutter.ui` | **19.1%** | 0.3% |
  | `io.flutter.raster` | **21.6%** | 3.1% |
  | `deniald` 主线程 | 5.6% | 0.9% |
  | `volition-kms` | 1.2% | 1.2% |

  按 60 fps 折算：每帧约 **3.2 ms UI + 3.6 ms 光栅**。
- 桌面项目数：**14 个，全部是 `.desktop` 快捷方式**（`xdg-user-dir DESKTOP` = `/home/wwt/桌面`）。

**结论：拖动时的成本一半在每帧 Dart 重建，一半在每帧绘制；松手即归零，不是后台任务。** 这两半都还没有被压到可接受水平。

## 4. 已确认的宿主行为（本轮从 build-kit 源码读出，含行号）

路径前缀 `R = /home/wwt/.local/state/denial/plugins/build-kits/4d69d87e.../runtime`。

1. **宿主挂载 surface 时没有绘制边界**：`R/packages/denial_flutter_sdk/lib/src/widgets/shell_surface_plane.dart:64-98`，只有 `Positioned` + `ClipRect` + `Stack`。所以插件内部任何重绘都会冒泡到整帧场景（含壁纸）。
2. **场景结构变化时重建整条 surface 链**：`R/plugins/denial_desktop/lib/src/desktop/desktop_scene.dart:795-831` 每次 build 都重新 `resolveShellSurfaces(...)`（`shell_surface_plane.dart:21-50`），并重建 desktop / desktopControls / aboveWindows 三个 plane；`_SurfaceInstance.build` 每次都 `entry.surface.build(...)` 返回**新 widget 实例**（`shell_surface_plane.dart:130-155`）。→ 插件 surface 会被动重建，`RepaintBoundary` 挡不住。
3. **纯 move-grab 拖动本应走快速通道**：`R/plugins/denial_desktop/lib/src/desktop/desktop_workspace_controller.dart:1278-1293` 在 begin 包把 `dragging=true`；结构相等性在双方都在拖动时忽略帧（`desktop_workspace.dart:686-709`），几何只通过 `DesktopLiveWindowPlacements` 的 `ValueNotifier<Offset>` 做绘制平移（`desktop_live_window_placements.dart:24-76`）。**resize / layoutPreview / 工作区切换 / 最小化最大化则会每帧重建整条链。**
   → 待确认：用户报告的是“拖动窗口”，如果实测确实每帧重建，说明该窗口`dragging`未置位（例如走客户端移动或 X11 路径），这是宿主侧问题。
4. **每次原生窗口快照都会重算插件可见窗口列表**：`R/plugins/denial_desktop/lib/src/core/shell_plugin_services.dart:112-144` 的 `_windows(monitorId)` 是 `autoDispose.family`，`ref.watch(referenceShellProvider)` 无 `select`，每次快照都新建 `List<ApplicationWindow>`（每窗口一个新对象，O(W) × 显示器数）。**只要有任何插件 watch 它就会重算**，`select` 只过滤回调、不阻止重算。
5. 插件可用的窗口 API 只有整份列表：`R/packages/denial_flutter_sdk/lib/services.dart:71-86`，没有细粒度几何流。
6. **任务栏每帧整条重建**：`plugins/denial_taskbar_custom/lib/src/window_buttons.dart:150` 直接 `ref.watch(services.windows(widget.monitorId))`，每次快照都会重跑 `WindowGroups.update`（`window_groups.dart:9-34`）并重建按钮列表 + `ReorderableListView` 布局。**本轮未改动（第三个插件，需用户同意）。**
7. 窗口预览不是截图：`shell_plugin_services.dart:327-368` 直接复用客户端纹理（`Texture`），拖动时没有重新编码/截屏成本。
8. 图标解码尺寸：`R/packages/denial_flutter_sdk/lib/src/widgets/app_icon.dart:81-93` 的 `cacheWidth = clamp(logicalW × dpr, 85, 512)`；`DeferredAppIcon` 的预取固定按 54 逻辑像素（`:221-251`）。→ 同一个应用可能同时存在两份解码（如 108² 与 96²），是显存细节，不是 CPU。
9. `app_shelf` 的 `onEnter/onExit` 只接到 220 ms 的关面板定时器（`R/plugins/denial_desktop/lib/src/desktop/desktop_panel_hover_controller.dart:43-64`），**不触发应用目录重扫**；`setLauncherActive` 的 750 ms 刷新只被移动端 `home_surface.dart` 调用。宿主还用 `_cachedApplicationLauncher()` 复用同一个 widget 实例（`desktop_panel_overlay.dart:57-91`），所以启动器**不在**窗口几何链路上。

## 5. 已经改了什么（都已提交并推送）

`origin/main` = `8e491ca`。

### `5b25f81` 第一轮：失效范围与后台开销

- `desk_canvas/lib/desk_canvas.dart`：surface 最外层加 `RepaintBoundary`（宿主没有）；全屏窗口覆盖工作区时 `visible` 加 `(!environment.fullscreen || environment.desktopVisible)`。
- `desktop_canvas.dart`：托管菜单只在实际绘制内容（菜单项、选择数、位置、标题、提示、忙碌、图标档位、隐藏开关）变化时才递增 `popupRevision`——原先画布任何 `setState` 都会重建带 `BackdropFilter` 的菜单。
- `desktop_canvas.dart`：`changed()` 在列表身份、错误、加载状态都没变时直接返回。
- `desktop_sdk_adapter.dart`：图标名解析结果进程级缓存 + 串行成批（原先每批新名字都新建一个冷缓存 isolate）；已安装应用目录改为打开快捷方式时按需 `Isolate.run` 读取，**不再 `ref.read(homeGridControllerProvider)`**（会为整个会话保留应用目录 watcher + 5 分钟周期重扫）。
- 两插件 `highlight_decoration.dart`：复用同一个插值动画实例，`shouldRepaint` 比较当前装饰值（原先每次 rebuild 都判为“变了”）。
- `app_shelf`：菜单指针/键盘选中改为 `ValueNotifier`（不再重建整面板）；`LauncherHighlight` 加入“必须真实指针位移才恢复悬停”+`feedbackEpoch`（可见性变化复位）；keep-alive 预算 96/12 → 32/8。

### `f14ee70` 第二轮：图标网格实例复用

`iconTiles()` 按签名（主题、项目列表、布局代次、选择集合、拖动项、反馈代次、图标档位、区域、悬停开关、滚动可见范围）复用同一批图标 widget。元素更新对相同实例直接跳过，宿主每帧重建 surface 时不再逐图标重建包装链。新增控件回归 `test/desktop_interaction_test.dart` 的 `unchanged desktop reuses its icon widgets on surface rebuild`（**因缺 `flutter_tester` 未执行**）。

### `8e491ca` 第三轮：整棵画布复用 + 削减模糊通道

- `desktop_canvas.dart`：`LayoutBuilder` 内部再按签名复用**整个画布子树**（`Focus`／`Stack`／背景手势／提示层），宿主每次重建只多一次哈希。
- `desktop_canvas.dart`：标签阴影 **2 层 → 1 层**（`blurRadius 3.5`），快捷方式角标的 `BoxShadow(blurRadius: 2)` **改为 0.7 px 描边**。14 个图标每帧的模糊渲染通道从约 **56 → 14**。**这是唯一的视觉变化**（标签光晕更紧、角标无投影），用户已被告知可回滚。

检查：两插件 `dart format` + `dart analyze --fatal-infos lib test` 通过；纯 Dart 回归（`desktop_feedback`、`refresh_coalescing`、`desktop_store`、`desktop_viewport`、`shortcut_writer`、`launcher_logic`、`scroll_motion`）通过；`tools/check_desktop_integration.dart` 通过。

最新候选：`1792769929521356-73686`（构建时已 grep 校验含 `_surfaceSignature`）。**是否已激活请现场用 `denial-plugins status` 核对。**

## 6. 明确已排除的

- 两插件内**没有** `Ticker` / `AnimationController.repeat` / `Timer.periodic` / 递归 `addPostFrameCallback`（唯一 `TickerProvider` 是 `smooth_scroll.dart` 传给 `BallisticScrollActivity` 的 vsync）。空闲采样全部线程 0.0% 印证。
- 两插件内**没有** `Image.memory` / `instantiateImageCodec` / 自持 `ui.Image`，不逐帧解码；图标走 SDK `AppIconImage` 按绘制尺寸解码。
- 两插件**不轮询**：桌面用 `Directory.watch()` + 120 ms 去抖；启动器没有文件监听。
- `app_shelf` 不在窗口几何链路上（见 4.9），宿主也不会因窗口变化重建它的 `LauncherContext`。
- 松手后 CPU 立刻回落（ui 0.3%、raster 3.1%）→ 不存在“关掉界面对应后台还在跑”的任务。

## 7. 剩余假设与建议的下一步（按优先级）

### H1（优先）ui 那 19% 到底是谁的

第三轮已经把我们 surface 的每帧 Dart 成本压到“一次签名哈希”。应用 `8e491ca` 后重测；**如果 ui 仍接近 19%，这部分就不在桌面插件里**，只可能来自宿主的每帧场景重建和任务栏的整条按钮列表重建。

- 实验 A：让用户在插件管理器里**关闭 Desk Canvas**，保持其它不变，拖 25 秒，用 3.2 的脚本对比 ui/raster。差值就是桌面插件的真实份额。（**不要自己改用户的选择**，只给步骤。）
- 实验 B：同样方法关掉 Custom Taskbar，验证 `window_buttons.dart:150` 的整列表订阅是不是大头。
- 如果确认是任务栏：把 `ref.watch(services.windows(...))` 改为按“渲染所需字段”的紧凑签名 `select`（如 `Object.hashAll([for (w in windows) Object.hash(w.id, w.active, w.minimized, w.title, w.appId, w.workspaceId)])`），实际分组时再 `ref.read` 完整列表。风险：`select` 值不变时会漏掉某些字段，需逐项核对 `window_buttons.dart` 到底读了哪些字段。

### H2 raster 那 21%：把静态图标层烘成图片

模糊通道已从 56 降到 14，若还不够：把每个图标的静态内容（图标 + 标签 + 角标 + 阴影）用 `PictureRecorder` + `toImage` 预渲染成一张 `ui.Image`，每帧只做 blit；悬停/选择装饰仍单独绘制（保持现有“装饰在下、内容在上”的观感）。

注意风险：
- 文本绘制要与 `TextPainter` 完全一致（`maxLines: 2`、`ellipsis`、`height: 1.15`、居中），否则会出现基线/省略号差异；
- dpr 变化要重建；主题/图标尺寸/名称变化要重建；
- 显存：14 ×（约 100×96 逻辑 × dpr² × 4 B）≈ 十几 MB，需要在 `dispose` 里释放 `ui.Image`；
- 本项目禁止“整体缩放文字/额外重采样”，此方案不缩放，但要保证与直接绘制同像素。

### H3 壁纸与任务栏玻璃

任务栏 `ShellBackdropBlur`（`plugins/denial_taskbar_custom/lib/src/taskbar.dart:202` 附近）在每帧都要重新采样背景并模糊；壁纸也是一张大图 blit。桌面拖动时整屏重画，这两块是固定成本，可能与插件无关。可让用户临时对比“任务栏玻璃关闭/开启”的拖动帧时间。

### H4 显存

`nvidia-smi` 看 `deniald` 的显存，分别在：登录后空闲、打开启动器后、拖动后。若确认为图标纹理，考虑统一解码档位（`AppIconImage` 的 `cacheWidth` 下限 85 对 24/32 逻辑像素的列表图标是浪费），或设置 `PaintingBinding.instance.imageCache.maximumSizeBytes`。

### 其它可选

- 桌面 `ref.listen(services.windows(...))` 只为一个 activeId，却让 `_windows(monitorId)` 保持存活；若任务栏被关掉，这个订阅就是唯一触发者，可改为更轻的来源或去掉（注意会失去“切换活动窗口后清理选择/悬停”的行为）。
- `app_shelf` 的 `findChildIndexCallback` 用 `apps.indexWhere`，目录变化时 O(可见 × N)，可换预建 map。
- `app_shelf` 的 `_source()` 打开菜单时读 `homeGridControllerProvider`，宿主启动器很可能已保活该 provider（不确定），收益不明，改前先确认。

## 8. 复现与验证清单（下一个代理照着做）

```sh
cd /home/wwt/项目/denial插件/plugins/desk_canvas
/opt/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib test
/opt/dart-sdk/bin/dart analyze --fatal-infos lib test
for f in test/desktop_feedback_test.dart test/refresh_coalescing_test.dart \
         test/desktop_store_test.dart test/desktop_viewport_test.dart; do
  /opt/dart-sdk/bin/dart run "$f" || echo "FAIL $f"
done
/opt/dart-sdk/bin/dart --packages=.dart_tool/package_config.json ../../tools/check_desktop_integration.dart

cd ../app_shelf
/opt/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib test
/opt/dart-sdk/bin/dart analyze --fatal-infos lib test
for f in test/shortcut_writer_test.dart test/launcher_logic_test.dart test/scroll_motion_test.dart; do
  /opt/dart-sdk/bin/dart run "$f" || echo "FAIL $f"
done
```

构建候选（注意第 2 节的异步坑）：

```sh
denial-plugins plan; sleep 25
ID=$(denial-plugins status | jq -r .plan.id)
denial-plugins build "$ID"
grep -rc "<你新增的符号>" ~/.local/state/denial/plugins/candidates/"$ID"/packages/
```

应用由用户执行（`denial-plugins activate <ID>` 或插件管理器），不要代劳。

## 9. 一句话总结

确定性结论：**没有常驻任务，也没有轮询；拖动时是每帧成本，UI 与光栅各占一半。** 已把桌面插件每帧的 Dart 成本压到接近零、把它的模糊通道减到四分之一；若仍不够，下一步必须先做“关闭 Desk Canvas / 关闭 Taskbar”的 A/B 采样来归属剩余成本，再决定改谁——不要在没有归属数据时继续改绘制细节。
