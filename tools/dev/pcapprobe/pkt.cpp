// 32-bit probe: call packet.dll exactly as eNSP_Cloud_Plugin does and dump the raw result.
#include <windows.h>
#include <cstdio>

typedef PCHAR (__cdecl *PFN_GetVersion)(void);
typedef BOOLEAN (__cdecl *PFN_GetNames)(PCHAR, PULONG);

int main() {
    HMODULE h = LoadLibraryA("packet.dll");
    char path[MAX_PATH] = {0};
    if (h) GetModuleFileNameA(h, path, MAX_PATH);
    printf("packet.dll loaded from: %s\n", h ? path : "(load failed)");
    if (!h) return 1;
    PFN_GetVersion ver = (PFN_GetVersion)GetProcAddress(h, "PacketGetVersion");
    PFN_GetNames names = (PFN_GetNames)GetProcAddress(h, "PacketGetAdapterNames");
    printf("PacketGetVersion() = \"%s\"\n", ver ? ver() : "(missing)");
    if (!names) return 2;

    ULONG size = 0;
    BOOLEAN ok = names(NULL, &size);
    printf("probe call: ok=%d size=%lu err=%lu\n", ok, size, GetLastError());
    ULONG cap = size ? size : 65536;
    char* buf = (char*)calloc(1, cap + 16);
    ULONG sz2 = cap;
    ok = names(buf, &sz2);
    printf("real call: ok=%d size=%lu err=%lu\n", ok, sz2, GetLastError());
    if (!ok) return 3;

    // Format: name\0name\0...\0\0desc\0desc\0...\0\0
    char* p = buf; int n = 0;
    printf("--- names ---\n");
    while (*p) { printf("  [%d] %s\n", n++, p); p += strlen(p) + 1; }
    p++;
    printf("--- descriptions ---\n");
    int d = 0;
    while (*p && d < 64) { printf("  [%d] %s\n", d++, p); p += strlen(p) + 1; }
    printf("names=%d descriptions=%d\n", n, d);
    // Raw head, to spot wide-char vs ANSI
    printf("--- first 48 bytes ---\n  ");
    for (int i = 0; i < 48; i++) printf("%02X ", (unsigned char)buf[i]);
    printf("\n");
    return 0;
}
