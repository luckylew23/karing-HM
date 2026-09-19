// karing-HM NAPI 桥：libkaringbox.so（sing-box 核心）↔ ArkTS
// 导出：setConfig(json) / start(tunFd) / stop() / isRunning() / version()
#include "napi/native_api.h"
#include "hilog/log.h"
#include <string>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>

#undef LOG_TAG
#define LOG_TAG "karingboxNapi"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, LOG_TAG, __VA_ARGS__)

typedef const char* (*set_config_fn)(const char*);
typedef const char* (*start_fn)(int32_t);
typedef const char* (*stop_fn)(void);
typedef int32_t (*is_running_fn)(void);
typedef const char* (*version_fn)(void);
typedef const char* (*backup_zip_fn)(const char*, const char*);
typedef const char* (*restore_zip_fn)(const char*, const char*);

static set_config_fn p_set_config = nullptr;
static start_fn p_start = nullptr;
static stop_fn p_stop = nullptr;
static is_running_fn p_is_running = nullptr;
static version_fn p_version = nullptr;
static backup_zip_fn p_backup_zip = nullptr;
static restore_zip_fn p_restore_zip = nullptr;
static bool g_loaded = false;

static void ensureLoaded() {
    if (g_loaded) return;
    void* h = dlopen("libkaringbox_core.so", RTLD_NOW);
    if (!h) {
        LOGE("dlopen libkaringbox_core.so failed: %{public}s", dlerror());
        return;
    }
    p_set_config = (set_config_fn)dlsym(h, "karingbox_set_config");
    p_start = (start_fn)dlsym(h, "karingbox_start");
    p_stop = (stop_fn)dlsym(h, "karingbox_stop");
    p_is_running = (is_running_fn)dlsym(h, "karingbox_is_running");
    p_version = (version_fn)dlsym(h, "karingbox_version");
    p_backup_zip = (backup_zip_fn)dlsym(h, "karingbox_backup_zip");
    p_restore_zip = (restore_zip_fn)dlsym(h, "karingbox_restore_zip");
    LOGI("dlopen ok, set_config=%p start=%p", p_set_config, p_start);
    g_loaded = true;
}

static char *dupCString(const char *s) {
    if (s == nullptr) return nullptr;
    size_t n = strlen(s);
    char *out = (char *)malloc(n + 1);
    if (out != nullptr) {
        memcpy(out, s, n + 1);
    }
    return out;
}

static napi_value NapiSetConfig(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    std::string json(len, '\0');
    napi_get_value_string_utf8(env, args[0], &json[0], len + 1, &len);
    ensureLoaded();
    const char *ret = p_set_config ? p_set_config(json.c_str()) : "ERR core not loaded";
    std::string msg = ret ? ret : "ERR null";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

static napi_value NapiStart(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t fd = -1;
    napi_get_value_int32(env, args[0], &fd);
    LOGI("NAPI start tunFd=%d", fd);
    const char *ret = p_start ? p_start(fd) : "ERR core not loaded";
    std::string msg = ret ? ret : "ERR null";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

static napi_value NapiStop(napi_env env, napi_callback_info info) {
    const char *ret = p_stop ? p_stop() : "ERR core not loaded";
    std::string msg = ret ? ret : "ERR null";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

static napi_value NapiIsRunning(napi_env env, napi_callback_info info) {
    int32_t running = p_is_running ? p_is_running() : 0;
    napi_value result = nullptr;
    napi_create_int32(env, running, &result);
    return result;
}

static napi_value NapiVersion(napi_env env, napi_callback_info info) {
    const char *ret = p_version ? p_version() : "unknown";
    std::string msg = ret ? ret : "unknown";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

static std::string getStringArg(napi_env env, napi_value arg) {
    size_t len = 0;
    napi_get_value_string_utf8(env, arg, nullptr, 0, &len);
    std::string s(len, '\0');
    napi_get_value_string_utf8(env, arg, &s[0], len + 1, &len);
    return s;
}

static napi_value NapiBackupZip(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string dir = getStringArg(env, args[0]);
    std::string zipPath = getStringArg(env, args[1]);
    ensureLoaded();
    const char *ret = p_backup_zip ? p_backup_zip(dir.c_str(), zipPath.c_str()) : "ERR core not loaded";
    std::string msg = ret ? ret : "ERR null";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

static napi_value NapiRestoreZip(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string zipPath = getStringArg(env, args[0]);
    std::string dir = getStringArg(env, args[1]);
    ensureLoaded();
    const char *ret = p_restore_zip ? p_restore_zip(zipPath.c_str(), dir.c_str()) : "ERR core not loaded";
    std::string msg = ret ? ret : "ERR null";
    napi_value result = nullptr;
    napi_create_string_utf8(env, msg.c_str(), msg.size(), &result);
    return result;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"setConfig", nullptr, NapiSetConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, NapiStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, NapiStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, NapiIsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, NapiVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"backupZip", nullptr, NapiBackupZip, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"restoreZip", nullptr, NapiRestoreZip, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module karingboxModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "karingbox",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterKaringBoxModule(void) {
    napi_module_register(&karingboxModule);
}
