// Copyright 2012 Google Inc. All Rights Reserved.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/** Class for internal use by Distance.dart. */

part of box2d;

class Simplex {
  final SimplexVertex v1;
  final SimplexVertex v2;
  final SimplexVertex v3;
  final List<SimplexVertex> vertices;
  int count;

  Simplex() :
    count = 0,
    v1 = new SimplexVertex(),
    v2 = new SimplexVertex(),
    v3 = new SimplexVertex(),
    vertices = new List<SimplexVertex>(3),
    e13 = new vec2.zero(),
    e12 = new vec2.zero(),
    e23 = new vec2.zero(),
    case2 = new vec2.zero(),
    case22 = new vec2.zero(),
    case3 = new vec2.zero(),
    case33 = new vec2.zero() {

    vertices[0] = v1;
    vertices[1] = v2;
    vertices[2] = v3;
  }

  /** Pooling. */
  final vec2 e13;
  final vec2 e23;
  final vec2 e12;
  final vec2 case2;
  final vec2 case22;
  final vec2 case3;
  final vec2 case33;

  void readCache(SimplexCache cache, DistanceProxy proxyA,
      Transform transformA, DistanceProxy proxyB,
      Transform transformB) {
    assert (cache.count <= 3);

    // Copy data from cache.
    count = cache.count;

    for (int i = 0; i < count; ++i) {
      SimplexVertex v = vertices[i];
      v.indexA = cache.indexA[i];
      v.indexB = cache.indexB[i];
      vec2 wALocal = proxyA.vertices[v.indexA];
      vec2 wBLocal = proxyB.vertices[v.indexB];
      Transform.mulToOut(transformA, wALocal, v.wA);
      Transform.mulToOut(transformB, wBLocal, v.wB);
      v.w.copyFrom(v.wB).sub(v.wA);
      v.a = 0.0;
    }

    // Compute the new simplex metric, if it is substantially different than
    // old metric then flush the simplex.
    if (count > 1) {
      num metric1 = cache.metric;
      num metric2 = getMetric();
      if (metric2 < 0.5 * metric1 || 2.0 * metric1 < metric2 || metric2 <
          Settings.EPSILON) {
        // Reset the simplex.
        count = 0;
      }
    }

    // If the cache is empty or invalid ...
    if (count == 0) {
      SimplexVertex v = vertices[0];
      v.indexA = 0;
      v.indexB = 0;
      vec2 wALocal = proxyA.vertices[0];
      vec2 wBLocal = proxyB.vertices[0];
      Transform.mulToOut(transformA, wALocal, v.wA);
      Transform.mulToOut(transformB, wBLocal, v.wB);
      v.w.copyFrom(v.wB).sub(v.wA);
      count = 1;
    }
  }

  void writeCache(SimplexCache cache) {
    cache.metric = getMetric();
    cache.count = count;

    for (int i = 0; i < count; ++i) {
      cache.indexA[i] = (vertices[i].indexA);
      cache.indexB[i] = (vertices[i].indexB);
    }
  }

  void getSearchDirection(vec2 out) {
    switch (count) {
      case 1 :
        out.copyFrom(v1.w).negate();
        return;
      case 2 :
        e12.copyFrom(v2.w).sub(v1.w);
        // use out for a temp variable real quick
        out.copyFrom(v1.w).negate();
        num sgn = cross(e12, out);

        if (sgn > 0) {
          // Origin is left of e12.
          out = cross(1, e12);
        }
        else {
          // Origin is right of e12.
          out = cross(e12, 1);
        }
        break;
      default :
        assert (false);
        out.splat(0.0);
        return;
    }
  }


  /**
   * this returns pooled objects. don't keep or modify them
   */
  void getClosestPoint(vec2 out) {
    switch (count) {
      case 0 :
        assert (false);
        out.splat(0.0);
        return;
      case 1 :
        out.copyFrom(v1.w);
        return;
      case 2 :
        case22.copyFrom(v2.w).scale(v2.a);
        case2.copyFrom(v1.w).scale(v1.a).add(case22);
        out.copyFrom(case2);
        return;
      case 3 :
        out.splat(0.0);
        return;
      default :
        assert (false);
        out.splat(0.0);
        return;
    }
  }


  void getWitnessPoints(vec2 pA, vec2 pB) {
    switch (count) {
      case 0 :
        assert (false);
        break;

      case 1 :
        pA.copyFrom(v1.wA);
        pB.copyFrom(v1.wB);
        break;

      case 2 :
        case2.copyFrom(v1.wA).scale(v1.a);
        pA.copyFrom(v2.wA).scale(v2.a).add(case2);
        case2.copyFrom(v1.wB).scale(v1.a);
        pB.copyFrom(v2.wB).scale(v2.a).add(case2);

        break;

      case 3 :
        pA.copyFrom(v1.wA).scale(v1.a);
        case3.copyFrom(v2.wA).scale(v2.a);
        case33.copyFrom(v3.wA).scale(v3.a);
        pA.add(case3).add(case33);
        pB.copyFrom(pA);
        break;

      default :
        assert (false);
        break;
    }
  }

  num getMetric() {
    switch (count) {
      case 0 :
        assert (false);
        return 0.0;

      case 1 :
        return 0.0;

      case 2 :
        return distance(v1.w, v2.w);

      case 3 :
        case3.copyFrom(v2.w).sub(v1.w);
        case33.copyFrom(v3.w).sub(v1.w);
        return cross(case3, case33);

      default :
        assert (false);
        return 0.0;
    }
  }

  /**
   * Solve a line segment using barycentric coordinates.
   */
  void solve2() {
    vec2 w1 = v1.w;
    vec2 w2 = v2.w;
    e12.copyFrom(w2).sub(w1);

    // w1 region
    num d12_2 = -dot(w1, e12);
    if (d12_2 <= 0.0) {
      // a2 <= 0, so we clamp it to 0
      v1.a = 1.0;
      count = 1;
      return;
    }

    // w2 region
    num d12_1 = dot(w2, e12);
    if (d12_1 <= 0.0) {
      // a1 <= 0, so we clamp it to 0
      v2.a = 1.0;
      count = 1;
      v1.setFrom(v2);
      return;
    }

    // Must be in e12 region.
    num inv_d12 = 1.0 / (d12_1 + d12_2);
    v1.a = d12_1 * inv_d12;
    v2.a = d12_2 * inv_d12;
    count = 2;
  }

  /**
   * Solve a line segment using barycentric coordinates.<br/>
   * Possible regions:<br/>
   * - points[2]<br/>
   * - edge points[0]-points[2]<br/>
   * - edge points[1]-points[2]<br/>
   * - inside the triangle
   */
  void solve3() {
    vec2 w1 = v1.w;
    vec2 w2 = v2.w;
    vec2 w3 = v3.w;

    // Edge12
    e12.copyFrom(w2).sub(w1);
    num w1e12 = dot(w1, e12);
    num w2e12 = dot(w2, e12);
    num d12_1 = w2e12;
    num d12_2 = -w1e12;

    // Edge13
    e13.copyFrom(w3).sub(w1);
    num w1e13 = dot(w1, e13);
    num w3e13 = dot(w3, e13);
    num d13_1 = w3e13;
    num d13_2 = -w1e13;

    // Edge23
    e23.copyFrom(w3).sub(w2);
    num w2e23 = dot(w2, e23);
    num w3e23 = dot(w3, e23);
    num d23_1 = w3e23;
    num d23_2 = -w2e23;

    // Triangle123
    num n123 = cross(e12, e13);

    num d123_1 = n123 * cross(w2, w3);
    num d123_2 = n123 * cross(w3, w1);
    num d123_3 = n123 * cross(w1, w2);

    // w1 region
    if (d12_2 <= 0.0 && d13_2 <= 0.0) {
      v1.a = 1.0;
      count = 1;
      return;
    }

    // e12
    if (d12_1 > 0.0 && d12_2 > 0.0 && d123_3 <= 0.0) {
      num inv_d12 = 1.0 / (d12_1 + d12_2);
      v1.a = d12_1 * inv_d12;
      v2.a = d12_2 * inv_d12;
      count = 2;
      return;
    }

    // e13
    if (d13_1 > 0.0 && d13_2 > 0.0 && d123_2 <= 0.0) {
      num inv_d13 = 1.0 / (d13_1 + d13_2);
      v1.a = d13_1 * inv_d13;
      v3.a = d13_2 * inv_d13;
      count = 2;
      v2.setFrom(v3);
      return;
    }

    // w2 region
    if (d12_1 <= 0.0 && d23_2 <= 0.0) {
      v2.a = 1.0;
      count = 1;
      v1.setFrom(v2);
      return;
    }

    // w3 region
    if (d13_1 <= 0.0 && d23_1 <= 0.0) {
      v3.a = 1.0;
      count = 1;
      v1.setFrom(v3);
      return;
    }

    // e23
    if (d23_1 > 0.0 && d23_2 > 0.0 && d123_1 <= 0.0) {
      num inv_d23 = 1.0 / (d23_1 + d23_2);
      v2.a = d23_1 * inv_d23;
      v3.a = d23_2 * inv_d23;
      count = 2;
      v1.setFrom(v3);
      return;
    }

    // Must be in triangle123
    num inv_d123 = 1.0 / (d123_1 + d123_2 + d123_3);
    v1.a = d123_1 * inv_d123;
    v2.a = d123_2 * inv_d123;
    v3.a = d123_3 * inv_d123;
    count = 3;
  }
}
