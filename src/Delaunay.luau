--!strict
--[[
Refines a triangulation to be Delaunay using edge flipping.
This improves the quality of the triangles, making them less "skinny".

Key Changes:
- Uses the `Utility.Robust.inCircle` for the Delaunay check.
- Uses the `triangulation:opposite` method for clarity.
- A simple Luau table is used as a stack for edges to be flipped.
]]

local Utility = require("./Utility")
local inCircle = Utility.Robust.inCircle
local Triangulation = require("./Triangulation")
local Types = require("./Types")

type Triangulation = Triangulation.Triangulation
type Point = Types.Point

local Delaunay = {}

-- Helper to test if an edge needs flipping and add it to the stack.
local function testFlip(
	points: { Point },
	triangulation: Triangulation,
	stack: { number },
	a: number,
	b: number,
	x: number
)
	local y = triangulation:opposite(a, b)

	-- Don't flip boundary edges
	if y <= 0 then return end

	-- Swap edge if order flipped to maintain a consistent order for checking constraints.
	if b < a then
		local tmpA = a
		a = b
		b = tmpA
		local tmpX = x
		x = y
		y = tmpX
	end

	-- Don't flip constrained edges
	if triangulation:isConstraint(a, b) then return end

	-- If the edge is not locally Delaunay, add it to the stack to be flipped.
	-- The order of points for inCircle matters for the sign.
	if inCircle(points[a], points[b], points[x], points[y]) < 0 then
		table.insert(stack, a)
		table.insert(stack, b)
	end
end

-- Main function to perform Delaunay refinement.
function Delaunay.refine(points: { Point }, triangulation: Triangulation)
	local stack: { number } = {}
	local numPoints = #points

	-- Initial population of the stack with all non-Delaunay, non-constrained edges.
	local stars = triangulation.stars
	for a = 1, numPoints do
		local star = stars[a]
		-- Each pair in a star (star[j-1], star[j]) represents a triangle (a, star[j-1], star[j]).
		for j = 2, #star, 2 do
			local b = star[j]

			-- If order is not consistent, then skip edge to process each edge only once.
			if b < a then continue end

			-- Check if edge is constrained
			if triangulation:isConstraint(a, b) then continue end

			-- Find the two vertices opposite the edge (a,b).
			-- The first triangle is (a, star[j-1], b). So star[j-1] is one opposite vertex.
			local x = star[j - 1]
			local y = -1

			-- Search for the other triangle attached to edge (a,b). It will be of the form (a,b,y).
			-- This means in the star of 'a', we must find another pair containing 'b'.
			-- Specifically, we look for the pair (b, y).
			for k = 2, #star, 2 do
				if star[k - 1] == b then
					y = star[k]
					break
				end
			end

			-- if y <= 0, it's a boundary edge, don't flip it.
			if y > 0 and inCircle(points[a], points[b], points[x], points[y]) < 0 then
				table.insert(stack, a)
				table.insert(stack, b)
			end
		end
	end

	-- Process flips until the stack is empty
	while #stack > 0 do
		local b = table.remove(stack) :: number
		local a = table.remove(stack) :: number

		-- Find opposite vertices x and y for the edge (a, b).
		-- The two triangles are (a, x, b) and (a, b, y).
		local x, y = -1, -1
		local star = stars[a]
		for i = 2, #star, 2 do
			local s = star[i - 1] -- opposite
			local t = star[i] -- neighbor in the pair
			-- For triangle (a,x,b), the pair in star[a] is (x,b).
			if t == b then
				x = s
			-- For triangle (a,b,y), the pair in star[a] is (b,y).
			elseif s == b then
				y = t
			end
		end

		-- If we couldn't find both opposite vertices, it's a boundary edge.
		if x <= 0 or y <= 0 then continue end

		-- Re-check the Delaunay condition, as other flips may have fixed this edge
		if inCircle(points[a], points[b], points[x], points[y]) >= 0 then continue end

		-- Flip the edge (a, b) to (x, y)
		triangulation:flip(a, b)

		-- The flip affects adjacent edges. Add them to the stack for checking.
		testFlip(points, triangulation, stack, x, a, y)
		testFlip(points, triangulation, stack, a, y, x)
		testFlip(points, triangulation, stack, y, b, x)
		testFlip(points, triangulation, stack, b, x, y)
	end
end

return Delaunay
