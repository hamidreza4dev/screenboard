import AppKit
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
func path(_ r:NSRect,_ rad:CGFloat)->NSBezierPath { NSBezierPath(roundedRect:r,xRadius:rad,yRadius:rad) }
func fill(_ p:NSBezierPath,_ c:NSColor){c.setFill();p.fill()}
func stroke(_ p:NSBezierPath,_ c:NSColor,_ w:CGFloat){c.setStroke();p.lineWidth=w;p.lineCapStyle = .round;p.lineJoinStyle = .round;p.stroke()}
func star(_ x:CGFloat,_ y:CGFloat,_ s:CGFloat){let p=NSBezierPath();p.move(to:NSPoint(x:x,y:y+s));p.curve(to:NSPoint(x:x+s,y:y),controlPoint1:NSPoint(x:x+s*0.15,y:y+s*0.15),controlPoint2:NSPoint(x:x+s*0.15,y:y+s*0.15));p.curve(to:NSPoint(x:x,y:y-s),controlPoint1:NSPoint(x:x+s*0.15,y:y-s*0.15),controlPoint2:NSPoint(x:x+s*0.15,y:y-s*0.15));p.curve(to:NSPoint(x:x-s,y:y),controlPoint1:NSPoint(x:x-s*0.15,y:y-s*0.15),controlPoint2:NSPoint(x:x-s*0.15,y:y-s*0.15));p.curve(to:NSPoint(x:x,y:y+s),controlPoint1:NSPoint(x:x-s*0.15,y:y+s*0.15),controlPoint2:NSPoint(x:x-s*0.15,y:y+s*0.15));fill(p,.white)}
for n in 1...3 {
let im=NSImage(size:NSSize(width:1024,height:1024));im.lockFocus()
let body=path(NSRect(x:100,y:100,width:824,height:824),180)
NSGraphicsContext.saveGraphicsState();let sh=NSShadow();sh.shadowColor=NSColor.black.withAlphaComponent(0.2);sh.shadowBlurRadius=18;sh.shadowOffset=NSSize(width:0,height:-8);sh.set();fill(body,.systemBlue);NSGraphicsContext.restoreGraphicsState()
let colors:[[NSColor]]=[[NSColor(calibratedRed:0.12,green:0.32,blue:0.9,alpha:1),.systemCyan],[NSColor(calibratedRed:0.24,green:0.15,blue:0.67,alpha:1),.systemBlue],[NSColor(calibratedRed:0.03,green:0.48,blue:0.63,alpha:1),NSColor(calibratedRed:0.44,green:0.85,blue:0.94,alpha:1)]]
NSGradient(colors:colors[n-1])!.draw(in:body,angle:60);stroke(path(NSRect(x:103,y:103,width:818,height:818),177),.white.withAlphaComponent(0.48),3)
if n==1 {
let screen=path(NSRect(x:242,y:345,width:540,height:365),48);fill(screen,.white.withAlphaComponent(0.16));stroke(screen,.white,25)
let base=NSBezierPath();base.move(to:NSPoint(x:215,y:290));base.line(to:NSPoint(x:809,y:290));stroke(base,.white,30)
star(544,527,107);star(703,704,54)
} else if n==2 {
let p=NSBezierPath();p.move(to:NSPoint(x:512,y:780));p.line(to:NSPoint(x:732,y:690));p.line(to:NSPoint(x:717,y:470));p.curve(to:NSPoint(x:512,y:259),controlPoint1:NSPoint(x:700,y:361),controlPoint2:NSPoint(x:591,y:292));p.curve(to:NSPoint(x:307,y:470),controlPoint1:NSPoint(x:433,y:292),controlPoint2:NSPoint(x:324,y:361));p.line(to:NSPoint(x:292,y:690));p.close();fill(p,.white.withAlphaComponent(0.22));stroke(p,.white.withAlphaComponent(0.9),18)
let arc=NSBezierPath();arc.appendArc(withCenter:NSPoint(x:512,y:570),radius:76,startAngle:0,endAngle:180);stroke(arc,.white,32);fill(path(NSRect(x:406,y:397,width:212,height:170),32),.white);star(751,759,55)
} else {
let tile=path(NSRect(x:282,y:270,width:460,height:470),75);fill(tile,.white.withAlphaComponent(0.25));stroke(tile,.white.withAlphaComponent(0.9),16)
let wipe=NSBezierPath();wipe.move(to:NSPoint(x:360,y:382));wipe.curve(to:NSPoint(x:650,y:640),controlPoint1:NSPoint(x:570,y:370),controlPoint2:NSPoint(x:430,y:652));stroke(wipe,.white,68);star(673,722,92);star(358,690,39)
}
im.unlockFocus();let rep=NSBitmapImageRep(data:im.tiffRepresentation!)!;try! rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("variant-\(n)-1024.png"))
let small=NSImage(size:NSSize(width:64,height:64));small.lockFocus();NSGraphicsContext.current!.imageInterpolation = .high;im.draw(in:NSRect(x:0,y:0,width:64,height:64));small.unlockFocus();try! NSBitmapImageRep(data:small.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("variant-\(n)-64.png"))
}
