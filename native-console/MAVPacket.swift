import Foundation

struct MAVPacket {
    let message: Int
    let system: UInt8
    let component: UInt8
    let sequence: UInt8
    let payload: [UInt8]
    let raw: Data
    func u8(_ i: Int) -> UInt8 { i < payload.count ? payload[i] : 0 }
    func u16(_ i: Int) -> UInt16 { UInt16(u8(i)) | (UInt16(u8(i+1)) << 8) }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | (UInt32(u16(i+2)) << 16) }
    func i32(_ i: Int) -> Int32 { Int32(bitPattern:u32(i)) }
    func float(_ i: Int) -> Float { Float(bitPattern:u32(i)) }
}

// Small, explicitly supported subset of common.xml. Extra CRC and wire lengths
// follow the generated MAVLink common dialect. Unknown types are counted, not decoded.
final class MAVParser {
    static let definitions: [Int:(UInt8,Int,Int)] = [0:(50,9,9),1:(124,31,43),24:(24,30,52),30:(39,28,28),33:(104,28,28),74:(20,20,20),253:(83,51,54)]
    private var buffer = [UInt8]()
    private(set) var rejected = 0
    private(set) var unsupported = 0
    static func crc(_ bytes: [UInt8], extra: UInt8) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes + [extra] {
            var tmp = UInt16(byte) ^ (crc & 0xff)
            tmp ^= (tmp << 4) & 0xff
            crc = (crc >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)
        }
        return crc
    }
    func feed(_ data: Data) -> [MAVPacket] {
        buffer.append(contentsOf:data)
        if buffer.count > 131072 { buffer.removeAll(); rejected += 1; return [] }
        var packets = [MAVPacket]()
        var offset = 0
        while buffer.count-offset >= 2 {
            let magic=buffer[offset]
            guard magic == 0xfe || magic == 0xfd else {offset += 1;continue}
            let v2=magic == 0xfd, header=v2 ? 10 : 6, length=Int(buffer[offset+1])
            guard buffer.count-offset >= header else {break}
            let flags=v2 ? buffer[offset+2] : 0
            let total=header+length+2+((flags & 1) != 0 ? 13 : 0)
            guard buffer.count-offset >= total else {break}
            let bytes=Array(buffer[offset..<offset+total]);offset += total
            // No signing key exists in this release: never present signed traffic as trusted.
            guard flags == 0 else {rejected += 1;continue}
            let id=v2 ? Int(bytes[7]) | Int(bytes[8])<<8 | Int(bytes[9])<<16 : Int(bytes[5])
            guard let (extra,minLength,maxLength)=Self.definitions[id] else {unsupported += 1;continue}
            guard length <= maxLength, (v2 ? length >= 1 : length == minLength) else {rejected += 1;continue}
            let expected=UInt16(bytes[header+length]) | UInt16(bytes[header+length+1])<<8
            guard Self.crc(Array(bytes[1..<header+length]),extra:extra) == expected else {rejected += 1;continue}
            let sys=bytes[v2 ? 5 : 3],comp=bytes[v2 ? 6 : 4]
            guard sys > 0, comp > 0 else {rejected += 1;continue}
            packets.append(MAVPacket(message:id,system:sys,component:comp,sequence:bytes[v2 ? 4 : 2],payload:Array(bytes[header..<header+length]),raw:Data(bytes)))
        }
        if offset>0 {buffer.removeFirst(offset)}
        return packets
    }
}
