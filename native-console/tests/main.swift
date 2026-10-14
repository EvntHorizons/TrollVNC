import Foundation

let fixtures=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:URL(fileURLWithPath:"native-console/tests/fixtures.json")))
func data(_ key:String)->Data {
    let h=Array(fixtures[key]!)
    return Data(stride(from:0,to:h.count,by:2).map{UInt8(String(h[$0...$0+1]),radix:16)!})
}
func check(_ value:Bool,_ name:String){if !value{fatalError(name)};print("PASS: \(name)")}
let parser=MAVParser()
let hb1=parser.feed(data("heartbeat1"))
check(hb1.count==1 && hb1[0].message==0 && hb1[0].system==1,"MAVLink 1 heartbeat")
let hb2=parser.feed(data("heartbeat2"))
check(hb2.count==1 && hb2[0].u8(6)==128 && hb2[0].u32(0)==4,"MAVLink 2 heartbeat")
let truncated=parser.feed(data("truncated"))
check(truncated.count==1 && truncated[0].u8(8)==0,"MAVLink 2 trailing zero reconstruction")
var bad=data("heartbeat2");bad[10] ^= 1
check(parser.feed(bad).isEmpty && parser.rejected==1,"Corrupted CRC rejected")
let split=data("position")
check(parser.feed(split.prefix(7)).isEmpty,"Fragment waits for rest")
let pos=parser.feed(split.dropFirst(7))
check(pos.count==1 && pos[0].i32(4)==400000000 && pos[0].i32(8) == -750000000 && pos[0].i32(16)==50000,"Position wire ordering")
let multiple=parser.feed(Data([4,5,6])+data("attitude")+data("gps")+data("hud")+data("status"))
check(multiple.map{$0.message} == [30,24,74,253],"Noise and concatenated frames")
check(abs(multiple[0].float(4)-0.1)<0.0001 && multiple[1].u8(29)==12 && multiple[2].float(12)==1,"Float and satellite fields")
var signed=data("heartbeat2");signed[2]=1;signed.append(Data(repeating:0,count:13))
check(parser.feed(signed).isEmpty && parser.rejected==2,"Unverified signed packets rejected")
var incompatible=data("heartbeat2");incompatible[2]=4
check(parser.feed(incompatible).isEmpty && parser.rejected==3,"Unknown incompatibility rejected")
check(parser.feed(data("heartbeat1")).count==1,"Recovery after rejection")
check(parser.feed(Data(repeating:0,count:131073)).isEmpty,"Bounded buffering")
print("All independent protocol fixtures passed.")
