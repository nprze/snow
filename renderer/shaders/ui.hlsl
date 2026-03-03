struct PSInput {
    float4 position : SV_POSITION;
    float3 color : COLOR;
    int index : TEXCOORD0;
};
PSInput VSMain(float2 position : POSITION0, float3 color : COLOR0, int index : TEXCOORD0) {
    PSInput result;
    result.position = float4(position, 1.0f, 1.0f);
    result.color = color;
    result.index = index;
    return result;
}
float3 PSMain(PSInput input) : SV_TARGET {
    return input.color;
};