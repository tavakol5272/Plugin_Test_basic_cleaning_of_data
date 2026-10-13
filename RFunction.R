library("moveapps")
library("move2")

## The parameter "data" is reserved for the data object passed on from the previous App.
## This App has no user settings.

## count the number of records per track, also returning 0 for tracks without records
count_by_track <- function(ids, tracks) {
  as.integer(table(factor(ids, levels = tracks)))
}

## first time, last time and median time lag (in minutes) per track
time_stats_by_track <- function(times, ids, tracks) {
  t_num <- as.numeric(times)
  stats <- lapply(tracks, function(tr) {
    t <- sort(t_num[ids == tr])
    data.frame(
      first = if (length(t) > 0) min(t) else NA,
      last = if (length(t) > 0) max(t) else NA,
      lag = if (length(t) > 1) median(diff(t)) / 60 else NA
    )
  })
  do.call(rbind, stats)
}

## all time lags (in minutes) within tracks, used for the summary over all tracks
all_time_lags <- function(times, ids, tracks) {
  t_num <- as.numeric(times)
  unlist(lapply(tracks, function(tr) diff(sort(t_num[ids == tr])))) / 60
}

format_time <- function(x) {
  format(as.POSIXct(x, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M:%S")
}

rFunction = function(data, ...) {
  
  start_time <- Sys.time()
  n_start <- nrow(data)
  logger.info(paste0("Input data: ", n_start, " locations in ", mt_n_tracks(data), " track(s)."))
  
  ## order by tracks
  if (!mt_is_track_id_cleaved(data)) {
    logger.info("Data were not grouped by track. Reordering by track.")
    data <- data |> dplyr::arrange(mt_track_id(data))
  }
  ## order time within tracks
  if (!mt_is_time_ordered(data)) {
    logger.info("Data were not time ordered within tracks. Reordering by time within each track.")
    data <- data |> dplyr::arrange(mt_track_id(data), mt_time(data))
  }
  
  tracks <- unique(as.character(mt_track_id(data)))
  n_input <- count_by_track(as.character(mt_track_id(data)), tracks)
  n_empty <- n_na_crds <- n_zero <- n_dupl <- rep(0L, length(tracks))
  
  ## remove empty locations
  if (!mt_has_no_empty_points(data)) {
    empty <- sf::st_is_empty(data)
    n_empty <- count_by_track(as.character(mt_track_id(data))[empty], tracks)
    data <- data[!empty, ]
  }
  logger.info(paste0("Removed ", sum(n_empty), " empty location(s)."))
  
  ## sometimes only lat or long are NA
  crds <- sf::st_coordinates(data)
  na_crds <- is.na(crds[, 1]) | is.na(crds[, 2])
  if (any(na_crds)) {
    n_na_crds <- count_by_track(as.character(mt_track_id(data))[na_crds], tracks)
    data <- data[!na_crds, ]
  }
  logger.info(paste0("Removed ", sum(n_na_crds), " location(s) with missing X or Y coordinate."))
  
  ## remove 0,0 coordinates
  ## coordinates are recalculated, because rows may have been removed in the step above
  crds <- sf::st_coordinates(data)
  zero_crds <- crds[, 1] == 0 & crds[, 2] == 0
  if (any(zero_crds)) {
    n_zero <- count_by_track(as.character(mt_track_id(data))[zero_crds], tracks)
    data <- data[!zero_crds, ]
  }
  logger.info(paste0("Removed ", sum(n_zero), " location(s) with coordinates (0, 0)."))
  
  ## retain the duplicate entry which contains the least number of columns with NA values
  if (!mt_has_unique_location_time_records(data)) {
    n_before_dupl <- count_by_track(as.character(mt_track_id(data)), tracks)
    data <- data |>
      dplyr::mutate(n_na = rowSums(is.na(dplyr::pick(dplyr::everything())))) |>
      dplyr::arrange(n_na) |>
      mt_filter_unique(criterion = "first") |> # this always needs to be "first" because the duplicates get ordered according to the number of columns with NA.
      dplyr::select(-n_na) |> # helper column, must not end up in the output
      dplyr::arrange(mt_track_id(), mt_time())
    n_dupl <- n_before_dupl - count_by_track(as.character(mt_track_id(data)), tracks)
  }
  logger.info(paste0("Removed ", sum(n_dupl), " duplicated track/time record(s), keeping the record with the fewest missing values."))
  
  ## summary of the cleaning, per track and over all tracks
  ids_out <- as.character(mt_track_id(data))
  times_out <- mt_time(data)
  n_output <- count_by_track(ids_out, tracks)
  t_stats <- time_stats_by_track(times_out, ids_out, tracks)
  
  summary_tracks <- data.frame(
    track_id = tracks,
    n_input = n_input,
    n_empty = n_empty,
    n_na_coords = n_na_crds,
    n_zero = n_zero,
    n_duplicates = n_dupl,
    n_removed = n_input - n_output,
    n_output = n_output,
    pct_removed = round(100 * (n_input - n_output) / n_input, 2),
    first_time = format_time(t_stats$first),
    last_time = format_time(t_stats$last),
    median_time_lag_min = round(t_stats$lag, 2)
  )
  
  all_lags <- all_time_lags(times_out, ids_out, tracks)
  summary_all <- data.frame(
    track_id = "ALL",
    n_input = sum(n_input),
    n_empty = sum(n_empty),
    n_na_coords = sum(n_na_crds),
    n_zero = sum(n_zero),
    n_duplicates = sum(n_dupl),
    n_removed = sum(n_input) - sum(n_output),
    n_output = sum(n_output),
    pct_removed = round(100 * (sum(n_input) - sum(n_output)) / sum(n_input), 2),
    first_time = if (nrow(data) > 0) format_time(min(as.numeric(times_out))) else NA,
    last_time = if (nrow(data) > 0) format_time(max(as.numeric(times_out))) else NA,
    median_time_lag_min = if (length(all_lags) > 0) round(median(all_lags), 2) else NA
  )
  
  summary_table <- rbind(summary_tracks, summary_all)
  
  summary_file <- appArtifactPath("cleaning_summary.csv")
  write.csv(summary_table, file = summary_file, row.names = FALSE)
  logger.info(paste("Cleaning summary saved as artifact:", summary_file))
  
  ## write the summary also to the log
  logger.info("Cleaning summary (track: input / empty / NA coords / (0,0) / duplicates / removed / output / % removed / first time / last time / median time lag [min]):")
  for (i in seq_len(nrow(summary_table))) {
    s <- summary_table[i, ]
    logger.info(paste0(s$track_id, ": ", s$n_input, " / ", s$n_empty, " / ", s$n_na_coords, " / ",
                       s$n_zero, " / ", s$n_duplicates, " / ", s$n_removed, " / ", s$n_output, " / ",
                       s$pct_removed, "% / ", s$first_time, " / ", s$last_time, " / ", s$median_time_lag_min))
  }
  
  if (nrow(data) == 0) {
    logger.warn("No locations are left after cleaning. Returning NULL.")
    result <- NULL
  } else {
    result <- data
    ## save the cleaned data as an artifact that can be downloaded by the Workflow user
    artifact <- appArtifactPath("cleaned_data.rds")
    saveRDS(result, file = artifact)
    logger.info(paste("Cleaned data saved as artifact:", artifact))
  }
  
  end_time <- Sys.time()
  logger.info(paste("Cleaning took", format(round(difftime(end_time, start_time), 2))))
  
  ## provide the result to the next App in the MoveApps Workflow
  return(result)
}
