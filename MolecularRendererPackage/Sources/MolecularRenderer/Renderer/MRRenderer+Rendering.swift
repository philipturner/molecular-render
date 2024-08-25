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
  
  // Dispatch threadgroups for the render command.
  func dispatchThreadgroups(to encoder: MTLComputeCommandEncoder) {
    // Dispatch an even number of threads (the shader will rearrange them).
    var dispatchGrid = MTLSize(width: 1, height: 1, depth: 1)
    dispatchGrid.width = (argumentContainer.intermediateTextureSize + 7) / 8
    dispatchGrid.height = (argumentContainer.intermediateTextureSize + 7) / 8
    
    var threadgroupGrid = MTLSize(width: 1, height: 1, depth: 1)
    threadgroupGrid.width = 8
    threadgroupGrid.height = 8
    encoder.dispatchThreadgroups(
      dispatchGrid, threadsPerThreadgroup: threadgroupGrid)
  }
  
  // Encode the GPU command for ray tracing.
  func render(commandQueue: MTLCommandQueue, frameID: Int) {
    /*
     constant CameraArguments *cameraArgs [[buffer(0)]],
     constant BVHArguments *bvhArgs [[buffer(1)]],
     constant RenderArguments *renderArgs [[buffer(2)]],
     
     device uint *dense_grid_data [[buffer(5)]],
     device uint *dense_grid_references [[buffer(6)]],
     
     device float4 *newAtoms [[buffer(10)]],
     device float3 *atomColors [[buffer(11)]],
     device float3 *motionVectors [[buffer(12)]],
     
     texture2d<half, access::write> color_texture [[texture(0)]],
     texture2d<float, access::write> depth_texture [[texture(1)]],
     texture2d<half, access::write> motion_texture [[texture(2)]],
     */
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(renderPipeline)
    
    // Arguments 0 - 2
    do {
      let cameraArguments = argumentContainer.createCameraArguments()
      let bvhArguments = [bvhBuilder.createBVHArguments()]
      let renderArguments = [argumentContainer.createRenderArguments()]
      
      func setBytes<T>(_ array: [T], index: Int) {
        let elementLength = MemoryLayout<T>.stride
        let arrayLength = array.count * elementLength
        encoder.setBytes(array, length: arrayLength, index: index)
      }
      setBytes(cameraArguments, index: 0)
      setBytes(bvhArguments, index: 1)
      setBytes(renderArguments, index: 2)
    }
    
    // Arguments 5 - 6
    do {
      let denseGridData = bvhBuilder.denseGridData
      let denseGridReferences = bvhBuilder.denseGridReferences
      guard let denseGridData,
            let denseGridReferences else {
        fatalError("BVH was not available.")
      }
      
      // Bind the dense grid data at offset 32.
      encoder.setBuffer(denseGridData, offset: 32, index: 5)
      
      // Bind the dense grid references.
      encoder.setBuffer(denseGridReferences, offset: 0, index: 6)
    }
    
    // Arguments 10 - 12
    do {
      // Bind the atoms.
      encoder.setBuffer(bvhBuilder.newAtomsBuffer, offset: 0, index: 10)
      
      // Bind the colors.
      let atomColorsLength = atomColors.count * 16
      encoder.setBytes(&atomColors, length: atomColorsLength, index: 11)
      
      // Bind the atom motion vectors.
      let ringIndex = bvhBuilder.ringIndex
      let motionVectors = bvhBuilder.motionVectorBuffers[ringIndex]
      guard let motionVectors else {
        fatalError("Atom-wise motion vectors were not available.")
      }
      encoder.setBuffer(motionVectors, offset: 0, index: 12)
    }
    
    // Textures 0 - 2
    do {
      let jitterFrameID = argumentContainer.jitterFrameID
      let textures = bufferedIntermediateTextures[jitterFrameID % 2]
      encoder.setTexture(textures.color, index: 0)
      encoder.setTexture(textures.depth, index: 1)
      encoder.setTexture(textures.motion, index: 2)
    }
    
    dispatchThreadgroups(to: encoder)
    
    encoder.endEncoding()
    commandBuffer.addCompletedHandler { [self] commandBuffer in
      let executionTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
      self.bvhBuilder.frameReportQueue.sync {
        for index in self.bvhBuilder.frameReports.indices.reversed() {
          guard self.bvhBuilder.frameReports[index].frameID == frameID else {
            continue
          }
          self.bvhBuilder.frameReports[index].renderTime = executionTime
          break
        }
      }
    }
    commandBuffer.commit()
  }
}

