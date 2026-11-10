import Foundation
import CoreGraphics

// Drag lock for the closed-case pointer. A tap on the case is one instant with nothing to hold down, so a drag
// is a toggle: three quick taps in one spot pick up (mouse down), moving the case drags, and the next tap drops
// (mouse up). The second tap of a pair could still become a pick-up, so while drag lock is on its double-click
// waits up to thirdTapWindow for a third tap. Without that wait, the double-click would open a file or zoom a
// window before it could be dragged. Single clicks are never delayed. Positions are in screen points.
struct ClosedCaseDragLock {
    enum Action:Equatable{case click(CGPoint,count:Int64),grab(CGPoint),drop(CGPoint)}
    static let nearby=8.0,thirdTapWindow=0.4
    var enabled=true{didSet{if !enabled{waiting=nil}}}
    private(set) var dragging=false
    private var last:(t:Double,at:CGPoint,count:Int64)?
    private var waiting:(t:Double,at:CGPoint)?

    private func near(_ a:CGPoint,_ b:CGPoint)->Bool{hypot(a.x-b.x,a.y-b.y)<Self.nearby}

    // A tap at `at` (screen points) at `now` (seconds). `interval` is the system double-click interval.
    mutating func tap(at:CGPoint,now:Double,interval:Double)->[Action]{
        if dragging{dragging=false;last=nil;waiting=nil;return [.drop(at)]}
        var actions:[Action]=[]
        if let held=waiting{
            waiting=nil
            if now-held.t<=Self.thirdTapWindow && near(held.at,at){dragging=true;last=nil;return [.grab(at)]}
            // Too late or too far for a pick-up: the held double-click goes out first.
            actions.append(.click(held.at,count:2));last=(held.t,held.at,2)
        }
        let count=last.map{now-$0.t<interval && near($0.at,at) ? $0.count+1:1} ?? 1
        if enabled && count==2{waiting=(now,at);return actions}
        last=(now,at,count)
        return actions+[.click(at,count:count)]
    }
    // Sends a held double-click once no third tap can come.
    mutating func tick(now:Double)->[Action]{
        guard let held=waiting,now-held.t>Self.thirdTapWindow else{return []}
        waiting=nil;last=(held.t,held.at,2)
        return [.click(held.at,count:2)]
    }
    // Another kind of click, such as a right-click, ends the series: a held double-click goes out first.
    mutating func interrupt()->[Action]{
        defer{waiting=nil;last=nil}
        return waiting.map{[.click($0.at,count:2)]} ?? []
    }
    // Pausing or ending forgets a held double-click and lets go of a drag. True when a drag was let go.
    mutating func cancel()->Bool{
        let was=dragging
        dragging=false;waiting=nil;last=nil
        return was
    }
}

func runDragLockChecks()throws {
    let a=CGPoint(x:100,y:100),b=CGPoint(x:103,y:101),far=CGPoint(x:300,y:300)
    func fail(_ why:String)->Error{LessonError.message("Drag lock: \(why)")}
    var lock=ClosedCaseDragLock()
    guard lock.tap(at:a,now:0,interval:0.5)==[.click(a,count:1)] else{throw fail("a single tap must click at once")}
    guard lock.tap(at:b,now:0.25,interval:0.5)==[],lock.tick(now:0.6)==[],lock.tick(now:0.66)==[.click(b,count:2)],lock.tick(now:0.7)==[] else{
        throw fail("a double tap must double-click once the third-tap window passes")
    }
    lock=ClosedCaseDragLock()
    _=lock.tap(at:a,now:0,interval:0.5);_=lock.tap(at:a,now:0.25,interval:0.5)
    guard lock.tap(at:b,now:0.5,interval:0.5)==[.grab(b)],lock.dragging,lock.tick(now:2)==[] else{throw fail("three quick taps must pick up")}
    guard lock.tap(at:far,now:3,interval:0.5)==[.drop(far)],!lock.dragging else{throw fail("the next tap must drop where the pointer is")}
    guard lock.tap(at:far,now:3.2,interval:0.5)==[.click(far,count:1)] else{throw fail("a tap after a drop is a fresh click")}
    lock=ClosedCaseDragLock()
    _=lock.tap(at:a,now:0,interval:0.5);_=lock.tap(at:a,now:0.25,interval:0.5)
    guard lock.tap(at:far,now:0.4,interval:0.5)==[.click(a,count:2),.click(far,count:1)],!lock.dragging else{
        throw fail("a third tap elsewhere sends the double-click, then clicks")
    }
    lock=ClosedCaseDragLock()
    _=lock.tap(at:a,now:0,interval:1);_=lock.tap(at:a,now:0.3,interval:1);_=lock.tick(now:0.71)
    guard lock.tap(at:a,now:0.9,interval:1)==[.click(a,count:3)],!lock.dragging else{throw fail("a slower third tap is a triple-click")}
    lock=ClosedCaseDragLock();lock.enabled=false
    guard lock.tap(at:a,now:0,interval:0.5)==[.click(a,count:1)],lock.tap(at:a,now:0.2,interval:0.5)==[.click(a,count:2)],
          lock.tap(at:a,now:0.4,interval:0.5)==[.click(a,count:3)],!lock.dragging else{throw fail("with drag lock off, clicks go out at once")}
    lock=ClosedCaseDragLock()
    _=lock.tap(at:a,now:0,interval:0.5);_=lock.tap(at:a,now:0.2,interval:0.5);_=lock.tap(at:a,now:0.4,interval:0.5)
    guard lock.cancel(),!lock.dragging,!lock.cancel() else{throw fail("a pause must let go of a drag once")}
    _=lock.tap(at:a,now:5,interval:0.5);_=lock.tap(at:a,now:5.2,interval:0.5)
    guard !lock.cancel(),lock.tick(now:9)==[] else{throw fail("a pause must forget a held double-click")}
    lock=ClosedCaseDragLock()
    _=lock.tap(at:a,now:0,interval:0.5);_=lock.tap(at:a,now:0.2,interval:0.5)
    guard lock.interrupt()==[.click(a,count:2)],lock.tick(now:1)==[],lock.interrupt()==[],
          lock.tap(at:a,now:0.5,interval:0.5)==[.click(a,count:1)] else{throw fail("a right-click must send a held double-click first and start a new series")}
}
