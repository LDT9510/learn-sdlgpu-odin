#version 460

// interpolated from vertex data
layout(location = 0) in vec2 uv;

layout(location = 0) out vec4 frag_color;

// SDL_GPU requires set 2 for samplers
layout(set = 2, binding = 0) uniform sampler2D tex_sampler;

void main() {
    frag_color = texture(tex_sampler, uv);
}
