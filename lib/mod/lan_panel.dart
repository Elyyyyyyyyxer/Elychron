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
    --bg: #f5f5f7; --card: #ffffff; --line: #e5e5ea;
    --text: #1c1c1e; --muted: #8e8e93; --accent: #007aff;
    --danger: #ff3b30; --ok: #34c759; --warn: #ff9500;
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
  .row { display: flex; align-items: flex-start; gap: 12px; padding: 10px 0; border-top: 1px solid var(--line); }
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
  #toast {
    position: fixed; left: 50%; bottom: 28px; transform: translateX(-50%);
    background: #1c1c1e; color: #fff; padding: 10px 18px; border-radius: 999px;
    font-size: 14px; opacity: 0; transition: opacity .25s; pointer-events: none; z-index: 20;
  }
  #toast.show { opacity: 1; }
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
    <div class="hint" style="margin-top:8px;">截止时间默认今天 23:59；新建后可回手机继续补充细节。</div>
  </div>

  <div class="card">
    <h2>进行中 <span id="countOpen" class="pill">0</span></h2>
    <div id="openList"><div class="hint">加载中…</div></div>
  </div>

  <div class="card">
    <h2>已完成 <span id="countDone" class="pill">0</span></h2>
    <div id="doneList"><div class="hint">—</div></div>
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

<script>
// 旧版这个 key 叫 telechron_token：读得到就顺手迁移，免得用户重新配对一次
var token = localStorage.getItem('elychron_token') || localStorage.getItem('telechron_token') || '';
if (token) { localStorage.setItem('elychron_token', token); localStorage.removeItem('telechron_token'); }
var bundle = null;

function toast(msg) {
  var el = document.getElementById('toast');
  el.textContent = msg; el.classList.add('show');
  setTimeout(function () { el.classList.remove('show'); }, 2600);
}
function setStatus(text, kind) {
  var el = document.getElementById('status');
  el.textContent = text;
  el.className = 'pill' + (kind ? ' ' + kind : '');
}
function api(path, options) {
  options = options || {};
  options.headers = Object.assign({ 'X-Lan-Token': token }, options.headers || {});
  return fetch(path, options).then(function (res) {
    return res.json().then(function (data) {
      if (res.status === 401) { showPair('配对已失效，请重新输入配对码'); throw new Error(data.error || 'unauthorized'); }
      if (!res.ok) { throw new Error(data.error || ('HTTP ' + res.status)); }
      return data;
    });
  });
}
function showPair(msg) {
  document.getElementById('pair').classList.remove('hidden');
  document.getElementById('pairErr').textContent = msg || '';
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
  }).catch(function (e) { document.getElementById('pairErr').textContent = '' + e; });
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

function renderRow(t) {
  var done = t.status === 'completed';
  var meta = [];
  meta.push('<span>' + (done ? '已完成' : '截止 ') + esc(fmt(t.endTime)) + '</span>');
  if (t.location) meta.push('<span>📍' + esc(t.location) + '</span>');
  if (PRIO[t.priority]) meta.push('<span class="prio-' + t.priority + '">' + PRIO[t.priority] + '</span>');
  if (t.subtasks && t.subtasks.length) {
    var dn = t.subtasks.filter(function (s) { return s.done; }).length;
    meta.push('<span>子待办 ' + dn + '/' + t.subtasks.length + '</span>');
  }
  (t.tags || []).forEach(function (tag) { meta.push('<span class="tag">' + esc(tag) + '</span>'); });
  return '<div class="row">' +
    '<input type="checkbox" ' + (done ? 'checked' : '') + ' onchange="toggleDone(\'' + t.uid + '\', this.checked)">' +
    '<div class="body">' +
      '<div class="title' + (done ? ' done' : '') + '">' + esc(t.summary || '(无标题)') + '</div>' +
      '<div class="meta">' + meta.join('') + '</div>' +
      (t.description ? '<div class="meta">' + esc(t.description) + '</div>' : '') +
    '</div>' +
    '<button class="danger" onclick="removeTask(\'' + t.uid + '\')">删除</button>' +
  '</div>';
}

function render() {
  if (!bundle) return;
  var tasks = bundle.tasks || [];
  var open = tasks.filter(function (t) { return t.status !== 'completed' && t.status !== 'deleted'; });
  open.sort(function (a, b) { return (a.endTime || '').localeCompare(b.endTime || ''); });
  var done = tasks.filter(function (t) { return t.status === 'completed'; });
  document.getElementById('openList').innerHTML = open.length
    ? open.map(renderRow).join('') : '<div class="hint">没有进行中的待办 🎉</div>';
  document.getElementById('doneList').innerHTML = done.length
    ? done.map(renderRow).join('') : '<div class="hint">—</div>';
  document.getElementById('countOpen').textContent = open.length;
  document.getElementById('countDone').textContent = done.length;
}

function refresh() {
  setStatus('同步中…');
  api('/bundle').then(function (data) {
    bundle = data;
    render();
    setStatus('已连接 · ' + (data.tasks || []).length + ' 条待办', 'ok');
  }).catch(function (e) {
    if (('' + e).indexOf('unauthorized') < 0 && ('' + e).indexOf('配对') < 0) {
      setStatus('连接失败', 'err');
      toast('' + e);
    }
  });
}

function push(summary) {
  return api('/bundle', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(bundle)
  }).then(function (data) {
    toast((summary ? summary + '，' : '') + '已同步到手机：' + (data.summary || ''));
    return refresh();
  }).catch(function (e) { toast('同步失败：' + e); });
}

function findTask(uid) {
  for (var i = 0; i < bundle.tasks.length; i++) { if (bundle.tasks[i].uid === uid) return bundle.tasks[i]; }
  return null;
}
function toggleDone(uid, checked) {
  var t = findTask(uid);
  if (!t) return;
  t.status = checked ? 'completed' : 'running';
  t.updatedAt = new Date().toISOString();
  push(checked ? '已打钩' : '已取消完成');
}
function removeTask(uid) {
  var t = findTask(uid);
  if (!t || !confirm('删除「' + (t.summary || '') + '」？')) { render(); return; }
  t.status = 'deleted';
  t.updatedAt = new Date().toISOString();
  push('已删除');
}
function addTask() {
  var title = document.getElementById('newTitle').value.trim();
  if (!title) { toast('先写点什么'); return; }
  var dateStr = document.getElementById('newEnd').value;
  var end = dateStr ? new Date(dateStr + 'T23:59:00') : new Date(new Date().setHours(23, 59, 0, 0));
  var now = new Date().toISOString();
  var uid = (crypto.randomUUID ? crypto.randomUUID() : 'r' + Math.random().toString(36).slice(2) + Date.now());
  bundle.tasks.push({
    uid: uid, status: 'running', description: '', timeSpent: 0, timeNeeded: 3600,
    endTime: end.toISOString(), location: '', summary: title, isBreakable: false,
    type: 'deadline', startTime: end.toISOString(), repeatType: 'norepeat',
    repeatPeriod: 1, repeatEndsTime: end.toISOString(), blockArrangements: true,
    fromUid: null, subtasks: [], priority: 'normal', reminderEnabled: false,
    reminderTime: null, attachments: [], comments: [], tags: [], starred: false,
    createdAt: now, updatedAt: now
  });
  document.getElementById('newTitle').value = '';
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
if (token) { refresh(); } else { showPair(); }
</script>
</body>
</html>
''';
