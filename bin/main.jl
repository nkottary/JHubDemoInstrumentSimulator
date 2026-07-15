using Pkg
const BASE_PATH = joinpath(@__DIR__, "..")
Pkg.activate(BASE_PATH)

include(joinpath(BASE_PATH, "src", "InstrumentSimulator.jl"))
using .InstrumentSimulator

InstrumentSimulator.main()
