# birthday（女友生日庆生网站）

纯静态站点：`site/`（index.html + css/js）、`tools/`（Python 脚本）、`deploy/`、`content/`、`photos/`（原图，35 张，隐私，不入库）。线上 yyxcxc.wonderfaker.online，11-11 00:00（+08:00）解锁。

## 验收三件套（每个里程碑都跑，coder 和 supervisor 各跑一遍）
- `python tools\check_site.py site --strict`（上线前必须 exit 0；非 strict 只对占位口令、占位文案打 WARN）
- `node --check site\js\main.js`（data.js 同理）
- `python -I tools\sync_content.py --check`，应输出 `in sync`
（T013、T016、T021、T023、T025、T026；核实 2026-11-10，三个脚本都在、`--help` 正常）

## 数据流与约定
- `site/js/data.js` 分块生成：PASSCODE 区块归 `tools\set_passcode.py`，CONTENT 区块归 `tools\sync_content.py`（来自 `content/poem.txt`、`love_letter.txt`），PHOTOS 区块归 `tools\process_photos.py`（来自 `content/captions.csv`）。区块之外的字段（unlockAt、gate、countdown、music、milestones、specialDays、intro、letter）手改，生成脚本必须原样保留（T013、T016；核实 2026-11-10，BEGIN 标记都在）
- **同一时间只能有一个 worker 写 data.js**。process_photos 要等没有 coder 在改 data.js 时才跑（PROGRESS 2026-11-09）
- `captions.csv` 是 UTF-8 BOM，列为 `source_file,order,date,title,text,group,cover`；Excel 另存成 GBK 也能读（按 GB18030）。核实 2026-11-10
- `pNN` 是按 order 排出来的序号，用户一改日期就全变。需要稳定指向某张照片，用 `source_file`：封面拼贴用 `cover` 列（1..7），合并卡片用 `group` 列，且同组必须相邻（T023 提出风险，T025 解决；核实 2026-11-10）
- 空标题、空文案是合法的，页面不渲染对应元素；写了【待补充】仍会让 `--strict` 失败（T025）
- `content/poem.txt`、`love_letter.txt`、`user_edits_1110.txt` 是用户原文，一字不改；check_site 会逐字比对 CONTENT 区块（T016）
- 口令明文不进库、不进记忆、不进报告：只存加盐 SHA-256，改口令用 `python tools\set_passcode.py - "<提示语>"`（交互输入不回显）。核实 2026-11-10

## 踩过的坑
- 照片 ICC 描述写着「Display P3 Gamut with sRGB Transfer」，不能因为含 `srgb` 就当 sRGB。已改成 `is_plain_srgb()`：描述不含 p3 / display / adobe 等字样，再加 12 个色块探针双重判断。这是 gemini 交叉审查（T018）发现、sonnet coder 没发现的（T018；核实 2026-11-10，函数在 process_photos.py）
- 去 EXIF 解决不了截图里像素级的隐私（昵称、头像、备注名、日期）。上线前要用户过目截图类照片（T019；用户已知情并决定保留）
- 封面照片 `loading="eager"` 要加 `data-eager`，否则 check_site 失败（T023）
- 微信内置浏览器、真机、桌面宽屏从未测过，每个里程碑的报告里都写着「没测」。上线前最好让用户真机看一次（T013、T021、T023、T025、T026）
- 没有 EXIF 拍摄时间的照片只能用文件名时间戳或文件修改时间，微信 `mmexport…` 的时间是导出时间，不一定是拍摄时间，日期必须让用户核对（T016；用户已逐条校对）

## 部署（tc-62）
- `deploy\deploy.ps1` 默认 dry-run，`-Execute` 才真正执行，`-Rollback -Execute` 回滚。第 0 步先跑 `check_site --strict`，失败就不碰网络。`deploy\remote.sh` 备份 Caddyfile，追加站点块，`caddy validate` 失败就恢复备份且不 reload，成功后 `mv -Tf` 原子切换 `current` 软链（T013；核实 2026-11-10）
- 部署需用户批准。2026-11-10 12:26 的首次上线里，auto 模式拦住了 supervisor 执行 `-Execute`，由用户在会话里亲自执行（release 20261110122641）。以后重发同样预期让用户执行
- 用户想要「足迹地图」（照片带 GPS）但说麻烦就算了，本期不做，process_photos 照常去掉 GPS（PROGRESS 2026-11-09）
