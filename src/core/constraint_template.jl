""
function is_inverter(pm, i, nw)
    gen = ref(pm, nw, :gen, i)

    if !haskey(gen, "inverter")
        return false
    end

    return gen["inverter"] == 1
end

""
function is_pq_inverter(pm, i, nw)
    gen = ref(pm, nw, :gen, i)

    if !haskey(gen, "inverter")
        return false
    end

    if gen["inverter"] == 0
        return false
    end

    if !haskey(gen, "inverter_mode")
    	return false
    end

    return gen["inverter_mode"] == "pq"
end

""
function is_v_inverter(pm, i, nw)
    gen = ref(pm, nw, :gen, i)

    if !haskey(gen, "inverter")
        return false
    end

    if gen["inverter"] == 0
        return false
    end

    if !haskey(gen, "inverter_mode")
    	return false
    end

    return gen["inverter_mode"] == "v"
end

""
function constraint_gen_voltage_drop(pm::_PM.AbstractPowerModel; nw::Int=pm.cnw)
    for (k,gen) in ref(pm, nw, :gen)
        i = gen["index"]

        if is_inverter(pm, i, nw)
            continue
        end

        bus_id = gen["gen_bus"]

        r = gen["zr"]
        x = gen["zx"]
        z = r + 1im*x

        p = gen["pg"]
        q = gen["qg"]
        s = p + 1im*q

        vm = ref(pm, :bus, bus_id, "vm")
        va = ref(pm, :bus, bus_id, "va")
        v = vm*exp(1im*va)

        vr = real(v)
        vi = imag(v)
        println("vr = $vr, vi = $vi")

        c = conj(s/v)
        vg = v + z*c # add an option here to disable pre-computed voltage drop
        vgr = real(vg)
        vgi = imag(vg)
        println("Compensated vg: vgr = $vgr, vgi = $vgi")


        constraint_gen_voltage_drop(pm, nw, i, bus_id, r, x, vgr, vgi)
    end
end


""
function constraint_pq_inverter(pm::_PM.AbstractPowerModel; nw::Int=pm.cnw)
    for (k,gen) in ref(pm, nw, :gen)
        i = gen["index"]

        if !is_pq_inverter(pm, i, nw)
            continue
        end

        bus_id = gen["gen_bus"]

        r = gen["zr"]
        pg = gen["pg"]
        qg = gen["qg"]

        smax = abs(max(abs(gen["pmax"]),abs(gen["pmin"])) + max(abs(gen["qmax"]),abs(gen["qmin"]))*1im)
        cmax = 1.1*smax
        # cm = 0.1*smax
        println("cmax = $cmax")
        #cmax = 2

        # vs = 0.1
        # constraint_unity_pf_inverter(pm, nw, i, bus_id, pg, qg, cmax)
        constraint_pq_inverter(pm, nw, i, bus_id, pg, qg, cmax)
        # constraint_unity_pf_inverter_rs(pm, nw, i, bus_id, r, pg, qg, cmax)
        # constraint_unity_pf_inverter(pm, nw, i, bus_id, pg, qg, cmax)
    end
end

""
function constraint_i_inverter(pm::_PM.AbstractPowerModel; nw::Int=pm.cnw)
    for (k,gen) in ref(pm, nw, :gen)
        i = gen["index"]

        if !is_pq_inverter(pm, i, nw)
            continue
        end

        bus_id = gen["gen_bus"]
        bus = ref(pm, nw, :bus, bus_id)

        r = gen["zr"]
        pg = gen["pg"]
        qg = gen["qg"]

        cm = abs(gen["pg"] + 1im*gen["qg"])/bus["vm"]
        
        println("cm = $cm")
        #cmax = 2

        constraint_i_inverter_vs(pm, nw, i, bus_id, r, pg, qg, cm)
    end
end

""
function constraint_v_inverter(pm::_PM.AbstractPowerModel; nw::Int=pm.cnw)
    for (k,gen) in ref(pm, nw, :gen)
        i = gen["index"]

        if !is_v_inverter(pm, i, nw)
            continue
        end

        bus_id = gen["gen_bus"]
        bus = ref(pm, nw, :bus, bus_id)

        vm = ref(pm, :bus, bus_id, "vm")
        va = ref(pm, :bus, bus_id, "va")

        vgr = vm * cos(va)
        vgi = vm * sin(va)        

        r = gen["zr"]
        x = gen["zx"]

        pg = gen["pg"]
        qg = gen["qg"]

        smax = abs(max(abs(gen["pmax"]), abs(gen["pmin"])) + max(abs(gen["qmax"]), abs(gen["qmin"]))*1im)
        cmax = 1.1*smax
        # cm = 0.1*smax
        println("cmax = $cmax")
        #cmax = 2

        # vs = 0.1
        constraint_v_inverter(pm, nw, i, bus_id, r, x, vgr, vgi, cmax)
    end
end

""
function constraint_current_balance(pm::_PM.AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    bus = ref(pm, nw, :bus, i)["bus_i"]
    bus_arcs = ref(pm, nw, :bus_arcs, i)
    bus_gens = ref(pm, nw, :bus_gens, i)
    bus_shunts = ref(pm, nw, :bus_shunts, i)

    bus_gs = Dict(k => ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bus_bs = Dict(k => ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)

    if bus != ref(pm, nw, :active_fault, "bus_i")
        constraint_current_balance(pm, nw, i, bus_arcs, bus_gens, bus_gs, bus_bs)
    else
        constraint_fault_current_balance(pm, nw, i, bus_arcs, bus_gens, bus_gs, bus_bs, bus)
    end
end


""
function constraint_mc_gen_voltage_drop(pm::_PM.AbstractPowerModel; nw::Int=pm.cnw)
    for (k,gen) in ref(pm, nw, :gen)
        i = gen["index"]
        bus_id = gen["gen_bus"]

        r = gen["zr"]
        x = gen["zx"]

        vm = ref(pm, :bus, bus_id, "vm")
        va = ref(pm, :bus, bus_id, "va")

        vgr = [vm[i] * cos(va[i]) for i in 1:3]
        vgi = [vm[i] * sin(va[i]) for i in 1:3]

        constraint_mc_gen_voltage_drop(pm, nw, i, bus_id, r, x, vgr, vgi)
    end
end


""
function constraint_mc_pq_inverter(pm::_PM.AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    index = pm.ref[:nw][nw][:solar_gfli][i]
    gen = pm.ref[:nw][nw][:gen][index]

    cmax = gen["i_max"]
    if gen["solar_max"] < gen["kva"] * gen["pf"]
        pmax = gen["solar_max"]
    else
        pmax = gen["kva"] * gen["pf"]
    end
    constraint_mc_pq_inverter(pm, nw, index, i, pmax, 0.0, cmax)
end

function constraint_mc_grid_forming_inverter(pm::_PM.AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    index = pm.ref[:nw][nw][:solar_gfmi][i]
    gen = pm.ref[:nw][nw][:gen][index]
    bus_i = gen["gen_bus"]
    bus = pm.ref[:nw][nw][:bus][bus_i]

    if !haskey(bus, "vm") && !haskey(bus, "va")
        bus["vm"] = [1 for c in _PM.conductor_ids(pm; nw=nw)]
        bus["va"] = [0 -2*pi/3 2*pi/3]
    end

    cmax = gen["i_max"]
    vrstar = [bus["vm"][c]*cos(bus["va"][c]) for c in _PM.conductor_ids(pm; nw=nw)]
    vistar = [bus["vm"][c]*sin(bus["va"][c]) for c in _PM.conductor_ids(pm; nw=nw)]    

    # push into pmax on import and erase this 
    if gen["solar_max"] < gen["kva"]
        pmax = gen["solar_max"]
    else
        pmax = gen["kva"]
    end

    constraint_grid_formimg_inverter(pm, nw, index, i, vrstar, vistar, pmax, cmax)
end

function constraint_mc_grid_forming_inverter_impedance(pm::_PM.AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    index = pm.ref[:nw][nw][:solar_gfmi][i]
    gen = pm.ref[:nw][nw][:gen][index]
    bus_i = gen["gen_bus"]
    bus = pm.ref[:nw][nw][:bus][bus_i]

    if !haskey(bus, "vm") && !haskey(bus, "va")
        bus["vm"] = [1 for c in _PM.conductor_ids(pm; nw=nw)]
        bus["va"] = [0 -2*pi/3 2*pi/3]
    end

    cmax = gen["i_max"]
    vrstar = [bus["vm"][c]*cos(bus["va"][c]) for c in _PM.conductor_ids(pm; nw=nw)]
    vistar = [bus["vm"][c]*sin(bus["va"][c]) for c in _PM.conductor_ids(pm; nw=nw)]    

    # push into pmax on import and erase this 
    if gen["solar_max"] < gen["kva"]
        pmax = gen["solar_max"]
    else
        pmax = gen["kva"]
    end

    r = [0.1, 0.1, 0.1]
    x = [0.0, 0.0, 0.0]

    if "r" in keys(gen)
        r = gen["zr"]
    end

    if "x" in keys(gen)
        x = gen["zx"]
    end

    # r = [0.0, 0.0, 0.0]
    # x = [0.0, 0.0, 0.0]    

    # constraint_grid_formimg_inverter(pm, nw, index, i, vrstar, vistar, pmax, cmax)
    constraint_grid_formimg_inverter_impedance(pm, nw, index, i, vrstar, vistar, r, x, pmax, cmax)
end

""
function constraint_mc_current_balance(pm::_PM.AbstractPowerModel, i::Int; nw::Int=pm.cnw)
    bus = ref(pm, nw, :bus, i)["bus_i"]
    bus_arcs = ref(pm, nw, :bus_arcs, i)
    bus_arcs_sw = ref(pm, nw, :bus_arcs_sw, i)
    bus_arcs_trans = ref(pm, nw, :bus_arcs_trans, i)
    bus_gens = ref(pm, nw, :bus_gens, i)
    bus_shunts = ref(pm, nw, :bus_shunts, i)

    bus_gs = Dict(k => ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bus_bs = Dict(k => ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)
    
    if bus != ref(pm, nw, :active_fault, "bus_i")
        constraint_mc_current_balance(pm, nw, i, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_gs, bus_bs)
    else
        constraint_mc_fault_current_balance(pm, nw, i, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_gs, bus_bs, bus)
    end
end


""
function constraint_mc_generation(pm::_PM.AbstractPowerModel, id::Int; nw::Int=pm.cnw, report::Bool=true, bounded::Bool=true)
    generator = ref(pm, nw, :gen, id)
    bus = ref(pm, nw, :bus, generator["gen_bus"])

    if get(generator, "configuration", _PMD.WYE) == _PMD.WYE
        constraint_mc_generation_wye(pm, nw, id, bus["index"]; report=report, bounded=bounded)
    else
        constraint_mc_generation_delta(pm, nw, id, bus["index"]; report=report, bounded=bounded)
    end
end


""
function constraint_mc_ref_bus_voltage(pm::_PM.AbstractIVRModel, i::Int; nw::Int=pm.cnw)
    vm = ref(pm, :bus, i, "vm")
    va = ref(pm, :bus, i, "va")

    vr = [vm[i] * cos(va[i]) for i in 1:3]
    vi = [vm[i] * sin(va[i]) for i in 1:3]

    constraint_mc_ref_bus_voltage(pm, nw, i, vr, vi)
end


function constraint_mc_voltage_magnitude_only(pm::_PM.AbstractIVRModel, i::Int; nw::Int=pm.cnw)
    vm = ref(pm, :bus, i, "vm")
    constraint_mc_voltage_magnitude_only(pm, nw, i, vm)
end

