#version 460 core

in vec3 pos;
out vec4 FragColor;

uniform vec2 resolution;
uniform float time;

struct Ray {
    vec3 origin;
    vec3 dir;
};

struct HitRecord {
    vec3 point;
    vec3 normal;
    float t;
};

vec3 rayAt(Ray ray, float t) {
    return ray.origin + ray.dir * t;
}

float hitSphere(vec3 center, float radius, Ray ray) {
    vec3 oc = center - ray.origin;
    float a = dot(ray.dir, ray.dir);
    float b = -2.0 * dot(ray.dir, oc);
    float c = dot(oc, oc) - (radius * radius);
    float discriminant = b*b - (4 * a * c);

    if (discriminant < 0.0) {
        return -1.0;
    } else {
        return (-b - sqrt(discriminant)) / (2.0 * a);
    }
}

//float hitSphere(vec3 center, float radius, Ray ray) {
//    vec3 oc = center - ray.origin;
//    float a = length(ray.dir);
//    float h = dot(ray.dir, oc);
//    float c = length(oc) - (radius * radius);
//    float discriminant = h * h - a * c;
//
//    if (discriminant < 0.0) {
//        return -1.0;
//    } else {
//        return (h - sqrt(discriminant)) / a;
//    }
//}

vec3 rayColor(Ray ray) {
    float t = hitSphere(vec3(0.0), 0.5, ray);
    if (t > 0.0) {
        vec3 N = normalize(rayAt(ray, t) - vec3(0.0));
        return 0.5 * vec3(N.x + 1, N.y + 1, N.z + 1);
    }

    vec3 unitDirection = normalize(ray.dir); 
    float a = 0.5 * (unitDirection.y + 1.0);
    return mix(vec3(1.0), vec3(0.5, 0.7, 1.0), a);
}


void main() {
    vec2 uv = pos.xy;
    vec2 aspectRatio = vec2(resolution.x / resolution.y, 1.0);
    uv *= aspectRatio;

    float focalLength = 1.0;
    vec3 pixelCenter = vec3(uv, pos.z);
    vec3 cameraCenter = vec3(0.0, 0.0, focalLength);
    vec3 rayDir = pixelCenter - cameraCenter;

    Ray ray = Ray(cameraCenter, rayDir);

    FragColor = vec4(rayColor(ray), 1.0);
}
