package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import lin "core:math/linalg"
import "core:math/rand"
import gl "vendor:OpenGL"
import "vendor:glfw"

PROGRAM_NAME :: "Nyoom"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 6

Vec3 :: [3]f32

Material_Type :: enum (c.int) {
	Lambertian = 0,
	Metal = 1,
	Dielectric,
}

// TODO(Thomas): Later we should just make a uniform buffer containing all the different materials
// then just have an index in the sphere or other objects about which Materials to use.
// TODO(Thomas): For some reason the byte array padding doesn't work, floats is the only way
// I've made thise work. Need to find a proper solution for this
Material :: struct #align (16) {
	type:            Material_Type,
	//_pad1:  [3]u8,
	a:               f32,
	b:               f32,
	c:               f32,
	albedo:          Vec3,
	fuzz:            f32,
	refractionIndex: f32,
}


Sphere :: struct {
	mat:    Material,
	center: Vec3,
	radius: f32,
}

MAX_SPHERES :: 13
spheres: [MAX_SPHERES]Sphere

Camera :: struct #align (16) {
	center:                 Vec3,
	world_up:               Vec3,
	front:                  Vec3,
	up:                     Vec3,
	right:                  Vec3,
	// euler angles
	yaw:                    f32,
	pitch:                  f32,
	// camera options
	movement_speed:         f32,
	movement_sprint_factor: f32,
	mouse_sensitivity:      f32,
	zoom:                   f32,
	// viewport parameters
	vfov:                   f32,
	viewport_width:         f32,
	viewport_height:        f32,
	viewport_u:             Vec3,
	viewport_v:             Vec3,
	pixel_delta_u:          Vec3,
	pixel_delta_v:          Vec3,
	viewport_upper_left:    Vec3,
	pixel00_loc:            Vec3,
	defocus_disk_u:         Vec3,
	defocus_disk_v:         Vec3,
	defocus_angle:          f32,
	focus_dist:             f32,
}

App_State :: struct {
	window:       glfw.WindowHandle,
	running:      bool,
	zoom:         f32,
	last_mouse_x: f32,
	last_mouse_y: f32,
	first_mouse:  bool,
	camera:       Camera,
}

app_state: App_State

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)

	fmt.println("Nyoom!!")

	if (glfw.Init() != true) {
		log.error("Failed to initialize GLFW")
		return
	}

	defer glfw.Terminate()
	glfw.SetErrorCallback(error_callback)

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, PROGRAM_NAME, nil, nil)

	if window == nil {
		log.error("Unable to create window")
	}

	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)

	// Enable vsync
	glfw.SwapInterval(1)

	glfw.SetKeyCallback(window, key_callback)
	glfw.SetScrollCallback(window, scroll_callback)

	glfw.SetFramebufferSizeCallback(window, size_callback)

	// Hide and capture the cursor
	glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)

	// Set the mouse callback
	glfw.SetCursorPosCallback(window, mouse_callback)

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

	sphere_index := 0

	material_ground := Material {
		type   = .Lambertian,
		albedo = Vec3{0.5, 0.5, 0.5},
	}

	spheres[sphere_index] = Sphere {
		mat    = material_ground,
		center = Vec3{0, -1000, 0},
		radius = 1000,
	}

	sphere_index += 1

	for a in -1 ..< 1 {
		for b in -1 ..< 1 {
			choose_mat := rand.float64()
			center := Vec3{f32(a) + 0.9 * rand.float32(), 0.2, f32(b) + 0.9 * rand.float32()}

			if lin.length(center - Vec3{4, 0.02, 0}) > 0.9 {
				sphere_material: Material

				if choose_mat < 0.8 {
					// diffuse
					albedo := random_vec3() * random_vec3()
					sphere_material = Material {
						type   = .Lambertian,
						albedo = albedo,
					}
					spheres[sphere_index] = Sphere {
						mat    = sphere_material,
						center = center,
						radius = 0.2,
					}
				} else if (choose_mat < 0.95) {
					// metal
					albedo := random_vec3_range(0.5, 1)
					fuzz := rand.float32_range(0, 0.5)
					sphere_material = Material {
						type   = .Metal,
						albedo = albedo,
						fuzz   = fuzz,
					}
					spheres[sphere_index] = Sphere {
						mat    = sphere_material,
						center = center,
						radius = 0.2,
					}
				} else {
					// glass
					sphere_material = Material {
						type            = .Dielectric,
						refractionIndex = 1.5,
					}
					spheres[sphere_index] = Sphere {
						mat    = sphere_material,
						center = center,
						radius = 0.2,
					}
				}
			}
			sphere_index += 1
		}
	}

	material1 := Material {
		type            = .Dielectric,
		refractionIndex = 1.50,
	}

	spheres[sphere_index] = Sphere {
		mat    = material1,
		center = Vec3{0, 1, 0},
		radius = 1.0,
	}

	sphere_index += 1

	material2 := Material {
		type   = .Lambertian,
		albedo = Vec3{0.4, 0.2, 0.1},
	}

	spheres[sphere_index] = Sphere {
		mat    = material2,
		center = Vec3{-4, 1, 0},
		radius = 1.0,
	}

	sphere_index += 1

	material3 := Material {
		type   = .Metal,
		albedo = Vec3{0.7, 0.6, 0.5},
		fuzz   = 0.0,
	}

	spheres[sphere_index] = Sphere {
		mat    = material3,
		center = Vec3{4, 1, 0},
		radius = 1.0,
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

	init(window)

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
		gl.Uniform1f(gl.GetUniformLocation(program, "u_zoom"), app_state.zoom)

		set_camera_uniform(program, app_state.camera)

		update(f32(delta_time))
		draw()

		// TODO(Thomas): Move into draw procedure
		gl.UseProgram(program)

		gl.BindVertexArray(vao)
		gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)


		glfw.SwapBuffers(window)
		counter += 1
	}

}

// Modify set_camera_uniform to include the new viewport parameters
set_camera_uniform :: proc(program: u32, camera: Camera) {
	center_loc := gl.GetUniformLocation(program, "u_camera.center")
	world_up_loc := gl.GetUniformLocation(program, "u_camera.worldUp")
	front_loc := gl.GetUniformLocation(program, "u_camera.front")
	up_loc := gl.GetUniformLocation(program, "u_camera.up")
	right_loc := gl.GetUniformLocation(program, "u_camera.right")
	viewport_u_loc := gl.GetUniformLocation(program, "u_camera.viewportU")
	viewport_v_loc := gl.GetUniformLocation(program, "u_camera.viewportV")
	pixel_delta_u_loc := gl.GetUniformLocation(program, "u_camera.pixelDeltaU")
	pixel_delta_v_loc := gl.GetUniformLocation(program, "u_camera.pixelDeltaV")
	viewport_upper_left_loc := gl.GetUniformLocation(program, "u_camera.viewportUpperLeft")
	pixel00_loc := gl.GetUniformLocation(program, "u_camera.pixel00Loc")
	defocus_disk_u_loc := gl.GetUniformLocation(program, "u_camera.defocusDiskU")
	defocus_disk_v_loc := gl.GetUniformLocation(program, "u_camera.defocusDiskV")
	defocus_disk_angle_loc := gl.GetUniformLocation(program, "u_camera.defocusDiskAngle")

	gl.Uniform3f(center_loc, camera.center.x, camera.center.y, camera.center.z)
	gl.Uniform3f(world_up_loc, camera.world_up.x, camera.world_up.y, camera.world_up.z)
	gl.Uniform3f(front_loc, camera.front.x, camera.front.y, camera.front.z)
	gl.Uniform3f(up_loc, camera.up.x, camera.up.y, camera.up.z)
	gl.Uniform3f(right_loc, camera.right.x, camera.right.y, camera.right.z)
	gl.Uniform3f(viewport_u_loc, camera.viewport_u.x, camera.viewport_u.y, camera.viewport_u.z)
	gl.Uniform3f(viewport_v_loc, camera.viewport_v.x, camera.viewport_v.y, camera.viewport_v.z)
	gl.Uniform3f(
		pixel_delta_u_loc,
		camera.pixel_delta_u.x,
		camera.pixel_delta_u.y,
		camera.pixel_delta_u.z,
	)
	gl.Uniform3f(
		pixel_delta_v_loc,
		camera.pixel_delta_v.x,
		camera.pixel_delta_v.y,
		camera.pixel_delta_v.z,
	)
	gl.Uniform3f(
		viewport_upper_left_loc,
		camera.viewport_upper_left.x,
		camera.viewport_upper_left.y,
		camera.viewport_upper_left.z,
	)
	gl.Uniform3f(pixel00_loc, camera.pixel00_loc.x, camera.pixel00_loc.y, camera.pixel00_loc.z)
	gl.Uniform3f(
		defocus_disk_u_loc,
		camera.defocus_disk_u.x,
		camera.defocus_disk_u.y,
		camera.defocus_disk_u.z,
	)
	gl.Uniform3f(
		defocus_disk_v_loc,
		camera.defocus_disk_v.x,
		camera.defocus_disk_v.y,
		camera.defocus_disk_v.z,
	)
	gl.Uniform1f(defocus_disk_angle_loc, camera.defocus_angle)
}


init :: proc(window: glfw.WindowHandle) {
	app_state.window = window
	app_state.running = true
	app_state.zoom = 1.0
	app_state.first_mouse = true
	app_state.camera = Camera {
		center                 = Vec3{0, 0, 1},
		up                     = Vec3{0, 1, 0},
		front                  = Vec3{0, 0, -1},
		world_up               = Vec3{0, 1, 0},
		movement_speed         = 1.0,
		movement_sprint_factor = 2.0,
		yaw                    = -90,
		pitch                  = 0,
		mouse_sensitivity      = 0.1,
		vfov                   = 90,
		defocus_angle          = 10,
		focus_dist             = 3.4,
	}
}

update_viewport_parameters :: proc(camera: ^Camera, window_width: i32, window_height: i32) {
	aspect_ratio := f32(window_width) / f32(window_height)
	theta := math.to_radians(camera.vfov)
	h := math.tan(theta / 2.0)
	viewport_height := 2.0 * h * camera.focus_dist
	viewport_width := viewport_height * aspect_ratio

	camera.viewport_width = viewport_width
	camera.viewport_height = viewport_height

	camera.viewport_u = camera.viewport_width * camera.right
	camera.viewport_v = camera.viewport_height * camera.up

	camera.pixel_delta_u = camera.viewport_u / f32(window_width)
	camera.pixel_delta_v = camera.viewport_v / f32(window_height)

	camera.viewport_upper_left =
		camera.center +
		(camera.focus_dist * camera.front) -
		camera.viewport_u / 2.0 -
		camera.viewport_v / 2.0

	camera.pixel00_loc =
		camera.viewport_upper_left + 0.5 * (camera.pixel_delta_u + camera.pixel_delta_v)

	defocus_radius := camera.focus_dist * math.tan(math.to_radians(camera.defocus_angle) / 2.0)
	camera.defocus_disk_u = camera.right * defocus_radius
	camera.defocus_disk_v = camera.up * defocus_radius
}

update_camera_vectors :: proc(camera: ^Camera) {
	// Convert Euler angles to direction vector
	front := Vec3{}
	front.x = math.cos(math.to_radians(camera.yaw)) * math.cos(math.to_radians(camera.pitch))
	front.y = math.sin(math.to_radians(camera.pitch))
	front.z = math.sin(math.to_radians(camera.yaw)) * math.cos(math.to_radians(camera.pitch))

	// Calculate camera basis vectors
	camera.front = lin.normalize(front)
	camera.right = lin.normalize(lin.cross(camera.front, camera.world_up))
	camera.up = lin.normalize(lin.cross(camera.right, camera.front))

	// Update viewport parameters with current window dimensions
	width, height := glfw.GetWindowSize(app_state.window)
	update_viewport_parameters(camera, width, height)
}

update :: proc(dt: f32) {
	camera := &app_state.camera
	camera_speed := dt * camera.movement_speed
	if glfw.GetKey(app_state.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS {
		camera_speed *= camera.movement_sprint_factor
	}

	if glfw.GetKey(app_state.window, glfw.KEY_W) == glfw.PRESS {
		camera.center += camera_speed * camera.front
	}
	if glfw.GetKey(app_state.window, glfw.KEY_S) == glfw.PRESS {
		camera.center -= camera_speed * camera.front
	}
	if glfw.GetKey(app_state.window, glfw.KEY_A) == glfw.PRESS {
		camera.center -= camera_speed * lin.normalize(lin.cross(camera.front, camera.up))
	}
	if glfw.GetKey(app_state.window, glfw.KEY_D) == glfw.PRESS {
		camera.center += camera_speed * lin.normalize(lin.cross(camera.front, camera.up))
	}

	update_camera_vectors(camera)
}

draw :: proc() {
	gl.ClearColor(0.2, 0.3, 0.3, -10.0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE {
		app_state.running = false
	}
}

size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
	context = runtime.default_context()
	update_viewport_parameters(&app_state.camera, width, height)
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, x_offset, y_offset: f64) {
	context = runtime.default_context()

	// Adjust these values to control zoom sensitivity
	zoom_speed: f32 = 0.1
	min_zoom: f32 = 0.1
	max_zoom: f32 = 10.0

	app_state.zoom *= 1.0 + (f32(y_offset) * zoom_speed)
	app_state.zoom = math.clamp(app_state.zoom, min_zoom, max_zoom)
}

error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	log.error(description)
}

mouse_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	context = runtime.default_context()

	x_pos: f32 = f32(xpos)
	y_pos: f32 = f32(ypos)

	if app_state.first_mouse {
		app_state.last_mouse_x = x_pos
		app_state.last_mouse_y = y_pos
		app_state.first_mouse = false
		return
	}

	x_offset := x_pos - app_state.last_mouse_x
	// Reversed since y-coordinates go from bottom to top
	y_offset := app_state.last_mouse_y - y_pos

	app_state.last_mouse_x = x_pos
	app_state.last_mouse_y = y_pos

	camera := &app_state.camera
	x_offset *= camera.mouse_sensitivity
	y_offset *= camera.mouse_sensitivity

	camera.yaw += f32(x_offset)
	camera.pitch += f32(y_offset)

	// Constrain the pitch to avoid flipping
	if camera.pitch > 89.0 do camera.pitch = 89.0
	if camera.pitch < -89.0 do camera.pitch = -89.0

	update_camera_vectors(camera)
}

random_vec3 :: proc() -> Vec3 {
	return Vec3{rand.float32(), rand.float32(), rand.float32()}
}

random_vec3_range :: proc(min: f32, max: f32) -> Vec3 {
	return Vec3 {
		rand.float32_range(min, max),
		rand.float32_range(min, max),
		rand.float32_range(min, max),
	}
}
