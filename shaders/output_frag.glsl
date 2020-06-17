#version 430

noperspective in vec2 uv;

out vec4 fragColour;

layout(rgba32f, binding = 0) uniform readonly image2D outputTexture;

uniform float exposure;

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

vec3 lessThan(vec3 f, float value)
{
	return vec3(
		(f.x < value) ? 1.0f : 0.0f,
		(f.y < value) ? 1.0f : 0.0f,
		(f.z < value) ? 1.0f : 0.0f);
}

vec3 linearToSRGB(vec3 rgb)
{
	rgb = clamp(rgb, 0.0f, 1.0f);

	return mix(
		pow(rgb, vec3(1.0f / 2.4f)) * 1.055f - 0.055f,
		rgb * 12.92f,
		lessThan(rgb, 0.0031308f)
	);
}

void main()
{
	ivec2 texCoords = ivec2(imageSize(outputTexture) * uv);
	vec3 outputColour = imageLoad(outputTexture, texCoords).rgb;

	// apply exposure (how long the shutter is open)
	outputColour *= exposure;

	// convert unbounded HDR color range to SDR color range
	outputColour = tonemapSelection(outputColour);

	// convert from linear to sRGB for display
	outputColour = linearToSRGB(outputColour);

	fragColour = vec4(outputColour, 1.0f);
}
