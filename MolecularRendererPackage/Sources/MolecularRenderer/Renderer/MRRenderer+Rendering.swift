//
//  MRRenderer+Rendering.swift
//  MolecularRenderer
//
//  Created by Philip Turner on 12/20/23.
//

import Metal

extension MRRenderer {
  func initRayTracer(library: MTLLibrary) {
    let constants = MTLFunctionConstantValues()
    var screenWidth = UInt32(argumentContainer.intermediateTextureSize)
    var screenHeight = UInt32(argumentContainer.intermediateTextureSize)
    constants.setConstantValue(&screenWidth, type: .uint, index: 0)
    constants.setConstantValue(&screenHeight, type: .uint, index: 1)
    
    let function = try! library.makeFunction(
      name: "renderAtoms", constantValues: constants)
    
    let desc = MTLComputePipelineDescriptor()
    desc.computeFunction = function
    desc.maxTotalThreadsPerThreadgroup = 1024
    self.renderPipeline = try! device.makeComputePipelineState(
      descriptor: desc, options: [], reflection: nil)
  }
  
  func dispatchRenderingWork(frameID: Int) {
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    
    // Bind the camera arguments.
    do {
      let cameraArguments = argumentContainer.createCameraArguments()
      let elementLength = MemoryLayout<CameraArguments>.stride
      let arrayLength = 2 * elementLength
      encoder.setBytes(cameraArguments, length: arrayLength, index: 0)
    }
    
    // Bind the render arguments.
    do {
      var renderArguments = argumentContainer.createRenderArguments()
      let length = MemoryLayout<RenderArguments>.stride
      encoder.setBytes(&renderArguments, length: length, index: 1)
    }
    
    // Bind the BVH arguments.
    do {
      encoder.setBuffer(bvhBuilder.bvhArguments, offset: 0, index: 2)
    }
    
    // Bind the element colors.
    do {
      let colors32 = argumentContainer.elementColors
      
      // Convert the colors from Float32 to Float16.
      #if arch(x86_64)
      fatalError("x86_64 is not supported.")
      #else
      var colors16: [SIMD3<Float16>] = []
      for atomicNumber in 0...118 {
        // Branch on whether the color was specified.
        if atomicNumber < colors32.count {
          let color32 = colors32[atomicNumber]
          let color16 = SIMD3<Float16>(color32)
          colors16.append(color16)
        } else {
          colors16.append(.zero)
        }
      }
      encoder.setBytes(colors16, length: 119 * 8, index: 3)
      #endif
    }
    
    // Bind the remaining buffers.
    do {
      encoder.setBuffer(bvhBuilder.largeCellMetadata, offset: 0, index: 4)
      encoder.setBuffer(bvhBuilder.smallCellOffsets, offset: 0, index: 5)
      encoder.setBuffer(bvhBuilder.smallAtomReferences, offset: 0, index: 6)
      encoder.setBuffer(bvhBuilder.convertedAtoms, offset: 0, index: 7)
      encoder.setBuffer(bvhBuilder.atomMotionVectors, offset: 0, index: 8)
    }
    
    // Bind the textures.
    do {
      let textureIndex = argumentContainer.doubleBufferIndex()
      let textures = bufferedIntermediateTextures[textureIndex]
      encoder.setTexture(textures.color, index: 0)
      encoder.setTexture(textures.depth, index: 1)
      encoder.setTexture(textures.motion, index: 2)
    }
    
    // Dispatch the correct number of threadgroups.
    do {
      let pipeline = renderPipeline!
      encoder.setComputePipelineState(pipeline)
      
      let textureSize = argumentContainer.intermediateTextureSize
      let dispatchSize = (textureSize + 7) / 8
      encoder.dispatchThreadgroups(
        MTLSize(width: dispatchSize, height: dispatchSize, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }
    
    // Submit the command buffer.
    encoder.endEncoding()
    commandBuffer.addCompletedHandler { [self] commandBuffer in
      let frameReporter = self.frameReporter!
      frameReporter.queue.sync {
        let index = frameReporter.index(of: frameID)
        guard let index else {
          return
        }
        
        let executionTime =
        commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
        frameReporter.reports[index].renderTime = executionTime
      }
    }
    commandBuffer.commit()
  }
}
