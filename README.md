# DSH (DeepSeek Harness) 的 Gemini 工具调用加固补丁

适用于 Windows Electron 版与 Linux Node.js 版 DeepSeek Harness。

## 背景与问题诊断

在原生 DSH 中接入 Gemini 模型（如 `gemini-3.8-flash`、`gemini-2.5-flash` 等）进行工具调用时，常出现一系列深层兼容性陷阱：

1. **参数缺失异常 (`missing required property "code"`)**：
   - Gemini 有时调用 `run_code` 时只生成 `description`，漏掉必填的 `code`。
   - 某些代理返回双重转义 JSON 字符串或外层包裹 Markdown 代码块（如 ```json ... ```），导致 DSH 参数解析器将其识别为普通字符串而非 Object，导致字段判定丢失。
2. **Markdown Fences 代码语法错误 (`SyntaxError: Unexpected token '`'`)**：
   - Gemini 极其习惯在 `code` 参数内包裹 ```typescript ... ``` 代码块标记，DSH 本地 Node.js 运行时动态编译时直接语法报错中断。
3. **直接调用子工具的折叠陷阱 (`only run_code is callable directly`)**：
   - Gemini 受模型指令对齐影响，倾向于直接调用顶级子工具（如直接 call `read`、`write`、`glob`、`pwsh`），而 DSH 默认只允许顶级调用 `run_code`，直接发起子工具会被 DSH 判定为 `ToolNotFoundError` 并报错拒绝。
4. **Linux 运行时下 CLI 入口静默退出问题**：
   - `/usr/bin/dsh` 入口代码使用 `if (import.meta.main) await runCli();`，在 Node.js 20 下 `import.meta.main` 为 `undefined`，导致执行 `dsh` 命令时静默退出。

---

## 解决方案（综合加固）

本补丁提供了多层防护方案：

### 1. 运行时参数与代码清洗 (Runtime Sanitization)
- **参数键名对齐与双重解包**：在参数反序列化阶段自动清理外层 Markdown 标记，支持双重 JSON 解析，并将模型偶发生成的 `program` / `script` / `command` 自动映射回 `code`。
- **自动剥离 Markdown Fences**：在 `run_code` 执行前自动检测并剥离首尾的代码块标记（如 ```ts`、```javascript`），确保 eval/AsyncFunction 语法绝对合法。

### 2. 顶级子工具自动升格包装 (Auto-Wrapping Collapsed Tools)
- 当检测到 Gemini 直接发起 `read`、`write`、`glob`、`pwsh` 等子工具调用时，底层调度器不再报错中断，而是**自动将其包装合成为标准的 `run_code` 脚本程序**：
  ```javascript
  return await tools[name](args);
  ```
  实现原生 Direct Tool Call 与 PTC（程序化工具调用）的双向全兼容！

### 3. Schema 契约简化
- 将 `run_code` 的 `description` 降级为可选参数，模型只需专注于生成 `code` 主体，本地运行时缺少标题时自动兜底显示“执行代码”。

### 4. Linux Node.js 入口修正
- 修正 CLI 入口自执行判断，确保 `dsh` 全局命令在 Linux 和 Windows 终端下均可原生正常启动。

---

## 快速使用方法

### 方式一：Windows Electron Desktop 一键修补

需要 Windows PowerShell 5.1 或更新版本，以及 Node.js 的 `npx`。完全退出 DSH Desktop 后，在解压目录运行：

```powershell
.\install.ps1 -InstallDir 'D:\dsh'
```

如需回退，运行：

```powershell
.\rollback.ps1 -InstallDir 'D:\dsh'
```

### 方式二：DSH 解包环境 / 源码直接热修补 (Linux / Windows)

如果你的 DSH 运行在解包环境或 Linux 生产服务器上，可以直接运行内附的 Node.js 热修补脚本：

```bash
node patch-runtime.mjs
```

---

## 验证与测试

安装补丁后启动 DSH，在会话中尝试：
1. 要求 Gemini 运行一段代码（测试 `run_code` 剥离反引号与参数容错）。
2. 让 Gemini 直接读取某文件（测试直接子工具自动升格包装）。
3. 观察工具调用卡片与执行结果，确认无报错流畅流转。
