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
uniform vec3 u_camera_center;

layout(std140) uniform SphereBlock {
    Sphere spheres[MAX_SPHERES];
};

float linearToGamma(float linearComponent) {
    if (linearComponent > 0.0) 
        return sqrt(linearComponent); 

    return 0.0;
}

vec3 linearToGammaVec3(vec3 color) {
    return vec3(linearToGamma(color.x), linearToGamma(color.y), linearToGamma(color.z));
}

// Returns a random real number in then interval [0, 1)
float rand(vec2 seed) {
   return fract(sin(dot(seed, vec2(12.9898,78.233))) * 43758.5453123);
}

// Returns a random real number in the interval [min, max)
float rand(float min, float max, vec2 seed) {
    return min + (max - min) * rand(seed); 
}


// Return a random vec3 with values in the interval [0, 1)
vec3 randVec3(vec2 seed) {
    vec3 h = vec3(seed, seed.x * seed.y);
    h = fract(h * vec3(0.1031, 0.1030, 0.0973));
    h += dot(h, h.yzx + 33.33);
    return fract((h.xxy + h.yzz) * h.zyx);
}

// Return a random vec3 with values in the interval [min, max)
vec3 randVec3(float min, float max, vec2 seed) {
    vec3 r = randVec3(seed);
    return min + (max - min) * r;
}


vec3 randUnitVector(vec2 seed) {
    float u = rand(seed);
    float v = rand(seed + vec2(1.0, 0.0));
    float theta = 2.0 * 3.14159265359 * u;
    float phi = acos(2.0 * v - 1.0);
    
    return vec3(
        sin(phi) * cos(theta),
        sin(phi) * sin(theta),
        cos(phi)
    );
}

// Basic rejection sampling method
vec3 sampleHemisphere(vec3 normal, vec2 seed)
{
    vec3 vec = normalize(
        vec3(
            rand(seed)*2.0-1.0,
            rand(seed.yx+vec2(1.123123123,2.545454))*2.0-1.0,
            rand(seed-vec2(9.21428,7.43163431))*2.0-1.0
        )
    );

	if (dot(vec, normal) < 0.0) vec *= -1; 

	return vec;
}

vec3 hemisphereRejection(vec3 normal, vec2 seed) {
    vec3 randomVec = vec3(
        rand(seed) * 2.0 - 1.0,
        rand(seed) * (2.0 - 1.0) * 2.0,
        rand(seed) * (2.0 - 1.0) * 3.0
    );
    vec3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
    vec3 bitangent = cross(normal, tangent);
    float r = rand(seed * 4.0);
    float theta = 2.0 * 3.14159265359 * rand(seed * 5.0);
    float r_sqrt = sqrt(r);
    return normalize(
        r_sqrt * cos(theta) * tangent +
        r_sqrt * sin(theta) * bitangent +
        sqrt(1.0 - r) * normal
    );
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
vec3 sampleSquare(vec2 seed) {
    return vec3(rand(seed) - 0.5, rand(seed + vec2(1.0, 2.0)) - 0.5, 0.0);
}

struct Ray {
    vec3 origin;
    vec3 dir;
};

Ray getRay(vec3 center, vec3 pixelCenter, vec2 seed) {
    // Calculate pixel deltas for x and y separately
    vec2 pixelDelta = 1.0 / u_resolution;
    
    // Get random offset in [-0.5, 0.5] range
    vec3 offset = sampleSquare(seed);
    
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

vec3 rayColor(Ray ray, vec2 seed) {
    HitRecord rec;
    rec.p = vec3(0.0);
    rec.normal = vec3(0.0);
    rec.t = 0.0;
    rec.frontFace = false;
    
    vec3 rayOrigin = ray.origin;
    vec3 rayDirection = ray.dir;

    vec3 unitDirection = normalize(ray.dir); 
    float a = 0.5 * (unitDirection.y + 1.0);
    vec3 pixelColor = mix(vec3(1.0), vec3(0.5, 0.7, 1.0), a);


    int maxBounces = 10;
    for (int i = 0; i < maxBounces; i++) {
        if (hit(Ray(rayOrigin, rayDirection), interval(0.001, INF), rec)) {
            // New ray origin at the hit point
            rayOrigin = rec.p; 

            // Calculate new rayDirection
            rayDirection = rec.normal + randUnitVector(seed);

            pixelColor *= 0.5;
        } else {
            break;
        }
    }

    return pixelColor;
}

void main() {
    vec2 uv = pos.xy;
    vec2 aspectRatio = vec2(u_resolution.x / u_resolution.y, 1.0);
    uv *= aspectRatio / u_zoom;

    float focalLength = 1.0;
    vec3 pixelCenter = vec3(uv, pos.z);
    vec3 cameraCenter = vec3(0.0, 0.0, focalLength);

    int samplesPerPixel = 100;
    float pixelSamplesScale = 1.0 / samplesPerPixel;
    vec3 pixelColor = vec3(0.0);
    
    for(int i = 0; i < samplesPerPixel; i++) {
        Ray ray = getRay(cameraCenter, pixelCenter, uv);
        pixelColor += rayColor(ray, uv);
    }
    pixelColor *= pixelSamplesScale;

    FragColor = vec4(linearToGammaVec3(pixelColor), 1.0);
}
