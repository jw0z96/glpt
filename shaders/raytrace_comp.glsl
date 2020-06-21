#version 430

// layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout (local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

layout(binding = 1) uniform sampler2D skyTexture;

uniform uint frame;

uniform float focalDistance;
uniform float apertureRadius;
uniform mat4 view;
uniform mat4 projection;

// mesh data
uniform uint meshNumFaces;

layout(std430, binding = 0) readonly buffer meshVertexIndicesBuffer
{
	int vertexIndices[];
};

layout(std430, binding = 1) readonly buffer meshNormalIndicesBuffer
{
	int normalIndices[];
};

layout(std430, binding = 2) readonly buffer meshVerticesBuffer
{
	float vertices[];
};

layout(std430, binding = 3) readonly buffer meshNormalsBuffer
{
	float normals[];
};

const vec3 meshColour = vec3(1.0f, 0.2f, 0.2f);
const float meshRoughness = 0.2f;
const float meshEmission = 0.0f;

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

#define TRACE_DEPTH 4

struct Ray
{
	vec3 origin;
	vec3 direction;
};

struct HitInfo
{
	float dist;
	// int index; // the index of the sphere we hit
	int index; // the index of the triangle we hit (in the single mesh we have)

	vec2 bary;
};

vec2 equirectangularLookup(vec3 dir)
{
	vec2 uv = vec2(atan(dir.z, dir.x), acos(dir.y));
	uv /= vec2(TWO_PI, PI);
	return uv;
}

void hitTriangle(Ray ray, int index, inout HitInfo info)
{
	vec3 vertex0 = vec3(
		vertices[vertexIndices[index * 3 + 0] * 3 + 0],
		vertices[vertexIndices[index * 3 + 0] * 3 + 1],
		vertices[vertexIndices[index * 3 + 0] * 3 + 2]
	);

	vec3 vertex1 = vec3(
		vertices[vertexIndices[index * 3 + 1] * 3 + 0],
		vertices[vertexIndices[index * 3 + 1] * 3 + 1],
		vertices[vertexIndices[index * 3 + 1] * 3 + 2]
	);

	vec3 vertex2 = vec3(
		vertices[vertexIndices[index * 3 + 2] * 3 + 0],
		vertices[vertexIndices[index * 3 + 2] * 3 + 1],
		vertices[vertexIndices[index * 3 + 2] * 3 + 2]
	);

	vec3 edge01 = vertex1 - vertex0;
	vec3 edge02 = vertex2 - vertex0;

	vec3 pvec = cross(ray.direction, edge02);
	float det = dot(edge01, pvec);

	if (det < 0.001f) return; // epsilon, if det is negative the hit is backfacing

	float invDet = 1.0f / det;

	vec3 tvec = ray.origin - vertex0;
	float u = dot(tvec, pvec) * invDet;
	if (u < 0 || u > 1) return;

	vec3 qvec = cross(tvec, edge01);
	float v = dot(ray.direction, qvec) * invDet;
	if (v < 0 || u + v > 1) return;

	float t = dot(edge02, qvec) * invDet;

	if (t < info.dist || info.index == -1)
	{
		info.dist = t;
		info.index = index;
		info.bary.x = u;
		info.bary.y = v;
	}
}

HitInfo hitMesh(Ray ray)
{
	// TODO: loop over meshNumFaces
	HitInfo info;
	info.dist = -1.0f; // max trace distance?? // could be hit position instead?
	info.index = -1;

	// for (int i = 0; i < meshNumFaces; ++i)
	for (int i = 0; i < 10; ++i)
	{
		hitTriangle(ray, i, info);
	}

	return info;
}

vec3 diffuseSample(vec3 normal)
{
	return normalize(normal + randomUnitVector(rngSeed));
}

// get the next ray
vec3 surfaceDistribution(vec3 view, vec3 normal, float roughness) // material
{
	return randomFloat(rngSeed) < roughness ?
	// 	diffuseSample(normal) :
		normalize(normal + roughness * randomUnitVector(rngSeed)) :
		normalize(reflect(view, normal) + (1.0f - roughness) * randomUnitVector(rngSeed));
	// 	reflect(view, normal);
	// return reflect(view, normal);
	// return diffuseSample(view, normal);

}

vec3 radiance(Ray ray)
{
	vec3 outputColour = vec3(0.0f);
	vec3 surfaceColour = vec3(1.0f); // start at 1.0f, multiply through by the surface colour of the spheres

	HitInfo info;
	for (uint depth = 0; depth < TRACE_DEPTH; ++depth)
	{
		info = hitMesh(ray);

		if (info.index == -1) // the ray didn't hit anything
		{
			outputColour += surfaceColour * texture(skyTexture, equirectangularLookup(ray.direction)).rgb;
			break;
		}

		// get the normals and interpolate them using barycentric coordinates
		vec3 normal0 = vec3(
			normals[normalIndices[info.index * 3 + 0] * 3 + 0],
			normals[normalIndices[info.index * 3 + 0] * 3 + 1],
			normals[normalIndices[info.index * 3 + 0] * 3 + 2]
		);

		vec3 normal1 = vec3(
			normals[normalIndices[info.index * 3 + 1] * 3 + 0],
			normals[normalIndices[info.index * 3 + 1] * 3 + 1],
			normals[normalIndices[info.index * 3 + 1] * 3 + 2]
		);

		vec3 normal2 = vec3(
			normals[normalIndices[info.index * 3 + 2] * 3 + 0],
			normals[normalIndices[info.index * 3 + 2] * 3 + 1],
			normals[normalIndices[info.index * 3 + 2] * 3 + 2]
		);

		// vec3 normal = info.bary.x * normal0 + info.bary.y * normal1 + (1.0f - info.bary.x - info.bary.y) * normal2;
		vec3 normal = info.bary.x * normal1 + info.bary.y * normal2 + (1.0f - info.bary.x - info.bary.y) * normal0;
		normal = normalize(normal);

		vec3 hitPos = ray.origin + ray.direction * info.dist;
		ray.origin = hitPos + normal * 0.01f; // avoid self intersection?
		ray.direction = surfaceDistribution(ray.direction, normal, meshRoughness);

		outputColour += surfaceColour * meshEmission; // ???
		surfaceColour *= meshColour;

		// do 'russian roulette' sampling - as our sufaceColour reduces, the chances of terminating a ray
		// increases, as it will be less likely to contribute to our image
		/*
		if ((float(gl_GlobalInvocationID.x) / imageSize(outputTexture).x) > 0.5f)
		{
			// float rayProbability = sphereRoughness[info.index];
			// rayProbability = max(rayProbability, 0.001f);
			// surfaceColour /= rayProbability;

			float p = max(surfaceColour.r, max(surfaceColour.g, surfaceColour.b));
			if (randomFloat(rngSeed) > p)
			{
				break;
			}

			// Add the energy we 'lose' by randomly terminating paths
			surfaceColour /= p;
		}
		*/
	}

	return outputColour;
}

void main()
{
	ivec2 textureDimensions = imageSize(outputTexture);

	uvec2 index = gl_GlobalInvocationID.xy;

	if (index.x >- textureDimensions.x || index.y >- textureDimensions.y)
	{
		return;
	}

	// We get the camera's center by multiplying the inverse view matrix through the origin
	mat4 inView = inverse(view);
	vec3 cameraCenter = (inView * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

	// TODO: loop here for num samples?
	Ray initialRay;

	// offset the center by our camera radius (to model depth of field)
	if (apertureRadius > 0.0f)
	{
		float r = apertureRadius * 0.5f * sqrt(randomFloat(rngSeed));
		float theta = randomFloat(rngSeed) * TWO_PI;
		vec2 apertureOffset = vec2(r * cos(theta), r * sin(theta));
		initialRay.origin = (inView * vec4(apertureOffset, 0.0f, 1.0f)).xyz;
	}
	else
	{
		initialRay.origin = cameraCenter;
	}

	//Wrandom offset between [-0.5, 0.5] to do random sampling around the pixel center
	vec2 jitter = vec2(randomFloat(rngSeed), randomFloat(rngSeed)) - 0.5f;

	// projection[1][1] gets us tan(0.5 * fov), with fov in radians, which gives us the correct fov
	// https://stackoverflow.com/questions/46182845/field-of-view-aspect-ratio-view-matrix-from-projection-matrix-hmd-ost-calib
	vec2 uv = vec2(index + jitter) / textureDimensions;
	initialRay.direction = vec3(uv * 2.0f - 1.0f, -projection[1][1]);

	// Extract the aspect ratio from the projection matrix, and correct for it
	initialRay.direction.y /= projection[1][1] / projection[0][0];

	initialRay.direction = (vec4(initialRay.direction, 1.0f) * view).xyz;
	initialRay.direction = normalize(initialRay.direction);

	// adjust the direction to account for the new origin, if we're modelling dof
	if (apertureRadius > 0.0f)
	{
		float distanceToOrigin = length(cameraCenter);
		initialRay.direction = normalize(
			(cameraCenter + initialRay.direction * distanceToOrigin) - initialRay.origin
		);
		// initialRay.direction = normalize(
		// 	(cameraCenter + initialRay.direction * focalDistance) - initialRay.origin
		// );
	}

	// add the sample from the scene with the colour in the texture
	vec4 outputColour = mix(
		imageLoad(outputTexture, ivec2(index)),
		vec4(radiance(initialRay), 1.0f),
		1.0f / float(frame + 1)
	);
	imageStore(outputTexture, ivec2(index), outputColour);
}
