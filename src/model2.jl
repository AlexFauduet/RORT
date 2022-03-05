using JuMP, CPLEX,ArgParse
include("read_files.jl")



function main(file_name :: String)
    nb_func,Function     = get_data("../instances/"*file_name*"Functions.txt",2)
    nb_func = Int(nb_func)
    nb_comm,Affinity   = get_data("../instances/"*file_name*"Affinity.txt", nb_func)
    useless,Fct_commod = get_data("../instances/"*file_name*"Fct_commod.txt" , nb_func)
    useless,Commodity  = get_data("../instances/"*file_name*"Commodity.txt" , nb_func)
    nb_nodes,nb_arcs,Arc      = get_data("../instances/"*file_name*"Graph.txt" , nb_func)

    #println("Function : ", Function)
    #println("Affinity  : ",Affinity )
    #println("nb_func : ",nb_func)
    #println("Fct_commod : ",Fct_commod )
    #println("Commodity  : ", Commodity )
    #println("Arc : ",Arc)

    func_per_comm = Fct_commod
    func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]

    source = [Commodity[c,1] for c in 1:nb_comm]
    sink =   [Commodity[c,1] for c in 1:nb_comm]

    open_cost = [1 for k in 1:nb_nodes]
    func_cost = Function[1:end,1:end]'
    println(func_cost)

    latency =  [[0 for i in 1:nb_nodes] for j in 1:nb_nodes] #definie après
    max_latency = [Commodity[c,4] for c in 1:nb_comm]

    bandwidth = [Commodity[c,3] for c in 1:nb_comm]
    capacity = [Function[1,f] for f in 1:nb_func]

    max_func = [0 for k in 1:nb_nodes]
    for i in 1:nb_arcs
        max_func[Int(Arc[1])+1] = Arc[3]
        max_func[Int(Arc[2])+1] = Arc[4]
        latency[Int(Arc[1])+1][Int(Arc[2])+1] = Arc[5]
        latency[Int(Arc[2])+1][Int(Arc[1])+1] = -Arc[5]
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

    @variable(model, open_node[1:nb_nodes], Bin)
    @variable(model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)
    @variable(model, select_edge[1:nb_nodes, 1:nb_nodes, 1:nb_comm, 1:nb_func + 1], Bin)
    @variable(model, exec_func[1:nb_nodes, 1:nb_comm, 0:nb_func + 1], Bin)

    @objective(
        model, Min,
        sum(open_cost[i] * open_node[i] for i in 1:nb_nodes) + sum(func_cost[i,f] * nb_functions[i, f] for i in 1:nb_nodes, f in 1:nb_func)
    )

    @constraint(
        model, [comm = 1:nb_comm],
        sum(
            latency[i][j] * select_edge[i, j, comm, stage]
            for stage in 1:length(func_per_comm[comm]) + 1, i in 1:nb_nodes, j in 1:nb_nodes if latency[i][j] > 0
        ) <= max_latency[comm]
    )

    @constraint(
        model, [i = 1:nb_nodes, comm = 1:nb_comm, stage = 1:length(func_per_comm[comm]) + 1],
        sum(select_edge[j, i, comm, stage] for j in 1:nb_nodes if latency[j][i] > 0)
        - sum(select_edge[i, j, comm, stage] for j in 1:nb_nodes if latency[i][j] > 0)
        == exec_func[i, comm, func_per_comm_[comm][stage + 1]] - exec_func[i, comm, func_per_comm_[comm][stage]]
    )

    @constraint(
        model, [comm = 1:nb_comm, f = func_per_comm[comm]],
        sum(exec_func[i, comm, f] for i in 1:nb_nodes) == 1
    )

    @constraint(
        model, [comm = 1:nb_comm],
        exec_func[source[comm], comm, 0] == 1
    )

    @constraint(
        model, [comm = 1:nb_comm],
        exec_func[sink[comm], comm, nb_func + 1] == 1
    )

    @constraint(
        model, [i = 1:nb_nodes, comm = 1:nb_comm, f = func_per_comm[comm], g = func_per_comm[comm]; exclusion[comm][f][g] == 1],
        exec_func[i, comm, f] + exec_func[i, comm, g] <= 1
    )

    @constraint(
        model, [i = 1:nb_nodes, f = 1:nb_func],
        sum(bandwidth[comm] * exec_func[i, comm, f] for comm in 1:nb_comm) <= capacity[f] * nb_functions[i, f]
    )

    @constraint(
        model, [i = 1:nb_nodes],
        sum(nb_functions[i, f] for f in 1:nb_func) <= max_func[i] * open_node[i]
    )

    optimize!(model)

    @show value.(open_node)
    @show value.(nb_functions)
    @show value.(select_edge)
    @show value.(exec_func)

end

main(ARGS[1])