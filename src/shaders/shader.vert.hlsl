cbuffer Global: register(b0, space1) {
    float4x4 ViewProjectionMat;
};

cbuffer Local: register(b1, space1) {
    float4x4 ModelMat;
    float4x4 NormalMat;
};

struct Input {
    float3 Position: TEXCOORD0;
    float2 UV: TEXCOORD1;
    float3 Normal: TEXCOORD2;
};

struct Output {
    float4 ClipPosition: SV_Position;
    float3 Position: TEXCOORD0;
    float2 UV: TEXCOORD1;
    float3 Normal: TEXCOORD2;
};

Output main(Input input) {
    float4 worldPosition = mul(ModelMat, float4(input.Position, 1.0));

    Output output;
    output.ClipPosition = mul(ViewProjectionMat, worldPosition);
    output.UV = input.UV;
    output.Position = worldPosition.xyz;
    output.Normal = normalize(mul(NormalMat, float4(input.Normal, 0)).xyz);

    return output;
}
