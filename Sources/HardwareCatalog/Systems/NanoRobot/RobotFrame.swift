//
//  RobotFrame.swift
//  MolecularRendererApp
//
//  Created by Philip Turner on 1/11/24.
//

import HDL
import MM4

struct RobotFrame {
  var grippers: [RobotGripper]
  var centerPiece: RobotCenterPiece
  
  var animationFrames: [[Entity]] = []
  
  init() {
    let robotGripper1 = RobotGripper()
    grippers = [robotGripper1, robotGripper1]
    grippers[1].rigidBody!.centerOfMass.x += 2.6
    grippers[1].rigidBody!.rotate(angle: .pi, axis: [0, 1, 0])
    
    centerPiece = RobotCenterPiece()
    for i in centerPiece.topology.atoms.indices {
      centerPiece.topology.atoms[i].position += SIMD3(1.5, 2.1, -0.6)
    }
    
    displayGripperConstruction()
    for _ in 0..<30 {
      displayStartFrame()
    }
    
    // Simulate the gripper joining.
    simulateGripperJoining()
//    displayJoinedFrame()
    
    displayCenterPieceConstruction()
    simulateCenterPieceStability()
    simulateGrippingMotion(directionIn: false)
  }
  
  mutating func displayGripperConstruction() {
    var frame: [Entity] = []
    for gripper in grippers {
      let rigidBody = gripper.rigidBody!
      let topology = gripper.topology
      for i in topology.atoms.indices {
        var entity = topology.atoms[i]
        entity.position = rigidBody.positions[i]
        frame.append(entity)
      }
    }
    for i in 0..<90 {
      let proportion = Float(i) / Float(90)
      let range = 0..<max(1, Int(proportion * Float(frame.count)))
      animationFrames.append(Array(frame[range]))
    }
  }
  
  mutating func displayStartFrame() {
    var frame: [Entity] = []
    for gripper in grippers {
      let rigidBody = gripper.rigidBody!
      let topology = gripper.topology
      for i in topology.atoms.indices {
        var entity = topology.atoms[i]
        entity.position = rigidBody.positions[i]
        frame.append(entity)
      }
    }
    animationFrames.append(frame)
  }
  
  // Reconstructs the grippers' rigid bodies so they're in the position we want.
  mutating func displayJoinedFrame() {
    var frame: [Entity] = []
    for gripperID in grippers.indices {
      let gripper = grippers[gripperID]
      var rigidBody = gripper.rigidBody!
      let shift = (gripperID == 0) ? Double(0.18) : Double(-0.18)
      rigidBody.centerOfMass.x += shift
      
      let topology = gripper.topology
      for i in topology.atoms.indices {
        var entity = topology.atoms[i]
        entity.position = rigidBody.positions[i]
        frame.append(entity)
      }
      grippers[gripperID].rigidBody = rigidBody
    }
    animationFrames.append(frame)
  }
  
  
  // To show this, you must already have a frame that displays the grippers in
  // their joined position.
  mutating func displayCenterPieceConstruction() {
    let frameGrippers = animationFrames.last!
    
    var frameCenterPiece: [Entity] = []
    do {
      let topology = centerPiece.topology
      for i in topology.atoms.indices {
        let entity = topology.atoms[i]
        frameCenterPiece.append(entity)
      }
    }
    
    for i in 0..<60 {
      let proportion = Float(i) / Float(60)
      let range = 0..<max(1, Int(proportion * Float(frameCenterPiece.count)))
      animationFrames.append(frameGrippers + Array(frameCenterPiece[range]))
    }
  }
  
  // Reconstructs the grippers' rigid bodies so they're in the position we want.
  mutating func simulateGripperJoining() {
    var sceneParameters: MM4Parameters?
    for gripper in grippers {
      let parameters = gripper.rigidBody!.parameters
      if sceneParameters == nil {
        sceneParameters = parameters
      } else {
        sceneParameters!.append(contentsOf: parameters)
      }
    }
    
    var forceFieldDesc = MM4ForceFieldDescriptor()
    forceFieldDesc.parameters = sceneParameters
    let forceField = try! MM4ForceField(descriptor: forceFieldDesc)
    var initialPositions: [SIMD3<Float>] = []
    for gripper in grippers {
      initialPositions += gripper.rigidBody!.positions
    }
    forceField.positions = initialPositions
    
    print("frame=0")
    for frameID in 0...70 {
      if frameID % 10 == .zero {
        forceField.velocities = Array(repeating: .zero, count: forceField.positions.count)
      }
      
      let step: Double = 0.200
      forceField.simulate(time: step)
      if frameID == 70 {
        forceField.minimize()
      }
      print("frame=\(frameID), time=\(String(format: "%.3f", Double(frameID) * step))")
      
      var cursor: Int = 0
      var frame: [Entity] = []
      for gripperID in grippers.indices {
        let gripper = grippers[gripperID]
        let topology = gripper.topology
        let range = cursor..<cursor + topology.atoms.count
        let positions = Array(forceField.positions[range])
        for i in topology.atoms.indices {
          var entity = topology.atoms[i]
          entity.position = positions[i]
          frame.append(entity)
        }
        cursor = range.endIndex
        
        if frameID == 70 {
          var rigidBodyDesc = MM4RigidBodyDescriptor()
          rigidBodyDesc.parameters = grippers[gripperID].rigidBody!.parameters
          rigidBodyDesc.positions = positions
          let rigidBody = try! MM4RigidBody(descriptor: rigidBodyDesc)
          grippers[gripperID].rigidBody = rigidBody
        }
      }
      animationFrames.append(frame)
    }
  }
  
  mutating func simulateCenterPieceStability() {
    var sceneParameters: MM4Parameters?
    for gripper in grippers {
      let parameters = gripper.rigidBody!.parameters
      if sceneParameters == nil {
        sceneParameters = parameters
      } else {
        sceneParameters!.append(contentsOf: parameters)
      }
    }
    sceneParameters!.append(contentsOf: centerPiece.parameters!)
    
    var forceFieldDesc = MM4ForceFieldDescriptor()
    forceFieldDesc.parameters = sceneParameters
    let forceField = try! MM4ForceField(descriptor: forceFieldDesc)
    var initialPositions: [SIMD3<Float>] = []
    for gripper in grippers {
      initialPositions += gripper.rigidBody!.positions
    }
    initialPositions += centerPiece.topology.atoms.map(\.position)
    forceField.positions = initialPositions
    forceField.minimize()
    
    print("frame=0")
    for frameID in 0...70 {
      if frameID % 10 == .zero {
        forceField.velocities = Array(repeating: .zero, count: forceField.positions.count)
      }
      
      let step: Double = 0.020
      forceField.simulate(time: step)
      if frameID == 70 {
        forceField.minimize()
      }
      print("frame=\(frameID), time=\(String(format: "%.3f", Double(frameID) * step))")
      
      var cursor: Int = 0
      var frame: [Entity] = []
      for gripperID in grippers.indices {
        let gripper = grippers[gripperID]
        let topology = gripper.topology
        let range = cursor..<cursor + topology.atoms.count
        let positions = Array(forceField.positions[range])
        for i in topology.atoms.indices {
          var entity = topology.atoms[i]
          entity.position = positions[i]
          frame.append(entity)
        }
        cursor = range.endIndex
        
        if frameID == 70 {
          print("HELLO WORLDLDLLELDEL")
          var rigidBodyDesc = MM4RigidBodyDescriptor()
          rigidBodyDesc.parameters = grippers[gripperID].rigidBody!.parameters
          rigidBodyDesc.positions = positions
          let rigidBody = try! MM4RigidBody(descriptor: rigidBodyDesc)
          grippers[gripperID].rigidBody = rigidBody
        }
      }
      do {
        let topology = centerPiece.topology
        let range = cursor..<cursor + topology.atoms.count
        let positions = Array(forceField.positions[range])
        for i in topology.atoms.indices {
          var entity = topology.atoms[i]
          entity.position = positions[i]
          if frameID == 70 {
            centerPiece.topology.atoms[i].position = entity.position
          }
          frame.append(entity)
        }
        cursor = range.endIndex
      }
      animationFrames.append(frame)
    }
  }
  
  mutating func simulateGrippingMotion(directionIn: Bool) {
    var centerPieceMinX: Float = .greatestFiniteMagnitude
    var centerPieceMaxX: Float = -.greatestFiniteMagnitude
    for atom in centerPiece.topology.atoms {
      let x = atom.position.x
      centerPieceMaxX = max(centerPieceMaxX, x)
      centerPieceMinX = min(centerPieceMinX, x)
    }
    
    var sceneParameters: MM4Parameters?
    for gripper in grippers {
      var parameters = gripper.rigidBody!.parameters
      for i in parameters.atoms.indices {
        if parameters.atoms.masses[i] == 0 {
          parameters.atoms.masses[i] = 12.011 * Float(MM4YgPerAmu)
        }
      }
      if sceneParameters == nil {
        sceneParameters = parameters
      } else {
        sceneParameters!.append(contentsOf: parameters)
      }
    }
    sceneParameters!.append(contentsOf: centerPiece.parameters!)
    
    var forceFieldDesc = MM4ForceFieldDescriptor()
    forceFieldDesc.parameters = sceneParameters
    let forceField = try! MM4ForceField(descriptor: forceFieldDesc)
    var initialPositions: [SIMD3<Float>] = []
    for gripper in grippers {
      initialPositions += gripper.rigidBody!.positions
    }
    initialPositions += centerPiece.topology.atoms.map(\.position)
    forceField.positions = initialPositions
    
    var externalForces: [SIMD3<Float>] = []
    var velocities: [SIMD3<Float>] = []
    for gripper in grippers {
      for position in gripper.rigidBody!.positions {
        if position.x > centerPieceMinX && position.x < centerPieceMaxX {
          externalForces.append(SIMD3(0, directionIn ? +1 : -1, 0))
          velocities.append(SIMD3(0, 0, 0))
        } else {
          externalForces.append(SIMD3(0, directionIn ? -1 : 1, 0))
          velocities.append(SIMD3(0, 0, 0))
        }
      }
    }
    for _ in centerPiece.topology.atoms.indices {
      externalForces.append(SIMD3(0, 0, 0))
      velocities.append(SIMD3(0, 0, 0))
    }
    forceField.externalForces = externalForces
    forceField.velocities = velocities
    
    print("frame=0")
    for frameID in 0...70 {
      // Add a thermostat to all atoms with X inside the desired range.
      if frameID % 10 == 0 {
        var newVelocities = forceField.velocities
        for i in forceField.positions.indices {
          let position = forceField.positions[i]
          if position.x > centerPieceMinX && position.x < centerPieceMaxX {
            newVelocities[i] = .zero
          }
        }
        forceField.velocities = newVelocities
      }
      
      // NOTE: Never minimize when there are external forces!
      let step: Double = 0.200
      forceField.simulate(time: step)
      print("frame=\(frameID), time=\(String(format: "%.3f", Double(frameID) * step))")
      
      var cursor: Int = 0
      var frame: [Entity] = []
      for gripperID in grippers.indices {
        let gripper = grippers[gripperID]
        let topology = gripper.topology
        let range = cursor..<cursor + topology.atoms.count
        let positions = Array(forceField.positions[range])
        for i in topology.atoms.indices {
          var entity = topology.atoms[i]
          entity.position = positions[i]
          frame.append(entity)
        }
        cursor = range.endIndex
        
        if frameID == 70 {
          var rigidBodyDesc = MM4RigidBodyDescriptor()
          rigidBodyDesc.parameters = grippers[gripperID].rigidBody!.parameters
          rigidBodyDesc.positions = positions
          let rigidBody = try! MM4RigidBody(descriptor: rigidBodyDesc)
          grippers[gripperID].rigidBody = rigidBody
        }
      }
      do {
        let topology = centerPiece.topology
        let range = cursor..<cursor + topology.atoms.count
        let positions = Array(forceField.positions[range])
        for i in topology.atoms.indices {
          var entity = topology.atoms[i]
          entity.position = positions[i]
          if frameID == 70 {
            centerPiece.topology.atoms[i].position = entity.position
          }
          frame.append(entity)
        }
        cursor = range.endIndex
      }
      animationFrames.append(frame)
    }
  }
}
