# OrbSweep

[![Build and release](https://github.com/iepngs/orbsweep/actions/workflows/release.yml/badge.svg)](https://github.com/iepngs/orbsweep/actions/workflows/release.yml)

一个用 SwiftUI 编写的 macOS 原生 OrbStack 清理工具。扫描容器、镜像、数据卷、网络和构建缓存，预览待删除内容，再按类别清理。

顶部的系统磁盘卡片显示启动磁盘总容量、已使用和剩余空间，并用进度条呈现占用比例。占用达到 85% 时显示橙色、95% 时显示红色；随扫描和清理更新，即使 OrbStack 未启动也能读取。容量采用 macOS 文件系统提供的实际空闲空间，已使用 = 总容量 − 剩余空间；APFS 共享空间、快照和可清除数据可能导致结果与 Finder 的「可用」容量不同。

## 下载与运行

在 [Releases](https://github.com/iepngs/orbsweep/releases) 下载 `OrbSweep-<版本>-macOS-universal.zip`，解压后双击 `OrbSweep.app`，也可以把它拖到「应用程序」目录。

- macOS 13 或以上。
- 已安装并启动 OrbStack，Docker CLI 可用。
- Release 应用同时支持 Apple Silicon 和 Intel。

应用使用本机 ad-hoc 签名，尚未使用 Apple Developer ID 签名或公证；从 GitHub 下载后可能需要在 macOS「系统设置 → 隐私与安全性」中批准打开。

### App 内更新

左下角版本号旁的「检查更新」，或 OrbSweep 菜单里的「检查更新…」，会查询本仓库最新的正式 Release。发现新版后显示版本、更新说明和安装包大小，点击「安装并重启」即可下载并替换当前 App。不会后台自动下载或安装；扫描、清理期间更新入口不可用。

更新使用现有 CI 发布的 universal ZIP，无需另外维护更新源。安装前核对 GitHub Release 的 SHA-256、安装包目录结构、Bundle ID、版本、macOS 最低版本与代码签名；下载或验证失败会保留当前 App。替换或打开失败时尝试恢复旧 App，安装日志在 `~/Library/Logs/OrbSweep-update.log`。

请将 App 放在有写入权限的「应用程序」目录中；只读磁盘映像或无写入权限的位置无法原地更新。当前使用 GitHub HTTPS 与附件摘要验证下载来源和完整性，ad-hoc 签名不提供 Developer ID 开发者身份验证。旧版没有更新入口，需要先手动安装一次包含此功能的版本。

## 使用

1. 打开应用，等待只读扫描完成。
2. 点击类别，查看该类别的待清理资源；通过复选框选择需要清理的类别。
3. 点击「清理所选」，检查摘要并确认永久删除。
4. 查看执行记录与重新扫描后的占用情况。

默认勾选镜像、网络和缓存。已停止容器、volumes 默认不勾选；删除 volumes 必须额外勾选数据删除确认。

> **未使用不等于没有价值。** 未被容器引用的数据库和命名卷也可能包含重要数据，删除后无法通过本应用恢复。删除已停止容器，也会删除该容器可写层中的文件。

## 清理规则

所有操作固定指向 `docker --context orbstack`，不切换当前 Docker context，不操作其他 Docker 环境或 OrbStack Linux 虚拟机。

| 类别 | 待清理条件 | 保护方式 |
| --- | --- | --- |
| 已停止容器 | 状态为 `exited` 或 `dead` | 删除前重新检查状态；不强制删除 |
| 镜像 | 没有被任何容器引用，含有标签的镜像 | 使用完整镜像 ID；不强制删除 |
| Volumes | 没有被任何容器引用，含命名卷 | 已停止、暂停、未启动容器的引用也会保留；不强制删除 |
| 网络 | 没有容器连接的自定义网络 | 保留 `bridge`、`host`、`none`；不强制删除 |
| 构建缓存 | Docker 默认 builder 判定可回收的缓存 | 由 `docker builder prune --all --force` 在执行时判断，不操作自定义 buildx builder |

运行中、暂停、重启中和尚未启动的容器不会成为清理候选项。扫描后被占用的资源由 Docker 的非强制删除规则再次保护；无法删除的资源会保留并记录原因。

容器、镜像、volumes 和网络只清理确认时的扫描列表。删除容器后才变为空闲的镜像和 volumes，会在下一次扫描中显示，需要再次确认；缓存按执行时的状态回收。

空间卡片来自 `docker system df`，展示整类资源占用与 Docker 估算的可回收量，不代表当前选择实际能释放的空间。多标签镜像可能被 Docker 拒绝通过 ID 删除，程序会保留并显示原因。应用不会后台自动清理。

## 本地开发

需要 Swift 5.9 或以上和 macOS 编译 SDK。可以安装 Xcode 或 Command Line Tools；项目没有第三方 Swift 依赖。

```bash
git clone git@github.com:iepngs/orbsweep.git
cd orbsweep
make app
```

产物位于 `dist/OrbSweep.app`。也可以用 Xcode 打开 `Package.swift` 编辑和运行。

| 命令 | 用途 |
| --- | --- |
| `make app` | 编译当前 Mac 架构，生成应用图标与 Info.plist，并签名验证 |
| `make run` | 编译并打开应用 |
| `make check` | 检查清理安全规则、更新版本比较、摘要校验、目录保护及安装回滚，无需 OrbStack |
| `make check-live` | 上述检查加 OrbStack 实机只读扫描，不执行删除 |
| `make package VERSION=1.0.0 UNIVERSAL=1` | 编译 Apple Silicon + Intel 通用应用并生成 ZIP |
| `make clean` | 删除编译缓存和 `dist` 下的构建产物 |

安全检查采用独立可执行目标，可在没有 XCTest 的 Command Line Tools 环境运行。`.build/`、`dist/`、`.app`、`.zip` 和 `.dmg` 均由 Git 忽略，仓库只保存源代码与构建配置。

## 自动发布

[GitHub Actions](https://github.com/iepngs/orbsweep/actions/workflows/release.yml) 在推送到默认分支 `master` 时自动执行，也支持在 Actions 页面手动运行：

1. 在 macOS runner 上运行安全规则检查。
2. 编译 Apple Silicon + Intel 通用应用，生成图标，执行 ad-hoc 签名和架构验证。
3. 打包为 `OrbSweep-1.0.<run_number>-macOS-universal.zip`。
4. 创建指向该次提交的 `v1.0.<run_number>` 标签与 GitHub Release，并上传压缩包。

版本号取自此工作流的 `github.run_number`，并同步写入应用版本。重复运行同一工作流会更新同版本 Release 的附件。发布使用 GitHub 自动提供的 `GITHUB_TOKEN`，无需配置个人访问令牌；工作流需要仓库的 `contents: write` 权限。CI 不连接个人 OrbStack 环境，也不执行实际数据清理。

## 项目结构

```text
Sources/CleanupCore/          Docker 调用、扫描、清理规则
Sources/UpdateCore/           Release 校验、安装包验证与更新替换
Sources/OrbSweep/             SwiftUI 界面与应用入口
Tests/CleanupCoreTests/       可独立运行的安全检查
scripts/build-app.sh          编译与 .app 打包
scripts/make-icon.swift       生成应用图标
scripts/verify-app.sh         验证签名和通用架构
Makefile                     本地构建入口
.github/workflows/release.yml 自动编译与发布
```
