// 有事等你时让 Herdr 的任务栏按钮像微信一样常亮（不闪，切回 Herdr 后消失）。
// "有事等你"指：
//   - 任何 agent 处于 blocked（等你批准/回答）
//   - 顶层 agent 在你没看着时干完了（done）；supervisor 自己和它派出的 worker 除外——
//     supervisor 的 done 只代表一轮结束，worker 的 done 由 supervisor 处理
//   - supervisor 挂了 sv.ask 标签（待你决定）
// 只有出现新的待办时才高亮；待办全部消失（比如你在别的客户端处理了）就取消高亮。
// 开关：settings.json 里的 "taskbar_highlight"（缺省为开），状态栏右侧的"任务栏提醒"开关改的就是它。

import { agents, terminals, exec, home, appHome, shared, setShared, readTextFile, writeTextFile } from "herdr";

const DIR = appHome().replace(/\//g, "\\") + "\\mods\\supervisor";
const EXE = home().replace(/\//g, "\\") + "\\AppData\\Local\\herdr-taskbar-flash\\taskbar-flash.exe";
const CSC = "C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe";
const KEY = "supervisor.taskbarFlash";
const ON_KEY = "supervisor.taskbarHighlight";
const SETTINGS = appHome() + "/settings.json";

// 开关的当前值（各 mod 副本共用）。还没读到 settings.json 时按开处理。
export function highlightOn() {
  return shared(ON_KEY) !== false;
}

// 从 settings.json 读开关（启动时和定时调用，这样手改 settings.json 也会生效）。
export async function loadHighlightSetting() {
  let on = true;
  try {
    on = JSON.parse((await readTextFile(SETTINGS)) ?? "{}").taskbar_highlight !== false;
  } catch {}
  if (on !== highlightOn()) applyHighlight(on);
}

// 切换开关：和 Herdr 的设置页一样读-改-写 settings.json（期间被别人改过就重读重来）。
export async function setHighlight(on) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const raw = await readTextFile(SETTINGS);
    let person = {};
    try {
      person = raw ? JSON.parse(raw) : {};
    } catch {}
    person.taskbar_highlight = on;
    try {
      await writeTextFile(SETTINGS, JSON.stringify(person, null, 2) + "\n", raw);
      break;
    } catch {}
  }
  applyHighlight(on);
}

function applyHighlight(on) {
  setShared(ON_KEY, on);
  // 关：立即取消高亮；开：清空记录，让现有待办被当成新的重新判断
  setShared(KEY, "");
  if (!on) runFlash(["--stop"]).catch((e) => console.log(`taskbar flash: ${e}`));
}

export function pendingKeys(sup) {
  const parentOf = {};
  for (const t of terminals()) parentOf[t.address] = t.parent;
  const keys = [];
  for (const a of agents()) {
    if (a.status === "blocked") keys.push(`blocked:${a.address}`);
    else if (a.status === "done" && a.address !== sup?.address && !parentOf[a.address]) keys.push(`done:${a.address}`);
  }
  const ask = sup?.labels?.["sv.ask"];
  if (ask) keys.push(`ask:${ask}`);
  return keys.sort();
}

async function runFlash(args) {
  try {
    return await exec(EXE, args, { timeout: 10000 });
  } catch (_e) {
    // exe 不存在：用系统自带的 .NET Framework 编译器现编一个
    await exec("powershell", ["-NoProfile", "-Command", `New-Item -ItemType Directory -Force '${EXE.replace(/\\[^\\]+$/, "")}' | Out-Null`]);
    const c = await exec(CSC, ["/nologo", "/target:winexe", `/out:${EXE}`, `${DIR}\\taskbar-flash.cs`], { timeout: 60000 });
    if (c.code !== 0) throw new Error(`编译 taskbar-flash 失败：${(c.stdout + c.stderr).trim().slice(-200)}`);
    return await exec(EXE, args, { timeout: 10000 });
  }
}

// 在 render 里调用。多个 mod 副本同时渲染时，靠 shared 状态只让第一个动手。
export function checkAttention(sup, cx) {
  if (!highlightOn()) return;
  const keys = pendingKeys(sup);
  const now = keys.join("\n");
  const before = shared(KEY) ?? "";
  if (now === before) return;
  setShared(KEY, now);
  const old = new Set(before ? before.split("\n") : []);
  const fresh = keys.some((k) => !old.has(k));
  if (!fresh && keys.length > 0) return; // 只是少了几项，还有别的待办：保持现状
  cx.spawn(async () => {
    try {
      await runFlash(fresh ? [] : ["--stop"]);
    } catch (e) {
      console.log(`taskbar flash: ${e}`);
    }
  });
}
