library("moveapps")
library("move2")
library("sf")

## The parameter "data" is reserved for the data object passed on from the previous App.

## Helper: find the locations that lie at longitude 0 and latitude 0.
## The check is always done in WGS84 (EPSG:4326), because (0,0) is only a
## "bad point" in normal longitude/latitude. The data itself is NOT changed here.
## Returns one TRUE/FALSE value per row of 'data' (TRUE = (0,0) location).
zero_coord_rows <- function(data, tolerance = 1e-6) {
  geom <- sf::st_geometry(data)

  if (is.na(sf::st_crs(geom))) {
    logger.warn("The data have no coordinate reference system (CRS). The App checks the raw coordinates for (0,0).")
  } else if (!isTRUE(sf::st_is_longlat(geom))) {
    logger.info("The data are projected. The App checks for (0,0) in WGS84 (EPSG:4326) and returns the data in the original projection.")
    geom <- sf::st_transform(geom, 4326)
  }

  crds <- sf::st_coordinates(geom)

  # Safety check: we need exactly one coordinate pair per location,
  # otherwise the row numbers would not match and wrong rows could be removed.
  if (nrow(crds) != length(geom)) {
    stop("Could not read exactly one coordinate pair per location. Please check that the data contain only point locations.", call. = FALSE)
  }

  x <- crds[, "X"]
  y <- crds[, "Y"]

  # NA coordinates and empty points are not (0,0), so they stay in the data.
  # A small tolerance catches values like 1e-15 that appear after re-projection.
  !is.na(x) & !is.na(y) & abs(x) < tolerance & abs(y) < tolerance
}

rFunction = function(data, ...) {

  is_zero <- zero_coord_rows(data)
  n_zero <- sum(is_zero)

  if (n_zero == 0) {
    logger.info("No locations with (0,0) coordinates were found. The data are returned unchanged.")
    return(data)
  }

  logger.info(paste0("Removed ", n_zero, " of ", nrow(data), " locations with (0,0) coordinates."))

  # Log how many locations were removed in each track
  removed_per_track <- table(as.character(move2::mt_track_id(data))[is_zero])
  for (trk in names(removed_per_track)) {
    logger.info(paste0("  Track '", trk, "': ", removed_per_track[[trk]], " location(s) removed."))
  }

  # Subsetting rows keeps the move2 class, CRS, time column and track data.
  # The row order is not changed, so tracks stay grouped and time-ordered.
  result <- data[!is_zero, ]

  if (nrow(result) == 0) {
    logger.warn("All locations had (0,0) coordinates. No data are left, so the App returns NULL.")
    return(NULL)
  }

  return(result)
}
