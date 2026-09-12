import 'package:flutter_test/flutter_test.dart';
import 'package:celechron/mod/lan_panel.dart';

void main() {
  test('LAN panel keeps its critical routes and safety hooks', () {
    expect(lanPanelHtml, contains("fetch('/pair'"));
    expect(lanPanelHtml, contains("api('/bundle'"));
    expect(lanPanelHtml, contains('position:fixed; right:22px'));
    expect(lanPanelHtml, contains('Notification.requestPermission'));
    expect(lanPanelHtml, contains('AbortController'));
    expect(lanPanelHtml, contains('visibilitychange'));
    expect(lanPanelHtml, contains('editReminderEnabled'));
    expect(lanPanelHtml, contains('setTaskFilter'));
    // A literal closing script tag is required for the HTML document, but no
    // script text may accidentally terminate the embedded JavaScript early.
    expect(lanPanelHtml.split('<script>').length, 2);
    expect(lanPanelHtml.split('</script>').length, 2);
  });

  test('LAN panel edits every itinerary subtask field', () {
    // 编辑器里的每一步都能改这四样：done / startTime / endTime / reminderMinutes
    expect(lanPanelHtml, contains('id="editSubtasks"'));
    expect(lanPanelHtml, contains('class="sub-row"'));
    expect(lanPanelHtml, contains('class="sub-done"'));
    expect(lanPanelHtml, contains('class="sub-start"'));
    expect(lanPanelHtml, contains('class="sub-end"'));
    expect(lanPanelHtml, contains('class="sub-lead"'));
    expect(lanPanelHtml, contains('renderSubtasksEditor'));
    expect(lanPanelHtml, contains('addSubtaskRow'));
    expect(lanPanelHtml, contains('removeSubtaskRow'));
    // 保存前必须从 DOM 读回草稿：漏掉没触发过事件的输入就会把用户改的时间丢掉
    expect(lanPanelHtml, contains('syncSubtasksEditor'));
    // 子待办容器是 div（没有 value），旧版直接给它赋 value 是死代码
    expect(lanPanelHtml, isNot(contains("getElementById('editSubtasks').value")));
  });

  test('LAN panel shows subtask reminders the same way the app does', () {
    // 语义与 model/task.dart 的 SubTask 一致：时刻 − 提前量，完成 / 无时间不提醒
    expect(lanPanelHtml, contains('subReminderTime'));
    expect(lanPanelHtml, contains('subIsSpan'));
    expect(lanPanelHtml, contains('subIsOngoing'));
    expect(lanPanelHtml, contains('subIsMissed'));
    expect(lanPanelHtml, contains('nearestSubReminder'));
    // 默认提前量取手机上「默认提醒提前量」（DataBackup 的 settings.reminderLeadMinutes）
    expect(lanPanelHtml, contains('reminderLeadMinutes'));
    // 任务级与子待办都要排电脑提醒
    expect(lanPanelHtml, contains("'sub|'"));
    expect(lanPanelHtml, contains('toggleSubtask'));
  });

  test('LAN panel writes the same timestamp format as the app', () {
    // 手机端 toIso8601String() 写的是**本地**格式；网页端混写 'Z' 结尾的 UTC 串会
    // 让 updatedAt 的比较（以及以后的字符串比较）判错新旧。
    expect(lanPanelHtml, contains('function isoLocal('));
    expect(lanPanelHtml, isNot(contains('.toISOString()')));
    expect(lanPanelHtml, contains('stampMs(local.updatedAt) >= stampMs(t.updatedAt)'));
  });
}
