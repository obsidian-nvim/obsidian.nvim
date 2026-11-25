---@meta

-- Neovim 0.12 defines IterMod's call operator without arguments; 0.13 adds
-- explicit table-input overloads. Use the public Iter API: ArrayIter's
-- implementations are annotated private in 0.12.
---@class IterMod
---@overload fun(src: table): Iter
