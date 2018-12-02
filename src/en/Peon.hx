package en;

class Peon extends Entity {
    public static var ALL : Array<Peon> = [];

    var grabbing = false;
    var speed = 1.0;
    var target : Null<CPoint>;
    var targetXr = 0.5;
    var path : Array<PathFinder.Node>;
    var dumbMode = true;
    public var invalidatePath = false;

    public function new(x,y) {
        super(x,y);
        ALL.push(this);
        hei = Const.GRID;
        spr.set("guy",1);
        spr.colorize(0x6633ee);
        speed = rnd(0.7,1);
        // lifter = true;
        path = [];
        cd.setS("turboLock",rnd(2.5,6));
    }

    override function dispose() {
        super.dispose();
        ALL.remove(this);
    }

    public function goto(x,y) {
        invalidatePath = false;
        path = level.pf.getPath(cx,cy, x,y);
        if( path.length>1 ) {
            dumbMode = false;
            path.shift();
            target = new CPoint(path[0].cx, path[0].cy);
            path.shift();
        }
        else {
            dumbMode = true;
            target = new CPoint(x,y);
        }
    }

    function grabAt(x,y) {
        setPosCase(x,y);
        grabbing = true;
        hasGravity = false;
        dx = dy = 0;
        xr = level.hasSpot("grabRight",cx,cy) ? 0.8 : 0.2;
        yr = 0.75;
        cd.setS("maintainGrab", rnd(0.4, 0.6));
    }


    override function checkLifters() {
        if( !grabbing && !Mob.anyoneHolds(this) )
            super.checkLifters();
    }

    function aiLocked() {
        return cd.has("stun") || cd.has("aiLock") || Mob.anyoneHolds(this);
    }

    public function onCatchByMob(e:Mob) {
        hasGravity = false;
        grabbing = false;
        dx = dy = 0;
    }

    public function onRelease() {
        hasGravity = true;
        dx = dy = 0;
        cd.setS("catchImmunity", 1);
    }

    override function canBeKicked():Bool {
        return !Mob.anyoneHolds(this);
    }

    override function onKick(by:Dynamic) {
        super.onKick(by);
        invalidatePath = true;
        cd.setS("stun",rnd(0.7,0.8));
    }

    override function postUpdate() {
        super.postUpdate();
        spr.alpha = isInLight() ? 1 : 0.7;
    }

    function pickTargetLight() {
        target = null;
        var dh = new DecisionHelper(Light.ALL);
        dh.keepOnly(function(e) return e.active);
        dh.score(function(e) return -e.cx);
        var nextLight = dh.getBest();
        if( nextLight!=null ) {
            fx.markerEntity(nextLight); // HACK
            var dh = new DecisionHelper(mt.deepnight.Bresenham.getDisc(nextLight.cx, nextLight.cy, Std.int(nextLight.radius/Const.GRID)));
            dh.keepOnly( function(pt) return !level.hasColl(pt.x,pt.y) && level.hasColl(pt.x,pt.y+1) );
            dh.score( function(pt) return -Lib.distance(nextLight.cx, nextLight.cy, pt.x, pt.y)*0.25 );
            dh.score( function(pt) return Lib.distance(nextLight.cx, nextLight.cy, pt.x, pt.y)<=1 ? -3 : 0 );
            dh.score( function(pt) return rnd(0,1) );
            var pt = dh.getBest();
            goto(pt.x, pt.y);
        }
    }

    override function update() {
        if( onGround && !isInLight() && !cd.hasSetS("pickLightTarget",4) )
            pickTargetLight();

        // Recompute path
        if( !aiLocked() && path.length>0 && onGround && invalidatePath ) {
            var last = path[path.length-1];
            goto(last.cx, last.cy);
        }

        if( !aiLocked() && !grabbing && target!=null ) {
            if( !cd.has("turboLock") ) {
                cd.setS("turbo",rnd(0.5,1.1));
                cd.setS("turboLock",rnd(2.5,6));
            }
            // Seek target
            if( !cd.has("walkLock") ) {
                var s = speed * 0.008 * (onGround?1:0.5) * ( isLiftingSomeone() ? 0.3 : 1) * (cd.has("turbo")?2:1);
                if( target.cx>cx || target.cx==cx && xr<0.5 ) {
                    dir = 1;
                    dx+=s*tmod;
                }
                if( target.cx<cx || target.cx==cx && xr>0.5 ) {
                    dir = -1;
                    dx-=s*tmod;
                }
            }

            // Jump (dumb mode)
            if( dumbMode && onGround && level.hasColl(cx+dir, cy) && ( dir==1 && xr>=0.7 || dir==-1 && xr<=0.3 ) && !cd.hasSetS("jump",rnd(0.3,0.7)) ) {
                dy = -0.23;
                dx = 0.2*dir;
                cd.setS("jumping", 0.10);
            }

            if( !dumbMode ) {
                // Normal jump
                if( onGround && target.cy==cy-1 && ( dir==1 && xr>=0.7 || dir==-1 && xr<=0.3 ) && !cd.hasSetS("jump",rnd(0.3,0.7)) ) {
                    dy = -0.21;
                    dx = 0.2*dir;
                    cd.unset("walkLock");
                    cd.setS("jumping", 0.10);
                }

                // High jump
                if( onGround && target.cy<cy-1 && ( dir==1 && xr>=0.6 || dir==-1 && xr<=0.4 ) && !cd.hasSetS("jump",rnd(0.2,0.4)) ) {
                    dy = -0.23;
                    dir = target.cx<cx ? -1 : 1;
                    if( target.cy==cy-1 && MLib.fabs(xr-0.5)<=0.2 )
                        dx = dir*0.1;
                    cd.setS("walkLock", 1);
                    cd.setS("jumping", 0.10);
                }
            }

            // Give up on impossible situations in Dumb Mode
            if( dumbMode && target.cx==cx && target.cy<cy )
                target = null;

            // Pick next point in path
            if( target!=null && cx==target.cx && cy==target.cy && MLib.fabs(xr-0.5)<=0.1 ) {
                if( path.length==0 )
                    target = null;
                else {
                    var next = path.shift();
                    target.set( next.cx, next.cy );
                }
            }

            #if debug
            if( Console.ME.hasFlag("pf") && target!=null )
                fx.markerCase(target.cx, target.cy, 0.2, 0x990000);
            #end
        }
        else if( !aiLocked() && !grabbing ) {
            // Wander
            if( !cd.hasSetS("wander", rnd(0.7,1)) )
                targetXr = rnd(0.1,0.9);
            if( isLiftingSomeone() )
                targetXr = xr;
             var s = speed * 0.004 * (onGround?1:0.5);
            if( MLib.fabs(xr-targetXr)>=0.1 ) {
                if( targetXr>xr ) {
                    dir = 1;
                    dx+=s*tmod;
                }
                if( targetXr<xr ) {
                    dir = -1;
                    dx-=s*tmod;
                }
            }
        }

        // Jump extra
        if( !onGround && cd.has("jumping") )
            dy-=0.042*tmod;

        super.update();

        // Ledge grabbing
        if( !aiLocked() && ( dumbMode || target!=null && target.cy<cy ) ) {
            if( dir==1 && level.hasSpot("grabRight",cx,cy) && dx>0 && dy>0 && xr>=0.6 && yr>=0.6 && !level.hasColl(cx+1,cy-1) )
                grabAt(cx,cy);
            if( dir==-1 && level.hasSpot("grabLeft",cx,cy) && dx<0 && dy>0 && xr<=0.4 && yr>=0.6 && !level.hasColl(cx-1,cy-1) )
                grabAt(cx,cy);
            if( dir==1 && level.hasSpot("grabRightUp",cx,cy) && dx>0 && dy>0 && xr>=0.7 && yr<=0.4 && !level.hasColl(cx,cy-1) && !level.hasColl(cx+1,cy-2) )
                grabAt(cx,cy-1);
            if( dir==-1 && level.hasSpot("grabLeftUp",cx,cy) && dx<0 && dy>0 && xr<=0.3 && yr<=0.4 && !level.hasColl(cx,cy-1) && !level.hasColl(cx-1,cy-2) )
                grabAt(cx,cy-1);
        }

        if( cd.has("stun") && grabbing )
            grabbing = false;

        // Leave grab
        if( grabbing && !cd.has("maintainGrab") ) {
            grabbing = false;
            hasGravity = true;
            dx = dir*0.16;
            dy = -0.17;
            cd.setS("jumping", 0.15);
        }

        // Stuck in wall
        if( level.hasColl(cx,cy) && !Mob.anyoneHolds(this) && !cd.hasSetS("stuckWallLimit",0.5) ) {
            var dh = new DecisionHelper( mt.deepnight.Bresenham.getDisc(cx,cy,3) );
            dh.keepOnly( function(pt) return !level.hasColl(pt.x,pt.y) && level.hasColl(pt.x,pt.y+1) );
            dh.score( function(pt) return -Lib.distance(cx,cy,pt.x,pt.y) );
            var pt = dh.getBest();
            if( pt!=null )
                setPosCase(pt.x, pt.y);
            else
                dy = -0.2;
        }
    }
}