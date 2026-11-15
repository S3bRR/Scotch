/* SPDX-License-Identifier: GPL-3.0-or-later
 * Wine's native Vulkan entry point. Select the tested driver per instance,
 * preserving native handles and dispatch instead of changing process globals. */
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#define EXPORT __attribute__((visibility("default")))
EXPORT PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance, const char *);
EXPORT PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice, const char *);
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void *libraries[2];
static PFN_vkGetInstanceProcAddr procs[2];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
typedef struct Handle {
    void *handle;
    VkInstance instance;
    unsigned driver, kind;
    struct Handle *next;
} Handle;
static Handle *handles;
static void init(void) {
    Dl_info info;
    if (!dladdr((void *)vkGetInstanceProcAddr, &info) || !info.dli_fname)
        return;
    char directory[PATH_MAX];
    if (!realpath(info.dli_fname, directory))
        snprintf(directory, sizeof(directory), "%s", info.dli_fname);
    char *slash = strrchr(directory, '/');
    if (!slash)
        return;
    *slash = 0;
    for (unsigned i = 0; i < 2; i++) {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/%s", directory, i ? "libvulkan_kosmickrisp.dylib" : "libMoltenVK.dylib");
        libraries[i] = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!libraries[i]) {
            fprintf(stderr, "Scotch Vulkan: %s\n", dlerror());
            continue;
        }
        typedef VkResult (*Negotiate)(uint32_t *);
        Negotiate n = (void *)dlsym(libraries[i], "vk_icdNegotiateLoaderICDInterfaceVersion");
        uint32_t version = 7;
        if (n && n(&version) != VK_SUCCESS)
            continue;
        procs[i] = (void *)dlsym(libraries[i], "vk_icdGetInstanceProcAddr");
        if (!procs[i])
            procs[i] = (void *)dlsym(libraries[i], "vkGetInstanceProcAddr");
    }
}
static PFN_vkVoidFunction proc(unsigned d, VkInstance instance, const char *name) {
    PFN_vkVoidFunction fn = procs[d] ? procs[d](instance, name) : NULL;
    if (!fn && instance) {
        size_t n = strlen(name);
        if (n > 3 && (!strcmp(name + n - 3, "KHR") || !strcmp(name + n - 3, "EXT"))) {
            char core[256];
            if (n - 3 < sizeof(core)) {
                memcpy(core, name, n - 3);
                core[n - 3] = 0;
                fn = procs[d](instance, core);
            }
        }
    }
    return fn ? fn : (libraries[d] ? (PFN_vkVoidFunction)dlsym(libraries[d], name) : NULL);
}
static int lookup(void *value, unsigned kind, Handle *out) {
    int found = 0;
    pthread_mutex_lock(&lock);
    for (Handle *h = handles; h; h = h->next)
        if (h->handle == value && h->kind == kind) {
            *out = *h;
            found = 1;
            break;
        }
    pthread_mutex_unlock(&lock);
    return found;
}
static void remember(void *value, unsigned kind, VkInstance instance, unsigned driver) {
    pthread_mutex_lock(&lock);
    for (Handle *h = handles; h; h = h->next)
        if (h->handle == value && h->kind == kind) {
            h->instance = instance;
            h->driver = driver;
            pthread_mutex_unlock(&lock);
            return;
        }
    Handle *h = malloc(sizeof(*h));
    if (!h)
        abort();
    *h = (Handle){value, instance, driver, kind, handles};
    handles = h;
    pthread_mutex_unlock(&lock);
}
static void forget(void *value, unsigned kind) {
    pthread_mutex_lock(&lock);
    Handle **p = &handles;
    while (*p) {
        Handle *h = *p;
        if ((h->handle == value && h->kind == kind) || (kind == 0 && h->instance == (VkInstance)value)) {
            *p = h->next;
            free(h);
        } else
            p = &h->next;
    }
    pthread_mutex_unlock(&lock);
}
static VKAPI_ATTR VkResult VKAPI_CALL create_instance(const VkInstanceCreateInfo *ci, const VkAllocationCallbacks *a,
                                                      VkInstance *out) {
    pthread_once(&once, init);
    const char *engine = ci->pApplicationInfo ? ci->pApplicationInfo->pEngineName : NULL;
    unsigned d = engine && strstr(engine, "zink");
    PFN_vkCreateInstance fn = (void *)proc(d, NULL, "vkCreateInstance");
    VkResult r = fn ? fn(ci, a, out) : VK_ERROR_INITIALIZATION_FAILED;
    if (r == VK_SUCCESS)
        remember(*out, 0, *out, d);
    if (getenv("SCOTCH_VULKAN_TRACE"))
        fprintf(stderr, "Scotch Vulkan: %s -> %s, result=%d\n", engine ? engine : "Wine",
                d ? "KosmicKrisp" : "MoltenVK", r);
    return r;
}
static VKAPI_ATTR void VKAPI_CALL destroy_instance(VkInstance instance, const VkAllocationCallbacks *a) {
    if (!instance)
        return;
    Handle h;
    if (!lookup(instance, 0, &h))
        return;
    PFN_vkDestroyInstance fn = (void *)proc(h.driver, instance, "vkDestroyInstance");
    fn(instance, a);
    forget(instance, 0);
}
static VKAPI_ATTR VkResult VKAPI_CALL enumerate_devices(VkInstance instance, uint32_t *count, VkPhysicalDevice *out) {
    Handle h;
    if (!lookup(instance, 0, &h))
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkEnumeratePhysicalDevices fn = (void *)proc(h.driver, instance, "vkEnumeratePhysicalDevices");
    VkResult r = fn(instance, count, out);
    if (out && (r == VK_SUCCESS || r == VK_INCOMPLETE))
        for (uint32_t i = 0; i < *count; i++)
            remember(out[i], 1, instance, h.driver);
    return r;
}
static VKAPI_ATTR VkResult VKAPI_CALL enumerate_groups(VkInstance instance, uint32_t *count,
                                                       VkPhysicalDeviceGroupProperties *out) {
    Handle h;
    if (!lookup(instance, 0, &h))
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkEnumeratePhysicalDeviceGroups fn = (void *)proc(h.driver, instance, "vkEnumeratePhysicalDeviceGroups");
    if (!fn)
        fn = (void *)proc(h.driver, instance, "vkEnumeratePhysicalDeviceGroupsKHR");
    if (!fn)
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    VkResult r = fn(instance, count, out);
    if (out && (r == VK_SUCCESS || r == VK_INCOMPLETE))
        for (uint32_t i = 0; i < *count; i++)
            for (uint32_t j = 0; j < out[i].physicalDeviceCount; j++)
                remember(out[i].physicalDevices[j], 1, instance, h.driver);
    return r;
}
static VKAPI_ATTR VkResult VKAPI_CALL create_device(VkPhysicalDevice physical, const VkDeviceCreateInfo *ci,
                                                    const VkAllocationCallbacks *a, VkDevice *out) {
    Handle h;
    if (!lookup(physical, 1, &h))
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkCreateDevice fn = (void *)proc(h.driver, h.instance, "vkCreateDevice");
    if (!fn)
        return VK_ERROR_INITIALIZATION_FAILED;
    VkResult r = fn(physical, ci, a, out);
    if (r == VK_SUCCESS)
        remember(*out, 2, h.instance, h.driver);
    return r;
}
static VKAPI_ATTR void VKAPI_CALL destroy_device(VkDevice device, const VkAllocationCallbacks *a) {
    if (!device)
        return;
    Handle h;
    if (!lookup(device, 2, &h))
        return;
    PFN_vkGetDeviceProcAddr gdpa = (void *)proc(h.driver, h.instance, "vkGetDeviceProcAddr");
    PFN_vkDestroyDevice fn = (void *)gdpa(device, "vkDestroyDevice");
    fn(device, a);
    forget(device, 2);
}
static VKAPI_ATTR VkResult VKAPI_CALL extensions(const char *layer, uint32_t *count, VkExtensionProperties *out) {
    pthread_once(&once, init);
    if (layer) {
        *count = 0;
        return VK_ERROR_LAYER_NOT_PRESENT;
    }
    VkExtensionProperties *lists[2] = {0};
    uint32_t sizes[2] = {0};
    VkResult r = VK_SUCCESS;
    for (unsigned d = 0; d < 2; d++) {
        PFN_vkEnumerateInstanceExtensionProperties fn = (void *)proc(d, NULL, "vkEnumerateInstanceExtensionProperties");
        if (!fn) {
            r = VK_ERROR_INITIALIZATION_FAILED;
            goto end;
        }
        r = fn(NULL, &sizes[d], NULL);
        if (r != VK_SUCCESS)
            goto end;
        lists[d] = calloc(sizes[d], sizeof(**lists));
        if (!lists[d] && sizes[d]) {
            r = VK_ERROR_OUT_OF_HOST_MEMORY;
            goto end;
        }
        r = fn(NULL, &sizes[d], lists[d]);
        if (r != VK_SUCCESS)
            goto end;
    }
    uint32_t available = 0, written = 0, capacity = out ? *count : 0;
    for (uint32_t i = 0; i < sizes[0]; i++)
        for (uint32_t j = 0; j < sizes[1]; j++)
            if (!strcmp(lists[0][i].extensionName, lists[1][j].extensionName)) {
                VkExtensionProperties common = lists[0][i];
                if (common.specVersion > lists[1][j].specVersion)
                    common.specVersion = lists[1][j].specVersion;
                available++;
                if (out && written < capacity)
                    out[written++] = common;
                break;
            }
    *count = out ? written : available;
    r = out && capacity < available ? VK_INCOMPLETE : VK_SUCCESS;
end:
    free(lists[0]);
    free(lists[1]);
    return r;
}
static VKAPI_ATTR VkResult VKAPI_CALL layers(uint32_t *count, VkLayerProperties *out) {
    (void)out;
    *count = 0;
    return VK_SUCCESS;
}
static VKAPI_ATTR VkResult VKAPI_CALL version(uint32_t *out) {
    pthread_once(&once, init);
    uint32_t values[2] = {VK_API_VERSION_1_0, VK_API_VERSION_1_0};
    for (unsigned i = 0; i < 2; i++) {
        PFN_vkEnumerateInstanceVersion fn = (void *)proc(i, NULL, "vkEnumerateInstanceVersion");
        if (fn)
            fn(&values[i]);
    }
    *out = values[0] < values[1] ? values[0] : values[1];
    return VK_SUCCESS;
}
static void spoof(unsigned driver, VkPhysicalDeviceProperties *p) {
    if (driver)
        return;
    const char *vendor = getenv("SCOTCH_GPU_VENDOR_ID"), *device = getenv("SCOTCH_GPU_DEVICE_ID"),
               *name = getenv("SCOTCH_GPU_DEVICE_NAME");
    if (vendor)
        p->vendorID = (unsigned)strtoul(vendor, NULL, 16);
    // Preserve the existing compatibility preset's driver identity along with
    // its vendor. Keep KosmicKrisp's real identity for Mesa's workarounds.
    if (vendor && p->vendorID == 0x1002)
        p->driverVersion = (23u << 22) | (12u << 12) | 1u;
    else if (vendor && p->vendorID == 0x10de)
        p->driverVersion = (550u << 22) | (54u << 14) | (14u << 6);
    if (device)
        p->deviceID = (unsigned)strtoul(device, NULL, 16);
    if (name && *name)
        snprintf(p->deviceName, sizeof(p->deviceName), "%s", name);
}
static VKAPI_ATTR void VKAPI_CALL properties(VkPhysicalDevice physical, VkPhysicalDeviceProperties *out) {
    Handle h;
    if (!lookup(physical, 1, &h))
        return;
    PFN_vkGetPhysicalDeviceProperties fn = (void *)proc(h.driver, h.instance, "vkGetPhysicalDeviceProperties");
    fn(physical, out);
    spoof(h.driver, out);
}
static VKAPI_ATTR void VKAPI_CALL properties2(VkPhysicalDevice physical, VkPhysicalDeviceProperties2 *out) {
    Handle h;
    if (!lookup(physical, 1, &h))
        return;
    PFN_vkGetPhysicalDeviceProperties2 fn = (void *)proc(h.driver, h.instance, "vkGetPhysicalDeviceProperties2");
    if (!fn)
        fn = (void *)proc(h.driver, h.instance, "vkGetPhysicalDeviceProperties2KHR");
    fn(physical, out);
    spoof(h.driver, &out->properties);
}
/* Wine probes this exported symbol to select Metal WSI. A GIPA-only
 * wrapper makes Wine select the legacy macOS surface path instead. */
EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkCreateMetalSurfaceEXT(VkInstance instance,
                                                              const VkMetalSurfaceCreateInfoEXT *ci,
                                                              const VkAllocationCallbacks *a, VkSurfaceKHR *out) {
    Handle h;
    if (!lookup(instance, 0, &h))
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkCreateMetalSurfaceEXT fn = (void *)proc(h.driver, instance, "vkCreateMetalSurfaceEXT");
    return fn ? fn(instance, ci, a, out) : VK_ERROR_EXTENSION_NOT_PRESENT;
}
EXPORT PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance instance, const char *name) {
    pthread_once(&once, init);
    if (!name)
        return NULL;

#define FN(n, f)                                                                                                       \
    if (!strcmp(name, n))                                                                                              \
    return (void *)f
    FN("vkGetInstanceProcAddr", vkGetInstanceProcAddr);
    FN("vkGetDeviceProcAddr", vkGetDeviceProcAddr);
    FN("vkCreateInstance", create_instance);
    FN("vkEnumerateInstanceVersion", version);
    FN("vkEnumerateInstanceExtensionProperties", extensions);
    FN("vkEnumerateInstanceLayerProperties", layers);
    Handle h;
    if (!instance || !lookup(instance, 0, &h))
        return NULL;
    FN("vkCreateMetalSurfaceEXT", vkCreateMetalSurfaceEXT);
    FN("vkDestroyInstance", destroy_instance);
    FN("vkDestroyDevice", destroy_device);
    FN("vkEnumeratePhysicalDevices", enumerate_devices);
    FN("vkEnumeratePhysicalDeviceGroups", enumerate_groups);
    FN("vkEnumeratePhysicalDeviceGroupsKHR", enumerate_groups);
    FN("vkCreateDevice", create_device);
    FN("vkGetPhysicalDeviceProperties", properties);
    FN("vkGetPhysicalDeviceProperties2", properties2);
    FN("vkGetPhysicalDeviceProperties2KHR", properties2);
    return proc(h.driver, instance, name);
}
EXPORT PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice device, const char *name) {
    pthread_once(&once, init);
    Handle h;
    if (!name || !lookup(device, 2, &h))
        return NULL;
    if (!strcmp(name, "vkDestroyDevice"))
        return (void *)destroy_device;
    PFN_vkGetDeviceProcAddr fn = (void *)proc(h.driver, h.instance, "vkGetDeviceProcAddr");
    PFN_vkVoidFunction result = fn ? fn(device, name) : NULL;
    if (!strcmp(name, "vkGetDeviceProcAddr"))
        return (void *)vkGetDeviceProcAddr;
    if (!result && fn) {
        size_t n = strlen(name);
        if (n > 3 && (!strcmp(name + n - 3, "KHR") || !strcmp(name + n - 3, "EXT"))) {
            char core[256];
            if (n - 3 < sizeof(core)) {
                memcpy(core, name, n - 3);
                core[n - 3] = 0;
                result = fn(device, core);
            }
        }
    }
    return result;
}
