#version 460

layout(set = 1, binding = 0) uniform UBO {
    mat4 mvp;
};

void main() {
    vec3 position;

    switch (gl_VertexIndex) {
        case 0:
        position = vec3(-.5, -.5, 0.);
        break;
        case 1:
        position = vec3(.0, .5, 0.);
        break;
        case 2:
        position = vec3(.5, -.5, 0.);
        break;
    }

    gl_Position = mvp * vec4(position, 1.0);
}
