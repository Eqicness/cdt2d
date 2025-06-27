--!strict
--[[
Utility module containing robust geometric predicates and binary search helpers.
Translated from various robust-arithmetic and binary-search JS packages.

Key Changes:
- [FIX] Binary search functions `lt` and `le` now correctly initialize their index variable to 0, ensuring a consistent "not found" return value for 1-based Luau indexing.
- Combines multiple JS utility packages into one organized Luau module.
- All array/table indexing is 1-based, conforming to Luau standards.
- Implements a single, flexible binary search utility.
- Refactors duplicated code from robust-sum and robust-subtract into a single helper.
]]
local Types = require("./Types")

local Utility = {}

-- Type definitions for clarity
type RobustNumber = { number }
type Point = Types.Point

-- Luau's equivalent for JS Number.EPSILON (2^-52) for double precision.
local EPSILON = 2.220446049250313e-16
local ERR_BOUND_3 = (3 + 16 * EPSILON) * EPSILON

--================------------------------------------------------==============
-- Binary Search
--================------------------------------------------------==============

Utility.BinarySearch = {}

-- Generic comparator function type
type Comparator<T, U> = (T, U) -> number

-- Finds the index of the last element strictly less than the value.
function Utility.BinarySearch.lt<T, U>(array: { T }, value: U, comparator: Comparator<T, U>): number
	local l, h = 1, #array
	-- [FIX] Initialize to 0. In Luau, 0 is a safe "not found" return for 1-based arrays.
	-- The original JS `l-1` would be 0 for the default `l=1`, but `i=0` is more explicit.
	local i = 0
	while l <= h do
		local m = (l + h) // 2
		if comparator(array[m], value) < 0 then
			i = m
			l = m + 1
		else
			h = m - 1
		end
	end
	return i
end

-- Finds the index of the last element less than or equal to the value.
function Utility.BinarySearch.le<T, U>(array: { T }, value: U, comparator: Comparator<T, U>): number
	local l, h = 1, #array
	-- [FIX] Initialize to 0 for a consistent "not found" return value.
	local i = 0
	while l <= h do
		local m = (l + h) // 2
		if comparator(array[m], value) <= 0 then
			i = m
			l = m + 1
		else
			h = m - 1
		end
	end
	return i
end

-- Finds the index of the first element strictly greater than the value.
function Utility.BinarySearch.gt<T, U>(array: { T }, value: U, comparator: Comparator<T, U>): number
	local l, h = 1, #array
	local i = h + 1
	while l <= h do
		local m = (l + h) // 2
		if comparator(array[m], value) > 0 then
			i = m
			h = m - 1
		else
			l = m + 1
		end
	end
	return i
end

-- Finds the index of the first element greater than or equal to the value.
function Utility.BinarySearch.ge<T, U>(array: { T }, value: U, comparator: Comparator<T, U>): number
	local l, h = 1, #array
	local i = h + 1
	while l <= h do
		local m = (l + h) // 2
		if comparator(array[m], value) >= 0 then
			i = m
			h = m - 1
		else
			l = m + 1
		end
	end
	return i
end

-- Finds the index of the first element equal to the value. Returns 0 if not found.
function Utility.BinarySearch.eq<T, U>(array: { T }, value: U, comparator: Comparator<T, U>): number
	local l, h = 1, #array
	while l <= h do
		local m = (l + h) // 2
		local p = comparator(array[m], value)
		if p == 0 then
			return m
		elseif p <= 0 then
			l = m + 1
		else
			h = m - 1
		end
	end
	return 0 -- Use 0 as "not found" to distinguish from index 1.
end

--================------------------------------------------------==============
-- Robust Geometric Predicates
--==============================================================================

Utility.Robust = {}

-- From two-product, used for robust multiplication.
local SPLITTER = 134217729 -- 2^27 + 1

-- Computes a * b as an exact sum of two floats (error, approximation).
-- Returns a table {error, approximation}.
local function twoProduct(a: number, b: number): { number }
	local x = a * b

	local c = SPLITTER * a
	local abig = c - a
	local ahi = c - abig
	local alo = a - ahi

	local d = SPLITTER * b
	local bbig = d - b
	local bhi = d - bbig
	local blo = b - bhi

	local err1 = x - (ahi * bhi)
	local err2 = err1 - (alo * bhi)
	local err3 = err2 - (ahi * blo)

	local y = alo * blo - err3

	return { y, x }
end

-- Shewchuk's Two-Sum algorithm. Computes a + b as an exact sum of two floats.
-- Returns a table {error, approximation}.
local function twoSum(a: number, b: number): { number }
	local x = a + b
	local bv = x - a
	local y = (a - (x - bv)) + (b - bv)
	return { y, x }
end

-- Internal helper for linearExpansionSum and robustSubtract to avoid code duplication.
-- Performs `e + (f * sign)`.
local function _linearExpansionOperation(e: RobustNumber, f: RobustNumber, sign: number): RobustNumber
	local ne = #e
	local nf = #f

	if ne == 1 and nf == 1 then
		local result = twoSum(e[1], sign * f[1])
		if result[1] ~= 0 then return result end
		return { result[2] }
	end

	local n = ne + nf
	local g = table.create(n)
	local count = 0
	local eptr, fptr = 1, 1

	local ei = e[eptr]
	local ea = math.abs(ei)
	local fi = sign * f[fptr]
	local fa = math.abs(fi)
	local a: number, b: number

	if ea < fa then
		b = ei
		eptr += 1
		if eptr <= ne then
			ei = e[eptr]
			ea = math.abs(ei)
		end
	else
		b = fi
		fptr += 1
		if fptr <= nf then
			fi = sign * f[fptr]
			fa = math.abs(fi)
		end
	end

	if (eptr <= ne and ea < fa) or (fptr > nf) then
		a = ei
		eptr += 1
		if eptr <= ne then
			ei = e[eptr]
			ea = math.abs(ei)
		end
	else
		a = fi
		fptr += 1
		if fptr <= nf then
			fi = sign * f[fptr]
			fa = math.abs(fi)
		end
	end

	local x, y, bv
	x = a + b
	bv = x - a
	y = b - bv
	local q0 = y
	local q1 = x

	while eptr <= ne and fptr <= nf do
		if ea < fa then
			a = ei
			eptr += 1
			if eptr <= ne then
				ei = e[eptr]
				ea = math.abs(ei)
			end
		else
			a = fi
			fptr += 1
			if fptr <= nf then
				fi = sign * f[fptr]
				fa = math.abs(fi)
			end
		end
		b = q0
		x = a + b
		bv = x - a
		y = b - bv
		if y ~= 0 then
			count += 1
			g[count] = y
		end

		local _x = q1 + x
		local _bv = _x - q1
		q0 = (q1 - (_x - _bv)) + (x - _bv)
		q1 = _x
	end

	while eptr <= ne do
		a = ei
		b = q0
		x = a + b
		bv = x - a
		y = b - bv
		if y ~= 0 then
			count += 1
			g[count] = y
		end

		local _x = q1 + x
		local _bv = _x - q1
		q0 = (q1 - (_x - _bv)) + (x - _bv)
		q1 = _x
		eptr += 1
		if eptr <= ne then ei = e[eptr] end
	end

	while fptr <= nf do
		a = fi
		b = q0
		x = a + b
		bv = x - a
		y = b - bv
		if y ~= 0 then
			count += 1
			g[count] = y
		end

		local _x = q1 + x
		local _bv = _x - q1
		q0 = (q1 - (_x - _bv)) + (x - _bv)
		q1 = _x
		fptr += 1
		if fptr <= nf then fi = sign * f[fptr] end
	end

	if q0 ~= 0 then
		count += 1
		g[count] = q0
	end
	if q1 ~= 0 then
		count += 1
		g[count] = q1
	end
	if count == 0 then
		count += 1
		g[count] = 0.0
	end

	-- Trim the table to the actual count
	for i = #g, count + 1, -1 do
		g[i] = nil
	end

	return g
end

-- Sum of two robust numbers
function Utility.Robust.sum(e: RobustNumber, f: RobustNumber): RobustNumber
	return _linearExpansionOperation(e, f, 1)
end

-- Subtraction of two robust numbers
function Utility.Robust.subtract(e: RobustNumber, f: RobustNumber): RobustNumber
	return _linearExpansionOperation(e, f, -1)
end

-- Scales a robust number by a scalar
function Utility.Robust.scale(e: RobustNumber, scale: number): RobustNumber
	local n = #e
	if n == 1 then
		local ts = twoProduct(e[1], scale)
		if ts[1] ~= 0 then return ts end
		return { ts[2] }
	end

	local g = table.create(2 * n)
	local count = 0

	local q = twoProduct(e[1], scale)
	if q[1] ~= 0 then
		count += 1
		g[count] = q[1]
	end

	for i = 2, n do
		local t = twoProduct(e[i], scale)
		local pq = q[2]
		local sum_q = twoSum(pq, t[1])
		if sum_q[1] ~= 0 then
			count += 1
			g[count] = sum_q[1]
		end

		local a = t[2]
		local b = sum_q[2]
		-- Fast-Two-Sum
		local x = a + b
		local bv = x - a
		local y = b - bv
		q = { y, x } -- Update q with the new error and approximation

		if q[1] ~= 0 then
			count += 1
			g[count] = q[1]
		end
	end

	if q[2] ~= 0 then
		count += 1
		g[count] = q[2]
	end
	if count == 0 then
		count += 1
		g[count] = 0.0
	end

	for i = #g, count + 1, -1 do
		g[i] = nil
	end

	return g
end

-- Exact orientation test for 3 points
local function orientation3Exact(p0: Point, p1: Point, p2: Point): number
	local m0 = { p0.X, p0.Y }
	local m1 = { p1.X, p1.Y }
	local m2 = { p2.X, p2.Y }

	local p = Utility.Robust.sum(
		Utility.Robust.sum(twoProduct(m1[2], m2[1]), twoProduct(-m2[2], m1[1])),
		Utility.Robust.sum(twoProduct(m0[2], m1[1]), twoProduct(-m1[2], m0[1]))
	)
	local n = Utility.Robust.sum(twoProduct(m0[2], m2[1]), twoProduct(-m2[2], m0[1]))
	local d = Utility.Robust.subtract(p, n)
	return d[#d]
end

-- Determines orientation of 3 points (c-cwise, cwise, or collinear).
-- Returns > 0 for counter-clockwise, < 0 for clockwise, 0 for collinear.
function Utility.Robust.orientation3(a: Point, b: Point, c: Point): number
	local l = (a.Y - c.Y) * (b.X - c.X)
	local r = (a.X - c.X) * (b.Y - c.Y)
	local det = l - r

	if l > 0 then
		if r <= 0 then return det end
	elseif l < 0 then
		if r >= 0 then return det end
	else
		return det
	end

	local s = math.abs(l) + math.abs(r)
	local tol = ERR_BOUND_3 * s
	if math.abs(det) >= tol then return det end

	return orientation3Exact(a, b, c)
end

-- Exact in-circle test for 4 points.
-- Returns > 0 if p3 is inside the circle defined by p0, p1, p2 (assuming p0,p1,p2 is CCW).
function Utility.Robust.inCircle(p0: Point, p1: Point, p2: Point, p3: Point): number
	local m0 = { p0.X, p0.Y }
	local m1 = { p1.X, p1.Y }
	local m2 = { p2.X, p2.Y }
	local m3 = { p3.X, p3.Y }

	local sum = Utility.Robust.sum
	local sub = Utility.Robust.subtract
	local scale = Utility.Robust.scale

	local w0 = sum(twoProduct(m0[1], m0[1]), twoProduct(m0[2], m0[2]))
	local w1 = sum(twoProduct(m1[1], m1[1]), twoProduct(m1[2], m1[2]))
	local w2 = sum(twoProduct(m2[1], m2[1]), twoProduct(m2[2], m2[2]))
	local w3 = sum(twoProduct(m3[1], m3[1]), twoProduct(m3[2], m3[2]))

	local w0m1 = scale(w0, m1[1])
	local w0m2 = scale(w0, m2[1])
	local w0m3 = scale(w0, m3[1])

	local w1m0 = scale(w1, m0[1])
	local w1m2 = scale(w1, m2[1])
	local w1m3 = scale(w1, m3[1])

	local w2m0 = scale(w2, m0[1])
	local w2m1 = scale(w2, m1[1])
	local w2m3 = scale(w2, m3[1])

	local w3m0 = scale(w3, m0[1])
	local w3m1 = scale(w3, m1[1])
	local w3m2 = scale(w3, m2[1])

	local p = sum(
		sum(scale(sub(w3m2, w2m3), m1[2]), sum(scale(sub(w3m1, w1m3), -m2[2]), scale(sub(w2m1, w1m2), m3[2]))),
		sum(scale(sub(w3m1, w1m3), m0[2]), sum(scale(sub(w3m0, w0m3), -m1[2]), scale(sub(w1m0, w0m1), m3[2])))
	)

	local n = sum(
		sum(scale(sub(w3m2, w2m3), m0[2]), sum(scale(sub(w3m0, w0m3), -m2[2]), scale(sub(w2m0, w0m2), m3[2]))),
		sum(scale(sub(w2m1, w1m2), m0[2]), sum(scale(sub(w2m0, w0m2), -m1[2]), scale(sub(w1m0, w0m1), m2[2])))
	)

	local d = sub(p, n)
	return d[#d]
end

function Utility.Point(x: number | { number }, y: number): Point
	if type(x) == "table" then
		-- If x is a table, assume it's a Vector2-like table
		return { X = x[1], Y = x[2] }
	end
	return { X = x, Y = y }
end

return Utility
