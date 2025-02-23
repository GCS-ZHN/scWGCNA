#' Calculates pseudocells from a Seurat object
#' 
#' This function calculates pseudocells from a Seurat object, based on pre-calculated cell clusters and dimentionality reduction. WARNING: This might be time consuming, depending on the size of the dataset.
#' @param s.cells The seurat object, with pre-computed PCA or other reductions, and the relevant clustering as IDs
#' @param seeds The proportion of cells to be used as seeds. Alternatively, a string with the name of the seeds to use. Numeric between 0.1 and 0.9 or string. Default 0.2
#' @param nn Number of nearest neighbors to compute and use for pseudocell aggregation. Default 10
#' @param reduction The name of the reduction to use. Should be present in the @@reductions slot of the seurat object. Default is "pca"
#' @param dims The relevant dimensions that will be used to compute nearest neighbors. Default 1:20
#' @param features The features to be used. Takes a string of feature names as present in the expression matrices. Defaults to NULL, which will use all the genes.
#' @param cells The clusters or identities to be used. Takes a string of identities as present in the @@active.ident slot. Defaults to NULL, which will use all the identities.
#' @param rseed Numeric. The random  number generator of R, used to sample the seed cells. Makes the function replicable.
#' @return A seurat object of aggregated pseudocells. With average expression. The slot misc contains the pseudocells dataframe, with each original cell and its assigned pseudocell, if no pseudocell is assigned then 00
#' @export
#' @examples
#' MmLimbE155.ps=calculate.pseudocells(my.small_MmLimbE155, dims = 1:10)

calculate.pseudocells <- function(s.cells, seeds=0.2, nn = 10, reduction = "pca", dims = 1:20, features =NULL, cells= NULL, rseed=42) {

  if(!class(s.cells)=="Seurat"){
    return(cat("Please provide a Seurat object"))
  }
  
  #if we're using a subset of the cells
  if (!is.null(cells)) {
    s.cells = subset(s.cells, idents=cells)
  }
  
  #if we're using a subset of the features / genes
  if (!is.null(features)) {
    s.cells = subset(s.cells, features=features)
  }
  
  # Do the nn calculation, using seurat
  s.cells = Seurat::FindNeighbors(s.cells,
                         reduction = reduction,
                         dims = dims,
                         k.param = nn)
  
  # Extract the nn matrix
  nn.matrix = s.cells@graphs[[paste0(Seurat::DefaultAssay(s.cells),"_nn")]]
  
  # To keep count
  my.seeds = list()
  seeds.count = c()
  
  # Here, to check which set of randomly selected seed we'll use
  if (is.numeric(seeds)) {
    
    message("Choosing seeds")
    
    set.seed(rseed)
    
    for (i in 1:50) {
      
      seed.set =c()
      
      #go trhough each cluster or ID
      for (cluster in levels(Seurat::Idents(s.cells)) ) {
        
        # How many seeds? According to proportion
        n.seeds = floor(table(Seurat::Idents(s.cells))[[cluster]]/(1/seeds))
        # Choose the seeds
        seed.set=c(seed.set, sample(rownames(s.cells@meta.data)[Seurat::Idents(s.cells) == cluster], n.seeds) )
      }
      
      # Keep count of the seeds
      my.seeds[[i]] = seed.set
      rm(seed.set)
      
      #How many cells would be aggragated using this particular set of seeds?
      seeds.count = c(seeds.count, length(which(Matrix::colSums(nn.matrix[my.seeds[[i]],]) > 0)) )
      
    }
    
    # Choose the one with the highest count
    seeds = my.seeds[[which.max(seeds.count)]]
    
  }
  
  #Subset the nn matrix, to only keep the seeds
  nn.matrix = nn.matrix[seeds, ]
  #Only keep the cells that would be aggregated
  nn.matrix = nn.matrix[,Matrix::colSums(nn.matrix) > 0 ]
  
  message(ncol(nn.matrix)," out of ", ncol(s.cells)," Cells will be agreggated into ",nrow(nn.matrix)," Pseudocells")
  
  #create a data frame, to keep record of cells and pseudocells. Non-asigned cells are 00
  my.pseudocells = data.frame(pseudocell = rep("00",nrow(s.cells@meta.data)), row.names = rownames(s.cells@meta.data))
  
  my.pseudocells$pseudocell = as.character(my.pseudocells$pseudocell)
  
  # First, each seed is assigned to iself
  my.pseudocells[seeds,1] = seeds
  # We remove the seeds from the universe to choose from
  nn.matrix = nn.matrix[,-which(colnames(nn.matrix) %in% seeds)]
  # Which cells are up for grabs?
  remaining.cells = colnames(nn.matrix)
  
  message("Assining pseudocells")
  
  while (length(remaining.cells) > 0) {
    #we go seed by seed, starting by the poorest seeds
    for (s in rownames(nn.matrix)[order(Matrix::rowSums(nn.matrix[,remaining.cells, drop = F]))]) {
      # If the seed still has options to choose from
      if ( sum(nn.matrix[s, remaining.cells]) > 0 & length(remaining.cells) > 0) {
        # take one of the seed nn
        c = sample(which(nn.matrix[s, remaining.cells] == 1),1)
        # Assign that nn to the seed
        my.pseudocells[remaining.cells[c],1] = s
        # Remove the nn from the universe to choose from
        remaining.cells = remaining.cells[-c]
        
      }
      # If all cells are assigned, stop
      if (length(remaining.cells) == 0) {break}
      
    }
    
  }
  
  # Make a new seurat object, using only the cells we assigned
  ps.seurat = subset(s.cells, cells = rownames(my.pseudocells)[my.pseudocells$pseudocell != "00"])
  
  # Add a new metadata column, with the pseudocell (seeds) info and set the identity
  ps.seurat = Seurat::AddMetaData(object = ps.seurat, metadata = my.pseudocells, col.name = "pseudo.ident")
  ps.seurat = Seurat::SetIdent(ps.seurat, value = "pseudo.ident")
  
  message("Aggregating pseudocell expression")
  
  # Aggregate the cells using seurat. get the average expression
  ps.seurat = Seurat::AverageExpression(object = ps.seurat,
                                return.seurat = T,
                                verbose = F)
  # Rescue the original cluster of each pseudocell!
  ps.seurat@meta.data$orig.cluster = Seurat::Idents(s.cells)[match(rownames(ps.seurat@meta.data), rownames(s.cells@meta.data))]
  
  # Add our records of cells to the misc slot
  ps.seurat@misc[["peudocells"]] = my.pseudocells
  
  # DONE
  return(ps.seurat)

}


