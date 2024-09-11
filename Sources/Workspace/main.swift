// swift package init --type executable
// Copy the following code into 'main.swift'.
// Change the platforms to '[.macOS(.v14)]' in the package manifest.
// swift run -Xswiftc -Ounchecked

// https://www.polpiella.dev/launching-a-swiftui-view-from-the-terminal

// Next steps:
// - Copying the code. [DONE]
//    - Save the code to a GitHub gist for reference.
//    - Make a cleaned molecular-renderer branch.
//    - Copy the above code into the branch.
//    - Test the code.
//    - Commit the files to Git.
// - Access the GPU.
//   - Modify it to get Metal rendering. [DONE]
//   - Clean up and simplify the code as much as possible.
//   - Get timestamps synchronizing properly (moving rainbow banner
//     scene).
// - Repeat the same process with COM / D3D12 on Windows.
//   - Another single-file Swift script that does the same thing.

import AppKit

struct Screen {
  static var desired: NSScreen {
    let screens = NSScreen.screens
    let fastest = screens.max(by: {
      $0.maximumFramesPerSecond < $1.maximumFramesPerSecond
    })!
    return fastest
  }
  
  static var renderTargetSize: Int {
    1920
  }
  
  static var backingScaleFactor: Float {
    var scaleFactors: [Float] = []
    for screen in NSScreen.screens {
      let scaleFactor = screen.backingScaleFactor
      scaleFactors.append(Float(scaleFactor))
    }
    
    if scaleFactors.count > 1 {
      let allAreEqual = scaleFactors.allSatisfy { scaleFactor in
        let expected = scaleFactors[0]
        return scaleFactor == expected
      }
      guard allAreEqual else {
        fatalError("Scale factors were not consistent across displays.")
      }
    }
    return scaleFactors[0]
  }
}

class Renderer {
  var device: MTLDevice
  var commandQueue: MTLCommandQueue
  var computePipelineState: MTLComputePipelineState
  var frameID: Int = .zero
  
  init() {
    device = MTLCreateSystemDefaultDevice()!
    commandQueue = device.makeCommandQueue()!
    computePipelineState = Renderer
      .createComputePipelineState(device: device)
  }
  
  func render(layer: CAMetalLayer) {
    frameID += 1
    
    let drawable = layer.nextDrawable()
    guard let drawable else {
      fatalError("Drawable timed out after 1 second.")
    }
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(computePipelineState)
    encoder.setBytes(&frameID, length: 4, index: 0)
    encoder.setTexture(drawable.texture, index: 0)
    
    let dispatchSize = Screen.renderTargetSize
    encoder.dispatchThreads(
      MTLSize(width: dispatchSize, height: dispatchSize, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}

extension Renderer {
  static func createSource() -> String {
    """
    
    #include <metal_stdlib>
    using namespace metal;
    
    kernel void renderImage(
      constant uint *frameID [[buffer(0)]],
      texture2d<half, access::write> drawableTexture [[texture(0)]],
      ushort2 tid [[thread_position_in_grid]]
    ) {
      half4 color;
      if (tid.x == tid.y || tid.x == 1920 - tid.y) {
        color = half4(0.00, 0.00, 0.00, 1.00);
      } else {
        uint frameModulo = *frameID % 120;
        half frameNormalized = half(frameModulo) / 120;
        color = half4(frameNormalized, 0.00, 0.00, 1.00);
      }
    
      drawableTexture.write(color, tid);
    }
    
    """
  }
  
  static func createComputePipelineState(
    device: MTLDevice
  ) -> MTLComputePipelineState {
    let shaderSource = Renderer.createSource()
    let library = try! device.makeLibrary(source: shaderSource, options: nil)
    
    let function = library.makeFunction(name: "renderImage")
    guard let function else {
      fatalError("Could not make function.")
    }
    let pipeline = try! device.makeComputePipelineState(function: function)
    return pipeline
  }
}

class RendererView: NSView, CALayerDelegate {
  var displayLink: CVDisplayLink!
  var metalLayer: CAMetalLayer!
  var delegate: RendererViewController!
  
  required init(coder: NSCoder) {
    fatalError("Not implemented.")
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    self.layerContentsRedrawPolicy = .duringViewResize
    self.wantsLayer = true
    metalLayer = self.layer! as? CAMetalLayer
    
    let renderTargetSize = Float(Screen.renderTargetSize)
    let windowSize = renderTargetSize / Screen.backingScaleFactor
    metalLayer.drawableSize = CGSize(
      width: Double(renderTargetSize),
      height: Double(renderTargetSize))
    
    metalLayer.delegate = self
    self.bounds.size = CGSize(
      width: Double(windowSize),
      height: Double(windowSize))
    self.frame.size = CGSize(
      width: Double(windowSize),
      height: Double(windowSize))
    
    metalLayer.device = MTLCreateSystemDefaultDevice()!
    metalLayer.framebufferOnly = false
    metalLayer.pixelFormat = .rgb10a2Unorm
  }
  
  override func makeBackingLayer() -> CALayer {
    let layer = CAMetalLayer()
    return layer
  }
  
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    CVDisplayLinkSetOutputHandler(displayLink) {
      [self]
      displayLink,
      now,
      outputTime,
      flagsIn,
      flagsOut in
      
      self.render()
      return kCVReturnSuccess
    }
    
    let screen = Screen.desired
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    let screenNumberAny = screen.deviceDescription[key]!
    let screenNumber = screenNumberAny as! NSNumber
    CVDisplayLinkSetCurrentCGDisplay(displayLink, screenNumber.uint32Value)
    CVDisplayLinkStart(displayLink)
  }
  
  func render() {
    
  }
}

extension RendererView {
  func checkDrawableSize(_ newSize: NSSize) {
    var expectedSize = Float(Screen.renderTargetSize)
    expectedSize /= Screen.backingScaleFactor
    print("Checking drawable size \(newSize) against \(expectedSize).")
    
    let width = Float(newSize.width)
    let height = Float(newSize.height)
    guard width == expectedSize,
          height == expectedSize else {
      fatalError("Not allowed to resize window.")
    }
  }
  
  override func setBoundsSize(_ newSize: NSSize) {
    super.setBoundsSize(newSize)
    checkDrawableSize(newSize)
  }
  
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    checkDrawableSize(newSize)
  }
}

class RendererViewController: NSViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    
    let view = RendererView()
    self.view = view
    view.delegate = self
  }
}

class EventResponder: NSResponder {
  
}
