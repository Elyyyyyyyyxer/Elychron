# PTA（拼题A / pintia.cn）作业读取 —— 侦察笔记

> 2026-10-01 侦察。对应上游 issue [#122](https://github.com/Celechron/Celechron/issues/122)，
> 那份 checklist 是：登录逻辑 / 作业抓取接口 / 把作业 todo 放进 ugrs_spider 一起抓 /
> 数据库与缓存 / 处理验证码。下面按这几条给结论。**本文件只是侦察，还没写实现。**

## 一、结论速览

| 问题 | 结论 |
|---|---|
| 接口公开吗 | 是。`pintia.cn/api/*` 可直接用，不需要模拟浏览器签名（实测 200）|
| 需要认证吗 | 需要。没有 cookie 时 `GET /api/problem-sets` 返回 `404 USER_NOT_FOUND` |
| 认证方式 | ① `PTASession` cookie；② 学号+姓名+密码（`/api/student-users/sessions`，**没有验证码**）；③ 邮箱/手机号+密码（`/api/users/sessions`，**要过腾讯验证码**）；④ 微信扫码（TokenLogin）|
| App 里最省事的做法 | **粘贴 `PTASession` cookie**（和开源社区做法一致），或试 ②（无验证码，可自动登录）|
| 数据够不够做待办 | 够。题目集自带 `startAt` / `endAt`（截止时间）与 `status`；每个题集里还能取到「考试/作业」的起止时间与未完成标志 |
| 主要风险 | cookie 会过期（要再粘一次）；登录接口有验证码/MFA；有 412/403 风控返回 |

## 二、接口清单（已实测可达）

主机：`https://pintia.cn`（业务）、`https://passport.pintia.cn`（身份）。
统一带 `Cookie: PTASession=<值>` 即可（见 vscode-pintia 的 ptaCookieAuthProvider）。

### 1. 我的题目集（作业的来源，含截止时间）

```
GET https://pintia.cn/api/problem-sets?filter={"endAtAfter":"<ISO8601>"}
→ { problemSets: [ { id, name, type, timeType, status, organizationName,
                     ownerNickname, startAt, endAt, duration, ... } ] }
```

- `filter` 用 `endAtAfter` 就相当于「还没截止的」；要全部就给 `{}`。
- `endAt` 就是**截止时间**；`organizationName` 是开课单位/课程名。
- ⚠️ 实测：不带 cookie 会被判成 `USER_NOT_FOUND`（404），不是 401。

### 2. 某个题目集里的「考试/作业」

```
GET https://pintia.cn/api/problem-sets/{psID}/exams
→ { status,
    exam?: { id, startAt, endAt, ended, score,
             existsSubmissionsNotCompleted, status, problemSetId },
    problemSet: {...}, permission: { permission } }
```

- `permission.permission`：9 = 无权限，15 = 有权限（vscode-pintia 的枚举）。
- 未开始/准备中的题集取题目摘要会 403 —— 要跳过，别当成错误弹给用户。

### 3. 做题情况（想知道「还差几题」时才用）

```
GET https://pintia.cn/api/problem-sets/{psID}/exam-problem-status
→ [ { id, label, score, problemSubmissionStatus, problemType, ... } ]
```

### 4. 其它（以后可能用得上）

- `GET https://passport.pintia.cn/api/u/current` → 当前用户（校验 cookie 还有没有效）
- `GET https://pintia.cn/api/u/info`、`POST https://pintia.cn/api/users/checkin`（签到）
- `GET https://pintia.cn/api/problem-sets/{psID}/problem-summaries` → 题目摘要
- `GET https://pintia.cn/api/submissions/{id}` → 提交结果
- 网页跳转：`https://pintia.cn/problem-sets/{psID}`（题目集页）

### 5. 登录接口（都还没实测成功，见「实测限制」）

```
POST https://pintia.cn/api/student-users/sessions      # 学号登录（无验证码）
  body: { organizationId, organizationCode, studentNumber, name, password,
          omsExamId, omsClientId }

POST https://pintia.cn/api/users/sessions              # 邮箱/手机号登录（要验证码）
  body: { email, password, rememberMe, phone, randStr, ticket, inMiniProgram }
  # randStr + ticket 就是腾讯验证码 TCaptcha（turing.captcha.qcloud.com）

POST https://pintia.cn/api/users/sessions/state/{state}/login_users/{login_user_id}   # 微信扫码
POST https://pintia.cn/api/users/mfa/init  +  /api/users/mfa/{uuid}/sms-check/login   # 短信 MFA
```

## 三、实测限制（诚实说明）

- 从这台机器**不带 cookie** 打登录接口，两个都返回 `406`（空 body）—— 大概率是风控/WAF
  拦了非浏览器请求。所以**登录流程必须在真机/浏览器里验**，我这边验不了。
- 没有 `PTASession` 就读不到任何真实数据，因此上面所有 JSON 字段形状来自
  [jinzcdev/vscode-pintia](https://github.com/jinzcdev/vscode-pintia) 的 TypeScript 接口定义
  （`src/entity/*.ts` 顶端都标了对应 URL，可信度高），**不是**我实测回来的。
  第一次实现时必须拿真 cookie 对一遍字段名。

## 四、接进 Elychron 的方案（待拍板）

现有数据流（见 `lib/mod/homework_tasks.dart`）：

```
教务刷新 → scholar.todos ──listen──> syncHomeworkTasks() → 待办(Task) → 日程/提醒/通知
```

PTA 接进来最省事的位置，就是在最后一步之前**多一路来源**：

1. `lib/http/pta_spider.dart`：`PtaSpider.fetch(cookie)`
   - 拉 `/api/problem-sets?filter={"endAtAfter":now}`；
   - 对每个题集再拉 `/exams`，把「题集本身的 endAt」和「里面 exam 的 endAt」都当截止时间；
   - 产出 `{ id, courseName, title, startTime, endTime, unfinished }`；
   - **落盘缓存**（和 vscode-pintia 一样），TTL 30 分钟左右，避免每次打一串请求。
2. `lib/mod/pta_config.dart`：开关 + cookie + 上次结果。
   - cookie 建议存 **Hive optionsBox**（和已有的"教务账号在 Hive 里也留一份"同一个取舍），
     而不是再往密钥库那套（encryptedSharedPreferences）里加第三个使用者 —— 你刚说那套不动。
3. `startHomeworkSync` 扩成「教务作业 + PTA 作业」两路合并，PTA 的 id 加 `pta:` 前缀，
   避免和教务作业 id 撞车；去重/已忽略沿用同一套（`homeworkDismissed`）。
4. 入口：设置 → 校园服务 → 「PTA 拼题A」：开关 / 粘贴 PTASession / 测试连接 / 上次同步时间。

这样**不用动物业模型**（`scholar.todos` 保持只装教务作业），也不用改 Hive adapter；
通知、提醒、日程、跨设备同步全部白拿（因为最终都变成待办）。

## 五、待拍板

1. 认证 UX：**粘 cookie**（最快、今天就能做）/ **学号+姓名+密码**（无验证码，但要先确认
   浙大在 PTA 的 `organizationCode`）/ 邮箱+密码（要腾讯验证码，几乎必须上 WebView，最重）。
2. PTA 作业要不要也**自动进待办**？还是只在学业页列出来、不自动建待办？
3. 给我一个 `PTASession` 我就能把字段形状实测一遍（只读、只打上面那几个 GET）；
   不给也行 —— 那就先按 vscode-pintia 的定义写，第一次跑通时再对齐。

## 六、实测结果（2026-10-01，真 cookie，已实现）

拿真实 PTASession 打了一遍，**社区文档里有两处和线上不一致**，实现按实测来：

| 项 | 社区定义 | 实测 |
|---|---|---|
| 未截止题目集 | — | 2 条，都是 type=EXERCISE / timeType=FIXED_TIME，organizationName=浙江大学 |
| 题目集截止时间 | problemSets[].endAt | ✅ 对（UTC） |
| 有考试时的截止时间 | exam.endAt | ✅ 对，且实测与题目集的 endAt 相同 |
| exam.existsSubmissionsNotCompleted | 有 | ❌ **线上不返回**，别依赖 |
| exam-problem-status | 数组 | ⚠️ 实际是对象 {problemStatus, examLabelByProblemSetProblemId}；**没有 exam 的题集返回 404**（要当跳过） |
| permission.permission | 9=无 / 15=有 | ⚠️ 实测 **47**，不能硬编码，只能靠 403/404 判断 |
| 登录能力（u/current） | — | studentUserLogin=false、studentUser/organization 空 → **学号登录这条对本人账号走不通**；phoneLogin=true（要腾讯验证码）；wechatUser 有 |

时区：endAt 是 UTC（2026-10-07T15:59:00Z = 北京 23:59）。
我们原样塞进 Todo.endTime，界面统一走 toStringHumanReadable() 里的 toLocal()，
所以不会差 8 小时（单测钉住了）。

已实现（2026-10-01）：
- lib/http/pta_spider.dart —— 拉取 + 纯解析（todosFrom / deadlineOf）
- lib/mod/pta_homework.dart —— 配置（optionsBox，不动 Hive adapter）+ 缓存 +
  并进 scholar.todos + 过期保留上一次
- lib/mod/pta_settings_page.dart —— 设置 → 校园服务 → PTA 拼题A
- main.dart 启动钩子（14 秒）：restore → 挂监听 → 有条件就 refresh
- test/pta_spider_test.dart —— 7 条（含 Z 时区换算、id 稳定、失败保留）
