// Agent board：把所有 agent 按状态排成四列卡片（等你处理 / 工作中 / 完成 / 空闲）。
// 点卡片 → agent.focus，下方的 { "agent": "focused" } 块就会实时显示它的终端。
// props.part === "live" 时只画 Live workspace 那一条标题栏。
// 源文件在 D:\Programming\Project\supervisor\herdr-mod\agent-board，这里是安装后的副本。

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, terminals, focused, run, theme, props } from "herdr";

const COLUMNS = [
  { key: "needs", label: "等你处理", color: "blocked" },
  { key: "working", label: "工作中", color: "working" },
  { key: "done", label: "完成", color: "done" },
  { key: "idle", label: "空闲", color: "idle" },
];

function column(status) {
  if (status === "blocked" || status === "error") return "needs";
  if (status === "working") return "working";
  if (status === "done") return "done";
  return "idle";
}

function ago(ms) {
  const m = Math.floor((Date.now() - ms) / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

function icon(p, size, color) {
  if (!p?.icon) return div().size(size).flex_none();
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

export default class AgentBoard extends View {
  init(_props, cx) {
    // address -> { status, since }：Herdr 不提供"进入当前状态的时间"，这里自己记
    this.since = new Map();
    this.scope = "all";
    try { this.scope = localStorage.getItem("scope") || "all"; } catch {}
    // 只为刷新"多久之前"的文字；状态变化本身会自动触发重绘
    cx.timer.every(30000, (cx) => cx.notify());
  }

  // 合并 agents()（空间、标签页、程序图标）和 terminals()（终端名、template、父终端）
  cards() {
    const byAddr = new Map(terminals().map((t) => [t.address, t]));
    const list = agents().map((a) => {
      const term = byAddr.get(a.address) ?? {};
      // 标签页名是编号，或者只是程序名（如 "Claude Code"），就没有信息量，改用终端标题（对话主题）
      const tabName = a.tab_name ?? "";
      const tab = /^\d+$/.test(tabName) || tabName === a.program?.name ? "" : tabName;
      const parent = term.parent ? byAddr.get(term.parent) : null;
      return {
        address: a.address,
        status: term.status === "error" ? "error" : a.status,
        program: a.program,
        title: term.name || tab || a.title || a.program?.name || a.address,
        space: a.space_name,
        // dispatch.ps1 派出的 worker 带 sv.role / sv.model / sv.effort 标签；一次性 template 名带随机后缀，不好读
        template: term.labels?.["sv.role"]
          ? [term.labels["sv.role"], [term.labels["sv.model"], term.labels["sv.effort"]].filter(Boolean).join("/")].filter(Boolean).join(" · ")
          : term.template,
        parent: parent?.name || term.parent || null,
      };
    });
    const now = Date.now();
    for (const c of list) {
      const prev = this.since.get(c.address);
      if (!prev || prev.status !== c.status) this.since.set(c.address, { status: c.status, since: now });
      c.since = this.since.get(c.address).since;
    }
    return list;
  }

  setScope(scope, cx) {
    this.scope = scope;
    try { localStorage.setItem("scope", scope); } catch {}
    cx.notify();
  }

  chip(id, label, on, t, onClick) {
    return div()
      .id(id)
      .px(10)
      .py(4)
      .rounded(6)
      .border(1)
      .border_color(on ? t.accent : t.border)
      .text_color(on ? t.foreground : t.muted)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(onClick)
      .child(label);
  }

  card(c, t, selected) {
    const col = COLUMNS.find((k) => k.key === column(c.status));
    const strip = t[col.color] ?? t.dim;
    const sub = [c.space, c.template, c.parent ? `由 ${c.parent} 派出` : null].filter(Boolean).join(" · ");
    return h_flex()
      .id(`card-${c.address}`)
      .w_full()
      .rounded(8)
      .overflow_hidden()
      .bg(t.background)
      .border(1)
      .border_color(selected ? t.accent : t.border)
      .cursor_pointer()
      .hover((s) => s.border_color(t.input))
      .on_click(() => run("agent.focus", { terminal: c.address }))
      .child(div().w(3).h_full().flex_none().bg(strip))
      .child(
        v_flex()
          .flex_1()
          .min_w(0)
          .px(12)
          .py(10)
          .gap(6)
          .child(
            h_flex().gap(6).items_center().text_size(11.5).text_color(t.muted)
              .child(icon(c.program, 13, t.foreground))
              .child(div().flex_1().truncate().child(c.program?.name ?? ""))
              .child(div().text_color(t.dim).child(c.address)),
          )
          .child(div().truncate().text_size(14).font_medium().text_color(t.foreground).child(c.title))
          .child(
            h_flex().gap(8).items_center().text_size(11.5).text_color(t.dim)
              .child(div().flex_1().truncate().child(sub))
              .child(div().flex_none().child(ago(c.since))),
          ),
      );
  }

  renderLive(t) {
    const f = focused();
    const a = f?.agent ? agents().find((x) => x.address === f.agent) : null;
    const term = a ? terminals().find((x) => x.address === a.address) : null;
    const where = a ? [a.space_name, term?.name || a.tab_name].filter(Boolean).join(" / ") : "点上面的卡片，在这里实时查看并操作它的终端";
    return h_flex()
      .size_full()
      .px(16)
      .gap(10)
      .items_center()
      .bg(t.chrome)
      .border_t(1)
      .border_b(1)
      .border_color(t.border)
      .text_size(12)
      .child(div().size(7).rounded(4).bg(a ? t[column(a.status) === "needs" ? "blocked" : a.status] ?? t.dim : t.dim))
      .child(div().font_medium().text_color(t.foreground).child("Live workspace"))
      .child(div().flex_1().truncate().text_color(t.muted).child(where))
      .when(Boolean(a), (el) =>
        el.child(
          div().id("open-tab").px(8).py(2).rounded(5).text_color(t.muted).cursor_pointer()
            .hover((s) => s.bg(t.hover).text_color(t.foreground))
            .on_click(() => {
              run("layout.switch", { name: "supervisor" });
              run("pane.focus", { terminal: a.address });
            })
            .child("在标签页中打开 ↗"),
        ),
      );
  }

  render(cx) {
    const t = theme();
    if (props()?.part === "live") return this.renderLive(t);

    const all = this.cards();
    const shown = this.scope === "supervisor" ? all.filter((c) => c.space === "Supervisor") : all;
    const spaceCount = new Set(all.map((c) => c.space)).size;
    const selected = focused()?.agent;

    const header = v_flex()
      .px(20)
      .pt(14)
      .pb(12)
      .gap(10)
      .border_b(1)
      .border_color(t.border)
      .child(
        h_flex().gap(10).items_center()
          .child(h_flex().gap(3).items_center()
            .child(div().w(4).h(16).rounded(2).bg(t.accent))
            .child(div().w(4).h(12).rounded(2).bg(t.accent))
            .child(div().w(4).h(16).rounded(2).bg(t.accent)))
          .child(div().text_size(16).font_semibold().text_color(t.foreground).child("Agent board"))
          .child(div().flex_1())
          .child(div().text_size(12).text_color(t.muted).child(`${all.length} 个 agent · ${spaceCount} 个空间`)),
      )
      .child(
        h_flex().gap(8).items_center().text_size(12)
          .child(this.chip("scope-all", "全部空间", this.scope === "all", t, (_e, cx) => this.setScope("all", cx)))
          .child(this.chip("scope-sv", "只看 Supervisor", this.scope === "supervisor", t, (_e, cx) => this.setScope("supervisor", cx)))
          .child(div().flex_1())
          .child(this.chip("to-work", "切换到工作区布局", false, t, () => run("layout.switch", { name: "supervisor" }))),
      );

    const cols = h_flex()
      .flex_1()
      .min_h(0)
      .px(16)
      .py(14)
      .gap(14)
      .children(
        COLUMNS.map((k) => {
          const items = shown.filter((c) => column(c.status) === k.key).sort((a, b) => a.since - b.since);
          return v_flex()
            .flex_1()
            .min_w(0)
            .h_full()
            .gap(10)
            .child(
              h_flex().gap(8).items_center().px(4).text_size(13)
                .child(div().size(8).rounded(4).bg(t[k.color] ?? t.dim))
                .child(div().font_medium().text_color(t.foreground).child(k.label))
                .child(div().px(6).rounded(4).bg(t.raised).text_size(11).text_color(t.muted).child(String(items.length))),
            )
            .child(
              v_flex()
                .id(`col-${k.key}`)
                .flex_1()
                .min_h(0)
                .gap(8)
                .overflow_y_scrollbar()
                .when(items.length === 0, (el) => el.child(div().px(4).text_size(12).text_color(t.dim).child("无")))
                .children(items.map((c) => this.card(c, t, c.address === selected))),
            );
        }),
      );

    return v_flex().size_full().bg(t.canvas).child(header).child(cols);
  }
}
