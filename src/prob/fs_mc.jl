# using Debugger
using Memento

"Runs the mc fault study"
function run_mc_fault_study(data::Dict{String,<:Any}, solver; kwargs...)
    Memento.setlevel!(_LOGGER, "debug")

    # check_pf!(data, solver)
    check_microgrid!(data)
    add_mc_fault_data!(data)
    solution = Dict{String, Any}()
    faults = deepcopy(data["fault"])
    delete!(data, "fault")  
    for (i,bus) in faults
        solution[i] = Dict{String,Any}()
        for (j,type) in bus
            solution[i][j] = Dict{String,Any}()
            for (f,fault) in type
                data["active_fault"] = fault
                Memento.info(_LOGGER, "Running short circuit")
                solution[i][j]["$f"] = run_mc_model(data, _PM.IVRPowerModel, solver, build_mc_fault_study; ref_extensions=[ref_add_fault!, ref_add_gen_dynamics!, ref_add_solar!], kwargs...)
            end
        end
    end
    return solution
end


"Call to run fs on file"
function run_mc_fault_study(file::String, solver; kwargs...)
    return run_mc_fault_study(parse_file(file; import_all = true), solver; kwargs...)
end


"Build mc fault study"
function build_mc_fault_study(pm::_PM.AbstractPowerModel)
    Memento.info(_LOGGER, "Building fault study")
    _PMD.variable_mc_bus_voltage(pm, bounded=false)
    variable_mc_branch_current(pm, bounded=false)
    variable_mc_transformer_current(pm, bounded=false)
    variable_mc_generation(pm, bounded=false) 
  
    variable_mc_pq_inverter(pm)
    variable_mc_grid_formimg_inverter(pm)

    for (i,bus) in ref(pm, :ref_buses)
        @assert bus["bus_type"] == 3
        constraint_mc_ref_bus_voltage(pm, i)
        # constraint_mc_voltage_magnitude_only(pm, i)
    end

    for id in ids(pm, :gen)
        constraint_mc_generation(pm, id)
    end

    # TODO add back in the generator voltage drop with inverters in model  
    Memento.info(_LOGGER, "Adding constraints for synchronous generators")   
    constraint_mc_gen_voltage_drop(pm)

    constraint_mc_fault_current(pm)

    for (i,bus) in ref(pm, :bus)
        constraint_mc_current_balance(pm, i)
    end

    for i in ids(pm, :branch)
        _PMD.constraint_mc_current_from(pm, i)
        _PMD.constraint_mc_current_to(pm, i)
        _PMD.constraint_mc_bus_voltage_drop(pm, i)
    end

    for i in ids(pm, :transformer)
        _PMD.constraint_mc_transformer_power(pm, i)
    end

    Memento.info(_LOGGER, "Adding constraints for grid-following inverters")   
    for i in ids(pm, :solar_gfli)
        Memento.info(_LOGGER, "Adding constraints for grid-following inverter $i")
        constraint_mc_pq_inverter(pm, i)
    end

    Memento.info(_LOGGER, "Adding constraints for grid-forming inverters")   
    for i in ids(pm, :solar_gfmi)
        Memento.info(_LOGGER, "Adding constraints for grid-forming inverter $i")
        # constraint_mc_grid_forming_inverter(pm, i)
        constraint_mc_grid_forming_inverter_virtual_impedance(pm, i)
    end

end
