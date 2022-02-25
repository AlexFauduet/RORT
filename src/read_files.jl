using JuMP

export get_data

function get_data(file_name :: String,nb_functions ::Int64)
	if isfile(file_name)
        file=open(file_name)
		data = readlines(file)
        #println(data)
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

        if occursin("Commod.txt",file_name)
            nb_commodities = length(data)
            Fct_commod = Array{Int64}(undef,nb_commodities,nb_functions)
            for i in 1:nb_commodities
                tab = split(data[i]," ")
                #print(tab)
                for j in 1:length(tab)-1
                    Fct_commod[i,j] = parse(Int64,tab[j])
                end
                for j in length(tab):nb_functions
                    Fct_commod[i,j] = -1
                end
            end
            close(file)
            return (nb_commodities,Fct_commod)
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



#en ecriture...

function write_results(fileName,e,x_ikf)
  
  cout_ouverture, Fct_commod, func_cost, func_capacity, nb_nodes, nb_arcs, nb_commodities, latency, node_capacity, commodity, nb_func, exclusion = read_instance(fileName)
  
  if !isfile("./Resultats/"*fileName*".txt") 
		touch("./Resultats/"*fileName*".txt")
	end
	file = open("./Resultats/"*fileName*".txt","w")

	for k in 1:nb_commodities
    size_fk=length( findall( y -> y > 0, Fct_commod[k,:]))
		tab_fk=sortperm( Fct_commod[k,:])[1:size_fk]
		write(file,"commod "*string(k)*'\n')
		
    #write source to first function
		s=commodity[k,1]
		p= findall( y -> y == 1., x_ikf[:,k,tab_fk[1]])[1,1,1]
		sol=string(s)
		i=s
		while i!=p
			i=findall(y->y==1., e[i,:,k,tab_fk[1]])[1,1,1,1]
			sol=sol*" "*string(i)
		end
		sol=sol*'\n'
		write(file,sol)
		
    #write function to function
		for f in tab_fk[2:end]
			s=p
			p= findall( y -> y == 1., x_ikf[:,k,f])[1,1,1]
			sol=string(s)
			i=s
			while i!=p
				i=findall(y->y==1., e[i,:,k,f])[1,1,1,1]
				sol=sol*" "*string(i)
			end
			sol=sol*'\n'
			write(file,sol)
		end
    
    #write function to sink
    s=p
    p=commodity[k,2]
    sol=string(s)
    i=s
    while i!=p
      i=findall(y->y==1., e[i,:,k,end])[1,1,1,1]
      sol=sol*" "*string(i)
    end
    sol=sol*'\n'
    write(file,sol)
	end
	
	close(file)
end
#nb_nodes,nb_arcs,Arc=get_data("../instances/grille2x3_Graph.txt")
nb_commodities,Fct_commod = get_data("../instances/grille2x3_Fct_Commod.txt",2)
#print(get_data("../instances/grille2x3_Fct_Commod.txt",2))

println("nb_commodities = ", nb_commodities)
println("fct = " ,Fct_commod)
