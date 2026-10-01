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
