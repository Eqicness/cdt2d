# Constrained Delaunay Triangulation for Luau
Translated to Luau from the [original library](https://github.com/mikolalysenko/cdt2d) by Mikola Lysenko

Fully functional, documentation WIP.

## Usage
```luau
CDT.triangulate(points: { Point }, edges: { Edge }?, options: CDTOptions?): { Cell }
```
- points: An array of Point objects ```{X: number, Y: number}```.
- edges: An array of constraint edges, e.g., {{1, 2}, {2, 3}}. Indices refer to the `points` array.
- options: A table with boolean flags:
- delaunay (default: true): Perform Delaunay refinement.
- interior (default: true): Include triangles inside the constraints.
- exterior (default: true): Include triangles outside the constraints.
- infinity (default: false): Include "infinite" triangles for hull.