#include "GraphicsProbeSupport.h"
#include <GL/gl.h>
#include <GL/glext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#define LOAD(name, type)                                                                                               \
    type name = (type)wglGetProcAddress(#name);                                                                        \
    if (!name) {                                                                                                       \
        printf("Missing %s\n", #name);                                                                                 \
        return 20;                                                                                                     \
    }
static GLuint compile(GLenum stage, const char *source) {
    PFNGLCREATESHADERPROC create = (void *)wglGetProcAddress("glCreateShader");
    PFNGLSHADERSOURCEPROC set = (void *)wglGetProcAddress("glShaderSource");
    PFNGLCOMPILESHADERPROC compile = (void *)wglGetProcAddress("glCompileShader");
    PFNGLGETSHADERIVPROC get = (void *)wglGetProcAddress("glGetShaderiv");
    PFNGLGETSHADERINFOLOGPROC log = (void *)wglGetProcAddress("glGetShaderInfoLog");
    GLuint shader = create(stage);
    set(shader, 1, &source, NULL);
    compile(shader);
    GLint ok = 0;
    get(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char msg[4096];
        log(shader, sizeof(msg), NULL, msg);
        printf("Shader failed: %s\n", msg);
        return 0;
    }
    return shader;
}
static int shader_tests(void) {
    LOAD(glCreateProgram, PFNGLCREATEPROGRAMPROC);
    LOAD(glAttachShader, PFNGLATTACHSHADERPROC);
    LOAD(glLinkProgram, PFNGLLINKPROGRAMPROC);
    LOAD(glGetProgramiv, PFNGLGETPROGRAMIVPROC);
    LOAD(glGetProgramInfoLog, PFNGLGETPROGRAMINFOLOGPROC);
    LOAD(glUseProgram, PFNGLUSEPROGRAMPROC);
    LOAD(glCreateBuffers, PFNGLCREATEBUFFERSPROC);
    LOAD(glNamedBufferStorage, PFNGLNAMEDBUFFERSTORAGEPROC);
    LOAD(glGetNamedBufferSubData, PFNGLGETNAMEDBUFFERSUBDATAPROC);
    LOAD(glBindBufferBase, PFNGLBINDBUFFERBASEPROC);
    LOAD(glDispatchCompute, PFNGLDISPATCHCOMPUTEPROC);
    LOAD(glMemoryBarrier, PFNGLMEMORYBARRIERPROC);
    LOAD(glCreateTextures, PFNGLCREATETEXTURESPROC);
    LOAD(glTextureBuffer, PFNGLTEXTUREBUFFERPROC);
    LOAD(glBindTextureUnit, PFNGLBINDTEXTUREUNITPROC);
    LOAD(glTransformFeedbackVaryings, PFNGLTRANSFORMFEEDBACKVARYINGSPROC);
    LOAD(glBeginTransformFeedback, PFNGLBEGINTRANSFORMFEEDBACKPROC);
    LOAD(glEndTransformFeedback, PFNGLENDTRANSFORMFEEDBACKPROC);
    LOAD(glCreateVertexArrays, PFNGLCREATEVERTEXARRAYSPROC);
    LOAD(glBindVertexArray, PFNGLBINDVERTEXARRAYPROC);
    const char *cs = "#version 450\nlayout(local_size_x=1) in;layout(std430,binding=0) buffer Out{uint "
                     "result;};layout(binding=1) uniform samplerBuffer src;void main(){vec3 "
                     "v=texelFetch(src,1).xyz;result=uint(round(dot(v,vec3(1000))))+uint(textureSize(src))*10000u;}";
    GLuint shader = compile(GL_COMPUTE_SHADER, cs);
    if (!shader)
        return 21;
    GLuint program = glCreateProgram();
    glAttachShader(program, shader);
    glLinkProgram(program);
    GLint ok = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char msg[4096];
        glGetProgramInfoLog(program, sizeof(msg), NULL, msg);
        printf("Compute link failed %s\n", msg);
        return 22;
    }
    GLuint buffers[3];
    glCreateBuffers(3, buffers);
    GLuint initial = 0;
    glNamedBufferStorage(buffers[0], sizeof(initial), &initial, 0);
    const GLfloat rgb[] = {10, 20, 30, .25, .5, .75};
    glNamedBufferStorage(buffers[1], sizeof(rgb), rgb, 0);
    GLuint tex;
    glCreateTextures(GL_TEXTURE_BUFFER, 1, &tex);
    glTextureBuffer(tex, GL_RGB32F, buffers[1]);
    glBindTextureUnit(1, tex);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffers[0]);
    glUseProgram(program);
    glDispatchCompute(1, 1, 1);
    glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
    GLuint result = 0;
    glGetNamedBufferSubData(buffers[0], 0, sizeof(result), &result);
    printf("OpenGL 4.5 DSA, compute, RGB32 fetch and textureSize=%u expected=21500 error=0x%x\n", result, glGetError());
    fflush(stdout);
    if (result != 21500)
        return 23;
    const char *vs =
        "#version 450\nout float captured;void main(){captured=float(gl_VertexID*2+3);gl_Position=vec4(0,0,0,1);}";
    shader = compile(GL_VERTEX_SHADER, vs);
    if (!shader)
        return 24;
    program = glCreateProgram();
    glAttachShader(program, shader);
    const char *varyings[] = {"captured"};
    glTransformFeedbackVaryings(program, 1, varyings, GL_INTERLEAVED_ATTRIBS);
    glLinkProgram(program);
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok)
        return 25;
    glNamedBufferStorage(buffers[2], 4 * sizeof(float), NULL, 0);
    glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, buffers[2]);
    GLuint vao;
    glCreateVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glUseProgram(program);
    glEnable(GL_RASTERIZER_DISCARD);
    glBeginTransformFeedback(GL_POINTS);
    glDrawArrays(GL_POINTS, 0, 4);
    glEndTransformFeedback();
    glDisable(GL_RASTERIZER_DISCARD);
    glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
    GLfloat values[4] = {0};
    glGetNamedBufferSubData(buffers[2], 0, sizeof(values), values);
    printf("OpenGL transform feedback=%g,%g,%g,%g error=0x%x\n", values[0], values[1], values[2], values[3],
           glGetError());
    fflush(stdout);
    return values[0] != 3 || values[1] != 5 || values[2] != 7 || values[3] != 9 ? 26 : 0;
}
int main(void) {
    SetUnhandledExceptionFilter(scotch_graphics_fault);
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = "ScotchZinkSmoke";
    wc.style = CS_OWNDC;
    RegisterClassA(&wc);
    HWND window = CreateWindowA(wc.lpszClassName, "Scotch Zink smoke", WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL,
                                wc.hInstance, NULL);
    if (!window) {
        printf("CreateWindow error=%lu\n", GetLastError());
        return 1;
    }
    ShowWindow(window, SW_SHOWNOACTIVATE);
    HDC dc = GetDC(window);
    PIXELFORMATDESCRIPTOR p = {0};
    p.nSize = sizeof(p);
    p.nVersion = 1;
    p.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    p.iPixelType = PFD_TYPE_RGBA;
    p.cColorBits = 24;
    p.cDepthBits = 24;
    int format = ChoosePixelFormat(dc, &p);
    if (!format || !SetPixelFormat(dc, format, &p)) {
        printf("PixelFormat error=%lu\n", GetLastError());
        return 2;
    }
    HGLRC context = wglCreateContext(dc);
    if (!context || !wglMakeCurrent(dc, context)) {
        printf("OpenGL context error=%lu\n", GetLastError());
        return 3;
    }
    typedef HGLRC(WINAPI * CreateContextAttribs)(HDC, HGLRC, const int *);
    CreateContextAttribs create = (CreateContextAttribs)wglGetProcAddress("wglCreateContextAttribsARB");
    if (!create) {
        printf("No core context API\n");
        return 4;
    }
    printf("GLSL=%s\n", glGetString(0x8B8C));
    printf("Legacy context version=%s renderer=%s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
    fflush(stdout);
    const char *ext = (const char *)glGetString(GL_EXTENSIONS);
    const char *needs[] = {"GL_ARB_texture_buffer_object_rgb32",
                           "GL_ARB_gpu_shader_fp64",
                           "GL_ARB_tessellation_shader",
                           "GL_ARB_gpu_shader5",
                           "GL_ARB_sample_shading",
                           "GL_ARB_transform_feedback2",
                           "GL_ARB_transform_feedback3",
                           "GL_ARB_shader_subroutine",
                           "GL_ARB_draw_indirect",
                           "GL_ARB_draw_buffers_blend",
                           "GL_ARB_texture_cube_map_array",
                           "GL_ARB_texture_gather",
                           "GL_ARB_texture_query_lod"};
    for (unsigned i = 0; i < sizeof(needs) / sizeof(needs[0]); i++)
        printf("%s=%d\n", needs[i], ext && strstr(ext, needs[i]) != NULL);
    fflush(stdout);
    const int attributes[] = {0x2091, 4, 0x2092, 5, 0x9126, 1, 0};
    HGLRC core = create(dc, NULL, attributes);
    if (!core) {
        printf("OpenGL 4.5 core context failed error=%lu\n", GetLastError());
        return 5;
    }
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(context);
    context = core;
    if (!wglMakeCurrent(dc, context))
        return 6;
    const char *version = (const char *)glGetString(GL_VERSION), *renderer = (const char *)glGetString(GL_RENDERER);
    printf("OpenGL version=%s\nrenderer=%s\n", version ? version : "NULL", renderer ? renderer : "NULL");
    fflush(stdout);
    glClearColor(0.2f, 0.4f, 0.6f, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    unsigned char pixel[4] = {0};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    printf("OpenGL readback=%u,%u,%u,%u error=0x%x\n", pixel[0], pixel[1], pixel[2], pixel[3], glGetError());
    fflush(stdout);
    if (!SwapBuffers(dc)) {
        printf("OpenGL SwapBuffers failed error=%lu\n", GetLastError());
        return 27;
    }
    printf("OpenGL SwapBuffers succeeded\n");
    int result = shader_tests();
    result = result ? result
                    : (!version || !renderer || !strstr(renderer, "zink") || atof(version) < 4.5f || pixel[0] < 50 ||
                       pixel[0] > 52 || pixel[1] < 101 || pixel[1] > 103 || pixel[2] < 152 || pixel[2] > 154);
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(context);
    ReleaseDC(window, dc);
    DestroyWindow(window);
    return result;
}
