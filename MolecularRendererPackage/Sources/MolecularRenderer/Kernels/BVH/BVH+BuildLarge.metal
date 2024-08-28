//
//  BVH+BuildLarge.metal
//  MolecularRendererGPU
//
//  Created by Philip Turner on 8/26/24.
//

#include <metal_stdlib>
#include "../Utilities/Constants.metal"
#include "../Utilities/VoxelAddress.metal"
using namespace metal;

// Quantize a position relative to the world origin.
inline ushort3 quantize(float3 position, ushort3 world_dims) {
  short3 output = short3(position);
  output = clamp(output, 0, short3(world_dims));
  return ushort3(output);
}

// Tasks:
// - Replicate 'buildSmallPart1'. [DONE]
// - Switch to generating the large voxel coordinate from the small voxel
//   coordinate.
// - Count the atom's footprint in each of 8 voxels.
//   - Match the reference count from the "bounding box" algorithm.
// - Accumulate both metrics at the same time.
kernel void buildLargePart1
(
 constant BVHArguments *bvhArgs [[buffer(0)]],
 device atomic_uint *largeCellMetadata [[buffer(1)]],
 device float4 *convertedAtoms [[buffer(2)]],
 
 uint tid [[thread_position_in_grid]])
{
  // Original code
#if 0
  // Transform the atom.
  float4 newAtom = convertedAtoms[tid];
  newAtom.xyz = (newAtom.xyz - bvhArgs->worldMinimum) / 2;
  newAtom.w = newAtom.w / 2;
  
  // Generate the bounding box.
  ushort3 grid_dims = bvhArgs->largeVoxelCount;
  auto box_min = quantize(newAtom.xyz - newAtom.w, grid_dims);
  auto box_max = quantize(newAtom.xyz + newAtom.w, grid_dims);
  
  // Iterate over the footprint on the 3D grid.
  for (ushort z = box_min[2]; z <= box_max[2]; ++z) {
    for (ushort y = box_min[1]; y <= box_max[1]; ++y) {
      for (ushort x = box_min[0]; x <= box_max[0]; ++x) {
        ushort3 cube_min { x, y, z };
        
        // Increment the voxel's counter.
        uint address = VoxelAddress::generate(grid_dims, cube_min);
        address = (address * 8) + (tid % 8);
        atomic_fetch_add_explicit(largeCellMetadata + address,
                                  1, memory_order_relaxed);
      }
    }
  }
  
  // New Code
#else
  // Transform the atom.
  float4 newAtom = convertedAtoms[tid];
  newAtom.xyz = 4 * (newAtom.xyz - bvhArgs->worldMinimum);
  newAtom.w = 4 * newAtom.w;
  
  // Generate the bounding box.
  short3 small_voxel_min = short3(floor(newAtom.xyz - newAtom.w));
  short3 small_voxel_max = short3(ceil(newAtom.xyz + newAtom.w));
  small_voxel_min = max(small_voxel_min, 0);
  small_voxel_max = max(small_voxel_max, 0);
  small_voxel_min = min(small_voxel_min, short3(bvhArgs->smallVoxelCount));
  small_voxel_max = min(small_voxel_max, short3(bvhArgs->smallVoxelCount));
  auto large_voxel_min = small_voxel_min / 8;
  auto large_voxel_max = small_voxel_max / 8;
  
  // Pre-compute the footprint.
  short3 dividingLine = large_voxel_max * 8;
  dividingLine = min(dividingLine, small_voxel_max);
  dividingLine = max(dividingLine, small_voxel_min);
  short3 footprintLow = dividingLine - small_voxel_min;
  short3 footprintHigh = small_voxel_max - dividingLine;
  
  ushort3 loopStart = select(ushort3(1),
                             ushort3(0),
                             footprintLow > 0);
  ushort3 loopEnd = select(ushort3(1),
                           ushort3(2),
                           footprintHigh > 0);
  
  // Iterate over the footprint on the 3D grid.
  //
  // TODO: Manually unroll these loops and measure the performance improvement.
#pragma clang loop unroll(disable)
  for (ushort z = loopStart[2]; z < loopEnd[2]; ++z) {
//    if (z == 1 && footprintHigh.z <= 0) {
//      continue;
//    }
    
#pragma clang loop unroll(disable)
    for (ushort y = loopStart[1]; y < loopEnd[1]; ++y) {
//      if (y == 1 && footprintHigh.y <= 0) {
//        continue;
//      }
      
#pragma clang loop unroll(disable)
      for (ushort x = loopStart[0]; x < loopEnd[0]; ++x) {
//        if (x == 1 && footprintHigh.x <= 0) {
//          continue;
//        }
        ushort3 xyz(x, y, z);
        
        // What subregion of the atom's bounding box falls within this large
        // voxel?
        short3 footprint = short3(0);
#pragma clang loop unroll(full)
        for (ushort laneID = 0; laneID < 3; ++laneID) {
          if (xyz[laneID] == 1) {
            footprint[laneID] = footprintHigh[laneID];
          } else {
            footprint[laneID] = footprintLow[laneID];
          }
        }
        
        // If included, move on to the next section.
        //
        // TODO: Determine whether a cleaner guard/continue statement harms
        // the instruction count.
        //if (all(footprint > 0))
        {
          ushort3 cube_min = ushort3(large_voxel_min) + xyz;
          ushort3 grid_dims = bvhArgs->largeVoxelCount;
          uint address = VoxelAddress::generate(grid_dims, cube_min);
          address = (address * 8) + (tid % 8);
          
          uint smallReferenceCount =
          footprint[0] * footprint[1] * footprint[2];
          uint word = (smallReferenceCount << 14) + 1;
          atomic_fetch_add_explicit(largeCellMetadata + address,
                                    word, memory_order_relaxed);
        }
      }
    }
  }
#endif
}
