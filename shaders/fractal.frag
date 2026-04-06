#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2  iResolution;
uniform float iTime;
uniform float iAmplitude; // 0.0 idle → 1.0 loud

// Configuration uniforms
uniform float uBaseRadius;
uniform float uRadiusGrowth;
uniform float uFractalIntensity;
uniform float uColorBoost;
uniform float uGlowStrength;
uniform float uZoomAmount;

out vec4 fragColor;

// ── Helpers ──────────────────────────────────────────────────────────────────

vec2 csqr(vec2 a) {
  return vec2(a.x * a.x - a.y * a.y, 2.0 * a.x * a.y);
}

mat2 rot(float a) {
  float c = cos(a), s = sin(a);
  return mat2(c, s, -s, c);
}

vec2 iSphere(vec3 ro, vec3 rd, vec4 sph) {
  vec3  oc = ro - sph.xyz;
  float b  = dot(oc, rd);
  float c  = dot(oc, oc) - sph.w * sph.w;
  float h  = b * b - c;
  if (h < 0.0) return vec2(-1.0);
  h = sqrt(h);
  return vec2(-b - h, -b + h);
}

// ── Fractal field ─────────────────────────────────────────────────────────────

float map(vec3 p) {
  vec3  c       = p;
  float res     = 0.0;
  float ct1     = cos(iTime * 0.15);
  float ct2     = cos(iTime * 0.15 + 1.6);

  float fold    = 0.7 + iAmplitude * uFractalIntensity;
  float offset  = 0.7 - iAmplitude * (uFractalIntensity * 0.8);

  for (int i = 0; i < 6; ++i) {
    p   = fold * abs(p + ct2 * 0.15) / dot(p, p) - offset + ct1 * 0.15;
    p.yz = csqr(p.yz);
    p   = p.zxy;
    res += exp(-19.0 * abs(dot(p, c)));
  }
  return res / 2.0;
}

// ── Volumetric ray march ──────────────────────────────────────────────────────

vec3 raymarch(vec3 ro, vec3 rd, vec2 tminmax) {
  float t   = tminmax.x;
  float dt  = mix(0.09, 0.045, iAmplitude) - 0.06 * cos(iTime * 0.025);
  vec3  col = vec3(0.0);
  float c   = 0.0;

  // #B454FF → vec3(0.706, 0.329, 1.000)
  // #EBD2FF → vec3(0.922, 0.824, 1.000)

  for (int i = 0; i < 36; i++) {
    t += dt * exp(-2.0 * c);
    if (t > tminmax.y) break;

    c = map(ro + t * rd);

    // deep: dark shade of #B454FF
    vec3 deep = mix(vec3(0.18, 0.06, 0.30), vec3(0.35, 0.13, 0.55), iAmplitude * uColorBoost);
    // mid: pure #B454FF range
    vec3 mid  = mix(vec3(0.55, 0.22, 0.82), vec3(0.71, 0.33, 1.00), iAmplitude * uColorBoost);
    // lav: light #EBD2FF range
    vec3 lav  = mix(vec3(0.78, 0.62, 0.95), vec3(0.92, 0.82, 1.00), iAmplitude * uColorBoost);

    float d = clamp(c, 0.0, 0.8);
    vec3  mc = mix(deep, mid, d);
    mc = mix(mc, lav, d * 0.5);

    col = 0.99 * col + 0.13 * mc * vec3(c * c, c * c, c);
  }

  // Ambient: very dark #B454FF shadow
  col += vec3(0.14, 0.05, 0.25) * 0.22;
  return col;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / iResolution;
  vec2 p  = -1.0 + 2.0 * uv;
  p.x *= iResolution.x / iResolution.y;

  float zoom = 1.0 - iAmplitude * uZoomAmount;
  vec3  ro   = zoom * vec3(4.0);
  ro.xz *= rot(0.25 * iTime);

  vec3 ta = vec3(0.0);
  vec3 ww = normalize(ta - ro);
  vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
  vec3 vv = cross(uu, ww);
  vec3 rd = normalize(p.x * uu + p.y * vv + 4.0 * ww) * 0.975;

  float radius = uBaseRadius + iAmplitude * uRadiusGrowth;
  vec2  tmm    = iSphere(ro, rd, vec4(0.0, 0.0, 0.0, radius));

  vec3  col   = vec3(0.0);
  float alpha = 0.0;

  if (tmm.x >= 0.0) {
    col = raymarch(ro, rd, tmm);

    // Edge glow: #B454FF → #EBD2FF on amplitude
    vec3  hit      = ro + tmm.x * rd;
    float edge     = length(hit) / radius;
    float glow     = pow(edge, 3.0) * mix(0.55, uGlowStrength, iAmplitude);
    vec3  glowCol  = mix(vec3(0.71, 0.33, 1.00), vec3(0.92, 0.82, 1.00), iAmplitude);
    col += glowCol * glow;

    alpha = 1.0;
  }

  col   = 0.75 * log(1.0 + col * mix(1.3, 2.0, iAmplitude));
  col   = clamp(col, 0.0, 0.95);

  fragColor = vec4(col, alpha);
}