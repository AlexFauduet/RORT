using JuMP

function get_data(file_name :: String,nb_functions ::Int64)
	if isfile(file_name)
        file=open(file_name)
		data = readlines(file)
        #println(data)
         if occursin("Affinity.txt",file_name)
            #println(data)
            nb_commodities = length(data)
            Affinity = zero(rand(nb_commodities,2))
            for i in 1:nb_commodities
                tab = split(data[i]," ")
                if tab != SubString{String}[""] && tab != SubString{String}["", ""]
                    Affinity[i,1] = parse(Int64,tab[1])
                    Affinity[i,1] = Affinity[i,1] + 1
                    Affinity[i,2] = parse(Int64,tab[2])
                    Affinity[i,2] = Affinity[i,2] + 1
                end 
            end
            close(file)
            return (nb_commodities,Affinity)
        end
        
       

        if occursin("commod.txt",file_name)
            nb_commodities = length(data)
            tab = split(data[1]," ")
            #println("nb_functions",nb_functions)
            Fct_commod = Array{Int64}(undef,nb_commodities,length(tab)-1)
            for i in 1:nb_commodities
                tab = split(data[i]," ")
                #print(tab)
                for j in 1:length(tab)-1
                    Fct_commod[i,j] = parse(Int64,tab[j])+1
                end
                #for j in length(tab):nb_functions
                #    Fct_commod[i,j] = -1
                #end
            end
            close(file)
            return (nb_commodities,Fct_commod)
        end

        if occursin("Commodity.txt",file_name)
            nb_commodities = parse(Int64,data[2][16:end])
            Commodity = Array{Float64}(undef,nb_commodities,4)
            Commodity_f = Array{Int64}(undef,nb_commodities,4)
            for i in 1:nb_commodities
                tab = split(data[2+i]," ")
                for j in 1:4
                    Commodity[i,j] = parse(Float64,(tab[j]))
                    Commodity[i,j] = round(Commodity[i,j])
                    Commodity_f[i,j] = Int64(Commodity[i,j])
                end
            end
            close(file)
            return (nb_commodities,Commodity_f)
        end
       

        if occursin("Functions.txt",file_name)
            nb_functions = parse(Int64,data[2][14:end])
            tab = split(data[3]," ")
            size = length(tab)
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
            #println(nb_arcs)
            Arc = Array{Float64}(undef,nb_arcs,5)
            Arc_f = Array{Int64}(undef,nb_arcs,5)
            for i in 1:nb_arcs
                tab = split(data[3+i]," ")
                for j in 1:2
                    Arc[i,j] = parse(Int64,tab[j])+1
                    Arc_f[i,j] = Int64(Arc[i,j] )
                end
                Arc[i,3] = parse(Float64,tab[4])
                Arc_f[i,3] = Int64(Arc[i,3])
                Arc[i,4] = parse(Float64,tab[5])
                Arc_f[i,4] = Int64(Arc[i,4])
                Arc[i,5] = parse(Float64,tab[6])
                Arc[i,5] = round(Arc[i,5])
                Arc_f[i,5] = Int64(Arc[i,5])
            end
            return (nb_nodes,nb_arcs,Arc_f)
        end
        return "fichier erroné"
		
	end
	return "fichier inexistant"
end


#nb_nodes,nb_arcs,Arc=get_data("../instances/grille2x3_Graph.txt")
#nb_commodities,Fct_commod = get_data("../instances/grille2x3_Fct_Commod.txt",2)
#println("nb_commodities = ", nb_commodities)
#println("fct = " ,Fct_commod)
#print(get_data("../instances/grille2x3_Fct_Commod.txt",2))
println(get_data("../instances/abilene/abilene_1/Fct_commod.txt",26))
#println(get_data("../instances/grille2x3_Affinity.txt",2))
#println(get_data("../instances/grille2x3_Functions.txt",2))
#println(get_data("../instances/test1_Fct_commod.txt",3))