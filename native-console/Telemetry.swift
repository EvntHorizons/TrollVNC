import Foundation
import Network
import Combine

struct Reading {
    let value: String
    let at: Date
}
final class Telemetry: ObservableObject {
    @Published var status="Stopped"
    @Published var active=false
    @Published var values=[String:Reading]()
    @Published var messages=[String]()
    @Published var received=0
    @Published var rejected=0
    @Published var unsupported=0
    @Published var lastHeartbeat: Date?
    @Published var now=Date()
    @Published var captureStatus="Capture off"
    @Published var captureURL: URL?
    private var listener:NWListener?
    private var peers=[UUID:NWConnection]()
    private var parsers=[UUID:MAVParser]()
    private var timer:AnyCancellable?
    private var file:FileHandle?
    private var bytesWritten=0
    private var target:UInt8=1
    private var targetComponent:UInt8=1
    private var generation=UUID()
    private var packetBudget=0
    private var byteBudget=0
    private var budgetAt=Date()
    var linkState:String {
        guard active else {return "Not connected"}
        guard let at=lastHeartbeat else {return "Waiting for heartbeat"}
        return now.timeIntervalSince(at)>5 ? "Heartbeat stale" : "Receiving telemetry"
    }
    init(){timer=Timer.publish(every:1,on:.main,in:.common).autoconnect().sink{[weak self] date in self?.now=date}}
    func display(_ key:String)->String {
        guard active,let r=values[key] else{return "—"}
        return now.timeIntervalSince(r.at)>5 ? "\(r.value) · stale" : r.value
    }
    func start(port:String,system:String,component:String,record:Bool){
        stop()
        guard let p=UInt16(port),p>0,let s=UInt8(system),s>0,let c=UInt8(component),c>0 else {status="Use port 1–65535 and IDs 1–255.";return}
        target=s;targetComponent=c;received=0;rejected=0;unsupported=0;values=[:];messages=[];lastHeartbeat=nil
        packetBudget=0;byteBudget=0;budgetAt=Date();captureURL=nil
        generation=UUID();let run=generation
        do {
            let l=try NWListener(using:.udp,on:NWEndpoint.Port(rawValue:p)!)
            listener=l;active=true;status="Opening UDP \(p)…"
            if record {openCapture()}
            l.stateUpdateHandler = {[weak self] state in
                guard let self=self,self.generation==run else{return}
                switch state {
                case .ready:self.status="Listening on UDP \(p) · system \(s), component \(c)"
                case .failed(let e):self.stop();self.status="Listener failed: \(e.localizedDescription)"
                default:break
                }
            }
            l.newConnectionHandler = {[weak self] c in
                guard let self=self,self.generation==run,self.active,self.peers.count<4 else {c.cancel();return}
                let id=UUID();self.peers[id]=c;self.parsers[id]=MAVParser()
                c.stateUpdateHandler = {[weak self] state in
                    if case .failed = state {self?.remove(id)}
                    if case .cancelled = state {self?.remove(id)}
                }
                c.start(queue:.main);self.receive(c,id:id,run:run)
                // Prevent an abandoned source from occupying a slot forever.
                DispatchQueue.main.asyncAfter(deadline:.now()+60){[weak self,weak c] in
                    if let self=self,self.generation==run {self.remove(id);c?.cancel()}
                }
            }
            l.start(queue:.main)
        } catch {stop();status=error.localizedDescription}
    }
    private func remove(_ id:UUID){peers.removeValue(forKey:id)?.cancel();parsers.removeValue(forKey:id)}
    private func receive(_ c:NWConnection,id:UUID,run:UUID){
        c.receiveMessage{[weak self,weak c] data,_,_,error in
            guard let self=self,let c=c,self.active,self.generation==run,self.peers[id] != nil else{return}
            if let data=data,let parser=self.parsers[id] {
                if Date().timeIntervalSince(self.budgetAt)>=1 {self.packetBudget=0;self.byteBudget=0;self.budgetAt=Date()}
                self.packetBudget += 1;self.byteBudget += data.count
                if self.packetBudget>200 || self.byteBudget>262144 {self.stop();self.status="Input rate exceeded diagnostic limit. Reduce source rate and restart.";return}
                let bad=parser.rejected,other=parser.unsupported
                for packet in parser.feed(data) where packet.system==self.target && packet.component==self.targetComponent {self.consume(packet)}
                self.rejected += parser.rejected-bad;self.unsupported += parser.unsupported-other
            }
            if error != nil {self.remove(id)} else {self.receive(c,id:id,run:run)}
        }
    }
    func stop(){
        generation=UUID();listener?.cancel();listener=nil
        let old=Array(peers.values);peers.removeAll();parsers.removeAll();old.forEach{$0.cancel()}
        active=false;status="Stopped";lastHeartbeat=nil;values=[:]
        if file != nil {try? file?.close();file=nil;captureStatus="Capture saved"}
    }
    private func openCapture(){
        do {
            let folder=dataRoot.appendingPathComponent("Captures")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let existing=(try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)).filter{$0.pathExtension=="tlog"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
            for old in existing.prefix(max(0,existing.count-4)) {try FileManager.default.removeItem(at:old)}
            let u=folder.appendingPathComponent("telemetry-\(Int(Date().timeIntervalSince1970)).tlog")
            guard FileManager.default.createFile(atPath:u.path,contents:nil) else {throw CocoaError(.fileWriteUnknown)}
            file=try FileHandle(forWritingTo:u);captureURL=u;bytesWritten=0;captureStatus="Recording · 10 MB limit"
        } catch {captureStatus="Capture unavailable: \(error.localizedDescription)"}
    }
    private func consume(_ p:MAVPacket){
        received += 1
        if let handle=file {
            var stamp=UInt64(Date().timeIntervalSince1970*1_000_000).bigEndian
            var data=withUnsafeBytes(of:&stamp){Data($0)};data.append(p.raw)
            if bytesWritten+data.count>10_000_000 {try? handle.close();file=nil;captureStatus="Capture saved · size limit reached"}
            else {do {try handle.write(contentsOf:data);bytesWritten += data.count} catch {try? handle.close();file=nil;captureStatus="Capture failed: \(error.localizedDescription)"}}
        }
        func set(_ key:String,_ value:String){values[key]=Reading(value:value,at:Date())}
        func f(_ v:Float,_ suffix:String)->String {v.isFinite ? String(format:"%.1f",v)+suffix : "Unknown"}
        switch p.message {
        case 0:
            lastHeartbeat=Date()
            set("Vehicle",[1:"Fixed wing",2:"Quadrotor",3:"Coaxial",4:"Helicopter",13:"Hexarotor",14:"Octorotor",19:"VTOL" ][Int(p.u8(4))] ?? "Type \(p.u8(4))")
            set("Arm state",p.u8(6)&128 != 0 ? "Armed" : "Disarmed")
            set("Custom mode","\(p.u32(0)) (autopilot-specific)")
        case 1:
            set("Voltage",p.u16(14)==65535 ? "Unknown" : String(format:"%.2f V",Double(p.u16(14))/1000))
            let remaining=Int8(bitPattern:p.u8(30));set("Aircraft battery",remaining<0 ? "Unknown" : "\(remaining)%")
        case 24:
            set("GPS fix",[0:"No GPS",1:"No fix",2:"2D",3:"3D",4:"DGPS",5:"RTK float",6:"RTK fixed"][Int(p.u8(28))] ?? "Fix \(p.u8(28))")
            set("Satellites",p.u8(29)==255 ? "Unknown" : "\(p.u8(29))")
        case 30:
            set("Roll",f(p.float(4)*180/Float.pi,"°"));set("Pitch",f(p.float(8)*180/Float.pi,"°"));set("Yaw",f(p.float(12)*180/Float.pi,"°"))
        case 33:
            let lat=Double(p.i32(4))/1e7,lon=Double(p.i32(8))/1e7
            if abs(lat)<=90 && abs(lon)<=180 {set("Latitude",String(format:"%.7f",lat));set("Longitude",String(format:"%.7f",lon))}
            set("Relative altitude",String(format:"%.1f m",Double(p.i32(16))/1000))
            set("Heading",p.u16(26)==65535 ? "Unknown" : String(format:"%.1f°",Double(p.u16(26))/100))
        case 74:
            set("Airspeed",f(p.float(0)," m/s"));set("Groundspeed",f(p.float(4)," m/s"));set("Climb",f(p.float(12)," m/s"))
        case 253:
            let text=String(bytes:p.payload.dropFirst().prefix(50).prefix{$0 != 0},encoding:.utf8) ?? "Unreadable status text"
            messages.insert("\(DateFormatter.localizedString(from:Date(),dateStyle:.none,timeStyle:.medium)) [\(p.u8(0))] \(text)",at:0)
            messages=Array(messages.prefix(50))
        default:break
        }
    }
}
