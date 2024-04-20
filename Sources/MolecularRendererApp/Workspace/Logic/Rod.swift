//
//  Rod.swift
//  MolecularRendererApp
//
//  Created by Philip Turner on 4/19/24.
//

import Foundation
import HDL
import MM4
import Numerics

struct Rod: GenericPart {
  var rigidBody: MM4RigidBody
  var boundingBox: (
    minimum: SIMD3<Double>,
    maximum: SIMD3<Double>)
  
  init(lattice: Lattice<Hexagonal>) {
    let topology = Self.createTopology(lattice: lattice)
    rigidBody = Self.createRigidBody(topology: topology)
    
    // y: [0, 2.4840] -> [2.8830, 5.3670]
    // z: [0, 1.8976] -> [3.0512, 4.9488]
    rigidBody.centerOfMass += SIMD3(0, 2.8830, 3.0512) * 0.3567
    boundingBox = (
      SIMD3(-1, 2.8830, 3.0512),
      SIMD3(1, 5.3670, 4.9488))
  }
  
  static func createTopology(lattice: Lattice<Hexagonal>) -> Topology {
    var reconstruction = SurfaceReconstruction()
    reconstruction.material = .elemental(.carbon)
    reconstruction.topology.insert(atoms: lattice.atoms)
    reconstruction.compile()
    
    var topology = reconstruction.topology
    let atomsToAtomsMap = topology.map(.atoms, to: .atoms)
    
    var removedAtoms: [UInt32] = []
    for i in topology.atoms.indices {
      let atom = topology.atoms[i]
      guard atom.atomicNumber == 1 else {
        continue
      }
      for j in atomsToAtomsMap[i] {
        let other = topology.atoms[Int(j)]
        if other.atomicNumber == 15 {
          removedAtoms.append(UInt32(i))
        }
        if other.atomicNumber == 16 {
          removedAtoms.append(UInt32(i))
        }
      }
    }
    topology.remove(atoms: removedAtoms)
    topology.sort()
    return topology
  }
  
  func createHolePattern() -> HolePattern {
    var minCarbonPosition = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var maxCarbonPosition = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    for atomID in rigidBody.parameters.atoms.indices {
      let atomicNumber = rigidBody.parameters.atoms.atomicNumbers[atomID]
      let position = rigidBody.positions[atomID]
      guard atomicNumber == 6 else {
        continue
      }
      
      minCarbonPosition
        .replace(with: position, where: position .< minCarbonPosition)
      maxCarbonPosition
        .replace(with: position, where: position .> maxCarbonPosition)
    }
    minCarbonPosition /= 0.3567
    maxCarbonPosition /= 0.3567
    minCarbonPosition -= SIMD3(1, 1, 1)
    maxCarbonPosition += SIMD3(1, 1, 1)
    
    return { h, k, l in
      Concave {
        Concave {
          Origin {
            Float(minCarbonPosition[0]) * h +
            Float(minCarbonPosition[1]) * k +
            Float(minCarbonPosition[2]) * l
          }
          Plane { h }
          Plane { k }
          Plane { l }
        }
        
        Concave {
          Origin {
            Float(maxCarbonPosition[0]) * h +
            Float(maxCarbonPosition[1]) * k +
            Float(maxCarbonPosition[2]) * l
          }
          Plane { -h }
          Plane { -k }
          Plane { -l }
        }
      }
      Replace { .empty }
    }
  }
  
  mutating func rotate(angle: Double, axis: SIMD3<Double>) {
    rigidBody.rotate(angle: angle, axis: axis)
    print(boundingBox)
    print(angle / .pi, axis)
    let rotation = Quaternion<Double>(angle: angle, axis: axis)
    rigidBody.centerOfMass = rotation.act(on: rigidBody.centerOfMass)
    boundingBox = (
      rotation.act(on: boundingBox.minimum),
      rotation.act(on: boundingBox.maximum))
    print(boundingBox)
    print()
    
    for laneID in 0..<3 {
      var lowerBound = boundingBox.minimum[laneID]
      var upperBound = boundingBox.maximum[laneID]
      guard lowerBound > upperBound else {
        continue
      }
      let delta = upperBound - lowerBound
      if (delta.magnitude - 2).magnitude < 0.001 {
        fatalError("Attempted to flip the length dimension.")
      }
      
      print("lane:", laneID)
      print(lowerBound, upperBound)
      swap(&lowerBound, &upperBound)
      let projectedLowerBound = -lowerBound
      let translation = projectedLowerBound - upperBound
      lowerBound += translation
      upperBound += translation
      print(lowerBound, upperBound)
      
      rigidBody.centerOfMass[laneID] += translation * 0.3567
      boundingBox.minimum[laneID] = lowerBound
      boundingBox.maximum[laneID] = upperBound
    }
    
//    exit(0)
  }
  
  // TODO: Functions for 'translate(x:)', y, z instead of operating directly on
  // the rigid body. Also removes the need to multiply by 0.3567 in source code.
}
