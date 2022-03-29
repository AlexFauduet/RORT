using JuMP, CPLEX,ArgParse
include("read_files.jl")



function main(file_name :: String)
    nb_func,Function     = get_data("../instances/"*file_name*"Functions.txt",2)
    nb_func = Int(nb_func)
    nb_comm,Affinity   = get_data("../instances/"*file_name*"Affinity.txt", nb_func)
    useless,Fct_commod = get_data("../instances/"*file_name*"Fct_commod.txt" , nb_func)
    useless,Commodity  = get_data("../instances/"*file_name*"Commodity.txt" , nb_func)
    nb_nodes,nb_arcs,Arc      = get_data("../instances/"*file_name*"Graph.txt" , nb_func)

    println("Function : ", Function)
    println("Affinity  : ",Affinity )
    println("nb_func : ",nb_func)
    println("Fct_commod : ",Fct_commod )
    println("Commodity  : ", Commodity )
    println("Arc : ",Arc)

    dim1 = size(Fct_commod)[1]
    dim2 = size(Fct_commod)[2]
    func_per_comm = [[Fct_commod[i,j] for j in 1:dim2] for i in 1:dim1]
    #println(func_per_comm)
    func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]

    if -1 in Fct_commod
        println("probleme sur l'instance Fct_commod")
    end
    if file_name == "test1_"
        func_per_comm = [[1, 2, 3], [2, 1]]
        func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]
    end
    

    source = [Commodity[c,1]+1 for c in 1:nb_comm]
    sink =   [Commodity[c,2]+1 for c in 1:nb_comm]

    open_cost = [1 for k in 1:nb_nodes]
    func_cost = Function[1:end,2:end]'

    latency =  [[-1 for i in 1:nb_nodes] for j in 1:nb_nodes] #definie après
    max_latency = [Commodity[c,4] for c in 1:nb_comm]

    bandwidth = [Commodity[c,3] for c in 1:nb_comm]
    #println("Fucntion : ",Function)
    capacity = [Function[f,1] for f in 1:nb_func]

    max_func = [0 for k in 1:nb_nodes]
    for i in 1:nb_arcs
        max_func[Int(Arc[i,1])] = Arc[i,3]
        max_func[Int(Arc[i,2])] = Arc[i,4]
        latency[Int(Arc[i,1])][Int(Arc[i,2])] = Arc[i,5]
    end

    #println("Affinity : ",Affinity)
    exclusion = [[[0 for k in 1:nb_func ] for i in 1:nb_func] for j in 1:nb_comm]
    for i in 1:nb_comm
        if Affinity[i] != [] && Affinity[i]!=0
            #println(exclusion)
            exclusion[i][Int(Affinity[i,1])][Int(Affinity[i,2])] = 1
        end        
    end

    println(nb_comm,nb_nodes,nb_func)
    println(func_per_comm,func_per_comm_,source,sink)
    println(open_cost,func_cost,latency,max_latency,bandwidth,capacity,max_func)
    println(exclusion)
    # Defining model
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

    @variable(model, open_node[1:nb_nodes], Bin)  # 1 if node is open
    @variable(model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)  # Number of functions installed on node
    @variable(model, select_edge[1:nb_nodes, 1:nb_nodes, 1:nb_comm, 1:nb_func + 1], Bin)  # flow on edge for given commodity and stage
    @variable(model, exec_func[1:nb_nodes, 1:nb_comm, 0:nb_func + 1], Bin)  # 1 if function executed on node for given commodity

    @objective(  # Minimize opening and intallation cost
        model, Min,
        sum(open_cost[i] * open_node[i] for i in 1:nb_nodes) + sum(func_cost[i, f] * nb_functions[i, f] for i in 1:nb_nodes, f in 1:nb_func)
    )

    @constraint(  # Max latency on each commodity
        model, [comm = 1:nb_comm],
        sum(
            latency[i][j] * select_edge[i, j, comm, stage]
            for stage in 1:length(func_per_comm[comm]) + 1, i in 1:nb_nodes, j in 1:nb_nodes if latency[i][j] > 0
        ) <= max_latency[comm]
    )

    @constraint(  # Flow constraint
        model, [i = 1:nb_nodes, comm = 1:nb_comm, stage = 1:length(func_per_comm[comm]) + 1],
        sum(select_edge[j, i, comm, stage] for j in 1:nb_nodes if latency[j][i] > 0)
        - sum(select_edge[i, j, comm, stage] for j in 1:nb_nodes if latency[i][j] > 0)
        == exec_func[i, comm, func_per_comm_[comm][stage + 1]] - exec_func[i, comm, func_per_comm_[comm][stage]]
    )

    @constraint(  # Execute each function once
        model, [comm = 1:nb_comm, f = func_per_comm[comm]],
        sum(exec_func[i, comm, f] for i in 1:nb_nodes) == 1
    )

    @constraint(  # Fictive function on source
        model, [comm = 1:nb_comm],
        exec_func[source[comm], comm, 0] == 1
    )

    @constraint(  # Fictive function on sink
        model, [comm = 1:nb_comm],
        exec_func[sink[comm], comm, nb_func + 1] == 1
    )

    @constraint(  # Exclusion constraint
        model, [i = 1:nb_nodes, comm = 1:nb_comm, f = func_per_comm[comm], g = func_per_comm[comm]; exclusion[comm][f][g] == 1],
        exec_func[i, comm, f] + exec_func[i, comm, g] <= 1
    )

    @constraint(  # Limit on function capacity
        model, [i = 1:nb_nodes, f = 1:nb_func],
        sum(bandwidth[comm] * exec_func[i, comm, f] for comm in 1:nb_comm) <= capacity[f] * nb_functions[i, f]
    )

    @constraint(  # Install functions on open nodes
        model, [i = 1:nb_nodes],
        sum(nb_functions[i, f] for f in 1:nb_func) <= max_func[i] * open_node[i]
    )

    optimize!(model)

    # Print results
    for comm in 1:nb_comm
        print("commodity " * string(comm) * ": ")

        for stage in 1:length(func_per_comm[comm]) + 1

            stage_start = -1
            stage_end = -1
            for i in 1:nb_nodes
                if value(exec_func[i, comm, func_per_comm_[comm][stage]]) == 1
                    stage_start = i
                end
                if value(exec_func[i, comm, func_per_comm_[comm][stage + 1]]) == 1
                    stage_end = i
                end
            end
            if stage == 1
                print(string(stage_start))
            end

            current_pos = stage_start
            while current_pos != stage_end
                for next_pos in 1:nb_nodes
                    if value(select_edge[current_pos, next_pos, comm, stage]) == 1
                        print(" -> ")
                        print(string(next_pos))
                        current_pos = next_pos
                        break
                    end
                end
            end

            if stage != length(func_per_comm[comm]) + 1
                print("(f" * string(func_per_comm_[comm][stage + 1]) * ")")
            end
        end

        print("\n")
    end
    for i in 1:nb_nodes
        if value(open_node[i]) == 1
            print("node " * string(i) * ":")

            for f in 1:nb_func
                print(" f" * string(f) * " * " * string(Int(value(nb_functions[i, f]))) * ",")
            end

            print("\n")
        end
    end

end

main(ARGS[1])