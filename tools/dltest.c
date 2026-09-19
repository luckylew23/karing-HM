// dlopen 测试：直接在真机加载 libkaringbox.so，打印 dlerror
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <libpath>\n", argv[0]); return 2; }
    const char *path = argv[1];
    fprintf(stderr, "dlopen: %s\n", path);
    void *h = dlopen(path, RTLD_NOW);
    if (!h) {
        fprintf(stderr, "DLOPEN_FAIL: %s\n", dlerror());
        return 1;
    }
    fprintf(stderr, "DLOPEN_OK handle=%p\n", h);
    // 试取 karingbox_version
    typedef const char *(*ver_fn)(void);
    dlerror();
    ver_fn ver = (ver_fn)dlsym(h, "karingbox_version");
    const char *e = dlerror();
    if (e) { fprintf(stderr, "dlsym version fail: %s\n", e); }
    else { fprintf(stderr, "version: %s\n", ver()); }
    return 0;
}
