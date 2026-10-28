#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const candidateDirs = [
  process.argv[2],
  process.env.DSH_DIR,
  '/usr/lib/node_modules/@deepseek-ai',
  'D:\\dsh\\resources\\app\\dsh',
  'C:\\Program Files\\DeepSeek Harness\\resources\\app\\dsh',
].filter(Boolean);

let dshRoot = null;
for (const dir of candidateDirs) {
  try {
    if (fs.existsSync(dir)) {
      dshRoot = dir;
      break;
    }
  } catch {}
}

if (!dshRoot) {
  console.error('未自动找到 DSH 安装路径，请显式指定路径，如: node patch-runtime.mjs /path/to/dsh');
  process.exit(1);
}

console.log('[*] 正在对 DSH 运行时进行 Gemini 工具调用深度加固:', dshRoot);

function safePatch(filePath, patches) {
  if (!fs.existsSync(filePath)) {
    console.warn('[-] 跳过不存在的文件:', filePath);
    return false;
  }
  let content = fs.readFileSync(filePath, 'utf-8');
  let modified = false;
  for (const { name, search, replace } of patches) {
    if (content.includes(search)) {
      content = content.replace(search, replace);
      console.log('  [+] 已应用补丁:', name);
      modified = true;
    } else {
      console.log('  [~] 已存在或未匹配:', name);
    }
  }
  if (modified) {
    fs.writeFileSync(filePath, content, 'utf-8');
    console.log('[✓] 文件更新完成:', filePath);
  }
  return modified;
}

let nodeModules = dshRoot.endsWith('@deepseek-ai') ? dshRoot : path.join(dshRoot, 'node_modules', '@deepseek-ai');
if (!fs.existsSync(nodeModules)) {
  nodeModules = dshRoot;
}

const toolsFile = path.join(nodeModules, 'dsh-tools', 'lib', 'index.js');
safePatch(toolsFile, [
  {
    name: '修正已存在的只读 args.code 赋值为浅拷贝解冻对象',
    search: 'if (typeof args.code === "string") args.code = args.code.trim().replace(/^```(?:typescript|ts|javascript|js)?\\r?\\n/i, "").replace(/\\r?\\n```$/i, "");',
    replace: 'if (args && typeof args.code === "string") args = { ...args, code: args.code.trim().replace(/^```(?:typescript|ts|javascript|js)?\\r?\\n/i, "").replace(/\\r?\\n```$/i, "") };'
  },
  {
    name: '剥离 run_code 生成代码首尾的 Markdown 标记',
    search: 'async execute(args, exec) {\n\t\t\tif (args.description !== void 0 && args.description.trim().length === 0)',
    replace: 'async execute(args, exec) {\n\t\t\tif (args && typeof args.code === "string") args = { ...args, code: args.code.trim().replace(/^```(?:typescript|ts|javascript|js)?\\r?\\n/i, "").replace(/\\r?\\n```$/i, "") };\n\t\t\tif (args.description !== void 0 && args.description.trim().length === 0)'
  },
  {
    name: '自动将 Gemini 直接发起的子工具调用升格为 run_code 包装程序',
    search: 'result: toolErrorResult(new ToolNotFoundError(name, `only \\`' + '${RUN_CODE_NAME}' + '\\` is callable directly — call \\`' + '${name}' + '\\` from inside a \\`' + '${RUN_CODE_NAME}' + '\\` program instead`))',
    replace: 'const autoCode = `return await tools[${JSON.stringify(name)}](${JSON.stringify(detached)});`; return this.createExecution({ ...exec, name: RUN_CODE_NAME, arguments: { code: autoCode, description: `Auto-wrapped ${name}` } });'
  }
]);

const loopFile = path.join(nodeModules, 'dsh-agent-loop', 'lib', 'index.js');
safePatch(loopFile, [
  {
    name: '强化 parseArguments 双重 JSON 解包与参数键名对齐',
    search: 'function parseArguments(raw) {\n\ttry {\n\t\treturn raw ? JSON.parse(raw) : {};\n\t} catch {\n\t\treturn raw;\n\t}\n}',
    replace: 'function parseArguments(raw) {\n\tif (!raw) return {};\n\tlet val = raw;\n\tif (typeof val === "string") {\n\t\tval = val.trim().replace(/^```(?:json)?\\s*/i, "").replace(/\\s*```$/, "");\n\t\ttry { val = JSON.parse(val); } catch { return { code: val }; }\n\t}\n\tif (typeof val === "string" && (val.trim().startsWith("{") || val.trim().startsWith("["))) {\n\t\ttry { val = JSON.parse(val); } catch {}\n\t}\n\tif (typeof val === "object" && val !== null) {\n\t\tif (!val.code && (val.program || val.script || val.command)) val.code = val.program || val.script || val.command;\n\t} else if (typeof val === "string") {\n\t\tval = { code: val };\n\t}\n\treturn val;\n}'
  }
]);

const dshBinFile = path.join(nodeModules, 'dsh', 'lib', 'bin.js');
safePatch(dshBinFile, [
  {
    name: 'Linux Node.js 下 dsh 自执行判断修复',
    search: 'if (import.meta.main) await runCli();',
    replace: 'await runCli();'
  }
]);

console.log('[✓] Gemini 加固补丁应用完成！');