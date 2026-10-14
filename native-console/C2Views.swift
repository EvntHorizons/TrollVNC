import SwiftUI
import MapKit
import AVKit

struct ExportItem:Identifiable {let id=UUID();let items:[Any]}
struct ExportSheet:UIViewControllerRepresentable {
    let items:[Any]
    func makeUIViewController(context:Context)->UIActivityViewController {UIActivityViewController(activityItems:items,applicationActivities:nil)}
    func updateUIViewController(_ c:UIActivityViewController,context:Context){}
}
struct Input:View {
    let title:String
    @Binding var text:String
    var body:some View {VStack(alignment:.leading,spacing:6){Text(title).font(.callout).foregroundColor(.secondary);TextField(title,text:$text).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true).accessibilityLabel(title)}}
}
struct C2Root:View {
    @StateObject var model=Model()
    @StateObject var station=Station()
    @StateObject var telemetry=Telemetry()
    @State var selected=0
    @State var exportItem:ExportItem?
    @Environment(\.scenePhase) var phase
    let pulse=Timer.publish(every:15,on:.main,in:.common).autoconnect()
    var body:some View {
        VStack(spacing:0){
            HStack(spacing:16){
                Image(systemName:"antenna.radiowaves.left.and.right").font(.title2).foregroundColor(.accentColor).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:3){Text("C2 Tablet").font(.title2.bold());Text("Diagnostic station").font(.caption).foregroundColor(.secondary)}
                Spacer()
                VStack(alignment:.trailing,spacing:3){Text(telemetry.linkState).font(.callout.weight(.semibold));Text("Tablet \(model.battery) · \(model.free) free").font(.caption).foregroundColor(.secondary)}
            }.padding(.horizontal,24).padding(.vertical,14)
            Divider()
            TabView(selection:$selected){
                StationView(model:model,station:station,telemetry:telemetry,export:share).tabItem{Label("Station",systemImage:"gauge")}.tag(0)
                LinksView(station:station,telemetry:telemetry,export:share).tabItem{Label("Links",systemImage:"antenna.radiowaves.left.and.right")}.tag(1)
                MissionView(station:station,export:share).tabItem{Label("Mission",systemImage:"map")}.tag(2)
                ToolkitView(model:model).tabItem{Label("Tools",systemImage:"wrench.and.screwdriver")}.tag(3)
                JournalView(model:model,station:station,export:share).tabItem{Label("Journal",systemImage:"book.closed")}.tag(4)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .accentColor(Color(UIColor{t in t.userInterfaceStyle == .dark ? UIColor(red:0.47,green:0.77,blue:0.96,alpha:1) : UIColor(red:0.13,green:0.40,blue:0.55,alpha:1)}))
        .preferredColorScheme(model.theme==0 ? nil : model.theme==1 ? .light : .dark)
        .sheet(item:$exportItem){ExportSheet(items:$0.items)}
        .onAppear{station.awake(true)}
        .onChange(of:station.keepAwake){_ in station.awake(phase == .active)}
        .onChange(of:phase){p in
            station.awake(p == .active)
            if p == .active {model.refresh();station.refreshArchives()}
            if p == .background {telemetry.stop();model.saveNotes()}
        }
        .onReceive(pulse){_ in if phase == .active {model.refresh()}}
    }
    func share(_ items:[Any]){exportItem=ExportItem(items:items)}
}

struct StationView:View {
    @ObservedObject var model:Model
    @ObservedObject var station:Station
    @ObservedObject var telemetry:Telemetry
    let export:([Any])->Void
    @State var brightness=UIScreen.main.brightness
    let columns=[GridItem(.adaptive(minimum:300),spacing:20,alignment:.top)]
    var thermal:String {
        switch ProcessInfo.processInfo.thermalState {case .nominal:return "Normal";case .fair:return "Warm";case .serious:return "Hot · reduce workload";case .critical:return "Critical · let tablet cool";@unknown default:return "Unknown"}
    }
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            LazyVGrid(columns:columns,spacing:20){
                Panel(title:"Tablet health"){
                    LabeledValue(name:"Battery",value:model.battery)
                    LabeledValue(name:"Free storage",value:model.free)
                    LabeledValue(name:"Thermal state",value:thermal)
                    LabeledValue(name:"System",value:"iPadOS \(UIDevice.current.systemVersion)")
                    LabeledValue(name:"Uptime",value:"\(Int(ProcessInfo.processInfo.systemUptime/60)) min")
                    ToolButton(title:"Save & share health report",symbol:"square.and.arrow.up"){model.refresh();model.archive(model.report());export([model.report()])}
                }
                Panel(title:"Connection readiness"){
                    Label(station.network,systemImage:"network")
                    LabeledValue(name:"Aircraft",value:telemetry.linkState)
                    LabeledValue(name:"Saved links",value:"\(station.state.profiles.count)")
                    LabeledValue(name:"Draft waypoints",value:"\(station.state.points.count)")
                    Text("Choose or save an endpoint in Links. A network connection alone does not confirm an aircraft connection.").font(.callout).foregroundColor(.secondary)
                    Text("Diagnostic release · aircraft commands unavailable").font(.callout.weight(.semibold))
                }
                Panel(title:"Field display"){
                    Picker("Appearance",selection:$model.theme){Text("Auto").tag(0);Text("Day").tag(1);Text("Night").tag(2)}.pickerStyle(.segmented).onChange(of:model.theme){UserDefaults.standard.set($0,forKey:"theme")}
                    Toggle("Keep screen awake in this app",isOn:$station.keepAwake)
                    Text("Brightness").font(.callout)
                    Slider(value:$brightness,in:0.1...1).accessibilityLabel("Screen brightness").onChange(of:brightness){UIScreen.main.brightness=$0}
                    Text("Screen lock returns to normal when you leave the app. Telemetry stops when the app enters the background.").font(.footnote).foregroundColor(.secondary)
                }
                Panel(title:"Workbench status"){
                    Label("Native app · tools run locally",systemImage:"ipad")
                    Label("No simulator installed",systemImage:"checkmark.circle")
                    Text("Notes, checklist, profiles and mission drafts work offline. Map imagery and remote video need a working source connection.").foregroundColor(.secondary)
                    Text("After a full restart, reapply Dopamine to restore jailbreak tools.").font(.footnote).foregroundColor(.secondary)
                }
            }
        }.padding(24)}
    }
}

struct LinksView:View {
    @ObservedObject var station:Station
    @ObservedObject var telemetry:Telemetry
    @StateObject var test=ConnectionTest()
    let export:([Any])->Void
    @State var name=""
    @State var host=""
    @State var port="5760"
    @State var udp="14550"
    @State var system="1"
    @State var component="1"
    @State var stream=""
    @State var record=false
    @State var message=""
    @State var player:AVPlayer?
    @State var videoStatus="No video open"
    @State var videoObservation:NSKeyValueObservation?
    @State var deleteProfile:LinkProfile?
    let columns=[GridItem(.adaptive(minimum:320),spacing:20,alignment:.top)]
    let readings=["Vehicle","Arm state","Custom mode","Aircraft battery","Voltage","GPS fix","Satellites","Latitude","Longitude","Relative altitude","Heading","Roll","Pitch","Yaw","Airspeed","Groundspeed","Climb"]
    var body:some View {
        ScrollView{VStack(spacing:20){
            LazyVGrid(columns:columns,spacing:20){
                profilePanel
                Panel(title:"Telemetry receiver"){
                    HStack{Input(title:"UDP listen port",text:$udp);Input(title:"System ID",text:$system);Input(title:"Component ID",text:$component)}.disabled(telemetry.active)
                    Toggle("Record supported packets",isOn:$record).disabled(telemetry.active)
                    ToolButton(title:telemetry.active ? "Stop receiver" : "Start receiver",symbol:telemetry.active ? "stop.circle" : "antenna.radiowaves.left.and.right"){
                        if telemetry.active {telemetry.stop();station.refreshArchives()} else {telemetry.start(port:udp,system:system,component:component,record:record)}
                    }
                    Text(telemetry.status).font(.callout)
                    Text(telemetry.linkState).font(.headline)
                    LabeledValue(name:"Accepted",value:"\(telemetry.received)")
                    LabeledValue(name:"Rejected / unsupported",value:"\(telemetry.rejected) / \(telemetry.unsupported)")
                    Text(telemetry.captureStatus).font(.footnote).foregroundColor(.secondary)
                    Text("Send MAVLink UDP from your bridge to this tablet’s Wi-Fi IP and listen port. View the IP in Tools → Network interfaces. Only the selected system/component is displayed; no commands or heartbeats are transmitted. Signed packets are rejected in this release.").font(.footnote).foregroundColor(.secondary)
                }
            }
            Panel(title:"Aircraft readings"){
                Text("Readings expire after 5 seconds without an update. A heartbeat confirms data reception, not readiness to fly.").font(.callout).foregroundColor(.secondary)
                LazyVGrid(columns:columns,spacing:4){ForEach(readings,id:\.self){key in LabeledValue(name:key,value:telemetry.display(key))}}
            }
            videoPanel
            Panel(title:"Aircraft messages"){
                if telemetry.messages.isEmpty {Text("No status messages received.").foregroundColor(.secondary)}
                ForEach(Array(telemetry.messages.enumerated()),id:\.offset){_,text in Text(text).font(.system(.callout,design:.monospaced)).textSelection(.enabled)}
            }
        }.padding(24)}
        .onDisappear{stopVideo()}
        .alert("Remove saved connection?",isPresented:Binding(get:{deleteProfile != nil},set:{if !$0{deleteProfile=nil}})){
            Button("Remove",role:.destructive){station.state.profiles.removeAll{$0.id==deleteProfile?.id};station.save();deleteProfile=nil}
            Button("Cancel",role:.cancel){deleteProfile=nil}
        }
    }
    var profilePanel:some View {
        Panel(title:"Saved connections"){
            if station.state.profiles.isEmpty {Text("Save your telemetry bridge or bench device when you have its address.").foregroundColor(.secondary)}
            ForEach(station.state.profiles){p in HStack{
                Button{load(p)}label:{VStack(alignment:.leading){Text(p.name).font(.headline);Text(p.host.isEmpty ? "UDP receiver profile" : p.host).font(.caption)}}.frame(minHeight:44)
                Spacer();Button{deleteProfile=p}label:{Image(systemName:"trash").frame(width:44,height:44)}.accessibilityLabel("Remove \(p.name)")
            }
            Input(title:"Connection name",text:$name)
            HStack{Input(title:"Host or IP (optional)",text:$host);Input(title:"TCP port",text:$port)}
            ToolButton(title:test.running ? "Checking…" : "Check TCP endpoint",symbol:"network"){test.test(host:host,port:port)}.disabled(test.running)
            Text(test.result).font(.callout).foregroundColor(.secondary)
            ToolButton(title:"Save connection",symbol:"plus.circle"){saveProfile()}
            if !message.isEmpty {Text(message).font(.callout)}
        }
    }
    var videoPanel:some View {
        Panel(title:"Camera link"){
            Input(title:"HLS stream or MP4 URL",text:$stream)
            Text("Native video preview for compatible HTTP(S) HLS/MP4 sources. RTSP and raw FPV radio feeds need a compatible bridge. Latency is source-dependent; this is not a piloting view.").font(.callout).foregroundColor(.secondary)
            HStack{
                ToolButton(title:"Open video",symbol:"video"){openVideo()}
                ToolButton(title:"Stop video",symbol:"stop.circle"){stopVideo()}.disabled(player == nil)
            }
            Text(videoStatus).font(.callout)
            if let p=player {VideoPlayer(player:p).frame(height:280)}
        }
    }
    func load(_ p:LinkProfile){
        guard !telemetry.active else {message="Stop the receiver before loading a different profile.";return}
        name=p.name;host=p.host;port=p.port;udp=p.udp;system=p.system;component=p.component;stream=p.stream;message="Loaded \(p.name)"
    }
    func saveProfile(){
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,let tp=UInt16(port),tp>0,let up=UInt16(udp),up>0,let s=UInt8(system),s>0,let c=UInt8(component),c>0 else {message="Enter a name, ports 1–65535 and IDs 1–255.";return}
        guard station.state.profiles.count<30 || station.state.profiles.contains(where:{$0.name==clean}) else {message="30 saved profiles maximum.";return}
        let p=LinkProfile(name:clean,host:host.trimmingCharacters(in:.whitespacesAndNewlines),port:port,udp:udp,system:system,component:component,stream:stream)
        if let i=station.state.profiles.firstIndex(where:{$0.name==clean}) {station.state.profiles[i]=p} else {station.state.profiles.append(p)}
        station.save();message=station.saveStatus
    }
    func stopVideo(){player?.pause();player=nil;videoObservation=nil;videoStatus="Video stopped"}
    func openVideo(){
        guard let url=URL(string:stream),["http","https"].contains(url.scheme ?? ""),url.host != nil,url.user == nil,url.password == nil else {videoStatus="Enter an HTTP(S) video address without embedded credentials.";return}
        stopVideo();let item=AVPlayerItem(url:url);let p=AVPlayer(playerItem:item);player=p;videoStatus="Opening video…"
        videoObservation=item.observe(\.status,options:[.initial,.new]){item,_ in DispatchQueue.main.async {
            if item.status == .readyToPlay {self.videoStatus="Source ready · playback controls below"}
            if item.status == .failed {self.videoStatus="Video unavailable: \(item.error?.localizedDescription ?? "Unsupported source")"}
        }}
        p.play()
    }
}

struct MissionView:View {
    @ObservedObject var station:Station
    let export:([Any])->Void
    @State var lat=""
    @State var lon=""
    @State var altitude=""
    @State var error=""
    @State var mapVisible=false
    @State var region=MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:0,longitude:0),span:MKCoordinateSpan(latitudeDelta:100,longitudeDelta:100))
    @State var deletePoint:UUID?
    @State var clear=false
    @State var surveyHeight=""
    @State var fov=""
    @State var overlap="70"
    let columns=[GridItem(.adaptive(minimum:320),spacing:20,alignment:.top)]
    var body:some View {
        ScrollView{VStack(spacing:20){
            Panel(title:"Mission draft"){
                Text("Plan coordinates for either aircraft type. These are local planning notes: no upload, terrain clearance, airspace checks, or aircraft performance validation.").foregroundColor(.secondary)
                LabeledValue(name:"Waypoints",value:"\(station.state.points.count)")
                LabeledValue(name:"Straight-line route",value:String(format:"%.2f km",station.routeDistance/1000))
                HStack{
                    ToolButton(title:mapVisible ? "Hide map" : "Show map",symbol:"map"){mapVisible.toggle();center()}
                    ToolButton(title:"Export GeoJSON draft",symbol:"square.and.arrow.up"){exportDraft()}.disabled(station.state.points.isEmpty)
                }
                if mapVisible {
                    Map(coordinateRegion:$region,annotationItems:station.state.points){point in MapPin(coordinate:CLLocationCoordinate2D(latitude:point.latitude,longitude:point.longitude),tint:.orange)}.frame(height:320).cornerRadius(8)
                    Button("Center on first waypoint"){center()}.frame(minHeight:44).disabled(station.state.points.isEmpty)
                    Text("Basemap needs network access; coordinates and drafts remain available offline.").font(.footnote).foregroundColor(.secondary)
                }
            }
            LazyVGrid(columns:columns,spacing:20){
                Panel(title:"Add waypoint"){
                    Input(title:"Latitude (−90 to 90)",text:$lat)
                    Input(title:"Longitude (−180 to 180)",text:$lon)
                    Input(title:"Planned altitude above launch (m)",text:$altitude)
                    ToolButton(title:"Add to draft",symbol:"mappin.and.ellipse"){add()}
                    if !error.isEmpty {Text(error).font(.callout)}
                }
                Panel(title:"Mapping estimate"){
                    Input(title:"Height above ground (m)",text:$surveyHeight)
                    Input(title:"Camera horizontal field of view (°)",text:$fov)
                    Input(title:"Side overlap (%)",text:$overlap)
                    Text(estimate).font(.callout)
                    Text("Flat ground, nadir camera, no lens distortion. An estimate only; this does not generate a survey mission.").font(.footnote).foregroundColor(.secondary)
                }
            }
            Panel(title:"Waypoint sequence"){
                if station.state.points.isEmpty {Text("No waypoints yet. Enter known coordinates above.").foregroundColor(.secondary)}
                ForEach(Array(station.state.points.enumerated()),id:\.element.id){i,p in
                    HStack{VStack(alignment:.leading,spacing:4){Text("Waypoint \(i+1)").font(.headline);Text(String(format:"%.6f, %.6f · %.1f m above launch",p.latitude,p.longitude,p.altitude)).font(.callout).textSelection(.enabled)};Spacer();Button{move(i,-1)}label:{Image(systemName:"arrow.up").frame(width:44,height:44)}.disabled(i==0).accessibilityLabel("Move waypoint \(i+1) earlier");Button{move(i,1)}label:{Image(systemName:"arrow.down").frame(width:44,height:44)}.disabled(i==station.state.points.count-1).accessibilityLabel("Move waypoint \(i+1) later");Button{deletePoint=p.id}label:{Image(systemName:"trash").frame(width:44,height:44)}.accessibilityLabel("Remove waypoint \(i+1)")}
                }
                Button("Clear draft",role:.destructive){clear=true}.frame(minHeight:44).disabled(station.state.points.isEmpty)
                Text(station.saveStatus).font(.footnote).foregroundColor(.secondary)
            }
        }.padding(24)}
        .alert("Remove waypoint?",isPresented:Binding(get:{deletePoint != nil},set:{if !$0{deletePoint=nil}})){
            Button("Remove",role:.destructive){station.state.points.removeAll{$0.id==deletePoint};station.save();deletePoint=nil};Button("Cancel",role:.cancel){deletePoint=nil}
        }
        .alert("Clear all draft waypoints?",isPresented:$clear){Button("Clear",role:.destructive){station.state.points=[];station.save()};Button("Cancel",role:.cancel){}}
    }
    var estimate:String {
        guard let h=Double(surveyHeight),h.isFinite,h>0,let f=Double(fov),f.isFinite,f>0,f<179,let o=Double(overlap),o.isFinite,o>=0,o<100 else {return "Enter height, camera field of view, and overlap to estimate coverage."}
        let width=2*h*tan(f*Double.pi/360)
        return String(format:"Ground footprint width: %.1f m\nApproximate lane spacing: %.1f m",width,width*(1-o/100))
    }
    func add(){
        guard let a=Double(lat),a.isFinite,abs(a)<=90,let b=Double(lon),b.isFinite,abs(b)<=180,let h=Double(altitude),h.isFinite,h>=0,h<=10000 else {error="Enter valid coordinates and an altitude from 0 to 10,000 m. The input limit is not flight authorization.";return}
        guard station.state.points.count<200 else{error="200 waypoints maximum per draft.";return}
        station.state.points.append(Waypoint(latitude:a,longitude:b,altitude:h));station.save();error=station.saveStatus;lat="";lon="";center()
    }
    func center(){if let p=station.state.points.first {region=MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:p.latitude,longitude:p.longitude),span:MKCoordinateSpan(latitudeDelta:0.02,longitudeDelta:0.02))}}
    func move(_ i:Int,_ step:Int){let j=i+step;guard station.state.points.indices.contains(j) else{return};station.state.points.swapAt(i,j);station.save()}
    func exportDraft(){
        do{let url=dataRoot.appendingPathComponent("mission-draft.geojson");try station.exportPlan().write(to:url,atomically:true,encoding:.utf8);export([url])}catch{error=error.localizedDescription}
    }
}

struct JournalView:View {
    @ObservedObject var model:Model
    @ObservedObject var station:Station
    let export:([Any])->Void
    @State var reset=false
    var body:some View {
        ScrollView{VStack(spacing:20){
            Panel(title:"Field notes"){
                TextEditor(text:$model.notes).frame(minHeight:240).font(.body).padding(8).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.secondary.opacity(0.4))).onChange(of:model.notes){_ in model.saveNotes()}.accessibilityLabel("Field notes")
                HStack{ToolButton(title:"Insert timestamp",symbol:"clock"){model.notes += "\n\n[\(ISO8601DateFormatter().string(from:Date()))]\n";model.saveNotes()};ToolButton(title:"Share notes",symbol:"square.and.arrow.up"){export([model.notes])}}
                Text(model.saveStatus).font(.footnote).foregroundColor(.secondary)
            }
            Panel(title:"Bench checklist"){
                Text("A reusable work record. Checked items do not certify flight readiness.").foregroundColor(.secondary)
                ForEach(Station.checks,id:\.self){item in Toggle(item,isOn:Binding(get:{station.state.checklist[item] ?? false},set:{station.state.checklist[item]=$0;station.save()})).padding(.vertical,4)}
                Button("Reset checklist"){reset=true}.frame(minHeight:44)
            }
            Panel(title:"Saved reports & captures"){
                Text("Keeps the newest 20 diagnostic reports and 5 telemetry captures. Captures contain the selected source’s supported, accepted packets only.").font(.callout).foregroundColor(.secondary)
                ToolButton(title:"Refresh saved files",symbol:"arrow.clockwise"){station.refreshArchives()}
                if station.archives.isEmpty {Text("Run a diagnostic or record telemetry to create a file.").foregroundColor(.secondary)}
                ForEach(station.archives,id:\.self){url in ToolButton(title:url.lastPathComponent,symbol:"square.and.arrow.up"){export([url])}}
            }
        }.padding(24)}.onAppear{station.refreshArchives()}
        .alert("Reset all checklist items?",isPresented:$reset){Button("Reset",role:.destructive){station.state.checklist=[:];station.save()};Button("Cancel",role:.cancel){}}
    }
}
