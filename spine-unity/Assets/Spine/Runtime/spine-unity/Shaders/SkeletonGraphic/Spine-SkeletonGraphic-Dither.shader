// This is a premultiply-alpha adaptation of the built-in Unity shader "UI/Default" in Unity 5.6.2 to allow Unity UI stencil masking.

Shader "Spine/SkeletonGraphic Dither"
{
	Properties
	{
		[PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
		[Toggle(_STRAIGHT_ALPHA_INPUT)] _StraightAlphaInput("Straight Alpha Texture", Int) = 0
		[Toggle(_CANVAS_GROUP_COMPATIBLE)] _CanvasGroupCompatible("CanvasGroup Compatible", Int) = 1
		_Color ("Tint", Color) = (1,1,1,1)

		[HideInInspector][Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("Stencil Comparison", Float) = 8
		[HideInInspector] _Stencil ("Stencil ID", Float) = 0
		[HideInInspector][Enum(UnityEngine.Rendering.StencilOp)] _StencilOp ("Stencil Operation", Float) = 0
		[HideInInspector] _StencilWriteMask ("Stencil Write Mask", Float) = 255
		[HideInInspector] _StencilReadMask ("Stencil Read Mask", Float) = 255

		[HideInInspector] _ColorMask ("Color Mask", Float) = 15

		[Toggle(UNITY_UI_ALPHACLIP)] _UseUIAlphaClip ("Use Alpha Clip", Float) = 0

		// Outline properties are drawn via custom editor.
		[HideInInspector] _OutlineWidth("Outline Width", Range(0,8)) = 3.0
		[HideInInspector] _OutlineColor("Outline Color", Color) = (1,1,0,1)
		[HideInInspector] _OutlineReferenceTexWidth("Reference Texture Width", Int) = 1024
		[HideInInspector] _ThresholdEnd("Outline Threshold", Range(0,1)) = 0.25
		[HideInInspector] _OutlineSmoothness("Outline Smoothness", Range(0,1)) = 1.0
		[HideInInspector][MaterialToggle(_USE8NEIGHBOURHOOD_ON)] _Use8Neighbourhood("Sample 8 Neighbours", Float) = 1
		[HideInInspector] _OutlineOpaqueAlpha("Opaque Alpha", Range(0,1)) = 1.0
		[HideInInspector] _OutlineMipLevel("Outline Mip Level", Range(0,3)) = 0
	}

	SubShader
	{
		Tags
		{
			"Queue"="Transparent"
			"IgnoreProjector"="True"
			"RenderType"="Transparent"
			"PreviewType"="Plane"
			"CanUseSpriteAtlas"="True"
		}

		Stencil
		{
			Ref [_Stencil]
			Comp [_StencilComp]
			Pass [_StencilOp]
			ReadMask [_StencilReadMask]
			WriteMask [_StencilWriteMask]
		}

		Cull Off
		Lighting Off
		ZWrite Off
		ZTest [unity_GUIZTestMode]
		Fog { Mode Off }
		Blend One Zero
		ColorMask [_ColorMask]

		Pass
		{
			Name "Normal"

		CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma shader_feature _ _CANVAS_GROUP_COMPATIBLE
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 2.0

			#include "UnityCG.cginc"
			#include "UnityUI.cginc"
			#include "../CGIncludes/Spine-Common.cginc"

			#pragma multi_compile __ UNITY_UI_ALPHACLIP

			struct VertexInput {
				float4 vertex   : POSITION;
				float4 color    : COLOR;
				float2 texcoord : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct VertexOutput {
				float4 vertex   : SV_POSITION;
				fixed4 color    : COLOR;
				half2 texcoord  : TEXCOORD0;
				float4 worldPosition : TEXCOORD1;
				float4 screenPosition : TEXCOORD2;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			#ifndef ENABLE_GRAYSCALE
			fixed4 _Color;
			#endif
			fixed4 _TextureSampleAdd;
			float4 _ClipRect;

			#ifdef ENABLE_FILL
			float4 _FillColor;
			float _FillPhase;
			#endif
			#ifdef ENABLE_GRAYSCALE
			float _GrayPhase;
			#endif

			VertexOutput vert (VertexInput IN) {
				VertexOutput OUT;

				UNITY_SETUP_INSTANCE_ID(IN);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

				OUT.worldPosition = IN.vertex;
				OUT.vertex = UnityObjectToClipPos(OUT.worldPosition);
				OUT.screenPosition = ComputeScreenPos(OUT.vertex);
				OUT.texcoord = IN.texcoord;

				#ifdef UNITY_HALF_TEXEL_OFFSET
				OUT.vertex.xy += (_ScreenParams.zw-1.0) * float2(-1,1);
				#endif

			#ifdef _CANVAS_GROUP_COMPATIBLE
				half4 vertexColor = IN.color;
				// CanvasGroup alpha sets vertex color alpha, but does not premultiply it to rgb components.
				vertexColor.rgb *= vertexColor.a;
				// Unfortunately we cannot perform the TargetToGamma and PMAGammaToTarget transformations,
				// as these would be wrong with modified alpha.
			#else
				// Note: CanvasRenderer performs a GammaToTargetSpace conversion on vertex color already,
				// however incorrectly assuming straight alpha color.
				// Saturated version used to prevent numerical issues of certain low-alpha values.
				float4 vertexColor = PMAGammaToTargetSpaceSaturated(half4(TargetToGammaSpace(IN.color.rgb), IN.color.a));
			#endif
				OUT.color = vertexColor;
			#ifndef ENABLE_GRAYSCALE
				OUT.color *= float4(_Color.rgb * _Color.a, _Color.a); // Combine a PMA version of _Color with vertexColor.
			#endif

				return OUT;
			}

			sampler2D _MainTex;

			fixed4 frag (VertexOutput IN) : SV_Target
			{
				half4 texColor = tex2D(_MainTex, IN.texcoord);

				#if defined(_STRAIGHT_ALPHA_INPUT)
				texColor.rgb *= texColor.a;
				#endif

				half4 color = (texColor + _TextureSampleAdd) * IN.color;
				color *= UnityGet2DClipping(IN.worldPosition.xy, _ClipRect);

				#ifdef UNITY_UI_ALPHACLIP
				clip (color.a - 0.001);
				#endif

				#ifdef ENABLE_FILL
				color.rgb = lerp(color.rgb, (_FillColor.rgb * color.a), _FillPhase); // make sure to PMA _FillColor.
				#endif
				#ifdef ENABLE_GRAYSCALE
				color.rgb = lerp(color.rgb, dot(color.rgb, float3(0.3, 0.59, 0.11)), _GrayPhase);
				#endif

				float2 screenPosition = IN.screenPosition.xy / IN.screenPosition.w;
				screenPosition *= _ScreenParams.xy;

				float DITHER_THRESHOLDS[16] =
				{
					1.0 / 17.0,  9.0 / 17.0,  3.0 / 17.0, 11.0 / 17.0,
					13.0 / 17.0,  5.0 / 17.0, 15.0 / 17.0,  7.0 / 17.0,
					4.0 / 17.0, 12.0 / 17.0,  2.0 / 17.0, 10.0 / 17.0,
					16.0 / 17.0,  8.0 / 17.0, 14.0 / 17.0,  6.0 / 17.0
				};

				int index = (int(screenPosition.x) % 4) * 4 + int(screenPosition.y) % 4;
				clip(color.a - DITHER_THRESHOLDS[index]);

				return color;
			}
		ENDCG
		}
	}
	CustomEditor "SpineShaderWithOutlineGUI"
}
