--!strict
--[[
Classifies faces of the triangulation as interior or exterior to the
constraint polygon boundaries. This is used to filter the final result.

Key Changes:
- [FIX] The canonicalization logic for triangles now perfectly matches the original JS
implementation. Instead of a full sort, it performs a rotation to place the smallest
vertex index first. This is critical because the subsequent flood-fill relies on
the specific edge ordering that this rotation preserves. The previous full-sort
approach broke this assumption, leading to incorrect filtering.
]]

local Utility = require("./Utility")
local BinarySearch = Utility.BinarySearch
local Triangulation = require("./Triangulation")
local Types = require("./Types")

-- Type definitions
type Cell = Types.Cell
type Triangulation = Triangulation.Triangulation

type FaceIndex = {
	cells: { Cell },
	neighbor: { number }, -- Adjacency info: neighbor[3*(i-1)+j] is neighbor of cell i's j-th edge
	constraint: { boolean }, -- True if an edge is a constraint
	flags: { number }, -- Classification flags (0: unclassified, 1: exterior, -1: interior)
	active: { number }, -- Queue for flood fill
	next: { number }, -- Queue for flood fill across constraints
	boundary: { Cell }?, -- Infinite faces for exterior triangulation
}

local Filter = {}

-- Comparator for sorting cells lexicographically.
local function compareCell(a: Cell, b: Cell): number
	local x = a[1] - b[1]
	if x ~= 0 then return x end
	local y = a[2] - b[2]
	if y ~= 0 then return y end
	return a[3] - b[3]
end

-- Locates the index of a triangle (a, b, c) in a sorted list of cells.
local function locate(index: FaceIndex, a: number, b: number, c: number): number
	-- If any vertex is invalid (e.g., from an edge with no opposite), the triangle doesn't exist.
	if a <= 0 or b <= 0 or c <= 0 then return -1 end

	-- [FIX] Canonicalize by rotation, not by sorting. This must match the canonicalization
	-- used to prepare the main cell list. It puts the smallest vertex first while preserving
	-- the relative cyclical order of the other two vertices.
	local x, y, z = a, b, c
	if b < c then
		if b < a then
			x, y, z = b, c, a
		end
	elseif c < a then
		x, y, z = c, a, b
	end

	local key: Cell = { x, y, z }
	return BinarySearch.eq(index.cells, key, compareCell)
end

-- Creates an indexed representation of the triangulation for fast traversal.
local function indexCells(triangulation: Triangulation, infinity: boolean): FaceIndex
	local cells = triangulation:cells()
	local nc = #cells

	-- [FIX] Canonicalize each cell by rotating the smallest vertex to the front. This is
	-- NOT a full sort. This specific rotation is required by the original algorithm's
	-- logic, as it preserves the edge ordering needed for neighbor finding.
	for _, c in ipairs(cells) do
		local x, y, z = c[1], c[2], c[3]
		if y < z then
			if y < x then
				c[1], c[2], c[3] = y, z, x
			end
		elseif z < x then
			c[1], c[2], c[3] = z, x, y
		end
	end
	table.sort(cells, function(a, b)
		return compareCell(a, b) < 0
	end)

	local flags = table.create(nc, 0)
	local neighbor = table.create(3 * nc)
	local constraint = table.create(3 * nc)
	local active: { number } = {}
	local nextQueue: { number } = {}
	local boundary = infinity and {} or nil

	local index: FaceIndex = {
		cells = cells,
		neighbor = neighbor,
		constraint = constraint,
		flags = flags,
		active = active,
		next = nextQueue,
		boundary = boundary,
	}

	for i = 1, nc do
		local c = cells[i]
		for j = 1, 3 do
			local p1 = c[j]
			-- `(j % 3) + 1` correctly cycles through {2, 3, 1} for j={1, 2, 3},
			-- giving the edges (p1,p2), (p2,p3), (p3,p1).
			local p2 = c[(j % 3) + 1]

			local oppVertex = triangulation:opposite(p2, p1)
			local neighborIdx = locate(index, p2, p1, oppVertex)
			local isConstraint = triangulation:isConstraint(p1, p2)

			local flatIdx = 3 * (i - 1) + j
			neighbor[flatIdx] = neighborIdx
			constraint[flatIdx] = isConstraint

			if neighborIdx <= 0 then -- This is a boundary edge of the mesh
				if isConstraint then
					table.insert(nextQueue, i)
				else
					table.insert(active, i)
					flags[i] = 1 -- Assume unconstrained boundary is exterior
				end
				if boundary then table.insert(boundary, { p2, p1, -1 }) end
			end
		end
	end

	return index
end

-- Filters cells based on their classification flag.
local function filterCells(cells: { Cell }, flags: { number }, target: number): { Cell }
	local n = 1
	for i = 1, #cells do
		if flags[i] == target then
			cells[n] = cells[i]
			n += 1
		end
	end
	-- Trim the table to the new size
	for i = #cells, n, -1 do
		cells[i] = nil
	end
	return cells
end

-- Main function to classify and filter faces.
function Filter.classify(triangulation: Triangulation, target: number, infinity: boolean)
	local index = indexCells(triangulation, infinity)

	-- Target 0 means return everything (no filtering)
	if target == 0 then
		if infinity and index.boundary then
			local new = table.clone(index.cells)
			table.move(index.boundary, 1, #index.boundary, #new + 1, new)
			return new
		end
		return index.cells
	end

	local side = 1 -- 1 for exterior, -1 for interior
	local active = index.active
	local nextQueue = index.next
	local flags = index.flags

	while #active > 0 or #nextQueue > 0 do
		-- Flood fill across non-constrained edges
		while #active > 0 do
			local t = table.remove(active) :: number
			if flags[t] == -side then continue end
			flags[t] = side

			for j = 1, 3 do
				local flatIdx = 3 * (t - 1) + j
				local f = index.neighbor[flatIdx]
				if f > 0 and flags[f] == 0 then
					if index.constraint[flatIdx] then
						table.insert(nextQueue, f)
					else
						flags[f] = side
						table.insert(active, f)
					end
				end
			end
		end

		-- Swap queues, flip the side, and continue flood fill across constraint boundaries
		local tmp = nextQueue
		nextQueue = active
		active = tmp
		table.clear(nextQueue)
		side = -side
	end

	local result = filterCells(index.cells, index.flags, target)
	if infinity and index.boundary then
		-- Replicate original JS behavior: create a new table and concatenate
		local clonedResult = table.create(#result + #index.boundary)
		table.move(result, 1, #result, 1, clonedResult)
		table.move(index.boundary, 1, #index.boundary, #result + 1, clonedResult)
		return clonedResult
	end
	return result
end

return Filter
