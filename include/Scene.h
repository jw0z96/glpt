#pragma once

#include <SDL2/SDL.h>

#include "OrbitalCamera.h"

#include "GLUtils/ShaderProgram.h"
#include "GLUtils/Buffer.h"
#include "GLUtils/VAO.h"
#include "GLUtils/Texture.h"

class Scene
{
public:
	Scene();

	// ~Scene(); // let the compiler do it

	void loadHDRI(const char* filepath);

	void processEvent(const SDL_Event& event);

	void resize(const unsigned int& width, const unsigned int& height);

	void render();

	void renderUI();

private:
	struct DispatchIndirectCommand
	{
		GLuint num_groups_x;
		GLuint num_groups_y;
		GLuint num_groups_z;
	};

	enum TonemappingMode : int
	{
		NONE = 0,
		ACES_FILMIC
	};

	bool initIndexFramebuffer(const unsigned int& width, const unsigned int& height);

	OrbitalCamera m_camera;

	const GLUtils::ShaderProgram m_computeShader, m_outputShader;
	const GLUtils::Buffer m_indirectComputeBuffer;
	const GLUtils::VAO m_emptyVAO;
	const GLUtils::Texture m_outputTex, m_skyTex;

	TonemappingMode m_tonemappingMode;
	float m_exposure;
	float m_focalDistance;
	float m_radius;
	GLuint m_frame;
};
