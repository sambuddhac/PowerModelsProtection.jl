module PowerModelsProtection
    import JuMP
    import Memento

    import InfrastructureModels
    import PowerModels
    import PowerModelsDistribution
    import MathOptInterface

    const _IM = InfrastructureModels
    const _PM = PowerModels
    const _PMD = PowerModelsDistribution

    import InfrastructureModels: ids, ref, var, con, sol, nw_ids, nws, ismultinetwork

    const MOI = MathOptInterface

    function __init__()
        global _LOGGER = Memento.getlogger(PowerModels)
        # Memento.setlevel!(_LOGGER, "debug")
    end

    include("core/variable.jl")
    include("core/constraint_template.jl")
    include("core/constraint.jl")
    include("core/constraint_inverter.jl")
    include("core/data.jl")
    include("core/ref.jl")
    include("core/objective.jl")
    include("core/solution.jl")

    include("io/common.jl")
    include("io/matpower.jl")
    include("io/opendss.jl")

    include("prob/common.jl")
    include("prob/fs.jl")
    include("prob/fs_mc.jl")
    include("prob/pf_mc.jl")

    include("core/export.jl")  # must be last include to properly export functions
end
