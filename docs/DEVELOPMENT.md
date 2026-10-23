# 集合中的独立插件开发准备

根目录不是 Dart 包。下面的准备适用于新插件；在目标插件目录运行依赖、格式化与分析。已存在插件的功能检查以其自身 README 为准。

## 使用匹配的本机工具

先准备目标 Denial 安装提供的编译套件：

```sh
denial-plugins prepare
PLUGIN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/denial/plugins"
PLUGIN_FLUTTER="$(jq -er '.flutter' "$PLUGIN_STATE/configuration.json")"
PLUGIN_RUNTIME="$(jq -er '.runtime' "$PLUGIN_STATE/configuration.json")"
PLUGIN_FLUTTER_ROOT="$(dirname "$(dirname "$PLUGIN_FLUTTER")")"
PLUGIN_DART="$PLUGIN_FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
```

这些变量需要在同一个终端使用。命令依赖 `jq`。不要以系统任意版本 Flutter 替换 Denial 的匹配工具；Denial 更新后重新确认工具和 SDK。

## 本地 SDK 路径

在目标插件目录创建 `pubspec_overrides.yaml`，将下方 `/ABSOLUTE/RUNTIME` 换成 `PLUGIN_RUNTIME` 的实际值。YAML 不展开 shell 变量。

```yaml
dependency_overrides:
  denial_sdk:
    path: /ABSOLUTE/RUNTIME/packages/denial_sdk
  denial_flutter_sdk:
    path: /ABSOLUTE/RUNTIME/packages/denial_flutter_sdk
```

该文件已由根 `.gitignore` 忽略。机器路径只放在这个文件，不写入可分发的 `pubspec.yaml`，不复制 SDK。插件管理器安装 Git 来源时提供自己的 SDK overrides。

## 检查与集成

```sh
"$PLUGIN_FLUTTER" pub get
"$PLUGIN_DART" format --output=none --set-exit-if-changed lib
"$PLUGIN_DART" analyze --fatal-infos lib
```

存在 `test/` 后，将实际测试目录纳入格式化和分析，并运行插件 README 列出的相关测试。无界面检查不启动桌面 UI。只有需要整体兼容性验证时才生成并构建候选，使用 `plan` 实际返回的 ID；不把来源添加、计划、构建和激活混为一步。

根 `plugins.yaml` 只是仓库来源索引，不会修改本机插件选择。Git 安装前还需把对应代码发布到仓库；仅修改本地索引不代表远端已经有这些包。

## 桌面与启动器的联合检查

在 Desk Canvas 目录执行独立 Dart 检查，不要求根目录成为 Dart 包：

```sh
cd plugins/desk_canvas
"$PLUGIN_DART" --packages=.dart_tool/package_config.json ../../tools/check_desktop_integration.dart
```

该检查让 App Shelf 向临时 XDG 桌面写入真实 `.desktop`，验证 Desk Canvas 的目录事件、本地化显示、重复发送、同名冲突、删除、桌面目录禁用／默认目录回退、无效配置修复和目录删除重建后的自动恢复；另验证真实重命名后端拒绝覆盖目标且保留两份内容。所有文件都在临时目录，不读取或修改用户桌面，不启动应用，不访问回收站。

需要候选构建但不改变当前选择时，可通过正式 CLI 的 `--state /ABSOLUTE/ISOLATED_STATE` 使用独立管理器状态：先 `initialize`，在该隔离状态中选择目标插件，再生成和构建候选。隔离候选不属于默认管理器列表；后续正式安装仍需按目标插件 README 添加来源、选择和构建。不要手改管理器内部状态文件或把隔离构建当作已激活。

公开契约与工具流程以[上游开发说明](https://github.com/denialwm/denial-plugins/blob/4b7adf998852b09b9a91c1cfab48be58debf2e80/docs/DEVELOPMENT.md)、[插件系统](https://github.com/denialwm/denial/blob/dev/docs/PLUGIN_SYSTEM.md)、[插件管理器](https://github.com/denialwm/denial/blob/dev/docs/PLUGIN_MANAGER.md)及当前安装为准。
