using JuMP, CPLEX,ArgParse
include("read_files.jl")



function main(file_name :: String)
    nb_functions,Function     = get_data("../instances/"*file_name*"_Function.txt",0)
    nb_functions = Int(nb_functions)
    nb_commodities,Affinity   = get_data("../instances/"*file_name*"_Affinity.txt", nb_functions)
    nb_commodities,Fct_commod = get_data("../instances/"*file_name*"_Fct_Commod.txt" , nb_functions)
    nb_commodities,Commodity  = get_data("../instances/"*file_name*"_Commodity.txt" , nb_functions)
    nb_nodes,nb_arcs,Arc      = get_data("../instances/"*file_name*"_Graph.txt" , nb_functions)

end

main(ARGS[1])