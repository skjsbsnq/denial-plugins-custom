# Denial 自定义插件集合

这里用于开发和维护个人的 Denial 插件。每个插件放在 `plugins/` 下的独立目录中，拥有自己的包名、依赖、说明和许可证，分别安装、选择与构建。以后新增插件时，在这里增加目录和索引即可。

## 插件索引

| 插件 | 包名 | 说明 |
| --- | --- | --- |
| [Custom Taskbar](plugins/denial_taskbar_custom/README.md) | `denial_taskbar_custom` | 自定义任务栏，包含独立控制中心、网络与蓝牙二级菜单。 |

各插件的功能、配置、安装注意事项和检查命令，见对应目录的 README。

项目开发与代理协作约定见 [AGENTS.md](AGENTS.md)。

## 项目结构

```text
.
├── README.md                       # 集合说明与插件索引
├── AGENTS.md                       # 开发与代理协作约定
├── plugins/
│   └── denial_taskbar_custom/       # 一个可独立选择的插件包
│       ├── README.md
│       ├── pubspec.yaml
│       ├── LICENSE
│       ├── lib/
│       └── test/
├── plugins.yaml                    # 本集合的插件来源索引
└── upstream/                       # 可选的本地参考副本，不上传 Git
```

根目录用于组织插件，当前不是 Dart 包或 Pub workspace。依赖解析、分析和测试应进入具体插件目录执行。`upstream/` 用于对照官方实现，自定义功能在 `plugins/` 中维护。

## 从 GitHub 安装

仓库：[skjsbsnq/denial-plugins-custom](https://github.com/skjsbsnq/denial-plugins-custom)。根目录不是插件包，添加时指定任务栏子目录：

```sh
denial-plugins prepare
denial-plugins --path plugins/denial_taskbar_custom add https://github.com/skjsbsnq/denial-plugins-custom.git
denial-plugins plan
```

在插件管理器中选择 **Custom Taskbar** 并关闭原来的 **Taskbar**，然后构建 `plan` 返回的候选 ID：

```sh
denial-plugins build CANDIDATE_ID
```

构建完成后由用户应用候选。源码仓库不包含 SDK、编译套件或预编译桌面 bundle；它们由目标 Denial 安装提供。

## 本地开发与使用

准备与当前 Denial 安装匹配的插件管理器和编译工具。从本项目根目录添加所需插件，例如：

```sh
denial-plugins prepare
denial-plugins --local add "$PWD/plugins/denial_taskbar_custom"
denial-plugins plan
```

按照 `plan` 的结果处理提供者选择，再构建返回的候选 ID：

```sh
denial-plugins build CANDIDATE_ID
```

将 `CANDIDATE_ID` 替换为实际 ID。构建完成后，在插件管理器中应用；也可以执行 `denial-plugins activate CANDIDATE_ID`。添加、选择、构建和激活是不同步骤。

修改本地源码后，需要重新生成候选、构建并应用。本地目录和 Git 仓库是两种来源；本项目当前机器上的插件来源仍为本地目录，上传仓库不会自动替换来源或激活候选。

## 新增插件

1. 在 `plugins/` 下创建独立目录，例如 `plugins/your_plugin/`，并使用唯一的 Dart 包名。
2. 添加自己的 `pubspec.yaml`、插件入口、README 和许可证；按需添加测试及资源文件。
3. 使用 Denial 公共 SDK，依赖版本与目标 Denial 安装匹配。普通 Dart／Flutter 组件库通过该插件自己的 `dependencies` 声明。
4. 在插件目录完成依赖解析、静态分析和相关检查，再通过插件管理器添加与构建。
5. 更新上方插件索引，将具体功能和使用说明留在该插件自己的 README 中。

若多个插件提供相同的独占能力，需要在插件管理器中明确选择提供者。未来需要共享代码时，可按需建立 `packages/`；普通共享库与可安装插件分开存放。

本机 SDK 路径通过 `pubspec_overrides.yaml` 配置，该文件已忽略，不应作为分发依赖提交。详细开发流程可参考[上游开发说明](https://github.com/denialwm/denial-plugins/blob/4b7adf998852b09b9a91c1cfab48be58debf2e80/docs/DEVELOPMENT.md)，并以当前安装的 Denial SDK 和工具要求为准。`upstream/` 仅用于可选的本地参考，Git 仓库不包含该副本。

## 来源与许可证

当前任务栏基于 [denialwm/denial-plugins](https://github.com/denialwm/denial-plugins) 的官方 `denial_taskbar` 复制，具体来源提交和许可证见其[插件说明](plugins/denial_taskbar_custom/README.md)。

各插件保留各自的来源、版权及许可证要求。当前任务栏按 GPL-3.0-or-later 分发，保留上游版权；Stats 参考部分的 MIT 许可见插件内的 `third_party/stats-LICENSE`。GPL 全文见 [LICENSES/GPL-3.0-only.txt](LICENSES/GPL-3.0-only.txt)。新增或复制插件时，应在对应目录记录这些信息。
