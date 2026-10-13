import SwiftUI
import UIKit
import Network
import Darwin

let dataRoot = URL(fileURLWithPath: "/var/mobile/Library/FieldConsole", isDirectory: true)
let projectRoot = URL(fileURLWithPath: "/var/mobile/Projects", isDirectory: true)
let ink = Color(red:0.10,green:0.17,blue:0.23)
let gold = Color(red:0.89,green:0.66,blue:0.30)

struct Project: Codable, Identifiable { var id = UUID(); var name: String; var address: String }
final class Model: ObservableObject {
    @Published var notes = ""
    @Published var projects: [Project] = []
    @Published var files: [String] = []
    @Published var free = "—"
    @Published var battery = "—"
    @Published var output = "Choose a diagnostic or run a Python project."
    @Published var busy = false
    @Published var saveStatus = "Saved locally"
    @Published var theme = 0
    init() {
        do {
            try FileManager.default.createDirectory(at:dataRoot,withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:projectRoot,withIntermediateDirectories:true)
            notes = (try? String(contentsOf:dataRoot.appendingPathComponent("notes.txt"))) ?? ""
            if let data=try? Data(contentsOf:dataRoot.appendingPathComponent("projects.json")), let saved=try? JSONDecoder().decode([Project].self,from:data) { projects=saved }
        } catch { saveStatus=error.localizedDescription }
        theme=UserDefaults.standard.integer(forKey:"theme")
        UIDevice.current.isBatteryMonitoringEnabled=true
        refresh()
    }
    func refresh() {
        if let a=try? FileManager.default.attributesOfFileSystem(forPath:"/var/mobile"), let bytes=a[.systemFreeSize] as? NSNumber { free=String(format:"%.2f GiB",bytes.doubleValue/1073741824) }
        let level=UIDevice.current.batteryLevel
        battery=level>=0 ? "\(Int(level*100))%" : "Unavailable"
        files=((try? FileManager.default.contentsOfDirectory(atPath:projectRoot.path)) ?? []).filter{$0.hasSuffix(".py")}.sorted()
    }
    func saveNotes() { do { try notes.write(to:dataRoot.appendingPathComponent("notes.txt"),atomically:true,encoding:.utf8);saveStatus="Saved on this iPad" } catch {saveStatus="Save failed: \(error.localizedDescription)"} }
    func saveProjects() { do { try JSONEncoder().encode(projects).write(to:dataRoot.appendingPathComponent("projects.json"),options:.atomic);saveStatus="Saved on this iPad" } catch {saveStatus=error.localizedDescription} }
    func run(_ path: String,_ argument: String) {
        guard !busy else {return};busy=true;output="Running…"
        DispatchQueue.global(qos:.userInitiated).async {
            let ptr=fc_run(path,argument);let text=ptr.map{String(cString:$0)} ?? "No output";freePointer(ptr)
            DispatchQueue.main.async {self.output=text;self.busy=false;self.refresh()}
        }
    }
    func createExample() {
        let url=projectRoot.appendingPathComponent("hello_field.py")
        guard !FileManager.default.fileExists(atPath:url.path) else {refresh();return}
        do {try "import platform, shutil\nprint('Hello from Field Console')\nprint(platform.platform())\nprint('Free bytes:', shutil.disk_usage('/var/mobile').free)\n".write(to:url,atomically:true,encoding:.utf8);refresh()} catch {output=error.localizedDescription}
    }
    func report() -> String {
        return "Field Console — \(Date())\niPad Air 2 / iPadOS \(UIDevice.current.systemVersion)\nFree storage: \(free)\nBattery: \(battery)\nUptime: \(Int(ProcessInfo.processInfo.systemUptime/60)) minutes\nProjects: \(projectRoot.path)\nJailbreak tools: \(FileManager.default.isExecutableFile(atPath:"/var/jb/usr/bin/python3") ? "available" : "unavailable")\n\nLast diagnostic:\n\(output)"
    }
}
func freePointer(_ pointer: UnsafeMutablePointer<CChar>?) { if let p=pointer { Darwin.free(p) } }

final class ConnectionTest: ObservableObject {
    @Published var result="Enter a host and port to test a single TCP connection."
    @Published var running=false
    private var connection:NWConnection?
    private var generation=UUID()
    func test(host:String,port:String) {
        guard let number=UInt16(port),number>0,!host.trimmingCharacters(in:.whitespaces).isEmpty else {result="Enter a host and a port between 1 and 65535.";return}
        connection?.cancel();generation=UUID();let id=generation
        let c=NWConnection(host:NWEndpoint.Host(host.trimmingCharacters(in:.whitespaces)),port:NWEndpoint.Port(rawValue:number)!,using:.tcp)
        connection=c;running=true;result="Connecting…";let start=Date()
        c.stateUpdateHandler = { [weak self] state in
            guard let self=self,self.generation==id,self.running else{return}
            switch state {
            case .ready:self.finish("Connected in \(Int(Date().timeIntervalSince(start)*1000)) ms. The TCP port is reachable.")
            case .failed(let error):self.finish("Connection failed: \(error.localizedDescription)")
            default:break
            }
        }
        c.start(queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self] in
            if let self=self,self.generation==id,self.running {self.finish("No connection within 5 seconds. Check the address, port, and network.")}
        }
    }
    func finish(_ message:String){result=message;running=false;connection?.cancel();connection=nil}
}

struct Share: UIViewControllerRepresentable {
    let text:String
    func makeUIViewController(context:Context)->UIActivityViewController {UIActivityViewController(activityItems:[text],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
struct ToolButton: View {
    let title:String;let symbol:String;let action:()->Void
    var body:some View {Button(action:action){Label(title,systemImage:symbol).font(.headline).frame(maxWidth:.infinity,minHeight:48,alignment:.leading)}.buttonStyle(.bordered)}
}
struct Panel<Content:View>:View {
    let title:String;@ViewBuilder var content:Content
    var body:some View {VStack(alignment:.leading,spacing:16){Text(title).font(.title2.bold());content}.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16)}
}
struct RootView:View {
    @StateObject var model=Model()
    @StateObject var test=ConnectionTest()
    @State var selected=0
    @State var host="127.0.0.1"
    @State var port="22"
    @State var projectName=""
    @State var projectURL=""
    @State var projectError=""
    @State var share=false
    @State var shareText=""
    @State var deleteID:UUID?
    @Environment(\.scenePhase) var phase
    let columns=[GridItem(.adaptive(minimum:340),spacing:20,alignment:.top)]
    func export(_ text:String){shareText=text;share=true}
    var body:some View {
        VStack(spacing:0) {
            HStack{Image(systemName:"slider.horizontal.3").font(.title).foregroundColor(gold);VStack(alignment:.leading){Text("Field Console").font(.title2.bold());Text("Native device utility").font(.caption).foregroundColor(.secondary)};Spacer();Button(action:model.refresh){Label("Refresh",systemImage:"arrow.clockwise")}.buttonStyle(.bordered)}.padding(.horizontal,28).padding(.vertical,16)
            TabView(selection:$selected) {
                device.tabItem{Label("Device",systemImage:"ipad")}.tag(0)
                diagnostics.tabItem{Label("Diagnostics",systemImage:"waveform.path.ecg")}.tag(1)
                projects.tabItem{Label("Projects",systemImage:"folder")}.tag(2)
                notes.tabItem{Label("Notes",systemImage:"square.and.pencil")}.tag(3)
            }
        }.background(Color(UIColor.systemGroupedBackground)).accentColor(Color(UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red:0.48,green:0.76,blue:0.94,alpha:1) : UIColor(red:0.12,green:0.38,blue:0.56,alpha:1) }))
        .preferredColorScheme(model.theme==0 ? nil : model.theme==1 ? .light : .dark)
        .sheet(isPresented:$share){Share(text:shareText)}
        .onChange(of:phase){if $0 == .active {model.refresh()} else {model.saveNotes()}}
    }
    var device:some View {
        ScrollView {VStack(spacing:20){
            LazyVGrid(columns:columns,spacing:20){
                Panel(title:"This iPad"){
                    LabeledValue(name:"System",value:"iPadOS \(UIDevice.current.systemVersion)")
                    LabeledValue(name:"Available storage",value:model.free)
                    LabeledValue(name:"Battery",value:model.battery)
                    LabeledValue(name:"Uptime",value:"\(Int(ProcessInfo.processInfo.systemUptime/60)) minutes")
                }
                Panel(title:"Device utilities"){
                    ToolButton(title:"Open terminal",symbol:"terminal"){openApp("ws.hbang.Terminal")}
                    ToolButton(title:"Manage packages",symbol:"shippingbox"){openApp("org.coolstar.SileoStore")}
                    ToolButton(title:"Open TrollStore",symbol:"app.badge"){openApp("com.opa334.TrollStore")}
                    ToolButton(title:"Open Dopamine",symbol:"wrench.and.screwdriver"){openApp("com.opa334.Dopamine")}
                }
            }
            Panel(title:"Display") {Picker("Appearance",selection:$model.theme){Text("Automatic").tag(0);Text("Day").tag(1);Text("Night").tag(2)}.pickerStyle(.segmented).onChange(of:model.theme){UserDefaults.standard.set($0,forKey:"theme")}}
            Text("Runs directly on the iPad. System tools require the active jailbreak. After a full restart, reapply Dopamine.").font(.footnote).foregroundColor(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(24)}
    }
    var diagnostics:some View {
        ScrollView {VStack(spacing:20){LazyVGrid(columns:columns,spacing:20){
            Panel(title:"Connection check") {
                Text("Test one TCP port from this iPad.").foregroundColor(.secondary)
                TextField("Hostname or IP",text:$host).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true).accessibilityLabel("Hostname or IP address")
                TextField("Port",text:$port).textFieldStyle(.roundedBorder).keyboardType(.numberPad).accessibilityLabel("TCP port")
                ToolButton(title:test.running ? "Connecting…" : "Check connection",symbol:"network"){test.test(host:host,port:port)}.disabled(test.running)
                Text(test.result).font(.callout).accessibilityIdentifier("connection-result")
            }
            Panel(title:"System checks") {
                ToolButton(title:"System information",symbol:"info.circle"){model.run("/var/jb/usr/bin/uname","-a")}.disabled(model.busy)
                ToolButton(title:"Storage usage",symbol:"internaldrive"){model.run("/var/jb/usr/bin/df","-h")}.disabled(model.busy)
                ToolButton(title:"Installed packages",symbol:"shippingbox"){model.run("/var/jb/usr/bin/dpkg-query","-W")}.disabled(model.busy)
                ToolButton(title:"Share device report",symbol:"square.and.arrow.up"){export(model.report())}
            }
        };Panel(title:"Diagnostic output") {Text(model.output).font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}.padding(24)}
    }
    var projects:some View {
        ScrollView {VStack(spacing:20){
            Panel(title:"Python projects"){
                Text(projectRoot.path).font(.system(.callout,design:.monospaced)).textSelection(.enabled)
                Text("Add .py files to this folder using SSH or the terminal. Runs stop after 15 seconds; results appear in Diagnostics.").foregroundColor(.secondary)
                ForEach(model.files,id:\.self){file in ToolButton(title:"Run \(file)",symbol:"play.circle"){model.run("/var/jb/usr/bin/python3",projectRoot.appendingPathComponent(file).path);selected=1}.disabled(model.busy)}
                ToolButton(title:"Create example project",symbol:"plus.circle"){model.createExample()}
            }
            Panel(title:"Project shortcuts"){
                if model.projects.isEmpty {Text("Save addresses for software you build or connect to later.").foregroundColor(.secondary)}
                ForEach(model.projects){p in HStack{Button{if let u=URL(string:p.address){UIApplication.shared.open(u)}}label:{VStack(alignment:.leading){Text(p.name).font(.headline);Text(p.address).font(.caption).foregroundColor(.secondary)}};Spacer();Button(role:.destructive){deleteID=p.id}label:{Image(systemName:"trash").padding(12)}.accessibilityLabel("Remove \(p.name)")}}
                TextField("Project name",text:$projectName).textFieldStyle(.roundedBorder)
                TextField("https:// or http:// address",text:$projectURL).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
                ToolButton(title:"Save shortcut",symbol:"plus"){addProject()}
                if !projectError.isEmpty {Text(projectError).foregroundColor(.secondary)}
                ToolButton(title:"Share project list",symbol:"square.and.arrow.up"){export(model.projects.map{"\($0.name)\n\($0.address)"}.joined(separator:"\n\n"))}
            }
        }.padding(24)}.alert("Remove shortcut?",isPresented:Binding(get:{deleteID != nil},set:{if !$0{deleteID=nil}})) {Button("Remove",role:.destructive){model.projects.removeAll{$0.id==deleteID};model.saveProjects();deleteID=nil};Button("Cancel",role:.cancel){deleteID=nil}}
    }
    var notes:some View {
        VStack(alignment:.leading,spacing:12){HStack{Text("Field notes").font(.title2.bold());Spacer();Button{export(model.notes)}label:{Label("Share notes",systemImage:"square.and.arrow.up")}.buttonStyle(.bordered)}
            Text("Saved as a local text file. No browser storage or server.").foregroundColor(.secondary)
            TextEditor(text:$model.notes).font(.body).padding(12).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12).onChange(of:model.notes){_ in model.saveNotes()}.accessibilityLabel("Field notes")
            Text(model.saveStatus).font(.footnote).foregroundColor(.secondary)
        }.padding(24)
    }
    func addProject(){guard !projectName.trimmingCharacters(in:.whitespaces).isEmpty,let url=URL(string:projectURL),let scheme=url.scheme,["http","https"].contains(scheme),url.host != nil else{projectError="Enter a name and a valid http or https address.";return};model.projects.append(Project(name:projectName,address:url.absoluteString));model.saveProjects();projectName="";projectURL="";projectError=model.saveStatus}
    func openApp(_ bundle:String) {
        DispatchQueue.global().async {
            // uiopen accepts a bundle identifier as a single positional argument.
            let ptr=fc_run("/var/jb/usr/bin/uiopen",bundle)
            let message=ptr.map{String(cString:$0)} ?? "Unable to open app";freePointer(ptr)
            DispatchQueue.main.async {model.output=message}
        }
    }
}
struct LabeledValue:View {let name:String;let value:String;var body:some View{HStack{Text(name).foregroundColor(.secondary);Spacer();Text(value).fontWeight(.semibold)}.padding(.vertical,6)}}
@main struct FieldConsoleApp:App {var body:some Scene{WindowGroup{RootView()}}}
