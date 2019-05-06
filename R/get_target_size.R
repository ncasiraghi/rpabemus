#' get_target_size
#' @param targetbed targeted regions in BED format
#' @param Mbp return count as Mbp. default: TRUE
#' @return Mbp covered in the BED file
#' @export
get_target_size <- function(targetbed,Mbp = TRUE){
  bed <- fread(input = targetbed,colClasses = list(character=1),data.table = F,stringsAsFactors = F,header = F)
  if(Mbp){
    return( sum(bed$V3-bed$V2)/1e+6 )
  } else {
    return( sum(bed$V3-bed$V2) )
  }
}