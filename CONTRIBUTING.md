# 贡献指引

感谢你愿意为 UESSH 出一份力！提交 Issue 或 PR 之前，请花几分钟读完这份指引。它说明了怎么搭建开发环境、我们对 PR 的要求，以及使用 AI 辅助开发时需要遵守的规定。

## 目录

- [提交 Issue](#提交-issue)
- [搭建开发环境](#搭建开发环境)
- [项目结构](#项目结构)
- [提交 PR](#提交-pr)
- [AI 辅助开发规定](#ai-辅助开发规定)
- [安全问题](#安全问题)
- [许可证](#许可证)

## 提交 Issue

- **报告 Bug**：请写清楚系统版本（macOS / Windows 及版本号）、UESSH 版本（在「设置」页底部）、复现步骤、期望结果和实际结果。有截图或日志更好（「设置 → 诊断」里可以查看日志）。
- **功能建议**：先说说你想解决什么问题，再说你设想的做法。
- 提交前请先搜索一下，看看是否已经有人提过。
- 日志和截图里**不要出现**服务器地址、用户名、密码、私钥、API Key 等敏感信息，贴出来之前请先打码。

## 搭建开发环境

### 需要准备

- **Flutter 3.47.9**（stable 渠道，Dart 3.13）。请尽量和 CI 使用同一个版本，版本号以 [`.github/workflows/release.yml`](.github/workflows/release.yml) 里的 `FLUTTER_VERSION` 为准。
- **macOS 开发**：Xcode 和命令行工具。
- **Windows 开发**：Visual Studio 2022，安装时勾选「使用 C++ 的桌面开发」。

### 运行

```bash
git clone git@github.com:ueeedev/uessh.git
cd uessh
flutter pub get
flutter run -d macos     # Windows 上换成 -d windows
```

### 常用命令

| 用途 | 命令 |
| --- | --- |
| 格式化代码 | `dart format lib test` |
| 静态检查 | `flutter analyze` |
| 运行全部测试 | `flutter test` |
| 修改文案后重新生成本地化代码 | `flutter gen-l10n` |
| 打包 macOS DMG | `tool/build_macos_dmg.sh` |

### 连接真实服务器的测试

[`test/ssh_live_test.dart`](test/ssh_live_test.dart) 会连接一台真实的 SSH 服务器，测试执行命令、断线重连、文件浏览等功能。没有设置下面的环境变量时，这些测试会自动跳过：

```bash
UESSH_TEST_HOST=你的测试服务器 UESSH_TEST_USER=用户名 UESSH_TEST_PASSWORD=密码 \
  flutter test test/ssh_live_test.dart
```

可选：`UESSH_TEST_PORT`（默认 22），以及用于密钥登录的 `UESSH_TEST_KEY_FILE`、`UESSH_TEST_KEY_PASSPHRASE`。

> [!WARNING]
> 请只用**专门用于测试**的服务器。服务器信息只能通过命令行的环境变量传入，**绝对不要**写进代码、测试文件、脚本或提交记录。

## 项目结构

```
lib/
├── core/          # 加密保险库、日志、JSON 文件读写等基础设施
├── features/
│   ├── hosts/     # 主机列表、主机卡片、编辑页
│   ├── keys/      # SSH 密钥
│   ├── snippets/  # 命令片段
│   ├── forwarding/ # 端口转发
│   ├── terminal/  # SSH 会话、标签页、分屏工作区、自动重连、命令高亮
│   ├── files/     # SFTP 文件浏览器、上传下载
│   ├── ai/        # AI 助手：服务商、对话、命令执行与安全分级
│   ├── settings/  # 设置页
│   └── security/  # 主密码、锁屏
├── l10n/          # 中英文文案（app_zh.arb 为模板）
├── shell/         # 窗口外壳、导航、托盘 / 菜单栏
└── widgets/       # 通用组件
test/              # 测试
tool/              # 打包和图标生成脚本
release-notes/     # 每个版本的更新说明
```

## 提交 PR

### 开始之前

- **小改动**（修 Bug、改文案、补测试）可以直接提 PR。
- **大改动**（新功能、改界面结构、重构）请先开一个 Issue 讨论，确认方向后再动手，免得白费功夫。
- **新增第三方依赖**要在 Issue 或 PR 里说明理由：为什么需要它、有没有更轻的替代方案，以及它的许可证是否和 GPL-3.0 兼容。

### PR 要求

1. **一个 PR 只做一件事。** 不相关的改动请分开提交。
2. **能通过检查。** 提交前请在本地确认：
   - `dart format` 之后没有格式差异
   - `flutter analyze` 没有任何问题
   - `flutter test` 全部通过
3. **有测试。** 修 Bug 请附上能复现这个 Bug 的测试；新功能请覆盖主要的使用路径。
4. **两种语言都要有。** 界面文字不要写死在代码里，请在 `lib/l10n/app_zh.arb` 和 `app_en.arb` 里**同时**添加，然后运行 `flutter gen-l10n`。
5. **两个平台都要考虑。** 涉及窗口、快捷键、文件路径、拖放等功能时，请说明在 macOS 和 Windows 上分别测试过没有。
6. **界面改动请附截图**，最好浅色和深色模式各一张。
7. **PR 描述**里写清楚改了什么、为什么改、怎么测试的，有关联的 Issue 请一并写上（如 `Closes #12`）。

### 代码风格

- 遵循 [`analysis_options.yaml`](analysis_options.yaml) 中的规则和 `dart format` 的格式。
- 注释用英文，写清楚**为什么**这样做，而不是复述代码在做什么。
- 状态管理使用 Riverpod，界面遵循 Material Design 3，请和现有代码保持一致。

### 提交信息

- 使用英文，第一行用祈使句简单概括改动，例如 `Fix file list flicker after running a command`。
- 需要时空一行再写详细说明。

### 版本与发布

版本号和发布由维护者负责，PR 中**不需要**修改 `pubspec.yaml` 里的 `version`。发布新版本时，维护者会在 `release-notes/版本号.md` 里写好更新说明，推送到 `main` 后由 GitHub Actions 自动构建并发布。

## AI 辅助开发规定

我们**允许**使用 AI 工具（如 Claude Code、Copilot、ChatGPT、Cursor 等）辅助开发，但必须遵守以下规定：

1. **你对提交的每一行代码负责。** 不管代码是谁写的，提交前你都必须读懂它、检查过它、亲自运行和测试过它。被问到为什么这样写时，你需要能够解释清楚。
2. **在 PR 中说明 AI 参与了哪些部分。** 请在 PR 描述里写明使用了什么工具、AI 参与了哪些部分（例如「测试用例由 AI 生成，人工检查后修改」）。提交信息里保留工具添加的 `Co-Authored-By` 标记也可以。
3. **不接受未经审查的批量生成内容。** 大段未经整理的 AI 生成代码、与项目风格明显不符的代码、虚构的 API 或依赖，以及 AI 生成的空泛 PR 描述和 Issue，都会被直接关闭。
4. **不要把敏感信息交给 AI 工具。** 服务器地址、密码、私钥、API Key、日志中的真实数据，都不要粘贴进任何 AI 工具。
5. **AI 生成的代码同样需要测试。** 尤其是边界情况和错误处理，不能只测「正常情况能跑」。
6. **注意版权。** 不要提交 AI 从其他项目大段复制而来、许可证不兼容的代码。

### 涉及安全的代码请格外小心

以下部分直接关系到用户的服务器和数据安全，修改时请在 PR 中**详细说明**改动及其影响，并补充对应测试：

- `lib/core/vault.dart`：凭据加密
- `lib/features/terminal/known_hosts.dart`：主机指纹校验
- `lib/features/ai/command_safety.dart`：判断 AI 执行的命令是否安全
- `lib/features/ai/ai_chat.dart`：AI 执行命令前的确认流程

**特别提醒：** 修改 AI 助手执行命令相关的逻辑时，不能让 AI 绕过用户确认去执行危险命令。

## 安全问题

如果你发现了安全漏洞（例如凭据泄露、AI 可以绕过确认执行危险命令），**请不要公开提交 Issue**。请通过 GitHub 仓库的 [Security → Report a vulnerability](https://github.com/ueeedev/uessh/security/advisories/new) 私下报告。我们修复之后会公开致谢。

## 许可证

UESSH 基于 [GNU 通用公共许可证第 3 版（GPL-3.0）](https://www.gnu.org/licenses/gpl-3.0.html) 授权。提交 PR 即表示你同意你的贡献也以 GPL-3.0 授权发布。
