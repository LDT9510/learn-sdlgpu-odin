#version 460

// interpolated from vertex data
layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;

layout(location = 0) out vec4 frag_color;

// SDL_GPU requires set 2
layout(set = 2, binding = 0) uniform sampler2D tex_sampler;

void main() {
    frag_color = texture(tex_sampler, uv) * color;
}
