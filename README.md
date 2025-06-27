# Constrained Delaunay Triangulation for Luau
> Translated to Luau from the [original library](https://github.com/mikolalysenko/cdt2d) by Mikola Lysenko

Fully functional, documentation & code cleanup WIP.

## Installation
Add `eqicness/cdt2d@0.1.0` to Wally dependencies

## Usage
```luau
CDT.triangulate(points: { Point }, edges: { Edge }?, options: CDTOptions?): { Cell }
```
- `points`: An array of Point objects ```{X: number, Y: number}```.
- `edges`: An array of constraint edges, e.g., {{1, 2}, {2, 3}}. Indices refer to the `points` array.
- `options`: A table with boolean flags:
```luau
CDTOptions: {
delaunay: boolean --(default: true): Perform Delaunay refinement.
interior: boolean --(default: true): Include triangles inside the constraints.
exterior: boolean --(default: true): Include triangles outside the constraints.
infinity: boolean --(default: false): Include "infinite" triangles for hull.
}
```