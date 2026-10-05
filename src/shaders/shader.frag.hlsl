cbuffer Global: register(b0, space3) {
    float3 LightPosition;
    float3 LightColor;
    float  LightIntensity;
    float3 ViewPosition;
    float3 AmbientLight;
};

cbuffer Local: register(b1, space3) {
    float3 MaterialSpecularColor;
    float  Shininess;
}

// interpolated from vertex data
struct VS_Output {
    float3 Position: TEXCOORD0;
    float2 UV: TEXCOORD1; // UV not being used crashes DX12
    float3 Normal: TEXCOORD2;
};

// SDL_GPU requires space 2 for samplers
Texture2D DiffuseMap: register(t0, space2);
SamplerState Smp: register(s0, space2);

float3 blinnPhongBRDF(float3 dirToLight, float3 dirToView, float3 surfaceNormal, float3 diffuseTexel) {
    float3 materialDiffuseReflection = diffuseTexel;

    float3 halfwayDir = normalize(dirToLight + dirToView);
    float specularDot = max(0, dot(halfwayDir, surfaceNormal));
    float specularFactor = pow(specularDot, Shininess);
    float3 specularReflection = MaterialSpecularColor * specularFactor;

    return materialDiffuseReflection + specularReflection; // TODO energy conservation
}

float3 sampleDiffuse(float2 uv) {
    return DiffuseMap.Sample(Smp, uv).rgb;
}

float4 main(VS_Output input): SV_Target0 {
    // rendering equation:
    // - outgoing radiance is a sum of emitted and reflected radiance
    // - emitted radiance is produces by our surface itself (lamp, screen, etc.)
    // - reflected radiance is produced by other surfaces (lights) and reflected by ours

    float3 vecToLight =  LightPosition - input.Position;
    float  distToLight = length(vecToLight);
    float3 dirToLight = vecToLight / distToLight;
    float3 surfaceNormal = normalize(input.Normal);
    float3 ambientIrradiance = AmbientLight;
    float3 dirToView = normalize(ViewPosition - input.Position);
    float  incidenceAngleFactor = dot(dirToLight, surfaceNormal); // 1 - direct, 0 - no incidence, -1 from the other side

    float3 reflectedRadiance = ambientIrradiance * sampleDiffuse(input.UV);
    if (incidenceAngleFactor > 0) {
        float  attenuationFactor = 1 / pow(distToLight, 2); // TODO add more control variables
        float3 incomingRadiance = LightColor * LightIntensity;
        float3 brdf = blinnPhongBRDF(dirToLight, dirToView, input.Normal, sampleDiffuse(input.UV));
        float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
        reflectedRadiance += irradiance * brdf;
    }

    float3 emittedRadiance = float3(0, 0, 0);
    float3 outRadiance = emittedRadiance + reflectedRadiance;

    return float4(outRadiance, 1);
}
