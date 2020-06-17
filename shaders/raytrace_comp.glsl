#version 430

layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

uniform mat4 view;
uniform mat4 projection;

void main()
{
	vec2 textureDimensions = imageSize(outputTexture);
	vec2 uv = gl_GlobalInvocationID.xy / textureDimensions;

	vec3 rayOrigin = (inverse(view) * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

	vec3 rayDirection = normalize(vec3(uv * 2.0f - 1.0f, 1.0f));

	// rayDirection = (vec4(rayDirection, 1.0f) * projection).xyz;
	// rayDirection = normalize(rayDirection);

	rayDirection = (vec4(rayDirection, 1.0f) * view).xyz;
	rayDirection = normalize(rayDirection);

	//
	// interesting stuff happens here later
	//

	vec4 outputColour = vec4(rayDirection, 1.0f);

	// output to a specific pixel in the image
	imageStore(outputTexture, ivec2(gl_GlobalInvocationID.xy), outputColour);
}
