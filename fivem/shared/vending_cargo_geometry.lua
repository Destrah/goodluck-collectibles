-- Oriented bounding-box intersection, independent of FiveM natives (also used by geometry tests).
local geometry = {}; MetaComic.VendingCargoGeometry = geometry
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b) return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
-- Centre a separate part over its parent's top, accounting for both model origins.
function geometry.topAttachment(parentMin,parentMax,partMin,partMax)
    return {x=(parentMin.x+parentMax.x-partMin.x-partMax.x)/2,
        y=(parentMin.y+parentMax.y-partMin.y-partMax.y)/2,z=parentMax.z-partMin.z}
end
local function aabb(box)
    if box.aabb then return box.aabb end
    local radius = {x=0,y=0,z=0}
    for i=1,3 do
        for _,axis in ipairs({'x','y','z'}) do radius[axis]=radius[axis]+box.half[i]*math.abs(box.axes[i][axis]) end
    end
    box.aabb = radius
    return radius
end
function geometry.bounds(minimum, maximum, transform)
    local center = transform((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2,(minimum.z+maximum.z)/2)
    local axes, half = {}, {}
    for index, point in ipairs({ transform(maximum.x,(minimum.y+maximum.y)/2,(minimum.z+maximum.z)/2),
        transform((minimum.x+maximum.x)/2,maximum.y,(minimum.z+maximum.z)/2),
        transform((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2,maximum.z) }) do
        local axis = sub(point,center);local length = math.sqrt(dot(axis,axis))
        if length < 0.00001 then return end
        axes[index], half[index] = {x=axis.x/length,y=axis.y/length,z=axis.z/length}, length
    end
    return {center=center,axes=axes,half=half}
end
function geometry.intersects(a,b, clearance)
    local delta = sub(b.center,a.center)
    local ar, br = aabb(a), aabb(b)
    -- Most cargo is well inside the van: reject disjoint world-axis bounds before allocating SAT axes.
    for _,axis in ipairs({'x','y','z'}) do
        if math.abs(delta[axis]) > ar[axis]+br[axis]+(clearance or 0) then return false end
    end
    local axes = {}
    for i=1,3 do axes[#axes+1]=a.axes[i];axes[#axes+1]=b.axes[i] end
    for i=1,3 do for j=1,3 do axes[#axes+1]=cross(a.axes[i],b.axes[j]) end end
    for _,axis in ipairs(axes) do
        local length = math.sqrt(dot(axis,axis))
        if length > 0.00001 then
            local radius = (clearance or 0)*length
            for i=1,3 do radius=radius+a.half[i]*math.abs(dot(a.axes[i],axis))+b.half[i]*math.abs(dot(b.axes[i],axis)) end
            if math.abs(dot(delta,axis)) > radius then return false end
        end
    end
    return true
end
-- The rear door pivots inward across half the van opening, and opens toward its rear (-Y).
function geometry.door(hinge, direction, width, bottom, top, angle, maximumDegrees)
    local radians = math.rad(angle*(maximumDegrees or 110))
    local u = {x=direction*math.cos(radians),y=-math.sin(radians),z=0}
    local v = {x=math.sin(radians),y=direction*math.cos(radians),z=0}
    return {center={x=hinge.x+u.x*width/2,y=hinge.y+u.y*width/2,z=(bottom+top)/2},
        axes={u,v,{x=0,y=0,z=1}},half={width/2,0.025,(top-bottom)/2}}
end
function geometry.limit(boxes, hinge, direction, width, bottom, top, maximumDegrees, clearance)
    local candidates = {}
    local sweep = {center={x=hinge.x,y=hinge.y-width/2,z=(bottom+top)/2},
        axes={{x=1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=0,z=1}},half={width+0.025,width/2+0.025,(top-bottom)/2}}
    for _,box in ipairs(boxes) do if geometry.intersects(sweep,box,clearance or 0.02) then candidates[#candidates+1]=box end end
    if #candidates == 0 then return 0 end
    local last = nil
    -- Small angular steps check the sweep, including collisions between fully open and fully closed.
    for step=0,100 do
        local panel = geometry.door(hinge,direction,width,bottom,top,step/100,maximumDegrees)
        for _,box in ipairs(candidates) do
            if geometry.intersects(panel,box,clearance or 0.02) then last=step/100;break end
        end
    end
    return last and math.min(1,last+0.02) or 0
end
-- Sliding doors translate outward and rearward; they do not swing through the cargo bay.
function geometry.slidingLimit(boxes, panel, clearance)
    local c, h, t = panel.center, panel.halfSize, panel.travel
    if not c or not h or not t then return 0 end
    local last
    for step=0,100 do
        local phase = step/100
        -- Initial outward movement clears the body before sliding rearward.
        local outward = math.min(1,phase/0.15)
        local slide = math.max(0,(phase-0.15)/0.85)
        local box = {center={x=c.x+t.x*outward,y=c.y+t.y*slide,z=c.z+t.z*slide},
            axes={{x=1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=0,z=1}},half={h.x,h.y,h.z}}
        for _, cargo in ipairs(boxes) do
            if geometry.intersects(box,cargo,clearance or 0) then last=phase;break end
        end
    end
    return last and math.min(1,last+0.01) or 0
end
