get_records <- function(aoi) {
  # Set AOI to extent of basque country
  aoi %>%
    st_bbox() %>%
    st_as_sfc() %>%
    set_aoi()

  # Connect to Copernicus Open Access Hub
  login_CopHub("be-marc", password = "ISQiwQDl")

  # Get records from Sentinel-2 in time range april to september 2017
  records <- getSentinel_query(c("2017-08-17", "2017-08-18"), platform = "Sentinel-2")

  # Select only L1C products
  records %<>%
    filter(processinglevel == "Level-2Ap") %>%
    arrange(beginposition)
}

download_images <- function(records) {
  # Set working directory for getSpatial package
  set_archive("/home/marc/basque/01_data/image_zip")

  # Connect to Copernicus Open Access Hub
  login_CopHub("be-marc", password = "ISQiwQDl")

  # Download images
  sentinel_dataset = getSentinel_data(records, force = FALSE)
}

unzip_images <- function(sentinel_dataset) {
  # Initialize cluster
  future::plan(future.callr::callr, workers = 16)

  # Unzip images
  sentinel_dataset %>%
    future_map(function(x) unzip(x, exdir = "/home/marc/basque/01_data/image_unzip/", overwrite = FALSE))

  # Return for drake
  list.files("/home/marc/basque/01_data/image_unzip/", full.names = TRUE)
}

stack_bands <- function(records, image_unzip) {
  # Initialize cluster
  # Each thread ~ 25 GB ram
  #makeCluster(1) %>% registerDoParallel()

  # Get record filenames
  records <- records$filename

  future_walk(records, ~ {
    scenes_10 <-
      list.files(paste0("/home/marc/basque/01_data/image_unzip/", .x), recursive = TRUE, pattern = ".*_B08_10m.jp2", full.names = TRUE) %>%
      map(~ raster(.)) %>%
      map(~ raster::aggregate(., fact = 2, fun = mean)) %>%
      stack()

    scenes_20 <-
      list.files(paste0("/home/marc/basque/01_data/image_unzip/", .x ), recursive = TRUE, pattern = ".*_B(02|03|04|05|06|07|8A|11|12)_20m.jp2", full.names = TRUE) %>%
      map(~ raster(.)) %>%
      stack()

    scenes_60 <-
      scenes_10 <-
      list.files(paste0("/home/marc/basque/01_data/image_unzip/", .x), recursive = TRUE, pattern = ".*_B08_10m.jp2", full.names = TRUE) %>%
      map(~ raster(.)) %>%
      map(~ raster::aggregate(., fact = 2, fun = mean)) %>%
      stack()

    scenes_20 <-
      list.files(paste0("/home/marc/basque/01_data/image_unzip/", .x ), recursive = TRUE, pattern = ".*_B(02|03|04|05|06|07|8A|11|12)_20m.jp2", full.names = TRUE) %>%
      map(~ raster(.)) %>%
      stack()

    scenes_60 <-
      list.files(paste0("/home/marc/basque/01_data/image_unzip/", .x), recursive = TRUE, pattern = ".*_B(01|09)_60m.jp2", full.names = TRUE) %>%
      map(~ raster(.)) %>%
      map(~ raster::disaggregate(., fact = 3)) %>%
      stack()

    ras_stack <-
      stack(scenes_60[[1]],
            scenes_20[[1]],
            scenes_20[[2]],
            scenes_20[[3]],
            scenes_20[[4]],
            scenes_20[[5]],
            scenes_20[[6]],
            scenes_10[[1]],
            scenes_20[[7]],
            scenes_60[[2]],
            scenes_20[[8]],
            scenes_20[[9]])

    writeRaster(ras_stack, paste0("/home/marc/basque/01_data/image_stack/", str_remove(.x, ".SAFE"), ".tif"),
                overwrite = TRUE)
  })


  # foreach(record = records) %do% {
  #   library(purrr)
  #   library(stringr)
  #   library(magrittr)
  #   library(raster)
  #
  #   scenes_10 <-
  #     list.files(paste0("/home/marc/basque/01_data/image_unzip/", record), recursive = TRUE, pattern = ".*_B08_10m.jp2", full.names = TRUE) %>%
  #     map(~ raster(.)) %>%
  #     map(~ raster::aggregate(., fact = 2, fun = mean)) %>%
  #     stack()
  #
  #   scenes_20 <-
  #     list.files(paste0("/home/marc/basque/01_data/image_unzip/", record ), recursive = TRUE, pattern = ".*_B(02|03|04|05|06|07|8A|11|12)_20m.jp2", full.names = TRUE) %>%
  #     map(~ raster(.)) %>%
  #     stack()
  #
  #   scenes_60 <-
  #     list.files(paste0("/home/marc/basque/01_data/image_unzip/", record), recursive = TRUE, pattern = ".*_B(01|09)_60m.jp2", full.names = TRUE) %>%
  #     map(~ raster(.)) %>%
  #     map(~ raster::disaggregate(., fact = 3)) %>%
  #     stack()
  #
  #   ras_stack <-
  #     stack(scenes_60[[1]],
  #           scenes_20[[1]],
  #           scenes_20[[2]],
  #           scenes_20[[3]],
  #           scenes_20[[4]],
  #           scenes_20[[5]],
  #           scenes_20[[6]],
  #           scenes_10[[1]],
  #           scenes_20[[7]],
  #           scenes_60[[2]],
  #           scenes_20[[8]],
  #           scenes_20[[9]])
  #
  #   writeRaster(ras_stack, paste0("/home/marc/basque/01_data/image_stack/", str_remove(record, ".SAFE"), ".tif"),
  #               overwrite = TRUE)
  # }

  # Return for drake
  list.files("/home/marc/basque/01_data/image_stack/", pattern = "\\.tif", full.names = TRUE)
}

copy_cloud <- function(records, image_unzip) {
  # Initialize cluster
  future::plan(future.callr::callr, workers = 16)

  # Get cloud mask filenames
  file_cloud_mask <-
    records$filename %>%
    map(~ list.files(paste0("/data/marc/03_hyperspectral/mod/unzip/", ., "/GRANULE"),
                     recursive = TRUE,
                     pattern = "MSK_CLOUDS_B00.gml",
                     full.names= TRUE))

  # Copy and rename
  list(file_cloud_mask, records$filename) %>%
    future_pmap(~ file.copy(.x, paste0("/home/marc/basque/01_data/image_stack/",
                                       str_remove(.y, ".SAFE"),
                                       "_cloud_mask.gml")))

  # Return for drake
  list.files("/home/marc/basque/01_data/image_stack/", pattern = "\\.gml", full.names = TRUE)
}

mosaic_images <- function(records, image_stack) {
  # Get cluster
  future::plan(future.callr::callr, workers = 2)

  # Get stack filenames
  file_stack <-
    unique(records$beginposition) %>%
    map(~ filter(records, beginposition == .)) %>%
    map(~ pull(., filename)) %>%
    map(~ str_remove(., ".SAFE")) %>%
    map_depth(2, ~ str_glue("/home/marc/basque/01_data/image_stack/", ., ".tif"))

  # Set mosaic filename
  file_mosaic <-
    records$filename %>%
    str_sub(1, 41) %>%
    unique() %>%
    map(~ str_glue("/home/marc/basque/01_data/image_mosaic/", ., ".tif"))

  # Build mosaic
  list(file_stack, file_mosaic) %>%
    future_pmap(~ mosaic_rasters(as.character(.x), as.character(.y), verbose = TRUE))

  file_mosaic
}

mosaic_clouds <- function(records, cloud_stack) {
  # Create dummy cloud mask for mosaics without clouds
  vec_dummy_cloud_mask <-
    st_polygon(list(cbind(c(0,1,1,0,0),c(0,0,1,1,0)))) %>%
    st_sfc() %>%
    st_sf(tibble(name = "Dummy")) %>%
    st_set_crs("+proj=utm +zone=30 +datum=WGS84 +units=m +no_defs")

  # Build cloud mask mosaic
  vec_mosaic_cloud_mask <-
    unique(records$beginposition) %>%
    map(~ filter(records, beginposition == .)) %>%
    map(~ pull(., filename)) %>%
    map(~ str_remove(., ".SAFE")) %>%
    map_depth(2, ~ str_glue("/home/marc/basque/01_data/image_stack/", ., "_cloud_mask.gpkg")) %>%
    map_depth(2, possibly(~ st_read(., quiet=TRUE), NA)) %>%
    map(~ purrr::discard(., function(x) all(is.na(x)))) %>%
    map(~ do.call(rbind, .)) %>%
    map_if(~ is.null(.), ~ vec_dummy_cloud_mask) %>%
    map(possibly(~ st_set_crs(., "+proj=utm +zone=30 +datum=WGS84 +units=m +no_defs"), NA))

  # Set cloud mask filename
  file_mosaic_cloud_mask <-
    records$filename %>%
    str_sub(1, 41) %>%
    unique() %>%
    map(~str_glue("/home/marc/basque/01_data/image_mosaic/", ., "_cloud_mask.gpkg"))

  # Write cloud mask mosaic
  list(vec_mosaic_cloud_mask, file_mosaic_cloud_mask) %>%
    pwalk(~ st_write(.x, .y))

  # Return for drake
  file_mosaic_cloud_mask
}