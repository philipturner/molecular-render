//
//  RayIntersector.metal
//  MolecularRenderer
//
//  Created by Philip Turner on 4/14/23.
//

#ifndef RAY_TRAVERSAL_H
#define RAY_TRAVERSAL_H

#include <metal_stdlib>
#include "../Ray/DDA.metal"
#include "../Utilities/Constants.metal"
using namespace metal;

// MARK: - Data Structures

struct IntersectionResult {
  bool accept;
  uint atomID;
  float distance;
};

struct IntersectionQuery {
  float3 rayOrigin;
  float3 rayDirection;
};

// MARK: - Intersector Class

struct RayIntersector {
  device half4 *convertedAtoms;
  device ushort *smallAtomReferences;
  device uint4 *largeCellMetadata;
  device uint4 *compactedLargeCellMetadata;
  device ushort2 *compactedSmallCellMetadata;
  threadgroup uint *threadgroupMemory;
  ushort threadIndex;
  
  uint globalFaultCounter = 0;
  uint errorCode = 0;
  static uint maxFaultCounter() {
    return 200;
  }
  
  // Retrieves the large cell metadata from the uncompacted buffer.
  uint4 largeMetadata(float3 largeLowerCorner) const
  {
    float3 coordinates = (largeLowerCorner + 64) / 2;
    float address =
    VoxelAddress::generate<float, float>(64, coordinates);
    return largeCellMetadata[uint(address)];
  }
  
  // Retrieves the small cell metadata from the compacted buffer.
  ushort2 smallMetadata(float3 largeLowerCorner,
                        float3 smallLowerCorner,
                        uint compactedLargeCellID) const
  {
    float3 coordinates = (smallLowerCorner - largeLowerCorner) / 0.25;
    float localAddress =
    VoxelAddress::generate<float, float>(8, coordinates);
    
    uint compactedGlobalAddress =
    compactedLargeCellID * 512 + uint(localAddress);
    return compactedSmallCellMetadata[compactedGlobalAddress];
  }
  
  // Fills the memory tape with large voxels.
  void fillMemoryTape(thread float3 &cursorCellBorder,
                      thread ushort &acceptedVoxelCount,
                      thread bool &outOfBounds,
                      IntersectionQuery intersectionQuery,
                      const DDA dda)
  {
    while (acceptedVoxelCount < 16) {
      globalFaultCounter += 1;
      if (globalFaultCounter > maxFaultCounter()) {
        errorCode = 1;
        break;
      }
      
      // Compute the lower corner.
      float3 smallLowerCorner = dda.cellLowerCorner(cursorCellBorder);
      float3 largeLowerCorner = 2 * floor(smallLowerCorner / 2);
      if (any(largeLowerCorner < -64) || any(largeLowerCorner >= 64)) {
        outOfBounds = true;
        return;
      }
      
      // If the large cell has small cells, proceed.
      uint4 largeMetadata = this->largeMetadata(largeLowerCorner);
      if (largeMetadata[0] > 0) {
        uint compactedLargeCellID = largeMetadata[0];
        uint threadgroupAddress = acceptedVoxelCount * 64 + threadIndex;
        threadgroupMemory[threadgroupAddress] = compactedLargeCellID;
        acceptedVoxelCount += 1;
      }
      
      // Fast forward to the next large voxel.
      cursorCellBorder = dda.nextSmallBorder(cursorCellBorder,
                                             intersectionQuery.rayOrigin);
    }
  }
  
  // Intersects all of the atoms in a small voxel.
  void testCell(thread IntersectionResult &result,
                float3 largeLowerCorner,
                uint4 largeMetadata,
                ushort2 smallMetadata,
                IntersectionQuery intersectionQuery,
                const DDA dda)
  {
    // Set the origin register.
    float3 origin = intersectionQuery.rayOrigin;
    origin -= largeLowerCorner;
    
    // Set the loop bounds register.
    uint referenceCursor = largeMetadata[2] + smallMetadata[0];
    uint referenceEnd = referenceCursor + smallMetadata[1];
    
    // Test every atom in the voxel.
    while (referenceCursor < referenceEnd) {
      // Locate the atom.
      ushort reference = smallAtomReferences[referenceCursor];
      
      // Retrieve the atom.
      uint atomID = largeMetadata[1] + reference;
      half4 atom = convertedAtoms[atomID];
      
      // Run the intersection test.
      {
        float3 oc = origin - float3(atom.xyz);
        float b2 = dot(float3(oc), intersectionQuery.rayDirection);
        
        float radius = float(atom.w);
        float c = -radius * radius;
        c = fma(oc.x, oc.x, c);
        c = fma(oc.y, oc.y, c);
        c = fma(oc.z, oc.z, c);
        
        float disc4 = b2 * b2 - c;
        if (disc4 > 0) {
          float distance = fma(-disc4, rsqrt(disc4), -b2);
          if (distance >= 0 && distance < result.distance) {
            result.atomID = atomID;
            result.distance = distance;
          }
        }
      }
      
      // Increment to the next reference.
      referenceCursor += 1;
    }
  }
  
  // BVH traversal algorithm for primary rays. These rays must jump very
  // large distances, but have minimal divergence.
  IntersectionResult intersectPrimary(IntersectionQuery intersectionQuery) {
    // Initialize the outer DDA.
    float3 largeCellBorder;
    const DDA largeDDA(&largeCellBorder,
                       intersectionQuery.rayOrigin,
                       intersectionQuery.rayDirection,
                       2.00);
    
    IntersectionResult result;
    result.accept = false;
    
    bool outOfBounds = false;
    while (!result.accept && !outOfBounds) {
      globalFaultCounter += 1;
      if (globalFaultCounter > maxFaultCounter()) {
        errorCode = 2;
        break;
      }
      
      // Loop over ~16 large voxels.
      ushort acceptedVoxelCount = 0;
      fillMemoryTape(largeCellBorder,
                     acceptedVoxelCount,
                     outOfBounds,
                     intersectionQuery,
                     largeDDA);
      
      simdgroup_barrier(mem_flags::mem_threadgroup);
      
      // Allocate the small DDA.
      DDA smallDDA;
      ushort acceptedVoxelCursor = 0;
      
      // Loop over ~128 small voxels.
      while (acceptedVoxelCursor < acceptedVoxelCount) {
        globalFaultCounter += 1;
        if (globalFaultCounter > maxFaultCounter()) {
          errorCode = 3;
          break;
        }
        
        // Read from threadgroup memory.
        uint threadgroupAddress = acceptedVoxelCursor * 64 + threadIndex;
        uint compactedLargeCellID = threadgroupMemory[threadgroupAddress];
        
        // Retrieve the large cell metadata.
        uint4 largeMetadata = compactedLargeCellMetadata[compactedLargeCellID];
        uchar4 compressedCellCoordinates = as_type<uchar4>(largeMetadata[0]);
        uint3 cellIndex1 = uint3(compressedCellCoordinates.xyz);
        
        // Compute the voxel bounds.
        float3 coordinates1 = float3(cellIndex1);
        float3 largeLowerCorner = coordinates1 * 2 - 64;
        float3 largeUpperCorner = largeLowerCorner + 2;
        
        // Initialize the inner DDA.
        float3 smallCellBorder;
        const DDA smallDDA(&smallCellBorder,
                           intersectionQuery.rayOrigin,
                           intersectionQuery.rayDirection,
                           largeLowerCorner,
                           largeUpperCorner);
        
        while (!result.accept) {
          globalFaultCounter += 1;
          if (globalFaultCounter > maxFaultCounter()) {
            errorCode = 4;
            break;
          }
          
          // Compute the lower corner.
          float3 smallLowerCorner = smallDDA.cellLowerCorner(smallCellBorder);
          
          // Check whether the DDA has gone out of bounds.
          if (any(smallLowerCorner < largeLowerCorner) ||
              any(smallLowerCorner >= largeUpperCorner)) {
            acceptedVoxelCursor += 1;
            break; // while loop
          }
          
          // Retrieve the small cell metadata.
          ushort2 smallMetadata = this->smallMetadata(largeLowerCorner,
                                                      smallLowerCorner,
                                                      compactedLargeCellID);
          
          if (smallMetadata[1] > 0) {
            // Compute the voxel maximum time.
            float3 acceptedSmallCellBorder = smallLowerCorner;
            acceptedSmallCellBorder +=
            select(float3(-smallDDA.dx), float3(0), smallDDA.dtdx >= 0);
            float voxelMaximumHitTime = smallDDA
              .voxelMaximumHitTime(acceptedSmallCellBorder,
                                   intersectionQuery.rayOrigin);
            
            // Set the distance register.
            result.distance = voxelMaximumHitTime;
            
            // Test the atoms in the accepted voxel.
            testCell(result,
                     largeLowerCorner,
                     largeMetadata,
                     smallMetadata,
                     intersectionQuery,
                     smallDDA);
            
            // Check whether we found a hit.
            if (result.distance < voxelMaximumHitTime) {
              result.accept = true;
            }
          }
          
          // Increment to the next small voxel.
          smallCellBorder = smallDDA.nextSmallBorder(smallCellBorder,
                                                     intersectionQuery.rayOrigin);
        }
        
        if (result.accept) {
          acceptedVoxelCursor = acceptedVoxelCount;
        }
      }
    }
    
    return result;
  }
  
  // BVH traversal algorithm for AO rays. These rays terminate after traveling
  // 1 nm, but their divergence can be extremely high.
  IntersectionResult intersectAO(IntersectionQuery intersectionQuery)
  {
    float3 cursorCellBorder;
    const DDA dda(&cursorCellBorder,
                  intersectionQuery.rayOrigin,
                  intersectionQuery.rayDirection,
                  0.25);
    
    IntersectionResult result;
    result.accept = false;
    
    while (!result.accept) {
      // Compute the voxel maximum time.
      float voxelMaximumHitTime = dda
        .voxelMaximumHitTime(cursorCellBorder,
                             intersectionQuery.rayOrigin);
      
      // This cutoff is parameterized for small voxels, where the distance
      // is 0.25 nm. If you switch to testing a different voxel size, the
      // parameter must change.
      constexpr float cutoff = 1 + 0.25 * 1.732051;
      
      // Compute the lower corner.
      float3 smallLowerCorner = dda.cellLowerCorner(cursorCellBorder);
      float3 largeLowerCorner = 2 * floor(smallLowerCorner / 2);
      
      // Check whether the DDA has gone out of bounds.
      if ((voxelMaximumHitTime > cutoff) ||
          any(largeLowerCorner < -64) ||
          any(largeLowerCorner >= 64)) {
        break;
      }
      
      // If the large cell has small cells, proceed.
      uint4 largeMetadata = this->largeMetadata(largeLowerCorner);
      if (largeMetadata[0] > 0) {
        ushort2 smallMetadata = this->smallMetadata(largeLowerCorner,
                                                    smallLowerCorner,
                                                    largeMetadata[0]);
        if (smallMetadata[1] > 0) {
          // Set the distance register.
          result.distance = voxelMaximumHitTime;
          
          // Test the atoms in the accepted voxel.
          testCell(result,
                   largeLowerCorner,
                   largeMetadata,
                   smallMetadata,
                   intersectionQuery,
                   dda);
          
          // Check whether we found a hit.
          if (result.distance < voxelMaximumHitTime) {
            result.accept = true;
          }
        }
      }
      
      // Increment to the next small voxel.
      cursorCellBorder = dda.nextSmallBorder(cursorCellBorder,
                                             intersectionQuery.rayOrigin);
    }
    
    return result;
  }
};

#endif // RAY_TRAVERSAL_H
