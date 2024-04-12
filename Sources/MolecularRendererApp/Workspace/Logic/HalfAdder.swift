//
//  HalfAdder.swift
//  MolecularRendererApp
//
//  Created by Philip Turner on 4/11/24.
//

import Foundation
import HDL
import MM4
import Numerics

struct HalfAdder {
  var unit: HalfAdderUnit
  var housing: LogicHousing
  var inputDriveWall: DriveWall
  var outputDriveWall: DriveWall
  var intermediateDriveWall: DriveWall
  
  var rigidBodies: [MM4RigidBody] {
    var output: [MM4RigidBody] = []
    output.append(contentsOf: unit.rods.map(\.rigidBody))
    output += [
      housing.rigidBody,
      inputDriveWall.rigidBody,
      outputDriveWall.rigidBody,
      intermediateDriveWall.rigidBody,
    ]
    return output
  }
  
  init() {
    unit = HalfAdderUnit()
    
    // Create the housing.
    
    typealias BoundingPattern = (
      SIMD3<Float>, SIMD3<Float>, SIMD3<Float>
    ) -> Void
    
    var boundingPatterns: [BoundingPattern] = []
    boundingPatterns.append { h, k, l in
      Origin { 22.75 * h }
      Plane { h }
      Replace { .empty }
    }
    boundingPatterns.append { h, k, l in
      Origin { 17.75 * k }
      Plane { k }
      Replace { .empty }
    }
    boundingPatterns.append { h, k, l in
      Origin { 14.75 * l }
      Plane { l }
      Replace { .empty }
    }
    
    var housingDesc = LogicHousingDescriptor()
    housingDesc.dimensions = SIMD3(23, 18, 15)
    housingDesc.patterns = unit.holePatterns
    housingDesc.patterns.append(contentsOf: boundingPatterns)
    housing = LogicHousing(descriptor: housingDesc)
    
    // Create the drive walls.
    
    let latticeConstant = Double(Constant(.square) { .elemental(.carbon) })
    
    var driveWallDesc = DriveWallDescriptor()
    driveWallDesc.dimensions = SIMD3(23, 18, 6)
    driveWallDesc.patterns = unit.backRampPatterns
    driveWallDesc.patterns.append(contentsOf: boundingPatterns)
    driveWallDesc.patterns.append { h, k, l in
      Origin { 1 * l }
      Plane { -l }
      Replace { .empty }
    }
    driveWallDesc.patterns.append { h, k, l in
      Origin { 5.5 * l }
      Plane { l }
      Replace { .empty }
    }
    
    driveWallDesc.patterns.append { h, k, l in
      Origin { 14 * h }
      Plane { h }
      Replace { .empty }
    }
    inputDriveWall = DriveWall(descriptor: driveWallDesc)
    inputDriveWall.rigidBody.centerOfMass.z -= (5.5 + 1) * latticeConstant
    
    driveWallDesc.patterns.removeLast()
    driveWallDesc.patterns.append { h, k, l in
      Origin { 15 * h }
      Plane { -h }
      Replace { .empty }
    }
    outputDriveWall = DriveWall(descriptor: driveWallDesc)
    outputDriveWall.rigidBody.centerOfMass.z -= (5.5 + 1) * latticeConstant
    
    driveWallDesc = DriveWallDescriptor()
    driveWallDesc.dimensions = SIMD3(23, 18, 15)
    driveWallDesc.patterns = unit.rightRampPatterns
    driveWallDesc.patterns.append(contentsOf: boundingPatterns)
    driveWallDesc.patterns.append { h, k, l in
      Origin { 16.75 * h }
      Plane { -h }
      Replace { .empty }
    }
    driveWallDesc.patterns.append { h, k, l in
      Origin { 17.25 * h }
      Plane { -h }
      Replace { .empty }
    }
    driveWallDesc.patterns.append { h, k, l in
      Origin { 21.75 * h }
      Plane { h }
      Replace { .empty }
    }
    intermediateDriveWall = DriveWall(descriptor: driveWallDesc)
    intermediateDriveWall
      .rigidBody.centerOfMass.x += (5.5 + 1) * latticeConstant
  }
}
