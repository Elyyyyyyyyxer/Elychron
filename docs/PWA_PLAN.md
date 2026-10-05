# PWA（iPhone / 网页版）实施计划

> 目标：给 iPhone（以及所有能"装到桌面"的设备）一个**完整可用**的 Elychron。
> 原则：**PWA 做不到的功能直接砍掉**，不硬撑；保留的核心功能要做扎实。
> 目录：新开 `pwa/` 作为 PWA 的**独立代码库**，与 App（Flutter）并存、互不干扰。

## 一、放在哪里（现状）

| 东西 | 位置 | 线上 |
|---|---|---|
| 官网 + 现在的 PWA 外壳 | `site/`（index.html / style.css / manifest.webmanifest / sw.js / icon*.png / functions/api/proxy.js） | https://elychron.pages.dev |
| PWA 应用（**待建**） | `pwa/`（新目录） | 计划 `elychron-app.pages.dev`（独立 Pages 项目，自带 functions/api/proxy.js） |
| 同源代理 | `site/functions/api/proxy.js`（已写）；PWA 项目里再放一份 | 挂在各自 pages.dev 同域下，**不碰 workers.dev**（实测国内不可达） |
| 安装包 | `releases/Elychron-1.5.0-elychron.1-arm64.apk`（SHA256 `F2A1907E…CAC6`） | GitHub Releases |
| 计划文档 | `docs/PWA_PLAN.md`（本文件） | — |

## 二、技术选型（刻意保持轻）

- **Vite + TypeScript + Preact**（约 3 KB 运行时）+ 手写 CSS（沿用官网那套粉色/课表语言，不引 UI 框架）
- 本地存储：**IndexedDB**（idb-keyval）—— 与 App 的字段结构对齐，导出成同一份 JSON
- 同步：**自己写最小 WebDAV 客户端**（PROPFIND / PUT / MKCOL），不引大依赖；把用户选中的网盘当唯一后端
- 路由：History API；PWA：manifest + service worker（预缓存外壳；数据在 IndexedDB）
- 校园数据：一律走**同源代理**（`/api/proxy?u=…`），浏览器不与校园站直接跨域

## 三、保留什么（PWA 能做，且要做扎实）

1. **课表**：周视图、当前节次、按周切换；从教务/学在浙大导入
2. **待办**：四种时间语义（活动/截止/提醒/备忘）、自由时间逻辑、子待办与行程、标签
3. **作业与预约自动进待办**：学在浙大作业、PTA 题目集、图书馆预约（带起止时间）
4. **专注计时**：前台计时 + 统计（今天/本周/本月）
5. **AI 助手**：用你自己的 Key；文本 + 图片（多模态）交给模型；一键把一段通知整理成待办
6. **多端同步**：WebDAV（坚果云/InfiniCloud/Koofr/Nextcloud/群晖/Alist），加**导出/导入 JSON**
7. **校园只读**：教务课表成绩、学在浙大、PTA、图书馆预约、素拓、研究生院
8. **离线可用**：装成 PWA 后断网也能看课表/待办（外壳 + IndexedDB 缓存）

## 四、砍掉什么（PWA 做不到，明确不做）

| 砍掉 | 原因 |
|---|---|
| 可靠的后台刷新（WorkManager 那套） | 浏览器没有可靠的周期后台任务；改为"打开时同步一次" |
| 系统级通知的可靠性 | iOS 只有在"装成 PWA + 16.4+"下才有 Web Push，且仍是尽力而为；降级为**应用内提醒**（打开时补播） |
| 桌面小组件（Widget） | PWA 无此能力 |
| 写入系统日历 | PWA 不能写系统日历（只能导出 .ics 让用户手动导入） |
| 局域网同步（手机当服务器） | 浏览器无法监听端口；只保留 WebDAV |
| 内置浏览器登录（WebView） | web 无 WebView；改为"经同源代理登录"或"粘贴令牌" |
| 附件挂到系统文件/分享 | 降级为 IndexedDB 附件 + 链接；导出时打包 |

## 五、关键决策（需要你拍板）

1. **凭据怎么放**（最重要）：
   - (a) 用户在网页里输入教务账号密码 → 经**同源代理**登录 → 会话 Cookie 只存在浏览器里，代理不落盘 ✓ 体验最好
   - (b) 粘贴 Cookie / 令牌（像 PTA 那样）✓ 最安全但麻烦
   - (c) 只做导入导出，不做实时抓取 ✗ 功能会残
   推荐 **(a) 为主 + (b) 兜底**。
2. **部署形态**：PWA 独立 Pages 项目（`elychron-app.pages.dev`）还是并进现有站点（`/app/`）？推荐独立，互不影响。
3. **数据格式**：与 App 完全对齐（同一份 JSON），保证"手机 App ↔ 网页版"能互相导入导出。

## 六、里程碑

| 阶段 | 内容 | 产出 |
|---|---|---|
| **M0** | 脚手架：Vite+TS+Preact、路由、IndexedDB、manifest+SW、可安装 | 能装到 iPhone 桌面、能增删一条待办 |
| **M1** | 课表 + 待办（核心，工作量最大） | 与 App 等价的本地体验，离线可用 |
| **M2** | 同步：WebDAV + 导入导出 | 与 App 数据互通 |
| **M3** | 校园数据：代理接入（教务/学在浙大/PTA/图书馆/素拓/研究生院） | 作业与预约自动进待办 |
| **M4** | AI 助手（Key 存在浏览器本地） | 整理/拆解/多模态 |
| **M5** | 打磨与 iOS 实测（安全区、手势、深色、备份提醒） | 可日常使用 |

## 七、风险

- **iOS 存储会被清理**（长时间不用可能清 IndexedDB）→ 必须**引导备份**（导出 + 网盘同步），并在界面上提示
- **学校 WAF 可能拦数据中心 IP** → 已实测：Cloudflare 出口对 zjuam/PTA/图书馆均返回 200 ✓（`courses` 400 是缺参数/cookie，不是被拦）
- **登录态单设备**（图书馆那类）→ web 与 App 同时登录会互顶，界面要显示服务端原话
