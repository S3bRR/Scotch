#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <vulkan/vulkan.h>
static void check(int ok, const char *message) {
    if (!ok) {
        fprintf(stderr, "FAILED: %s\n", message);
        exit(1);
    }
}
int main(int argc, char **argv) {
    check(argc == 2, "pass the extracted Graphics/libvulkan.1.dylib path");
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    check(library != NULL, dlerror());
    PFN_vkGetInstanceProcAddr gipa = (void *)dlsym(library, "vkGetInstanceProcAddr");
    check(gipa != NULL, "GIPA");
    for (unsigned preset = 0; preset < 3; preset++) {
        const char *vendor = preset == 0 ? "1002" : preset == 1 ? "10de" : NULL;
        if (vendor) {
            setenv("SCOTCH_GPU_VENDOR_ID", vendor, 1);
            setenv("SCOTCH_GPU_DEVICE_ID", "744c", 1);
            setenv("SCOTCH_GPU_DEVICE_NAME", "Scotch identity probe", 1);
        } else {
            unsetenv("SCOTCH_GPU_VENDOR_ID");
            unsetenv("SCOTCH_GPU_DEVICE_ID");
            unsetenv("SCOTCH_GPU_DEVICE_NAME");
        }
        VkInstance instances[2] = {0};
        for (unsigned driver = 0; driver < 2; driver++) {
            VkApplicationInfo ai = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                                    .pApplicationName = "Scotch identity probe",
                                    .pEngineName = driver ? "zink" : "Wine",
                                    .apiVersion = VK_API_VERSION_1_3};
            VkInstanceCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ai};
            PFN_vkCreateInstance create = (void *)gipa(NULL, "vkCreateInstance");
            check(create(&ci, NULL, &instances[driver]) == VK_SUCCESS, "create instance");
            PFN_vkEnumeratePhysicalDevices enumerate = (void *)gipa(instances[driver], "vkEnumeratePhysicalDevices");
            VkPhysicalDevice devices[8];
            uint32_t count = 8;
            check(enumerate(instances[driver], &count, devices) == VK_SUCCESS && count > 0, "enumerate devices");
            PFN_vkGetPhysicalDeviceProperties2 properties =
                (void *)gipa(instances[driver], "vkGetPhysicalDeviceProperties2");
            VkPhysicalDeviceProperties2 p = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
            properties(devices[0], &p);
            unsigned expected = driver || !vendor ? 0x106b : preset == 0 ? 0x1002 : 0x10de;
            check(p.properties.vendorID == expected, "driver-specific vendor identity");
            if (!driver && vendor) {
                unsigned version =
                    preset == 0 ? (23u << 22) | (12u << 12) | 1u : (550u << 22) | (54u << 14) | (14u << 6);
                check(p.properties.driverVersion == version, "compatibility driver version");
            }
        }
        for (unsigned driver = 0; driver < 2; driver++) {
            PFN_vkDestroyInstance destroy = (void *)gipa(instances[driver], "vkDestroyInstance");
            destroy(instances[driver], NULL);
        }
    }
    puts("Passed: simultaneous driver instances preserve AMD/NVIDIA compatibility identities and driver versions, "
         "while Zink retains the actual Apple GPU.");
}
