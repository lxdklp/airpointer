import AppKit
import ApplicationServices

// Slides: while a presentation app is showing a slideshow in front, a tap on the case moves to the next slide and two
// quick taps go back one, with the arrow keys every slideshow understands. There is no setting: anywhere else, a tap clicks.
enum SlideKey:Equatable{
    case next,previous
    var keyCode:CGKeyCode{self == .next ? 124:123} // → and ←
}

enum SlideShow {
    static let apps:Set<String>=["com.apple.Keynote","com.apple.iWork.Keynote","com.microsoft.Powerpoint"]
    // A slideshow is a window of the front presentation app that covers a whole display, menu bar included, without being
    // a full-screen editing window: macOS gives those the AXFullScreen attribute, a slideshow's own window doesn't have it.
    static func isShowing(bundleID:String?,windowFrame:CGRect?,fullScreenWindow:Bool,displays:[CGRect])->Bool{
        guard let bundleID,apps.contains(bundleID),let windowFrame,!fullScreenWindow else{return false}
        return displays.contains{display in
            abs(display.minX-windowFrame.minX)<1 && abs(display.minY-windowFrame.minY)<1 &&
            abs(display.width-windowFrame.width)<1 && abs(display.height-windowFrame.height)<1
        }
    }
    // Reads the front app's focused window through Accessibility, which the pointer already needs.
    static func frontmostIsShowing()->Bool{
        guard AXIsProcessTrusted(),let front=NSWorkspace.shared.frontmostApplication,
              let bundleID=front.bundleIdentifier,apps.contains(bundleID) else{return false}
        let app=AXUIElementCreateApplication(front.processIdentifier)
        var value:CFTypeRef?
        guard AXUIElementCopyAttributeValue(app,kAXFocusedWindowAttribute as CFString,&value) == .success,
              let value,CFGetTypeID(value)==AXUIElementGetTypeID() else{return false}
        let window=value as! AXUIElement
        func attribute(_ name:String)->CFTypeRef?{
            var result:CFTypeRef?
            return AXUIElementCopyAttributeValue(window,name as CFString,&result) == .success ? result:nil
        }
        var origin=CGPoint.zero,size=CGSize.zero
        guard let position=attribute(kAXPositionAttribute),CFGetTypeID(position)==AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue,.cgPoint,&origin),
              let extent=attribute(kAXSizeAttribute),CFGetTypeID(extent)==AXValueGetTypeID(),
              AXValueGetValue(extent as! AXValue,.cgSize,&size) else{return false}
        let fullScreen=(attribute("AXFullScreen") as? Bool) ?? false
        // Accessibility and CGDisplayBounds share the same top-left global coordinates.
        var count:UInt32=0;CGGetActiveDisplayList(0,nil,&count)
        var ids=[CGDirectDisplayID](repeating:0,count:Int(count));CGGetActiveDisplayList(count,&ids,&count)
        return isShowing(bundleID:bundleID,windowFrame:CGRect(origin:origin,size:size),fullScreenWindow:fullScreen,displays:ids.map(CGDisplayBounds))
    }
    static func post(_ key:SlideKey){
        guard let down=CGEvent(keyboardEventSource:nil,virtualKey:key.keyCode,keyDown:true),
              let up=CGEvent(keyboardEventSource:nil,virtualKey:key.keyCode,keyDown:false) else{return}
        down.post(tap:.cghidEventTap);up.post(tap:.cghidEventTap)
    }
}

// One tap waits a moment for a second: alone it is the next slide, with a second it is the previous one. The wait is the
// cost of telling the two apart, and only slideshows pay it.
struct SlideTapGate {
    static let window=0.4
    private(set) var pendingSince:Double?
    // A tap at this time. Returns the slide to change now, if any.
    mutating func tap(at t:Double)->SlideKey?{
        if let since=pendingSince,t-since<=Self.window{pendingSince=nil;return .previous}
        let expired=poll(at:t);pendingSince=t;return expired
    }
    // A lone tap whose wait is over becomes the next slide.
    mutating func poll(at t:Double)->SlideKey?{
        guard let since=pendingSince,t-since>Self.window else{return nil}
        pendingSince=nil;return .next
    }
    mutating func cancel(){pendingSince=nil}
}

func runSlideControlChecks(){
    var gate=SlideTapGate()
    selfCheck(gate.tap(at:10)==nil && gate.poll(at:10.3)==nil && gate.poll(at:10.5) == .next && gate.poll(at:11)==nil,"one tap is the next slide once its wait is over")
    selfCheck(gate.tap(at:20)==nil && gate.tap(at:20.25) == .previous && gate.poll(at:21)==nil,"two quick taps are the previous slide, and nothing else")
    selfCheck(gate.tap(at:30)==nil && gate.tap(at:30.6) == .next && gate.poll(at:30.9)==nil && gate.poll(at:31.1) == .next,"a slow second tap is its own next slide")
    selfCheck(gate.tap(at:40)==nil && gate.tap(at:40.2) == .previous && gate.tap(at:40.35)==nil && gate.poll(at:40.8) == .next,"a third quick tap starts again")
    _=gate.tap(at:50);gate.cancel();selfCheck(gate.poll(at:51)==nil,"pausing drops a waiting tap")
    let display=CGRect(x:0,y:0,width:1512,height:982),side=CGRect(x:1512,y:-200,width:1920,height:1080)
    selfCheck(SlideShow.isShowing(bundleID:"com.apple.Keynote",windowFrame:display,fullScreenWindow:false,displays:[display,side]),"a Keynote window over a whole display is a slideshow")
    selfCheck(SlideShow.isShowing(bundleID:"com.microsoft.Powerpoint",windowFrame:side,fullScreenWindow:false,displays:[display,side]),"a slideshow on a second display counts")
    selfCheck(!SlideShow.isShowing(bundleID:"com.apple.Keynote",windowFrame:display,fullScreenWindow:true,displays:[display]),"full-screen editing is not a slideshow")
    selfCheck(!SlideShow.isShowing(bundleID:"com.apple.Keynote",windowFrame:CGRect(x:0,y:33,width:1512,height:949),fullScreenWindow:false,displays:[display]),"a zoomed editing window under the menu bar is not a slideshow")
    selfCheck(!SlideShow.isShowing(bundleID:"com.apple.Safari",windowFrame:display,fullScreenWindow:false,displays:[display]),"other apps keep clicking")
    selfCheck(!SlideShow.isShowing(bundleID:nil,windowFrame:display,fullScreenWindow:false,displays:[display]) && !SlideShow.isShowing(bundleID:"com.apple.Keynote",windowFrame:nil,fullScreenWindow:false,displays:[display]),"no app or no window is not a slideshow")
    selfCheck(SlideKey.next.keyCode==124 && SlideKey.previous.keyCode==123,"slides move with the arrow keys")
}
