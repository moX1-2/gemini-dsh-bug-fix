# DSH Desktop 的 Gemini 工具调用补丁

## 版本号

适用于 Windows Electron 版 DeepSeek Harness Desktop `0.2.0-rc.2`，构建提交 `04f392c9ddd144fa426da2045178797da6db6c11`。安装脚本会校验原始归档与文件哈希，其他构建不会应用补丁。

## 任务背景

在该版本中，Gemini 有时调用 `run_code` 时只生成 `description`，漏掉必填的 `code`，导致 `missing required property "code"`。针对上述版本的本地测试已通过，包括补丁安装、回退及 DSH Desktop 工具调用。

**这是破坏性修改。**补丁会直接改动 DSH Desktop 安装目录中解包后的打包 JS 代码。更新 DSH 后应重新核对补丁，不应直接套用到其他版本。

## 修改方法

`install.ps1` 使用 `npx` 解包 `app.asar`，再由 PowerShell 按 `patch-spec.json` 精确修改两处 `run_code` 实现。给模型的参数表不再提供 `description`，本地运行时仍兼容旧调用中的该字段，并在缺少标题时显示“执行代码”。原始归档保存为 `app.asar.original`。安装过程无需 Git，`run-code.patch` 供查看差异。

使用者也可以参考这里的修改点，将同一思路实现为 DSH 插件；本仓库当前提供的是安装目录补丁。

## 操作方法

需要 Windows PowerShell 5.1 或更新版本，以及 Node.js 的 `npx`。在本仓库点击 **Code → Download ZIP**，解压到任意目录。完全退出 DSH Desktop 后，在解压目录运行：

~~~powershell
.\install.ps1 -InstallDir 'D:\dsh'
~~~

`InstallDir` 填写包含 `DeepSeek Harness.exe` 的目录。安装后启动 DSH Desktop，新建会话测试。需要回退时，完全退出程序后运行：

~~~powershell
.\rollback.ps1 -InstallDir 'D:\dsh'
~~~
