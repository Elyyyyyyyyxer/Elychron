# 校园服务：调研与布局规划（2026-09-30）

> 用户拍板：**AED 地图砍掉**（"做的很烂，不想动"）；先做**紧急通讯录**与**图书馆**的规划。
> 本页只记调研结果与方案，不含实现。

## 一、紧急通讯录（零风险，可先做）

**页面结构已完全摸清**（`mapp.zju.edu.cn/lightapp/jjdh/`，是老式 RequireJS 应用）：

```
/app/home.html          ← 壳，只负责渲染
/app/home.main.js       ← 启动
/app/controller/apis.js ← **接口定义**（关键）
```

`controller/apis.js` 原文（节选）：

```js
pageListAPI: { type: "GET", url: "../apis/pageList.js", dataType: "json" },
detailAPI:   { type: "GET", url: "../apis/detail.js",   dataType: "json" },
// 注释里还留着真实后端：210.32.159.215/lightapp/lightapp/getDepartmentList
```

**结论：数据是静态 JSON，不需要登录、不需要 ticket。**

- `http://mapp.zju.edu.cn/lightapp/jjdh/www/apis/pageList.js`（部门/分类列表）
- `http://mapp.zju.edu.cn/lightapp/jjdh/www/apis/detail.js`（各单位的电话明细）
- ⚠️ 主机解析到 **内网 10.203.3.215**：**校园网/校外 VPN 才能访问**。
  所以做法应该是"**拉一次存成随包资源**"（离线可用、校外也能看），
  外加一个"更新数据"按钮（需要在校内网时点）。

**实现（很小）**：
1. 拉两个 JSON → 清洗 → 存成 `assets/campus/emergency.json`（随包，离线可用）；
2. UI：设置 → 校园服务 → 紧急电话；顶部**搜索框**（按单位/电话），列表分组；
3. 点一下 = `tel:` 跳系统拨号（Flutter 侧 `url_launcher` 的 `tel:`）——
   这正是用户说的"点击甚至能直接跳转手机通讯录"；
4. 再加一个**安卓长按图标快捷方式**（App Shortcuts → 直接进紧急电话），紧急时才不用翻三层。

## 二、图书馆（`m.lib.zju.edu.cn`）

**站点结构**：Vue CLI 单页应用（`/static/js/chunk-vendors.*.js` + `/static/js/index.*.js`），
主机解析到 **内网 10.203.97.164**（同样校园网/VPN）。

从 `index.js` 里挖出来的**接口键名**（值在打包文件里，需要时再取）：

| 键 | 大概是 |
|---|---|
| `apiurl` / `zdapiurl` | 接口根地址（两个后端） |
| `apiauth` / `uniloginurl` / `loginurl` | **鉴权与登录入口**（校园统一身份 / iportal ticket） |
| `zddgetseat` | 座位查询（有没有空位） |
| `apiorder` / `apicancleorder` | **预约 / 取消预约**（写操作） |
| `apiborinfo` / `apiborhis` / `apiupdatebor` / `apirenew` | 借阅信息 / 历史 / 续借 |
| `apifind` / `apisort` / `apipresent` / `apidocshort` / `apidocitem` / `apiitemorder` / `apiitemplace` | 馆藏检索、文献预约之类 |

打包里的页面路由：`/pages/index/index`、`/pages/gccx`（馆藏查询）、`/pages/dzfw`（读者服务）、
`/pages/qsjs`、`/pages/wechat/auth`、`/pages/ding` ——
**auth 页走的是微信/钉钉授权**，说明它期望"从微信/钉钉里进"（iportal 的 lightapp 也是这个路数）。

用户给的那个链接里带着 `ticket=ST-xxx` + 一堆 `iportal.*` 参数 ——
这就是 **iportal 的免密单点登录**：门户给每个 lightapp 发一张 ticket，
应用拿 ticket 换会话。**这是唯一"不碰用户密码"的路子。**

### 分三期（先读后写）

**P1｜只读信息（推荐先做）**
- 在 App 内用 **WebView 打开 iportal 的那个入口链接**（用户已登录 iportal 时会自动带 ticket），
  或者让用户粘贴一次入口链接；
- 从页面/接口里取：**当前借阅、到期时间、已有预约**；
- 落成：**"《XX》还书截止 YYYY-MM-DD"自动变成待办**（这才是它属于 Elychron 的理由）；
- 权限：只读、低频（每次进页面手动刷新，不做后台轮询）。

**P2｜座位查询（只读）**
- `zddgetseat` 取空位 → 显示"现在哪里还有座"；
- 仍然**不写**，只是让你少开一次网页。

**P3｜预约座位（写，最后做，且要谨慎）**
- `apiorder` 是**真实占座**：必须
  二次确认 + 明说"约了哪个馆、哪个时段" + 失败要如实报（不能"以为约上了"）；
- 这一层最容易踩坑（频控、被风控、取消不及时导致违规），所以放最后、且默认关闭。

### 风险与红线（写进实现前的检查表）

1. **不能存明文密码**：能用 iportal ticket 就绝不做账号密码登录；
   （项目已有系统密钥库设施，见 webdav/AI key 的做法。）
2. **不能把 ticket 写进仓库/日志**：ticket 是临时凭证，任何时候不进代码、不进文档、不进提交。
3. **校外不可达**：两个主机都是内网地址；要么走学校 VPN，要么只做"校内可用 + 数据随包"。
4. **接口是内部接口**：字段和路径随时可能变，所以解析要**容错 + 失败只提示不崩**。
5. **频控**：默认手动触发，绝不做高频轮询（这正是坚果云 503 的教训）。

## 三、布局规划（功能放哪）

```
设置
└── 校园服务（二级页，一个入口，一屏列完）
    ├── 紧急电话        ← 静态数据 + tel: + 搜索（**安卓还挂长按图标快捷方式**）
    └── 图书馆          ← 登录/授权一次 → 借阅到期 → 一键变待办（P1）
                        └ 座位空位查询（P2）→ 预约（P3，默认关）
```

- **主页四个标签不动**：这些是"偶尔用一次"的工具，塞进主导航只会让主界面变脏；
- 唯一值得"出门"的是**紧急电话**：给它一个 App Shortcut（长按图标直达），紧急时最省事；
- 图书馆产出的待办走现有待办体系（不新建概念）。

---

## 三、校外可达性实测（2026-10-01，用户在家里 / 手机热点上）

上次是在校内测的，这次在校外重测了一遍，结论差别很大：

| 主机 | 校外 443 | 说明 |
|---|---|---|
| `m.lib.zju.edu.cn`（手机版 SPA，接口键名见第二节） | ❌ 超时 | DNS 给的是公网 210.32.13.173，但防火墙只放校网/VPN |
| `libweb.zju.edu.cn`（电脑版门户，webplus CMS） | ✅ 200 | 只是一堆链接，本身没数据 |
| `opac.zju.edu.cn`（馆藏/我的借阅） | ⛔ 403 | **官方公告：图书馆OPAC网站因故暂停对公网服务**（原文见下），校外只给 WebVPN 或浙大钉 |
| `booking.lib.zju.edu.cn/h5/`（**图书馆空间预约系统**） | ✅ **200** | **Vue H5，接口全在这儿，校外直接用** |
| `webvpn.zju.edu.cn` | ✅ 302 | 校外访问网关 |

OPAC 403 页面原文（存证）：

> 图书馆OPAC网站因故暂停对公网服务。本校师生如有在校外查询馆藏、预约图书、续借图书的需要，
> 可通过以下方法使用：方法一：登录Web VPN后访问……方法二：通过移动图书馆访问（浙大钉 → 工作台 → 浙大生活 → 图书馆）。

所以**"借阅到期 → 待办"这条只读需求，校外被官方堵死**；要么 WebVPN，要么浙大钉的 ticket。

## 四、图书馆空间预约系统（校外可达，值得做）

`https://booking.lib.zju.edu.cn/h5/` —— Vue 3 + Element Plus，axios `baseURL:"/"`，
全部接口都是 **POST + JSON**，路径在 `/api/...`。共挖到 **63 个**接口（正则
`url:"(/api/...)",method:"..."` 从 `assets/index.*.js` 里提取）。

**免登录就能读的**（实测 200）：

```
POST /api/index/notice     公告列表（实测 13 条，带标题/时间）
POST /api/index/banner     首页横幅
POST /api/index/time       服务器时间
POST /api/index/config     系统配置 —— 但 data 是**加密串**，客户端解密后才用
```

**要登录的**（实测返回 `{"code":10001,"msg":"您尚未登录"}`）：

```
座位：  /api/Seat/tree  /api/Seat/seat  /api/Seat/date  /api/seat/map  /api/seat/label
自习区：/api/Study/libinfo  /api/Study/StudyArea  /api/Study/StudyOpenTime
研讨间：/api/Room/list  /api/Room/detail  /api/Seminar/*
我的：  /api/Member/my  /api/Member/seat  /api/Member/room  /api/Member/seminar
```

**登录方式（关键）**：

- **CAS 统一身份**（推荐）：`POST /api/cas/user`，请求体 `{cas: "<CAS ticket ST-xxx>"}`
  → 返回 `{code:1, member:{token:...}}`，之后 token 随请求走。
  这条**不在加密名单里**（见下），是明文 JSON —— 我们 App 已经有 zjuam 那套 CAS 代码，
  理论上可以**复用教务账号免密登录**，而且校外可用。
- 账号密码：`POST /api/login/login`（+ `/api/Captcha/verify`）。注意 axios 拦截器里有一份
  **加密名单**（`/api/login/login`、`/api/Seat/confirm`、`/api/Seminar/confirm` …），
  这些接口的 body 会被包成 `{aesjson: encrypt(...)}` —— 也就是**密码登录要自己实现前端那套
  AES 加密 + 处理验证码**，比 CAS 麻烦得多，不推荐。
- 还有 `/api/login/wxlogin`、`/api/login/dingtalksns`、`/api/login/wxwork`（微信/钉钉）。

**还差一步**：CAS 的 `service` 值（售票口）没在 bundle 里写死 —— `toLogin()` 只是
`location.hash="#/login"`，登录页是懒加载 chunk，或者 CAS 入口 URL 藏在**加密的
`/api/index/config`** 里。下一步用真浏览器打开 `#/login` 点一下"统一身份认证"，
把跳转链抓下来就能确定（不需要账号密码）。

**能变成什么功能**（和"借阅到期→待办"同一个价值，但校外能用）：
1. **我的预约 → 待办**（`/api/Member/seat|room|seminar`）：约了几点的座位/研讨间，到点提醒；
2. **座位查询（只读）**：`/api/Seat/tree` + `/api/Seat/seat`，"现在哪个馆还有座"；
3. 公告（`/api/index/notice`）当首页小卡片，几乎是白捡的。

### 4.1 登录链（2026-10-01 追完）

**前端加密**：axios 会把这些接口的 body 包成 `{aesjson: <base64>}`：
`/api/login/login`、`/api/Seat/confirm`、`/api/Seminar/confirm`、`/api/Enter/confirm`、
`/api/seat/qrcode`、`/api/login/updateUserInfo` …
加密方式：**AES-128-CBC/PKCS7**，IV = `ZZWBKJ_ZHIHUAWEI`，
密钥 = `exchangeDateTime(now,41)` × 2 = **当天 `YYYYMMDD` + 它的倒序**（16 字符）。

> 用这招把 `POST /api/index/config` 解密出来了（它返回的就是加密串）：
> `config.cas_url = https://booking.lib.zju.edu.cn/api/cas/cas`、
> `web.title = 浙江大学图书馆预约平台`、开放时间 `07:00~23:59`、
> 取消规则 `seatcancel=-30 / roomcancel=30`、功能开关若干。
> 想复现：`AES-128-CBC(key=20261001+"10016202", iv="ZZWBKJ_ZHIHUAWEI")`。

**CAS 链（实测跳转）**：

```
GET https://booking.lib.zju.edu.cn/api/cas/cas
  302 → http://zjuam.zju.edu.cn/cas/login?service=https%3A%2F%2Fbooking.lib.zju.edu.cn%2Fapi%2Fcas%2Fcas
        （同时下发 PHPSESSID）
```

即 **service = `https://booking.lib.zju.edu.cn/api/cas/cas`**（唯一没写死在前端、
要靠跳转才能看到的值，现在拿到了）。

带假 ticket 打回去是 `500 CAS Authentication failed!`（phpCAS 的味道），
说明**这个回调是服务端校验 ticket 并建立自己的会话**；另有一条
`POST /api/cas/user {cas: ticket}` → `{code:1, member:{token}}` 给 SPA 用
（假 ticket 返回 `code:0`）。

**两条登录路径**：
- **(A) 跟完整跳转链**（推荐）：我们 App 的 `ZjuAm` 已经会做 zjuam 的密码登录 →
  用它的 `getServiceCallback` 拿到带 ticket 的回调 URI →
  **立刻**用同一个 cookie jar GET 它 → 后端建立 PHPSESSID 会话 → 之后直接带 cookie 调 API。
  全程服务端，不需要前端那套 AES，也不需要验证码 ✓
- (B) 拿 ticket 去 `POST /api/cas/user` 换 `token` —— 前端那套，得自己保证 ticket 只被消费一次。

**能落成的功能**（校外可用）：
1. **我的预约 → 待办/日程**：`/api/Member/my|seat|room|seminar`（预约是**时段**，
   有开始也有结束 —— 比 PTA 的"只有截止时间"更该走 Task 的 startTime+endTime）；
2. **座位查询**：`/api/Seat/tree` + `/api/Seat/seat`（"哪个馆还有座"）；
3. 公告：`/api/index/notice`（免登录）。
