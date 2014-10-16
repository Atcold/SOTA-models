--------------------------------------------------------------------------------
-- Profiling network (forward only)
-- Computational time and estimation of number of operations
--------------------------------------------------------------------------------
-- Alfredo Canziani, Oct 14
--------------------------------------------------------------------------------

-- Requires --------------------------------------------------------------------
require 'xlua'
require 'sys'

-- Local definitions -----------------------------------------------------------
local pf = function(...) print(string.format(...)) end
local r = sys.COLORS.red
local g = sys.COLORS.green
local n = sys.COLORS.none
local THIS = sys.COLORS.blue .. 'THIS' .. n

local function time(name, model, nFeatureMaps, mapSize, iterations, cuda, totOps)
   pf('Profiling %s, %d iterations', r..name..n, iterations)
   collectgarbage()

   -- Input definition ---------------------------------------------------------
   local input = torch.Tensor(nFeatureMaps[0], mapSize.real[0], mapSize.real[0])
   if cuda then input = input:cuda() end

   local timer = torch.Timer()
   local convOutput
   for i = 1, iterations do
      xlua.progress(i, iterations)
      convOutput = model.modules[1]:forward(input)
      if cuda then cutorch.synchronize() end
   end
   convTime = timer:time().real/iterations

   timer = torch.Timer()
   for i = 1, iterations do
      xlua.progress(i, iterations)
      model.modules[2]:forward(convOutput)
      if cuda then cutorch.synchronize() end
   end
   MLPTime = timer:time().real/iterations

   time = convTime + MLPTime
   local d -- device
   if not cuda then d = 'CPU'
   else d = g .. 'GPU' .. n end
   pf('   Forward average time on %s %s: %.2f ms', THIS, d, time * 1e3)
   pf('    + Convolution time: %.2f ms', convTime * 1e3)
   pf('    + MLP time: %.2f ms', MLPTime * 1e3)
   pf('   Performance for %s %s: %.2f G-Ops/s\n', THIS, d,
      totOps * 1e-9 / time)

   return time

end

local function ops(nFeatureMaps, filterSize, convPadding, convStride, poolSize,
   poolStride, hiddenUnits, mapSize, time)
   collectgarbage()

   local convOps = torch.Tensor(#nFeatureMaps)
   local poolOps = torch.zeros(#nFeatureMaps)
   for i = 1, #nFeatureMaps do
      convOps[i] = 2 * nFeatureMaps[i-1] * nFeatureMaps[i] * filterSize[i]^2 *
         mapSize.real[i]^2 + 2 * mapSize.real[i] -- bias + ReLU
      if poolSize[i] > 1 then
         poolOps[i] = poolSize[i]^2 * mapSize.pool[i]^2
      end
   end
   local MLPOps = torch.Tensor(#hiddenUnits)
   local neurons = model.neurons.pool
   for i, hidden in ipairs(hiddenUnits) do
      MLPOps[i] = 2 * neurons[#nFeatureMaps+i-1] * neurons[#nFeatureMaps+i] +
         2 * neurons[#nFeatureMaps+i] -- bias + ReLU
   end

   --print(convOps, poolOps, MLPOps)
   local totOps = convOps:sum() + poolOps:sum() + MLPOps:sum()
   pf('   Operations estimation:')
   pf('    + Total: %.2f G-Ops', totOps * 1e-9)
   pf('    + Conv/Pool/MLP: %.2fG/%.2fk/%.2fM(-Ops)\n',
      convOps:sum() * 1e-9, poolOps:sum() * 1e-3, MLPOps:sum() * 1e-6)

   return totOps
end

-- Public function -------------------------------------------------------------
profileNet = {time = time, ops = ops}
