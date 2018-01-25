#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

float3 toRectangular(float3 sph) {
    return float3(sph.x * sin(sph.z) * cos(sph.y),
                  sph.x * sin(sph.z) * sin(sph.y),
                  sph.x * cos(sph.z));
}

float3 toSpherical(float3 rec) {
    return float3(length(rec),
                  atan2(rec.y,rec.x),
                  atan2(sqrt(rec.x*rec.x+rec.y*rec.y), rec.z));
}

// ===========================================================================================

float DE(float3 position, Control control) {
    float3 z = position;
    float dr = 1.0;
    float r = 0.0;
    float theta,phi,zr,sineTheta;
    
    for(int i=0;i<64;++i) {
        if(i > control.iterMax) break;
        r = length(z);
        if(r > control.bailout) break;
        
        theta = control.power * atan2(sqrt(z.x*z.x+z.y*z.y),z.z);
        phi = control.power * atan2(z.y,z.x);
        sineTheta = sin(theta);
        zr = pow(r,control.power);
        z = float3(zr * sineTheta * cos(phi) + position.x,
                   zr * sin(phi) * sineTheta + position.y,
                   zr * cos(theta) + position.z);
        dr = ( pow(r, control.power - 1.0) * control.power * dr ) + 1.0;
    }
    
    return 0.5 * log(r)*r/dr;
}

// ===========================================================================================

float3 normalOf(float3 pos, Control control) {
    float eps = 0.01;   // float eps = abs(d_est_u/100.0);
    return normalize(float3(DE( pos + float3(eps,0,0), control) - DE(pos - float3(eps,0,0), control),
                            DE( pos + float3(0,eps,0), control) - DE(pos - float3(0,eps,0), control),
                            DE( pos + float3(0,0,eps), control) - DE(pos - float3(0,0,eps), control)  ));
}

float phong(float3 position, Control control) {
    float3 k = (position - control.light) + (control.camera - control.light);
    float3 h = k / length(k);
    return 0.0-dot(h,normalOf(position,control));
}

// ===========================================================================================

int iterCount(float3 w, Control control) {
    int iter = 0;
    float r, theta_power, r_power, phi, phi_cos;
    
    for(;;) {
        if(++iter == control.iterMax) return 0; // 'in' the set = invisible
        
        r = length(w);
        if(r > 4) return iter;  // point escaped after this many tries
        
        theta_power = atan2(w.y,w.x) * control.power;
        r_power = pow(r,control.power);
        
        phi = asin(w.z / r);
        phi_cos = cos(phi * control.power);
        w.x += r_power * cos(theta_power) * phi_cos;
        w.y += r_power * sin(theta_power) * phi_cos;
        w.z += r_power * sin(phi * control.power);
    }
    
    return 0;
}

// ===========================================================================================

float3 hsvIter(float len,int c, int min) {
    if(c < min) return float3(0,0,0);
    float r = log(len) / float(c * 6);
    return float3(r,r,r*2) * 40;
}

float3 march(float3 position, float3 direction, Control control) {
    int jog = 0,c,lowSide,highSide,maxIter = 0;
    
    // initial fast walk
    for(int steps=0;steps <  1000; ++steps) {
        position += direction;
        if(length(position) > 8) return float3();

        c = iterCount(position,control);
        if(c < maxIter) break;
        if(c >= maxIter) maxIter = c;
    }
    
    position -= direction;      // highest count position was just passed
    
    for(;;) {
        if(++jog > 10) break;
        
        direction /= 2;
        if(length(direction) < 0.0001) break;
    
        lowSide  = iterCount(position-direction,control);
        highSide = iterCount(position+direction,control);
    
        if(lowSide > highSide) {
            c = lowSide;
            position -= direction;
        }
        else {
            c = highSide;
            position += direction;
        }
    }
    
    return hsvIter(length(position),c,control.iterMin); //  /2 + phong(position,control) / 2;
}

// ===========================================================================================

float3 lerp(float3 a, float3 b, float w) { return a + w * (b-a); }

float3 hsv2rgb(float3 c) {
    c.x *= 0.5;
    return lerp(saturate((abs(fract(c.x + float3(1,2,3)/3) * 6 - 3) - 1)),  1,c.y) * c.z;
//harry    return lerp(saturate((abs(fract(c.x + float3(2,2.1,2.1)/3) * 6 - 3) - 1)), 2,c.y) * c.z / 2;
}

kernel void rayMarchShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 constant Control &control [[buffer(0)]],
 uint2 p [[thread_position_in_grid]])
{
    float2 uv = float2(float(p.x) / float(control.size), float(p.y) / float(control.size));     // map pixel to 0..1
    float3 viewVector = control.focus - control.camera;
    float3 topVector = toSpherical(viewVector);
    topVector.z += 1.5708;
    topVector = toRectangular(topVector);
    
    float3 sideVector = cross(viewVector,topVector);
    sideVector = normalize(sideVector) * length(topVector);

    float dx = control.zoom * (uv.x - 0.5);
    float dy = (-1.0) * control.zoom * (uv.y - 0.5);

    float3 direction = normalize((sideVector * dx) + (topVector * dy) + viewVector)  * 0.1; // * control.hop;
    float3 color = hsv2rgb( march(control.camera,direction, control));

    outTexture.write(float4(color,1),p);
}


