import XCTest
@testable import TalkBridgeCore

final class AudioRouteInfoTests: XCTestCase {
    func testRouteMapping() {
        XCTAssertEqual(AudioRouteInfo.from(portType: "BluetoothA2DPOutput", portName: "Kevin's AirPods Pro").kind, .airPods)
        XCTAssertEqual(AudioRouteInfo.from(portType: "BluetoothA2DPOutput", portName: "JBL Tune").kind, .bluetooth)
        XCTAssertEqual(AudioRouteInfo.from(portType: "BluetoothHFP", portName: "JBL Tune").kind, .bluetooth)
        XCTAssertEqual(AudioRouteInfo.from(portType: "BluetoothLE", portName: "Buds").kind, .bluetooth)
        XCTAssertEqual(AudioRouteInfo.from(portType: "Speaker", portName: "Speaker").kind, .speaker)
        XCTAssertEqual(AudioRouteInfo.from(portType: "Receiver", portName: "Receiver").kind, .receiver)
        XCTAssertEqual(AudioRouteInfo.from(portType: "Headphones", portName: "Headphones").kind, .headphones)
        XCTAssertEqual(AudioRouteInfo.from(portType: "USBAudio", portName: "USB-C").kind, .headphones)
        XCTAssertEqual(AudioRouteInfo.from(portType: "Weird", portName: "X").kind, .unknown)
        XCTAssertEqual(AudioRouteInfo.from(portType: "Speaker", portName: "Speaker").portName, "Speaker")
    }

    func testDisplayNames() {
        XCTAssertEqual(AudioOutputKind.airPods.displayName, "AirPods")
        XCTAssertEqual(AudioOutputKind.bluetooth.displayName, "藍牙耳機")
        XCTAssertEqual(AudioOutputKind.speaker.displayName, "手機喇叭")
        XCTAssertEqual(AudioOutputKind.receiver.displayName, "聽筒")
        XCTAssertEqual(AudioOutputKind.headphones.displayName, "有線耳機")
        XCTAssertEqual(AudioOutputKind.unknown.displayName, "未知")
    }

    func testHeadsetKinds() {
        XCTAssertTrue(AudioOutputKind.airPods.isHeadset)
        XCTAssertTrue(AudioOutputKind.bluetooth.isHeadset)
        XCTAssertTrue(AudioOutputKind.headphones.isHeadset)
        XCTAssertFalse(AudioOutputKind.speaker.isHeadset)
        XCTAssertFalse(AudioOutputKind.receiver.isHeadset)
        XCTAssertFalse(AudioOutputKind.unknown.isHeadset)
    }

    func testEverySymbolNameIsSet() {
        for kind in [AudioOutputKind.airPods, .bluetooth, .speaker, .receiver, .headphones, .unknown] {
            XCTAssertFalse(kind.symbolName.isEmpty)
        }
    }
}
