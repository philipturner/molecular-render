//
//  BVHBuilder.swift
//  MolecularRenderer
//
//  Created by Philip Turner on 6/17/23.
//

import Accelerate
import Metal
import simd
import QuartzCore

// There should be an option to enable this performance reporting mechanism, in
// the descriptor for 'MRRenderer'.
struct MRFrameReport {
  // The ID of the frame that owns this report.
  var frameID: Int
  
  // CPU time spent preparing geometry.
  var preprocessingTimeCPU: Double
  
  // CPU time spent copying geometry into GPU buffer.
  var copyingTime: Double
  
  // GPU time spent preparing geometry.
  var preprocessingTimeGPU: Double
  
  // GPU time spent building the uniform grid.
  var geometryTime: Double
  
  // GPU time spent rendering.
  var renderTime: Double
}

class BVHBuilder {
  // Main rendering resources.
  var device: MTLDevice
  unowned var renderer: MRRenderer
  
  // Safeguard access to these using a dispatch queue.
  var reportPerformance: Bool = false
  var frameReportQueue: DispatchQueue = .init(
    label: "com.philipturner.MolecularRenderer.BVHBuilder.frameReportQueue")
  var frameReports: [MRFrameReport] = []
  var frameReportCounter: Int = 0
  static let frameReportHistorySize: Int = 10
  
  // BVH state information.
  var worldMinimum: SIMD3<Float> = .zero
  var worldMaximum: SIMD3<Float> = .zero
  
  // Pipeline state objects.
  var memsetPipeline: MTLComputePipelineState
  var preprocessPipeline: MTLComputePipelineState
  var densePass1Pipeline: MTLComputePipelineState
  var densePass2Pipeline: MTLComputePipelineState
  var densePass3Pipeline: MTLComputePipelineState
  
  // Data buffers (per atom).
  var originalAtomsBuffers: [MTLBuffer]
  var convertedAtomsBuffer: MTLBuffer
  
  // Data buffers (other).
  var globalAtomicCounters: MTLBuffer
  var smallCellMetadata: MTLBuffer
  var smallCellCounters: MTLBuffer
  var smallCellAtomReferences: MTLBuffer
  
  public init(
    renderer: MRRenderer,
    library: MTLLibrary
  ) {
    self.device = renderer.device
    self.renderer = renderer
    
    // Initialize the memset kernel.
    let constants = MTLFunctionConstantValues()
    var pattern4: UInt32 = 0
    constants.setConstantValue(&pattern4, type: .uint, index: 1000)
    
    let memsetFunction = try! library.makeFunction(
      name: "memset_pattern4", constantValues: constants)
    self.memsetPipeline = try! device
      .makeComputePipelineState(function: memsetFunction)
    
    // Initialize kernels for BVH construction.
    let preprocessFunction = library.makeFunction(name: "preprocess")!
    let densePass1Function = library.makeFunction(name: "dense_grid_pass1")!
    let densePass2Function = library.makeFunction(name: "dense_grid_pass2")!
    let densePass3Function = library.makeFunction(name: "dense_grid_pass3")!
    preprocessPipeline = try! device
      .makeComputePipelineState(function: preprocessFunction)
    densePass1Pipeline = try! device
      .makeComputePipelineState(function: densePass1Function)
    densePass2Pipeline = try! device
      .makeComputePipelineState(function: densePass2Function)
    densePass3Pipeline = try! device
      .makeComputePipelineState(function: densePass3Function)
    
    // Allocate data buffers (per atom).
    func createAtomBuffer(device: MTLDevice) -> MTLBuffer {
      // Limited to 4 million atoms for now.
      let bufferSize: Int = (4 * 1024 * 1024) * 16
      return device.makeBuffer(length: bufferSize)!
    }
    originalAtomsBuffers = [
      createAtomBuffer(device: device),
      createAtomBuffer(device: device),
      createAtomBuffer(device: device),
    ]
    convertedAtomsBuffer = createAtomBuffer(device: device)
    
    // Allocate data buffers (other).
    globalAtomicCounters = device.makeBuffer(length: 8 * 4)!
    smallCellMetadata = device.makeBuffer(length: 512 * 512 * 512 * 4)!
    smallCellCounters = device.makeBuffer(length: 512 * 512 * 512 * 4)!
    smallCellAtomReferences = device.makeBuffer(length: 64 * 1024 * 1024 * 4)!
  }
}
