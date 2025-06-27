-- Type definitions

-- Custom point is used for numerical precision (necessary)
-- Roblox's Vector2 does not have enough precision for this use case.
export type Point = { X: number, Y: number }

-- Should only ever have two indices
export type Edge = { number } -- 1-based vertex indices

-- Should have three indices (triangle)
export type Cell = { number }

return {}
