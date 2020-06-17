#include "Scene.h"

#include <imgui/imgui.h>

#include <glm/gtc/type_ptr.hpp>

#include "GLUtils/Timer.h"

#include <algorithm>
#include <random>

#include <iostream>

Scene::Scene() :
	m_camera(),
	m_computeShader({{GL_COMPUTE_SHADER, "shaders/raytrace_comp.glsl"}}),
	m_outputShader({
		{GL_VERTEX_SHADER, "shaders/screenspace_vert.glsl"}, {GL_FRAGMENT_SHADER, "shaders/output_frag.glsl"}
	}),
	m_outputTex(),
	m_tonemappingMode(NONE)
{
	glDisable(GL_DEPTH_TEST);
	m_emptyVAO.bind();
	resize(800, 600); // these constants match those in main.cpp

	// Set constant uniforms on the shaders
	m_computeShader.use();
	glUniformMatrix4fv(
		m_computeShader.getUniformLocation("projection"),
		1,
		GL_FALSE,
		glm::value_ptr(m_camera.getProjection())
	);
}

void Scene::processEvent(const SDL_Event& event)
{
	if(event.type == SDL_WINDOWEVENT &&
		(event.window.event == SDL_WINDOWEVENT_RESIZED ||
			event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED))
	{
		resize(event.window.data1, event.window.data2); // implicit cast to uint
		m_camera.setAspect(event.window.data1, event.window.data2);
		m_computeShader.use();
		glUniformMatrix4fv(
			m_computeShader.getUniformLocation("projection"),
			1,
			GL_FALSE,
			glm::value_ptr(m_camera.getProjection())
		);
	}

	m_camera.processInput(event);
}

void Scene::resize(const unsigned int& width, const unsigned int& height)
{
	// we only resize the currently bound framebuffer, which should be default (0)
	glViewport(0, 0, width, height);

	// resize the texture resource
	m_outputTex.bindAs(GL_TEXTURE_2D);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, width, height, 0, GL_RGBA, GL_FLOAT, NULL);
	// bind mip level 0 of our texture to image unit 0 (which is not the same as the texture unit)
	m_outputTex.bindToImageUnit(0, 0, GL_FALSE, 0, GL_READ_WRITE, GL_RGBA32F);

	// set the indirect command buffer
	const DispatchIndirectCommand indirectCompute = {width, height, 1};
	m_indirectComputeBuffer.bindAs(GL_DISPATCH_INDIRECT_BUFFER);
	glBufferData(GL_DISPATCH_INDIRECT_BUFFER, sizeof(indirectCompute), &indirectCompute, GL_DYNAMIC_DRAW);

}

void Scene::render()
{
	GLUtils::scopedTimer(newFrameTimer);

	m_computeShader.use();
	glUniformMatrix4fv(
		m_computeShader.getUniformLocation("view"),
		1,
		GL_FALSE,
		glm::value_ptr(m_camera.getView())
	);

	glUniformMatrix4fv(
		m_computeShader.getUniformLocation("projection"),
		1,
		GL_FALSE,
		glm::value_ptr(m_camera.getProjection())
	);

	glDispatchComputeIndirect(0);

	// make sure image is finished writing
	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

	// blit the texture to the default framebuffer (and do some tonemapping if needed)
	glClear(GL_COLOR_BUFFER_BIT);
	// The vertex shader will create a screen space quad, but we do need an empty VAO in core profile
	m_outputShader.use();

	// select the tonemapping mode
	GLuint subRoutineIndex;
	switch(m_tonemappingMode)
	{
		case ACES_FILMIC:
			subRoutineIndex = m_outputShader.getSubroutineIndex(GL_FRAGMENT_SHADER, "tonemapACESFilmic");
		break;

		case NONE:
		default:
			subRoutineIndex = m_outputShader.getSubroutineIndex(GL_FRAGMENT_SHADER, "tonemapNone");
		break;
	}
	glUniformSubroutinesuiv(GL_FRAGMENT_SHADER, 1, &subRoutineIndex);

	glDrawArrays(GL_TRIANGLES, 0, 6);
}

void Scene::renderUI()
{
	// stats window
	ImGui::Begin("Stats");
	const float frameTime = GLUtils::getElapsed(newFrameTimer);
	ImGui::Text("Frame time: %.1f ms (%.1f fps)", frameTime, 1000.0f / frameTime);

	ImGui::Separator();

	ImGui::Text("Tonemapping Mode");
	const char* items[] = { "None", "ACEs Filmic"};
	int tonemappingSelect = m_tonemappingMode;
	ImGui::ListBox("", &tonemappingSelect, items, IM_ARRAYSIZE(items), 2);
	m_tonemappingMode = static_cast<TonemappingMode>(tonemappingSelect);

	ImGui::End();
}
