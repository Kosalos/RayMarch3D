import UIKit

class DeltaView: UIView {
    var context : CGContext?
    var scenter:Float = 0
    var swidth:Float = 0
    var ident:Int = 0
    var active = true
    
    var valuePointerX:UnsafeMutableRawPointer! = nil
    var valuePointerY:UnsafeMutableRawPointer! = nil
    var deltaValue:Float = 0
    var name:String = "name"
    
    var mRange = float2(0,256)
    
    func address<T>(of: UnsafePointer<T>) -> UInt { return UInt(bitPattern: of) }
    
    func initialize(_ iname:String) { 
        name = iname
        swidth = Float(bounds.width)
        scenter = swidth / 2
        setNeedsDisplay()
    }
    
    func initializeFloat1(_ vx: inout Float,  _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        let valueAddressX = address(of:&vx)
        valuePointerX = UnsafeMutableRawPointer(bitPattern:valueAddressX)!
        
        mRange.x = min
        mRange.y = max
        deltaValue = delta
        name = iname        
        swidth = Float(bounds.width)
        scenter = swidth / 2
    }
    
    func initializeFloat2(_ vy: inout Float) {
        let valueAddressY = address(of:&vy)
        valuePointerY = UnsafeMutableRawPointer(bitPattern:valueAddressY)!
        setNeedsDisplay()
    }
    
    func setActive(_ v:Bool) {
        active = v
        setNeedsDisplay()
    }
    
    func percentX(_ percent:CGFloat) -> CGFloat { return CGFloat(bounds.size.width) * percent }
    
    //MARK: ==================================
    
    override func draw(_ rect: CGRect) {
        context = UIGraphicsGetCurrentContext()
        
        if !active {
            let G:CGFloat = 0.13        // color Lead
            UIColor(red:G, green:G, blue:G, alpha: 1).set()
            UIBezierPath(rect:bounds).fill()
            return
        }
        
        UIColor(red:0.2, green:0.2, blue:0.2, alpha: 1).set()
        UIBezierPath(rect:bounds).fill()
        
        // edge -------------------------------------------------
        let ctx = context!
        let path = UIBezierPath(rect:bounds)
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        
        UIColor.black.set()
        context?.setLineWidth(2)
        
        if self.tag == 0 {   // cross hairs
            drawVLine(CGFloat(scenter),0,bounds.height)
            drawHLine(0,bounds.width,CGFloat(scenter))
        }
        
        if self.tag == 1 { // iter diagonals
            drawLine(CGPoint(x:CGFloat(scenter), y:0), CGPoint(x:0, y:bounds.height))
            drawLine(CGPoint(x:CGFloat(scenter), y:0), CGPoint(x:bounds.width, y:bounds.height))
        }
        
        // value ------------------------------------------
        func formatted(_ v:Float) -> String { return String(format:"%6.4f",v) }
        func formatted2(_ v:Float) -> String { return String(format:"%7.5f",v) }
        func formatted3(_ v:Float) -> String { return String(format:"%d",Int(v)) }
        func formatted4(_ v:Float) -> String { return String(format:"%5.2f",v) }
        
        let vx = percentX(0.60)
        
        func valueColor(_ v:Float) -> UIColor {
            var c = UIColor.gray
            if v < 0 { c = UIColor.red } else if v > 0 { c = UIColor.green }
            return c
        }
        
        func coloredValue(_ v:Float, _ y:CGFloat) { drawText(vx,y,valueColor(v),16, formatted(v)) }
        
        drawText(10,8,.white,16,name)
        
        if valuePointerX != nil {
            let xx:Float = valuePointerX.load(as: Float.self)
            let yy:Float = valuePointerY.load(as: Float.self)
            
            if self.tag == 1 { // iter
                drawText(vx, 8,valueColor(xx),16, formatted3(xx))
                drawText(vx,28,valueColor(yy),16, formatted3(yy))
            }
            else {
                coloredValue(xx,8)
                coloredValue(yy,28)
            }
        }
    }
    
    func fClamp2(_ v:Float, _ range:float2) -> Float {
        if v < range.x { return range.x }
        if v > range.y { return range.y }
        return v
    }
    
    var deltaX:Float = 0
    var deltaY:Float = 0
    var touched = false
    
    //MARK: ==================================
    
    func update() -> Bool {
        if valuePointerX == nil || !active || !touched { return false }
        
        var valueX = valuePointerX.load(as: Float.self)
        var valueY = valuePointerY.load(as: Float.self)
        
        valueX = fClamp2(valueX + deltaX * deltaValue, mRange)
        valueY = fClamp2(valueY + deltaY * deltaValue, mRange)
        
        valuePointerX.storeBytes(of:valueX, as:Float.self)
        valuePointerY.storeBytes(of:valueY, as:Float.self)
        
        setNeedsDisplay()
        return true
    }
    
    //MARK: ==================================
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !active { return }
        if valuePointerX == nil { return }
        
        for t in touches {
            let pt = t.location(in: self)
            
            deltaX = (Float(pt.x) - scenter) / swidth / 10
            deltaY = (Float(pt.y) - scenter) / swidth / 10
            touched = true
            setNeedsDisplay()
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touchesBegan(touches, with:event) }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touched = false }
    
    func drawLine(_ p1:CGPoint, _ p2:CGPoint) {
        context?.beginPath()
        context?.move(to:p1)
        context?.addLine(to:p2)
        context?.strokePath()
    }
    
    func drawVLine(_ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat) { drawLine(CGPoint(x:x,y:y1),CGPoint(x:x,y:y2)) }
    func drawHLine(_ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat) { drawLine(CGPoint(x:x1, y:y),CGPoint(x: x2, y:y)) }
    
    func drawText(_ x:CGFloat, _ y:CGFloat, _ color:UIColor, _ sz:CGFloat, _ str:String) {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = NSTextAlignment.left
        
        let font = UIFont.init(name: "Helvetica", size:sz)!
        
        let textFontAttributes = [
            NSAttributedStringKey.font: font,
            NSAttributedStringKey.foregroundColor: color,
            NSAttributedStringKey.paragraphStyle: paraStyle,
            ]
        
        str.draw(in: CGRect(x:x, y:y, width:800, height:100), withAttributes: textFontAttributes)
    }
    
    func drawText(_ pt:CGPoint, _ color:UIColor, _ sz:CGFloat, _ str:String) { drawText(pt.x,pt.y,color,sz,str) }
}
