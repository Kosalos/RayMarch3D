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
    
    float cameraX,cameraY,cameraZ;  // sliderView,deltaView cannot handle float3, so these are substitutes
    float focusX,focusY,focusZ;
    
    int size;
    int bailout;
    float power;
    float zoom;
    int iterMin;
    int iterMax;
    int iterWidth;
    float hop;
};

#endif /* ShaderTypes_h */


