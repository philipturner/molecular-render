//
//  BVHBuilder+Prepare.swift
//  MolecularRenderer
//
//  Created by Philip Turner on 8/20/24.
//

import Metal
import QuartzCore
import simd

extension BVHBuilder {
  func prepareBVH(frameID: Int) {
    let preprocessingTimeCPU = reduceAndAssignBB()
    let copyingTime = copyAtoms()
    
    let commandBuffer = renderer.commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    encodeConvert(to: encoder)
    encodeSetIndirectArguments(to: encoder)
    encoder.endEncoding()
    
    commandBuffer.addCompletedHandler { [self] commandBuffer in
      let frameReporter = self.renderer.frameReporter!
      frameReporter.queue.sync {
        let index = frameReporter.index(of: frameID)
        guard let index else {
          return
        }
        
        let executionTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
        frameReporter.reports[index].reduceBBTime = preprocessingTimeCPU
        frameReporter.reports[index].copyTime = copyingTime
        frameReporter.reports[index].prepareTime = executionTime
      }
    }
    commandBuffer.commit()
  }
}

extension BVHBuilder {
  // Run and time the bounding box construction.
  func reduceAndAssignBB() -> Double {
    let preprocessingStart = CACurrentMediaTime()
    (worldMinimum, worldMaximum) = reduceBoundingBox()
    let preprocessingEnd = CACurrentMediaTime()
    
    return preprocessingEnd - preprocessingStart
  }
  
  // Run and time the copying into the GPU buffer.
  func copyAtoms() -> Double {
    let atoms = renderer.argumentContainer.currentAtoms
    let tripleIndex = renderer.argumentContainer.tripleBufferIndex()
    let originalAtomsBuffer = originalAtomsBuffers[tripleIndex]
    
    let copyingStart = CACurrentMediaTime()
    memcpy(originalAtomsBuffer.contents(), atoms, atoms.count * 16)
    let copyingEnd = CACurrentMediaTime()
    
    return copyingEnd - copyingStart
  }
}

extension BVHBuilder {
  func encodeConvert(to encoder: MTLComputeCommandEncoder) {
    // Argument 0
    do {
      let tripleIndex = renderer.argumentContainer.tripleBufferIndex()
      let originalAtomsBuffer = originalAtomsBuffers[tripleIndex]
      encoder.setBuffer(originalAtomsBuffer, offset: 0, index: 0)
    }
    
    // Argument 1
    renderer.atomRadii.withUnsafeBufferPointer {
      let length = $0.count * 4
      encoder.setBytes($0.baseAddress!, length: length, index: 1)
    }
    
    // Argument 2
    encoder.setBuffer(convertedAtomsBuffer, offset: 0, index: 2)
    
    // Dispatch
    let atoms = renderer.argumentContainer.currentAtoms
    encoder.setComputePipelineState(convertPipeline)
    encoder.dispatchThreads(
      MTLSizeMake(atoms.count, 1, 1),
      threadsPerThreadgroup: MTLSizeMake(128, 1, 1))
  }
  
  func encodeSetIndirectArguments(to encoder: MTLComputeCommandEncoder) {
    // Arguments 0 - 1
    do {
      var boundingBoxMin = worldMinimum
      var boundingBoxMax = worldMaximum
      encoder.setBytes(&boundingBoxMin, length: 16, index: 0)
      encoder.setBytes(&boundingBoxMax, length: 16, index: 1)
    }
    
    // Argument 2
    encoder.setBuffer(bvhArgumentsBuffer, offset: 0, index: 2)
    
    // Dispatch
    let singleThread = MTLSize(width: 1, height: 1, depth: 1)
    encoder.setComputePipelineState(setIndirectArgumentsPipeline)
    encoder.dispatchThreads(
      singleThread, threadsPerThreadgroup: singleThread)
  }
}
