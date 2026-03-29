#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 iResolution;
uniform float iTime;

out vec4 fragColor;

float zoom = 1.0;

vec2 csqr(vec2 a) { return vec2(a.x*a.x - a.y*a.y, 2.0*a.x*a.y); }

mat2 rot(float a) {
    float c = cos(a);
    float s = sin(a);
    return mat2(c, s, -s, c);
}

vec2 iSphere(in vec3 ro, in vec3 rd, in vec4 sph) {
    vec3 oc = ro - sph.xyz;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - sph.w*sph.w;
    float h = b*b - c;
    if(h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b-h, -b+h);
}

float map(in vec3 p) {
    float res = 0.0;
    vec3 c = p;
    float cosTime = cos(iTime*0.15);
    float cosTime2 = cos(iTime*0.15 + 1.6);

    for(int i = 0; i < 6; ++i) {
        p = 0.7*abs(p + cosTime2*0.15)/dot(p,p) - 0.7 + cosTime*0.15;
        p.yz = csqr(p.yz);
        p = p.zxy;
        res += exp(-19.0 * abs(dot(p,c)));
    }
    return res/2.0;
}

vec3 raymarch(in vec3 ro, vec3 rd, vec2 tminmax) {
    float t = tminmax.x;
    float dt = 0.1 - 0.075*cos(iTime*0.025);
    vec3 col = vec3(0.0);
    float c = 0.0;

    for(int i = 0; i < 32; i++) {
        t += dt*exp(-2.0*c);
        if(t > tminmax.y) break;
        c = map(ro + t*rd);

        // Purple/Pink marble colors - darker and more saturated
        vec3 deepPurple = vec3(0.45, 0.2, 0.65);   // Deep purple
        vec3 purple = vec3(0.55, 0.25, 0.75);      // Medium purple
        vec3 lavender = vec3(0.6, 0.35, 0.7);      // Lavender purple

        // Mix colors based on density - clamped to prevent over-brightening
        float densityFactor = clamp(c, 0.0, 0.8); // Clamp to prevent white areas
        vec3 marbleColor = mix(deepPurple, purple, densityFactor);
        marbleColor = mix(marbleColor, lavender, densityFactor * 0.5);

        col = 0.99*col + 0.14*marbleColor*vec3(c*c, c*c, c); // Controlled accumulation
    }

    // Add purple base color to fill dark areas
    col += vec3(0.35, 0.2, 0.45) * 0.2;

    return col;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 q = fragCoord / iResolution;
    vec2 p = -1.0 + 2.0 * q;
    p.x *= iResolution.x/iResolution.y;

    vec3 ro = zoom*vec3(4.0);
    ro.xz *= rot(0.25*iTime);

    vec3 ta = vec3(0.0);
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = cross(uu, ww);
    vec3 rd = normalize(p.x*uu + p.y*vv + 4.0*ww)*0.975;

    vec2 tmm = iSphere(ro, rd, vec4(0.0, 0.0, 0.0, 2.0));

    vec3 col = vec3(0.0);
    float alpha = 0.0;

    if(tmm.x >= 0.0) {
        col = raymarch(ro, rd, tmm);

        // Calculate distance from center for inner glow
        vec3 hitPos = ro + tmm.x*rd;
        float distFromCenter = length(hitPos);
        float sphereRadius = 2.0;

        // Inner glow calculation - stronger at edges
        float edgeFactor = distFromCenter / sphereRadius;
        float innerGlow = pow(edgeFactor, 3.0) * 0.6; // Adjust power and intensity

        // Purple glow color
        vec3 glowColor = vec3(0.7, 0.4, 0.9);
        col += glowColor * innerGlow;

        // Fresnel reflection
        vec3 nor = reflect(rd, (ro + tmm.x*rd)*0.5);
        float fre = pow(0.5 + clamp(dot(nor, rd), 0.0, 1.0), 3.0)*1.3;

        // Subtle purple reflection highlights
        col += vec3(0.2, 0.12, 0.25) * fre;

        alpha = 1.0;
    }

    // Moderate brightness adjustment - prevents over-saturation
    col = 0.75*log(1.0 + col * 1.3);
    col = clamp(col, 0.0, 0.95); // Cap at 0.95 to prevent pure white

    fragColor = vec4(col, alpha);
}