//
//  BVH+BuildSmall+Atoms.metal
//  MolecularRendererGPU
//
//  Created by Philip Turner on 7/15/23.
//

#include <metal_stdlib>
#include "../Utilities/Constants.metal"
#include "../Utilities/VoxelAddress.metal"
using namespace metal;

inline ushort pickPermutation(ushort3 footprint) {
  ushort output;
  if (footprint[2] > footprint[0] && footprint[2] > footprint[1]) {
    output = 0;
  } else if (footprint[1] > footprint[0]) {
    output = 1;
  } else {
    output = 2;
  }
  return output;
}

inline ushort3 reorderForward(ushort3 loopBound, ushort permutationID) {
  ushort3 output;
  if (permutationID == 0) {
    output = ushort3(loopBound[1], loopBound[2], loopBound[0]);
  } else if (permutationID == 1) {
    output = ushort3(loopBound[0], loopBound[2], loopBound[1]);
  } else {
    output = ushort3(loopBound[0], loopBound[1], loopBound[2]);
  }
  return output;
}

inline ushort3 reorderBackward(ushort3 loopBound, ushort permutationID) {
  ushort3 output;
  if (permutationID == 0) {
    output = ushort3(loopBound[2], loopBound[0], loopBound[1]);
  } else if (permutationID == 1) {
    output = ushort3(loopBound[0], loopBound[2], loopBound[1]);
  } else {
    output = ushort3(loopBound[0], loopBound[1], loopBound[2]);
  }
  return output;
}

inline ushort3 clamp(short3 position, ushort3 world_dims) {
  short3 output = position;
  output = clamp(output, 0, short3(world_dims));
  return ushort3(output);
}

// Test whether an atom overlaps a 1x1x1 cube.
inline bool cubeSphereIntersection(ushort3 cube_min, float4 atom)
{
  float3 c1 = float3(cube_min);
  float3 c2 = c1 + 1;
  float3 delta_c1 = atom.xyz - c1;
  float3 delta_c2 = atom.xyz - c2;
  
  float dist_squared = atom.w * atom.w;
#pragma clang loop unroll(full)
  for (int dim = 0; dim < 3; ++dim) {
    if (atom[dim] < c1[dim]) {
      dist_squared -= delta_c1[dim] * delta_c1[dim];
    } else if (atom[dim] > c2[dim]) {
      dist_squared -= delta_c2[dim] * delta_c2[dim];
    }
  }
  
  return dist_squared > 0;
}

// MARK: - Kernels

// Before:                    380 microseconds
// After reducing divergence: 350 microseconds
// Duplicating large atoms:   950 microseconds
// Increasing divergence:     960 milliseconds
// Using 2x small counters:
kernel void buildSmallPart1_1
(
 constant BVHArguments *bvhArgs [[buffer(0)]],
 device float4 *convertedAtoms [[buffer(1)]],
 device atomic_uint *smallCounterMetadata [[buffer(2)]],
 constant uint *atomCount [[buffer(3)]],
 device uint *largeAtomReferences [[buffer(4)]],
 uint tid [[thread_position_in_grid]])
{
  // Materialize the atom.
  if (tid >= *atomCount) {
    return;
  }
  uint atomID = largeAtomReferences[tid];
  float4 atom = convertedAtoms[atomID];
  
  // Place the atom in the grid of small cells.
  atom.xyz = 4 * (atom.xyz - bvhArgs->worldMinimum);
  atom.w = 4 * atom.w;
  
  // Generate the bounding box.
  ushort3 loopStart;
  ushort3 loopEnd;
  {
    short3 smallVoxelMin = short3(floor(atom.xyz - atom.w));
    short3 smallVoxelMax = short3(ceil(atom.xyz + atom.w));
    
    ushort3 gridDims = bvhArgs->smallVoxelCount;
    loopStart = clamp(smallVoxelMin, gridDims);
    loopEnd = clamp(smallVoxelMax, gridDims);
  }
  
  // Reorder the loop traversal.
  ushort permutationID = pickPermutation(loopEnd - loopStart);
  loopStart = reorderForward(loopStart, permutationID);
  loopEnd = reorderForward(loopEnd, permutationID);
  
  // Iterate over the footprint on the 3D grid.
  for (ushort z = loopStart[2]; z < loopEnd[2]; ++z) {
    for (ushort y = loopStart[1]; y < loopEnd[1]; ++y) {
      for (ushort x = loopStart[0]; x < loopEnd[0]; ++x) {
        ushort3 actualXYZ = ushort3(x, y, z);
        actualXYZ = reorderBackward(actualXYZ, permutationID);
        
        // Narrow down the cells with a cube-sphere intersection test.
        bool intersected = cubeSphereIntersection(actualXYZ, atom);
        if (!intersected) {
          continue;
        }
        
        // Locate the counter.
        ushort3 gridDims = bvhArgs->smallVoxelCount;
        uint address = VoxelAddress::generate(gridDims, actualXYZ);
        
        // Increment the counter.
        atomic_fetch_add_explicit(smallCounterMetadata + address,
                                  1, memory_order_relaxed);
      }
    }
  }
}

// Before:                    1.1 milliseconds
// After reducing divergence: 1.1 milliseconds
// Duplicating large atoms:   2.0 milliseconds
// Increasing divergence:     1.9 milliseconds
// Using 2x small counters:
kernel void buildSmallPart2_2
(
 constant BVHArguments *bvhArgs [[buffer(0)]],
 device float4 *convertedAtoms [[buffer(1)]],
 device atomic_uint *smallCounterMetadata [[buffer(2)]],
 device uint *smallAtomReferences [[buffer(3)]],
 constant uint *atomCount [[buffer(4)]],
 device uint *largeAtomReferences [[buffer(5)]],
 uint tid [[thread_position_in_grid]])
{
  // Materialize the atom.
  if (tid >= *atomCount) {
    return;
  }
  uint atomID = largeAtomReferences[tid];
  float4 atom = convertedAtoms[atomID];
  
  // Place the atom in the grid of small cells.
  atom.xyz = 4 * (atom.xyz - bvhArgs->worldMinimum);
  atom.w = 4 * atom.w;
  
  // Generate the bounding box.
  ushort3 loopStart;
  ushort3 loopEnd;
  {
    short3 smallVoxelMin = short3(floor(atom.xyz - atom.w));
    short3 smallVoxelMax = short3(ceil(atom.xyz + atom.w));
    
    ushort3 gridDims = bvhArgs->smallVoxelCount;
    loopStart = clamp(smallVoxelMin, gridDims);
    loopEnd = clamp(smallVoxelMax, gridDims);
  }
  
  // Reorder the loop traversal.
  ushort permutationID = pickPermutation(loopEnd - loopStart);
  loopStart = reorderForward(loopStart, permutationID);
  loopEnd = reorderForward(loopEnd, permutationID);
  
  // Iterate over the footprint on the 3D grid.
  for (ushort z = loopStart[2]; z < loopEnd[2]; ++z) {
    for (ushort y = loopStart[1]; y < loopEnd[1]; ++y) {
      for (ushort x = loopStart[0]; x < loopEnd[0]; ++x) {
        ushort3 actualXYZ = ushort3(x, y, z);
        actualXYZ = reorderBackward(actualXYZ, permutationID);
        
        // Narrow down the cells with a cube-sphere intersection test.
        bool intersected = cubeSphereIntersection(actualXYZ, atom);
        if (!intersected) {
          continue;
        }
        
        // Locate the counter.
        ushort3 gridDims = bvhArgs->smallVoxelCount;
        uint address = VoxelAddress::generate(gridDims, actualXYZ);
        
        // Increment the counter.
        uint offset =
        atomic_fetch_add_explicit(smallCounterMetadata + address,
                                  1, memory_order_relaxed);
        
        // Write the reference to the list.
        smallAtomReferences[offset] = atomID;
      }
    }
  }
}
