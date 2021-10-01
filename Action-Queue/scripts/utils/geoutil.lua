-- Returns a function which computes the barycentric coordinates of its input relative to (A, B, C).
-- A is taken to be the origin, with directions B-A and C-A.
local function BarycentricCoordinates(A, B, C)
    local v0 = C - A
    local v1 = B - A
    local dot00 = v0:Dot(v0)
    local dot01 = v0:Dot(v1)
    local dot11 = v1:Dot(v1)
    local scale = 1/(dot00*dot11 - dot01 * dot01)
    return function(P)
        local v2 = P - A
        local dot02 = v0:Dot(v2)
        local dot12 = v1:Dot(v2)
        local u = (dot11*dot02 - dot01*dot12)*scale
        local v = (dot00*dot12 - dot01*dot02)*scale
        return u, v
    end
end
-- Returns a function which tests if a point is in a given triangle.
local function NewTriangleTester(A, B, C)
    local coordsOf = BarycentricCoordinates(A, B, C)
    return function(P)
        local u, v = coordsOf(P)
        return u >= 0 and v >= 0 and u + v <= 1
    end
end
-- Returns a function which tests if a point is in a given quadrilateral.
local function NewQuadrilateralTester(A, B, C, D)
    local tritest1, tritest2 = NewTriangleTester(A, B, C), NewTriangleTester(C, D, A)
    return function(P)
        return tritest1(P) or tritest2(P)
    end
end

return {
    BarycentricCoordinates = BarycentricCoordinates,
    NewTriangleTester      = NewTriangleTester,
    NewQuadrilateralTester = NewQuadrilateralTester,
}
