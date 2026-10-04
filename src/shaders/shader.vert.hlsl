cbuffer UBO: register(b0, space1) { // TODO separate local and global UBOs
    float4x4 VP;
    float4x4 M;
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
    float4 worldPosition = mul(M, float4(input.Position, 1.0));

    Output output;
    output.ClipPosition = mul(VP, worldPosition);
    output.UV = input.UV;
    output.Position = worldPosition.xyz;
    output.Normal = normalize(mul(M, float4(input.Normal, 0)).xyz); // TODO fix non-uniform scale

    return output;
}
