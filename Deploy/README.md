# 局域网热分发部署

推送 `v*` Tag 后，GitHub Actions 会编译并发布 `SDGO-Toolbox.exe` 与 `version.json`。

GitHub-hosted runner 通常不能访问内网 SMB/NAS。工作流的 `deploy-lan` job 使用标签为 `self-hosted`、`windows`、`sdgo-lan` 的局域网 Runner 自动同步。请将 GitHub Actions Runner 安装在一台既能访问 NAS 又能访问 GitHub 的局域网电脑或服务器上，并在仓库 **Settings → Secrets and variables → Actions → Variables** 设置 `LAN_SHARE_PATH=\\192.168.1.100\Share\Software`。该节点的运行账户必须对共享目录有写入权限。

如果暂时未部署自托管 Runner，可在同类节点上手动执行同步：

```powershell
.\Deploy\Sync-ReleaseToLanShare.ps1 -Repository 'OWNER/REPOSITORY' -SharePath '\\192.168.1.100\Share\Software' -Tag 'v2.2.2'
```

若本机 PowerShell 执行策略禁止脚本，使用单次绕过方式运行（不修改系统策略）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Deploy\Sync-ReleaseToLanShare.ps1 -Repository 'OWNER/REPOSITORY' -SharePath '\\192.168.1.100\Share\Software' -Tag 'v2.2.2'
```

也可由 Windows Task Scheduler 每 5 分钟运行一次；省略 `-Tag` 即同步最新 Release。同步脚本先写 EXE、最后写 `version.json`，避免客户端看到未完整发布的版本；脚本会校验 EXE 的 SHA-256 后才发布。

在 NAS 创建 `\\192.168.1.100\Share\Software`：同步节点有写权限，客户端只有读取权限。首次测试可把 [version.json.template](version.json.template) 按实际版本另存为共享目录的 `version.json`。客户端在 `Data/Settings.ini` 的 `[Updater]` 中配置同一共享目录。

编译后的客户端启动时，只会在共享目录的版本高于内置 `APP_VERSION` 且下载文件的 SHA-256 与清单一致时，才会退出、替换自身并重启；源码 `.ahk` 运行不会更新。发布前将 `SDGO工具脚本.ahk` 的 `APP_VERSION` 改为 Tag 对应版本，例如 `v2.2.2` 对应 `2.2.2`；CI 会拒绝 Tag 与内置版本不一致的发布。
