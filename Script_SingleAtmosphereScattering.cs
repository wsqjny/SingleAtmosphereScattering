using UnityEngine;
using System.Collections;
using UnityEngine.Rendering;
using System;
using System.Text;

[ExecuteInEditMode]
#if UNITY_5_4_OR_NEWER
[ImageEffectAllowedInSceneView]
#endif

public class Script_SingleAtmosphereScattering : MonoBehaviour
{
    protected Shader _ppShader;
    protected Material _ppMaterial;

    private CommandBuffer _cascadeShadowCommandBuffer;

    protected virtual void Start()
    {
        _InitPPShader();

        _ppMaterial = new Material(_ppShader);
        _ppMaterial.hideFlags = HideFlags.HideAndDontSave;
    }


    void OnRenderImage(RenderTexture sourceTexture, RenderTexture destTexture)
    {
        if (_ppShader != null)
        {
            _SetPPShaderParam();
            Graphics.Blit(sourceTexture, destTexture, _ppMaterial);
        }
        else
        {
            Graphics.Blit(sourceTexture, destTexture);
        }
    }

    protected virtual void _InitPPShader()
    {
        _ppShader = Shader.Find("CustomShader/Shader_SingleAtmosphereScattering");
    }

    protected virtual void _SetPPShaderParam()
    {
        _SetClipToWorldMatrixToMaterial();
    }

    void _SetClipToWorldMatrixToMaterial()
    {

        var projectionMatrix = GL.GetGPUProjectionMatrix(Camera.current.projectionMatrix, false);

        _ppMaterial.SetMatrix("_InverseViewMatrix", Camera.current.worldToCameraMatrix.inverse);
        _ppMaterial.SetMatrix("_InverseProjectionMatrix", projectionMatrix.inverse);
    }
}

