// 32-bit harness: call eNSP_Cloud_Plugin.dll's own adapter enumeration and print
// what the Cloud dialog would get. See docs/findings/cloud-npcap.md.
//
// The plugin is loaded from this exe's directory (cloud.bat copies it there from
// your eNSP install), so the packet.dll it binds to is whichever one that
// directory search finds first: put Npcap's 32-bit Packet.dll next to the exe to
// test Npcap without touching the system's WinPcap.
//
// RVA 0x11480 is the enumeration in eNSP V100R003C00SPC100's plugin: cdecl, one
// argument, 20 entries of 0x800 bytes (WCHAR name[0x200] + WCHAR desc[0x200]),
// called the same way at 100088DA.
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef int (__cdecl *ENUMFN)(void*);
typedef const char* (*VERFN)();

int main() {
    HMODULE pk = LoadLibraryA("packet.dll");
    char path[MAX_PATH] = "";
    if (pk) GetModuleFileNameA(pk, path, MAX_PATH);
    printf("packet.dll       : %s\n", pk ? path : "(load failed)");
    VERFN ver = pk ? (VERFN)GetProcAddress(pk, "PacketGetVersion") : NULL;
    printf("PacketGetVersion : %s\n", ver ? ver() : "?");

    HMODULE h = LoadLibraryA("eNSP_Cloud_Plugin.dll");
    if (!h) { printf("[!] cannot load eNSP_Cloud_Plugin.dll (err %lu)\n", GetLastError()); return 1; }
    ENUMFN fn = (ENUMFN)((unsigned char*)h + 0x11480);
    static unsigned char buf[20 * 0x800];
    fn(buf);
    int n = 0;
    for (int i = 0; i < 20; i++) {
        wchar_t* name = (wchar_t*)(buf + i * 0x800);
        wchar_t* desc = (wchar_t*)(buf + i * 0x800 + 0x400);
        if (!name[0]) continue;
        char d[0x400];   // descriptions may be non-ASCII: print in the console code page
        WideCharToMultiByte(CP_ACP, 0, desc, -1, d, sizeof d, NULL, NULL);
        printf("  [%2d] %ls  %s\n", i, name, d);
        n++;
    }
    printf("adapters offered to Cloud: %d\n", n);
    return 0;
}
