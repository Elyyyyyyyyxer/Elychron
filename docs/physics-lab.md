# 普物实验课表接入

## 使用与验收

在「设置 → 教务」中，普物实验与 PTA、图书馆并列。
进入「登录选课系统」，在官网自行登录并进入「我的课表」，点击 App 右上角「完成」。
首次同步后选择「教务课表」或「实验选课系统」作为普物实验的最终上课安排。
未选择时保留教务课表；选择实验选课后，逐门确认它对应的教务课程，或明确教务中没有此课。
仅替换确认课程的上课安排，成绩、学分及考试保留教务数据；其他课程不变。
选择按账号保存。可随时切回教务来源，原始教务缓存不会被改写。

打开或回到 App 会尝试同步；自动同步有五分钟间隔，也可以立即同步。

已选实验显示在现有课程表、课程详情和日历中，不创建待办。课程详情显示实验日期和精确起止钟点。
重复同步替换来源附加层，改期更新同一来源记录；教务刷新后重新附加。
官网没有给出结束时间时采用 2 小时 25 分钟，请以官网实际安排为准。
网络、登录或转换失败保留已有课表；关闭同步移除附加层及其创建的空学期。

## 参考与边界

参考 [5dbwat4/zjuphylab.ics](https://github.com/5dbwat4/zjuphylab.ics) 的接口、字段映射和默认时长方案。
参考项目的脚本仅取第一门课程，本实现读取当前学期所有课程。
使用官方选课网站 Vue `studentCourse` 的 `emitAjax` 进行三个只读请求：
`/api/courses/uid`、`/api/course/lab/students/full`、`/api/courseLabTimes/date`。
认证和请求签名由官网页面完成，不另写密码登录协议，不把网页 token 导出或存入 App 缓存。
缓存仅包含课表字段、账号哈希范围和来源创建的学期名，独立存于 optionsBox。
不改 Hive adapter 或教务课程 JSON 结构。

选课系统为校园内网 HTTP 服务 `10.203.16.55`。需要校园网或能访问该内网的学校 VPN。
iOS ATS 和 Android 明文访问例外仅增加该 IP，不开放所有网站。
macOS 模拟器需宿主机分流正常；iPhone/iPad 实机需要自身可访问校园网，不能继承 Mac 代理。
只在允许的平台展示网页登录。实际账号登录、课表数据和实验结束时间需用户验收。

## 自动验证

- `flutter test test/physics_lab_courses_test.dart`：日期、去重、改期、序列化隔离、原子替换、校历归属与学期清理。
- `flutter test test/physics_lab_service_test.dart`：离线恢复通知、教务刷新重新附加、账号隔离、来源持久化与过期操作取消。
- `flutter test test/physics_lab_page_test.dart`：来源选择、对应课程确认及切回教务的界面流程。
- `flutter test test/physics_lab_semester_selection_test.dart`：三个既有控制器在学期变化后保持选择、安全回退。
- `node test_native/physics_lab_bridge/main.cjs`：官网桥接端点、所有课程、字段白名单、异站阻止、登录/错误与会话变化。
