# Arknights 官服 / B服 客户端去重工具

**中文** | [English](README.en.md)

一键让《明日方舟》**官服**与 **B服** 两个 PC 客户端共享磁盘上的相同文件，在**不下载第二份、不切换、不影响正常游玩**的前提下，节省约一半磁盘占用。

## 原理

惯例上，官服和 B 服是两个独立客户端（各自 20+ GB）。但它们的**游戏资源逐字节相同**，真正的区别只在一层“登录渠道”（渠道 SDK、可执行文件、渠道配置等）。

本工具会：

1. 自动探测官服与 B 服的安装目录；
2. 逐个用 MD5 比对两份客户端的同路径文件；
3. 对**内容完全一致**的文件，删除 B 服副本并改为指向官服的 **NTFS 硬链接**（内容不变、对程序透明）；
4. **内容不同**的文件（`Arknights.exe`、`GameAssembly.dll`、渠道 SDK 等）以及 B 服独有文件保持独立副本。

结果：两个客户端都保持原样、各自启动器可正常使用，磁盘实际占用从 `≈53 GB` 降到 `≈27 GB`。

## 系统要求

- Windows 10 / 11
- PowerShell 5.1（系统自带）
- 官服与 B 服位于**同一磁盘分区**（硬链接的要求）
- 磁盘文件系统为 NTFS

## 使用方法

### 方式一：单文件版（最简单，推荐）
从 [Releases](https://github.com/linksoceancat/arknights-client-dedup/releases/latest) 下载 **`ArknightsDedup-standalone.bat`**，放到任意文件夹双击运行即可。
整个工具都在这一个文件里，首次运行会在同目录自动解压出 `ArknightsDedup.ps1` 并启动，之后按菜单操作。

> 若系统提示 SmartScreen/脚本安全，选择“仍要运行”即可（脚本未签名，属正常现象）。

### 方式二：完整版
1. 下载/克隆本仓库（或 Release 里的 zip 并解压）。
2. 双击 **`Start.bat`**。
3. 按菜单操作：
   - `[1] 扫描并去重`
   - `[2] 查看当前状态`
   - `[3] 回滚`
   - `[4] 重新探测 / 设置客户端路径`

也可以命令行调用：

```powershell
powershell -ExecutionPolicy Bypass -File .\ArknightsDedup.ps1 -Action Dedup
powershell -ExecutionPolicy Bypass -File .\ArknightsDedup.ps1 -Action Status
powershell -ExecutionPolicy Bypass -File .\ArknightsDedup.ps1 -Action Rollback
```

首次运行若自动探测失败，会提示手动输入两个客户端的**游戏根目录**（即包含 `Arknights.exe` 的文件夹），并保存到 `config.json`。

## 目录结构

```
ArknightsDedup.ps1   主程序（菜单 + 去重/回滚/状态）
Start.bat            一键启动入口
build-standalone.ps1 打包：把主程序内嵌成单文件 .bat（输出到 dist/）
config.json          客户端路径（首次运行自动生成）
data/
  manifest.csv       比对结果（同路径同大小文件是否一致）
  rollback.csv       可回滚的文件清单
  run.log            运行日志
```

## 游戏更新后

大版本更新会替换文件，被替换的硬链接会**自然断开**，对应文件变回独立副本、占用回升（安全）。更新完并把两个客户端都更到同一版本后，**再次运行 `[1] 扫描并去重`** 即可把新的相同文件重新链接。

> 注意：不要在某个客户端正在打补丁时运行本工具；建议先关闭所有游戏与启动器。

## 回滚

菜单 `[3] 回滚` 会把所有硬链接还原为 B 服的独立文件副本（内容不变，只是不再共享空间）。回滚依据 `data/rollback.csv`。

## 注意事项

- 本工具**只读取文件内容做比对**，再建立硬链接，不修改任何游戏内容。
- 由于内容一致才链接，按内容校验的反作弊不受影响。
- 同一时刻建议只运行一个客户端（硬链接下，理论上“原地改写”共享文件可能相互影响，概率极低）。
- 请自行评估在游戏客户端上使用本工具的风险并遵守相关服务条款。

## 许可证

[MIT](LICENSE)

## 免责声明

本工具为第三方开源工具，与鹰角网络 / 哔哩哔哩无任何关联。使用风险自负。
