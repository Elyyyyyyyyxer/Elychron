/**
 * Elychron 的同源代理（Cloudflare Pages Function，路径 /api/proxy）
 *
 * 为什么要它：校园各站都不给浏览器放行（实测 zjuam / 预约系统 / PTA / 坚果云 WebDAV 都没有 CORS 头），
 * 所以网页版必须经由服务端转发。放在**同一个 pages.dev 域名**下的好处：
 *   · 没有跨域问题（同源）；
 *   · 不用碰 workers.dev（那个域名在国内不可达，实测 TCP 超时）；
 *   · 会话 cookie 由浏览器自然带上/带回，服务端不必存密码。
 *
 * 用法：POST /api/proxy?u=<encodeURIComponent(完整目标 URL)>
 *   · 只允许白名单里的主机（见 ALLOW）；
 *   · 除 host/content-length 外的请求头、请求体、状态码、响应头、Set-Cookie 全部透传；
 *   · 需要"从服务器发起登录"的场景（学校 CAS 跳转链）也能用：把每一跳的目标依次传进来即可。
 */
const ALLOW = [
  'zjuam.zju.edu.cn',
  'zdbk.zju.edu.cn',
  'courses.zju.edu.cn',
  'pintia.cn',
  'passport.pintia.cn',
  'booking.lib.zju.edu.cn',
  'sztz.zju.edu.cn',
  'yjsy.zju.edu.cn',
  'dav.jianguoyun.com',
];

export async function onRequest(context) {
  const { request } = context;
  const target = new URL(request.url).searchParams.get('u');
  if (!target) return json({ error: 'missing ?u=<target url>' }, 400);

  let url;
  try { url = new URL(target); } catch { return json({ error: 'bad url' }, 400); }
  if (url.protocol !== 'https:') return json({ error: 'https only' }, 400);
  if (!ALLOW.some((h) => url.hostname === h || url.hostname.endsWith('.' + h))) {
    return json({ error: 'host not allowed: ' + url.hostname }, 403);
  }

  // 透传请求头（去掉会破坏转发的几个），并把 cookie 一并带上
  const headers = new Headers(request.headers);
  for (const h of ['host', 'content-length', 'cf-connecting-ip', 'cf-ray', 'cf-ipcountry']) headers.delete(h);
  headers.set('origin', url.origin);
  headers.set('referer', url.origin + '/');

  const init = { method: request.method, headers, redirect: 'manual' };
  if (request.method !== 'GET' && request.method !== 'HEAD') init.body = await request.arrayBuffer();

  let upstream;
  try {
    upstream = await fetch(url.toString(), init);
  } catch (e) {
    return json({ error: 'upstream failed: ' + String(e) }, 502);
  }

  const out = new Headers(upstream.headers);
  out.delete('content-encoding');   // 交给运行时重新处理
  out.delete('content-length');
  out.set('x-elychron-proxy', url.hostname);
  return new Response(upstream.body, { status: upstream.status, headers: out });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json; charset=utf-8' } });
}
