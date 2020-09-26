Shader "CustomShader/Shader_SingleAtmosphereScattering"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
	}
		SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"
			#include "Cgs_SingleAtmosphereScattering.cginc"



			ENDCG
		}
	}
}


