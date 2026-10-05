# 图书馆空间预约 —— 实现规格（自包含）

> 目的：**任何新窗口（新会话 / 空窗口子代理）读完这一份就能接手**，不需要继承整段对话。
> 上游侦察细节在 `docs/CAMPUS_SERVICES_PLAN.md` 第三、四节。

## 一、站点与可达性（2026-10-01 实测）
- 宿主 `https://booking.lib.zju.edu.cn/h5/`（浙大图书馆空间预约），**校外可达** ✓
- `m.lib.zju.edu.cn`（手机版图书馆）校外超时；`opac.zju.edu.cn` 校外 403（官方"暂停对公网服务"）→ 那两个要 WebVPN，暂不做。
- 接口全在 `/api/...`，全部 **POST + JSON**。

## 二、两个致命事实（别回退）
1. **凭据只在那个 WebView 页面里成立**：Dart 侧另起 HttpClient 带 token 请求，必被判
   `code=10001 您尚未登录`（服务端把它当"另一台设备"）。**所有数据必须用页面内同源 fetch 取**。
2. **每新建一个 WebView，`sessionStorage` 都是空的**：上一次登录的 token 不跟过来；
   `onPageFinished` 之后要**等页面自己把 token 写回来**（实测 1~2 秒，写入 735 字符）再发请求，
   否则必失败。日志证据：`图书馆会话：首页已就绪` → `等到的 token 长度=735`。
- 另：这站是**单设备登录** —— 在浏览器/微信再登一次，App 这边会被顶掉，服务端原话
  「请注意,您的账号在其他设备登录！」。界面要**原样透出**这句话，别改写成"登录已失效"。

## 三、接口清单（用到的）
| 用途 | 路径 | 形状 |
|---|---|---|
| 我是谁 | `POST /api/Member/my` | `{code, data:{name,id,...}}` |
| 座位预约 | `POST /api/Member/seat` | `{code, data:[…]}`（数组）|
| 研讨间 | `POST /api/Member/room` | `{code, data:[…]}`（数组）|
| 活动/研讨间 | `POST /api/Member/seminar` | `{code, data:{total,…,data:[…]}}`（**分页对象**）|
| 公告 | `POST /api/index/notice` | `{code, data:{…,data:[…]}}`（免登录）|

**每条预约的字段**（真数据）：`id` / `title` / `nameMerge`（地点）/ `beginTime` / `endTime` /
`statusname`（"已使用"等）/ `timelist`（6 个小时段 —— **不是**新预约！盲目递归会把它算成预约，
真机上曾显示"7 条预约" = 1+6）。

## 四、文件分工
- `lib/http/library_spider.dart`：纯解析（`LibraryReservation` 含 `id`、`reservationsFrom` 分层精确解析、`looksLikeInClass` 之外的东西不在这里）+ `libraryTrace()`。
- `lib/mod/library_web_session.dart`：**常驻隐藏 WebView 会话**（单例；`hasWebViewLogin` 守卫；
  `ensureReady()` 等 token 恢复；`postJson()` 页面内 fetch + 轮询 `window.__ely`；`reset()`）。
- `lib/mod/library_login_page.dart`：内置浏览器登录页；登录成功后把 controller/token 交接给会话。
- `lib/mod/library_tasks.dart`：预约 → 待办（`uid = "lib-<id>"` 保证反复同步不重复；
  `startTime = beginTime`、`endTime = endTime`；`tags=["图书馆"]`；**只增不删**）。
- `lib/mod/library_settings_page.dart`：状态卡 / 我的预约 / 同步到待办 / 登录。
- `lib/mod/library_config.dart` + `database_helper.dart`：enabled / token / lastResult / lastName / lastCount（全部 optionsBox）。
- `lib/main.dart`：启动 20 秒后静默 `ensureReady() + syncLibraryReservations()`（仅 enabled，全程 try/catch）。

## 五、验收标准（要做成什么样）
1. 启动约 20 秒后（无需用户操作）待办里出现图书馆预约，**起止时间正确**、高优先级、各**只一条**；
2. 再同步一次显示"**更新 N**"而不是新增 —— 证明 `uid` 去重有效；
3. 失败（被顶掉 / 网络不好）**绝不动**已有待办，界面显示服务端原话；
4. 设置页：状态卡（已连接 · 姓名 · N 条预约）+ 预约列表（标题·地点 / 起止 / 状态）+ 同步行 + 登录区，脚注 1~2 句。

## 六、怎么验（真机）
```
adb mdns services                 # 现查手机 IP
adb connect <IP>:5555
adb logcat -c                     # 先清，再操作
# 操作后：
adb logcat -d | Select-String Elychron     # 看 libraryTrace 的痕迹
```
构建与装机（注意必须看到 `√ Built`）见 `AGENTS.md` 第二节。
