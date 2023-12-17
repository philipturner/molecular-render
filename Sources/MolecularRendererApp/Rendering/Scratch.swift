// Save as GitHub Gist instead of polluting the molecular-renderer source tree.

import Foundation
import HDL
import MolecularRenderer
import Numerics

func createNanomachinery() -> [MRAtom] {
  // The entire assembly can be roughly put together, even while many
  // important pieces are missing. This should be done to get a rough
  // estimate of the atom count and final geometry.
  //
  // missing pieces:
  // - level 1:
  //   - small manufactured pieces (gold atoms)
  //
  // - level 2:
  //   - recycle the "roof piece" with some slight modifications
  //   - rod that links controls for 3 assembly lines in SIMD fashion
  //   - leave some space near the rods, to visualize the adjacent quadrant
  //   - larger manufactured pieces (gold atoms)
  //
  // - level 3:
  //   - hexagonal centerpiece at the 3rd level of convergent assembly
  //   - mystery - what is the feature here? large multi-DOF manipulator?
  //     computer? decide when the time comes.
  
  let masterQuadrant = Quadrant()
  var quadrants: [Quadrant] = []
  quadrants.append(masterQuadrant)
  
  for i in 1..<4 {
    let angle = Float(i) * -90 * .pi / 180
    let quaternion = Quaternion<Float>(angle: angle, axis: [0, 1, 0])
    let basisX = quaternion.act(on: [1, 0, 0])
    let basisY = quaternion.act(on: [0, 1, 0])
    let basisZ = quaternion.act(on: [0, 0, 1])
    quadrants.append(masterQuadrant)
    quadrants[i].transform {
      var origin = $0.origin.x * basisX
      origin.addProduct($0.origin.y, basisY)
      origin.addProduct($0.origin.z, basisZ)
      $0.origin = origin
    }
  }
  
  return quadrants.flatMap { $0.createAtoms() }
}
