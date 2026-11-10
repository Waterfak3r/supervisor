// Supervisor 状态栏：Herdr 打开时，如果 supervisor 没在运行就自动启动它；
// 平时显示 supervisor 和它派出的 worker 的状态，点击可跳转。
// 源文件在 D:\Programming\Project\supervisor\herdr-mod，这里是安装后的副本。

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { terminals, theme, run, exec, shared, setShared, notify, playSound } from "herdr";

const ROOT = "D:\\Programming\\Project\\supervisor";
const SCRIPT = ROOT + "\\start-supervisor.ps1";

function live(t) {
  return t && t.state === "live";
}

function color(t, status) {
  return { working: t.working, blocked: t.blocked, done: t.done, idle: t.idle, error: t.blocked }[status] ?? t.dim;
}

const WORD = { working: "工作中", blocked: "等你处理", done: "完成", idle: "空闲", error: "出错" };

export default class Supervisor extends View {
  init(_props, cx) {
    this.note = "";
    // 只在 Herdr 打开时自动检查一次；之后如果你手动退出了 supervisor，就不会擅自重启，点"启动"即可。
    cx.timer.after(2500, (cx) => {
      if (!this.running()) this.start(cx);
    });
  }

  supervisor() {
    return terminals().find((t) => t.name === "supervisor" && live(t));
  }

  // 终端活着，而且里面的 claude 在报告状态。电脑重启后终端会被恢复成一个空 shell，那种情况不算在运行。
  running() {
    const s = this.supervisor();
    return Boolean(s && s.status);
  }

  start(cx) {
    // 多个副本（或保存后重载）同时触发时，只让一个去启动
    const last = shared("supervisor.starting") ?? 0;
    if (Date.now() - last < 30000) return;
    setShared("supervisor.starting", Date.now());
    this.note = "启动中…";
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const r = await exec("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SCRIPT, "-NoAttach"], { cwd: ROOT });
        this.note = r.code === 0 ? "" : `启动失败（${r.code}）：${(r.stderr || r.stdout).trim().slice(-120)}`;
      } catch (e) {
        this.note = `启动失败：${e}`;
      }
      setShared("supervisor.starting", 0);
      cx.notify();
    });
  }

  item(id, t, dot, label, terminal) {
    return h_flex()
      .id(id)
      .gap(6)
      .items_center()
      .px(6)
      .rounded(4)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("agent.focus", { terminal }))
      .child(div().size(7).rounded(4).bg(dot))
      .child(label);
  }

  render(cx) {
    const t = theme();
    const sup = this.running() ? this.supervisor() : null;
    const workers = sup ? terminals().filter((w) => live(w) && w.parent === sup.address) : [];
    const bar = h_flex().size_full().px(12).gap(10).items_center().bg(t.chrome).border_t(1).border_color(t.border).text_size(11.8).text_color(t.muted);

    if (!sup) {
      return bar
        .child(div().size(7).rounded(4).bg(t.dim))
        .child(div().child(this.note || "Supervisor 未运行"))
        .child(
          div().id("sv-start").px(8).rounded(4).bg(t.solid).text_color(t.solid_foreground).cursor_pointer()
            .on_click((_e, cx) => this.start(cx))
            .child("启动"),
        );
    }

    const s = sup.status ?? "idle";
    bar.child(this.item("sv-main", t, color(t, s), `Supervisor · ${WORD[s] ?? s}`, sup.address));

    // supervisor 有问题要问用户时，会给自己挂上 sv.ask 标签（问题写在它的回复正文里，它本身保持空闲、随时接新任务）。
    // 这里醒目地显示出来；第一次出现或内容变化时，响提示音并弹通知。
    const ask = sup.labels?.["sv.ask"];
    if (ask) {
      if (shared("supervisor.ask.notified") !== ask) {
        setShared("supervisor.ask.notified", ask);
        playSound("blocked");
        notify({ title: "Supervisor 有事待你决定", body: ask, level: "warning", action: { name: "agent.focus", args: { terminal: sup.address } } });
      }
      bar.child(
        h_flex().id("sv-ask").gap(6).items_center().px(8).rounded(4).bg(t.blocked).text_color(t.solid_foreground).cursor_pointer()
          .on_click(() => run("agent.focus", { terminal: sup.address }))
          .child(`待你决定：${ask}`),
      );
    }
    if (workers.length === 0) {
      bar.child(div().text_color(t.dim).child("没有运行中的 worker"));
    } else {
      // 等你处理的排在最前面
      const order = { blocked: 0, error: 1, working: 2, done: 3, idle: 4 };
      workers
        .slice()
        .sort((a, b) => (order[a.status] ?? 9) - (order[b.status] ?? 9))
        .forEach((w) => {
          const ws = w.status ?? "idle";
          bar.child(this.item(`sv-${w.address}`, t, color(t, ws), `${w.name ?? w.address} · ${WORD[ws] ?? ws}`, w.address));
        });
    }
    if (this.note) bar.child(div().text_color(t.blocked).child(this.note));
    return bar;
  }
}
