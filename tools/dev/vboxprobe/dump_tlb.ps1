# Dump vtable slot of every method of the given interfaces from a type library.
# Output: <Interface>\t<slot>\t<get_|put_|><name>
param([string]$TlbPath, [string[]]$Interfaces = @('IVirtualBox','IMachine'))

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using CT = System.Runtime.InteropServices.ComTypes;
public static class Tlb {
    [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void LoadTypeLibEx(string file, int regkind, out CT.ITypeLib tlb);
    public static string[] Dump(string path, string[] wanted) {
        CT.ITypeLib tlb; LoadTypeLibEx(path, 2 /* REGKIND_NONE */, out tlb);
        var outp = new System.Collections.Generic.List<string>();
        int n = tlb.GetTypeInfoCount();
        for (int i = 0; i < n; i++) {
            CT.ITypeInfo ti; tlb.GetTypeInfo(i, out ti);
            string name, doc, hf; int ctx;
            ti.GetDocumentation(-1, out name, out doc, out ctx, out hf);
            if (Array.IndexOf(wanted, name) < 0) continue;
            IntPtr pta; ti.GetTypeAttr(out pta);
            var ta = (CT.TYPEATTR)Marshal.PtrToStructure(pta, typeof(CT.TYPEATTR));
            if (ta.typekind == CT.TYPEKIND.TKIND_DISPATCH) {   // dual: switch to the vtable side
                ti.ReleaseTypeAttr(pta);
                int href; ti.GetRefTypeOfImplType(-1, out href);
                CT.ITypeInfo ti2; ti.GetRefTypeInfo(href, out ti2); ti = ti2;
                ti.GetTypeAttr(out pta); ta = (CT.TYPEATTR)Marshal.PtrToStructure(pta, typeof(CT.TYPEATTR));
            }
            for (int f = 0; f < ta.cFuncs; f++) {
                IntPtr pfd; ti.GetFuncDesc(f, out pfd);
                var fd = (CT.FUNCDESC)Marshal.PtrToStructure(pfd, typeof(CT.FUNCDESC));
                string fn, d2, h2; int c2;
                ti.GetDocumentation(fd.memid, out fn, out d2, out c2, out h2);
                string pre = fd.invkind == CT.INVOKEKIND.INVOKE_PROPERTYGET ? "get_" :
                             (fd.invkind == CT.INVOKEKIND.INVOKE_PROPERTYPUT ? "put_" : "");
                outp.Add(name + "\t" + (fd.oVft / IntPtr.Size) + "\t" + pre + fn + "\t" + fd.cParams);
                ti.ReleaseFuncDesc(pfd);
            }
            ti.ReleaseTypeAttr(pta);
        }
        return outp.ToArray();
    }
}
"@
[Tlb]::Dump($TlbPath, $Interfaces)
