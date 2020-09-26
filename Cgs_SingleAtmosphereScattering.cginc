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

#define PI 3.14159265359

float _AtmosphereHeight;
float _PlanetRadius;
float2 _DensityScaleHeight;

float3 _ScatteringR;
float3 _ScatteringM;
float3 _ExtinctionR;
float3 _ExtinctionM;

float4 _IncomingLight;
float _MieG;

float _SunIntensity;
float _DistanceScale;

float3 _LightDir;

float4x4 _InverseViewMatrix;
float4x4 _InverseProjectionMatrix;

int _SampleCount;





sampler2D _MainTex;
sampler2D _NoiseTex;

sampler2D_float _CameraDepthTexture;
float4 _CameraDepthTexture_ST;

float3 GetWorldSpacePosition(float2 i_UV)
{
	float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i_UV);
	
	float4 positionViewSpace = mul(_InverseProjectionMatrix, float4(2.0 * i_UV - 1.0, depth, 1.0));
	positionViewSpace /= positionViewSpace.w;

	
	float3 positionWorldSpace = mul(_InverseViewMatrix, float4(positionViewSpace.xyz, 1.0)).xyz;
	return positionWorldSpace;
}


float3 ACESFilm(float3 x)
{
	float a = 2.51f;
	float b = 0.03f;
	float c = 2.43f;
	float d = 0.59f;
	float e = 0.14f;
	return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}


//-----------------------------------------------------------------------------------------
// Helper Funcs 1 : RaySphereIntersection
//-----------------------------------------------------------------------------------------
float2 RaySphereIntersection(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
{
	rayOrigin -= sphereCenter;
	float a = dot(rayDir, rayDir);
	float b = 2.0 * dot(rayOrigin, rayDir);
	float c = dot(rayOrigin, rayOrigin) - (sphereRadius * sphereRadius);
	float d = b * b - 4 * a * c;
	if (d < 0)
	{
		return -1;
	}
	else
	{
		d = sqrt(d);
		return float2(-b - d, -b + d) / (2 * a);
	}
}




//-----------------------------------------------------------------------------------------
// Helper Funcs 2 : ShaodwMap Funcs
//-----------------------------------------------------------------------------------------

inline fixed4 GetCascadeWeights_SplitSpheres(float3 wpos)
{
	float3 fromCenter0 = wpos.xyz - unity_ShadowSplitSpheres[0].xyz;
	float3 fromCenter1 = wpos.xyz - unity_ShadowSplitSpheres[1].xyz;
	float3 fromCenter2 = wpos.xyz - unity_ShadowSplitSpheres[2].xyz;
	float3 fromCenter3 = wpos.xyz - unity_ShadowSplitSpheres[3].xyz;
	float4 distances2 = float4(dot(fromCenter0, fromCenter0), dot(fromCenter1, fromCenter1), dot(fromCenter2, fromCenter2), dot(fromCenter3, fromCenter3));
//#if SHADER_TARGET > 30
	fixed4 weights = float4(distances2 < unity_ShadowSplitSqRadii);
	weights.yzw = saturate(weights.yzw - weights.xyz);
//#else
//			fixed4 weights = float4(distances2 >= unity_ShadowSplitSqRadii);
//#endif
	return weights;
}

inline float getShadowFade_SplitSpheres(float3 wpos)
{
	float sphereDist = distance(wpos.xyz, unity_ShadowFadeCenterAndType.xyz);
	half shadowFade = saturate(sphereDist * _LightShadowData.z + _LightShadowData.w);
	return shadowFade;
}

inline float4 GetCascadeShadowCoord(float4 wpos, fixed4 cascadeWeights)
{
	float3 sc0 = mul(unity_WorldToShadow[0], wpos).xyz;
	float3 sc1 = mul(unity_WorldToShadow[1], wpos).xyz;
	float3 sc2 = mul(unity_WorldToShadow[2], wpos).xyz;
	float3 sc3 = mul(unity_WorldToShadow[3], wpos).xyz;
	float4 shadowMapCoordinate = float4(sc0 * cascadeWeights[0] + sc1 * cascadeWeights[1] + sc2 * cascadeWeights[2] + sc3 * cascadeWeights[3], 1);
#if defined(UNITY_REVERSED_Z)
	float  noCascadeWeights = 1 - dot(cascadeWeights, float4(1, 1, 1, 1));
	shadowMapCoordinate.z += noCascadeWeights;
#endif
	return shadowMapCoordinate;
}

UNITY_DECLARE_SHADOWMAP(_CascadeShadowMapTexture);

float GetLightAttenuation(float3 wpos)
{
	float atten = 1;
	// sample cascade shadow map
	float4 cascadeWeights = GetCascadeWeights_SplitSpheres(wpos);
	bool inside = dot(cascadeWeights, float4(1, 1, 1, 1)) < 4;
	float4 samplePos = GetCascadeShadowCoord(float4(wpos, 1), cascadeWeights);

	//atten = UNITY_SAMPLE_SHADOW(_CascadeShadowMapTexture, samplePos.xyz);
	atten = inside ? UNITY_SAMPLE_SHADOW(_CascadeShadowMapTexture, samplePos.xyz) : 1.0f;
	//atten += getShadowFade_SplitSpheres(wpos);

	//atten = _LightShadowData.r + atten * (1 - _LightShadowData.r);

	return atten;
}


//-----------------------------------------------------------------------------------------
// Helper Funcs 3 : Sun
//-----------------------------------------------------------------------------------------
float Sun(float cosAngle)
{
	float g = 0.98;
	float g2 = g * g;

	float sun = pow(1 - g, 2.0) / (4 * PI * pow(1.0 + g2 - 2.0*g*cosAngle, 1.5));
	return sun * 0.003;// 5;
}
float3 RenderSun(in float3 scatterM, float cosAngle)
{
	return scatterM * Sun(cosAngle);
}


//-----------------------------------------------------------------------------------------
// Helper Funcs 4 : Atmosphere Funs
//-----------------------------------------------------------------------------------------
//----- Input
// position			视线采样点P
// lightDir			光照方向

//----- Output : 
// opticalDepthCP:	dcp
void lightSampleing(
	float3 position,							// Current point within the atmospheric sphere
	float3 lightDir,							// Direction towards the sun
	out float2 opticalDepthCP)
{
	opticalDepthCP = 0;

	float3 rayStart = position;
	float3 rayDir = -lightDir;

	float3 planetCenter = float3(0, -_PlanetRadius, 0);

	float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
	float3 rayEnd = rayStart + rayDir * intersection.y;

	// compute density along the ray
	float stepCount = 50;// 250;
	float3 step = (rayEnd - rayStart) / stepCount;
	float stepSize = length(step);
	float2 density = 0;

	for (float s = 0.5; s < stepCount; s += 1.0)
	{
		float3 position = rayStart + step * s;
		float height = abs(length(position - planetCenter) - _PlanetRadius);
		float2 localDensity = exp(-(height.xx / _DensityScaleHeight));

		density += localDensity * stepSize;
	}

	opticalDepthCP = density;
}

//----- Input
// position			视线采样点P
// lightDir			光照方向

//----- Output : 
//localDensity	    p点density	
//densityToAtmTop 	dpc
void GetAtmosphereDensityRealtime(float3 position, float3 planetCenter, float3 lightDir, out float2 localDensity, out float2 densityToAtmTop)
{
	float height = length(position - planetCenter) - _PlanetRadius;
	localDensity = exp(-height.xx / _DensityScaleHeight.xy);

	lightSampleing(position, lightDir, densityToAtmTop);
}

//----- Input
// localDensity			rho(h)
// densityPC
// densityAP

//----- Output : 
// localInscatterR 
// localInscatterM
void ComputeLocalInscattering(float2 localDensity, float2 densityPC, float2 densityAP, out float3 localInscatterR, out float3 localInscatterM)
{
	float2 densityCPA = densityAP + densityPC;

	float3 Tr = densityCPA.x * _ExtinctionR;
	float3 Tm = densityCPA.y * _ExtinctionM;

	float3 extinction = exp(-(Tr + Tm));

	localInscatterR = localDensity.x * extinction;
	localInscatterM = localDensity.y * extinction;
}

//----- Input
// cosAngle			散射角

//----- Output : 
// scatterR 
// scatterM
void ApplyPhaseFunction(inout float3 scatterR, inout float3 scatterM, float cosAngle)
{
	// r
	float phase = (3.0 / (16.0 * PI)) * (1 + (cosAngle * cosAngle));
	scatterR *= phase;

	// m
	float g = _MieG;
	float g2 = g * g;
	phase = (1.0 / (4.0 * PI)) * ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + cosAngle * cosAngle) / (pow((1 + g2 - 2 * g * cosAngle), 3.0 / 2.0)));
	scatterM *= phase;
}

//----- Input
// rayStart			视线起点 A
// rayDir			视线方向
// rayLength		AB 长度
// planetCenter		地球中心坐标
// distanceScale	世界坐标的尺寸
// lightdir			太阳光方向
// sampleCount		AB 采样次数

//----- Output : 
// extinction       T(AP)
// inscattering:	Inscatering
float4 IntegrateInscatteringRealtime(float3 rayStart, float3 rayDir, float rayLength, float3 planetCenter, float distanceScale, float3 lightDir, float sampleCount, out float4 extinction)
{
	float3 step = rayDir * (rayLength / sampleCount);
	float stepSize = length(step) * distanceScale;

	float2 densityAP = 0;
	float3 scatterR = 0;
	float3 scatterM = 0;

	float2 localDensity;
	float2 densityPC;

	float2 prevLocalDensity;
	float3 prevLocalInscatterR, prevLocalInscatterM;
	GetAtmosphereDensityRealtime(rayStart, planetCenter, lightDir, prevLocalDensity, densityPC);

	ComputeLocalInscattering(prevLocalDensity, densityPC, densityAP, prevLocalInscatterR, prevLocalInscatterM);

	// P - current integration point
	// A - camera position
	// C - top of the atmosphere
	[loop]
	for (float s = 1.0; s < sampleCount; s += 1)
	{
		float3 p = rayStart + step * s;

		GetAtmosphereDensityRealtime(p, planetCenter, lightDir, localDensity, densityPC);	
		
		densityAP += (localDensity + prevLocalDensity) * (stepSize / 2.0);
		float3 localInscatterR, localInscatterM;
		ComputeLocalInscattering(localDensity, densityPC, densityAP, localInscatterR, localInscatterM);

		scatterR += (localInscatterR + prevLocalInscatterR) * (stepSize / 2.0);
		scatterM += (localInscatterM + prevLocalInscatterM) * (stepSize / 2.0);

		prevLocalInscatterR = localInscatterR;
		prevLocalInscatterM = localInscatterM;

		prevLocalDensity = localDensity;	
	}

	float3 m = scatterM;
	// phase function
	ApplyPhaseFunction(scatterR, scatterM, dot(rayDir, -lightDir.xyz));
	//scatterR = 0;
	float3 lightInscatter = (scatterR * _ScatteringR + scatterM * _ScatteringM) * _IncomingLight.xyz;
	float3 lightExtinction = exp(-(densityAP.x * _ExtinctionR + densityAP.y * _ExtinctionM));

	extinction = float4(lightExtinction, 0);
	return float4(lightInscatter, 1);
}



float4 frag(v2f i) : SV_Target
{
	float deviceZ = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);

	float3 positionWorldSpace = GetWorldSpacePosition(i.uv);	

	float3 rayStart = _WorldSpaceCameraPos;
	float3 rayDir = positionWorldSpace - _WorldSpaceCameraPos;
	float rayLength = length(rayDir);
	rayDir /= rayLength;

	if (deviceZ < 0.000001)
	{
		rayLength = 1e20;
	}

	float3 planetCenter = float3(0, -_PlanetRadius, 0);
	float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
	
	rayLength = min(intersection.y, rayLength);	

	float4 extinction;	
	if (deviceZ < 0.000001)
	{		
		float4 inscattering = IntegrateInscatteringRealtime(rayStart, rayDir, rayLength, planetCenter, 1, _LightDir, _SampleCount, extinction);
		return inscattering;
	}
	else
	{
		return 0;
		
	}

	//return float4(positionWorldSpace, 1);
}