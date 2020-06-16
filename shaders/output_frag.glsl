#version 430

layout(rgba32f, binding = 0) uniform readonly image2D outputTexture;

// use subroutines to select tonemapping method
subroutine vec3 tonemap(vec3 inputColour);

subroutine uniform tonemap tonemapSelection;

subroutine (tonemap)
vec3 tonemapNone(vec3 inputColour)
{
	return inputColour;
}

// https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
subroutine (tonemap)
vec3 tonemapACESFilmic(vec3 inputColour)
{
	float a = 2.51f;
	float b = 0.03f;
	float c = 2.43f;
	float d = 0.59f;
	float e = 0.14f;
	return clamp(
		(inputColour * (a * inputColour + b)) / (inputColour * (c * inputColour + d) + e),
		0.0,
		1.0
	);
}

noperspective in vec2 uv;

out vec4 fragColour;

void main()
{
	ivec2 texCoords = ivec2(imageSize(outputTexture) * uv);
	vec3 outputColour = imageLoad(outputTexture, texCoords).rgb;
	fragColour = vec4(tonemapSelection(outputColour), 1.0f);
}
