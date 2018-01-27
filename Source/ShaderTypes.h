#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

struct Control {
    vector_float3 camera;
    vector_float3 focus;
    vector_float3 light;
    vector_float3 hsv;

    int size;
    int formula;
    int bailout;
    float power;
    float zoom;
    int iterMin;
    int iterMax;
    int iterWidth;
    
    float fLimit;   // mandelBox
    float fValue;
    float mRadius;
    float fRadius;
    float scale;
    float cutoff;
    
    float cameraX,cameraY,cameraZ;
    float focusX,focusY,focusZ;
    float hsvX,hsvY,hsvZ;
};

#endif /* ShaderTypes_h */


