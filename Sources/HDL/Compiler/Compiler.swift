//
//  Compiler.swift
//  MolecularRendererApp
//
//  Created by Philip Turner on 8/28/23.
//

import QuaternionModule

// MARK: - Environment Objects

public class Compiler {
  static let global: Compiler = Compiler()
  
  // For editing a lattice.
  private var stack: Stack?
  private var willUseLattice: Bool = false
  private var didSetMaterial: Bool = false
  
  // For combining multiple lattices or solids into a solid.
  // TODO: Encapsulate all these variables in another object for solids.
  private var solidStack: SolidStack?
  private var willUseSolid: Bool = false
  private var didSetAffine: Bool = false
  
  init() {
    // Resets the scene after the popping the stack of the outermost
    // 'Solid' scope.
  }
  
  /// Unstable API; do not use this function.
  public func _makeKeyFrames() {
    // Return key frames for animating the geometry compilation.
    // TODO: Method to track keyframes across the different objects. They only
    // track operations performed, not the evolution of the objects' data.
  }
}

extension Compiler {
  func reset() {
    stack = nil
    willUseLattice = false
    didSetMaterial = false
    
    solidStack = nil
    willUseSolid = false
    didSetAffine = false
  }
  
  func assertReset() {
    precondition(stack == nil)
    precondition(willUseLattice == false)
    precondition(didSetMaterial == false)
    
    precondition(solidStack == nil)
    precondition(willUseSolid == false)
    precondition(didSetAffine == false)
  }
  
  func moveOrigin(_ delta: SIMD3<Float>) {
    if willUseLattice {
      assertBoundsSet()
      stack!.applyOrigin(delta: delta)
    } else if willUseSolid {
      assertSolid()
      solidStack!.applyOrigin(delta: delta)
    } else {
      fatalError()
    }
  }
}

extension Compiler {
  private func assertLattice() {
    precondition(willUseLattice && !willUseSolid)
  }
  
  private func assertBoundsSet() {
    assertLattice()
    precondition(didSetMaterial)
    precondition(stack != nil)
  }
  
  func startLattice<T: Basis>(type: T.Type) {
    precondition(T.self == Cubic.self, "Unsupported basis.")
    assertReset()
    willUseLattice = true
  }
  
  func endLattice<T: Basis>(type: T.Type) -> [SIMD3<Float>] {
    precondition(T.self == Cubic.self, "Unsupported basis.")
    assertLattice()
    defer { reset() }
    
    if let stack {
      return stack.result.makeCenters()
    } else {
      return []
    }
  }
  
  func setMaterial(_ elements: [Element]) {
    assertLattice()
    precondition(didSetMaterial == false)
    precondition(elements == [.carbon])
  }
  
  func setBounds(_ bounds: SIMD3<Int32>) {
    assertLattice()
    precondition(didSetMaterial)
    precondition(stack == nil)
    
    // For now, require the bounds to be greater than zero. Eventually, we may
    // permit bounds below zero that just shift the origin (or use a shifted
    // origin, but the bounds are positive, etc).
    precondition(all(bounds .> 0))
    stack = Stack(dimensions: bounds)
  }
  
  func startVolume() {
    assertBoundsSet()
  }
  
  func endVolume() {
    assertBoundsSet()
  }
}

extension Compiler {
  private func assertSolid() {
    precondition(willUseSolid && !willUseLattice)
  }
  
  private func assertAffine() {
    assertSolid()
    precondition(didSetAffine)
  }
  
  func startSolid() {
    assertReset()
  }
  
  func endSolid() -> [SIMD3<Float>] {
    assertSolid()
    defer { reset() }
    
    if let solidStack {
      return solidStack.centers
    } else {
      return []
    }
  }
  
  func startAffine() {
    assertSolid()
    precondition(!didSetAffine)
  }
  
  func endAffine() {
    assertAffine()
  }
  
  func startCopy() {
    assertSolid()
  }
  
  func endCopy() {
    assertSolid()
  }
}
