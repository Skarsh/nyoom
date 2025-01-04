package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import gl "vendor:OpenGL"
import "vendor:glfw"

PROGRAM_NAME :: "Nyoom"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 6

Vec3 :: [3]f32

Sphere :: struct {
	center: Vec3,
	radius: f32,
}

MAX_SPHERES :: 2
spheres: [MAX_SPHERES]Sphere

App_State :: struct {
	running: bool,
}

app_state: App_State

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

main :: proc() {
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)

	fmt.println("Nyoom!!")
	// TODO(Thomas): Add error callback

	if (glfw.Init() != true) {
		log.error("Failed to initialize GLFW")
		return
	}

	defer glfw.Terminate()

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, PROGRAM_NAME, nil, nil)

	if window == nil {
		log.error("Unable to create window")
	}

	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)

	// Enable vsync
	glfw.SwapInterval(1)

	glfw.SetKeyCallback(window, key_callback)

	glfw.SetFramebufferSizeCallback(window, size_callback)

	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	// load shaders
	program, shader_success := gl.load_shaders("shaders/vert.glsl", "shaders/frag.glsl")
	defer gl.DeleteProgram(program)

	// setup vao
	vao: u32

	gl.GenVertexArrays(1, &vao)
	defer gl.DeleteVertexArrays(1, &vao)

	gl.BindVertexArray(vao)

	// setup vbo
	
    // odinfmt: disable
    vertices := [?]f32 {
         1.0,  1.0, 0.0,
         1.0, -1.0, 0.0,
        -1.0, -1.0, 0.0,
        -1.0,  1.0, 0.0,
    }

    indices := [?]u32 {
        0, 1, 3,
        1, 2, 3,
    }

    // odinfmt: enable

	vbo: u32
	gl.GenBuffers(1, &vbo)
	defer gl.DeleteBuffers(1, &vbo)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices[0], gl.STATIC_DRAW)


	// setup ebo
	ebo: u32
	gl.GenBuffers(1, &ebo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices[0], gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), cast(uintptr)0)

	gl.EnableVertexAttribArray(0)

	// set the first sphere in the buffer
	spheres[0] = Sphere {
		center = Vec3{},
		radius = 0.5,
	}

	spheres[1] = Sphere {
		center = Vec3{0, -100.5, 0},
		radius = 100,
	}

	// setup Uniform Buffer Object for spheres
	ubo: u32
	gl.GenBuffers(1, &ubo)
	gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
	gl.BufferData(gl.UNIFORM_BUFFER, size_of(spheres), &spheres[0], gl.STATIC_DRAW)

	// Get the uniform block index and bind it
	block_index := gl.GetUniformBlockIndex(program, "SphereBlock")
	gl.UniformBlockBinding(program, block_index, 0)

	// Bind the buffer to the binding point
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ubo)

	// unbind the vao
	gl.BindVertexArray(0)

	init()

	last_time := glfw.GetTime()
	counter := 0
	for !glfw.WindowShouldClose(window) && app_state.running {
		glfw.PollEvents()

		time := glfw.GetTime()
		delta_time := time - last_time
		last_time = time
		if counter % 100 == 0 {
			fmt.println("delta_time: ", delta_time)
		}

		width, height := glfw.GetWindowSize(window)
		gl.Uniform2f(gl.GetUniformLocation(program, "u_resolution"), f32(width), f32(height))
		gl.Uniform1f(gl.GetUniformLocation(program, "u_time"), f32(time))

		update()
		draw()

		// TODO(Thomas): Move into draw procedure
		gl.UseProgram(program)

		gl.BindVertexArray(vao)
		gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)


		glfw.SwapBuffers(window)
		counter += 1
	}

}

init :: proc() {
	app_state.running = true
}

update :: proc() {

}

draw :: proc() {
	gl.ClearColor(0.2, 0.3, 0.3, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE {
		app_state.running = false
	}
}

size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	log.error(description)
}
