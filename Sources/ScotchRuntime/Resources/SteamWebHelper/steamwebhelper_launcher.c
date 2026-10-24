// Scotch steamwebhelper launcher.
//
// Wine 11 on Apple Silicon fails to present frames that Chromium hands between
// its GPU/renderer processes and the browser window, so Steam's UI stays black.
// Scotch installs this as Steam's bin/cef/cef.win64/steamwebhelper.exe (the real
// one is renamed steamwebhelper_real.exe). It starts the real helper with
// --disable-gpu --single-process so everything renders in one process, then
// mirrors its exit code. Override the flags with SCOTCH_CEF_FLAGS.
//
// Build: x86_64-w64-mingw32-gcc -O2 -s -municode -mwindows \
//          -o steamwebhelper_launcher.exe steamwebhelper_launcher.c
#include <windows.h>
#include <wchar.h>

static const WCHAR *skip_argv0(const WCHAR *cmd) {
    if (*cmd == L'"') {
        cmd++;
        while (*cmd && *cmd != L'"') cmd++;
        if (*cmd) cmd++;
    } else {
        while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
    }
    while (*cmd == L' ' || *cmd == L'\t') cmd++;
    return cmd;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmdLine, int show) {
    (void)inst; (void)prev; (void)cmdLine; (void)show;

    WCHAR real[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, real, MAX_PATH);
    if (!n || n >= MAX_PATH) return 1;
    WCHAR *slash = wcsrchr(real, L'\\');
    if (!slash) return 1;
    wcscpy(slash + 1, L"steamwebhelper_real.exe");

    WCHAR flags[2048];
    DWORD f = GetEnvironmentVariableW(L"SCOTCH_CEF_FLAGS", flags, 2048);
    if (!f || f >= 2048) wcscpy(flags, L"--disable-gpu --single-process");

    static WCHAR cmd[32768];
    _snwprintf(cmd, 32767, L"\"%ls\" %ls %ls", real, flags, skip_argv0(GetCommandLineW()));
    cmd[32767] = 0;

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(real, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) return 1;
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
