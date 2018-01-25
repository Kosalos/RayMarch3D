import UIKit
import Metal
import MetalKit

var control = Control()
var vc:ViewController! = nil
var iTerV1:Float = 0
var iTerV2:Float = 0

class ViewController: UIViewController {
    var cBuffer:MTLBuffer! = nil
    
    var timer = Timer()
    var outTexture: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    
    let VIEWSIZE:Int = 500

    let threadGroupCount = MTLSizeMake(20,20, 1)   // integer factor of image size
    lazy var threadGroups: MTLSize = { MTLSizeMake(VIEWSIZE / threadGroupCount.width, VIEWSIZE / threadGroupCount.height, 1) }()
    
    var sList:[SliderView] = []
    var dList:[DeltaView] = []

    @IBOutlet var cameraZ: SliderView!
    @IBOutlet var focusZ: SliderView!
    @IBOutlet var iterMin: SliderView!
    @IBOutlet var iterWidth: SliderView!
    @IBOutlet var zoom: SliderView!
    @IBOutlet var power: SliderView!
    @IBOutlet var cameraXY: DeltaView!
    @IBOutlet var focusXY: DeltaView!
    @IBOutlet var imageViewL: UIImageView!
    @IBOutlet var imageViewR: UIImageView!
    
    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }

    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        do {
            guard let kf1 = defaultLibrary.makeFunction(name: "rayMarchShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        }
        catch { fatalError("error creating pipelines") }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: VIEWSIZE,
            height: VIEWSIZE,
            mipmapped: false)
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!
       
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
    }
    
    let cameraMin:Float = -5
    let cameraMax:Float = 5
    let focusMin:Float = -10
    let focusMax:Float = 10
    let zoomMin:Float = 0.3
    let zoomMax:Float = 30
    let powerMin:Float = 2
    let powerMax:Float = 12

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        sList.append(cameraZ)
        sList.append(focusZ)
        sList.append(iterMin)
        sList.append(iterWidth)
        sList.append(zoom)
        sList.append(power)
        dList.append(cameraXY)
        dList.append(focusXY)

        cameraZ.initializeFloat(&control.cameraZ, .delta, cameraMin, cameraMax, 0.125, "Camera Z")
        focusZ.initializeFloat(&control.focusZ, .delta, focusMin, focusMax, 1, "Focus Z")
        iterMin.initializeInt32(&control.iterMin, .direct, Float(1), Float(10), 10, "Iter Min")
        iterWidth.initializeInt32(&control.iterWidth, .direct, Float(1), Float(40), 10, "Iter Width")
        zoom.initializeFloat(&control.zoom, .delta, zoomMin, zoomMax, 2, "Zoom")
        power.initializeFloat(&control.power, .delta, powerMin, powerMax, 0.25, "Power")
        
        cameraXY.initializeFloat1(&control.cameraX, cameraMin, cameraMax, 0.125, "Camera XY")
        cameraXY.initializeFloat2(&control.cameraY)
        focusXY.initializeFloat1(&control.focusX, focusMin,focusMax, 1, "Focus XY")
        focusXY.initializeFloat2(&control.focusY)

        timer = Timer.scheduledTimer(timeInterval: 1.0/30.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
        reset()
    }
    
    //MARK: -

    func reset() {
        control.focus = vector_float3(0.02,0.11,0.18)
        control.zoom = 2
        control.size = Int32(VIEWSIZE)
        control.bailout = 10
        control.power = 8
        control.iterMin = 3
        control.iterWidth = 5
        control.hop = 0.01
        control.camera = vector_float3(0.0,0.0,-2)
        control.cameraZ = 2;
        control.cameraX = control.camera.x
        control.cameraY = control.camera.y
        control.cameraZ = control.camera.z
        control.focusX = control.focus.x
        control.focusY = control.focus.y
        control.focusZ = control.focus.z

        for s in sList { s.setNeedsDisplay() }
        for d in dList { d.setNeedsDisplay() }

        needsPaint = true
    }
    
    //MARK: -
    
    var angle:Float = 0
    var needsPaint:Bool = false

    @objc func timerHandler() {
        for s in sList { if s.update() { needsPaint = true }}
        
        if cameraXY.update() { needsPaint = true }
        if focusXY.update() { needsPaint = true }
        
//        control.light.x = sinf(angle) * 5
//        control.light.y = sinf(angle/3) * 5
//        control.light.z = -12 + sinf(angle/2) * 5
//        angle += 0.05
//        update()
        
        if needsPaint {
            needsPaint = false
            update()
        }
    }
    
    //MARK: -
    
    func update() {
        queue.async {
            DispatchQueue.main.async {
                self.calcRayMarch(0)
                self.imageViewL.image = self.image(from: self.outTexture)
                self.calcRayMarch(1)
                self.imageViewR.image = self.image(from: self.outTexture)
            }
        }
    }
    
    var startZoom:Float = 0
    
    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {
        if sender.state == .began { startZoom = control.zoom  }        
        control.zoom = fClamp(startZoom / Float(sender.scale),zoomMin,zoomMax)
        zoom.setNeedsDisplay()
        needsPaint = true
    }
    
    //MARK: -

    func calcRayMarch(_ who:Int) {
        control.camera.x = control.cameraX
        control.camera.y = control.cameraY
        control.camera.z = control.cameraZ
        control.focus.x = control.focusX
        control.focus.y = control.focusY
        control.focus.z = control.focusZ
        control.iterMax = control.iterMin + control.iterWidth
        
        let stereo:Float = 0.005
        if who == 0 {
            control.camera.x = control.cameraX + stereo
            cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        }
        else {
            control.camera.x = control.cameraX - stereo
            cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(outTexture, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    //MARK: -
    let bytesPerPixel: Int = 4

    // edit Scheme, Options:  set Metal API Validation to Disabled
    // the fix is to turn off Metal API validation under Product -> Scheme -> Options
    
//    func texture(from image: UIImage) -> MTLTexture {
//        guard let cgImage = image.cgImage else { fatalError("Can't open image \(image)") }
//
//        let textureLoader = MTKTextureLoader(device: self.device)
//        do {
//            let textureOut = try textureLoader.newTexture(cgImage:cgImage)
//            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
//                pixelFormat: .bgra8Unorm_srgb, // textureOut.pixelFormat,
//                width: 2000, //textureOut.width,
//                height: 2000, //textureOut.height,
//                mipmapped: false)
//            let t:MTLTexture = self.device.makeTexture(descriptor: textureDescriptor)!
//            return t // extureOut
//        }
//        catch {
//            fatalError("Can't load texture")
//        }
//    }
    
    func image(from texture: MTLTexture) -> UIImage {
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let context = CGContext(data: &src,
                                width: texture.width,
                                height: texture.height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)
        
        let dstImageFilter = context?.makeImage()
        
        return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.up)
    }
}

// -----------------------------------------------------------------
func fClamp(_ v:Float, _ range:float2) -> Float {
    if v < range.x { return range.x }
    if v > range.y { return range.y }
    return v
}

func fClamp(_ v:Float, _ min:Float, _ max:Float) -> Float {
    if v < min { return min }
    if v > max { return max }
    return v
}

func iClamp(_ v:Int32, _ min:Int32, _ max:Int32) -> Int32 {
    if v < min { return min }
    if v > max { return max }
    return v
}

