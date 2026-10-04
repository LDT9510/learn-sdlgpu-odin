cbuffer Global: register(b0, space3) {
    float3 lightPosition;
    float3 lightColor;
    float  lightIntensity;
};

// interpolated from vertex data
struct VS_Output {
    float3 Position: TEXCOORD0;
    float2 UV: TEXCOORD1; // UV not being used crashes DX12
    float3 Normal: TEXCOORD2;
};

// SDL_GPU requires space 2 for samplers
Texture2D Texture: register(t0, space2);
SamplerState Smp: register(s0, space2);

float4 main(VS_Output input): SV_Target0 {
    // rendering equation:
    // - outgoing radiance is a sum of emitted and reflected radiance
    // - emitted radiance is produces by our surface itself (lamp, screen, etc.)
    // - reflected radiance is produced by other surfaces (lights) and reflected by ours

    float3 vecToLight =  lightPosition - input.Position;
    float  distToLight = length(vecToLight);
    float3 dirToLight = vecToLight / distToLight;

    float3 surfaceNormal = normalize(input.Normal);

    float  incidenceAngleFactor = dot(dirToLight, surfaceNormal); // 1 - direct, 0 - no incidence, -1 from the other side
    float3 reflectedRadiance = float3(0, 0, 0);
    if (incidenceAngleFactor > 0) {
        float  attenuationFactor = 1 / pow(distToLight, 2); // TODO add more control variables
        float3 incomingRadiance = lightColor * lightIntensity;
        float3 brdf = 1;
        float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
        reflectedRadiance = irradiance * brdf;
    }

    float3 emittedRadiance = float3(0, 0, 0);
    float3 outRadiance = emittedRadiance + reflectedRadiance;

    return float4(outRadiance, 1);
}
