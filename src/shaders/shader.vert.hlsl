cbuffer UBO: register(b0, space1) {
    float4x4 MVP;
};

struct Input {
    float3 Position: TEXCOORD0;
    float2 UV: TEXCOORD1;
};

struct Output {
    float2 UV: TEXCOORD0;
    float4 Position: SV_Position;
};

Output main(Input input) {
    Output output;
    output.UV = input.UV;
    output.Position = mul(MVP, float4(input.Position, 1.0));

    return output;
}
