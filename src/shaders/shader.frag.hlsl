// interpolated from vertex data
struct VS_Output {
    float2 UV: TEXCOORD0;
};

// SDL_GPU requires space 2 for samplers
Texture2D Texture: register(t0, space2);
SamplerState Smp: register(s0, space2);

float4 main(VS_Output input): SV_Target0 {
    return Texture.Sample(Smp, input.UV);
}
