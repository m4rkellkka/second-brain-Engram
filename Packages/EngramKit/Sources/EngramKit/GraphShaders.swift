/// Metal shaders for the Brain graph, compiled at launch with
/// `makeLibrary(source:)` so building Engram needs no separate Metal
/// toolchain download.
///
/// Everything is drawn with additive blending and no depth test: overlapping
/// glows add up, so dense clusters shine like small nebulae. Depth fades
/// far dots and lines (fog), which is what makes the picture read as 3D.
public enum GraphShaders {
  public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
      float4x4 viewProjection;
      float4 viewport;   // width, height (pixels), time, max dot radius (pixels)
      float4 fog;        // near, far, min factor, unused
    };

    struct Sprite {
      float4 position;   // xyz, world radius
      float4 color;      // rgb, intensity
    };

    struct Line {
      float4 a;          // xyz, width in pixels
      float4 b;          // xyz, 1 = dashed
      float4 color;      // rgb, intensity
    };

    struct SpriteOut {
      float4 position [[position]];
      float2 uv;
      float4 color;
    };

    struct LineOut {
      float4 position [[position]];
      float along;
      float dashed;
      float4 color;
    };

    constant float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

    float fogFactor(float w, float4 fog) {
      return clamp(1.0 - (w - fog.x) / max(fog.y - fog.x, 0.001), fog.z, 1.0);
    }

    // The quad is 3x the dot so the halo fits around it.
    constant float glowScale = 3.0;

    vertex SpriteOut spriteVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                  constant Sprite *sprites [[buffer(0)]],
                                  constant Uniforms &u [[buffer(1)]]) {
      Sprite s = sprites[iid];
      float4 clip = u.viewProjection * float4(s.position.xyz, 1.0);
      float2 corner = corners[vid];
      // A world-space radius becomes a clip offset through the projection's
      // scale terms; keep at least ~1.2 px so far dots never vanish.
      float2 scale = float2(u.viewProjection[0][0], u.viewProjection[1][1]);
      float radius = s.position.w;
      float pixels = radius * scale.y / max(clip.w, 0.001) * u.viewport.y * 0.5;
      if (pixels < 1.2) { radius *= 1.2 / max(pixels, 0.0001); }
      // Close up, dots stay dots instead of growing into bubbles.
      if (pixels > u.viewport.w) { radius *= u.viewport.w / pixels; }
      clip.xy += corner * radius * glowScale * float2(scale.x, scale.y);
      SpriteOut out;
      out.position = clip;
      out.uv = corner;
      out.color = float4(s.color.rgb, s.color.a * fogFactor(clip.w, u.fog));
      return out;
    }

    fragment float4 spriteFragment(SpriteOut in [[stage_in]]) {
      float d = length(in.uv) * glowScale;           // 1.0 = edge of the dot
      float core = 1.0 - smoothstep(0.75, 1.0, d);
      float glow = exp(-d * d * 0.55) * 0.45;
      float a = (core + glow) * in.color.a;
      float3 rgb = mix(in.color.rgb, float3(1.0), core * 0.2);  // a slightly hot centre
      return float4(rgb * a, a);
    }

    vertex LineOut lineVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              constant Line *lines [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
      Line l = lines[iid];
      float4 ca = u.viewProjection * float4(l.a.xyz, 1.0);
      float4 cb = u.viewProjection * float4(l.b.xyz, 1.0);
      LineOut out;
      if (ca.w <= 0.05 || cb.w <= 0.05) {
        out.position = float4(0, 0, 0, 1);
        out.along = 0; out.dashed = 0; out.color = float4(0);
        return out;
      }
      float2 halfSize = u.viewport.xy * 0.5;
      float2 sa = ca.xy / ca.w * halfSize;
      float2 sb = cb.xy / cb.w * halfSize;
      float2 dir = sb - sa;
      float len = max(length(dir), 0.0001);
      dir /= len;
      float2 normal = float2(-dir.y, dir.x);
      bool atB = (vid & 1) == 1;
      float side = vid < 2 ? -1.0 : 1.0;
      float4 clip = atB ? cb : ca;
      float2 offset = normal * side * l.a.w * 0.5 / halfSize;
      clip.xy += offset * clip.w;
      out.position = clip;
      out.along = atB ? len : 0.0;
      out.dashed = l.b.w;
      float fog = fogFactor((ca.w + cb.w) * 0.5, u.fog);
      out.color = float4(l.color.rgb, l.color.a * fog);
      return out;
    }

    fragment float4 lineFragment(LineOut in [[stage_in]]) {
      if (in.dashed > 0.5 && fract(in.along / 9.0) > 0.55) { discard_fragment(); }
      float a = in.color.a;
      return float4(in.color.rgb * a, a);
    }
    """
}
