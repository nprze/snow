struct PSInput {
    float4 position : SV_POSITION;
    float4 color : COLOR;
};
PSInput VSMain(float2 position : POSITION0, float4 color : COLOR0) {
    PSInput result;
    result.position = float4(position, 0.0f, 1.0f);
    result.color = color;
    return result;
}
float4 PSMain(PSInput input) : SV_TARGET {
    return input.color;
};