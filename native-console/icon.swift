import AppKit
for size in [120,152,167,180] {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
 NSColor(calibratedRed:0.10,green:0.17,blue:0.23,alpha:1).setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
 let s=CGFloat(size)
 NSColor(calibratedRed:0.47,green:0.77,blue:0.96,alpha:1).setStroke()
 for scale in [0.19,0.32] {
  let circle=NSBezierPath();circle.lineWidth=s*0.025
  circle.appendArc(withCenter:NSPoint(x:s*0.50,y:s*0.59),radius:s*scale,startAngle:25,endAngle:155)
  circle.stroke()
 }
 NSColor(calibratedRed:0.89,green:0.66,blue:0.30,alpha:1).setFill()
 NSBezierPath(ovalIn:NSRect(x:s*0.46,y:s*0.55,width:s*0.08,height:s*0.08)).fill()
 let label="C2" as NSString
 let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:s*0.30,weight:.bold),.foregroundColor:NSColor.white]
 let textSize=label.size(withAttributes:attrs)
 label.draw(at:NSPoint(x:(s-textSize.width)/2,y:s*0.15),withAttributes:attrs)
 image.unlockFocus();let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"Icon\(size).png"))
}
