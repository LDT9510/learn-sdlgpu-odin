#version 460

void main() {
    switch (gl_VertexIndex) {
        case 0:
        gl_Position = vec4(-.5, -.5, .0, 1.0);
        break;
        case 1:
        gl_Position = vec4(.0, .5, .0, 1.0);
        break;
        case 2:
        gl_Position = vec4(.5, -.5, .0, 1.0);
        break;
    }
}
