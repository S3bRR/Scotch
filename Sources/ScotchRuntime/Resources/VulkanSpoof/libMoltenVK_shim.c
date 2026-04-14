#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VK_MAX_PHYSICAL_DEVICE_NAME_SIZE 256

typedef struct VkInstance_T *VkInstance;
typedef struct VkPhysicalDevice_T *VkPhysicalDevice;
typedef struct VkDevice_T *VkDevice;
typedef int32_t VkResult;
typedef void (*PFN_vkVoidFunction)(void);

typedef struct VkPhysicalDevicePropertiesSpoofView {
    uint32_t apiVersion;
    uint32_t driverVersion;
    uint32_t vendorID;
    uint32_t deviceID;
    uint32_t deviceType;
    char deviceName[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
} VkPhysicalDevicePropertiesSpoofView;

typedef struct VkPhysicalDeviceProperties2SpoofView {
    uint32_t sType;
    void *pNext;
    VkPhysicalDevicePropertiesSpoofView properties;
} VkPhysicalDeviceProperties2SpoofView;

typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(VkInstance, const char *);
typedef PFN_vkVoidFunction (*PFN_vkGetDeviceProcAddr)(VkDevice, const char *);
typedef void (*PFN_vkGetPhysicalDeviceProperties)(VkPhysicalDevice, VkPhysicalDevicePropertiesSpoofView *);
typedef void (*PFN_vkGetPhysicalDeviceProperties2)(VkPhysicalDevice, VkPhysicalDeviceProperties2SpoofView *);
typedef PFN_vkVoidFunction (*PFN_vkIcdGetPhysicalDeviceProcAddr)(VkInstance, const char *);
typedef VkResult (*PFN_vkIcdNegotiateLoaderICDInterfaceVersion)(uint32_t *);

#define SCOTCH_EXPORT __attribute__((visibility("default")))

_Static_assert(offsetof(VkPhysicalDevicePropertiesSpoofView, vendorID) == 8, "Unexpected vendorID offset");
_Static_assert(offsetof(VkPhysicalDevicePropertiesSpoofView, deviceID) == 12, "Unexpected deviceID offset");
_Static_assert(offsetof(VkPhysicalDevicePropertiesSpoofView, deviceName) == 20, "Unexpected deviceName offset");
_Static_assert(offsetof(VkPhysicalDeviceProperties2SpoofView, properties.vendorID) == 24,
               "Unexpected VkPhysicalDeviceProperties2 vendorID offset");

static pthread_once_t g_init_once = PTHREAD_ONCE_INIT;
static void *g_real_moltenvk;
static PFN_vkGetInstanceProcAddr g_real_gipa;
static PFN_vkGetDeviceProcAddr g_real_gdpa;
static PFN_vkGetPhysicalDeviceProperties g_real_get_physical_device_properties;
static PFN_vkGetPhysicalDeviceProperties2 g_real_get_physical_device_properties2;
static PFN_vkIcdGetPhysicalDeviceProcAddr g_real_icd_get_physical_device_proc_addr;
static PFN_vkIcdNegotiateLoaderICDInterfaceVersion g_real_icd_negotiate_loader_icd_interface_version;

static bool g_spoof_enabled;
static uint32_t g_spoof_vendor_id;
static uint32_t g_spoof_device_id;
static uint32_t g_spoof_driver_version;
static char g_spoof_device_name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
static FILE *g_log;

SCOTCH_EXPORT PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance instance, const char *name);
SCOTCH_EXPORT PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice device, const char *name);

static uint32_t parse_hex_u32_env(const char *name) {
    const char *value = getenv(name);
    char *end = NULL;
    unsigned long parsed;

    if (!value || !*value) return 0;

    parsed = strtoul(value, &end, 16);
    if (end == value) return 0;
    if (parsed > UINT_MAX) return UINT_MAX;
    return (uint32_t)parsed;
}

static uint32_t driver_version_for_vendor(uint32_t vendor) {
    if (vendor == 0x1002) return (23u << 22) | (12u << 12) | 1u;
    if (vendor == 0x10de) return (550u << 22) | (54u << 14) | (14u << 6);
    return 0;
}

static void apply_spoof(VkPhysicalDevicePropertiesSpoofView *properties) {
    if (!properties || !g_spoof_enabled) return;

    if (g_spoof_vendor_id) properties->vendorID = g_spoof_vendor_id;
    if (g_spoof_device_id) properties->deviceID = g_spoof_device_id;
    if (g_spoof_driver_version) properties->driverVersion = g_spoof_driver_version;
    if (g_spoof_device_name[0]) {
        strncpy(properties->deviceName, g_spoof_device_name, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE - 1);
        properties->deviceName[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE - 1] = '\0';
    }
    if (g_log) {
        fprintf(g_log, "spoof: vendor=0x%x device=0x%x driver=0x%x name=%s\n",
                properties->vendorID, properties->deviceID, properties->driverVersion, properties->deviceName);
        fflush(g_log);
    }
}

static void shim_init_once(void) {
    const char *real_path = getenv("SCOTCH_REAL_MOLTENVK_PATH");
    const char *spoof_name = getenv("SCOTCH_GPU_DEVICE_NAME");

    g_log = fopen("/tmp/scotch_gpu_spoof.log", "w");

    g_spoof_vendor_id = parse_hex_u32_env("SCOTCH_GPU_VENDOR_ID");
    g_spoof_device_id = parse_hex_u32_env("SCOTCH_GPU_DEVICE_ID");
    g_spoof_driver_version = driver_version_for_vendor(g_spoof_vendor_id);

    if (spoof_name && *spoof_name) {
        strncpy(g_spoof_device_name, spoof_name, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE - 1);
        g_spoof_device_name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE - 1] = '\0';
    }
    g_spoof_enabled = (g_spoof_vendor_id != 0) || (g_spoof_device_id != 0) || (g_spoof_device_name[0] != '\0');

    if (g_log) {
        fprintf(g_log, "init: vendor=0x%x device=0x%x driver=0x%x name=%s enabled=%d\n",
                g_spoof_vendor_id, g_spoof_device_id, g_spoof_driver_version, g_spoof_device_name, g_spoof_enabled);
        fflush(g_log);
    }

    if (!real_path || !*real_path) return;

    g_real_moltenvk = dlopen(real_path, RTLD_NOW | RTLD_LOCAL);
    if (!g_real_moltenvk) return;

    g_real_gipa = (PFN_vkGetInstanceProcAddr)dlsym(g_real_moltenvk, "vkGetInstanceProcAddr");
    g_real_gdpa = (PFN_vkGetDeviceProcAddr)dlsym(g_real_moltenvk, "vkGetDeviceProcAddr");
    g_real_icd_get_physical_device_proc_addr = (PFN_vkIcdGetPhysicalDeviceProcAddr)dlsym(
        g_real_moltenvk, "vk_icdGetPhysicalDeviceProcAddr");
    g_real_icd_negotiate_loader_icd_interface_version = (PFN_vkIcdNegotiateLoaderICDInterfaceVersion)dlsym(
        g_real_moltenvk, "vk_icdNegotiateLoaderICDInterfaceVersion");
}

static inline void ensure_initialized(void) {
    pthread_once(&g_init_once, shim_init_once);
}

static void shim_vkGetPhysicalDeviceProperties(
    VkPhysicalDevice physical_device, VkPhysicalDevicePropertiesSpoofView *properties
) {
    ensure_initialized();

    if (!g_real_get_physical_device_properties && g_real_gipa) {
        g_real_get_physical_device_properties = (PFN_vkGetPhysicalDeviceProperties)g_real_gipa(
            NULL, "vkGetPhysicalDeviceProperties");
    }
    if (!g_real_get_physical_device_properties) return;

    g_real_get_physical_device_properties(physical_device, properties);
    apply_spoof(properties);
}

static void shim_vkGetPhysicalDeviceProperties2(
    VkPhysicalDevice physical_device, VkPhysicalDeviceProperties2SpoofView *properties2
) {
    ensure_initialized();

    if (!g_real_get_physical_device_properties2 && g_real_gipa) {
        g_real_get_physical_device_properties2 = (PFN_vkGetPhysicalDeviceProperties2)g_real_gipa(
            NULL, "vkGetPhysicalDeviceProperties2");
    }
    if (!g_real_get_physical_device_properties2) {
        if (!properties2) return;
        if (g_real_get_physical_device_properties) {
            g_real_get_physical_device_properties(physical_device, &properties2->properties);
            apply_spoof(&properties2->properties);
        }
        return;
    }

    g_real_get_physical_device_properties2(physical_device, properties2);
    if (properties2) apply_spoof(&properties2->properties);
}

static PFN_vkVoidFunction maybe_wrap_instance_proc(const char *name, PFN_vkVoidFunction real_proc) {
    if (!name || !real_proc) return real_proc;
    if (!g_spoof_enabled) return real_proc;

    if (!strcmp(name, "vkGetPhysicalDeviceProperties")) {
        g_real_get_physical_device_properties = (PFN_vkGetPhysicalDeviceProperties)real_proc;
        return (PFN_vkVoidFunction)shim_vkGetPhysicalDeviceProperties;
    }

    if (!strcmp(name, "vkGetPhysicalDeviceProperties2") || !strcmp(name, "vkGetPhysicalDeviceProperties2KHR")) {
        g_real_get_physical_device_properties2 = (PFN_vkGetPhysicalDeviceProperties2)real_proc;
        return (PFN_vkVoidFunction)shim_vkGetPhysicalDeviceProperties2;
    }

    if (!strcmp(name, "vkGetInstanceProcAddr")) return (PFN_vkVoidFunction)vkGetInstanceProcAddr;
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)vkGetDeviceProcAddr;

    return real_proc;
}

SCOTCH_EXPORT PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance instance, const char *name) {
    PFN_vkVoidFunction real_proc;

    ensure_initialized();
    if (!g_real_gipa) return NULL;

    real_proc = g_real_gipa(instance, name);
    return maybe_wrap_instance_proc(name, real_proc);
}

SCOTCH_EXPORT PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice device, const char *name) {
    ensure_initialized();
    if (!g_real_gdpa) return NULL;
    return g_real_gdpa(device, name);
}

SCOTCH_EXPORT PFN_vkVoidFunction vk_icdGetInstanceProcAddr(VkInstance instance, const char *name) {
    return vkGetInstanceProcAddr(instance, name);
}

SCOTCH_EXPORT PFN_vkVoidFunction vk_icdGetPhysicalDeviceProcAddr(VkInstance instance, const char *name) {
    PFN_vkVoidFunction real_proc;

    ensure_initialized();

    if (!g_real_icd_get_physical_device_proc_addr) return NULL;
    real_proc = g_real_icd_get_physical_device_proc_addr(instance, name);
    return maybe_wrap_instance_proc(name, real_proc);
}

SCOTCH_EXPORT VkResult vk_icdNegotiateLoaderICDInterfaceVersion(uint32_t *supported_version) {
    ensure_initialized();

    if (!g_real_icd_negotiate_loader_icd_interface_version) return -9;
    return g_real_icd_negotiate_loader_icd_interface_version(supported_version);
}
