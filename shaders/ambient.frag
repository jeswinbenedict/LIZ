// The ambient light behind every page (lib/shared/widgets/ambient.dart).
//
// A ring of red light computed per pixel, as light rather than paint: its
// brightness is a sum of profiles across the ring (a hairline core, a tube,
// a glow, a bloom that falls off faster inward than outward), scaled by how
// lit each part of the ring is (two bright arcs, faint between), and the
// brightest light turns from red toward white, as a bright red source does.
// A whisper falls inward from the bright arcs, and a vignette darkens the
// corners. Tuned in tool/brand (see the doc comment in ambient.dart).
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uCentre;
uniform float uRadius;
uniform float uDpr;
uniform vec3 uBase;
uniform vec3 uRed;
uniform vec3 uHot;
uniform float uLevel;
uniform float uTime;
uniform vec2 uPointer;
uniform float uPointerOn;

out vec4 fragColor;

const float PI = 3.14159265;

float peak(float th, float at, float width) {
  float a = th - at;
  a = atan(sin(a), cos(a));
  return exp(-(a / width) * (a / width));
}

float g(float x, float w) {
  return exp(-(x / w) * (x / w));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 dv = p - uCentre;
  float r = length(dv);
  float th = atan(dv.y, dv.x);
  float R = uRadius;
  float d = r - R;

  // Motion (uTime, seconds; 0 = still): the bright arcs drift slowly
  // around the ring and sway, a comet of light travels along it, and the
  // bloom breathes. The pointer lights the part of the ring nearest it.
  float t = uTime;
  float drift = t * 0.045 + 0.12 * sin(t * 0.21);
  float lit = 0.22
      + 0.95 * peak(th, radians(140.0) + drift, 0.55 + 0.06 * sin(t * 0.37))
      + 0.75 * peak(th, radians(-35.0) + drift * 1.3, 0.45 + 0.05 * sin(t * 0.29 + 1.0))
      + 0.18 * peak(th, radians(60.0) - drift, 0.8);
  if (t > 0.0) {
    lit += 0.85 * peak(th, t * 0.32, 0.22) + 0.4 * peak(th, -t * 0.19 + 2.0, 0.3);
  }
  vec2 pv = uPointer - uCentre;
  float pr = length(pv);
  float near = uPointerOn * exp(-pow((pr - R) / (0.45 * R), 2.0));
  lit += 0.9 * near * peak(th, atan(pv.y, pv.x), 0.35);

  float core = g(d, 1.6 * uDpr) * 1.3;
  float tube = g(d, 0.006 * R) * 0.75;
  float glow = g(d, 0.03 * R) * 0.5;
  float breathe = 1.0 + 0.18 * sin(t * 0.55);
  float bloom = breathe * exp(-pow(max(d, 0.0) / (0.11 * R), 2.0) - pow(min(d, 0.0) / (0.07 * R), 2.0)) * 0.3;
  float inner = g(r - 0.955 * R, 0.9 * uDpr) * 0.22 * peak(th, radians(150.0), 0.4);
  float beam = (r < R ? g(R - r, 0.35 * R) : 0.0) * 0.09
      * (peak(th, radians(140.0), 0.35) + 0.7 * peak(th, radians(-35.0), 0.3));

  // uLevel: 1 on open pages, lower behind dense content. The white-hot
  // part fades fastest (it is scaled twice), so a quiet ring stays red,
  // never a bright line behind text.
  // The level scales the light after it is mapped to colour: scaled before,
  // a core bright enough to saturate would stay saturated at any level.
  float L = (core + tube + glow + bloom) * lit + inner + beam;
  vec3 light = uRed * clamp(L, 0.0, 1.0)
      + (uHot - uRed) * clamp(L - 0.55, 0.0, 1.0) * 1.1 * uLevel;
  vec3 c = uBase + light * uLevel;
  // A soft pool of light under the pointer, faint so text stays legible.
  float pool = uPointerOn * g(length(p - uPointer), 0.22 * R);
  c += uRed * pool * 0.07 * (0.5 + 0.5 * uLevel);

  vec2 q = vec2((p.x - uSize.x * 0.5) / (uSize.x * 0.75), (p.y - uSize.y * 0.45) / (uSize.y * 0.75));
  float v = clamp((length(q) - 0.55) / 0.6, 0.0, 1.0);
  c *= 1.0 - 0.55 * pow(v, 1.5);

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
