import AppKit
for size in [120,152,167,180] {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
 NSColor(calibratedRed:0.10,green:0.17,blue:0.23,alpha:1).setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
 let s=CGFloat(size)
 for i in 0..<3 {
  let y=s*(0.28+CGFloat(i)*0.22)
  NSColor(calibratedWhite:0.85,alpha:1).setStroke();let path=NSBezierPath();path.lineWidth=s*0.035;path.move(to:NSPoint(x:s*0.20,y:y));path.line(to:NSPoint(x:s*0.80,y:y));path.stroke()
  NSColor(calibratedRed:0.89,green:0.66,blue:0.30,alpha:1).setFill();let x=s*(i==1 ? 0.62:0.35);NSBezierPath(roundedRect:NSRect(x:x-s*0.055,y:y-s*0.075,width:s*0.11,height:s*0.15),xRadius:s*0.025,yRadius:s*0.025).fill()
 }
 image.unlockFocus();let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"Icon\(size).png"))
}
