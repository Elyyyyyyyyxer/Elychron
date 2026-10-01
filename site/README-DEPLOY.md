# 官网部署说明（Cloudflare Pages）

这个文件夹就是完整的官网：**纯静态**，两个文件，没有构建步骤，没有第三方脚本（不引 CDN 字体、不装统计 —— 和"不收集数据"保持一致）。

- `index.html` —— 页面
- `style.css` —— 样式（含深色模式）

---

## 一、先注册 Cloudflare（一次性）

1. 打开 <https://dash.cloudflare.com/sign-up>，用邮箱 + 密码注册，去邮箱点验证链接。
2. 登录后左侧找 **Workers & Pages**（新界面可能叫 **Compute (Workers)** → 里面再选 Pages）。
3. 不需要绑定信用卡 —— 静态托管和 Pages 的免费额度就够个人用。

## 二、部署方式 A：直接上传（最快，5 分钟）

1. **Workers & Pages** → **Create** → 选 **Pages** → **Upload assets**。
2. **Project name** 填 `elychron`（最终网址就是 `https://elychron.pages.dev`）。
3. 把本文件夹里的 `index.html`、`style.css` **直接拖进**上传框（拖文件夹也行，注意别多套一层目录）。
4. 点 **Deploy site**，几秒后得到 `https://elychron.pages.dev`。
5. **以后怎么更新**：进这个项目 → **Create new deployment** → 重新拖文件 → Deploy。
   （内容是缓存过的，浏览器强刷一下 `Ctrl+F5` 就能看到新版。）

## 三、部署方式 B：接 GitHub 仓库（推荐长期用，push 自动部署）

1. 先把本文件夹放进仓库（建议路径 `site/`），push。
2. Cloudflare：**Workers & Pages** → **Create** → **Pages** → **Connect to Git** → 授权 GitHub →
   选中你的仓库（**私有仓库也可以**，网站照样是公开的）。
3. 构建设置（关键，别填错）：
   - **Framework preset**：`None`
   - **Build command**：**留空**
   - **Build output directory**：`site`
4. **Save and Deploy**。之后每次往仓库 push，Cloudflare 会自动重新部署。

> 命令行党也可以：`npx wrangler pages deploy site --project-name elychron`

## 四、自定义域名（可选，要花钱）

Pages 项目 → **Custom domains** → **Set up a domain** → 填你的域名 → 按提示在域名商那里加一条 CNAME 指向 `<项目名>.pages.dev`，证书自动签发。

## 五、免费额度与限制（个人项目足够）

| 项目 | 免费额度 |
|---|---|
| 站点数量 | 不限 |
| 每月构建次数 | 500 次 |
| 单文件大小 | **上限 25 MiB** ← 注意 |
| 流量 | 静态资源不计费 |
| HTTPS 证书 | 自动 |

⚠️ **安装包别放这里**：我们的 APK 是 28.5 MB，**超过 25 MiB 上限**。所以下载按钮指向 GitHub Releases（或 Gitee Releases），不要把 APK 拖进本文件夹。

## 六、几个容易踩的坑

- **Pages 是公开的**：别把凭据、含个人信息的截图、未脱敏的日志放进 `site/`。
- 上传时**别多套一层文件夹**（要让 `index.html` 在部署根目录，否则打开是文件列表 / 404）。
- 想改内容就直接改这两个文件，本地双击 `index.html` 就能预览（不需要服务器）。
- 以后要加**代理**（Worker）是另一个产品：`Workers & Pages` → **Create** → **Workers**，和这个静态站点互不影响。
