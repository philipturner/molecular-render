//
//  OutputUnit.swift
//  MolecularRendererApp
//
//  Created by Philip Turner on 3/24/24.
//

import Foundation
import HDL
import MM4
import Numerics

struct OutputUnit {
  // The carry bits for the final computation.
  //
  // Ordered from bit 0 -> bit 3.
  var carry: [Rod] = []
  
  var rods: [Rod] {
    carry
  }
  
  init() {
    for layerID in 1...4 {
      let y = 6 * Float(layerID)
      
      // Create 'carry'.
      do {
        let offset = SIMD3(41, y + 0, 0)
        let rod = OutputUnit.createRodZ(offset: offset)
        carry.append(rod)
      }
    }
  }
}

extension OutputUnit {
  private static func createRodZ(offset: SIMD3<Float>) -> Rod {
    let rodLatticeZ = Lattice<Hexagonal> { h, k, l in
      let h2k = h + 2 * k
      Bounds { 50 * h + 2 * h2k + 2 * l }
      Material { .elemental(.carbon) }
    }
    
    let atoms = rodLatticeZ.atoms.map {
      var copy = $0
      var position = copy.position
      let latticeConstant = Constant(.square) { .elemental(.carbon) }
      position = SIMD3(position.z, position.y, position.x)
      position += SIMD3(0.91, 0.85, 0)
      position += offset * latticeConstant
      copy.position = position
      return copy
    }
    return Rod(atoms: atoms)
  }
}
