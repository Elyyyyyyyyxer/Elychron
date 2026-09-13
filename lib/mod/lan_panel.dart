/// 局域网面板的网页（内嵌在 App 里，电脑浏览器打开的界面）。
///
/// 刻意做成**自包含单文件**：不引用任何 CDN、不依赖网络，因为校园网/内网
/// 未必能访问外网；所有样式与脚本都在这一个字符串里。
const String lanPanelHtml = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Elychron · 局域网同步</title>
<style>
  /* ============================================================
     视觉基准完全对齐手机端：
       · 强调色 #FF699A（手机 CupertinoThemeData.primaryColor）
       · 分组背景 #F2F2F7 / #1C1C1E（手机 systemGroupedBackground）
       · 卡片 #FFFFFF / #2C2C2E（手机 secondarySystemGroupedBackground）
       · SF Pro 字体栈、iOS 分隔线、行高与圆角沿用 iOS 观感
     ============================================================ */
  :root {
    --bg: #f2f2f7;
    --bg-elevated: #ffffff;
    --card: #ffffff;
    --card-2: #f7f7fa;
    --line: rgba(60,60,67,.14);
    --line-strong: rgba(60,60,67,.24);
    --text: #000000;
    --text-2: #6b6b73;
    --text-3: #6f6f78;
    --accent: #ff699a;
    --accent-strong: #ff4d86;
    /* 文字专用的深一档颜色：系统橙 / 系统红 / 强调粉直接当正文用对比度不够
       （#ff9500 在白底只有 2.2:1），这几个值都在 5:1 上下。 */
    --accent-text: #b8285c;
    --warn-text: #a85c00;
    --danger-text: #c92f26;
    --accent-soft: rgba(255,105,154,.12);
    --accent-line: rgba(255,105,154,.3);
    --fill: rgba(118,118,128,.10);
    --fill-2: rgba(118,118,128,.16);
    --blue: #007aff;
    --danger: #ff3b30;
    --ok: #34c759;
    --warn: #ff9500;
    --shadow-card: 0 1px 2px rgba(0,0,0,.04), 0 8px 24px rgba(0,0,0,.05);
    --shadow-pop: 0 12px 40px rgba(0,0,0,.16);
    --header-bg: rgba(242,242,247,.78);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #1c1c1e;
      --bg-elevated: #2c2c2e;
      --card: #2c2c2e;
      --card-2: #242426;
      --line: rgba(84,84,88,.42);
      --line-strong: rgba(120,120,128,.6);
      --text: #ffffff;
      --text-2: rgba(235,235,245,.68);
      --text-3: rgba(235,235,245,.58);
      --accent: #ff7da8;
      --accent-strong: #ff699a;
      --accent-text: #ff9dbe;
      --warn-text: #ffb340;
      --danger-text: #ff7b72;
      --accent-soft: rgba(255,125,168,.16);
      --accent-line: rgba(255,125,168,.34);
      --fill: rgba(118,118,128,.22);
      --fill-2: rgba(118,118,128,.32);
      --shadow-card: 0 1px 2px rgba(0,0,0,.3);
      --shadow-pop: 0 16px 48px rgba(0,0,0,.55);
      --header-bg: rgba(28,28,30,.78);
    }
  }

  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0; min-height: 100vh;
    background: var(--bg); color: var(--text);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC",
      "Hiragino Sans GB", "Microsoft YaHei", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }

  /* ---------------------------------------------------------- 顶栏 */
  header {
    position: sticky; top: 0; z-index: 20;
    display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
    padding: 12px max(20px, calc((100vw - 1080px) / 2));
    background: var(--header-bg);
    backdrop-filter: saturate(180%) blur(24px);
    -webkit-backdrop-filter: saturate(180%) blur(24px);
    border-bottom: 1px solid var(--line);
  }
  .brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
  .brand-mark {
    width: 32px; height: 32px; flex: none; border-radius: 10px;
    display: grid; place-items: center;
    background: linear-gradient(160deg, #ff8fb4, var(--accent));
    box-shadow: 0 4px 12px rgba(255,105,154,.3);
    color: #fff; font-size: 16px; font-weight: 700;
  }
  header h1 { font-size: 17px; margin: 0; font-weight: 650; letter-spacing: -.02em; }
  .subtitle { font-size: 11px; color: var(--text-3); margin-top: -1px; }

  .pill {
    font-size: 11px; font-weight: 500; padding: 3px 9px; border-radius: 999px;
    background: var(--fill); color: var(--text-2); white-space: nowrap;
    transition: background .2s ease, color .2s ease;
  }
  .pill.ok { background: rgba(52,199,89,.14); color: #1a7a3a; }
  .pill.err { background: rgba(255,59,48,.14); color: #b3261e; }
  @media (prefers-color-scheme: dark) {
    .pill.ok { color: #4cd964; }
    .pill.err { color: #ff7b72; }
  }

  .spacer { flex: 1 1 auto; }
  .header-search { max-width: 200px; }

  /* ---------------------------------------------------------- 主体 */
  main {
    max-width: 1080px; margin: 0 auto; padding: 20px;
    display: grid; gap: 18px;
    grid-template-columns: minmax(0, 340px) minmax(0, 1fr);
    align-items: start;
  }
  main > .col { display: flex; flex-direction: column; gap: 18px; min-width: 0; }
  @media (max-width: 900px) {
    main { grid-template-columns: 1fr; padding: 16px; gap: 14px; }
    header { padding: 10px 16px; }
  }
  /* 窄屏把顶栏压成两行：品牌 + 状态，然后搜索框撑满其余空间 */
  @media (max-width: 620px) {
    header { gap: 8px; }
    .spacer { display: none; }
    .header-search { flex: 1 1 130px; max-width: none; }
    .tabs { gap: 14px; }
  }

  /* ---------------------------------------------------------- 卡片 */
  .card {
    background: var(--card); border-radius: 16px; padding: 18px;
    box-shadow: var(--shadow-card);
    border: 1px solid transparent;
  }
  @media (prefers-color-scheme: dark) { .card { border-color: var(--line); } }
  .card h2 {
    font-size: 13px; margin: 0 0 14px; color: var(--text-2);
    font-weight: 600; letter-spacing: .04em;
  }
  .card-title-row { display: flex; align-items: baseline; gap: 8px; margin-bottom: 14px; }
  .card-title-row h2 { margin: 0; }
  .card-title-row .hint { margin-left: auto; }

  /* ---------------------------------------------------------- 表单 */
  label { color: var(--text-2); font-size: 13px; }
  input[type=text], input[type=date], input[type=number],
  input[type=datetime-local], select, textarea {
    font: inherit; width: 100%; color: var(--text);
    padding: 9px 12px; border-radius: 10px;
    border: 1px solid var(--line);
    background: var(--card-2);
    transition: border-color .18s ease, background .18s ease, box-shadow .18s ease;
    -webkit-appearance: none; appearance: none;
  }
  @media (prefers-color-scheme: dark) {
    input, select, textarea { background: var(--card-2); }
  }
  input:hover, select:hover, textarea:hover { border-color: var(--line-strong); }
  /* 日期 / 日期时间这类控件在 Chromium 里焦点落在影子节点上，只用 :focus 会漏掉，
     所以补一份 :focus-within。 */
  input:focus, input:focus-within,
  select:focus, select:focus-within,
  textarea:focus, textarea:focus-within {
    outline: none; border-color: var(--accent);
    box-shadow: 0 0 0 3.5px var(--accent-soft);
    background: var(--bg-elevated);
  }
  textarea { min-height: 72px; resize: vertical; line-height: 1.5; }
  select {
    background-image:
      linear-gradient(45deg, transparent 50%, var(--text-3) 50%),
      linear-gradient(135deg, var(--text-3) 50%, transparent 50%);
    background-position: calc(100% - 17px) 50%, calc(100% - 12px) 50%;
    background-size: 5px 5px, 5px 5px; background-repeat: no-repeat;
    padding-right: 32px;
  }
  .field { margin-top: 12px; }
  .field > label { display: block; margin-bottom: 6px; }
  input[type=file] { font-size: 13px; color: var(--text-2); width: 100%; }
  input[type=file]::file-selector-button {
    font: inherit; font-weight: 500; color: var(--text);
    background: var(--fill); border: none; border-radius: 9px;
    padding: 7px 12px; margin-right: 10px; cursor: pointer;
  }
  input[type=file]::file-selector-button:hover { background: var(--fill-2); }
  .grid { display: grid; gap: 8px; grid-template-columns: minmax(0,1fr) auto; align-items: center; }
  .grid .span-all { grid-column: 1 / -1; }
  @media (max-width: 520px) { .grid { grid-template-columns: 1fr; } }

  .switch-row {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 12px; border-radius: 11px; background: var(--card-2);
    border: 1px solid var(--line); cursor: pointer; user-select: none;
  }
  .switch-row:hover { border-color: var(--line-strong); }
  .switch-row input[type=checkbox] {
    width: 18px; height: 18px; flex: none; margin: 0;
    accent-color: var(--accent); cursor: pointer;
  }
  .switch-row span { font-size: 14px; color: var(--text); }

  /* ---------------------------------------------------------- 按钮 */
  button {
    font: inherit; font-weight: 500; cursor: pointer;
    color: var(--text); background: var(--fill);
    border: none; border-radius: 10px; padding: 7px 13px;
    transition: transform .14s ease, background .16s ease, opacity .16s ease;
    white-space: nowrap;
  }
  button:hover { background: var(--fill-2); }
  button:active { transform: scale(.97); }
  /* 键盘焦点环要用实色：--accent-soft 只有 12% 透明度，实际几乎看不见 */
  button:focus-visible,
  input:focus-visible, textarea:focus-visible, select:focus-visible {
    outline: 2px solid var(--accent); outline-offset: 2px;
  }
  button.primary {
    color: #fff; background: linear-gradient(180deg, #f4538a, #e0356f);
    box-shadow: 0 4px 14px rgba(224,53,111,.3);
  }
  button.primary:hover { background: linear-gradient(180deg, #ec437c, #d02a60); }
  button.danger { color: var(--danger-text); }
  button.danger:hover { background: rgba(255,59,48,.12); }
  button.ghost { background: transparent; color: var(--text-2); }
  button.ghost:hover { background: var(--fill); color: var(--text); }
  button:disabled { opacity: .45; cursor: default; transform: none; }
  .hint { font-size: 12.5px; color: var(--text-2); line-height: 1.5; }

  /* ---------------------------------------------------------- 分类（对齐手机端下划线式标签） */
  .workbar {
    display: flex; align-items: flex-start; justify-content: space-between;
    gap: 14px; flex-wrap: wrap; margin-bottom: 6px;
  }
  .tabs { display: flex; gap: 18px; flex-wrap: wrap; }
  .tab {
    position: relative; border: none; background: transparent;
    padding: 4px 0 9px; color: var(--text-2); font-size: 15px; font-weight: 400;
    border-radius: 0;
  }
  .tab:hover { background: transparent; color: var(--text); }
  .tab.active { color: var(--text); font-weight: 650; }
  .tab::after {
    content: ''; position: absolute; left: 50%; bottom: 2px;
    width: 0; height: 3px; border-radius: 2px; background: var(--accent);
    transform: translateX(-50%); transition: width .22s cubic-bezier(.2,.8,.2,1);
  }
  .tab.active::after { width: 22px; }
  .tab .pill { margin-left: 5px; vertical-align: 1px; }

  /* ---------------------------------------------------------- 任务行（iOS 列表） */
  .row {
    display: flex; align-items: flex-start; gap: 12px;
    padding: 12px 4px; border-top: 1px solid var(--line);
    cursor: pointer; border-radius: 12px;
    transition: background .18s ease, transform .18s ease;
  }
  .row:first-of-type { border-top: none; }
  .row:hover { background: var(--accent-soft); transform: translateX(2px); }
  .row input[type=checkbox] {
    width: 21px; height: 21px; flex: none; margin: 1px 0 0;
    accent-color: var(--accent); cursor: pointer;
  }
  .row .body { flex: 1; min-width: 0; }
  .row .title { font-size: 15px; font-weight: 500; word-break: break-word; letter-spacing: -.01em; }
  .row .title.done { color: var(--text-2); text-decoration: line-through; }
  .meta {
    display: flex; flex-wrap: wrap; gap: 4px 9px; margin-top: 5px;
    font-size: 12.5px; color: var(--text-2);
  }
  .meta .due-soon { color: var(--warn-text); font-weight: 500; }
  .meta .overdue { color: var(--danger-text); font-weight: 600; }
  .tag {
    font-size: 11px; padding: 1px 8px; border-radius: 999px;
    background: var(--accent-soft); color: var(--accent-text);
  }
  .prio-high { color: var(--warn-text); }
  .prio-urgent { color: var(--danger-text); }
  .empty-state { text-align: center; padding: 34px 16px; color: var(--text-2); }
  .empty-state .emoji { font-size: 30px; display: block; margin-bottom: 8px; }

  /* ---------------------------------------------------------- 弹层 */
  .overlay {
    position: fixed; inset: 0; z-index: 40;
    display: flex; align-items: center; justify-content: center;
    padding: 20px; background: rgba(0,0,0,.28);
    backdrop-filter: blur(6px); -webkit-backdrop-filter: blur(6px);
    animation: fadeIn .2s ease;
  }
  @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
  .sheet {
    width: min(560px, 100%); max-height: calc(100vh - 40px); overflow: auto;
    background: var(--bg-elevated); border-radius: 18px; padding: 22px;
    box-shadow: var(--shadow-pop);
    animation: sheetIn .28s cubic-bezier(.2,.85,.25,1);
  }
  @keyframes sheetIn {
    from { opacity: 0; transform: translateY(14px) scale(.97); }
    to { opacity: 1; transform: none; }
  }
  .sheet h2 { margin: 0 0 4px; font-size: 20px; font-weight: 700; letter-spacing: -.02em; }
  .sheet .sheet-sub { font-size: 13px; color: var(--text-2); margin: 0 0 18px; }
  /* 表单很长时「保存」不能藏在滚动底部：动作条钉在弹层底部 */
  .sheet .actions {
    position: sticky; bottom: -22px; z-index: 1;
    display: flex; justify-content: flex-end; gap: 8px;
    margin: 20px -22px -22px; padding: 14px 22px 18px;
    background: var(--bg-elevated);
    border-top: 1px solid var(--line);
    border-radius: 0 0 18px 18px;
  }

  /* ---------------------------------------------------------- 配对 */
  #pair { background: var(--bg); }
  #pair .sheet { width: min(360px, 100%); text-align: center; padding: 28px 24px; }
  #pair h2 { font-size: 19px; margin-bottom: 6px; }
  #pair p { font-size: 13px; color: var(--text-2); margin: 0 0 18px; line-height: 1.5; }
  #pair input {
    text-align: center; font-size: 24px; font-weight: 600;
    letter-spacing: .38em; text-indent: .38em; padding: 12px;
    font-variant-numeric: tabular-nums;
  }
  #pair button.primary { width: 100%; padding: 11px; font-size: 16px; margin-top: 4px; }

  /* ---------------------------------------------------------- 子待办（只读列表） */
  .sub-list { margin-top: 9px; display: flex; flex-direction: column; gap: 5px; }
  .sub-item {
    display: flex; align-items: flex-start; gap: 8px; flex-wrap: wrap;
    padding: 6px 10px; border-radius: 9px; background: var(--card-2);
    font-size: 13px;
  }
  .sub-item input[type=checkbox] {
    width: 16px; height: 16px; flex: none; margin: 1px 0 0; accent-color: var(--accent);
  }
  /* 标题留一个最小宽度：否则窄屏上会被时间和提醒挤成一行一个字 */
  .sub-item .sub-title { flex: 1 1 7em; min-width: 7em; word-break: break-word; }
  .sub-item .sub-time, .sub-item .sub-hint, .sub-item .sub-state {
    flex: none; color: var(--text-2); font-size: 12px;
    font-variant-numeric: tabular-nums;
  }
  .sub-item.done .sub-title { color: var(--text-2); text-decoration: line-through; }
  .sub-item.ongoing { background: rgba(0,122,255,.1); }
  .sub-item.ongoing .sub-title, .sub-item.ongoing .sub-time { color: var(--blue); font-weight: 600; }
  .sub-item.ongoing .sub-state { color: var(--blue); font-weight: 600; }
  .sub-item.missed .sub-title, .sub-item.missed .sub-time, .sub-item.missed .sub-state { color: var(--danger-text); }

  /* ---------------------------------------------------------- 编辑器内的子待办行 */
  #editSubtasks { display: flex; flex-direction: column; gap: 9px; }
  #editSubtasks .sub-row {
    border: 1px solid var(--line); border-radius: 12px; padding: 11px;
    background: var(--card-2);
  }
  #editSubtasks .sub-row-head { display: flex; align-items: center; gap: 9px; }
  #editSubtasks .sub-row-head input[type=checkbox] {
    width: 18px; height: 18px; flex: none; margin: 0; accent-color: var(--accent);
  }
  #editSubtasks .sub-row-head input[type=text] { flex: 1; min-width: 0; }
  #editSubtasks .sub-row-times {
    display: grid; gap: 8px; margin-top: 9px;
    grid-template-columns: repeat(2, minmax(0,1fr)) 118px;
  }
  #editSubtasks .sub-row-times label { display: block; font-size: 12px; margin-bottom: 4px; }
  #editSubtasks .sub-row-hint { margin-top: 7px; font-size: 12px; color: var(--text-2); }
  #editSubtasks .empty { font-size: 13px; color: var(--text-2); padding: 2px 0 4px; }
  @media (max-width: 560px) { #editSubtasks .sub-row-times { grid-template-columns: 1fr; } }

  /* ---------------------------------------------------------- 通知（整屏右下角） */
  #toast {
    position: fixed; right: 24px; bottom: 24px; z-index: 60;
    width: min(370px, calc(100vw - 32px));
    /* 从上往下排：最新的那条离屏幕右下角最近，视线不用往上找 */
    display: flex; flex-direction: column; gap: 9px;
    pointer-events: none;
  }
  .toast-item {
    pointer-events: auto; color: #fff; font-size: 14px; line-height: 1.45;
    padding: 12px 15px; border-radius: 14px;
    background: rgba(28,28,30,.94);
    backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
    box-shadow: var(--shadow-pop);
    opacity: 0; transform: translate3d(20px, 12px, 0) scale(.97);
    animation: toastIn .34s cubic-bezier(.2,.85,.25,1) forwards;
  }
  .toast-item.ok { background: rgba(28,120,62,.96); }
  .toast-item.err { background: rgba(178,42,36,.96); }
  @keyframes toastIn { to { opacity: 1; transform: none; } }
  .toast-item.leaving { animation: toastOut .22s ease forwards; }
  @keyframes toastOut { to { opacity: 0; transform: translate3d(14px, 6px, 0) scale(.98); } }
  @media (max-width: 560px) { #toast { right: 12px; bottom: 12px; } }

  /* ---------------------------------------------------------- 无障碍 / 动效偏好 */
  .hidden { display: none !important; }
  .visually-hidden {
    position: absolute; width: 1px; height: 1px; overflow: hidden;
    clip: rect(0 0 0 0); white-space: nowrap;
  }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: .001ms !important; animation-iteration-count: 1 !important;
      transition-duration: .001ms !important;
    }
    .row:hover { transform: none; }
  }
</style>
</head>
<body>

<div id="pair" class="overlay">
  <div class="sheet">
    <h2>配对这台电脑</h2>
    <p>配对码显示在手机「局域网同步」页面上，输一次就会记住。</p>
    <input id="codeInput" type="text" inputmode="numeric" maxlength="6" placeholder="000000" autocomplete="off" aria-label="六位配对码">
    <div id="pairErr" class="hint" style="color:var(--danger-text); min-height:18px; margin-top:8px;"></div>
    <button class="primary" onclick="pair()">连接手机</button>
  </div>
</div>

<header>
  <div class="brand">
    <span class="brand-mark">E</span>
    <div>
      <h1>Elychron</h1>
      <div class="subtitle">局域网同步</div>
    </div>
  </div>
  <span id="status" class="pill">未连接</span>
  <span class="spacer"></span>
  <input id="searchInput" class="header-search" type="text" placeholder="搜索待办…" aria-label="搜索待办" oninput="render()">
  <button class="ghost" onclick="refresh()">刷新</button>
  <button class="ghost" onclick="downloadBundle()">导出备份</button>
</header>

<main>
  <div class="col">
    <section class="card">
      <div class="card-title-row"><h2>新建待办</h2></div>
      <div class="grid">
        <input id="newTitle" class="span-all" type="text" placeholder="要做的事…" aria-label="标题">
        <input id="newEnd" type="date" aria-label="截止日期">
        <button class="primary" onclick="addTask()">添加</button>
      </div>
      <div class="field">
        <label for="newDescription">描述</label>
        <textarea id="newDescription" placeholder="补充说明（可选）"></textarea>
      </div>
      <div class="field">
        <label class="switch-row" for="newReminderEnabled">
          <input id="newReminderEnabled" type="checkbox">
          <span>到点提醒我</span>
        </label>
      </div>
      <div class="field">
        <label for="newReminder">提醒时间</label>
        <input id="newReminder" type="datetime-local">
      </div>
      <p class="hint" style="margin:12px 0 0;">
        截止日期留空就按今天 23:59。提醒交给手机来响，这台电脑也能单独开启通知。
      </p>
      <button style="margin-top:12px;" onclick="enableBrowserReminders()">开启电脑提醒</button>
    </section>

    <section class="card">
      <div class="card-title-row"><h2>导入备份</h2></div>
      <input id="importFile" type="file" accept="application/json,.json" onchange="importBundle(this)">
      <p class="hint" style="margin:12px 0 0;">
        按 uid 和更新时间合并，不会盖掉较新的数据。删除会留墓碑，能在设备之间正确传播。
      </p>
    </section>
  </div>

  <div class="col">
    <section class="card">
      <div class="workbar">
        <div class="tabs" role="tablist">
          <button class="tab active" data-filter="open" onclick="setTaskFilter('open')">待我处理 <span id="countOpen" class="pill">0</span></button>
          <button class="tab" data-filter="priority" onclick="setTaskFilter('priority')">优先处理</button>
          <button class="tab" data-filter="done" onclick="setTaskFilter('done')">我已处理 <span id="countDone" class="pill">0</span></button>
          <button class="tab" data-filter="starred" onclick="setTaskFilter('starred')">星标</button>
        </div>
      </div>
      <div id="taskList"><p class="hint">加载中…</p></div>
    </section>
  </div>
</main>

<div id="toast" role="status" aria-live="polite"></div>

<div id="editor" class="overlay hidden">
  <div class="sheet">
    <h2 id="editorTitle">编辑待办</h2>
    <p class="sheet-sub">改动会在保存后合并回手机，较新的一侧说了算。</p>
    <div class="field"><label for="editSummary">标题</label><input id="editSummary" type="text"></div>
    <div class="field"><label for="editDescription">描述</label><textarea id="editDescription"></textarea></div>
    <div class="field"><label for="editLocation">地点</label><input id="editLocation" type="text"></div>
    <div class="field">
      <label for="editPriority">优先级</label>
      <select id="editPriority"><option value="low">低</option><option value="normal">普通</option><option value="high">高</option><option value="urgent">紧急</option></select>
    </div>
    <div class="field">
      <label class="switch-row" for="editStarred"><input id="editStarred" type="checkbox"><span>加入星标</span></label>
    </div>
    <div class="field">
      <label class="switch-row" for="editReminderEnabled"><input id="editReminderEnabled" type="checkbox"><span>到点提醒我</span></label>
    </div>
    <div class="field"><label for="editReminder">提醒时间</label><input id="editReminder" type="datetime-local"></div>
    <div class="field">
      <label for="editRepeatType">重复</label>
      <select id="editRepeatType"><option value="norepeat">不重复</option><option value="daily">每天</option><option value="weekly">每周</option><option value="monthly">每月</option></select>
    </div>
    <div class="field"><label for="editTags">标签</label><input id="editTags" type="text" placeholder="用逗号分隔"></div>
    <div class="field">
      <label>子待办</label>
      <div id="editSubtasks"></div>
      <button type="button" class="add-row" style="margin-top:9px;" onclick="addSubtaskRow()">添加步骤</button>
      <p class="hint" style="margin:9px 0 0;">
        每一步都能单独设开始、结束时间和提前提醒分钟数。提前量留空就沿用设置里的默认值；没有时间的步骤只是普通清单项。
      </p>
    </div>
    <div class="actions">
      <button onclick="closeEditor()">取消</button>
      <button class="primary" onclick="saveEditor()">保存修改</button>
    </div>
  </div>
</div>

<script>
// 旧版这个 key 叫 telechron_token：读得到就顺手迁移，免得用户重新配对一次
var token = localStorage.getItem('elychron_token') || localStorage.getItem('telechron_token') || '';
if (token) { localStorage.setItem('elychron_token', token); localStorage.removeItem('telechron_token'); }
var bundle = null;
var taskFilter = 'open';

function setTaskFilter(filter) {
  taskFilter = filter;
  document.querySelectorAll('.tab').forEach(function (el) {
    el.classList.toggle('active', el.getAttribute('data-filter') === filter);
  });
  render();
}
function toast(msg) { notify(msg, 'err'); }
var pendingMutation = null;
function setStatus(text, kind) {
  var el = document.getElementById('status');
  el.textContent = text;
  el.className = 'pill' + (kind ? ' ' + kind : '');
}
function notify(message, kind) {
  var host = document.getElementById('toast');
  var item = document.createElement('div');
  item.className = 'toast-item ' + (kind || 'info');
  item.textContent = message;
  host.appendChild(item);
  while (host.children.length > 3) host.removeChild(host.firstChild);
  setTimeout(function () { if (item.parentNode) item.remove(); }, kind === 'err' ? 7000 : 3200);
}
function api(path, options, attempt) {
  options = options || {};
  attempt = attempt || 0;
  options.headers = Object.assign({ 'X-Lan-Token': token }, options.headers || {});
  // 每次重试都创建新的 options 和 AbortController；已 abort 的 signal 不能复用。
  var requestOptions = Object.assign({}, options);
  var requestHeaders = Object.assign({}, options.headers || {});
  requestOptions.headers = requestHeaders;
  var controller = window.AbortController ? new AbortController() : null;
  if (controller) { requestOptions.signal = controller.signal; setTimeout(function () { controller.abort(); }, 9000); }
  return fetch(path, requestOptions).then(function (res) {
    return res.json().then(function (data) {
      if (res.status === 401) {
        token = ''; localStorage.removeItem('elychron_token');
        showPair('配对已失效，请重新输入配对码');
        throw new Error(data.error || 'unauthorized');
      }
      if (!res.ok) { throw new Error(data.error || ('HTTP ' + res.status)); }
      return data;
    });
  }).catch(function (error) {
    var safeToRetry = (!options.method || options.method === 'GET') && attempt < 2 && token;
    if (!safeToRetry) throw error;
    setStatus('正在重连…', 'err');
    return new Promise(function (resolve) { setTimeout(resolve, 500 * (attempt + 1)); })
      .then(function () { return api(path, options, attempt + 1); });
  });
}
function showPair(msg) {
  document.getElementById('pair').classList.remove('hidden');
  document.getElementById('pairErr').textContent = msg || '';
  if (pendingMutation) notify('重新配对后会继续刚才的保存操作', 'info');
}
function pair() {
  var code = document.getElementById('codeInput').value.trim();
  if (!code) return;
  fetch('/pair', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: code })
  }).then(function (r) { return r.json(); }).then(function (data) {
    if (!data.ok) { document.getElementById('pairErr').textContent = data.error || '配对失败'; return; }
    token = data.token;
    localStorage.setItem('elychron_token', token);
    document.getElementById('pair').classList.add('hidden');
    refresh();
    if (pendingMutation) {
      var retry = pendingMutation;
      pendingMutation = null;
      setTimeout(retry, 0);
    }
  }).catch(function (e) { document.getElementById('pairErr').textContent = '' + e; });
}

var browserReminders = false;
var browserReminderTimers = {};
var browserReminderPermission = 'default';
function enableBrowserReminders() {
  if (!('Notification' in window)) { notify('当前浏览器不支持电脑提醒', 'err'); return; }
  Notification.requestPermission().then(function (permission) {
    browserReminderPermission = permission;
    browserReminders = permission === 'granted';
    notify(browserReminders ? '电脑提醒已开启' : '未获得提醒权限', browserReminders ? 'ok' : 'err');
    if (browserReminders) scheduleBrowserReminders();
  });
}
function scheduleBrowserReminders() {
  if (!browserReminders || !bundle) return;
  var active = {};
  var nowMs = Date.now();
  var lead = leadMinutes();
  var added = 0;
  // 先算出「应该有哪些提醒」，再和已经排好的对照：
  // 新增的排上，删掉 / 改过时间的清掉。这样重复调用（每 30 秒刷新一次）不会重复弹。
  var plan = [];
  (bundle.tasks || []).forEach(function (t) {
    if (t.status === 'completed' || t.status === 'deleted') return;
    // 任务级：用手机端写好的 reminderTime 那一刻
    if (t.reminderEnabled && t.reminderTime) {
      plan.push({ key: 'task|' + t.uid + '|' + t.reminderTime, at: stampMs(t.reminderTime), body: t.summary || '有一项待办' });
    }
    // 子待办：与手机端一致 —— 时刻 − 提前量；这一步单独设过提前量就用它的。
    (t.subtasks || []).forEach(function (sub, index) {
      var when = subReminderTime(sub, lead);
      if (!when) return;
      plan.push({
        key: 'sub|' + t.uid + '|' + (sub.uid || index) + '|' + when.getTime(),
        at: when.getTime(),
        body: (sub.title || '有一步该做') + (t.summary ? ' · ' + t.summary : '')
      });
    });
  });
  plan.forEach(function (item) {
    active[item.key] = true;
    if (browserReminderTimers[item.key]) return;
    var delay = item.at - nowMs;
    if (delay < 0 || delay > 2147483647) return;
    added++;
    browserReminderTimers[item.key] = setTimeout(function () {
      delete browserReminderTimers[item.key];
      new Notification('Elychron 提醒', { body: item.body });
      notify('⏰ ' + item.body, 'info');
    }, delay);
  });
  Object.keys(browserReminderTimers).forEach(function (key) {
    if (!active[key]) { clearTimeout(browserReminderTimers[key]); delete browserReminderTimers[key]; }
  });
  // 只有真的新排了才说话，免得每次自动刷新都弹一条。
  if (added) notify('已安排 ' + added + ' 条电脑提醒', 'info');
}
function fmt(iso) {
  if (!iso) return '';
  var d = new Date(iso);
  if (isNaN(d)) return '';
  var p = function (n) { return (n < 10 ? '0' : '') + n; };
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}
function esc(s) {
  return ('' + (s == null ? '' : s)).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}
var PRIO = { low: '低', normal: '', high: '高', urgent: '紧急' };

// ===== 时间戳格式 =====
// 约定：和手机端一样写**本地时间**的 ISO 串（不带 Z）。DataBackup / TaskJson 用
// toIso8601String() 写的就是这个格式；混着 'Z' 结尾的 UTC 串会让字符串比较失真。
function pad2(n) { return (n < 10 ? '0' : '') + n; }
function isoLocal(date) {
  return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate()) +
    'T' + pad2(date.getHours()) + ':' + pad2(date.getMinutes()) + ':' + pad2(date.getSeconds()) +
    '.' + ('00' + date.getMilliseconds()).slice(-3);
}
function isoLocalOrNull(value) {
  if (!value) return null;
  var d = new Date(value);
  return isNaN(d) ? null : isoLocal(d);
}
// 解析成毫秒便于比较：老数据里可能混着 'Z' 结尾与本地格式两种串。
function stampMs(value) {
  if (!value) return 0;
  var ms = Date.parse(value);
  return isNaN(ms) ? 0 : ms;
}
function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function clockOf(d) { return pad2(d.getHours()) + ':' + pad2(d.getMinutes()); }
function briefOf(d) {
  return sameDay(d, new Date()) ? clockOf(d) : (d.getMonth() + 1) + '-' + d.getDate() + ' ' + clockOf(d);
}
function newUid(prefix) {
  var rand = (window.crypto && crypto.randomUUID)
    ? crypto.randomUUID()
    : ('r' + Math.random().toString(36).slice(2) + Date.now().toString(36));
  return (prefix ? prefix + '-' : '') + rand;
}

// ===== 子待办：语义与手机端 model/task.dart 的 SubTask 一致 =====
// 默认提前量优先读 bundle.settings.reminderLeadMinutes（手机上「默认提醒提前量」），
// 读不到就退回 30 分钟（与 App 默认值相同）。
var DEFAULT_LEAD_MINUTES = 30;
function leadMinutes() {
  var settings = bundle && bundle.settings;
  var value = settings ? settings.reminderLeadMinutes : null;
  return (typeof value === 'number' && value >= 0) ? value : DEFAULT_LEAD_MINUTES;
}
function leadLabel(minutes) {
  if (minutes <= 0) return '准时';
  if (minutes % 1440 === 0) return '提前 ' + (minutes / 1440) + ' 天';
  if (minutes % 60 === 0) return '提前 ' + (minutes / 60) + ' 小时';
  return '提前 ' + minutes + ' 分钟';
}
// stepLead：这一步自己的提前量；没设（null）就用默认值。负数按 0 处理（同手机端）。
function stepLead(sub, fallback) {
  var value = (sub && typeof sub.reminderMinutes === 'number' && sub.reminderMinutes >= 0)
    ? sub.reminderMinutes : fallback;
  return value < 0 ? 0 : value;
}
function subHasTime(sub) { return !!sub && !!(sub.startTime || sub.endTime); }
function subAnchorTime(sub) {
  if (!sub) return null;
  var raw = sub.startTime || sub.endTime;
  if (!raw) return null;
  var d = new Date(raw);
  return isNaN(d) ? null : d;
}
function subIsSpan(sub) {
  if (!sub || !sub.startTime || !sub.endTime) return false;
  var a = new Date(sub.startTime), b = new Date(sub.endTime);
  return !isNaN(a) && !isNaN(b) && a.getTime() < b.getTime();
}
// 这一步什么时候响：已完成 / 没时间 → 不提醒（同 SubTask.reminderAt）。
function subReminderTime(sub, defaultLead) {
  if (!sub || sub.done) return null;
  var anchor = subAnchorTime(sub);
  if (!anchor) return null;
  return new Date(anchor.getTime() - stepLead(sub, defaultLead) * 60000);
}
function subIsOngoing(sub, now) {
  if (!sub || sub.done || !subIsSpan(sub)) return false;
  var a = new Date(sub.startTime), b = new Date(sub.endTime);
  return now.getTime() >= a.getTime() && now.getTime() < b.getTime();
}
function subIsMissed(sub, now) {
  if (!sub || sub.done) return false;
  var due = sub.endTime || sub.startTime;
  if (!due) return false;
  var d = new Date(due);
  return !isNaN(d) && d.getTime() < now.getTime();
}
function subTimeLabel(sub) {
  var anchor = subAnchorTime(sub);
  if (!anchor) return '';
  var head = sameDay(anchor, new Date()) ? '' : (anchor.getMonth() + 1) + '-' + anchor.getDate() + ' ';
  return head + (subIsSpan(sub)
    ? clockOf(new Date(sub.startTime)) + '-' + clockOf(new Date(sub.endTime))
    : clockOf(anchor));
}
// 与手机端详情页同一套说法：会在 17:40 提醒 / 17:40 已提醒过
function reminderText(when) {
  return when.getTime() > Date.now() ? '会在 ' + briefOf(when) + ' 提醒' : briefOf(when) + ' 已提醒过';
}
// 显示顺序与手机端一致：没时间的清单项在前，有时间的按时刻排。
function orderedSubtasks(task) {
  var items = (task.subtasks || []).map(function (sub, index) { return { sub: sub, index: index }; });
  var timeless = items.filter(function (x) { return !subHasTime(x.sub); });
  var timed = items.filter(function (x) { return subHasTime(x.sub) && subAnchorTime(x.sub); })
    .sort(function (a, b) { return subAnchorTime(a.sub) - subAnchorTime(b.sub); });
  var rest = items.filter(function (x) { return subHasTime(x.sub) && !subAnchorTime(x.sub); });
  return timeless.concat(timed, rest);
}
// 最近一条还没到点的子待办提醒，用来在任务行上摘要显示。
function nearestSubReminder(task) {
  var lead = leadMinutes(), nowMs = Date.now(), best = null;
  (task.subtasks || []).forEach(function (sub) {
    var when = subReminderTime(sub, lead);
    if (!when || when.getTime() <= nowMs) return;
    if (!best || when.getTime() < best.when.getTime()) best = { when: when, sub: sub };
  });
  if (!best) return '';
  return '⏰ ' + briefOf(best.when) + ' ' + (best.sub.title || '有一步该做');
}
function renderSubtaskLines(task) {
  var items = orderedSubtasks(task);
  if (!items.length) return '';
  var now = new Date(), lead = leadMinutes();
  var lines = items.map(function (item) {
    var sub = item.sub;
    var when = subReminderTime(sub, lead);
    var ongoing = subIsOngoing(sub, now), missed = subIsMissed(sub, now);
    var state = sub.done ? 'done' : (ongoing ? 'ongoing' : (missed ? 'missed' : ''));
    var time = subTimeLabel(sub);
    return '<div class="sub-item ' + state + '">' +
      '<input type="checkbox" ' + (sub.done ? 'checked' : '') +
        ' onclick="event.stopPropagation()" onchange="toggleSubtask(\'' + task.uid + '\',' + item.index + ', this.checked)">' +
      (time ? '<span class="sub-time">' + esc(time) + '</span>' : '') +
      '<span class="sub-title">' + esc(sub.title || '(未命名步骤)') + '</span>' +
      (when ? '<span class="sub-hint">⏰ ' + esc(reminderText(when)) + '</span>' : '') +
      (ongoing ? '<span class="sub-state">进行中</span>'
        : (missed ? '<span class="sub-state">已超时</span>' : '')) +
      '</div>';
  });
  return '<div class="sub-list">' + lines.join('') + '</div>';
}

function renderRow(t) {
  var done = t.status === 'completed';
  var meta = [];
  // 截止时间按紧迫程度着色，和手机端一样：过期红、今天橙，其余保持次要文字色。
  var endMs = stampMs(t.endTime);
  var now = new Date();
  var endAt = endMs ? new Date(endMs) : null;
  var dueClass = '';
  if (!done && endAt) {
    if (endMs < now.getTime()) dueClass = ' class="overdue"';
    else if (sameDay(endAt, now)) dueClass = ' class="due-soon"';
  }
  meta.push('<span' + dueClass + '>' + (done ? '已完成 ' : '截止 ') + esc(fmt(t.endTime)) + '</span>');
  if (t.location) meta.push('<span>📍' + esc(t.location) + '</span>');
  if (t.reminderEnabled && t.reminderTime) meta.push('<span>⏰ 提醒 ' + esc(fmt(t.reminderTime)) + '</span>');
  if (PRIO[t.priority]) meta.push('<span class="prio-' + t.priority + '">' + PRIO[t.priority] + '</span>');
  if (t.subtasks && t.subtasks.length) {
    var dn = t.subtasks.filter(function (s) { return s.done; }).length;
    meta.push('<span>子待办 ' + dn + '/' + t.subtasks.length + '</span>');
    var next = nearestSubReminder(t);
    if (next && !done) meta.push('<span>' + esc(next) + '</span>');
  }
  (t.tags || []).forEach(function (tag) { meta.push('<span class="tag">' + esc(tag) + '</span>'); });
  return '<div class="row" onclick="openEditor(\'' + t.uid + '\')">' +
    '<input type="checkbox" onclick="event.stopPropagation()" ' + (done ? 'checked' : '') + ' onchange="toggleDone(\'' + t.uid + '\', this.checked)">' +
    '<div class="body">' +
      '<div class="title' + (done ? ' done' : '') + '">' + esc(t.summary || '(无标题)') + '</div>' +
      '<div class="meta">' + meta.join('') + '</div>' +
      (t.description ? '<div class="meta">' + esc(t.description) + '</div>' : '') +
      renderSubtaskLines(t) +
    '</div>' +
    '<button class="danger" onclick="event.stopPropagation(); removeTask(\'' + t.uid + '\')">删除</button>' +
  '</div>';
}

function render() {
  if (!bundle) return;
  var tasks = bundle.tasks || [];
  var query = (document.getElementById('searchInput') || {}).value || '';
  query = query.trim().toLowerCase();
  if (query) tasks = tasks.filter(function (t) {
    return (t.summary || '').toLowerCase().indexOf(query) >= 0 ||
      (t.description || '').toLowerCase().indexOf(query) >= 0;
  });
  var open = tasks.filter(function (t) { return t.status !== 'completed' && t.status !== 'deleted'; });
  open.sort(function (a, b) { return (a.endTime || '').localeCompare(b.endTime || ''); });
  var done = tasks.filter(function (t) { return t.status === 'completed'; });
  var shown = taskFilter === 'done' ? done : taskFilter === 'priority'
    ? open.filter(function (t) { return t.priority === 'high' || t.priority === 'urgent'; })
    : taskFilter === 'starred' ? tasks.filter(function (t) { return t.starred && t.status !== 'deleted'; }) : open;
  document.getElementById('taskList').innerHTML = shown.length
    ? shown.map(renderRow).join('')
    : '<div class="empty-state"><span class="emoji">🎉</span>这里还没有任务</div>';
  document.getElementById('countOpen').textContent = open.length;
  document.getElementById('countDone').textContent = done.length;
}

function refresh() {
  setStatus(navigator.onLine === false ? '等待网络…' : '同步中…');
  api('/bundle').then(function (data) {
    bundle = data;
    render();
    setStatus('已连接 · ' + (data.tasks || []).length + ' 条待办', 'ok');
    scheduleBrowserReminders();
  }).catch(function (e) {
    if (('' + e).indexOf('unauthorized') < 0 && ('' + e).indexOf('配对') < 0) {
      setStatus('连接失败', 'err');
      toast('' + e);
    }
  });
}

function push(summary) {
  // 若会话过期，保存动作暂存到重新配对后继续，避免用户修改丢失。
  pendingMutation = function () { push(summary); };
  // 写入前重新拉取；把本次网页编辑合并到新快照，避免覆盖手机刚产生的改动。
  var edited = JSON.parse(JSON.stringify(bundle));
  return api('/bundle').then(function (fresh) {
    var byUid = {};
    (edited.tasks || []).forEach(function (t) { byUid[t.uid] = t; });
    (fresh.tasks || []).forEach(function (t, i) {
      var local = byUid[t.uid];
      // 比的是「时刻」而不是字符串：老数据里混着 'Z' 结尾（UTC）与本地格式两种
      // 时间戳，直接比字符串会把刚改的判成旧的，然后把网页编辑丢掉。
      if (local && stampMs(local.updatedAt) >= stampMs(t.updatedAt)) {
        fresh.tasks[i] = local;
      }
    });
    (edited.tasks || []).forEach(function (t) {
      if (!(fresh.tasks || []).some(function (x) { return x.uid === t.uid; })) fresh.tasks.push(t);
    });
    bundle = fresh;
    render();
    return api('/bundle', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(bundle)
    });
  }).then(function (data) {
    pendingMutation = null;
    notify((summary ? summary + '，' : '') + '已同步到手机：' + (data.summary || ''), 'ok');
    return refresh();
  }).catch(function (e) { notify('同步失败：' + e, 'err'); });
}

function findTask(uid) {
  for (var i = 0; i < bundle.tasks.length; i++) { if (bundle.tasks[i].uid === uid) return bundle.tasks[i]; }
  return null;
}
var editingUid = null;
// 编辑器里的子待办草稿：先复制一份，改字段只动草稿，点「保存修改」才写回任务。
// 只要用户没改过的字段就原样保留（uid / 描述 / 优先级 / 附件都不会丢）。
var editingSubtasks = [];
function deepCopy(value) { return JSON.parse(JSON.stringify(value)); }
function toInputDate(iso) {
  if (!iso) return '';
  var d = new Date(iso); if (isNaN(d)) return '';
  var p = function (n) { return (n < 10 ? '0' : '') + n; };
  return d.getFullYear() + '-' + p(d.getMonth()+1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
}
function openEditor(uid) {
  var t = findTask(uid); if (!t) return;
  editingUid = uid;
  document.getElementById('editSummary').value = t.summary || '';
  document.getElementById('editDescription').value = t.description || '';
  document.getElementById('editLocation').value = t.location || '';
  document.getElementById('editPriority').value = t.priority || 'normal';
  document.getElementById('editStarred').checked = !!t.starred;
  document.getElementById('editReminderEnabled').checked = !!t.reminderEnabled;
  document.getElementById('editReminder').value = toInputDate(t.reminderTime);
  document.getElementById('editRepeatType').value = t.repeatType || 'norepeat';
  document.getElementById('editTags').value = (t.tags || []).join(', ');
  editingSubtasks = (t.subtasks || []).map(deepCopy);
  renderSubtasksEditor();
  document.getElementById('editorTitle').textContent = '编辑待办 · ' + (t.reminderEnabled ? '已设提醒' : '未设提醒');
  document.getElementById('editor').classList.remove('hidden');
}
function closeEditor() { editingUid = null; editingSubtasks = []; document.getElementById('editor').classList.add('hidden'); }

// ----------------------------------------------------- 子待办字段编辑
// 每一行都是完整的「一步」：勾选 = done，标题，开始 / 结束时间，提前提醒分钟数。
// 时间留空 = 手机端说的「清单型」步骤（不单独提醒）；提前量留空 = 用默认提前量。
function subRowHint(sub) {
  var lead = leadMinutes();
  var hint = subHasTime(sub)
    ? '时间 ' + subTimeLabel(sub) + '（' + (subIsSpan(sub) ? '一段时间' : '一个时刻') + '）'
    : '没有时间：普通清单项，手机不会为这一步单独提醒';
  if (sub.done) return hint + ' · 已完成，不提醒';
  var when = subReminderTime(sub, lead);
  if (!when) return hint;
  return hint + ' · ' + leadLabel(stepLead(sub, lead)) + ' → ' + fmt(isoLocal(when)) +
    (when.getTime() > Date.now() ? ' 提醒' : ' 已过去');
}
function renderSubtasksEditor() {
  var host = document.getElementById('editSubtasks');
  if (!editingSubtasks.length) {
    host.innerHTML = '<div class="empty">还没有步骤。点下面的「+ 添加步骤」加一条。</div>';
    return;
  }
  host.innerHTML = editingSubtasks.map(function (sub, index) {
    var lead = (typeof sub.reminderMinutes === 'number' && sub.reminderMinutes >= 0) ? sub.reminderMinutes : '';
    return '<div class="sub-row" data-index="' + index + '">' +
      '<div class="sub-row-head">' +
        '<input type="checkbox" class="sub-done" aria-label="完成"' + (sub.done ? ' checked' : '') +
          ' onchange="subtaskRowChanged(this)">' +
        '<input type="text" class="sub-title" placeholder="这一步要做什么…" value="' + esc(sub.title || '') +
          '" oninput="subtaskRowChanged(this)">' +
        '<button type="button" class="danger" onclick="removeSubtaskRow(' + index + ')">删除</button>' +
      '</div>' +
      '<div class="sub-row-times">' +
        '<div><label>开始时间</label><input type="datetime-local" class="sub-start" value="' +
          esc(toInputDate(sub.startTime)) + '" onchange="subtaskRowChanged(this)"></div>' +
        '<div><label>结束时间</label><input type="datetime-local" class="sub-end" value="' +
          esc(toInputDate(sub.endTime)) + '" onchange="subtaskRowChanged(this)"></div>' +
        '<div><label>提前提醒（分钟）</label><input type="number" class="sub-lead" min="0" step="5" placeholder="默认 ' +
          leadMinutes() + '" value="' + lead + '" oninput="subtaskRowChanged(this)"></div>' +
      '</div>' +
      '<div class="sub-row-hint">' + esc(subRowHint(sub)) + '</div>' +
    '</div>';
  }).join('');
}
// 找到输入框所在的那一整行。注意必须按**类名整体**匹配：
// `.sub-row-times` / `.sub-row-head` 里也含有 "sub-row" 这几个字，
// 用 indexOf 会把它们当成整行，后面的 querySelector 就全落空了。
function subtaskRowOf(el) {
  if (el && el.closest) {
    var found = el.closest('.sub-row');
    if (found) return found;
  }
  var node = el;
  while (node) {
    var cls = ('' + (node.className || '')).split(/\s+/);
    if (cls.indexOf('sub-row') >= 0) return node;
    node = node.parentNode;
  }
  return null;
}
// 输入框 → 草稿。只改这一行对应的那一条，不整块重画（否则会打断正在输入的焦点）。
function readSubtaskRow(row) {
  var index = parseInt(row.getAttribute('data-index'), 10);
  var sub = editingSubtasks[index];
  if (!sub) return null;
  sub.done = row.querySelector('.sub-done').checked;
  sub.title = row.querySelector('.sub-title').value.trim();
  sub.startTime = isoLocalOrNull(row.querySelector('.sub-start').value);
  sub.endTime = isoLocalOrNull(row.querySelector('.sub-end').value);
  var raw = row.querySelector('.sub-lead').value.trim();
  var minutes = raw === '' ? NaN : parseInt(raw, 10);
  sub.reminderMinutes = isNaN(minutes) ? null : (minutes < 0 ? 0 : minutes);
  return sub;
}
function subtaskRowChanged(el) {
  var row = subtaskRowOf(el);
  if (!row) return;
  var sub = readSubtaskRow(row);
  if (!sub) return;
  var hint = row.querySelector('.sub-row-hint');
  if (hint) hint.textContent = subRowHint(sub);
}
// 保存前把 DOM 里的所有行读回草稿（避免漏掉没有触发过事件的输入）。
function syncSubtasksEditor() {
  var rows = document.querySelectorAll('#editSubtasks .sub-row');
  for (var i = 0; i < rows.length; i++) readSubtaskRow(rows[i]);
}
function addSubtaskRow() {
  syncSubtasksEditor();
  editingSubtasks.push({
    uid: newUid('sub'), title: '', done: false, description: '',
    startTime: null, endTime: null, reminderMinutes: null,
    priority: 'normal', tags: [], attachments: [], location: ''
  });
  renderSubtasksEditor();
  var rows = document.querySelectorAll('#editSubtasks .sub-row');
  var last = rows[rows.length - 1];
  if (last) { var input = last.querySelector('.sub-title'); if (input) input.focus(); }
}
function removeSubtaskRow(index) {
  syncSubtasksEditor();
  editingSubtasks.splice(index, 1);
  renderSubtasksEditor();
}
function saveEditor() {
  var t = findTask(editingUid); if (!t) return closeEditor();
  syncSubtasksEditor();
  t.summary = document.getElementById('editSummary').value.trim() || '(无标题)';
  t.description = document.getElementById('editDescription').value;
  t.location = document.getElementById('editLocation').value;
  t.priority = document.getElementById('editPriority').value;
  t.starred = document.getElementById('editStarred').checked;
  t.reminderEnabled = document.getElementById('editReminderEnabled').checked;
  t.reminderTime = isoLocalOrNull(document.getElementById('editReminder').value);
  t.repeatType = document.getElementById('editRepeatType').value;
  t.tags = document.getElementById('editTags').value.split(',').map(function (x) { return x.trim(); }).filter(Boolean);
  // 空行（没标题也没时间）直接丢掉；其余原样写回，字段缺什么补什么默认值。
  t.subtasks = editingSubtasks.filter(function (sub) {
    return (sub.title || '') !== '' || subHasTime(sub);
  }).map(function (sub) {
    var out = Object.assign({}, sub);
    out.uid = out.uid || newUid('sub');
    out.title = (out.title || '').trim();
    out.done = !!out.done;
    if (typeof out.description !== 'string') out.description = '';
    out.startTime = out.startTime || null;
    out.endTime = out.endTime || null;
    out.reminderMinutes = (typeof out.reminderMinutes === 'number' && out.reminderMinutes >= 0)
      ? out.reminderMinutes : null;
    if (!out.priority) out.priority = 'normal';
    if (!out.tags) out.tags = [];
    if (!out.attachments) out.attachments = [];
    if (typeof out.location !== 'string') out.location = '';
    return out;
  });
  t.updatedAt = isoLocal(new Date());
  closeEditor(); render(); push('已保存修改');
}
// 任务行上直接勾掉某一步（不用打开编辑器）。
function toggleSubtask(uid, index, checked) {
  var t = findTask(uid);
  var sub = t && t.subtasks ? t.subtasks[index] : null;
  if (!sub) { render(); return; }
  sub.done = !!checked;
  t.updatedAt = isoLocal(new Date());
  push(checked ? '这一步已完成' : '这一步已取消完成');
}
function toggleDone(uid, checked) {
  var t = findTask(uid);
  if (!t) return;
  t.status = checked ? 'completed' : 'running';
  t.updatedAt = isoLocal(new Date());
  push(checked ? '已打钩' : '已取消完成');
}
function removeTask(uid) {
  var t = findTask(uid);
  if (!t || !confirm('删除「' + (t.summary || '') + '」？')) { render(); return; }
  t.status = 'deleted';
  t.updatedAt = isoLocal(new Date());
  push('已删除');
}
function addTask() {
  var title = document.getElementById('newTitle').value.trim();
  if (!title) { toast('先写点什么'); return; }
  var dateStr = document.getElementById('newEnd').value;
  var end = dateStr ? new Date(dateStr + 'T23:59:00') : new Date(new Date().setHours(23, 59, 0, 0));
  var now = isoLocal(new Date());
  var uid = (crypto.randomUUID ? crypto.randomUUID() : 'r' + Math.random().toString(36).slice(2) + Date.now());
  bundle.tasks.push({
    uid: uid, status: 'running', description: document.getElementById('newDescription').value, timeSpent: 0,
    endTime: isoLocal(end), location: '', summary: title,
    type: 'deadline', startTime: isoLocal(end), repeatType: 'norepeat',
    repeatPeriod: 1, repeatEndsTime: isoLocal(end),
    fromUid: null, subtasks: [], priority: 'normal',
    reminderEnabled: document.getElementById('newReminderEnabled').checked,
    reminderTime: document.getElementById('newReminderEnabled').checked
      ? isoLocalOrNull(document.getElementById('newReminder').value) : null,
    attachments: [], comments: [], tags: [], starred: false,
    createdAt: now, updatedAt: now
  });
  document.getElementById('newTitle').value = '';
  document.getElementById('newDescription').value = '';
  document.getElementById('newReminder').value = '';
  document.getElementById('newReminderEnabled').checked = false;
  push('已新建「' + title + '」');
}
function downloadBundle() {
  if (!bundle) return;
  var blob = new Blob([JSON.stringify(bundle, null, 2)], { type: 'application/json' });
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  var p = function (n) { return (n < 10 ? '0' : '') + n; };
  var d = new Date();
  a.href = url;
  a.download = 'elychron-' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + '.json';
  a.click();
  URL.revokeObjectURL(url);
}
function importBundle(input) {
  var file = input.files && input.files[0];
  if (!file) return;
  var reader = new FileReader();
  reader.onload = function () {
    var text = '' + reader.result;
    var parsed;
    try { parsed = JSON.parse(text); } catch (e) { toast('不是合法的 JSON'); return; }
    if (!parsed || !parsed.tasks) { toast('这个文件里没有待办数据'); return; }
    if (!confirm('用这份备份与手机上的数据合并？')) return;
    api('/bundle', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: text
    }).then(function (data) {
      toast('合并完成：' + (data.summary || ''));
      refresh();
    }).catch(function (e) { toast('导入失败：' + e); });
  };
  reader.readAsText(file);
  input.value = '';
}

document.getElementById('codeInput').addEventListener('keydown', function (e) {
  if (e.key === 'Enter') pair();
});
window.addEventListener('online', function () { notify('网络已恢复，正在同步…', 'ok'); refresh(); });
window.addEventListener('offline', function () { setStatus('已离线', 'err'); notify('当前没有网络连接', 'err'); });
document.addEventListener('visibilitychange', function () { if (!document.hidden && token) refresh(); });
setInterval(function () { if (!document.hidden && token) refresh(); }, 30000);
if (token) { refresh(); } else { showPair(); }
</script>
</body>
</html>
''';
