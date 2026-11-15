#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#define INITGUID
#include "GraphicsProbeSupport.h"
#include <d3d11.h>
#include <d3d12.h>
#include <stdio.h>
#include <windows.h>
typedef HRESULT(WINAPI *create12_fn)(IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);
typedef HRESULT(WINAPI *create11_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *, UINT,
                                     UINT, ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
static int render11(ID3D11Device *device, ID3D11DeviceContext *context) {
    D3D11_TEXTURE2D_DESC desc = {0};
    desc.Width = 4;
    desc.Height = 4;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    ID3D11Texture2D *target = NULL, *readback = NULL;
    ID3D11RenderTargetView *view = NULL;
    HRESULT hr = ID3D11Device_CreateTexture2D(device, &desc, NULL, &target);
    if (FAILED(hr))
        return 3;
    hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &view);
    if (FAILED(hr))
        return 4;
    const float color[4] = {0.25f, 0.5f, 0.75f, 1};
    ID3D11DeviceContext_ClearRenderTargetView(context, view, color);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = ID3D11Device_CreateTexture2D(device, &desc, NULL, &readback);
    if (FAILED(hr))
        return 5;
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)readback, (ID3D11Resource *)target);
    D3D11_MAPPED_SUBRESOURCE map = {0};
    hr = ID3D11DeviceContext_Map(context, (ID3D11Resource *)readback, 0, D3D11_MAP_READ, 0, &map);
    if (FAILED(hr))
        return 6;
    const unsigned char *pixel = map.pData;
    printf("D3D11 readback=%u,%u,%u,%u\n", pixel[0], pixel[1], pixel[2], pixel[3]);
    fflush(stdout);
    int result = (pixel[0] < 63 || pixel[0] > 65 || pixel[1] < 127 || pixel[1] > 129 || pixel[2] < 190 ||
                  pixel[2] > 192 || pixel[3] != 255);
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);
    ID3D11RenderTargetView_Release(view);
    ID3D11Texture2D_Release(readback);
    ID3D11Texture2D_Release(target);
    return result;
}

typedef HRESULT(WINAPI *create_swap_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *, UINT,
                                        UINT, const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **, ID3D11Device **,
                                        D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
static int present11(HMODULE module) {
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = "ScotchPresentProbe";
    RegisterClassA(&wc);
    HWND window = CreateWindowA(wc.lpszClassName, "Scotch graphics validation", WS_OVERLAPPEDWINDOW, 0, 0, 96, 96, NULL,
                                NULL, wc.hInstance, NULL);
    if (!window)
        return 50;
    ShowWindow(window, SW_SHOWNOACTIVATE);
    DXGI_SWAP_CHAIN_DESC desc = {0};
    desc.BufferDesc.Width = 64;
    desc.BufferDesc.Height = 64;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.OutputWindow = window;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    create_swap_fn create = (create_swap_fn)GetProcAddress(module, "D3D11CreateDeviceAndSwapChain");
    if (!create)
        return 51;
    IDXGISwapChain *swap = NULL;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL level;
    HRESULT hr = create(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &desc, &swap, &device,
                        &level, &context);
    printf("D3D11 swapchain HRESULT=0x%08lx\n", (unsigned long)hr);
    fflush(stdout);
    if (FAILED(hr))
        return 52;
    ID3D11Texture2D *buffer = NULL;
    ID3D11RenderTargetView *view = NULL;
    hr = IDXGISwapChain_GetBuffer(swap, 0, &IID_ID3D11Texture2D, (void **)&buffer);
    if (FAILED(hr))
        return 53;
    hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)buffer, NULL, &view);
    if (FAILED(hr))
        return 54;
    const float color[] = {.25, .5, .75, 1};
    ID3D11DeviceContext_ClearRenderTargetView(context, view, color);
    hr = IDXGISwapChain_Present(swap, 1, 0);
    printf("D3D11 Present HRESULT=0x%08lx\n", (unsigned long)hr);
    fflush(stdout);
    Sleep(50);
    ID3D11RenderTargetView_Release(view);
    ID3D11Texture2D_Release(buffer);
    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    IDXGISwapChain_Release(swap);
    DestroyWindow(window);
    return FAILED(hr) ? 55 : 0;
}
static int render12(ID3D12Device *device) {
    ID3D12CommandQueue *queue = NULL;
    ID3D12CommandAllocator *allocator = NULL;
    ID3D12GraphicsCommandList *commands = NULL;
    ID3D12DescriptorHeap *heap = NULL;
    ID3D12Resource *target = NULL, *readback = NULL;
    ID3D12Fence *fence = NULL;
    D3D12_COMMAND_QUEUE_DESC q = {0};
    q.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    HRESULT hr = ID3D12Device_CreateCommandQueue(device, &q, &IID_ID3D12CommandQueue, (void **)&queue);
    if (FAILED(hr))
        return 30;
    hr = ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator,
                                             (void **)&allocator);
    if (FAILED(hr))
        return 31;
    hr = ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, NULL,
                                        &IID_ID3D12GraphicsCommandList, (void **)&commands);
    if (FAILED(hr))
        return 32;
    D3D12_HEAP_PROPERTIES gpu = {0};
    gpu.Type = D3D12_HEAP_TYPE_DEFAULT;
    gpu.CreationNodeMask = gpu.VisibleNodeMask = 1;
    D3D12_RESOURCE_DESC texture = {0};
    texture.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    texture.Width = 4;
    texture.Height = 4;
    texture.DepthOrArraySize = 1;
    texture.MipLevels = 1;
    texture.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    texture.SampleDesc.Count = 1;
    texture.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_CLEAR_VALUE clear = {0};
    clear.Format = texture.Format;
    clear.Color[0] = .25f;
    clear.Color[1] = .5f;
    clear.Color[2] = .75f;
    clear.Color[3] = 1;
    hr = ID3D12Device_CreateCommittedResource(device, &gpu, D3D12_HEAP_FLAG_NONE, &texture,
                                              D3D12_RESOURCE_STATE_RENDER_TARGET, &clear, &IID_ID3D12Resource,
                                              (void **)&target);
    if (FAILED(hr))
        return 33;
    D3D12_DESCRIPTOR_HEAP_DESC hd = {0};
    hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    hd.NumDescriptors = 1;
    hr = ID3D12Device_CreateDescriptorHeap(device, &hd, &IID_ID3D12DescriptorHeap, (void **)&heap);
    if (FAILED(hr))
        return 34;
    D3D12_CPU_DESCRIPTOR_HANDLE handle = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(heap);
    ID3D12Device_CreateRenderTargetView(device, target, NULL, handle);
    ID3D12GraphicsCommandList_ClearRenderTargetView(commands, handle, clear.Color, 0, NULL);
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint = {0};
    UINT rows;
    UINT64 rowBytes, bytes;
    ID3D12Device_GetCopyableFootprints(device, &texture, 0, 1, 0, &footprint, &rows, &rowBytes, &bytes);
    D3D12_HEAP_PROPERTIES cpu = {0};
    cpu.Type = D3D12_HEAP_TYPE_READBACK;
    cpu.CreationNodeMask = cpu.VisibleNodeMask = 1;
    D3D12_RESOURCE_DESC buffer = {0};
    buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer.Width = bytes;
    buffer.Height = 1;
    buffer.DepthOrArraySize = 1;
    buffer.MipLevels = 1;
    buffer.SampleDesc.Count = 1;
    buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    hr = ID3D12Device_CreateCommittedResource(device, &cpu, D3D12_HEAP_FLAG_NONE, &buffer,
                                              D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource,
                                              (void **)&readback);
    if (FAILED(hr))
        return 35;
    D3D12_RESOURCE_BARRIER barrier = {0};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = target;
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    ID3D12GraphicsCommandList_ResourceBarrier(commands, 1, &barrier);
    D3D12_TEXTURE_COPY_LOCATION src = {0}, dst = {0};
    src.pResource = target;
    src.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    dst.pResource = readback;
    dst.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    dst.PlacedFootprint = footprint;
    ID3D12GraphicsCommandList_CopyTextureRegion(commands, &dst, 0, 0, 0, &src, NULL);
    hr = ID3D12GraphicsCommandList_Close(commands);
    if (FAILED(hr))
        return 36;
    ID3D12CommandList *lists[] = {(ID3D12CommandList *)commands};
    ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);
    hr = ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
    if (FAILED(hr))
        return 37;
    HANDLE event = CreateEvent(NULL, FALSE, FALSE, NULL);
    ID3D12CommandQueue_Signal(queue, fence, 1);
    ID3D12Fence_SetEventOnCompletion(fence, 1, event);
    if (WaitForSingleObject(event, 10000) != WAIT_OBJECT_0)
        return 38;
    void *data = NULL;
    D3D12_RANGE range = {0, (SIZE_T)bytes};
    hr = ID3D12Resource_Map(readback, 0, &range, &data);
    if (FAILED(hr))
        return 39;
    const unsigned char *pixel = (const unsigned char *)data + footprint.Offset;
    printf("D3D12 readback=%u,%u,%u,%u\n", pixel[0], pixel[1], pixel[2], pixel[3]);
    fflush(stdout);
    int result = pixel[0] < 63 || pixel[0] > 65 || pixel[1] < 127 || pixel[1] > 129 || pixel[2] < 190 ||
                 pixel[2] > 192 || pixel[3] != 255;
    D3D12_RANGE written = {0, 0};
    ID3D12Resource_Unmap(readback, 0, &written);
    CloseHandle(event);
    ID3D12Fence_Release(fence);
    ID3D12Resource_Release(readback);
    ID3D12Resource_Release(target);
    ID3D12DescriptorHeap_Release(heap);
    ID3D12GraphicsCommandList_Release(commands);
    ID3D12CommandAllocator_Release(allocator);
    ID3D12CommandQueue_Release(queue);
    return result;
}
int main(int argc, char **argv) {
    SetUnhandledExceptionFilter(scotch_graphics_fault);
    int only11 = argc > 1 && !strcmp(argv[1], "--d3d11");
    HMODULE a = only11 ? NULL : LoadLibraryA("d3d12.dll"), b = LoadLibraryA("d3d11.dll");
    printf("Load d3d12=%p d3d11=%p error=%lu\n", a, b, GetLastError());
    fflush(stdout);
    if ((!a && !only11) || !b)
        return 1;
    create12_fn f12 = (create12_fn)GetProcAddress(a, "D3D12CreateDevice");
    create11_fn f11 = (create11_fn)GetProcAddress(b, "D3D11CreateDevice");
    if ((!f12 && !only11) || !f11)
        return 2;
    ID3D12Device *device12 = NULL;
    HRESULT h12 = only11 ? S_OK : f12(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device12);
    printf("D3D12CreateDevice HRESULT=0x%08lx device=%p\n", (unsigned long)h12, device12);
    fflush(stdout);
    ID3D11Device *device11 = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL level;
    HRESULT h11 = f11(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &device11, &level, &context);
    printf("D3D11CreateDevice HRESULT=0x%08lx device=%p feature=0x%x\n", (unsigned long)h11, device11, level);
    fflush(stdout);
    printf("vkd3d=%p wined3d=%p vulkan=%p\n", GetModuleHandleA("vkd3d.dll"), GetModuleHandleA("wined3d.dll"),
           GetModuleHandleA("vulkan-1.dll"));
    int rendered = SUCCEEDED(h11) && device11 && context ? render11(device11, context) : 1;
    if (!only11 && device12 && !rendered)
        rendered = render12(device12);
    if (!rendered)
        rendered = present11(b);
    if (context)
        ID3D11DeviceContext_Release(context);
    if (device11)
        ID3D11Device_Release(device11);
    if (device12)
        ID3D12Device_Release(device12);
    return FAILED(h11) || FAILED(h12) || rendered;
}
