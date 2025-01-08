#version 460 core

#define INF 1.0 / 0.0
#define PI 3.14159265

#define MAX_SPHERES 5
#define MAX_BOUNCES 10
#define SAMPLES_PER_PIXEL 100

#define MATERIAL_LAMBERTIAN 0
#define MATERIAL_METAL 1
#define MATERIAL_DIELECTRIC 2

in vec3 pos;
out vec4 FragColor;

struct Camera {
    vec3 center;
    vec3 lookAt;
    vec3 worldUp;
    vec3 front;
    vec3 up;
    vec3 right;
};

struct Material {
    int type;
    vec3 albedo;
    float fuzz;
    float refractionIndex;
};

struct Sphere {
    Material mat;
    vec3 center;
    float radius;
};

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_zoom;
uniform vec3 u_camera_center;

uniform Camera u_camera;

layout(std140) uniform SphereBlock {
    Sphere spheres[MAX_SPHERES];
};

// Returns true if vector is close to zero in all dimensions
bool nearZero(vec3 v) {
    float s = 1e-8;
    return (abs(v[0]) < s) && (abs(v[1]) < s) && (abs(v[2]) < s);
}

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

vec3 reflect(vec3 v, vec3 n) {
    return v - 2.0 * dot(v, n) * n;
}

vec3 refract(vec3 uv, vec3 n, float etai_over_etat) {
    float cos_theta = min(dot(-uv, n), 1.0);
    vec3 rOutPerp = etai_over_etat * (uv + cos_theta * n);
    vec3 rOutParallel = -sqrt(abs(1.0 - dot(rOutPerp, rOutPerp))) * n;
    return rOutPerp + rOutParallel;
}

float reflectance(float cosine, float refractionIndex) {
    // Use Schlick's approximation for reflectance
    float r0 = (1.0 - refractionIndex) / (1.0 + refractionIndex);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
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
    return vec3(
        rand(seed) - 0.5,
        rand(seed * vec2(12.989, 78.233)) - 0.5,
        0.0
    );
}

struct Ray {
    vec3 origin;
    vec3 dir;
};

Ray getRay(vec3 center, vec3 pixelCenter, vec2 seed) {
    // vertical field-of-view in degrees
    float vfov = 90.0;
    float focal_length = 1.0;
    
    // Calculate viewport dimensions
    float theta = radians(vfov);
    float h = tan(theta/2.0);
    float viewport_height = 2.0 * h * focal_length;
    float viewport_width = viewport_height * (u_resolution.x/u_resolution.y);
    
    // Calculate viewport vectors
    vec3 viewport_u = vec3(viewport_width, 0, 0);
    vec3 viewport_v = vec3(0, -viewport_height, 0);
    
    // Calculate pixel delta vectors
    vec3 pixel_delta_u = viewport_u / u_resolution.x;
    vec3 pixel_delta_v = viewport_v / u_resolution.y;
    
    // Calculate upper left pixel location
    vec3 viewport_upper_left = center 
                              - vec3(0, 0, focal_length) 
                              - viewport_u/2.0 
                              - viewport_v/2.0;
    vec3 pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);
    
    // Convert UV coordinates to pixel coordinates
    vec2 pixel_coords = pixelCenter.xy * u_resolution;
    
    // Get random offset and calculate pixel sample position
    vec3 offset = sampleSquare(seed);
    vec3 pixel_sample = pixel00_loc 
                       + (pixel_coords.x + offset.x) * pixel_delta_u 
                       + (pixel_coords.y + offset.y) * pixel_delta_v;
    
    vec3 ray_origin = center;
    vec3 ray_direction = normalize(pixel_sample - ray_origin);
    
    return Ray(ray_origin, ray_direction);
}

struct HitRecord {
    vec3 p;
    vec3 normal;
    Material mat;
    float t;
    bool frontFace;
};

bool lambertianScatter(Material material, Ray rayIn, HitRecord rec, inout vec3 attenuation, inout Ray scattered, vec2 seed) {
    vec3 scatterDirection = rec.normal + randUnitVector(seed);

    // Catch degenerate scatter direction
    if (nearZero(scatterDirection))
        scatterDirection = rec.normal;

    scattered = Ray(rec.p, scatterDirection);
    attenuation = material.albedo;
    return true;
}

bool metalScatter(Material material, Ray rayIn, HitRecord rec, inout vec3 attenuation, inout Ray scattered, vec2 seed) {
    vec3 reflected = reflect(rayIn.dir, rec.normal);
    reflected = normalize(reflected) + (material.fuzz * randUnitVector(seed));
    scattered = Ray(rec.p, reflected);
    attenuation = material.albedo;
    return (dot(scattered.dir, rec.normal) > 0.0);
}

bool dielectricScatter(Material material, Ray rayIn, HitRecord rec, inout vec3 attenuation, inout Ray scattered, vec2 seed) {
    attenuation = vec3(1.0, 1.0, 1.0);
    float ri = rec.frontFace ? (1.0 / material.refractionIndex) : material.refractionIndex;
    
    vec3 unitDirection = normalize(rayIn.dir);

    float cosTheta = min(dot(-unitDirection, rec.normal), 1.0);
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    bool cannotRefract = ri * sinTheta > 1.0;
    vec3 direction;
    
    if (cannotRefract || reflectance(cosTheta, ri) > rand(seed))
        direction = reflect(unitDirection, rec.normal);
    else 
        direction = refract(unitDirection, rec.normal, ri);

    scattered = Ray(rec.p, direction);

    return true;
}

HitRecord hitRecord() {
    Material mat = Material(0, vec3(0.0), 0.0, 0.0);
    return HitRecord(vec3(0.0), vec3(0.0), mat, 0.0, false);
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
    rec.mat = sphere.mat;

    return true;
}

bool hit(Ray ray, Interval rayInterval, inout HitRecord rec) {
    HitRecord tempRec = hitRecord();
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

vec3 rayColor(Ray r, vec2 seed) {
    Ray ray = r;
    vec3 accumulatedColor = vec3(1.0);
    HitRecord rec;
    
    for (int depth = 0; depth < MAX_BOUNCES; depth++) {
        if (hit(ray, interval(0.001, INF), rec)) {
            Ray scattered;
            vec3 attenuation;
            
            if (rec.mat.type == MATERIAL_LAMBERTIAN) {
                if (lambertianScatter(rec.mat, ray, rec, attenuation, scattered, seed)) {
                    accumulatedColor *= attenuation;
                    ray = scattered;
                    continue;
                }
            } else if (rec.mat.type == MATERIAL_METAL) {
                if (metalScatter(rec.mat, ray, rec, attenuation, scattered, seed)) {
                    accumulatedColor *= attenuation;
                    ray = scattered;
                    continue;
                }
            } else if(rec.mat.type == MATERIAL_DIELECTRIC) {
                if (dielectricScatter(rec.mat, ray, rec, attenuation, scattered, seed)) {
                    accumulatedColor *= attenuation;
                    ray = scattered;
                    continue;
                }
            }
            return vec3(0.0);
        }
    }
    
    vec3 unit_direction = normalize(ray.dir);
    float a = 0.5 * (unit_direction.y + 1.0);
    vec3 background = (1.0-a)*vec3(1.0, 1.0, 1.0) + a*vec3(0.5, 0.7, 1.0);
    return accumulatedColor * background;
}

void main() {
    // Convert from [-1, 1] to [0, 1] and flip Y
    vec2 uv = (pos.xy + 1.0) * 0.5;
    uv.y = 1.0 - uv.y;  // Flip Y coordinate
    
    vec2 center = vec2(0.5);
    uv = center + (uv - center) / u_zoom;
    
    vec3 color = vec3(0.0);
    
    for(int s = 0; s < SAMPLES_PER_PIXEL; s++) {
        vec2 seed = uv + vec2(float(s), u_time);
        Ray r = getRay(u_camera.center, vec3(uv, 0.0), seed);
        color += rayColor(r, seed);
    }
    
    color /= float(SAMPLES_PER_PIXEL);
    FragColor = vec4(linearToGammaVec3(color), 1.0);
}
