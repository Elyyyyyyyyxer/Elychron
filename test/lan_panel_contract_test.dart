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
}
