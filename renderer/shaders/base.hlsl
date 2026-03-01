struct PSInput {
    float4 position : SV_POSITION;
    float3 color : COLOR;
};
PSInput VSMain(float3 position : POSITION0, float3 color : COLOR0) {
    PSInput result;
    result.position = float4(position, 1.0f);
    result.color = color;
    return result;
}
float3 PSMain(PSInput input) : SV_TARGET {
    return input.color;
};