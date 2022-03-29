#=
utils:
- Julia version: 1.7.2
- Author: alex
- Date: 2022-03-29
=#

using Graphs

function compute_shortest_paths(nb_nodes, latency)
    latency_ = copy(latency)
    for i in 1:nb_nodes
        for j in 1:nb_nodes
            if latency_[i, j] == -1
                latency_[i, j] += 1
            end
        end
    end
    graph = SimpleDiGraph(latency_)

    sp = floyd_warshall_shortest_paths(graph)

    latency_sp = sp.dists
    shortest_path = enumerate_paths(sp)
    for i in 1:nb_nodes
        for j in 1:nb_nodes
            if shortest_path[i][j] != []
                shortest_path[i][j] = shortest_path[i][j][2:end]
            end
        end
    end

    return latency_sp, shortest_path
end