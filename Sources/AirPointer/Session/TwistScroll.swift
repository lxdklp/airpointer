import Foundation

// Twist-to-scroll. Turn the case about the way it points, like a key, and the page scrolls; turn back and
// pointing resumes. Twisting is measured from this person's own resting twist, a baseline that follows how
// they hold the case: many grips already sit 15° or so off the calibrated pose, which an absolute threshold
// mistakes for a scroll. Moving the arm also rolls the wrist, so a scroll starts only from a deliberate twist:
// at least minimumTwistIn degrees within `window`, much more than the aim moved, ending `start` degrees from
// the baseline. A twist that drifts there slowly, or arrives with a sweep of the cursor, is ignored.
// (Twist-to-scroll itself, its pixel rate and its direction come from musubipapi/airpointer#12.)
struct ClosedCaseTwistScroll {
    enum Event:Equatable{case started(twist:Double,baseline:Double,twistIn:Double,aimIn:Double),ended,ignored(String)}
    static let start=20.0,stop=12.0,minimumTwistIn=8.0,window=0.3,dominance=1.5
    // The baseline follows the grip within calmTau, and all but stops (heldTau) while the case is twisting
    // quickly, so a deliberate twist isn't soaked up but a slow change of grip is.
    static let calmTau=3.0,heldTau=30.0
    // Pixels per second for each degree past `stop`.
    static let pixelsPerDegree=25.0
    var reverse=false
    private(set) var scrolling=false,baseline:Double?,rate=0.0
    private var history:[(t:Double,twist:Double,swing:SIMD3<Double>)]=[]
    private var lastIgnored = -Double.infinity

    mutating func reset()->[Event]{
        history=[];rate=0
        guard scrolling else{return []}
        scrolling=false;return [.ended]
    }
    private func pixelRate(_ residual:Double)->Double{
        let sign:Double=(residual>0) != reverse ? -1:1
        return sign*Self.pixelsPerDegree*max(0,abs(residual)-Self.stop)
    }
    // One motion sample: seconds, twist in degrees, the rest of the aim as a rotation in degrees. Blocked while
    // a tap holds the pointer, during a drag, or while pointing is off: a scroll ends and nothing is learned.
    mutating func feed(t:Double,twist:Double,swing:SIMD3<Double>,blocked:Bool)->[Event]{
        guard t.isFinite,twist.isFinite,swing.x.isFinite,swing.y.isFinite,swing.z.isFinite else{return []}
        if blocked{return reset()}
        let previous=history.last
        if let previous,t<=previous.t{return []}
        history.append((t,twist,swing))
        while let first=history.first,t-first.t>Self.window+0.1{history.removeFirst()}
        guard let base=baseline,let previous else{if baseline==nil{baseline=twist};return []}
        let residual=twist-base
        if scrolling{
            if abs(residual)<Self.stop{scrolling=false;rate=0;return [.ended]}
            rate=pixelRate(residual);return []
        }
        var events:[Event]=[]
        let past=history.first(where:{t-$0.t<=Self.window}) ?? previous
        let turned=twist-past.twist,twistIn=abs(turned)
        if abs(residual)>=Self.start{
            let aimIn=((swing-past.swing)*(swing-past.swing)).sum().squareRoot()
            if twistIn>=Self.minimumTwistIn,twistIn>=Self.dominance*aimIn,(turned>0)==(residual>0){
                scrolling=true;rate=pixelRate(residual)
                return [.started(twist:twist,baseline:base,twistIn:twistIn,aimIn:aimIn)]
            }
            if t-lastIgnored>=1{
                lastIgnored=t
                events.append(.ignored(twistIn<Self.minimumTwistIn ?
                    String(format:"twist %.0f° from baseline %.0f° arrived slowly, %.0f° in %.1f s",residual,base,twistIn,Self.window):
                    String(format:"twist %.0f° from baseline %.0f° came with aiming, %.0f° of twist and %.0f° of aim in %.1f s",residual,base,twistIn,aimIn,Self.window)))
            }
        }
        let tau=twistIn>=Self.minimumTwistIn/2 ? Self.heldTau:Self.calmTau
        baseline=base+residual*(1-exp(-(t-previous.t)/tau))
        return events
    }
}

func runTwistScrollChecks()throws {
    func fail(_ why:String)->Error{LessonError.message("Twist-to-scroll: \(why)")}
    // Feeds 100 Hz samples from `from` to `to` seconds, with twist and swing as functions of time.
    func run(_ scroll:inout ClosedCaseTwistScroll,_ from:Double,_ to:Double,twist:(Double)->Double,swing:(Double)->SIMD3<Double>={_ in .zero},blocked:Bool=false)->[ClosedCaseTwistScroll.Event]{
        var events:[ClosedCaseTwistScroll.Event]=[],t=from
        while t<to-1e-9{events+=scroll.feed(t:t,twist:twist(t),swing:swing(t),blocked:blocked);t+=0.01}
        return events
    }
    func started(_ events:[ClosedCaseTwistScroll.Event])->Bool{events.contains{if case .started=$0{return true};return false}}
    let wobble={(t:Double)->Double in 0.6*sin(t*7)}

    // A grip that sits 15° off the calibrated pose, aiming around slowly, never scrolls.
    var scroll=ClosedCaseTwistScroll()
    guard !started(run(&scroll,0,5,twist:{-15+wobble($0)},swing:{SIMD3(10*sin($0),5*cos($0*0.7),0)})),!scroll.scrolling else{throw fail("a twisted resting grip must not scroll")}
    // A fast sweep that rolls the wrist 25° along with 50° of aim doesn't scroll, nor does holding where it ended.
    let sweep=run(&scroll,5,5.4,twist:{-15+25*($0-5)/0.4},swing:{SIMD3(50*($0-5)/0.4,0,0)})
    let after=run(&scroll,5.4,6.5,twist:{_ in 10},swing:{_ in SIMD3(50,0,0)})
    guard !started(sweep),!started(after),!scroll.scrolling else{throw fail("aiming that rolls the wrist must not scroll")}
    guard (sweep+after).contains(where:{if case .ignored=$0{return true};return false}) else{throw fail("a near miss should be logged")}

    // A deliberate twist from a settled grip scrolls; further twists scroll faster; turning back stops it.
    scroll=ClosedCaseTwistScroll()
    _=run(&scroll,0,3,twist:{wobble($0)})
    let twistIn=run(&scroll,3,3.25,twist:{30*($0-3)/0.25},swing:{SIMD3(2*($0-3)/0.25,0,0)})
    guard started(twistIn),scroll.scrolling else{throw fail("a deliberate twist must scroll")}
    _=run(&scroll,3.25,4,twist:{_ in 30})
    guard let base=scroll.baseline,abs(scroll.rate+25*(30-base-12))<1,scroll.rate<0 else{throw fail("the rate must grow with the twist past the stop edge")}
    let back=run(&scroll,4,4.25,twist:{30-30*($0-4)/0.25})
    guard back.contains(.ended),!scroll.scrolling,scroll.rate==0 else{throw fail("turning back must stop scrolling")}
    // The other way scrolls the other way, and Reverse swaps both.
    _=run(&scroll,4.25,6,twist:{_ in 0})
    _=run(&scroll,6,6.25,twist:{-30*($0-6)/0.25})
    guard scroll.scrolling,scroll.rate>0 else{throw fail("twisting the other way must scroll the other way")}
    scroll.reverse=true;_=run(&scroll,6.25,6.3,twist:{_ in -30})
    guard scroll.rate<0 else{throw fail("Reverse must swap the direction")}

    // A grip that drifts 25° over six seconds is learned, not scrolled.
    scroll=ClosedCaseTwistScroll()
    guard !started(run(&scroll,0,6,twist:{25*$0/6})),let drifted=scroll.baseline,drifted>8 else{throw fail("a slow change of grip must move the baseline, not scroll")}
    guard !started(run(&scroll,6,20,twist:{_ in 25})),let settled=scroll.baseline,abs(settled-25)<5 else{throw fail("a held new grip must become the baseline")}

    // A tap's hold, a drag or a pause ends a scroll.
    scroll=ClosedCaseTwistScroll()
    _=run(&scroll,0,2,twist:{_ in 0});_=run(&scroll,2,2.2,twist:{30*($0-2)/0.2})
    guard scroll.scrolling,run(&scroll,2.2,2.25,twist:{_ in 30},blocked:true)==[.ended],!scroll.scrolling else{throw fail("blocking must end a scroll")}
    guard scroll.reset()==[] else{throw fail("ending twice must report once")}
}
