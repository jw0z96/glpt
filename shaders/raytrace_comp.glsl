#version 430

// layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout (local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

layout(binding = 1) uniform sampler2D skyTexture;

uniform uint frame;
uniform mat4 view;
uniform mat4 projection;

const float PI = 3.141592653589793f;
const float TWO_PI = 6.283185307179586f;

// initialize a random number seed based on compute index and frame
// see: https://blog.demofox.org/2020/05/25/casual-shadertoy-path-tracing-1-basic-camera-diffuse-emissive
uint rngSeed = uint(uint(gl_GlobalInvocationID.x) * uint(1973) + uint(gl_GlobalInvocationID.y) * uint(9277) + uint(frame) * uint(26699)) | uint(1);

uint wangHash(inout uint seed)
{
	seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
	seed *= uint(9);
	seed = seed ^ (seed >> 4);
	seed *= uint(0x27d4eb2d);
	seed = seed ^ (seed >> 15);
	return seed;
}

// random float between [0, 1]
float randomFloat(inout uint seed)
{
	return float(wangHash(seed)) / 4294967296.0;
}

vec3 randomUnitVector(inout uint seed)
{
	float z = randomFloat(seed) * 2.0f - 1.0f;
	float a = randomFloat(seed) * TWO_PI;
	float r = sqrt(1.0f - z * z);
	float x = r * cos(a);
	float y = r * sin(a);
	return vec3(x, y, z);
}

const uint maxTraceDepth = 5;

// global 'scene' info
const int numSpheres = 4;
const vec3 spherePositions[4] = {
	vec3(0.0f, 0.0f, 2.0f),
	vec3(0.0f, 0.0f, -2.0f),
	vec3(2.0f, 0.0f, 0.0f),
	vec3(-2.0f, 0.0f, 0.0f)
};
const float sphereRadii[4] = {1.0f, 1.0f, 1.0f, 1.0f};
const vec3 sphereColours[4] = {
	vec3(0.2f, 0.2f, 1.0f),
	vec3(0.2f, 1.0f, 0.2f),
	vec3(1.0f, 0.2f, 0.2f),
	vec3(1.0f, 1.0f, 1.0f)
};
const float sphereRoughness[4] = {0.0f, 0.333f, 0.667f, 1.0f};
// pack sphere positions with radius into vec4? can't access with struct member function

struct Ray
{
	vec3 origin;
	vec3 direction;
};

struct HitInfo
{
	float dist;
	int index; // the index of the sphere we hit
};

vec2 equirectangularLookup(vec3 dir)
{
	vec2 uv = vec2(atan(dir.z, dir.x), acos(dir.y));
	uv /= vec2(TWO_PI, PI);
	return uv;
}

// hit sphere func for testing
float hitSphere(Ray ray, vec3 spherePosition, float radius)
{
	float t = -1.0f;
	vec3 oc = ray.origin - spherePosition;
	float a = dot(ray.direction, ray.direction);
	float b = 2.0f * dot(oc, ray.direction);
	float c = dot(oc, oc) - radius * radius;
	float discriminant = b * b - 4 * a * c;

	if (discriminant < 0)
	{
		return -1.0f;
	}

	return (-b - sqrt(discriminant)) / (2.0f * a);
}

HitInfo hitScene(Ray ray)
{
	HitInfo info;
	info.dist = -1.0f; // max trace distance?? // could be hit position instead?
	info.index = -1;
	for (int i = 0; i < numSpheres; ++i)
	{
		float t = hitSphere(ray, spherePositions[i], sphereRadii[i]);

		if (t > 0.0f && (t < info.dist || info.index == -1))
		{
			info.dist = t;
			info.index = i;
		}
	}

	return info;
}

// get the next ray
vec3 surfaceDistribution(vec3 view, vec3 normal, float roughness) // material
{
	return randomFloat(rngSeed) < roughness ?
		normalize(normal + randomUnitVector(rngSeed)) :
		reflect(view, normal);
}

vec3 scene(Ray ray)
{
	vec3 outputColour = vec3(0.0f);
	vec3 surfaceColour = vec3(1.0f); // start at 1.0f, multiply through by the surface colour of the spheres

	HitInfo info;
	for (uint depth = 0; depth < maxTraceDepth; ++depth)
	{
		info = hitScene(ray);

		if (info.index == -1) // the ray didn't hit anything
		{
			break;
		}

		vec3 hitPos = ray.origin + ray.direction * info.dist;
		vec3 sphereCenter = spherePositions[info.index];
		vec3 normal = normalize(hitPos - sphereCenter);

		ray.direction = surfaceDistribution(ray.direction, normal, sphereRoughness[info.index]);
		ray.origin = hitPos + normal * 0.01f; // avoid self intersection?

		// outputColour += surfaceColour * sphereEmission[info.index]; // ???
		surfaceColour *= sphereColours[info.index];

		// do 'russian roulette' sampling - as our sufaceColour reduces, the chances of terminating a ray
		// increases, as it will be less likely to contribute to our image
		{
			float p = max(surfaceColour.r, max(surfaceColour.g, surfaceColour.b));
			if (randomFloat(rngSeed) > p)
				break;

			// Add the energy we 'lose' by randomly terminating paths
			surfaceColour /= p;
		}
	}

	if (info.index != -1)
	{
		// we hit max trace depth
		outputColour = vec3(0.0f, 0.0f, 0.0f);
	}
	else // we left the scene
	{
		outputColour = surfaceColour * texture(skyTexture, equirectangularLookup(ray.direction)).rgb;
	}

	return outputColour;
}

void main()
{
	ivec2 textureDimensions = imageSize(outputTexture);

	uvec2 index = gl_GlobalInvocationID.xy; // local size 1

	if (index.x >- textureDimensions.x || index.y >- textureDimensions.y)
	{
		return;
	}

	// TODO: loop here for num samples?

	Ray initialRay;

	// We get the camera's position by multiplying the inverse view matrix through the origin
	mat4 inView = inverse(view);
	initialRay.origin = (inView * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

	// random offset between [-0.5, 0.5] to do random sampling around the pixel center
	vec2 jitter = vec2(randomFloat(rngSeed), randomFloat(rngSeed)) - 0.5f;

	// projection[1][1] gets us tan(0.5 * fov), with fov in radians, which gives us the correct fov
	// https://stackoverflow.com/questions/46182845/field-of-view-aspect-ratio-view-matrix-from-projection-matrix-hmd-ost-calib
	vec2 uv = vec2(index + jitter) / textureDimensions;
	initialRay.direction = vec3(uv * 2.0f - 1.0f, -projection[1][1]);

	// Extract the aspect ratio from the projection matrix, and correct for it
	initialRay.direction.y /= projection[1][1] / projection[0][0];

	initialRay.direction = (vec4(initialRay.direction, 1.0f) * view).xyz;
	initialRay.direction = normalize(initialRay.direction);

	vec4 outputColour = vec4(scene(initialRay), 1.0f);
	// vec4 outputColour = vec4(mix(scene(initialRay), scene(initialRay), 0.5), 1.0f);

	vec4 lastFrameColor = imageLoad(outputTexture, ivec2(index));
	outputColour = mix(lastFrameColor, outputColour, 1.0f / float(frame + 1));
	imageStore(outputTexture, ivec2(index), outputColour);
}
