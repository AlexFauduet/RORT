using JuMP

export get_data

function get_data(file_name :: String)
	if isfile(file_name)
        file=open(file_name)
		data = readlines(file)
        if occursin("Affinity.txt",file_name)

            return ()
        end

        if occursin("Commodity.txt",file_name)
            nb_commodities = parse(Int64,data[2][16:end])
            Commodity = Array{Int64}(undef,nb_commodities,4)
            for i in 1:nb_commodities
                Commodity[i,:] = [split(data[2+i]," ")]
            end
            return (nb_commodities,Commodity)
        end

        if occursin("Commod.txt",file_name)

            return ()
        end

        if occursin("Functions.txt",file_name)
            nb_functions = parse(Int64,data[2][14:end])
            size = length([split(data[3]," ")])
            Function = Array{Int64}(undef,nb_commodities,size)
            for i in 1:nb_functions
                Function[i,:] = [split(data[2+i]," ")]
            end
            return (nb_functions,Function)
        end

        if occursin("Graph.txt",file_name)
            nb_nodes = parse(Int64,data[2][10:end])
            nb_arcs  = parse(Int64,data[3][9:end])
            Arc = Array{Int64}(undef,nb_arc,5)
            for i in 1:nb_arcs
                Arc[i,:] = [split(data[3+i]," ")]
            end
            return (nb_nodes,nb_arc,Arc)
        end
	
		
	end
	return
end

function write_sol(algo, file, isOptimal, traj, sol, cpt , sec,obj)
	println("isOptimal : ", isOptimal)
	println(" traj : ", traj)
	println("obj : ",obj)
	println(" sol : ", sol)
	println("  cpt: ",cpt )
	println(" sec : ", sec)
	output_folder = "../results/"*algo
	println("output_folder : ",output_folder)
	output_file = "../results/"*algo*"/"*file*"_score_"*string(round(obj,digits=3))*"_"*string(sec)*".txt"
	println("output_file : ",output_file)
	if !isdir(output_folder)
            mkdir(output_folder)
        end
	if !isfile(output_file)
		f = open(output_file, "w")
		println(f, "Valeur solution optimale trouvée :", round(obj,digits=3))
		println(f, "Solution optimale trouvée : ",isOptimal)
		println(f, "Valeur de la solution : ",traj)
		println(f, "Temps : ",sec)
		println(f, "Solution : ",sol )
		println(f, "Nombre de branchements : ",cpt )
		close(f)
    end	
end