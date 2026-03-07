struct PSInput {
    float4 position : SV_POSITION;
    float4 color : COLOR;
    float2 uv : TEXCOORD;
};
PSInput VSMain(float2 position : POSITION0, float2 uv : TEXCOORD0, float4 color : COLOR0) {
    PSInput result;
    result.position = float4(position, 0.0, 1.0);
    result.color = color;
    result.uv = uv;
    return result;
}


Texture2D tex : register(t0);
SamplerState samp : register(s0);
float4 PSMain(PSInput input) : SV_TARGET {
    float4 sampled = tex.Sample(samp, input.uv);
    return input.color * sampled;
};