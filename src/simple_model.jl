#=
test:
- Julia version: 1.7.2
- Author: alex
- Date: 2022-02-15
=#

using JuMP, CPLEX

#model avec test1 (cours)

# Defining parameters
nb_comm = 2
nb_nodes = 4
nb_func = 3

func_per_comm = [[1, 2, 3], [2, 1]]

source = [1, 2]
sink = [3, 4]

open_cost = [1, 1, 1, 1]
func_cost = [1 1 1; 1 1 1; 1 1 1; 1 1 1]

latency = [-1 1 -1 1; 1 -1 1 -1; -1 1 -1 1; 1 -1 1 -1]
max_latency = [5, 3]

bandwidth = [20, 2]
capacity = [10, 10, 10]

max_func = [3, 3, 3, 3]

exclusion = [[0 1 0; 1 0 0; 0 0 0], [0 1 0; 1 0 0; 0 0 0]]

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
    exec_func[sink[comm], comm,length(func_per_comm[comm])] == 1
)

@constraint(  # Exclusion constraint
    model, [
        i = 1:nb_nodes, comm = 1:nb_comm, stage_k = 1:length(func_per_comm[comm]), stage_l = 1:length(func_per_comm[comm]);
        exclusion[comm][func_per_comm[comm][stage_k], func_per_comm[comm][stage_l]] == 1
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
for comm in 1:nb_comm
    print("commodity " * string(comm) * ": ")

    for stage in 1:length(func_per_comm[comm]) + 1

        stage_start = -1
        stage_end = -1
        for i in 1:nb_nodes
            if value(exec_func[i, comm, stage - 1]) == 1
                stage_start = i
            end
            if value(exec_func[i, comm, stage]) == 1
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
            print("(f" * string(func_per_comm[comm][stage]) * ")")
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
