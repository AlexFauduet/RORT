#=
DW_model:
- Julia version: 1.7.2
- Author: alex
- Date: 2022-03-22
=#

using JuMP, CPLEX
include("utils.jl")


# Precision for adding DW variables
global const eps = 0.0001

# Defining parameters
global nb_comm = 2
global nb_nodes = 4
global nb_func = 3

global func_per_comm = [[1, 2, 3], [2, 1]]
global func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]

global source = [1, 2]
global sink = [3, 4]

global open_cost = [1, 1, 1, 1]
global func_cost = [1 1 1; 1 1 1; 1 1 1; 1 1 1]

global latency = [-1 1 -1 1; 1 -1 1 -1; -1 1 -1 1; 1 -1 1 -1]
global max_latency = [3, 3]

global latency_sp, shortest_path = compute_shortest_paths(nb_nodes, latency)

global bandwidth = [20, 2]
global capacity = [10, 10, 10]

global max_func = [3, 3, 3, 3]#[30, 30, 30, 30]#

global exclusion = [[0 1 0; 1 0 0; 0 0 0], [0 1 0; 1 0 0; 0 0 0]]


function init_problem()
    init_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(init_model, "CPX_PARAM_EPINT", 1e-8)

    @variable(init_model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)  # Number of functions installed on node
    @variable(init_model, exec_func[1:nb_nodes, 1:nb_comm, 0:nb_func + 1], Bin)  # 1 if function executed on node
    @variable(init_model, stage_latency[comm = 1:nb_comm, 1:length(func_per_comm[comm]) + 1])  # total latency induced by each stage

    @expression(  # Max latency (DW)
        init_model, comm_latency[comm = 1:nb_comm],
        sum(stage_latency[comm, stage] for stage in 1:length(func_per_comm[comm]) + 1)
    )

    @objective(
        init_model, Min,
        sum(comm_latency[comm] for comm in 1:nb_comm)
    )

    @constraint(  # stage latency (DW)
        init_model, [comm = 1:nb_comm, stage = 1:length(func_per_comm[comm]) + 1, i = 1:nb_nodes, j = 1:nb_nodes],
        stage_latency[comm, stage] >= (exec_func[i, comm, func_per_comm_[comm][stage]] + exec_func[j, comm, func_per_comm_[comm][stage + 1]] - 1) * latency_sp[i, j]
    )

    @constraint(  # Execute each function once
        init_model, [comm = 1:nb_comm, f = func_per_comm[comm]],
        sum(exec_func[i, comm, f] for i in 1:nb_nodes) == 1
    )

    @constraint(  # Fictive function on source
        init_model, [comm = 1:nb_comm],
        exec_func[source[comm], comm, 0] == 1
    )

    @constraint(  # Fictivve function on sink
        init_model, [comm = 1:nb_comm],
        exec_func[sink[comm], comm, nb_func + 1] == 1
    )

    @constraint(  # Exclusion constraint
        init_model, [comm = 1:nb_comm, i = 1:nb_nodes, f = func_per_comm[comm], g = func_per_comm[comm]; exclusion[comm][f, g] == 1],
        exec_func[i, comm, f] + exec_func[i, comm, g] <= 1
    )

    @constraint(  # Limit on function capacity
        init_model, capacity_constr[comm = 1:nb_comm, i = 1:nb_nodes, f = 1:nb_func],
        sum(bandwidth[comm] * exec_func[i, comm, f] for comm in 1:nb_comm) <= capacity[f] * nb_functions[i, f]
    )

    @constraint(  # Install functions on open nodes
        init_model, [i = 1:nb_nodes],
        sum(nb_functions[i, f] for f in 1:nb_func) <= max_func[i]
    )

    added_constr = true
    while added_constr
        optimize!(init_model)

        added_constr = false
        for comm in 1:nb_comm
            if value(comm_latency[comm]) > max_latency[comm] + eps
                @constraint(
                    init_model,
                    comm_latency[comm] <= max_latency[comm]
                )
                added_constr = true
            end
        end
    end

    nb_paths = [1 for comm in 1:nb_comm]
    exec_func_paths = [[value.(exec_func[:, comm, :])] for comm in 1:nb_comm]

    return nb_paths, exec_func_paths
end


function master_problem(nb_paths, exec_func_paths; MILP=true)
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

    @variable(model, open_node[1:nb_nodes], Bin)  # 1 if node is open
    @variable(model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)  # Number of functions installed on node
    @variable(model, select_path[comm = 1:nb_comm, 1:nb_paths[comm]], Bin)  # select given path for given commodity (DW)

    @objective(  # Minimize opening and intallation cost
        model, Min,
        sum(open_cost[i] * open_node[i] for i in 1:nb_nodes) + sum(func_cost[i, f] * nb_functions[i, f] for i in 1:nb_nodes, f in 1:nb_func)
    )

    @constraint(  # Limit on function capacity (DW)
        model, capacity_constr[i = 1:nb_nodes, f = 1:nb_func],
        sum(sum(
            bandwidth[comm] * exec_func_paths[comm][path][i, f] * select_path[comm, path]
            for path in 1:nb_paths[comm]) for comm in 1:nb_comm
        ) <= capacity[f] * nb_functions[i, f]
    )

    @constraint(  # Select exactly one path
        model, path_selection_constr[comm = 1:nb_comm],
        sum(select_path[comm, path] for path in 1:nb_paths[comm]) == 1
    )

    @constraint(  # Install functions on open nodes
        model, [i = 1:nb_nodes],
        sum(nb_functions[i, f] for f in 1:nb_func) <= max_func[i] * open_node[i]
    )

    if !MILP
        relax_integrality(model)
    end

    optimize!(model)

    if MILP
        capacity_dual = nothing
        path_selection_dual = nothing
    else
        capacity_dual = -dual.(capacity_constr)
        path_selection_dual = dual.(path_selection_constr)
    end

    return value.(select_path), value.(open_node), value.(nb_functions), capacity_dual, path_selection_dual
end


function sub_problem(nb_paths, exec_func_paths, capacity_dual, path_selection_dual)
    added_path = false

    for comm in 1:nb_comm

        # Defining subproblem
        sub_model = Model(CPLEX.Optimizer)
        set_optimizer_attribute(sub_model, "CPX_PARAM_EPINT", 1e-8)
        set_optimizer_attribute(sub_model, "CPX_PARAM_MIPDISPLAY", 0)

        @variable(sub_model, exec_func[1:nb_nodes, 0:nb_func + 1], Bin)  # 1 if function executed on node
        @variable(sub_model, stage_latency[1:length(func_per_comm[comm]) + 1])  # total latency induced by each stage

        path_weight = @objective(  # Minimize total path weight (DW)
            sub_model, Min,
            sum(bandwidth[comm] * exec_func[i, f] * capacity_dual[i, f] for i in 1:nb_nodes, f in func_per_comm[comm])
        )

        @constraint(  # Max latency (DW)
            sub_model,
            sum(stage_latency[stage] for stage in 1:length(func_per_comm[comm]) + 1) <= max_latency[comm]
        )

        @constraint(  # stage latency (DW)
            sub_model, [stage = 1:length(func_per_comm[comm]) + 1, i = 1:nb_nodes, j = 1:nb_nodes],
            stage_latency[stage] >= (exec_func[i, func_per_comm_[comm][stage]] + exec_func[j, func_per_comm_[comm][stage + 1]] - 1) * latency_sp[i, j]
        )

        @constraint(  # Execute each function once
            sub_model, [f = func_per_comm[comm]],
            sum(exec_func[i, f] for i in 1:nb_nodes) == 1
        )

        @constraint(  # Fictive function on source
            sub_model,
            exec_func[source[comm], 0] == 1
        )

        @constraint(  # Fictivve function on sink
            sub_model,
            exec_func[sink[comm], nb_func + 1] == 1
        )

        @constraint(  # Exclusion constraint
            sub_model, [i = 1:nb_nodes, f = func_per_comm[comm], g = func_per_comm[comm]; exclusion[comm][f, g] == 1],
            exec_func[i, f] + exec_func[i, g] <= 1
        )

        optimize!(sub_model)

        # Add new path variable in master if necessary
        if value(path_weight) + eps <= path_selection_dual[comm]
            nb_paths[comm] += 1
            push!(exec_func_paths[comm], value.(exec_func))

            added_path = true
        end
    end

    return added_path
end


# Initialization for column generation
nb_paths, exec_func_paths = init_problem()

# Column generation
added_path = true
while added_path
    # Solving relaxed master
    _, _, _, capacity_dual, path_selection_dual = master_problem(nb_paths, exec_func_paths, MILP=false)

    # Solving sub-problem
    global added_path = sub_problem(nb_paths, exec_func_paths, capacity_dual, path_selection_dual)
end

# Solving MIP using generated paths
select_path, open_node, nb_functions, _, _ = master_problem(nb_paths, exec_func_paths, MILP=true)

# Reconstruct variable from original problem
exec_func = [0 for i in 1:nb_nodes, comm in 1:nb_comm, f in 0:nb_func + 1]
for comm in 1:nb_comm
    for path in 1:nb_paths[comm]
        if Int(select_path[comm, path]) == 1
            exec_func[:, comm, :] = exec_func_paths[comm][path]
            break
        end
    end
end

# Print results
for comm in 1:nb_comm
    print("commodity " * string(comm) * ": ")

    for stage in 1:length(func_per_comm[comm]) + 1

        stage_start = -1
        stage_end = -1
        for i in 1:nb_nodes
            if Int(exec_func[i, comm, func_per_comm_[comm][stage] + 1]) == 1
                stage_start = i
            end
            if Int(exec_func[i, comm, func_per_comm_[comm][stage + 1] + 1]) == 1
                stage_end = i
            end
        end
        if stage == 1
            print(string(stage_start))
        end

        for i in shortest_path[stage_start][stage_end]
            print(" -> ")
            print(string(i))
        end

        if stage != length(func_per_comm[comm]) + 1
            print("(f" * string(func_per_comm_[comm][stage + 1]) * ")")
        end
    end

    print("\n")
end
for i in 1:nb_nodes
    if open_node[i] == 1
        print("node " * string(i) * ":")

        for f in 1:nb_func
            print(" f" * string(f) * " * " * string(Int(nb_functions[i, f])) * ",")
        end

        print("\n")
    end
end
