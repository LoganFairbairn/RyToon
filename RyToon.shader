// RyToon is an NPR (non-photo-realistic) shader that's designed to render anime and toon assets 'half way' between physicially based and a fully toon shader.
// The aim of the shader is to allow assets to look 'toon like', while still looking good, and not out of place in most lighting conditions.
// This makes the use of the shader ideal for VRChat as many worlds use PBR realistic lighting, while many characters are toon based.

// A big benefit of using this shader is there is an equivalent shader in Blender, where the mathematical algorithms for lighting and the input parameters are compatible.
// This allows users to view how their assets will look like in Blender without having to import them into Unity.
// Github for this shader: https://github.com/LoganFairbairn/RyToon

// Reference links for this shader:
// Fast Subsurface Scattering for Unity URP     -   https://johnaustin.io/articles/2020/fast-subsurface-scattering-for-the-unity-urp
// Genshin Impact Shader in UE5                 -   https://www.artstation.com/artwork/g0gGOm
// Ben Ayers Blender NPR Genshin Impact Shader  -   https://www.artstation.com/blogs/bjayers/9oOD/blender-npr-recreating-the-genshin-impact-shader

Shader "MatLayer/RyToon" {
    Properties {
        _Color ("Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _ColorTexture ("Color Texture", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _ORMTexture ("ORM Texture", 2D) = "black" {}
        _SubsurfaceTexture ("Subsurface Texture", 2D) = "black" {}
        _EmissionTexture ("Emission Texture", 2D) = "black" {}
        _Roughness ("Roughness", Range(0.0, 1.0)) = 0.5
        _Metallic ("Metallic", Range(0.0, 1.0)) = 0
        _Subsurface ("Subsurface", Range(0.0, 1.0)) = 0
        _SubsurfaceColor ("Subsurface Tint", Color) = (1.0, 1.0, 1.0, 1.0)
        _WrapValue ("Wrap Value", Range(0.0, 1.0)) = 0.5
        _SheenIntensity ("Sheen Intensity", Range(0.0, 1.0)) = 0.0
        _SheenColor ("Sheen Color", Color) = (1.0, 1.0, 1.0, 1.0)
    }
    SubShader {
        Tags { "RenderType" = "Opaque" }
        CGPROGRAM

        // Support all light shadow types with 'fullforwardshadows' https://docs.unity3d.com/Manual/SL-SurfaceShaders.html
        #pragma surface surf RyToon fullforwardshadows

        // Custom Properties
        sampler2D _ColorTexture;
        sampler2D _ORMTexture;
        sampler2D _NormalMap;
        sampler2D _SubsurfaceTexture;
        sampler2D _EmissionTexture;
        fixed4 _Color;
        half _Roughness;
        float _Metallic;
        float _Subsurface;
        fixed4 _SubsurfaceColor;
        float _WrapValue;
        fixed4 _SheenColor;
        float _SheenIntensity;

        float BeckmannNormalDistribution(float roughness, float NdotH)
        {
            float roughnessSqr = roughness * roughness;
            float NdotHSqr = NdotH * NdotH;
            return max(0.000001,(1.0 / (3.1415926535 * roughnessSqr * NdotHSqr * NdotHSqr)) * exp((NdotHSqr-1)/(roughnessSqr*NdotHSqr)));
        }

        // Custom surface output defines the input and output required for shader calculations.
        struct CustomSurfaceOutput {
            half3 Albedo;
            half3 Normal;
            half3 Emission;
            half3 Subsurface;
            half Alpha;
        };

        // Calculate custom lighting here.
        half4 LightingRyToon (CustomSurfaceOutput s, half3 lightDir, half viewDir, half atten) {
            // Half Lambert lighting is a technique created by Valve for Half-Life designed to prevent the rear of the object from losing it's shape.
            // This technique provides a good middle ground between a totally toon lighting approach and a physically accurate approach.
            // Calculate base lighting using the half-lambert lighting model.
            half4 c;
            half NdotL = max(0, dot(s.Normal, lightDir));
            half HalfLambert = pow(NdotL * 0.5 + 0.5, 2);

            // The toon shader used in Genshin Impact uses an artifical subsurface scattering effect which allows...
            // simulating light scattering through organic objects such as skin, wax and clothes.
            // If a subsurface (a.k.a thickness) texture is provided, we'll use it to determine where subsurface should be applied to the object.
            half3 subsurface;
            half diffuseWrap = 1 - pow(NdotL * _WrapValue + (1 - _WrapValue), 2);
            subsurface = diffuseWrap * _Subsurface * _SubsurfaceColor;

            // Calculate specular reflections using the Beckmann normal distribution method.
            float3 halfDirection = normalize(viewDir + lightDir);
            float NdotH = max(0.0, dot(s.Normal, halfDirection));
            float spec = BeckmannNormalDistribution(_Roughness, NdotH);

            // Calculate a sheen approximation, which is useful for simulating microfiber lighting for fabric and cloth.
            half sheen = pow(1 - dot(s.Normal, halfDirection), 5) * _SheenIntensity * _SheenColor;

            // Calculate accumulative lighting contributions.
            //c.rgb = (s.Albedo * _LightColor0.rgb * HalfLambert + _LightColor0.rgb * spec + sheen) * atten + subsurface.rgb;
            c.rgb = s.Albedo * _LightColor0.rgb * HalfLambert;
            c.a = s.Alpha;
            return c;
        }

        // Input Structure
        struct Input {
            float2 uv_ColorTexture;
            float2 uv_NormalMap;
            float2 uv_EmissionTexture;
            float2 uv_SubsurfaceTexture;
        };

        // Main shader calculations.
        void surf (Input IN, inout CustomSurfaceOutput o) {

            // Calculate artifical metalness as a spherical gradient matcap.
            half3 viewSpaceNormals = mul((float3x3)UNITY_MATRIX_V, o.Normal);
            viewSpaceNormals.xyz *= float3(0.5, 0.5, 1.0);
            float metallic = saturate(1 - (length(viewSpaceNormals)));
            metallic = smoothstep(0.3, 0.0, metallic);

            // Apply textures and channel packing.
            half3 baseColor = (tex2D (_ColorTexture, IN.uv_ColorTexture).rgb) * _Color;
            o.Albedo = saturate(lerp(baseColor, baseColor * metallic, _Metallic));
            //o.Normal = UnpackNormal (tex2D (_NormalMap, IN.uv_NormalMap));
            o.Emission = (tex2D (_EmissionTexture, IN.uv_EmissionTexture).rgb);
            //o.Subsurface = (tex2D (_SubsurfaceTexture, IN.uv_SubsurfaceTexture).rgb);
        }
        ENDCG
    } 
    Fallback "Diffuse"
}