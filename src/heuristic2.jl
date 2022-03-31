using JuMP, CPLEX,ArgParse
include("read_files.jl")
include("utils.jl")


#file_names = ["dfn-bwin/dfn-bwin_1/","dfn-bwin/dfn-bwin_2/","dfn-bwin/dfn-bwin_3/","dfn-bwin/dfn-bwin_4/","dfn-bwin/dfn-bwin_5/","dfn-bwin/dfn-bwin_6/","dfn-bwin/dfn-bwin_7/","dfn-bwin/dfn-bwin_8/","dfn-bwin/dfn-bwin_9/","dfn-bwin/dfn-bwin_10/","di-yuan/di-yan_1/","di-yuan/di-yan_2/","di-yuan/di-yan_3/","di-yuan/di-yan_4/","di-yuan/di-yan_5/","di-yuan/di-yan_6/","di-yuan/di-yan_7/","di-yuan/di-yan_8/","di-yuan/di-yan_9/","di-yuan/di-yan_10/"]
file_names = ["di-yuan/di-yuan_1/","di-yuan/di-yuan_2/","di-yuan/di-yuan_3/","di-yuan/di-yuan_4/","di-yuan/di-yuan_5/","di-yuan/di-yuan_6/","di-yuan/di-yuan_7/","di-yuan/di-yuan_8/","di-yuan/di-yuan_9/","di-yuan/di-yuan_10/"]



for file_name in file_names
    println("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    println("                                 ")
    println("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    println("                                 ")
    println(file_name)
    println("                                 ")
    println("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    println("                                 ")
    println("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

    #Leture des instances
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


    function mp_heuristic()
        # Defining model
        mp_h = Model(CPLEX.Optimizer)
        set_optimizer_attribute(mp_h, "CPX_PARAM_EPINT", 1e-5)

        @variable(mp_h, open_node[1:nb_nodes], Bin)  # 1 if node is open
        @variable(mp_h, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)  # Number of functions installed on node
        @variable(mp_h, select_edge[1:nb_nodes, 1:nb_nodes, 1:nb_comm, 1:nb_func + 1], Bin)  # flow on edge for given commodity and stage
        @variable(mp_h, exec_func[1:nb_nodes, 1:nb_comm, 0:nb_func + 1], Bin)  # 1 if function executed on node for given commodity

        @expression(mp_h, node_open_cost,sum(open_cost[i] * open_node[i] for i in 1:nb_nodes) )
        @expression(mp_h, func_install_cost,sum(func_cost[i, f] * nb_functions[i, f] for i in 1:nb_nodes, f in 1:nb_func))

        # Minimize opening and intallation cost
        @objective(  mp_h, Min,node_open_cost)
        #@objective(  mp_h, Min,func_install_cost)

        # Max latency on each commodity
        @constraint(mp_h, [comm = 1:nb_comm],sum(latency[i, j] * select_edge[i, j, comm, stage] for stage in 1:length(func_per_comm[comm]) + 1, i in 1:nb_nodes, j in 1:nb_nodes if latency[i, j] > 0) <= max_latency[comm])
        # Flow constraint
        @constraint(mp_h, [i = 1:nb_nodes, comm = 1:nb_comm, stage = 1:length(func_per_comm[comm]) + 1],sum(select_edge[j, i, comm, stage] for j in 1:nb_nodes if latency[j, i] > 0)- sum(select_edge[i, j, comm, stage] for j in 1:nb_nodes if latency[i, j] > 0)== exec_func[i, comm, stage] - exec_func[i, comm, stage - 1])
        # Execute each function once
        @constraint(mp_h, [comm = 1:nb_comm, stage = 1:length(func_per_comm[comm])],sum(exec_func[i, comm, stage] for i in 1:nb_nodes) == 1)
        # Fictive function on source
        @constraint(mp_h, [comm = 1:nb_comm],exec_func[source[comm], comm, 0] == 1)
        # Fictive function on sink
        @constraint(mp_h, [comm = 1:nb_comm],exec_func[sink[comm], comm, length(func_per_comm[comm])] == 1)
        # Exclusion constraint
        @constraint( mp_h, [i = 1:nb_nodes, comm = 1:nb_comm, stage_k = 1:length(func_per_comm[comm]), stage_l = 1:length(func_per_comm[comm]);exclusion[comm][func_per_comm[comm][stage_k]][func_per_comm[comm][stage_l]] == 1],exec_func[i, comm, stage_k] + exec_func[i, comm, stage_l] <= 1)
        # Limit on function capacity
        @constraint(mp_h, [i = 1:nb_nodes, f = 1:nb_func],sum(sum(bandwidth[comm] * exec_func[i, comm, stage] for stage in 1:length(func_per_comm[comm]) if func_per_comm[comm][stage] == f) for comm in 1:nb_comm    ) <= capacity[f] * nb_functions[i, f])
        # Install functions on open nodes
        @constraint(mp_h, [i = 1:nb_nodes],sum(nb_functions[i, f] for f in 1:nb_func) <= max_func[i] * open_node[i])

        optimize!(mp_h)
        println("value.(nb_functions)",value.(nb_functions))
        println("nb_functions",nb_functions)

        return node_open_cost, func_install_cost, exec_func, select_edge, func_per_comm, open_node, nb_functions, value.(exec_func), value.(bandwidth), value.(nb_functions), value.(open_node)
    end

    node_open_cost, func_install_cost, exec_func, select_edge, func_per_comm, open_node, nb_functions, val_exec_func, val_bandwidth, val_nb_functions, val_open_node= mp_heuristic()


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

        if round(Int, value(val_open_node[i])) == 1
            print("node " * string(i) * ":")

            for f in 1:nb_func
                print(" f" * string(f) * " * " * string(round(Int, value(nb_functions[i, f]))) * ",")
            end

            print("\n")
        end
    end
end