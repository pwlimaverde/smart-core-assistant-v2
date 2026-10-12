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
  const unsigned int largura = 1280;
  const unsigned int altura = 720;
  const double escala = ::GetDpiForSystem() / 96.0;
  const int area_largura = static_cast<int>(::GetSystemMetrics(SM_CXSCREEN) / escala);
  const int area_altura = static_cast<int>(::GetSystemMetrics(SM_CYSCREEN) / escala);
  const int x = (area_largura - static_cast<int>(largura)) / 2;
  const int y = (area_altura - static_cast<int>(altura)) / 2;
  Win32Window::Point origin(static_cast<unsigned int>(x > 0 ? x : 0),
                            static_cast<unsigned int>(y > 0 ? y : 0));
  Win32Window::Size size(largura, altura);
  // D3: Título da janela (aparece na barra de título e no Alt+Tab)
  if (!window.Create(L"Smart Core Tenant", origin, size)) {
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
