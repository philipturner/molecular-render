//
//  Renderer.swift
//  MolecularRenderer
//
//  Created by Philip Turner on 2/22/23.
//

import Foundation
import MolecularRenderer
import QuartzCore

class Renderer {
  unowned let coordinator: Coordinator
  unowned let eventTracker: EventTracker
  
  // Rendering resources.
  var renderSemaphore: DispatchSemaphore = .init(value: 3)
  var renderingEngine: MRRenderer!
  var animationFrameID: Int = 0
  
  // Data serializers.
  var gifSerializer: GIFSerializer!
  var serializer: Serializer!
  
  init(coordinator: Coordinator) {
    self.coordinator = coordinator
    self.eventTracker = coordinator.eventTracker
    initializeExternalLibraries()
    
    let start = CACurrentMediaTime()
    let animation = createLonsdaleiteSimulation()
    let end = CACurrentMediaTime()
    print("atoms:", animation.frames.first!.count)
    print("compile time:", String(format: "%.1f", (end - start) * 1e3), "ms")
    self.renderingEngine.setAtomProvider(animation)
  }
}
