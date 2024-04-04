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
  var renderSemaphore: DispatchSemaphore = .init(value: 3)
  var renderingEngine: MRRenderer!
  var animationFrameID: Int = 0
  
  init(coordinator: Coordinator) {
    self.coordinator = coordinator
    self.eventTracker = coordinator.eventTracker
    initializeExternalLibraries()
//    initializeCompilation {
//      createGeometry()
//    }
    renderOffline(renderingEngine: renderingEngine)
  }
}

extension Renderer {
  func update() {
    self.renderSemaphore.wait()
    
    let frameDelta = coordinator.vsyncHandler.updateFrameID()
    let frameID = coordinator.vsyncHandler.frameID
    eventTracker.update(time: MRTime(
      absolute: frameID,
      relative: frameDelta,
      frameRate: ContentView.frameRate))
    
    var animationDelta: Int
    if eventTracker[.keyboardP].pressed {
      animationDelta = frameDelta
    } else {
      animationDelta = 0
    }
    if eventTracker[.keyboardR].pressed {
      animationDelta = 0
      animationFrameID = 0
    }
    animationFrameID += animationDelta
    
    let playerState = eventTracker.playerState
    let fov = playerState.fovDegrees(progress: eventTracker.fovHistory.progress)
    let (azimuth, zenith) = playerState.orientations
    let rotation = PlayerState.rotation(azimuth: azimuth, zenith: zenith)
    
    renderingEngine.setTime(MRTime(
      absolute: animationFrameID,
      relative: animationDelta,
      frameRate: ContentView.frameRate))
    
    renderingEngine.setCamera(MRCamera(
      position: playerState.position,
      rotation: rotation,
      fovDegrees: fov))
    
    renderingEngine.setLights([
      MRLight(
        origin: playerState.position,
        diffusePower: 1, specularPower: 1)
    ])
    
    renderingEngine.render(layer: coordinator.view.metalLayer!) {
      self.renderSemaphore.signal()
    }
  }
}
