using JuMP, CPLEX,ArgParse
include("read_files.jl")



function main(file_name :: String)
    nb_func,Function     = get_data("../instances/"*file_name*"Functions.txt",2)
    nb_func = Int(nb_func)
    nb_comm,Affinity   = get_data("../instances/"*file_name*"Affinity.txt", nb_func)
    if file_name == "test1_"
        Fct_commod = [0]
        func_per_comm = [[1, 2, 3], [2, 1]]
        func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
    elseif file_name == "grille2x3_"
        Fct_commod = [0]
        func_per_comm = [[1], [1, 2], [1,2]]
        func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
    else
        useless,Fct_commod = get_data("../instances/"*file_name*"Fct_commod.txt" , nb_func)
        dim1 = size(Fct_commod)[1]
        dim2 = size(Fct_commod)[2]
        func_per_comm = [[Fct_commod[i,j] for j in 1:dim2] for i in 1:dim1]
        #println(func_per_comm)
        func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
    end
    useless,Commodity  = get_data("../instances/"*file_name*"Commodity.txt" , nb_func)
    nb_nodes,nb_arcs,Arc      = get_data("../instances/"*file_name*"Graph.txt" , nb_func)

    if -1 in Fct_commod 
        println("probleme sur l'instance Fct_commod")
    end
    

    source = [Commodity[c,1]+1 for c in 1:nb_comm]
    sink =   [Commodity[c,2]+1 for c in 1:nb_comm]

    open_cost = [1 for k in 1:nb_nodes]
    func_cost = Function[1:end,2:end]'

    latency =  [-1 for i in 1:nb_nodes, j in 1:nb_nodes] #definie après
    max_latency = [Commodity[c,4] for c in 1:nb_comm]

    bandwidth = [Commodity[c,3] for c in 1:nb_comm]
    #println("Fucntion : ",Function)
    capacity = [Function[f,1] for f in 1:nb_func]

    max_func = [0 for k in 1:nb_nodes]
    for i in 1:nb_arcs
        max_func[Int64(Arc[i,1])] = Int64(Arc[i,3])
        max_func[Int64(Arc[i,2])] = Int64(Arc[i,4])
        latency[Int64(Arc[i,1]), Int64(Arc[i,2])] = Int64(Arc[i,5])
    end

    #println("Affinity : ",Affinity)
    exclusion = [[[0 for k in 1:nb_func ] for i in 1:nb_func] for j in 1:nb_comm]
    for i in 1:nb_comm
        if Affinity[i] != [] && Affinity[i]!=0
            #println(exclusion)
            exclusion[i][Int(Affinity[i,1])][Int(Affinity[i,2])] = 1
        end        
    end

    # Defining model
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

    @variable(model, open_node[1:nb_nodes], Bin)  # 1 if node is open
    @variable(model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)  # Number of functions installed on node
    @variable(model, select_edge[1:nb_nodes, 1:nb_nodes, 1:nb_comm, 1:nb_func + 1], Bin)  # flow on edge for given commodity and stage
    @variable(model, exec_func[1:nb_nodes, 1:nb_comm, 0:nb_func + 1], Bin)  # 1 if function executed on node for given commodity

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

    @constraint(  # Max latency on each commodity
        model, [comm = 1:nb_comm],
        sum(
            latency[i, j] * select_edge[i, j, comm, stage]
            for stage in 1:length(func_per_comm[comm]) + 1, i in 1:nb_nodes, j in 1:nb_nodes if latency[i, j] > 0
        ) <= max_latency[comm]
    )

    @constraint(  # Flow constraint
        model, [i = 1:nb_nodes, comm = 1:nb_comm, stage = 1:length(func_per_comm[comm]) + 1],
        sum(select_edge[j, i, comm, stage] for j in 1:nb_nodes if latency[j, i] > 0)
        - sum(select_edge[i, j, comm, stage] for j in 1:nb_nodes if latency[i, j] > 0)
        == exec_func[i, comm, stage] - exec_func[i, comm, stage - 1]
    )

    @constraint(  # Execute each function once
        model, [comm = 1:nb_comm, stage = 1:length(func_per_comm[comm])],
        sum(exec_func[i, comm, stage] for i in 1:nb_nodes) == 1
    )

    @constraint(  # Fictive function on source
        model, [comm = 1:nb_comm],
        exec_func[source[comm], comm, 0] == 1
    )

    @constraint(  # Fictive function on sink
        model, [comm = 1:nb_comm],
        exec_func[sink[comm], comm, length(func_per_comm[comm])] == 1
    )

    @constraint(  # Exclusion constraint
        model, [
            i = 1:nb_nodes, comm = 1:nb_comm, stage_k = 1:length(func_per_comm[comm]), stage_l = 1:length(func_per_comm[comm]);
            exclusion[comm][func_per_comm[comm][stage_k]][func_per_comm[comm][stage_l]] == 1
        ],
        exec_func[i, comm, stage_k] + exec_func[i, comm, stage_l] <= 1
    )

    @constraint(  # Limit on function capacity
        model, [i = 1:nb_nodes, f = 1:nb_func],
        sum(sum(
            bandwidth[comm] * exec_func[i, comm, stage]
            for stage in 1:length(func_per_comm[comm]) if func_per_comm[comm][stage] == f)
            for comm in 1:nb_comm
        ) <= capacity[f] * nb_functions[i, f]
    )

    @constraint(  # Install functions on open nodes
        model, [i = 1:nb_nodes],
        sum(nb_functions[i, f] for f in 1:nb_func) <= max_func[i] * open_node[i]
    )

    optimize!(model)

    # Print results
    println("Objective: opening nodes " * string(value(node_open_cost)) * ", installing functions " * string(value(func_install_cost)) * ", total " * string(value(node_open_cost + func_install_cost)))
    for comm in 1:nb_comm
        print("commodity " * string(comm) * ": ")

        for stage in 1:length(func_per_comm[comm]) + 1

            stage_start = -1
            stage_end = -1
            for i in 1:nb_nodes
                if round(Int, value(exec_func[i, comm, stage - 1])) == 1
                    stage_start = i
                end
                if round(Int, value(exec_func[i, comm, stage])) == 1
                    stage_end = i
                end
            end
            if stage == 1
                print(string(stage_start))
            end

            current_pos = stage_start
            while current_pos != stage_end
                for next_pos in 1:nb_nodes
                    if round(Int, value(select_edge[current_pos, next_pos, comm, stage])) == 1
                        print(" -> ")
                        print(string(next_pos))
                        current_pos = next_pos
                        break
                    end
                end
            end

            if stage != length(func_per_comm[comm]) + 1
                print("(f" * string(func_per_comm[comm][stage]) * ")")
            end
        end

        print("\n")
    end
    for i in 1:nb_nodes
        if round(Int, value(open_node[i])) == 1
            print("node " * string(i) * ":")

            for f in 1:nb_func
                print(" f" * string(f) * " * " * string(round(Int, value(nb_functions[i, f]))) * ",")
            end

            print("\n")
        end
    end

end

main(ARGS[1])
