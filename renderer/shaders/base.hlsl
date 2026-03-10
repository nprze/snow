struct PSInput {
    float4 position : SV_POSITION;
    float3 pos: POSITION;
    float3 normal: NORMAL;
    float3 color : COLOR;
};
cbuffer CameraBuffer : register(b0)
{
    float4x4 viewProj;
};
PSInput VSMain(float3 position : POSITION0, float3 normal : NORMAL0, float3 color : COLOR0) {
    PSInput result;
    result.position = mul(float4(position, 1.0f), viewProj);
    result.color = color;
    result.pos = position;
    result.normal = normal;
    return result;
}
float4 PSMain(PSInput input) : SV_TARGET {
    float3 lightPosition = {0,3,0};
    float3 lightColor = {0.5,0.5,1};
    
    float3 norm = normalize(input.normal);
    float3 toLight = normalize(lightPosition - input.pos);
    
    
    float specular = pow(max(dot(toLight, norm), 0), 32) * 0.5;
    float3 diffuse = lightColor * max(dot(toLight, norm), 0) * 0.4;
    float3 ambient = input.color * 0.3;

    return float4(float3(specular, specular, specular) + ambient + diffuse, 1.0);
};