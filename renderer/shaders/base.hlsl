struct PSInput {
    float4 position : SV_POSITION;
    float3 color : COLOR;
};
cbuffer CameraBuffer : register(b0)
{
    float4x4 viewProj;
};
PSInput VSMain(float3 position : POSITION0, float3 color : COLOR0) {
    PSInput result;
    result.position = mul(float4(position, 1.0f), viewProj);
    result.color = color;
    return result;
}
float4 PSMain(PSInput input) : SV_TARGET {
    return float4(input.color, 1.0);
};