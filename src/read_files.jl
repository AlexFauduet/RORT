using JuMP

export get_data

function get_data(file_name :: String)
	if isfile(file_name)
        file=open(file_name)
		data = readlines(file)
        println(data)
        if occursin("Affinity.txt",file_name)
            nb_commodities = length(data)-1
            Affinity = []
            if nb_commodities >= 1
                tab = split(data[1]," ")
                println(tab)
                if tab != SubString{String}[""]  #j'ai suppose qu'on avait tjs des fonction pour la premeir commodite -> a changer si pb
                    Affinity = Array{Int64}(undef,nb_commodities)
                    Affinity = parse(Int64,tab)
                    for i in 2:nb_commodities
                        tab = split(data[i]," ")
                        if tab != SubString{String}[""]
                            vcat(Commodity,parse(Int64,tab))
                        else 
                            vcat(Commodity,[])
                        end 
                    end
                end
            end
            close(file)
            return (nb_commodities,Affinity)
        end

        if occursin("Commodity.txt",file_name)
            nb_commodities = parse(Int64,data[2][16:end])
            Commodity = Array{Int64}(undef,nb_commodities,4)
            for i in 1:nb_commodities
                tab = split(data[2+i]," ")
                for j in 1:4
                    Commodity[i,j] = parse(Int64,tab[j])
                end
            end
            close(file)
            return (nb_commodities,Commodity)
        end

        if occursin("Commod.txt",file_name)
            nb_commodities = length(data)-1
            Fct_commod = Array{Int64,2}(zeros(nb_commodities,nb_func))
            for i in 1:nb_commodities
                line = parse.(Int64, split(readline(file), " "))
                cpt=1
                for f in line
                    Fct_commod[i,f+1]=cpt
                    cpt=cpt+1
                end
            end
            close(file)
            return (cpt,Fct_commod)
        end

        if occursin("Functions.txt",file_name)
            nb_functions = parse(Int64,data[2][14:end])
            tab = split(data[3]," ")
            size = length(tab)-1
            Function = Array{Int64}(undef,nb_functions,size)  
            for i in 1:nb_functions
                tab = split(data[2+i]," ")
                for j in 1:size
                    Function[i,j] = parse(Int64,tab[j])
                end
            end
            close(file)
            return (nb_functions,Function)
        end

        if occursin("Graph.txt",file_name)
            nb_nodes = parse(Int64,data[2][10:end])
            nb_arcs  = parse(Int64,data[3][9:end])
            println(nb_arcs)
            Arc = Array{Int64}(undef,nb_arcs,5)
            for i in 1:nb_arcs
                tab = split(data[3+i]," ")
                for j in 1:5
                    Arc[i,j] = parse(Int64,tab[j])
                end
            end
            return (nb_nodes,nb_arcs,Arc)
        end
        return "fichier erroné"
		
	end
	return "fichier inexistant"
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

#nb_nodes,nb_arcs,Arc=get_data("../instances/grille2x3_Graph.txt")
print(get_data("../instances/grille2x3_Fct_Commod.txt"))
