struct PSInput {
    float4 position : SV_POSITION;
    float3 pos: POSITION;
    float3 normal: NORMAL;
    float3 color : COLOR;
    float2 uv : UV;
};
cbuffer CameraBuffer : register(b0)
{
    float4x4 viewProj;
};
StructuredBuffer<float4x4> ModelMatrices : register(t0);
PSInput VSMain(float3 position : POSITION0, float3 normal : NORMAL0, float3 color : COLOR0, float2 uv: TEXCOORD0, uint modelMatrix: INDEX0) {
    PSInput result;
    float4 worldPos = mul(float4(position, 1.0f), ModelMatrices[modelMatrix]);
    result.position = mul(worldPos, viewProj);
    result.color = color;
    result.pos = worldPos.xyz;
    float3 worldNormal = mul((float3x3)ModelMatrices[modelMatrix], normal);
    result.normal = normalize(worldNormal);
    result.uv = uv;
    return result;
}
float rand(float x)
{
    return frac(sin(x) * 43758.5453123);
}
Texture2D tex : register(t1);
SamplerState samp : register(s0);
float4 PSMain(PSInput input) : SV_TARGET {
    float3 lightPosition = {0,200,0};
    float3 lightColor = {0.4, 0.4, 0.7};

    float3 sampled = tex.Sample(samp, input.uv);
    float noise = length(sampled);
    float random = noise * 2 * 3.14;

    float3 normal = normalize(input.normal);
    float3 up = abs(normal.y) > 0.99 ? float3(1,0,0) : float3(0,1,0);
    float3 tangent = normalize(cross(normal, up));
    float3 bitangent = normalize(cross(normal, tangent));

    float toAddVector = normalize(tangent * cos(random) + bitangent * sin(random)) * 0.1 * noise;

    float3 flucNormal = normalize(normal+toAddVector);

    float3 toLight = normalize(lightPosition - input.pos);
    
    float specular = pow(max(dot(toLight, flucNormal), 0), 32) * 0.5;
    float3 diffuse = lightColor * max(dot(toLight, flucNormal), 0) * 0.4;
    float3 ambient = input.color * 0.8 * (0.1 * noise.x +0.9);

    return float4(float3(specular, specular, specular) + ambient + diffuse, 1.0);
};