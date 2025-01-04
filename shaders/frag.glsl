#version 460 core

#define INF 1.0 / 0.0
#define PI 3.14159265

#define MAX_SPHERES 2

in vec3 pos;
out vec4 FragColor;

struct Sphere {
    vec3 center;
    float radius;
};

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_zoom;

layout(std140) uniform SphereBlock {
    Sphere spheres[MAX_SPHERES];
};


// Returns a random real number in then interval [0, 1)
float rand() {
   return fract(sin(dot(gl_FragCoord.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

// Returns a random real number in the interval [min, max)
float rand(float min, float max) {
    return min + (max - min) * rand(); 
}

struct Interval {
    float min;
    float max;
};

Interval interval() {
    return Interval(-INF, INF);
}

Interval interval(float min, float max) {
    return Interval(min, max);
}

float intervalSize(Interval interval) {
    return interval.max - interval.min;
}

bool intervalContains(Interval interval, float x) {
    return interval.min <= x && x <= interval.max;
}

bool intervalSurrounds(Interval interval, float x) {
    return interval.min < x && x < interval.max;
}

const Interval emptyInterval = Interval(INF, -INF);
const Interval universeInterval = Interval(-INF, INF);

// Returns a vector to a random point in the [-0.5, 0.5] to [0.5, 0.5] unit square
vec3 sampleSquare() {
    return vec3(rand() - 0.5, rand() - 0.5, 0.0);
}

struct Ray {
    vec3 origin;
    vec3 dir;
};

Ray getRay(vec3 center, vec3 pixelCenter) {
    // Calculate pixel deltas for x and y separately
    vec2 pixelDelta = 1.0 / u_resolution;
    
    // Get random offset in [-0.5, 0.5] range
    vec3 offset = sampleSquare();
    
    // Apply the properly scaled offset to the pixel center
    vec3 pixelSample = pixelCenter + vec3(offset.xy * pixelDelta, 0.0);
    
    vec3 rayOrigin = center;

    vec3 rayDirection = pixelSample - rayOrigin;

    return Ray(rayOrigin, rayDirection);
}


struct HitRecord {
    vec3 p;
    vec3 normal;
    float t;
    bool frontFace;
};

HitRecord hitRecord() {
    return HitRecord(vec3(0.0), vec3(0.0), 0.0, false);
}

vec3 rayAt(Ray ray, float t) {
    return ray.origin + ray.dir * t;
}

void setFaceNormal(inout HitRecord rec, Ray ray, vec3 outwardNormal) {
    // Sets the hit record normal
    // NOTE: the parameter `outwardNormal` is assumed to have unit length
    rec.frontFace = dot(ray.dir, outwardNormal) < 0.0;
    rec.normal = rec.frontFace ? outwardNormal : -outwardNormal;
}


bool hitSphere(Sphere sphere, Ray ray, Interval rayInterval, inout HitRecord rec) {
    vec3 oc = sphere.center - ray.origin;
    float a = dot(ray.dir, ray.dir);
    float h = dot(ray.dir, oc);
    float c = dot(oc, oc) - (sphere.radius * sphere.radius);

    float discriminant = h*h - (a * c);

    if (discriminant < 0.0) 
        return false;

    float sqrtd = sqrt(discriminant);

    // Find the nearest root that lies in the acceptable range
    float root = (h - sqrtd) / a;
    if (!intervalSurrounds(rayInterval, root)) {
        root = (h + sqrtd) / a;
        if (!intervalSurrounds(rayInterval, root)) {
            return false;
        }
    }

    rec.t = root;
    rec.p = rayAt(ray, rec.t);
    vec3 outwardNormal = (rec.p - sphere.center) / sphere.radius;
    setFaceNormal(rec, ray, outwardNormal);

    return true;
}

bool hit(Ray ray, Interval rayInterval, inout HitRecord rec) {
    HitRecord tempRec;
    bool hitAnything = false;
    float closestSoFar = rayInterval.max;

    for (int i = 0; i < spheres.length(); i++) {
        if (hitSphere(spheres[i], ray, interval(rayInterval.min, closestSoFar), tempRec)) {
            hitAnything = true;
            closestSoFar = tempRec.t;
            rec = tempRec;
        }
    }

    return hitAnything;
}

vec3 rayColor(Ray ray) {
    HitRecord rec;
    rec.p = vec3(0.0);
    rec.normal = vec3(0.0);
    rec.t = 0.0;
    rec.frontFace = false;

    if (hit(ray, interval(0, INF), rec)) {
        return 0.5 * (rec.normal + vec3(1.0));
    }

    vec3 unitDirection = normalize(ray.dir); 
    float a = 0.5 * (unitDirection.y + 1.0);
    return mix(vec3(1.0), vec3(0.5, 0.7, 1.0), a);
}

void main() {
    vec2 uv = pos.xy;
    vec2 aspectRatio = vec2(u_resolution.x / u_resolution.y, 1.0);
    uv *= aspectRatio / u_zoom;

    float focalLength = 1.0;
    vec3 pixelCenter = vec3(uv, pos.z);
    vec3 cameraCenter = vec3(0.0, 0.0, focalLength);

    //vec3 rayDir = pixelCenter - cameraCenter;
    //Ray ray = Ray(cameraCenter, rayDir);
    //vec3 pixelColor = rayColor(ray);
    //FragColor = vec4(pixelColor, 1.0);

    int samplesPerPixel = 100;
    float pixelSamplesScale = 1.0 / samplesPerPixel;
    vec3 pixelColor = vec3(0.0);
    
    for(int i = 0; i < samplesPerPixel; i++) {
        Ray ray = getRay(cameraCenter, pixelCenter);
        pixelColor += rayColor(ray);
    }

    FragColor = vec4(pixelColor * pixelSamplesScale, 1.0);
}
