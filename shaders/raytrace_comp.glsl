#version 430

// layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout (local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

layout(binding = 1) uniform sampler2D skyTexture;

uniform mat4 view;
uniform mat4 projection;

const float PI = 3.141592653589793f;
const float TWO_PI = 6.283185307179586f;

struct Ray
{
	vec3 origin;
	vec3 direction;
};

struct HitInfo
{
	float dist;
	vec3 normal;
};

vec2 equirectangularLookup(vec3 dir)
{
	vec2 uv = vec2(atan(dir.z, dir.x), acos(dir.y));
	uv /= vec2(TWO_PI, PI);

	// vec2 uv = vec2(atan(dir.z, dir.x), asin(-dir.y));
	// uv *= vec2(0.1591f, 0.3183f); // inverse atan
	// uv += 0.5f;

	return uv;
}

// hit sphere func for testing
float hitSphere(Ray ray, vec3 spherePosition, float radius)
{
	// hit sphere
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

// sphere scene for testing
vec3 scene(Ray ray)
{
	vec3 outputColour = vec3(0.0f);

	if (hitSphere(ray, vec3(0.0f, 0.0f, 10.0f), 1.0f) > 0.0f)
	{
		outputColour = vec3(0.0f, 0.0f, 1.0f);
	}
	else if (hitSphere(ray, vec3(0.0f, 0.0f, -10.0f), 1.0f) > 0.0f)
	{
		outputColour = vec3(0.0f, 1.0f, 1.0f);
	}
	else if (hitSphere(ray, vec3(10.0f, 0.0f, 0.0f), 1.0f) > 0.0f)
	{
		outputColour = vec3(1.0f, 0.0f, 0.0f);
	}
	else if (hitSphere(ray, vec3(-10.0f, 0.0f, 0.0f), 1.0f) > 0.0f)
	{
		outputColour = vec3(1.0f, 1.0f, 0.0f);
	}
	else
	{
		outputColour = texture(skyTexture, equirectangularLookup(ray.direction)).rgb;
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

	vec4 outputColour = vec4(scene(initialRay), 1.0f);

	// output to a specific pixel in the image
	imageStore(outputTexture, ivec2(index), outputColour);
}
