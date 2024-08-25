//
//  BVHBuilder+Preprocessing.swift
//  MolecularRenderer
//
//  Created by Philip Turner on 10/27/23.
//

import Metal
import Foundation
import simd
import func QuartzCore.CACurrentMediaTime

func denseGridStatistics(
  atoms: [SIMD4<Float>],
  atomRadii: [Float],
  voxel_width_numer: Float,
  voxel_width_denom: Float
) -> (boundingBox: (SIMD3<Float>, SIMD3<Float>), references: Int) {
  precondition(atoms.count > 0, "Not enough atoms.")
  precondition(atomRadii.count > 0, "Not enough styles.")
  precondition(atomRadii.count < 255, "Too many styles.")
  
  let epsilon: Float = 1e-4
  let workBlockSize: Int = 64 * 1024
  let numThreads = (atoms.count + workBlockSize - 1) / workBlockSize
  var elementInstances = [UInt32](repeating: .zero, count: 256 * numThreads)
  var minCoordinatesArray = [SIMD3<Float>](repeating: .zero, count: numThreads)
  var maxCoordinatesArray = [SIMD3<Float>](repeating: .zero, count: numThreads)
  var referencesArray = [Double](repeating: .zero, count: numThreads)
  
  DispatchQueue.concurrentPerform(iterations: numThreads) { taskID in
    var minCoordinates: SIMD4<Float> = .zero
    var maxCoordinates: SIMD4<Float> = .zero
    var references: Double = .zero
    var loopStart = atoms.count * taskID / numThreads
    var loopEnd = atoms.count * (taskID + 1) / numThreads
    let elementsOffset = 256 * taskID
    
    atoms.withUnsafeBufferPointer {
      let baseAddress = OpaquePointer($0.baseAddress!)
      let atomBuffer = UnsafeMutableRawPointer(baseAddress)
        .assumingMemoryBound(to: SIMD4<Float>.self)
      
      @inline(__always)
      func countCells(_ atom: SIMD4<Float>) -> SIMD4<Float> {
        let element = Int(atom.w)
        elementInstances[elementsOffset &+ element] &+= 1
        
        let radius = Float(atomRadii[element]) + epsilon
        let lowerBound = ((atom - radius) / 0.25)
        let upperBound = ((atom + radius) / 0.25)
        return upperBound.rounded(.down) - lowerBound.rounded(.down) + 1
      }
      
      while loopStart % 4 != 0, loopStart < loopEnd {
        let atom = atomBuffer[loopStart]
        minCoordinates = simd_min(minCoordinates, atom)
        maxCoordinates = simd_max(maxCoordinates, atom)
        
        let cells = countCells(atom)
        references += Double(cells[0] * cells[1] * cells[2])
        loopStart &+= 1
      }
      while loopEnd % 4 != 0, loopStart < loopEnd {
        let atom = atomBuffer[loopEnd &- 1]
        minCoordinates = simd_min(minCoordinates, atom)
        maxCoordinates = simd_max(maxCoordinates, atom)
        
        let cells = countCells(atom)
        references += Double(cells[0] * cells[1] * cells[2])
        loopEnd &-= 1
      }
      
      if loopStart % 4 == 0, loopEnd % 4 == 0 {
        let atomBuffer = UnsafeMutableRawPointer(baseAddress)
          .assumingMemoryBound(to: SIMD16<Float>.self)
        var minCoordinatesVector: SIMD8<Float> = .zero
        var maxCoordinatesVector: SIMD8<Float> = .zero
        
        for vectorID in loopStart / 4..<loopEnd / 4 {
          let vector = atomBuffer[vectorID]
          let atom1 = vector.lowHalf.lowHalf
          let atom2 = vector.lowHalf.highHalf
          let atom3 = vector.highHalf.lowHalf
          let atom4 = vector.highHalf.highHalf
          
          let cells1 = countCells(atom1)
          let cells2 = countCells(atom2)
          let cells3 = countCells(atom3)
          let cells4 = countCells(atom4)
          
          let products0 = SIMD4<Float>(
            cells1[0] * cells1[1] * cells1[2],
            cells2[0] * cells2[1] * cells2[2],
            cells3[0] * cells3[1] * cells3[2],
            cells4[0] * cells4[1] * cells4[2])
          references += Double(products0.sum())
          
          var minCoords = simd_min(vector.lowHalf, vector.highHalf)
          var maxCoords = simd_max(vector.lowHalf, vector.highHalf)
          minCoordinatesVector = simd_min(minCoordinatesVector, minCoords)
          maxCoordinatesVector = simd_max(maxCoordinatesVector, maxCoords)
        }
        
        minCoordinates = simd_min(
          minCoordinates, minCoordinatesVector.lowHalf)
        minCoordinates = simd_min(
          minCoordinates, minCoordinatesVector.highHalf)
        
        maxCoordinates = simd_max(
          maxCoordinates, maxCoordinatesVector.lowHalf)
        maxCoordinates = simd_max(
          maxCoordinates, maxCoordinatesVector.highHalf)
      }
    }
    
    minCoordinatesArray[taskID] = unsafeBitCast(
      minCoordinates, to: SIMD3<Float>.self)
    maxCoordinatesArray[taskID] = unsafeBitCast(
      maxCoordinates, to: SIMD3<Float>.self)
    referencesArray[taskID] = references
  }
  
  var minCoordinates: SIMD3<Float> = .zero
  var maxCoordinates: SIMD3<Float> = .zero
  for taskID in 0..<numThreads {
    minCoordinates = simd_min(minCoordinates, minCoordinatesArray[taskID])
    maxCoordinates = simd_max(maxCoordinates, maxCoordinatesArray[taskID])
  }
  for taskID in 1..<numThreads {
    for elementID in 0..<256 {
      elementInstances[elementID] += elementInstances[256 * taskID + elementID]
    }
  }
  guard let references = Int(exactly: referencesArray.reduce(0, +)) else {
    fatalError("This should never happen.")
  }
  
  var maxRadius: Float = 0
  for i in 0..<atomRadii.count {
    let radius = Float(atomRadii[i])
    let cellSpan = 1 + ceil(
      (2 * radius + epsilon) / 0.25)
    
    let instances = elementInstances[i]
    let presentMask: Float = (instances > 0) ? 1 : 0
    maxRadius = max(radius * presentMask, maxRadius)
  }
  maxRadius += epsilon
  minCoordinates -= maxRadius
  maxCoordinates += maxRadius
  
  return ((minCoordinates, maxCoordinates), references)
}

extension BVHBuilder {
  func reduceBoundingBox() -> (SIMD3<Float>, SIMD3<Float>) {
    let atoms = renderer.argumentContainer.currentAtoms
    
    var statistics = denseGridStatistics(
      atoms: atoms,
      atomRadii: renderer.atomRadii,
      voxel_width_numer: 4,
      voxel_width_denom: 16)
    guard statistics.references < 64 * 1024 * 1024 else {
      fatalError("Too many references for a dense grid.")
    }
    
    var minCoordinates = statistics.boundingBox.0
    var maxCoordinates = statistics.boundingBox.1
    
    // Round to the nearest multiple of 2 nm.
    do {
      minCoordinates /= 2
      maxCoordinates /= 2
      minCoordinates.round(.down)
      maxCoordinates.round(.up)
      minCoordinates *= 2
      maxCoordinates *= 2
    }
    
    // Clamp to [-64, 64].
    minCoordinates.replace(with: -64, where: minCoordinates .< -64)
    maxCoordinates.replace(with: 64, where: maxCoordinates .> 64)
    
    return (minCoordinates, maxCoordinates)
  }
  
  func buildDenseGrid(commandQueue: MTLCommandQueue, frameID: Int) {
    let atoms = renderer.argumentContainer.currentAtoms
    
    let preprocessingStart = CACurrentMediaTime()
    do {
      let boundingBox = reduceBoundingBox()
      worldOrigin = SIMD3<Int16>(boundingBox.0)
      worldDimensions = SIMD3<Int16>(boundingBox.1 - boundingBox.0)
    }
    let preprocessingEnd = CACurrentMediaTime()
    
    // The first rendered frame will have an ID of 1.
    frameReportCounter += 1
    let performance = frameReportQueue.sync { () -> SIMD8<Double> in
      // Remove frames too far back in the history.
      let minimumID = frameReportCounter - Self.frameReportHistorySize
      while frameReports.count > 0, frameReports.first!.frameID < minimumID {
        frameReports.removeFirst()
      }
      
      var dataSize: Int = 0
      var output: SIMD8<Double> = .zero
      for report in frameReports {
        if report.preprocessingTimeGPU >= 0,
           report.geometryTime >= 0,
           report.renderTime >= 0 {
          dataSize += 1
          output[0] += report.preprocessingTimeCPU
          output[1] += report.copyingTime
          output[2] += report.preprocessingTimeGPU
          output[3] += report.geometryTime
          output[4] += report.renderTime
        }
      }
      if dataSize > 0 {
        output /= Double(dataSize)
      }
      
      let report = MRFrameReport(
        frameID: frameReportCounter,
        preprocessingTimeCPU: preprocessingEnd - preprocessingStart,
        copyingTime: 0,
        preprocessingTimeGPU: 0,
        geometryTime: 0,
        renderTime: 0)
      frameReports.append(report)
      return output
    }
    if reportPerformance, any(performance .> 0) {
      print("", terminator: " ")
      
      for laneID in 0..<5 {
        // Pad the integer to a common width.
        var repr = "\(Int(performance[laneID] * 1e6))"
        while repr.count < 6 {
          repr = " " + repr
        }
        
        // Print the integer and column separator.
        if laneID == 5 - 1 {
          print(repr, terminator: "\n")
        } else {
          print(repr, terminator: " | ")
        }
      }
    }
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    
    // Clear the global atomic counters.
    do {
      encoder.setComputePipelineState(memsetPipeline)
      encoder.setBuffer(globalAtomicCounters, offset: 0, index: 0)
      encoder.dispatchThreads(
        MTLSizeMake(8, 1, 1),
        threadsPerThreadgroup: MTLSizeMake(128, 1, 1))
    }
    
    // Clear the small cell metadata.
    do {
      let totalCells = 64
      * Int(worldDimensions[0])
      * Int(worldDimensions[1])
      * Int(worldDimensions[2])
      
      encoder.setComputePipelineState(memsetPipeline)
      encoder.setBuffer(smallCellMetadata, offset: 0, index: 0)
      encoder.dispatchThreadgroups(
        MTLSizeMake((totalCells + 255) / 256, 1, 1),
        threadsPerThreadgroup: MTLSizeMake(256, 1, 1))
    }
    
    // Bind the uniform grid arguments.
    do {
      struct UniformGridArguments {
        var worldMinimum: SIMD3<Float>
        var worldMaximum: SIMD3<Float>
        var smallVoxelCount: SIMD3<Int16>
      }
      
      let smallVoxelCount = 4 &* worldDimensions
      var arguments: UniformGridArguments = .init(
        worldMinimum: SIMD3(worldOrigin),
        worldMaximum: SIMD3(worldOrigin &+ worldDimensions),
        smallVoxelCount: smallVoxelCount)
      let argumentsStride = MemoryLayout<UniformGridArguments>.stride
      encoder.setBytes(&arguments, length: argumentsStride, index: 0)
    }
    
    let tripleIndex = renderer.argumentContainer.tripleBufferIndex()
    encoder.setBuffer(smallCellMetadata, offset: 0, index: 3)
    encoder.setBuffer(smallCellCounters, offset: 0, index: 4)
    encoder.setBuffer(globalAtomicCounters, offset: tripleIndex * 4, index: 5)
    encoder.setBuffer(smallCellAtomReferences, offset: 0, index: 6)
    encoder.setBuffer(globalAtomicCounters, offset: tripleIndex * 4 + 16, index: 7)
    encoder.setBuffer(convertedAtomsBuffer, offset: 0, index: 10)
    
    // Encode the first pass.
    encoder.setComputePipelineState(densePass1Pipeline)
    encoder.dispatchThreads(
      MTLSizeMake(atoms.count, 1, 1),
      threadsPerThreadgroup: MTLSizeMake(128, 1, 1))
    
    // Encode the second pass.
    do {
      let totalCells = 64
      * Int(worldDimensions[0])
      * Int(worldDimensions[1])
      * Int(worldDimensions[2])
      
      encoder.setComputePipelineState(densePass2Pipeline)
      encoder.dispatchThreadgroups(
        MTLSizeMake((totalCells + 127) / 128, 1, 1),
        threadsPerThreadgroup: MTLSizeMake(128, 1, 1))
    }
    
    // Encode the third pass.
    encoder.setComputePipelineState(densePass3Pipeline)
    encoder.dispatchThreads(
      MTLSizeMake(atoms.count, 1, 1),
      threadsPerThreadgroup: MTLSizeMake(128, 1, 1))
    
    encoder.endEncoding()
    commandBuffer.addCompletedHandler { [self] commandBuffer in
      let executionTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
      self.frameReportQueue.sync {
        for index in self.frameReports.indices.reversed() {
          guard self.frameReports[index].frameID == frameID else {
            continue
          }
          self.frameReports[index].geometryTime = executionTime
          break
        }
      }
    }
    commandBuffer.commit()
  }
}
