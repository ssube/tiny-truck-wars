#!/usr/bin/env python3
"""Counts the texture units each compiled shader program's fragment stage uses.

Reads the programs Mesa captured while the game ran (MESA_SHADER_CAPTURE_PATH,
*.shader_test: the exact GLSL Godot gave the driver, its own code and ours),
links each one again in an offscreen GL context, and asks the driver which
sampler uniforms the fragment stage references: the count a GL driver checks
against GL_MAX_TEXTURE_IMAGE_UNITS. Also counts the samplers the fragment
source names anywhere (GLSL's static use, called or not): what ANGLE counts,
which is what Chrome, Edge and most Windows browsers and drivers run on.
Both are checked against the limit.

    tools/shader_units.py DIR [--limit 16]

Exits 1 if any program's count, either way, is over the limit. Uses only the
standard library (ctypes over libEGL and libGL; a surfaceless Mesa context).
"""
import argparse
import ctypes
import pathlib
import re
import sys

EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
EGL_OPENGL_API = 0x30A2
EGL_CONTEXT_MAJOR_VERSION = 0x3098
EGL_CONTEXT_MINOR_VERSION = 0x30FB
EGL_CONTEXT_OPENGL_PROFILE_MASK = 0x30FD
EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT = 0x1
EGL_NONE = 0x3038
EGL_NO_SURFACE = ctypes.c_void_p(0)

GL_FRAGMENT_SHADER = 0x8B30
GL_VERTEX_SHADER = 0x8B31
GL_COMPILE_STATUS = 0x8B81
GL_LINK_STATUS = 0x8B82
GL_UNIFORM = 0x92E1
GL_ACTIVE_RESOURCES = 0x92F5
GL_TYPE = 0x92FA
GL_ARRAY_SIZE = 0x92FB
GL_REFERENCED_BY_FRAGMENT_SHADER = 0x930A
GL_MAX_TEXTURE_IMAGE_UNITS = 0x8872

# Every GLSL sampler type's enum (sampler*, isampler*, usampler*).
SAMPLER_TYPES = {
    0x8B5D, 0x8B5E, 0x8B5F, 0x8B60, 0x8B61, 0x8B62, 0x8B63, 0x8B64,
    0x8DC0, 0x8DC1, 0x8DC4, 0x8DC5, 0x8DC9, 0x8DCA, 0x8DCB, 0x8DCC,
    0x8DCD, 0x8DCE, 0x8DCF, 0x8DD1, 0x8DD2, 0x8DD3, 0x8DD4, 0x8DD6,
    0x8DD7, 0x8DD8, 0x900C, 0x900D, 0x900E, 0x900F, 0x9108, 0x9109,
    0x910A, 0x910B, 0x910C, 0x910D, 0x8D66, 0x8DC2, 0x8DC3, 0x8DC8,
    0x8DD0, 0x8DD5, 0x9055, 0x9056, 0x9057,
}


def context():
    egl = ctypes.CDLL("libEGL.so.1")
    gl = ctypes.CDLL("libGL.so.1")
    egl.eglGetPlatformDisplay.restype = ctypes.c_void_p
    egl.eglGetPlatformDisplay.argtypes = [ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p]
    egl.eglCreateContext.restype = ctypes.c_void_p
    egl.eglCreateContext.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
    egl.eglMakeCurrent.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    egl.eglInitialize.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    egl.eglBindAPI.argtypes = [ctypes.c_uint]
    display = egl.eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, None, None)
    if not display or not egl.eglInitialize(display, None, None):
        sys.exit("No EGL display (needs Mesa's surfaceless platform).")
    egl.eglBindAPI(EGL_OPENGL_API)
    attributes = (ctypes.c_int * 7)(EGL_CONTEXT_MAJOR_VERSION, 4, EGL_CONTEXT_MINOR_VERSION, 3,
                                    EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE)
    ctx = egl.eglCreateContext(display, None, None, attributes)
    if not ctx or not egl.eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx):
        sys.exit("No GL 4.3 context.")
    gl.glCreateShader.restype = ctypes.c_uint
    gl.glCreateProgram.restype = ctypes.c_uint
    gl.glGetProgramResourceName.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_char_p]
    return gl


def compile_shader(gl, kind, source):
    shader = gl.glCreateShader(kind)
    text = ctypes.c_char_p(source.encode())
    gl.glShaderSource(shader, 1, ctypes.byref(text), None)
    gl.glCompileShader(shader)
    ok = ctypes.c_int()
    gl.glGetShaderiv(shader, GL_COMPILE_STATUS, ctypes.byref(ok))
    if not ok.value:
        log = ctypes.create_string_buffer(8192)
        gl.glGetShaderInfoLog(shader, 8192, None, log)
        raise RuntimeError(log.value.decode(errors="replace"))
    return shader


def referenced_samplers(gl, vertex, fragment):
    program = gl.glCreateProgram()
    gl.glAttachShader(program, compile_shader(gl, GL_VERTEX_SHADER, vertex))
    gl.glAttachShader(program, compile_shader(gl, GL_FRAGMENT_SHADER, fragment))
    gl.glLinkProgram(program)
    ok = ctypes.c_int()
    gl.glGetProgramiv(program, GL_LINK_STATUS, ctypes.byref(ok))
    if not ok.value:
        log = ctypes.create_string_buffer(8192)
        gl.glGetProgramInfoLog(program, 8192, None, log)
        raise RuntimeError(log.value.decode(errors="replace"))
    count = ctypes.c_int()
    gl.glGetProgramInterfaceiv(program, GL_UNIFORM, GL_ACTIVE_RESOURCES, ctypes.byref(count))
    props = (ctypes.c_uint * 3)(GL_TYPE, GL_ARRAY_SIZE, GL_REFERENCED_BY_FRAGMENT_SHADER)
    names = []
    units = 0
    for index in range(count.value):
        values = (ctypes.c_int * 3)()
        gl.glGetProgramResourceiv(program, GL_UNIFORM, index, 3, props, 3, None, values)
        if values[0] in SAMPLER_TYPES and values[2]:
            name = ctypes.create_string_buffer(256)
            gl.glGetProgramResourceName(program, GL_UNIFORM, index, 256, None, name)
            names.append(name.value.decode())
            units += max(1, values[1])
    gl.glDeleteProgram(program)
    return units, sorted(names)


def static_samplers(source):
    """Samplers the fragment source declares and names anywhere else once its
    #if blocks are settled: GLSL's "static use", what ANGLE (Chrome, Edge,
    most Windows browsers) counts against the limit, called or not."""
    defined = set()
    active = [True]
    declared = {}
    body = []
    for line in source.splitlines():
        stripped = line.strip()
        word = stripped.split()
        if stripped.startswith("#define") and len(word) > 1 and active[-1]:
            defined.add(word[1])
        elif stripped.startswith("#ifdef"):
            active.append(active[-1] and word[1] in defined)
        elif stripped.startswith("#ifndef"):
            active.append(active[-1] and word[1] not in defined)
        elif stripped.startswith("#if"):
            active.append(active[-1])  # an expression: counted as taken (worst case)
        elif stripped.startswith("#else"):
            parent = active[-2] if len(active) > 1 else True
            active[-1] = parent and not active[-1]
        elif stripped.startswith("#endif"):
            active.pop()
        elif active[-1]:
            found = re.match(r"\s*uniform\s+(?:\w+\s+)?[iu]?sampler\w*\s+(\w+)\s*(?:\[\s*(\d+)\s*\])?", line)
            if found:
                declared[found.group(1)] = int(found.group(2)) if found.group(2) else 1
            else:
                body.append(re.sub(r"//.*", "", line))
    text = "\n".join(body)
    return sum(size for name, size in declared.items() if re.search(r"\b%s\b" % name, text))


def sections(path):
    text = path.read_text(errors="replace")
    parts = re.split(r"^\[(\w+ shader|require)\]\s*$", text, flags=re.M)
    found = {}
    for k in range(1, len(parts), 2):
        found[parts[k]] = parts[k + 1]
    return found.get("vertex shader"), found.get("fragment shader")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("dir")
    parser.add_argument("--limit", type=int, default=16)
    args = parser.parse_args()
    gl = context()
    here = ctypes.c_int()
    gl.glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, ctypes.byref(here))
    files = sorted(pathlib.Path(args.dir).glob("*.shader_test"), key=lambda p: int(re.sub(r"\D", "", p.stem) or 0))
    if not files:
        sys.exit("No captured programs in %s." % args.dir)
    over = []
    rows = []
    for path in files:
        vertex, fragment = sections(path)
        if vertex is None or fragment is None:
            continue
        ours = sorted(set(re.findall(r"uniform\s+\w+\s+[iu]?sampler\w*\s+(m_\w+)", fragment)))
        try:
            units, names = referenced_samplers(gl, vertex, fragment)
        except RuntimeError as error:
            print("%s: does not build here: %s" % (path.name, error.splitlines()[0] if str(error) else "?"))
            continue
        declared = static_samplers(fragment)
        rows.append((units, declared, path.name, names, ours))
        if max(units, declared) > args.limit:
            over.append(path.name)
    rows.sort(reverse=True)
    print("GL_MAX_TEXTURE_IMAGE_UNITS here: %d; limit checked: %d" % (here.value, args.limit))
    print("%-8s %-9s %-18s %s" % ("used", "static", "program", "used samplers"))
    for units, declared, name, names, ours in rows:
        flag = "  OVER" if max(units, declared) > args.limit else ""
        print("%-8d %-9d %-18s %s%s" % (units, declared, name, ", ".join(names), flag))
    if over:
        print("SHADER_UNITS: FAIL %d program(s) over %d: %s" % (len(over), args.limit, ", ".join(over)))
        return 1
    print("SHADER_UNITS: PASS %d programs, the most %d" % (len(rows), max((max(r[0], r[1]) for r in rows), default=0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
