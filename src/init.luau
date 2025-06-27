--!strict
--[[
Main entry point for the Constrained Delaunay Triangulation (CDT) library.
This module orchestrates the entire process:
1. Initial monotone triangulation respecting constraints.
2. Refinement to meet the Delaunay condition.
3. Filtering to extract interior, exterior, or all triangles.

API:
CDT.triangulate(points, edges, options)
- points: An array of Point objects {X, Y}.
- edges: An array of constraint edges, e.g., {{1, 2}, {2, 3}}.
Indices MUST BE 1-BASED and refer to the `points` array.
- options: A table with boolean flags:
- delaunay (default: true): Perform Delaunay refinement.
- interior (default: true): Include triangles inside the constraints.
- exterior (default: true): Include triangles outside the constraints.
- infinity (default: false): Include "infinite" triangles for convex hull.
]]

local Delaunay = require("@self/Delaunay")
local Filter = require("@self/Filter")
local Monotone = require("@self/Monotone")
local Triangulation = require("@self/Triangulation")
local Types = require("@self/Types")

-- Type definitions
export type Edge = Types.Edge
export type Cell = Types.Cell
export type Point = Types.Point
type Triangulation = Triangulation.Triangulation

type CDTOptions = {
	delaunay: boolean?,
	interior: boolean?,
	exterior: boolean?,
	infinity: boolean?,
}

local CDT = {}

-- Sorts an edge's vertices to be in ascending order.
local function canonicalizeEdge(e: Edge): Edge
	if e[1] < e[2] then return e end
	return { e[2], e[1] }
end

-- Comparator for lexicographical edge sorting.
local function compareEdge(a: Edge, b: Edge): boolean
	local d = a[1] - b[1]
	if d ~= 0 then return d < 0 end
	return (a[2] - b[2]) < 0
end

-- Main triangulation function.
function CDT.triangulate(points: { Point }, edges: { Edge }?, options: CDTOptions?): { Cell }
	local edges = edges or {} :: { Edge }
	local options = options or {} :: CDTOptions

	-- Parse options with defaults
	local delaunay = if options.delaunay ~= nil then options.delaunay else true
	local interior = if options.interior ~= nil then options.interior else true
	local exterior = if options.exterior ~= nil then options.exterior else true
	local infinity = if options.infinity ~= nil then options.infinity else false

	-- Handle trivial cases
	if (not interior and not exterior) or #points == 0 then return {} end

	-- STEP 1: Create an initial triangulation that respects constraints.
	local cells = Monotone.triangulate(points, edges)

	-- If delaunay refinement or filtering is needed, build the triangulation structure
	if delaunay or interior ~= exterior or infinity then
		-- STEP 2: Index the triangulation for efficient queries and manipulation.
		local canonicalEdges = {}
		for _, edge in ipairs(edges) do
			table.insert(canonicalEdges, canonicalizeEdge(edge))
		end
		table.sort(canonicalEdges, compareEdge)

		local triangulation = Triangulation.new(#points, canonicalEdges)
		for _, f in ipairs(cells) do
			triangulation:addTriangle(f[1], f[2], f[3])
		end

		-- STEP 3: Refine the mesh to be Delaunay (if requested).
		if delaunay then Delaunay.refine(points, triangulation) end

		-- STEP 4: Filter the triangles based on interior/exterior classification.
		if not exterior then
			-- Return only interior triangles (-1)
			return Filter.classify(triangulation, -1, false)
		elseif not interior then
			-- Return only exterior triangles (1)
			return Filter.classify(triangulation, 1, infinity)
		elseif infinity then
			-- Return all triangles plus infinite ones (0)
			return Filter.classify(triangulation, 0, infinity)
		else
			-- Return all finite triangles
			return triangulation:cells()
		end
	else
		-- If no advanced processing is needed, return the monotone triangulation.
		return cells
	end
end

return CDT
