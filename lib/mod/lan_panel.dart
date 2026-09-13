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
  :root {
    --bg: #f8f8fb; --card: #ffffff; --line: #e8e8ef;
    --text: #202027; --muted: #8b8b96; --accent: #ff6b9a;
    --danger: #ff3b30; --ok: #34c759; --warn: #ff9500;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#17171c; --card:#24242b; --line:#3a3a44; --text:#f5f5f7; --muted:#a4a4ad; --accent:#ff7da8; }
    header { background:rgba(23,23,28,.88); }
    input, textarea, select { background:#2c2c34 !important; color:var(--text) !important; }
    #editSubtasks .sub-row { background:#2b2b33; }
    button { background:var(--card); color:var(--text); }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--text);
    font: 15px/1.5 -apple-system, "PingFang SC", "Microsoft YaHei", system-ui, sans-serif;
  }
  header {
    position: sticky; top: 0; z-index: 5; background: rgba(245,245,247,.92);
    backdrop-filter: saturate(180%) blur(20px);
    border-bottom: 1px solid var(--line); padding: 14px 20px;
    display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
  }
  header h1 { font-size: 17px; margin: 0; font-weight: 600; }
  .pill { font-size: 12px; padding: 2px 8px; border-radius: 999px; background: var(--line); color: var(--muted); }
  .pill.ok { background: rgba(52,199,89,.15); color: #1a7f37; }
  .pill.err { background: rgba(255,59,48,.15); color: #b3261e; }
  main { max-width: 860px; margin: 0 auto; padding: 20px; }
  .card {
    background: var(--card); border: 1px solid var(--line); border-radius: 14px;
    padding: 16px; margin-bottom: 16px;
  }
  .card h2 { font-size: 14px; margin: 0 0 12px; color: var(--muted); font-weight: 600; letter-spacing: .02em; }
  .workbar { display:flex; gap:16px; align-items:flex-end; justify-content:space-between; flex-wrap:wrap; margin-bottom:10px; }
  .tabs { display:flex; gap:5px; flex-wrap:wrap; }
  .tab { border-color:transparent; background:transparent; color:var(--muted); padding:6px 8px; }
  .tab.active { color:var(--accent); background:rgba(255,107,154,.10); }
  .tab .pill { margin-left:3px; }
  .row { display: flex; align-items: flex-start; gap: 12px; padding: 10px 0; border-top: 1px solid var(--line); cursor:pointer; transition:background .18s ease, transform .18s ease; }
  .row:hover { background:rgba(255,107,154,.06); transform:translateX(2px); }
  .row:first-of-type { border-top: none; }
  .row input[type=checkbox] { width: 20px; height: 20px; margin-top: 2px; accent-color: var(--accent); cursor: pointer; flex: none; }
  .row .body { flex: 1; min-width: 0; }
  .row .title { font-weight: 500; word-break: break-word; }
  .row .title.done { color: var(--muted); text-decoration: line-through; }
  .meta { font-size: 12.5px; color: var(--muted); margin-top: 2px; display: flex; gap: 8px; flex-wrap: wrap; }
  .tag { background: var(--line); border-radius: 6px; padding: 0 6px; font-size: 12px; }
  .prio-high { color: var(--warn); } .prio-urgent { color: var(--danger); }
  button {
    font: inherit; border: 1px solid var(--line); background: var(--card);
    color: var(--text); border-radius: 9px; padding: 6px 12px; cursor: pointer;
  }
  button:hover { background: #fafafa; }
  button.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  button.danger { color: var(--danger); }
  button:disabled { opacity: .5; cursor: default; }
  input[type=text], input[type=date], input[type=number] {
    font: inherit; padding: 7px 10px; border: 1px solid var(--line);
    border-radius: 9px; background: #fff; color: var(--text); width: 100%;
  }
  .grid { display: grid; gap: 8px; grid-template-columns: 1fr 170px auto; align-items: center; }
  @media (max-width: 620px) { .grid { grid-template-columns: 1fr; } }
  .hint { font-size: 12.5px; color: var(--muted); }
  #editor {
    position: fixed; inset: 0; z-index: 35; display:flex; align-items:center; justify-content:center;
    background: rgba(20,20,28,.22); backdrop-filter: blur(8px);
  }
  #editor .box { width:min(560px, calc(100vw - 32px)); max-height:calc(100vh - 40px); overflow:auto;
    background:var(--card); border:1px solid var(--line); border-radius:18px; padding:22px;
    box-shadow:0 24px 80px rgba(20,20,28,.24); animation:editorIn .24s cubic-bezier(.2,.8,.2,1); }
  @keyframes editorIn { from { opacity:0; transform:translateY(12px) scale(.98); } to { opacity:1; transform:none; } }
  #editor h2 { margin:0 0 16px; font-size:20px; }
  #editor label { display:block; color:var(--muted); font-size:12px; margin:12px 0 5px; }
  #editor textarea { width:100%; min-height:90px; resize:vertical; font:inherit; padding:9px 10px;
    border:1px solid var(--line); border-radius:9px; color:var(--text); }
  #editor .actions { display:flex; justify-content:flex-end; gap:8px; margin-top:18px; }
  #toast { position:fixed; right:22px; bottom:22px; width:min(380px,calc(100vw - 32px));
    display:flex; flex-direction:column-reverse; gap:8px; pointer-events:none; z-index:40; }
  .toast-item { color:#fff; padding:13px 16px; border-radius:14px; box-shadow:0 16px 48px rgba(20,20,28,.22);
    font-size:14px; opacity:0; transform:translate3d(18px,10px,0) scale(.98);
    animation:toastIn .32s cubic-bezier(.2,.8,.2,1) forwards; pointer-events:auto; }
  .toast-item.info { background:rgba(32,32,39,.96); }
  .toast-item.err { background:rgba(146,35,48,.97); }
  .toast-item.ok { background:rgba(31,101,59,.97); }
  @keyframes toastIn { to { opacity:1; transform:none; } }
  .reminder-fields { display:grid; grid-template-columns:170px 190px; gap:8px; margin-top:8px; }
  input[type=datetime-local], select {
    font: inherit; padding: 7px 10px; border: 1px solid var(--line);
    border-radius: 9px; background: #fff; color: var(--text); width:100%;
  }
  @media (max-width:620px) { .reminder-fields { grid-template-columns:1fr; } }
  /* ===== 子待办：任务行里的清单 + 行程（时间 / 提醒）===== */
  .sub-list { margin-top: 8px; }
  .sub-item { display: flex; align-items: flex-start; gap: 8px; padding: 4px 0; font-size: 13px; border-top: 1px dashed var(--line); }
  .sub-item:first-child { border-top: none; }
  .sub-item input[type=checkbox] { width: 16px; height: 16px; margin-top: 1px; flex: none; }
  .sub-item .sub-title { flex: 1; min-width: 0; word-break: break-word; }
  .sub-item .sub-time { flex: none; color: var(--muted); font-variant-numeric: tabular-nums; }
  .sub-item .sub-hint { flex: none; color: var(--muted); font-size: 12px; }
  .sub-item.done .sub-title { color: var(--muted); text-decoration: line-through; }
  .sub-item.ongoing .sub-title, .sub-item.ongoing .sub-time { color: #0a84ff; font-weight: 600; }
  .sub-item.missed .sub-title, .sub-item.missed .sub-time { color: var(--danger); }
  .sub-item .sub-state { flex: none; font-size: 12px; }
  /* ===== 编辑器里的子待办行 ===== */
  #editSubtasks { margin-top: 6px; }
  #editSubtasks .sub-row { border: 1px solid var(--line); border-radius: 12px; padding: 10px; margin-bottom: 8px; background: #fcfcfe; }
  #editSubtasks .sub-row-head { display: flex; align-items: center; gap: 8px; }
  #editSubtasks .sub-row-head input[type=checkbox] { width: 18px; height: 18px; flex: none; accent-color: var(--accent); }
  #editSubtasks .sub-row-head input[type=text] { flex: 1; min-width: 0; }
  #editSubtasks .sub-row-times { display: grid; grid-template-columns: repeat(2, minmax(0,1fr)) 130px; gap: 8px; margin-top: 8px; }
  #editSubtasks .sub-row-times label { display: block; color: var(--muted); font-size: 12px; margin-bottom: 4px; }
  #editSubtasks .sub-row-hint { margin-top: 6px; font-size: 12px; color: var(--muted); }
  #editSubtasks .empty { font-size: 13px; color: var(--muted); padding: 4px 0 8px; }
  #editSubtasks .add-row { margin-top: 2px; }
  @media (max-width:620px) { #editSubtasks .sub-row-times { grid-template-columns:1fr; } }
  #pair {
    position: fixed; inset: 0; background: var(--bg); z-index: 30;
    display: flex; align-items: center; justify-content: center;
  }
  #pair .box { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 24px; width: 320px; text-align: center; }
  #pair h2 { margin: 0 0 6px; font-size: 18px; color: var(--text); }
  #pair p { font-size: 13px; color: var(--muted); margin: 0 0 16px; }
  #pair input { text-align: center; font-size: 22px; letter-spacing: 6px; margin-bottom: 12px; }
  .hidden { display: none !important; }
</style>
</head>
<body>

<div id="pair">
  <div class="box">
    <h2>输入配对码</h2>
    <p>配对码显示在手机的「局域网同步」页面上</p>
    <input id="codeInput" type="text" inputmode="numeric" maxlength="6" placeholder="000000" autocomplete="off">
    <div id="pairErr" class="hint" style="color:var(--danger); min-height:18px;"></div>
    <button class="primary" style="width:100%; padding:10px;" onclick="pair()">连接</button>
  </div>
</div>

<header>
  <h1>Elychron</h1>
  <span id="status" class="pill">未连接</span>
  <span style="flex:1"></span>
  <input id="searchInput" type="text" placeholder="搜索待办…" style="max-width:220px" oninput="render()">
  <button onclick="refresh()">刷新</button>
  <button onclick="downloadBundle()">导出到电脑</button>
</header>

<main>
  <div class="card">
    <h2>新建待办</h2>
    <div class="grid">
      <input id="newTitle" type="text" placeholder="要做的事…">
      <input id="newEnd" type="date">
      <button class="primary" onclick="addTask()">添加</button>
    </div>
    <label for="newDescription">描述（可选）</label>
    <textarea id="newDescription" style="width:100%; min-height:58px; resize:vertical; font:inherit; padding:8px; border:1px solid var(--line); border-radius:9px"></textarea>
    <div class="reminder-fields">
      <label class="hint"><input id="newReminderEnabled" type="checkbox"> 开启提醒</label>
      <input id="newReminder" type="datetime-local" aria-label="提醒时间">
    </div>
    <div class="hint" style="margin-top:8px;">截止时间默认今天 23:59；提醒时间可选，保存后由手机负责实际通知。</div>
    <button style="margin-top:10px" onclick="enableBrowserReminders()">开启电脑提醒</button>
  </div>

  <div class="card">
    <div class="workbar">
      <div><h2 style="margin:0">任务</h2><div class="hint">把今天要做的事放在眼前</div></div>
      <div class="tabs" role="tablist">
        <button class="tab active" data-filter="open" onclick="setTaskFilter('open')">待我处理 <span id="countOpen" class="pill">0</span></button>
        <button class="tab" data-filter="priority" onclick="setTaskFilter('priority')">优先处理</button>
        <button class="tab" data-filter="done" onclick="setTaskFilter('done')">我已处理 <span id="countDone" class="pill">0</span></button>
        <button class="tab" data-filter="starred" onclick="setTaskFilter('starred')">星标</button>
      </div>
    </div>
    <div id="taskList"><div class="hint">加载中…</div></div>
  </div>

  <div class="card">
    <h2>导入电脑上的备份</h2>
    <input id="importFile" type="file" accept="application/json,.json" onchange="importBundle(this)">
    <div class="hint" style="margin-top:8px;">
      按 uid + 更新时间合并，不会覆盖较新的数据；删除会记墓碑，能在手机之间正确传播。
    </div>
  </div>
</main>

<div id="toast"></div>
<div id="editor" class="hidden">
  <div class="box">
    <h2 id="editorTitle">编辑待办</h2>
    <label for="editSummary">标题</label><input id="editSummary" type="text">
    <label for="editDescription">描述</label><textarea id="editDescription"></textarea>
    <label for="editLocation">地点</label><input id="editLocation" type="text">
    <label for="editPriority">优先级</label>
    <select id="editPriority"><option value="low">低</option><option value="normal">普通</option><option value="high">高</option><option value="urgent">紧急</option></select>
    <label><input id="editStarred" type="checkbox"> 加入星标</label>
    <label><input id="editReminderEnabled" type="checkbox"> 开启提醒</label>
    <label for="editReminder">提醒时间</label><input id="editReminder" type="datetime-local">
    <label for="editRepeatType">重复</label>
    <select id="editRepeatType"><option value="norepeat">不重复</option><option value="daily">每天</option><option value="weekly">每周</option><option value="monthly">每月</option></select>
    <label for="editTags">标签（用逗号分隔）</label><input id="editTags" type="text">
    <label>子待办</label>
    <div id="editSubtasks"></div>
    <button type="button" class="add-row" onclick="addSubtaskRow()">+ 添加步骤</button>
    <div class="hint">每一步都能单独设开始 / 结束时间、完成状态和提前提醒分钟数；提前量留空表示沿用设置里的默认值。没有时间的步骤就是普通清单项。</div>
    <div class="actions"><button onclick="closeEditor()">取消</button><button class="primary" onclick="saveEditor()">保存修改</button></div>
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
      (ongoing ? '<span class="sub-state" style="color:#0a84ff">进行中</span>'
        : (missed ? '<span class="sub-state" style="color:var(--danger)">已超时</span>' : '')) +
      '</div>';
  });
  return '<div class="sub-list">' + lines.join('') + '</div>';
}

function renderRow(t) {
  var done = t.status === 'completed';
  var meta = [];
  meta.push('<span>' + (done ? '已完成' : '截止 ') + esc(fmt(t.endTime)) + '</span>');
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
    ? shown.map(renderRow).join('') : '<div class="hint">这里还没有任务 🎉</div>';
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
