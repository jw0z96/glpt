#version 430

// layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout (local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

layout(binding = 1) uniform sampler2D skyTexture;

uniform mat4 view;
uniform mat4 projection;

const float PI = 3.141592653589793f;
const float TWO_PI = 6.283185307179586f;

const uint maxTraceDepth = 5;

// global 'scene' info
const int numSpheres = 4;
const vec3 spherePositions[4] = {
	vec3(0.0f, 0.0f, 2.0f),
	vec3(0.0f, 0.0f, -2.0f),
	vec3(2.0f, 0.0f, 0.0f),
	vec3(-2.0f, 0.0f, 0.0f)
};
const vec3 sphereColours[4] = {
	vec3(0.2f, 0.2f, 1.0f),
	vec3(0.2f, 1.0f, 0.2f),
	vec3(1.0f, 0.2f, 0.2f),
	vec3(1.0f, 1.0f, 1.0f)
};
const float sphereRadii[4] = {1.0f, 1.0f, 1.0f, 1.0f};
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
vec3 surfaceDistribution(vec3 view, vec3 normal) // material
{
	return reflect(view, normal);
}

// sphere scene for testing
vec3 colour(Ray ray)
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

		ray.direction = surfaceDistribution(ray.direction, normal);
		ray.origin = hitPos; //  + normal * 0.0001f; // avoid self shadowing?

		// surfaceColour += sphereEmission[info.index]; // ???
		surfaceColour *= sphereColours[info.index];
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

	vec2 uv = vec2(index) / textureDimensions;

	Ray initialRay;

	// We get the camera's position by multiplying the inverse view matrix through the origin
	mat4 inView = inverse(view);
	initialRay.origin = (inView * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

	// projection[1][1] gets us tan(0.5 * fov), with fov in radians, which gives us the correct fov
	// https://stackoverflow.com/questions/46182845/field-of-view-aspect-ratio-view-matrix-from-projection-matrix-hmd-ost-calib
	// TODO: sampling around pixel center
	initialRay.direction = vec3(uv * 2.0f - 1.0f, -projection[1][1]);

	// Extract the aspect ratio from the projection matrix, and correct for it
	initialRay.direction.y /= projection[1][1] / projection[0][0];

	initialRay.direction = (vec4(initialRay.direction, 1.0f) * view).xyz;
	initialRay.direction = normalize(initialRay.direction);

	vec4 outputColour = vec4(colour(initialRay), 1.0f);

	// output to a specific pixel in the image
	imageStore(outputTexture, ivec2(index), outputColour);
}
