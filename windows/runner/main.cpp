#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // ===== v1.5.0 桌面端：默认窗口大小 =====
  // 1280x720 在 150% 缩放的笔记本屏上会变成 1920x1080 物理像素，比屏幕还大，
  // 一打开就被系统撑成最大化（实测在 1707x1067 的屏上必现）。
  // 这里按"留出任务栏和边距"给一个更保守的默认值：1120x760。
  // 150% 缩放的屏上，逻辑宽 1120 -> 物理 1680，比屏幕还宽会被系统裁掉
  // （实测：1120 逻辑只剩 ~747 逻辑可用，页面被挤成一条）。
  // 这里按"在 1707x1067 的屏上也放得下"来定：1050 逻辑约 1575 物理。
  Win32Window::Point origin(40, 30);
  Win32Window::Size size(1050, 680);
  if (!window.Create(L"Elychron", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
