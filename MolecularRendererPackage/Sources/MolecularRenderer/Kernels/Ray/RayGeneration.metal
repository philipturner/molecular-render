//
//  RayGeneration.metal
//  MolecularRenderer
//
//  Created by Philip Turner on 4/22/23.
//

#ifndef RAY_GENERATION_H
#define RAY_GENERATION_H

#include <metal_stdlib>
#include "../Ray/Ray.metal"
#include "../Ray/Sampling.metal"
#include "../Utilities/Constants.metal"
using namespace metal;

// Partially sourced from:
// https://github.com/nvpro-samples/gl_vk_raytrace_interop/blob/master/shaders/raygen.rgen
// https://github.com/microsoft/DirectX-Graphics-Samples/tree/master/Samples/Desktop/D3D12Raytracing/src/D3D12RaytracingRealTimeDenoisedAmbientOcclusion/RTAO

class RayGeneration {
public:
  struct Basis {
    // Basis for the coordinate system around the normal vector.
    half3x3 axes;

    // Uniformly distributed random numbers for determining angles.
    float random1;
    float random2;
  };
  
  static ushort2 makePixelID(ushort2 tgid, ushort2 lid) {
    ushort local_linear_id = lid.y * 8 + lid.x;
    ushort new_y = (local_linear_id >= 32) ? 4 : 0;
    ushort new_x = (local_linear_id % 32 >= 16) ? 4 : 0;
    new_y += (local_linear_id % 16 >= 8) ? 2 : 0;
    new_x += (local_linear_id % 8 >= 4) ? 2 : 0;
    new_y += (local_linear_id % 4 >= 2) ? 1 : 0;
    new_x += local_linear_id % 2 >= 1;
    
    return tgid * ushort2(8, 8) + ushort2(new_x, new_y);
  }
  
  static float3x3 makeBasis(const float3 normal) {
    // ZAP's default coordinate system for compatibility.
    float3 z = normal;
    const float yz = -z.y * z.z;
    float3 y = normalize
    (
     (abs(z.z) > 0.99999f)
     ? float3(-z.x * z.y, 1.0f - z.y * z.y, yz)
     : float3(-z.x * z.z, yz, 1.0f - z.z * z.z));
    
    float3 x = cross(y, z);
    return float3x3(x, y, z);
  }
  
  static Ray<float> primaryRay(constant CameraArguments *cameraArgs,
                               float2 jitter,
                               ushort2 pixelCoords) {
    // Apply the pixel position.
    float3 rayDirection(float2(pixelCoords) + 0.5, -1);
    rayDirection.xy += jitter;
    rayDirection.xy -= float2(SCREEN_WIDTH, SCREEN_HEIGHT) / 2;
    rayDirection.y = -rayDirection.y;
    
    // Apply the camera FOV.
    float fovMultiplier = cameraArgs->positionAndFOVMultiplier[3];
    rayDirection.xy *= fovMultiplier;
    rayDirection = normalize(rayDirection);
    
    // Apply the camera direction.
    float3x3 rotation(cameraArgs->rotationColumn1,
                      cameraArgs->rotationColumn2,
                      cameraArgs->rotationColumn3);
    rayDirection = rotation * rayDirection;
    
    // Apply the camera position.
    float3 worldOrigin = cameraArgs->positionAndFOVMultiplier.xyz;
    return { worldOrigin, rayDirection };
  }
  
  static Ray<half> secondaryRay(float3 origin, Basis basis) {
    // Transform the uniform distribution into the cosine distribution. This
    // creates a direction vector that's already normalized.
    float phi = 2 * M_PI_F * basis.random1;
    float cosThetaSquared = basis.random2;
    float sinTheta = sqrt(1.0 - cosThetaSquared);
    float3 direction(cos(phi) * sinTheta,
                     sin(phi) * sinTheta, sqrt(cosThetaSquared));
    
    // Apply the basis as a linear transformation.
    direction = float3x3(basis.axes) * direction;
    return { origin, half3(direction) };
  }
};

class GenerationContext {
  constant CameraArguments* cameraArgs;
  uchar seed;
  
public:
  GenerationContext(constant CameraArguments* cameraArgs,
                    uint frameSeed,
                    ushort2 pixelCoords) {
    this->cameraArgs = cameraArgs;
    
    uint pixelSeed = as_type<uint>(pixelCoords);
    uint seed1 = Sampling::tea(pixelSeed, frameSeed);
    ushort seed2 = as_type<ushort2>(seed1)[0];
    seed2 ^= as_type<ushort2>(seed1)[1];
    this->seed = seed2 ^ (seed2 / 256);
  }
  
  Ray<half> generate(ushort i, ushort samples, float3 hitPoint, half3 normal) {
    // Generate a random number and increment the seed.
    float random1 = Sampling::radinv3(seed);
    float random2 = Sampling::radinv2(seed);
    seed += 1;
    
    if (samples >= 3) {
      float sampleCountRecip = fast::divide(1, float(samples));
      float minimum = float(i) * sampleCountRecip;
      float maximum = minimum + sampleCountRecip;
      maximum = (i == samples - 1) ? 1 : maximum;
      random1 = mix(minimum, maximum, random1);
    }
    
    // Move origin slightly away from the surface to avoid self-occlusion.
    // Switching to a uniform grid acceleration structure should make it
    // possible to ignore this parameter.
    float3 origin = hitPoint + 0.0001 * float3(normal);
    
    // Align the atoms' coordinate systems with each other, to minimize
    // divergence. Here is a primitive method that achieves that by aligning
    // the X and Y dimensions to a common coordinate space.
    float3x3 rotation(cameraArgs->rotationColumn1,
                      cameraArgs->rotationColumn2,
                      cameraArgs->rotationColumn3);
    float3 modNormal = transpose(rotation) * float3(normal);
    float3x3 _axes = RayGeneration::makeBasis(modNormal);
    half3x3 axes = half3x3(rotation * _axes);
    
    // Create a random ray from the cosine distribution.
    RayGeneration::Basis basis { axes, random1, random2 };
    return RayGeneration::secondaryRay(origin, basis);
  }
};

#endif // RAY_GENERATION_H
