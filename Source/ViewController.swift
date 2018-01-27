import UIKit
import Metal
import MetalKit

var control = Control()
var vc:ViewController! = nil

var autoMove:Bool = false
var autoAngle:Float = 0

class ViewController: UIViewController {
    var cBuffer:MTLBuffer! = nil
    var timer = Timer()
    var outTexture: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    
    let VIEWSIZE:Int = 500

    let threadGroupCount = MTLSizeMake(20,20, 1)   // integer factor of image size
    lazy var threadGroups: MTLSize = { MTLSizeMake(VIEWSIZE / threadGroupCount.width, VIEWSIZE / threadGroupCount.height, 1) }()
    
    var sList:[SliderView]! = nil
    var dList:[DeltaView]! = nil

    @IBOutlet var sCameraZ: SliderView!
    @IBOutlet var sFocusZ: SliderView!
    @IBOutlet var sIterMin: SliderView!
    @IBOutlet var sIterWidth: SliderView!
    @IBOutlet var sZoom: SliderView!
    @IBOutlet var sPower: SliderView!
    @IBOutlet var sHsvX: SliderView!
    @IBOutlet var sHsvY: SliderView!
    @IBOutlet var sHsvZ: SliderView!
    @IBOutlet var sFlimit: SliderView!
    @IBOutlet var sFvalue: SliderView!
    @IBOutlet var sMradius: SliderView!
    @IBOutlet var sFradius: SliderView!
    @IBOutlet var sScale: SliderView!
    @IBOutlet var sCutoff: SliderView!

    @IBOutlet var dCameraXY: DeltaView!
    @IBOutlet var dFocusXY: DeltaView!

    @IBOutlet var imageViewL: UIImageView!
    @IBOutlet var imageViewR: UIImageView!
    @IBOutlet var formulaSeg: UISegmentedControl!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var autoButton: UIButton!
    @IBOutlet var colorResetButton: UIButton!
    @IBOutlet var paletteButton: UIButton!
    @IBOutlet var saveLoadButton: UIButton!
    @IBOutlet var helpButton: UIButton!
    @IBOutlet var resetButton: UIButton!

    @IBAction func autoButtonPressed(_ sender: UIButton) { autoMove = !autoMove }
    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }
    @IBAction func recordButtonPressed(_ sender: UIButton) { nextRecordingStatus() }
    
    func resetHsv() {
        control.hsv = vector_float3(3.62,1,2.4)
        unWrapFloat3()
    }
    
    @IBAction func resetColorPressed(_ sender: UIButton) {
        resetHsv()
        sHsvX.setNeedsDisplay()
        sHsvY.setNeedsDisplay()
        sHsvZ.setNeedsDisplay()
        needsPaint = true
    }

    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -

    let zoomMin:Float = 0.3
    let zoomMax:Float = 30

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        do {
            let defaultLibrary: MTLLibrary! = device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "rayMarchShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        } catch { fatalError("error creating pipelines") }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: VIEWSIZE,
            height: VIEWSIZE,
            mipmapped: false)
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!
        
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        sList = [ sCameraZ,sFocusZ, sHsvX,sHsvY,sHsvZ, sIterMin,sIterWidth, sZoom, sPower, sFlimit,sFvalue,sMradius,sFradius,sScale,sCutoff ]
        dList = [ dCameraXY,dFocusXY ]
        
        let cameraMin:Float = -5
        let cameraMax:Float = 5
        let focusMin:Float = -10
        let focusMax:Float = 10
        let powerMin:Float = 2
        let powerMax:Float = 12
        
        dCameraXY.initializeFloat1(&control.cameraX, cameraMin, cameraMax, 1, "Camera XY")
        dCameraXY.initializeFloat2(&control.cameraY)
        sCameraZ.initializeFloat(&control.cameraZ, .delta, cameraMin, cameraMax, 1, "Camera Z")
        
        dFocusXY.initializeFloat1(&control.focusX, focusMin,focusMax, 1, "Focus XY")
        dFocusXY.initializeFloat2(&control.focusY)
        sFocusZ.initializeFloat(&control.focusZ, .delta, focusMin, focusMax, 1, "Focus Z")
        
        sHsvX.initializeFloat(&control.hsvX, .loop,  0.1, 5, 5, "Color Center")
        sHsvY.initializeFloat(&control.hsvY, .delta, 0.1, 1, 5, "Color Bright")
        sHsvZ.initializeFloat(&control.hsvZ, .delta, 0.1, 3, 5, "Color Width")
        
        sIterMin.initializeInt32(&control.iterMin, .direct, Float(1), Float(10), 1, "Iter Min")
        sIterWidth.initializeInt32(&control.iterWidth, .direct, Float(1), Float(50), 1, "Iter Width")
        sZoom.initializeFloat(&control.zoom, .delta, zoomMin, zoomMax, 2, "Zoom")
        sPower.initializeFloat(&control.power, .delta, powerMin, powerMax, 1, "Power")
        
        sFlimit.initializeFloat(&control.fLimit,    .delta, 0.1,1,  0.3,    "F Limit")  // Box
        sFvalue.initializeFloat(&control.fValue,    .delta, 0.1,2,  0.3,    "F Value")
        sMradius.initializeFloat(&control.mRadius,  .delta, 0.5,2,  0.3,    "M Radius")
        sFradius.initializeFloat(&control.fRadius,  .delta, 1.1,3,  0.3,    "F Radius")
        sScale.initializeFloat(&control.scale,      .delta, 0.2,3,   1,     "Scale")
        sCutoff.initializeFloat(&control.cutoff,    .delta, 0.1,5,   1,     "Cutoff")

        timer = Timer.scheduledTimer(timeInterval: 1.0/60.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
        reset()
        resetHsv()
    }
    
    func unWrapFloat3() {
        control.cameraX = control.camera.x
        control.cameraY = control.camera.y
        control.cameraZ = control.camera.z
        control.focusX = control.focus.x
        control.focusY = control.focus.y
        control.focusZ = control.focus.z
        control.hsvX = control.hsv.x
        control.hsvY = control.hsv.y
        control.hsvZ = control.hsv.z
    }

    func wrapFloat3() {
        control.camera.x = control.cameraX
        control.camera.y = control.cameraY
        control.camera.z = control.cameraZ
        control.focus.x = control.focusX
        control.focus.y = control.focusY
        control.focus.z = control.focusZ
        control.hsv.x = control.hsvX
        control.hsv.y = control.hsvY
        control.hsv.z = control.hsvZ
    }

    //MARK: -
    //MARK: -
    
    func reset() {
        control.camera = vector_float3(0.0,0.0,-1.66)
        control.focus = vector_float3(0.01,0.01,1)
        control.zoom = 2
        control.size = Int32(VIEWSIZE)
        control.bailout = 10
        control.power = 8
        control.iterMin = 3
        control.iterWidth = 5
        
        control.fLimit = 1.4149    // Box
        control.fValue = 1.4949
        control.mRadius = 1.0874
        control.fRadius = 1.3303
        control.scale = 1.5755
        control.cutoff = 1.3836

        unWrapFloat3()

        for s in sList { s.setNeedsDisplay() }
        for d in dList { d.setNeedsDisplay() }

        updateActiveWidgets()
        setRecordingStatus(.idle)

        needsPaint = true
    }
    
    //MARK: -
    //MARK: -
    
    enum RecordStatus { case idle,recording,playing }
    
    var recordStatus:RecordStatus = .idle
    var recordStart = Control()
    var recordEnd = Control()
    var recordRatio:Float = 0
    
    func setRecordingStatus(_ status:RecordStatus) {
        recordStatus = status
        var str:String = ""
        switch recordStatus {
        case .idle :
            str = "Start Recording"
            hidePlaybackWidgets(false)
        case .recording :
            str = "Start Playing"
            recordStart = control
        case .playing :
            str = "Stop Playing"
            hidePlaybackWidgets(true)
            recordEnd = control
            recordRatio = 0
        }
        
        recordButton.setTitle(str, for:.normal)
    }
    
    func nextRecordingStatus() {
        switch recordStatus {
        case .idle : setRecordingStatus(.recording)
        case .recording : setRecordingStatus(.playing)
        case .playing : setRecordingStatus(.idle)
        }
    }
    
    func playRecording() {
        func fRatio(_ v1:Float, _ v2:Float, _ ratio:Float) -> Float { return v1 + (v2-v1) * ratio }
        
        let mix:Float = 0.5 + sinf(recordRatio)/2
        recordRatio += 0.01
        
        control.camera.x = fRatio(recordStart.camera.x,recordEnd.camera.x,mix)
        control.camera.y = fRatio(recordStart.camera.y,recordEnd.camera.y,mix)
        control.camera.z = fRatio(recordStart.camera.z,recordEnd.camera.z,mix)
        control.focus.x = fRatio(recordStart.focus.x,recordEnd.focus.x,mix)
        control.focus.y = fRatio(recordStart.focus.y,recordEnd.focus.y,mix)
        control.focus.z = fRatio(recordStart.focus.z,recordEnd.focus.z,mix)
        control.zoom = fRatio(recordStart.zoom,recordEnd.zoom,mix)
        control.power = fRatio(recordStart.power,recordEnd.power,mix)
        control.fLimit = fRatio(recordStart.fLimit,recordEnd.fLimit,mix)
        control.fValue = fRatio(recordStart.fValue,recordEnd.fValue,mix)
        control.mRadius = fRatio(recordStart.mRadius,recordEnd.mRadius,mix)
        control.fRadius = fRatio(recordStart.fRadius,recordEnd.fRadius,mix)
        control.scale = fRatio(recordStart.scale,recordEnd.scale,mix)
        control.cutoff = fRatio(recordStart.cutoff,recordEnd.cutoff,mix)
        unWrapFloat3()

        _ = sHsvX.update()
        _ = sHsvY.update()
        _ = sHsvZ.update()

        needsPaint = true
    }

    func hidePlaybackWidgets(_ hide:Bool) {
        let show = !hide
        dCameraXY.setActive(show)
        dFocusXY.setActive(show)
        sCameraZ.setActive(show)
        sFocusZ.setActive(show)
        sZoom.setActive(show)
        sPower.setActive(show)
        
        autoButton.isHidden = hide
        resetButton.isHidden = hide
        saveLoadButton.isHidden = hide
        helpButton.isHidden = hide
        formulaSeg.isHidden = hide
        
        updateActiveWidgets()
    }

    //MARK: -

    func updateActiveWidgets() {
        let box:Bool = (control.formula == 5) && (recordStatus != .playing)
        sFlimit.setActive(box)
        sFvalue.setActive(box)
        sMradius.setActive(box)
        sFradius.setActive(box)
        sScale.setActive(box)
        sCutoff.setActive(box)
        sPower.setActive(!box && (recordStatus != .playing))
    }
    
    @IBAction func formulaChanged(_ sender: UISegmentedControl) {
        control.formula = Int32(sender.selectedSegmentIndex)
        updateActiveWidgets()
        needsPaint = true
    }

    func programLoaded() {
        updateActiveWidgets()
        formulaSeg.selectedSegmentIndex = Int(control.formula)
        for s in sList { s.setNeedsDisplay() }
        for d in dList { d.setNeedsDisplay() }
        needsPaint = true
    }

    var angle:Float = 0
    var needsPaint:Bool = false
    
    //MARK: -
    //MARK: -
    
    @objc func timerHandler() {
        if recordStatus == .playing {
            playRecording()
        }
        else {
            for s in sList { if s.update() { needsPaint = true }}
            for d in dList { if d.update() { needsPaint = true }}

            control.light.x = sinf(angle) * 5
            control.light.y = sinf(angle/3) * 5
            control.light.z = -12 + sinf(angle/2) * 5
            angle += 0.05
            
            if autoMove {
                autoAngle += 0.01
                needsPaint = true
            }
        }
        
        if needsPaint {
            needsPaint = false
            
            calcRayMarch(0)
            imageViewL.image = self.image(from: self.outTexture)
            calcRayMarch(1)
            imageViewR.image = self.image(from: self.outTexture)
        }
    }
    
    //MARK: -
    //MARK: -

    func parseCameraRotation(_ pt:CGPoint) {
        let scale:Float = 0.0001
        control.cameraX += Float(pt.x) * scale
        control.cameraY += Float(pt.y) * scale
        dCameraXY.setNeedsDisplay()
        needsPaint = true
    }
    
    func parseFocusRotation(_ pt:CGPoint) {
        let scale:Float = 0.0001
        control.focusX += Float(pt.x) * scale
        control.focusY += Float(pt.y) * scale
        dFocusXY.setNeedsDisplay()
        needsPaint = true
    }
    
    var numberPanTouches:Int = 0
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        
        if recordStatus == .playing { setRecordingStatus(.idle) }

        let pt = sender.translation(in: self.view)
        let count = sender.numberOfTouches
        if count == 0 { numberPanTouches = 0 }  else if count > numberPanTouches { numberPanTouches = count }
        
        switch sender.numberOfTouches {
        case 1 : if numberPanTouches < 2 { parseCameraRotation(pt) } // prevent rotation after releasing translation
        case 2 : parseFocusRotation(pt)
        default : break
        }
    }

    var startZoom:Float = 0
    
    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {
        if sender.state == .began { startZoom = control.zoom  }        
        control.zoom = fClamp(startZoom / Float(sender.scale),zoomMin,zoomMax)
        sZoom.setNeedsDisplay()
        needsPaint = true
    }
    
    //MARK: -
    
    func calcRayMarch(_ who:Int) {
        wrapFloat3()
        control.iterMax = control.iterMin + control.iterWidth
        
        if autoMove {
            control.camera.x += cosf(autoAngle) / 10
            control.camera.y += sinf(autoAngle) / 10
        }
        
        let parallax:Float = 0.002
        
        if who == 0 {
            control.camera.x = control.cameraX + parallax
            cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        }
        else {
            control.camera.x = control.cameraX - parallax
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

