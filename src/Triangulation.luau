--!strict
--[[
Data structure for representing and manipulating a triangulation.

Key Changes:
- [FIX] Corrected a critical logic error in the `flip` method where the parameters to `removeTriangle` and `addTriangle` were swapped relative to the original JS. This was the primary cause of incomplete triangulations.
- Implemented as a Luau table "class" with methods.
- Uses 1-based indexing for vertex references.
- `isConstraint` uses the BinarySearch utility.
]]

local Types = require("./Types")
local Utility = require("./Utility")
local BinarySearch = Utility.BinarySearch

-- Type definitions
export type Edge = Types.Edge
export type Cell = Types.Cell

export type Triangulation = {
	stars: { { number } }, -- Adjacency lists for each vertex
	_edges: { Edge }, -- Sorted list of constraint edges
	-- Methods
	isConstraint: (self: Triangulation, i: number, j: number) -> boolean,
	removeTriangle: (self: Triangulation, i: number, j: number, k: number) -> (),
	addTriangle: (self: Triangulation, i: number, j: number, k: number) -> (),
	opposite: (self: Triangulation, i: number, j: number) -> number,
	flip: (self: Triangulation, i: number, j: number) -> (),
	cells: (self: Triangulation) -> { Cell },
	new: (numVerts: number, constraintEdges: { Edge }) -> Triangulation,
}

local Triangulation: Triangulation = {} :: Triangulation
(Triangulation :: any).__index = Triangulation

-- Helper to remove a j-k pair from a vertex's star list.
local function removePair(list: { number }, j: number, k: number)
	for i = 2, #list, 2 do
		-- The star's adjacency pairs are ordered (prev_neighbor, next_neighbor)
		-- to define the fan of triangles around a vertex. The check must be strict.
		if list[i - 1] == j and list[i] == k then
			-- Swap with the end and pop for efficiency
			local n = #list
			list[i - 1] = list[n - 1]
			list[i] = list[n]
			list[n] = nil
			list[n - 1] = nil
			return
		end
	end
end

-- Comparator for lexicographical edge sorting.
local function compareEdge(a: Edge, b: Edge): number
	local x = a[1] - b[1]
	if x ~= 0 then return x end
	return a[2] - b[2]
end

-- Checks if an edge is a constrained edge using binary search.
function Triangulation:isConstraint(i: number, j: number): boolean
	local key: Edge = { math.min(i, j), math.max(i, j) }
	return BinarySearch.eq(self._edges, key, compareEdge) > 0
end

-- Removes a triangle (i, j, k) from the triangulation.
-- Note: This assumes (i,j,k) has CW winding for pair removal.
function Triangulation:removeTriangle(i: number, j: number, k: number)
	removePair(self.stars[i], j, k)
	removePair(self.stars[j], k, i)
	removePair(self.stars[k], i, j)
end

-- Adds a triangle (i, j, k) to the triangulation.
-- Note: This assumes (i,j,k) has CW winding for pair storage.
function Triangulation:addTriangle(i: number, j: number, k: number)
	table.insert(self.stars[i], j)
	table.insert(self.stars[i], k)
	table.insert(self.stars[j], k)
	table.insert(self.stars[j], i)
	table.insert(self.stars[k], i)
	table.insert(self.stars[k], j)
end

-- Finds the vertex opposite to the edge (i, j).
-- `i` is the center vertex whose star is searched, `j` is the neighbor.
-- If star[i] has pair [k,j], it represents CW triangle (i,k,j).
-- The vertex opposite edge (i,j) is k.
function Triangulation:opposite(j: number, i: number): number
	local list = self.stars[i]
	for k = 2, #list, 2 do
		if list[k] == j then return list[k - 1] end
	end
	return -1 -- Sentinel for no opposite vertex (boundary edge)
end

-- Flips the edge (i, j) shared by two triangles.
function Triangulation:flip(i: number, j: number)
	-- `a` becomes the vertex opposite edge (j,i), from triangle (j, a, i).
	local a = self:opposite(i, j)
	-- `b` becomes the vertex opposite edge (i,j), from triangle (i, b, j).
	local b = self:opposite(j, i)

	if a <= 0 or b <= 0 then
		return -- Cannot flip boundary edges
	end

	-- [FIX] This is the corrected flip logic. The previous version had the 'a' and 'b'
	-- parameters swapped in the calls below, which corrupted the triangulation's
	-- adjacency information and led to an incomplete mesh. This version now
	-- correctly matches the robust logic from the original JS implementation.

	-- 1. Remove the two old triangles: (i,j,a) and (j,i,b).
	-- Note: removeTriangle is not order-dependent for vertices, but it constructs
	-- the ordered pairs to remove, so the calls must match the JS.
	self:removeTriangle(i, j, a)
	self:removeTriangle(j, i, b)

	-- 2. Add the two new triangles, forming an edge between the opposite vertices (a,b).
	-- The new triangles are (i,b,a) and (j,a,b).
	self:addTriangle(i, b, a)
	self:addTriangle(j, a, b)
end

-- Returns a list of all triangles (cells) in the triangulation.
function Triangulation:cells(): { Cell }
	local result = {}
	local stars = self.stars
	for i = 1, #stars do
		local list = stars[i]
		-- A star list should always have an even number of elements.
		-- This loop iterates over the pairs of adjacent vertices.
		for j = 1, #list, 2 do
			local s = list[j]
			local t = list[j + 1]
			-- Add triangle only once, using the smallest vertex index as the key
			if i < s and i < t then table.insert(result, { i, s, t }) end
		end
	end
	return result
end

-- Constructor for a new Triangulation object.
function Triangulation.new(numVerts: number, constraintEdges: { Edge }): Triangulation
	local stars = table.create(numVerts)
	for i = 1, numVerts do
		stars[i] = {}
	end

	return setmetatable(
		{
			stars = stars,
			_edges = constraintEdges, -- Assumes edges are already canonicalized and sorted
		} :: any,
		Triangulation
	) :: Triangulation
end

return Triangulation
