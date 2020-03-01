using PowerModels, PowerModelsDistribution, JuMP, Ipopt

const PMs = PowerModels
const PMD = PowerModelsDistribution

""
function run_mc_fault_study(data::Dict{String,Any}, solver; kwargs...)
    return PMs.run_model(data, PMs.IVRPowerModel, solver, build_mc_fault_study; ref_extensions=[ref_add_arcs_trans!], multiconductor=true, kwargs...)
end


""
function run_mc_fault_study(file::String, solver; kwargs...)
    return run_mc_fault_study(PowerModelsDistribution.parse_file(file), PMs.IVRPowerModel, solver; kwargs...)
end


""
function build_mc_fault_study(pm::PMs.AbstractPowerModel)
    # Variables
    PMD.variable_mc_voltage(pm, bounded = false)
    PMD.variable_mc_branch_current(pm, bounded = false)
    PMD.variable_mc_transformer_current(pm, bounded = false)
    PMD.variable_mc_generation(pm, bounded = false) 

    # gens should be constrained before KCL, or Pd/Qd undefined
    for id in PMs.ids(pm, :gen)
        PMD.constraint_mc_generation(pm, id)
    end


    for (i,bus) in PMs.ref(pm, :bus)
        # do need a new version to handle gmat
        constraint_mc_fault_current_balance(pm, i)        
    end

    for (i,gen) in ref(pm, :gen)
        # do I need a new version for multiconductor
        constraint_mc_gen_fault_voltage_drop(pm, i)
    end

    for i in PMs.ids(pm, :branch)
        PMD.constraint_mc_current_from(pm, i)
        PMD.constraint_mc_current_to(pm, i)

        PMD.constraint_mc_voltage_drop(pm, i)
    end

    for i in PMs.ids(pm, :transformer)
        PMD.constraint_mc_trans(pm, i)
    end
end

""
function constraint_mc_fault_current_balance(pm::PMs.AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    bus = PMs.ref(pm, nw, :bus, i)
    bus_arcs = PMs.ref(pm, nw, :bus_arcs, i)
    bus_arcs_sw = PMs.ref(pm, nw, :bus_arcs_sw, i)
    bus_arcs_trans = PMs.ref(pm, nw, :bus_arcs_trans, i)
    bus_gens = PMs.ref(pm, nw, :bus_gens, i)
    bus_storage = PMs.ref(pm, nw, :bus_storage, i)
    bus_loads = PMs.ref(pm, nw, :bus_loads, i)
    bus_shunts = PMs.ref(pm, nw, :bus_shunts, i)

        bus_faults = []

    # TODO: replace with list comprehension
    for (k,f) in ref(pm, :fault)
        if f["bus"] == i
            push!(bus_faults, k)
        end
    end    

    bus_gs = Dict(k => PMs.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bus_bs = Dict(k => PMs.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)

    bus_gf =  Dict(k => ref(pm, nw, :fault, k, "gf") for k in bus_faults)

    constraint_mc_fault_current_balance(pm, nw, i, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_gs, bus_bs, bus_gf)
end


"""
Kirchhoff's current law applied to buses
`sum(cr + im*ci) = 0`
"""
function constraint_mc_fault_current_balance(pm::PMs.AbstractIVRModel, n::Int, i, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_gs, bus_bs, bus_gf)
    vr = PMs.var(pm, n, :vr, i)
    vi = PMs.var(pm, n, :vi, i)

    # TODO: add storage back with inverter fault model
    cr    = get(PMs.var(pm, n),    :cr, Dict()); PMs._check_var_keys(cr, bus_arcs, "real current", "branch")
    ci    = get(PMs.var(pm, n),    :ci, Dict()); PMs._check_var_keys(ci, bus_arcs, "imaginary current", "branch")
    crg   = get(PMs.var(pm, n),   :crg_bus, Dict()); PMs._check_var_keys(crg, bus_gens, "real current", "generator")
    cig   = get(PMs.var(pm, n),   :cig_bus, Dict()); PMs._check_var_keys(cig, bus_gens, "imaginary current", "generator")
    crsw  = get(PMs.var(pm, n),  :crsw, Dict()); PMs._check_var_keys(crsw, bus_arcs_sw, "real current", "switch")
    cisw  = get(PMs.var(pm, n),  :cisw, Dict()); PMs._check_var_keys(cisw, bus_arcs_sw, "imaginary current", "switch")
    crt   = get(PMs.var(pm, n),   :crt, Dict()); PMs._check_var_keys(crt, bus_arcs_trans, "real current", "transformer")
    cit   = get(PMs.var(pm, n),   :cit, Dict()); PMs._check_var_keys(cit, bus_arcs_trans, "imaginary current", "transformer")

    cnds = PMs.conductor_ids(pm; nw=n)
    ncnds = length(cnds)

    Gt = isempty(bus_gs) ? fill(0.0, ncnds, ncnds) : sum(values(bus_gs))
    Bt = isempty(bus_bs) ? fill(0.0, ncnds, ncnds) : sum(values(bus_bs))

    for c in cnds
        JuMP.@NLconstraint(pm.model,  sum(cr[a][c] for a in bus_arcs)
                                    + sum(crsw[a_sw][c] for a_sw in bus_arcs_sw)
                                    + sum(crt[a_trans][c] for a_trans in bus_arcs_trans)
                                    ==
                                    sum(crg[g][c]        for g in bus_gens)
                                    - sum( Gt[c,d]*vr[d] for d in cnds) # shunts
                                    - sum(gf for gf in values(bus_gf))*vr[c]
                                    )
        JuMP.@NLconstraint(pm.model, sum(ci[a][c] for a in bus_arcs)
                                    + sum(cisw[a_sw][c] for a_sw in bus_arcs_sw)
                                    + sum(cit[a_trans][c] for a_trans in bus_arcs_trans)
                                    ==
                                    sum(cig[g][c]        for g in bus_gens)
                                    - sum( Gt[c,d]*vi[d] for d in cnds) # shunts
                                    - sum(gf for gf in values(bus_gf))*vi[c]
                                    )
    end
end


""
function constraint_mc_gen_fault_voltage_drop(pm::AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    gen = ref(pm, nw, :gen, i)
    busid = gen["gen_bus"]
    gen_bus = ref(pm, nw, :bus, busid)

    if haskey(gen, "rg")
        r = gen["rg"]
    else
        r = 0
    end

    if haskey(gen, "xg")
        x = gen["xg"]
    else
        x = 0.1
    end   

    # Watch out! OpenDSS doesn't include base case voltages in input file
    vm = ref(pm, :bus, busid, "vm") 
    va = ref(pm, :bus, busid, "va")

    # Watch out! Angles are in radians unlike in vanilla PowerModels
    v = [vm[i]*exp(1im*va[i]) for i in 1:3]

    vgr = [real(vk) for vk in v]
    vgi = [imag(vk) for vk in v]

    constraint_mc_gen_fault_voltage_drop(pm, nw, i, busid, r, x, vgr, vgi)
end


"""
Defines voltage drop over a branch, linking from and to side complex voltage
"""
function constraint_mc_gen_fault_voltage_drop(pm::AbstractIVRModel, n::Int, i, busid, r, x, vr_fr, vi_fr)
    vr_to = var(pm, n, :vr, busid)
    vi_to = var(pm, n, :vi, busid)

    # need generator currents
    crg =  var(pm, n, :crg, i)
    cig =  var(pm, n, :cig, i)    

    cnds = PMs.conductor_ids(pm; nw=n)
    ncnds = length(cnds)

    for c in cnds
        JuMP.@constraint(pm.model, vr_to[c] == vr_fr[c] - r*crg[c] + x*cig[c])
        JuMP.@constraint(pm.model, vi_to[c] == vi_fr[c] - r*cig[c] - x*crg[c])
    end
end




path = "data/mc/case3_balanced.dss"
net = PMD.parse_file(path)
net["multinetwork"] = false

# create a convenience function add_fault or keyword options to run_mc_fault study
net["fault"] = Dict()
net["fault"]["1"] = Dict("bus"=>3, "gf"=>10)

solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, print_level=0)
pmd = PMD.parse_file("data/mc/case3_balanced.dss")
sol = PMD.run_mc_pf_iv(pmd, PMs.IVRPowerModel, solver)
result = run_mc_fault_study(net, solver)