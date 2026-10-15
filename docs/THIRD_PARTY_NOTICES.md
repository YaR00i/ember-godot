# Third-party notices

## NGNT/treegen-pinegen

The large voxel tree generator in
`addons/ember_import/ember_voxel_large_tree_generator.gd` adapts algorithmic
ideas from [NGNT/treegen-pinegen](https://github.com/NGNT/treegen-pinegen):
seeded recursive branching, tapered voxel lines and foliage grown around branch
tips. Ember uses a separate bounded sparse implementation and its own Resource,
palette, collision and editor lifecycle.

MIT License

Copyright (c) 2025 NGNT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## TheRealSarin/tree-gen

The opt-in21 support planner in `addons/ember_import/ember_tree_branch_layout.gd`
adapts recursive child growth, depth-dependent length/radius falloff and seeded
variation from `_grow`, `_child_length`, `_child_radius` at
[commit aacb4cfe](https://github.com/TheRealSarin/tree-gen/blob/aacb4cfec66c8c985a3552057379c2a4be776d43/script/tree_gen.gd).
The Ember adaptation retains its own support hierarchy, voxel Source/Recipe and
shared derived material workflow. It does not import the standalone editor/renderer.

MIT License

Copyright (c) 2026 Flow Construct Studios

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
