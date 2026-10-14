import SwiftUI
import Network

struct LinkProfile:Codable,Identifiable {
    var id=UUID()
    var name:String
    var host:String
    var port:String
    var udp:String
    var system:String
    var component:String
    var stream:String
}
struct Waypoint:Codable,Identifiable {
    var id=UUID()
    var latitude:Double
    var longitude:Double
    var altitude:Double
}
struct StationState:Codable {
    var profiles=[LinkProfile]()
    var points=[Waypoint]()
    var checklist=[String:Bool]()
}
final class Station:ObservableObject {
    @Published var state=StationState()
    @Published var saveStatus="Saved on this tablet"
    @Published var network="Checking network…"
    @Published var archives=[URL]()
    @Published var keepAwake=UserDefaults.standard.bool(forKey:"keepAwake")
    private let monitor=NWPathMonitor()
    init(){
        let url=dataRoot.appendingPathComponent("station.json")
        if let data=try? Data(contentsOf:url) {
            do {state=try JSONDecoder().decode(StationState.self,from:data)}
            catch {saveStatus="Could not read saved station settings. Original file preserved."}
        }
        monitor.pathUpdateHandler = {[weak self] path in DispatchQueue.main.async {
            let type=path.usesInterfaceType(.wifi) ? "Wi-Fi" : path.usesInterfaceType(.wiredEthernet) ? "Ethernet" : path.usesInterfaceType(.cellular) ? "Cellular" : "Network"
            self?.network=path.status == .satisfied ? "\(type) available · reachability untested" : "No network path"
        }}
        monitor.start(queue:DispatchQueue(label:"c2.path"));refreshArchives()
    }
    deinit{monitor.cancel()}
    func save(){do{try JSONEncoder().encode(state).write(to:dataRoot.appendingPathComponent("station.json"),options:.atomic);saveStatus="Saved on this tablet"}catch{saveStatus="Save failed: \(error.localizedDescription)"}}
    func refreshArchives(){
        archives=["Reports","Captures"].flatMap{folder -> [URL] in
            ((try? FileManager.default.contentsOfDirectory(at:dataRoot.appendingPathComponent(folder),includingPropertiesForKeys:nil)) ?? []).filter{["txt","tlog"].contains($0.pathExtension)}
        }.sorted{$0.lastPathComponent>$1.lastPathComponent}
    }
    func awake(_ active:Bool){UIApplication.shared.isIdleTimerDisabled=keepAwake && active;UserDefaults.standard.set(keepAwake,forKey:"keepAwake")}
    static let checks=["Airframe and fasteners inspected","Propellers and control surfaces inspected","Power wiring and battery checked","Flight controller and sensors identified","RC link and manual takeover checked","Telemetry link checked","Failsafe behavior tested on bench","Flight area and mission reviewed"]
    func exportPlan()->String {
        let features: [[String:Any]]=state.points.enumerated().map{i,p in
            ["type":"Feature","properties":["sequence":i+1,"plannedAltitudeAboveLaunchM":p.altitude,"status":"draft; not flight validated"],"geometry":["type":"Point","coordinates":[p.longitude,p.latitude]]]
        }
        let object:[String:Any]=["type":"FeatureCollection","name":"C2 Tablet mission draft","features":features]
        return (try? String(data:JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)) ?? "Export failed"
    }
    var routeDistance:Double {
        guard state.points.count>1 else{return 0}
        return zip(state.points,state.points.dropFirst()).reduce(0){sum,pair in
            let a=pair.0,b=pair.1,r=Double.pi/180
            let dlat=(b.latitude-a.latitude)*r,dlon=(b.longitude-a.longitude)*r
            let h=pow(sin(dlat/2),2)+cos(a.latitude*r)*cos(b.latitude*r)*pow(sin(dlon/2),2)
            return sum+6371000*2*atan2(sqrt(max(0,min(1,h))),sqrt(max(0,1-h)))
        }
    }
}
