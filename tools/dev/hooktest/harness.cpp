// Concurrency harness for the VBox52.dll CreateProcessW hook.
//   harness.exe <VBox52.dll> <threads> <iterations> <outdir>
//   harness.exe --child <outfile> ...   (child: records its own command line)
#include <windows.h>
#include <cstdio>
#include <cwchar>

static wchar_t g_self[MAX_PATH], g_out[MAX_PATH];
static int g_iters;
static int g_pad = 0;   // HARNESS_PAD: extra chars on each command line
static HANDLE g_go;
static volatile LONG g_fail = 0;
typedef void (__stdcall *PFN_Install)();
static PFN_Install g_install;

static DWORD WINAPI installer(LPVOID) { WaitForSingleObject(g_go, INFINITE); g_install(); return 0; }

static DWORD WINAPI spawner(LPVOID arg) {
    int t = (int)(INT_PTR)arg;
    WaitForSingleObject(g_go, INFINITE);
    for (int i = 0; i < g_iters; i++) {
        wchar_t cmd[4096];
        static wchar_t pad[2048];
        if (g_pad && !pad[0]) { for (int k = 0; k < g_pad && k < 2000; k++) pad[k] = L'x'; }
        swprintf(cmd, 4096, L"\"%s\" --child \"%s\\t%02d_%03d.txt\" %s modifyvm vm%d --uartmode2 server \\\\.\\pipe\\p%d",
                 g_self, g_out, t, i, pad, t, i);
        STARTUPINFOW si = { sizeof(si) }; PROCESS_INFORMATION pi;
        if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
            InterlockedIncrement(&g_fail); continue;
        }
        WaitForSingleObject(pi.hProcess, INFINITE);
        CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    }
    return 0;
}

int wmain(int argc, wchar_t** argv) {
    if (argc >= 3 && wcscmp(argv[1], L"--child") == 0) {
        FILE* f = _wfopen(argv[2], L"w, ccs=UTF-8");
        if (f) { fputws(GetCommandLineW(), f); fclose(f); }
        return 0;
    }
    if (argc < 5) { wprintf(L"usage: harness <dll> <threads> <iters> <outdir>\n"); return 2; }
    setvbuf(stdout, NULL, _IONBF, 0);
    { wchar_t e[16]; if (GetEnvironmentVariableW(L"HARNESS_PAD", e, 16)) g_pad = _wtoi(e); }
    GetModuleFileNameW(NULL, g_self, MAX_PATH);
    int installers = (argc > 5 && wcscmp(argv[5], L"seq") == 0) ? 1 : 8;
    int threads = _wtoi(argv[2]); g_iters = _wtoi(argv[3]); wcscpy(g_out, argv[4]);
    CreateDirectoryW(g_out, NULL);

    HMODULE dll = LoadLibraryW(argv[1]);
    if (!dll) { wprintf(L"LoadLibrary failed %lu\n", GetLastError()); return 3; }
    g_install = (PFN_Install)GetProcAddress(dll, "ShimSelfTest_InstallHooks");
    if (!g_install) g_install = (PFN_Install)GetProcAddress(dll, "_ShimSelfTest_InstallHooks@0");
    if (!g_install) { wprintf(L"no ShimSelfTest_InstallHooks export\n"); return 4; }

    // Phase 1: 8 threads race to install the hooks (what GetVBoxInstance and
    // Factory_CreateInstance can do in eNSP).
    g_go = CreateEventW(NULL, TRUE, FALSE, NULL);
    HANDLE h[64];
    for (int i = 0; i < installers; i++) h[i] = CreateThread(NULL, 0, installer, NULL, 0, NULL);
    SetEvent(g_go);
    WaitForMultipleObjects(installers, h, TRUE, INFINITE);
    for (int i = 0; i < installers; i++) CloseHandle(h[i]);
    wprintf(L"phase1: concurrent install done\n");

    // Phase 2: many threads spawn "VBoxManage modifyvm --uartmode2" lookalikes.
    ResetEvent(g_go);
    for (int i = 0; i < threads; i++) h[i] = CreateThread(NULL, 0, spawner, (LPVOID)(INT_PTR)i, 0, NULL);
    DWORD t0 = GetTickCount();
    SetEvent(g_go);
    WaitForMultipleObjects(threads, h, TRUE, INFINITE);
    DWORD ms = GetTickCount() - t0;

    int total = 0, injected = 0, missing = 0;
    for (int t = 0; t < threads; t++) for (int i = 0; i < g_iters; i++) {
        wchar_t p[MAX_PATH]; swprintf(p, MAX_PATH, L"%s\\t%02d_%03d.txt", g_out, t, i);
        FILE* f = _wfopen(p, L"r, ccs=UTF-8");
        if (!f) { missing++; continue; }
        wchar_t buf[4096] = {0}; fgetws(buf, 4096, f); fclose(f);
        total++;
        if (wcsstr(buf, L"--uart2 0x2f8 3 --uartmode2")) injected++;
    }
    int expected = threads * g_iters;
    wprintf(L"phase2: %d threads x %d = %d spawns in %lu ms\n", threads, g_iters, expected, ms);
    wprintf(L"        CreateProcess failed: %ld, child output missing: %d\n", g_fail, missing);
    wprintf(L"        injected: %d / %d   NOT injected (hook bypassed): %d\n", injected, total, total - injected);
    return (injected == expected) ? 0 : 1;
}
