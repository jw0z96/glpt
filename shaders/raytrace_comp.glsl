#version 430

layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

uniform mat4 view;
uniform mat4 projection;

const float PI = 3.14159265358979323846264338327950288;

struct Ray
{
	vec3 origin;
	vec3 direction;
};

// hit sphere func for testing
bool hitSphere(Ray ray, vec3 spherePosition, float radius)
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
		return false;
	}

	return ((-b - sqrt(discriminant)) / (2.0f * a)) > 0.0f;
}

void main()
{
	vec2 textureDimensions = imageSize(outputTexture);
	vec2 uv = gl_GlobalInvocationID.xy / textureDimensions;

	Ray initialRay;

	// We get the camera's position by multiplying the inverse view matrix through the origin
	mat4 inView = inverse(view);
	initialRay.origin = (inView * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

	// projection[1][1] gets us tan(0.5 * fov), with fov in radians, which gives us the correct fov
	// https://stackoverflow.com/questions/46182845/field-of-view-aspect-ratio-view-matrix-from-projection-matrix-hmd-ost-calib
	// TODO: sampling around pixel center
	initialRay.direction = vec3(uv * 2.0f - 1.0f, -projection[1][1]);

	// Extract the aspect ration from the projection matrix, and correct for it
	initialRay.direction.y /= projection[1][1] / projection[0][0];

	initialRay.direction = (vec4(initialRay.direction, 1.0f) * view).xyz;
	initialRay.direction = normalize(initialRay.direction);

	vec4 outputColour = vec4(initialRay.direction, 1.0f);

	//
	// interesting stuff happens here later
	//
/*
	vec3 spherePosition = vec3(0.0f, 0.0f, 10.0f);
	float sphereSize = 1.0f;

	// hit sphere
	float t = -1.0f;
	vec3 oc = initialRay.origin - spherePosition;
	float a = dot(initialRay.direction, initialRay.direction);
	float b = 2.0f * dot(oc, initialRay.direction);
	float c = dot(oc, oc) - sphereSize * sphereSize;
	float discriminant = b * b - 4 * a * c;
	if (discriminant >= 0)
	{
		t = (-b - sqrt(discriminant)) / (2.0f * a);
	// vec3 N = normalize((initialRay.origin + (initialRay.direction * t)) - vec3(0.0f, 0.0f, -1.0f));
	}
 */
	if (hitSphere(initialRay, vec3(0.0f, 0.0f, 10.0f), 1.0f))
	{
		outputColour = vec4(0.0f, 0.0f, 1.0f, 1.0f);
	}
	else if (hitSphere(initialRay, vec3(0.0f, 0.0f, -10.0f), 1.0f))
	{
		outputColour = vec4(0.0f, 1.0f, 1.0f, 1.0f);
	}
	else if (hitSphere(initialRay, vec3(10.0f, 0.0f, 0.0f), 1.0f))
	{
		outputColour = vec4(1.0f, 0.0f, 0.0f, 1.0f);
	}
	else if (hitSphere(initialRay, vec3(-10.0f, 0.0f, 0.0f), 1.0f))
	{
		outputColour = vec4(1.0f, 1.0f, 0.0f, 1.0f);
	}


	// output to a specific pixel in the image
	imageStore(outputTexture, ivec2(gl_GlobalInvocationID.xy), outputColour);
}
