using JuMP, CPLEX,ArgParse
include("read_files.jl")
include("utils.jl")


file_name = ARGS[1]

global nb_func,Function     = get_data("../instances/"*file_name*"Functions.txt",2)
global nb_func = Int(nb_func)
global nb_comm,Affinity   = get_data("../instances/"*file_name*"Affinity.txt", nb_func)
if file_name == "test1_"
    Fct_commod = [0]
    global func_per_comm = [[1, 2, 3], [2, 1]]
    global func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
elseif file_name == "grille2x3_"
    Fct_commod = [0]
    global func_per_comm = [[1], [1, 2], [1,2]]
    global func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
else
    useless,Fct_commod = get_data("../instances/"*file_name*"Fct_commod.txt" , nb_func)
    dim1 = size(Fct_commod)[1]
    dim2 = size(Fct_commod)[2]
    global func_per_comm = [[Fct_commod[i,j] for j in 1:dim2] for i in 1:dim1]
    #println(func_per_comm)
    global func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
end
global useless,Commodity  = get_data("../instances/"*file_name*"Commodity.txt" , nb_func)
global nb_nodes,nb_arcs,Arc      = get_data("../instances/"*file_name*"Graph.txt" , nb_func)

# Precision for adding DW variables
global const eps = 0.0001

global source = [Commodity[c,1]+1 for c in 1:nb_comm]
global sink = [Commodity[c,2]+1 for c in 1:nb_comm]

global open_cost = [1 for k in 1:nb_nodes]
global func_cost = Function[1:end,2:end]'

global latency = [-1 for i in 1:nb_nodes, j in 1:nb_nodes] #definie après
global max_latency = [Commodity[c,4] for c in 1:nb_comm]

global bandwidth = [Commodity[c,3] for c in 1:nb_comm]
global capacity = [Function[f,1] for f in 1:nb_func]

global max_func = [0 for k in 1:nb_nodes]
for i in 1:nb_arcs
    global max_func[Int(Arc[i,1])] = Arc[i,3]
    global max_func[Int(Arc[i,2])] = Arc[i,4]
    global latency[Int(Arc[i,1]), Int(Arc[i,2])] = Arc[i,5]
end

global exclusion = [[[0 for k in 1:nb_func ] for i in 1:nb_func] for j in 1:nb_comm]
for i in 1:nb_comm
    if Affinity[i] != [] && Affinity[i]!=0
        #println(exclusion)
        global exclusion[i][Int(Affinity[i,1])][Int(Affinity[i,2])] = 1
    end        
end

global latency_sp, shortest_path = compute_shortest_paths(nb_nodes, latency)


function init_problem()
    init_model = Model(CPLEX.Optimizer)

    set_optimizer_attribute(init_model, "CPX_PARAM_MIPDISPLAY", 1)
    set_optimizer_attribute(init_model, "CPX_PARAM_PARAMDISPLAY", 0)
    set_optimizer_attribute(init_model, "CPX_PARAM_EPINT", 1e-8)
    set_optimizer_attribute(init_model, "CPX_PARAM_TILIM", 90)
    set_optimizer_attribute(init_model, "CPX_PARAM_MIPEMPHASIS", 1)

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
        stage_latency[comm, stage] >= (exec_func[i, comm, stage - 1] + exec_func[j, comm, stage] - 1) * latency_sp[i, j]
    )

    @constraint(  # Execute each function once
        init_model, [comm = 1:nb_comm, stage = 1:length(func_per_comm[comm])],
        sum(exec_func[i, comm, stage] for i in 1:nb_nodes) == 1
    )

    @constraint(  # Fictive function on source
        init_model, [comm = 1:nb_comm],
        exec_func[source[comm], comm, 0] == 1
    )

    @constraint(  # Fictive function on sink
        init_model, [comm = 1:nb_comm],
        exec_func[sink[comm], comm, length(func_per_comm[comm]) + 1] == 1
    )

    @constraint(  # Exclusion constraint
        init_model, [
            i = 1:nb_nodes, comm = 1:nb_comm, stage_k = 1:length(func_per_comm[comm]), stage_l = 1:length(func_per_comm[comm]);
            exclusion[comm][func_per_comm[comm][stage_k]][func_per_comm[comm][stage_l]] == 1
        ],
        exec_func[i, comm, stage_k] + exec_func[i, comm, stage_l] <= 1
    )

    @constraint(  # Limit on node capacity
        init_model, [i = 1:nb_nodes],
        sum(sum(
            bandwidth[comm] / capacity[func_per_comm[comm][stage]] * exec_func[i, comm, stage]
            for stage in 1:length(func_per_comm[comm]))
            for comm in 1:nb_comm
        ) <=  max_func[i]
    )

    added_constr = -1
    while added_constr != 0
        optimize!(init_model)

        comm_latency_val = value.(comm_latency)
        added_constr = 0
        for comm in 1:nb_comm
            if comm_latency_val[comm] > max_latency[comm] + eps
                @constraint(
                    init_model,
                    comm_latency[comm] <= max_latency[comm]
                )
                added_constr += 1
            end
        end
        if (added_constr > 0)
            println("Re-adding latency constraint for " * string(added_constr) * " commodities")
        end
    end

    nb_paths = [1 for comm in 1:nb_comm]
    exec_func_paths = [[round.(Int, value.(exec_func[:, comm, :]))] for comm in 1:nb_comm]

    return nb_paths, exec_func_paths
end


function master_problem(nb_paths, exec_func_paths; MILP=true)
    model = Model(CPLEX.Optimizer)

    if MILP
        set_optimizer_attribute(model, "CPX_PARAM_PARAMDISPLAY", 0)
    else
        set_optimizer_attribute(model, "CPX_PARAM_SCRIND", 0)
    end
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

    @variable(model, open_node[1:nb_nodes], Bin)  # 1 if node is open
    @variable(model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)  # Number of functions installed on node
    @variable(model, select_path[comm = 1:nb_comm, 1:nb_paths[comm]], Bin)  # select given path for given commodity (DW)

    @expression(
        model, node_open_cost,
        sum(open_cost[i] * open_node[i] for i in 1:nb_nodes)
    )

    @expression(
        model, func_install_cost,
        sum(func_cost[i, f] * nb_functions[i, f] for i in 1:nb_nodes, f in 1:nb_func)
    )

    @objective(  # Minimize opening and intallation cost
        model, Min,
        node_open_cost + func_install_cost
    )

    @constraint(  # Limit on function capacity (DW)
        model, capacity_constr[i = 1:nb_nodes, f = 1:nb_func],
        sum(sum(sum(
            bandwidth[comm] * exec_func_paths[comm][path][i, stage] * select_path[comm, path]
            for path in 1:nb_paths[comm])
            for stage in 1:length(func_per_comm[comm]) if func_per_comm[comm][stage] == f)
            for comm in 1:nb_comm
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

    return value.(select_path), value.(open_node), value.(nb_functions), value(node_open_cost), value(func_install_cost), capacity_dual, path_selection_dual
end


function sub_problem(nb_paths, exec_func_paths, capacity_dual, path_selection_dual)
    added_path = 0

    for comm in 1:nb_comm

        # Defining subproblem
        sub_model = Model(CPLEX.Optimizer)

        set_optimizer_attribute(sub_model, "CPX_PARAM_SCRIND", 0)
        set_optimizer_attribute(sub_model, "CPX_PARAM_EPINT", 1e-8)

        @variable(sub_model, exec_func[1:nb_nodes, 0:nb_func + 1], Bin)  # 1 if function executed on node
        @variable(sub_model, stage_latency[1:length(func_per_comm[comm]) + 1])  # total latency induced by each stage

        path_weight = @objective(  # Minimize total path weight (DW)
            sub_model, Min,
            sum(
                bandwidth[comm] * exec_func[i, stage] * capacity_dual[i, func_per_comm[comm][stage]]
                for i in 1:nb_nodes, stage in 1:length(func_per_comm[comm])
            )
        )

        @constraint(  # Max latency (DW)
            sub_model,
            sum(stage_latency[stage] for stage in 1:length(func_per_comm[comm]) + 1) <= max_latency[comm]
        )

        @constraint(  # stage latency (DW)
            sub_model, [stage = 1:length(func_per_comm[comm]) + 1, i = 1:nb_nodes, j = 1:nb_nodes],
            stage_latency[stage] >= (exec_func[i, stage - 1] + exec_func[j, stage] - 1) * latency_sp[i, j]
        )

        @constraint(  # Execute each function once
            sub_model, [stage = 1:length(func_per_comm[comm])],
            sum(exec_func[i, stage] for i in 1:nb_nodes) == 1
        )

        @constraint(  # Fictive function on source
            sub_model,
            exec_func[source[comm], 0] == 1
        )

        @constraint(  # Fictivve function on sink
            sub_model,
            exec_func[sink[comm], length(func_per_comm[comm]) + 1] == 1
        )

        @constraint(  # Exclusion constraint
            sub_model, [
                i = 1:nb_nodes, stage_k = 1:length(func_per_comm[comm]), stage_l = 1:length(func_per_comm[comm]);
                exclusion[comm][func_per_comm[comm][stage_k]][func_per_comm[comm][stage_l]] == 1
            ],
            exec_func[i, stage_k] + exec_func[i, stage_l] <= 1
        )

        optimize!(sub_model)

        # Add new path variable in master if necessary
        if value(path_weight) + eps <= path_selection_dual[comm]
            nb_paths[comm] += 1
            push!(exec_func_paths[comm], round.(Int, value.(exec_func)))

            added_path += 1
        end
    end

    return added_path
end


# Initialization for column generation
println("------- Initial problem -------")
nb_paths, exec_func_paths = init_problem()
print("\n\n")

# Column generation
println("------- Column Generation -------")
added_path = -1
while added_path != 0
    # Solving relaxed master
    _, _, _, node_open_cost, func_install_cost, capacity_dual, path_selection_dual = master_problem(nb_paths, exec_func_paths, MILP=false)

    # Solving sub-problem
    global added_path = sub_problem(nb_paths, exec_func_paths, capacity_dual, path_selection_dual)

    if added_path > 0
        println("Adding new paths for " * string(added_path) * " commodities")
    else
        println("Column generation lower bound: " * string(node_open_cost + func_install_cost))
    end
end
print("\n\n")

# Solving MIP using generated paths
println("------- Final MIP -------")
select_path, open_node, nb_functions, node_open_cost, func_install_cost, _, _ = master_problem(nb_paths, exec_func_paths, MILP=true)
print("\n\n")

# Reconstruct variable from original problem
exec_func = [0 for i in 1:nb_nodes, comm in 1:nb_comm, stage in 0:nb_func + 1]
for comm in 1:nb_comm
    for path in 1:nb_paths[comm]
        if round(Int, select_path[comm, path]) == 1
            exec_func[:, comm, :] = exec_func_paths[comm][path]
            break
        end
    end
end

# Print results
println("Objective: opening nodes " * string(node_open_cost) * ", installing functions " * string(func_install_cost) * ", total " * string(node_open_cost + func_install_cost))
for comm in 1:nb_comm
    print("commodity " * string(comm) * ": ")

    for stage in 1:length(func_per_comm[comm]) + 1

        stage_start = -1
        stage_end = -1
        for i in 1:nb_nodes
            if round(Int, exec_func[i, comm, stage]) == 1
                stage_start = i
            end
            if round(Int, exec_func[i, comm, stage + 1]) == 1
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
            print("(f" * string(func_per_comm[comm][stage]) * ")")
        end
    end

    print("\n")
end
for i in 1:nb_nodes
    if open_node[i] == 1
        print("node " * string(i) * ":")

        for f in 1:nb_func
            print(" f" * string(f) * " * " * string(round(Int, nb_functions[i, f])) * ",")
        end

        print("\n")
    end
end
