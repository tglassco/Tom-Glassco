##########################################################################################
################## Read, manipulate and write raster data
##########################################################################################

########################################################################################## 
# Contact: remi.dannunzio@fao.org
# Last update: 2018-10-14
##########################################################################################

time_start  <- Sys.time()

if(!(file.exists(paste0(lc_dir,"LCF2015_Liberia_32629_10m.tif")))){
  system(sprintf("wget -O %s %s",
                 paste0(lc_dir,"LCF2015_Liberia_32629_10m.tif"),
                 "https://www.dropbox.com/s/7f4hjbn40oktprv/LCF2015_Liberia_32629_10m.tif?dl=0"))}


lcc_map <- paste0(bfst_dir,list.files(bfst_dir,pattern = glob2rx("*.tif"))[1])
  
####################################################################################
####### PREPARE COMMODITY MAP (RASTERIZE AND CLIP TO EXTENT)
####################################################################################
shp <- readOGR(paste0(ag_dir,"all_farms_merged.shp"))
dbf <- shp@data
dbf$unique_id <- row(dbf)[,1]
shp@data <- dbf

shp <- spTransform(shp,CRS('+init=epsg:4326'))

writeOGR(shp,paste0(ag_dir,"commodities.shp"),paste0(ag_dir,"commodities"),"ESRI Shapefile",overwrite_layer = T)

head(shp)
system(sprintf("python %s/oft-rasterize_attr.py -v %s -i %s -o %s -a %s",
               scriptdir,
               paste0(ag_dir,"commodities.shp"),
               lcc_map,
               paste0(ag_dir,"commodities.tif"),
               "unique_id"
))

#################### ALIGN PRODUCTS ON MASK: BFAST RESULTS
mask   <- lcc_map
proj   <- proj4string(raster(mask))
extent <- extent(raster(mask))
res    <- res(raster(mask))[1]


#################### INPUT : GEOVILLE MAP 2015
input  <- paste0(lc_dir,"LCF2015_Liberia_32629_10m.tif")
ouput  <- paste0(lc_dir,"lc_2015.tif")

system(sprintf("gdalwarp -co COMPRESS=LZW -t_srs \"%s\" -te %s %s %s %s -tr %s %s %s %s -overwrite",
               proj4string(raster(mask)),
               extent(raster(mask))@xmin,
               extent(raster(mask))@ymin,
               extent(raster(mask))@xmax,
               extent(raster(mask))@ymax,
               res(raster(mask))[1],
               res(raster(mask))[2],
               input,
               ouput
))

####################################################################################
####### COMBINE LAYERS
####################################################################################


############################ CREATE THE LOSS LAYER
system(sprintf("gdal_calc.py -A %s -B %s -C %s --co COMPRESS=LZW --outfile=%s --calc=\"%s\"",
               paste0(lc_dir,"lc_2015.tif"),
               lcc_map,
               paste0(ag_dir,"commodities.tif"),
               paste0(lc_dir,"tmp_loss.tif"),
               paste0("((B==4)+(B==5))*(A>=1)*(A<=4)*(C==0)")
))

############################ CREATE THE GAIN LAYER
system(sprintf("gdal_calc.py -A %s -B %s -C %s --co COMPRESS=LZW --outfile=%s --calc=\"%s\"",
               paste0(lc_dir,"lc_2015.tif"),
               lcc_map,
               paste0(ag_dir,"commodities.tif"),
               paste0(lc_dir,"tmp_gain.tif"),
               paste0("((B==8)+(B==9))*((A==14)+(A==16))*(C==0)")
))

############################ CREATE THE FOREST NON FOREST MASK
system(sprintf("gdal_calc.py -A %s --co COMPRESS=LZW --outfile=%s --calc=\"%s\"",
               paste0(lc_dir,"lc_2015.tif"),
               paste0(lc_dir,"tmp_fnf_2015.tif"),
               paste0("(A>=1)*(A<=4)*1+(A>4)*(A<14)*2+(A==14)*3+(A>14)*2")
))

system(sprintf("gdal_calc.py -A %s -B %s -C %s --co COMPRESS=LZW --outfile=%s --calc=\"%s\"",
               paste0(lc_dir,"tmp_fnf_2015.tif"),
               paste0(lc_dir,"tmp_loss.tif"),
               paste0(lc_dir,"tmp_gain.tif"),
               paste0(lc_dir,"tmp_fnf_2018.tif"),
               paste0("(B==0)*(C==0)*A+(B==1)*2+(C==1)*1")
))


#################### CREATE A COLOR TABLE FOR THE OUTPUT MAP
my_classes <- c(0,1,2,3)
my_colors  <- col2rgb(c("black","darkgreen","grey","blue"))

pct <- data.frame(cbind(my_classes,
                        my_colors[1,],
                        my_colors[2,],
                        my_colors[3,]))

write.table(pct,paste0(dd_dir,"color_table.txt"),row.names = F,col.names = F,quote = F)




################################################################################
#################### Add pseudo color table to result
################################################################################
system(sprintf("(echo %s) | oft-addpct.py %s %s",
               paste0(dd_dir,"color_table.txt"),
               paste0(lc_dir,"tmp_fnf_2018.tif"),
               paste0(lc_dir,"tmp_fnf_pct_2018.tif")
))

################################################################################
#################### COMPRESS
################################################################################
system(sprintf("gdal_translate -ot Byte -co COMPRESS=LZW %s %s",
               paste0(lc_dir,"tmp_fnf_pct_2018.tif"),
               paste0(lc_dir,"fnf_2018.tif")
 ))


 
################################################################################
####################  CLEAN
################################################################################
system(sprintf("rm %s",
               paste0(lc_dir,"tmp*.tif")
))

(time_decision_tree <- Sys.time() - time_start)

