library("moveapps")
library("move2")
library("lubridate")

## The parameter "data" is reserved for the data object passed on from the previous app

# to display messages to the user in the log file of the App in MoveApps
# one can use the function from the logger.R file:
# logger.fatal(), logger.error(), logger.warn(), logger.info(), logger.debug(), logger.trace()

# Showcase injecting app setting (parameter `year`)
rFunction = function(data, sdk, year, ...) {
  logger.info(paste("Welcome to the", sdk))
  result <- if (any(lubridate::year(move2::mt_time(data)) == year)) { 
    data[lubridate::year(move2::mt_time(data)) == year,]
  } else {
    NULL
  }
  if (!is.null(result)) {
    # Showcase creating an app artifact. 
    # This artifact can be downloaded by the workflow user on Moveapps.
    artifact <- appArtifactPath("plot.png")
    logger.info(paste("plotting to artifact:", artifact))
    png(artifact)
    plot(result[move2::mt_track_id_column(result)], max.plot=1)
    dev.off()
  } else {
    logger.warn("nothing to plot")
  }
  # Showcase to access a file ('auxiliary files') that is 
  # a) provided by the app-developer and 
  # b) can be overridden by the workflow user.
  fileName <- getAuxiliaryFilePath("auxiliary-file-a")
  logger.info(readChar(fileName, file.info(fileName)$size))

  # provide my result to the next app in the MoveApps workflow
  return(result)
}





#######-----------------#######
## 3. basic cleaning of data ##
#######-----------------#######
## data are cleaned: empty locations, "0,0" coordinates and duplicated timestamps are removed

library(move2)
library(units)
library(dplyr)

## in case in parallel is an option
# library(doParallel)
# library(plyr)
# mycores <- detectCores()-1
# registerDoParallel(mycores)
# library(dplyr)

pathTOfolder <- "./MBdata/"
pthDownld <- paste0(pathTOfolder,"01_MB_indv_mv2/")
dir.create(paste0(pathTOfolder,"02_MB_indv_mv2_clean"))
pthClean <- paste0(pathTOfolder,"02_MB_indv_mv2_clean/")

flsMV <- list.files(pthDownld, full.names = F)
done <- list.files(pthClean, full.names = F) #checking which have been already done in case an error occurs and script stops
flsMV <- flsMV[!flsMV%in%done]

## remove empty locs, 0,0 corrds and duplicated ts
start_time <- Sys.time()
# indPth <- flsMV[10]
lapply(flsMV, function(indPth){
  # llply(flsMV, function(indPth){
  mv2 <- readRDS(paste0(pthDownld,indPth))
  if(!mt_is_track_id_cleaved(mv2)){mv2 <- mv2 |> dplyr::arrange(mt_track_id(mv2))} ## order by tracks
  if(!mt_is_time_ordered(mv2)){mv2 <- mv2 |> dplyr::arrange(mt_track_id(mv2),mt_time(mv2))} # order time within tracks
  if(!mt_has_no_empty_points(mv2)){mv2 <- mv2[!sf::st_is_empty(mv2),]} ## remove empty locs
  
  ## sometimes only lat or long are NA
  crds <- sf::st_coordinates(mv2)
  rem <- unique(c(which(is.na(crds[,1])),which(is.na(crds[,2]))))
  if(length(rem)>0){mv2 <- mv2[-rem,]}
  
  ## remove 0,0 coordinates
  rem0 <- which(crds[,1]==0 & crds[,2]==0)
  if(length(rem0)>0){mv2 <- mv2[-rem0,]}
  
  ## retain the duplicate entry which contains the least number of columns with NA values
  mv2 <- mv2 %>%
    mutate(n_na = rowSums(is.na(pick(everything())))) %>%
    arrange(n_na) %>%
    mt_filter_unique(criterion='first') %>% # this always needs to be "first" because the duplicates get ordered according to the number of columns with NA. 
    dplyr::arrange(mt_track_id()) %>%
    dplyr::arrange(mt_track_id(),mt_time())
  
  saveRDS(mv2, file=paste0(pthClean,indPth))
} )
# } ,.parallel = T)
end_time <- Sys.time()
end_time - start_time # 
