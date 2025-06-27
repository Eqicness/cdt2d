--!strict
--[[
Generates a unimonotone triangulation using a sweep-line algorithm.
This is the first major step in the CDT process.

Key Changes:
- [FIX] Corrected the loop bounds in `addPoint`. The original binary search logic is fragile and its direct translation could lead to loops with invalid start indices (e.g., 0). The loop is adjusted to handle the sentinels and search results correctly.
- [FIX] Added a guard in `splitHulls` to prevent errors if binary search doesn't find a hull to split.
- Converted JS classes `PartialHull` and `Event` to Luau types/tables.
- All indexing and loops are 1-based.
- Uses the `Utility.Robust.orientation3` for geometric tests.
- Uses the `Utility.BinarySearch` for locating items in the sweep-line status.
]]

local Types = require("./Types")
local Utility = require("./Utility")
local orient = Utility.Robust.orientation3
local BinarySearch = Utility.BinarySearch

-- Type definitions
type Edge = Types.Edge
type Cell = Types.Cell
type Point = Types.Point

-- Constants for event types in the sweep-line algorithm
local EVENT_POINT = 0
local EVENT_END = 1
local EVENT_START = 2

type Event = {
	a: Point,
	b: Point?,
	type: number,
	idx: number,
}

type PartialHull = {
	a: Point,
	b: Point,
	idx: number,
	lowerIds: { number },
	upperIds: { number },
}

local Point = Utility.Point

-- Comparison function for sorting events for the sweep-line.
local function compareEvent(a: Event, b: Event): boolean
	local d = a.a.X - b.a.X
	if d ~= 0 then return d < 0 end

	d = a.a.Y - b.a.Y
	if d ~= 0 then return d < 0 end

	d = a.type - b.type
	if d ~= 0 then return d < 0 end

	if a.type ~= EVENT_POINT then
		d = orient(a.a, a.b :: Point, b.b :: Point)
		if d ~= 0 then return d < 0 end
	end

	return (a.idx - b.idx) < 0
end

-- Test if a point is above or below a hull segment.
local function testPoint(hull: PartialHull, p: Point): number
	return orient(hull.a, hull.b, p)
end

-- Adds a point to the triangulation, connecting it to the visible hull segments.
local function addPoint(cells: { Cell }, hulls: { PartialHull }, points: { Point }, p: Point, idx: number)
	local lo = BinarySearch.lt(hulls, p, testPoint)
	local hi = BinarySearch.gt(hulls, p, testPoint)

	-- [FIX] Corrected loop bounds. The original JS `for(i=lo; i<hi; ++i)` is fragile.
	-- `lt` returns the last index < p, `gt` returns the first index > p.
	-- For a point between hull k and k+1, our 1-based search gets lo=k and hi=k+1.
	-- The equivalent loop is `for i = lo, hi - 1`, which correctly processes the single
	-- channel the point falls into.
	for i = lo, hi - 1 do
		local hull = hulls[i]
		if not hull then continue end

		-- Insert p into lower chain, triangulating as we go
		local lowerIds = hull.lowerIds
		local n = #lowerIds
		while n > 1 and orient(points[lowerIds[n - 1]], points[lowerIds[n]], p) > 0 do
			-- The orientation test is for (p(m-2), p(m-1), p(idx)) > 0, which is CCW.
			-- The original pushes (m-1, m-2, idx), which is CW. We replicate this.
			table.insert(cells, { lowerIds[n], lowerIds[n - 1], idx })
			table.remove(lowerIds)
			n -= 1
		end
		table.insert(lowerIds, idx)

		-- Insert p into upper chain, triangulating as we go
		local upperIds = hull.upperIds
		n = #upperIds
		while n > 1 and orient(points[upperIds[n - 1]], points[upperIds[n]], p) < 0 do
			-- The orientation test is for (p(m-2), p(m-1), p(idx)) < 0, which is CW.
			-- The original pushes (m-2, m-1, idx), which is also CW. We replicate this.
			table.insert(cells, { upperIds[n - 1], upperIds[n], idx })
			table.remove(upperIds)
			n -= 1
		end
		table.insert(upperIds, idx)
	end
end

-- Comparator to find where a new edge splits a hull.
local function findSplit(hull: PartialHull, edge: Event): number
	local d
	if hull.a.X < edge.a.X then
		d = orient(hull.a, hull.b, edge.a)
	else
		d = orient(edge.b :: Point, edge.a, hull.a)
	end
	if d ~= 0 then return d end

	if (edge.b :: Point).X < hull.b.X then
		d = orient(hull.a, hull.b, edge.b :: Point)
	else
		d = orient(edge.b :: Point, edge.a, hull.b)
	end
	return if d ~= 0 then d else (hull.idx - edge.idx)
end

-- Splits a hull segment when a constraint edge starts.
local function splitHulls(hulls: { PartialHull }, points: { Point }, event: Event)
	local splitIdx = BinarySearch.le(hulls, event, findSplit)
	-- [FIX] Add guard to prevent crash if no hull is found. `le` returns 0 if not found.
	if splitIdx == 0 then return end

	local hull = hulls[splitIdx]
	local upperIds = hull.upperIds
	local x = upperIds[#upperIds] -- The rightmost point of the upper chain
	hull.upperIds = { x }

	local newHull: PartialHull = {
		a = event.a,
		b = event.b :: Point,
		idx = event.idx,
		lowerIds = { x },
		upperIds = upperIds,
	}

	table.insert(hulls, splitIdx + 1, newHull)
end

-- Merges two hull segments when a constraint edge ends.
local function mergeHulls(hulls: { PartialHull }, points: { Point }, event: Event)
	-- Swap pointers to find the start of the edge
	event.a, event.b = event.b :: Point, event.a

	local mergeIdx = BinarySearch.eq(hulls, event, findSplit)
	-- Guard against merging the first hull or if the edge isn't found
	if mergeIdx <= 1 then return end

	local upper = hulls[mergeIdx]
	local lower = hulls[mergeIdx - 1]

	-- The lower hull's upper chain becomes the upper hull's upper chain
	lower.upperIds = upper.upperIds
	table.remove(hulls, mergeIdx)
end

local Monotone = {}

-- Main function to create the monotone triangulation.
function Monotone.triangulate(points: { Point }, edges: { Edge }): { Cell }
	local numPoints = #points
	local numEdges = #edges
	local events: { Event } = {}

	-- Create point events (indices are 1-based)
	for i = 1, numPoints do
		table.insert(events, { a = points[i], b = nil, type = EVENT_POINT, idx = i })
	end

	-- Create edge events (indices are 1-based)
	for i = 1, numEdges do
		local e = edges[i]
		local p1 = points[e[1]]
		local p2 = points[e[2]]

		if p1.X < p2.X then
			table.insert(events, { a = p1, b = p2, type = EVENT_START, idx = i })
			table.insert(events, { a = p2, b = p1, type = EVENT_END, idx = i })
		elseif p1.X > p2.X then
			table.insert(events, { a = p2, b = p1, type = EVENT_START, idx = i })
			table.insert(events, { a = p1, b = p2, type = EVENT_END, idx = i })
		end
	end

	-- Sort events lexicographically and by type
	table.sort(events, compareEvent)

	if #events == 0 then return {} end

	-- Initialize sweep-line status with sentinel hulls
	local minX = events[1].a.X - (1 + math.abs(events[1].a.X)) * 2.220446049250313e-16
	local hulls: { PartialHull } = {
		{ a = Point(minX, 1), b = Point(minX, 0), idx = -1, lowerIds = {}, upperIds = {} },
	}

	local cells: { Cell } = {}
	for _, event in ipairs(events) do
		if event.type == EVENT_POINT then
			addPoint(cells, hulls, points, event.a, event.idx)
		elseif event.type == EVENT_START then
			splitHulls(hulls, points, event)
		else -- EVENT_END
			mergeHulls(hulls, points, event)
		end
	end

	return cells
end

return Monotone
