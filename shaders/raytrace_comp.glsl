#version 430

layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D outputTexture;

void main()
{
	vec2 textureDimensions = imageSize(outputTexture);
	vec2 uv = gl_GlobalInvocationID.xy / textureDimensions;
	vec4 outputColour = vec4(uv, 0.0, 1.0);

	//
	// interesting stuff happens here later
	//

	// output to a specific pixel in the image
	imageStore(outputTexture, ivec2(gl_GlobalInvocationID.xy), outputColour);
}
