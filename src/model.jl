#=
test:
- Julia version: 1.7.2
- Author: alex
- Date: 2022-02-15
=#

using JuMP, CPLEX


# Defining parameters
nb_comm = 2
nb_nodes = 4
nb_func = 3

func_per_comm = [[1, 2, 3], [2, 1]]
func_per_comm_ = [cat(cat([0], func_per_comm[comm], dims=1), [nb_func + 1], dims=1) for comm in 1:nb_comm]

source = [1, 2]
sink = [3, 4]

open_cost = [1, 1, 1, 1]
func_cost = [1 1 1; 1 1 1; 1 1 1; 1 1 1]

latency = [-1 1 -1 1; 1 -1 1 -1; -1 1 -1 1; 1 -1 1 -1]
max_latency = [3, 3]

bandwidth = [20, 2]
capacity = [10, 10, 10]

max_func = [3, 3, 3, 3]

exclusion = [[0 1 0; 1 0 0; 0 0 0], [0 1 0; 1 0 0; 0 0 0]]

# Defining model
model = Model(CPLEX.Optimizer)
set_optimizer_attribute(model, "CPX_PARAM_EPINT", 1e-8)

@variable(model, open_node[1:nb_nodes], Bin)
@variable(model, nb_functions[1:nb_nodes, 1:nb_func] >= 0, Int)
@variable(model, select_edge[1:nb_nodes, 1:nb_nodes, 1:nb_comm, 1:nb_func + 1], Bin)
@variable(model, exec_func[1:nb_nodes, 1:nb_comm, 0:nb_func + 1], Bin)

@objective(
    model, Min,
    sum(open_cost[i] * open_node[i] for i in 1:nb_nodes) + sum(func_cost[i, f] * nb_functions[i, f] for i in 1:nb_nodes, f in 1:nb_func)
)

@constraint(
    model, [comm = 1:nb_comm],
    sum(
        latency[i, j] * select_edge[i, j, comm, stage]
        for stage in 1:length(func_per_comm[comm]) + 1, i in 1:nb_nodes, j in 1:nb_nodes if latency[i, j] > 0
    ) <= max_latency[comm]
)

@constraint(
    model, [i = 1:nb_nodes, comm = 1:nb_comm, stage = 1:length(func_per_comm[comm]) + 1],
    sum(select_edge[j, i, comm, stage] for j in 1:nb_nodes if latency[j, i] > 0)
    - sum(select_edge[i, j, comm, stage] for j in 1:nb_nodes if latency[i, j] > 0)
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
    model, [i = 1:nb_nodes, comm = 1:nb_comm, f = func_per_comm[comm], g = func_per_comm[comm]; exclusion[comm][f, g] == 1],
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
