#ifndef SCOTCH_GRAPHICS_PROBE_SUPPORT
#define SCOTCH_GRAPHICS_PROBE_SUPPORT
#include <stdint.h>
#include <stdio.h>
#include <windows.h>
static LONG WINAPI scotch_graphics_fault(EXCEPTION_POINTERS *e) {
#ifdef _WIN64
    uintptr_t stack = e->ContextRecord->Rsp, info = e->ContextRecord->Rdx;
#else
    uintptr_t stack = e->ContextRecord->Esp, info = ((uintptr_t *)stack)[2];
#endif
    MEMORY_BASIC_INFORMATION memory = {0};
    unsigned type = 0xffffffff;
    if (info && VirtualQuery((void *)info, &memory, sizeof(memory)) && memory.State == MEM_COMMIT &&
        !(memory.Protect & (PAGE_NOACCESS | PAGE_GUARD)))
        type = *(unsigned *)info;
    uintptr_t caller = *(uintptr_t *)stack;
    HMODULE module = NULL;
    char name[MAX_PATH] = {0};
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)caller, &module);
    if (module)
        GetModuleFileNameA(module, name, sizeof(name));
    printf("Graphics exception=0x%08lx VkCreateInfoType=%u caller=%s+0x%llx\n", e->ExceptionRecord->ExceptionCode, type,
           name, (unsigned long long)(caller - (uintptr_t)module));
    fflush(stdout);
    ExitProcess(97);
    return EXCEPTION_EXECUTE_HANDLER;
}
#endif
