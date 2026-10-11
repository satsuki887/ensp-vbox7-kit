// 32-bit runtime probe of the real VirtualBox 7.2 IVirtualBox vtable.
// Read-only: get_Version, FindMachine, and a correctly-typed read of slot 41.
#include <windows.h>
#include <objbase.h>
#include <oleauto.h>
#include <cstdio>

static const CLSID CLSID_VirtualBox = {0xB1A7A4F2,0x47B9,0x4A1E,{0x82,0xB2,0x07,0xCC,0xD5,0x32,0x3C,0x3F}};
static const IID IID_IVirtualBox7  = {0x2CE10519,0x3C09,0x45D8,{0xA1,0x2D,0xE8,0x87,0x78,0x61,0x46,0xB7}};

typedef HRESULT (__stdcall *GetBstr)(IUnknown*, BSTR*);
typedef HRESULT (__stdcall *GetUlong)(IUnknown*, ULONG*);
typedef HRESULT (__stdcall *FindFn)(IUnknown*, BSTR, IUnknown**);
typedef HRESULT (__stdcall *GetName)(IUnknown*, BSTR*);

int main() {
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    IUnknown* vb = NULL;
    hr = CoCreateInstance(CLSID_VirtualBox, NULL, CLSCTX_LOCAL_SERVER, IID_IVirtualBox7, (void**)&vb);
    printf("CoCreateInstance(IVirtualBox 7.2) hr=0x%08lX\n", hr);
    if (FAILED(hr)) return 1;
    void** vt = *(void***)vb;

    BSTR ver = NULL;
    hr = ((GetBstr)vt[7])(vb, &ver);
    printf("[7]  get_Version              hr=0x%08lX value=%S\n", hr, ver ? ver : L"(null)");

    // Slot 41: type library says InternalAndReservedAttribute6 (ULONG* out).
    ULONG dummy = 0xDEADBEEF;
    hr = ((GetUlong)vt[41])(vb, &dummy);
    printf("[41] (tlb: reserved getter)   hr=0x%08lX  %s\n", hr,
           hr == (HRESULT)0x80004001 ? "E_NOTIMPL -> slot 41 is a reserved attribute" : "");

    BSTR name = SysAllocString(L"AR_Base");
    { int slot = 53;
        IUnknown* m = NULL;
        hr = ((FindFn)vt[slot])(vb, name, &m);
        printf("[%d] FindMachine(\"AR_Base\")  hr=0x%08lX machine=%p\n", slot, hr, m);
        if (SUCCEEDED(hr) && m) {
            // IMachine::get_Name -- look it up from the IMachine type info instead of guessing
            IDispatch* d = NULL;
            if (SUCCEEDED(m->QueryInterface(IID_IDispatch, (void**)&d)) && d) {
                LPOLESTR nm = (LPOLESTR)L"Name"; DISPID id;
                if (SUCCEEDED(d->GetIDsOfNames(IID_NULL, &nm, 1, LOCALE_SYSTEM_DEFAULT, &id))) {
                    DISPPARAMS dp = {0}; VARIANT r; VariantInit(&r);
                    hr = d->Invoke(id, IID_NULL, LOCALE_SYSTEM_DEFAULT, DISPATCH_PROPERTYGET, &dp, &r, NULL, NULL);
                    printf("     -> machine.Name via IDispatch hr=0x%08lX value=%S\n", hr, r.vt == VT_BSTR ? r.bstrVal : L"?");
                    VariantClear(&r);
                }
                d->Release();
            }
            m->Release();
        }
    }
    SysFreeString(name);
    vb->Release();
    CoUninitialize();
    return 0;
}
