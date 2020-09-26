struct appdata
{
	float4 vertex : POSITION;
	float2 uv : TEXCOORD0;
};

struct v2f
{
	float4 vertex : SV_POSITION;
	float2 uv : TEXCOORD0;	
};


v2f vert(appdata v)
{
	v2f o;
	o.vertex = UnityObjectToClipPos(v.vertex);
	o.uv = v.uv;

	return o;
}

sampler2D _MainTex;
sampler2D _NoiseTex;

sampler2D_float _CameraDepthTexture;
float4 _CameraDepthTexture_ST;

float4x4 _InverseViewMatrix;
float4x4 _InverseProjectionMatrix;

float3 GetWorldSpacePosition(float2 i_UV)
{
	float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i_UV);
	
	float4 positionViewSpace = mul(_InverseProjectionMatrix, float4(2.0 * i_UV - 1.0, depth, 1.0));
	positionViewSpace /= positionViewSpace.w;

	
	float3 positionWorldSpace = mul(_InverseViewMatrix, float4(positionViewSpace.xyz, 1.0)).xyz;
	return positionWorldSpace;
}

float4 frag(v2f i) : SV_Target
{
	float deviceZ = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);

	float3 positionWorldSpace = GetWorldSpacePosition(i.uv);	
	return float4(positionWorldSpace, 1);
}