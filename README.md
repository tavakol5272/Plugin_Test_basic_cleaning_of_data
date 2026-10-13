# Remove Invalid and Duplicate Locations

MoveApps

Github repository: 

## Description
Cleans location data by removing empty locations, locations with a missing longitude/X or latitude/Y coordinate, locations at exactly (0, 0), and duplicated track/timestamp records (keeping the record with the fewest missing values). Provides the cleaned data and a per-track summary of how many locations were removed.

## Documentation
This App performs a basic cleaning of movement (location) data, so that later Apps in the Workflow receive data without invalid or duplicated locations. The following steps are applied, in this order, to the whole data set:

1. **Ordering:** if the data are not grouped by track, they are reordered by track. If the locations are not ordered by time within each track, they are reordered by time within each track.
2. **Empty locations:** locations without geometry (empty points) are removed.
3. **Missing coordinates:** locations where only one of the two coordinates (X/longitude or Y/latitude) is missing (`NA`) are removed.
4. **(0, 0) coordinates:** locations where both coordinates are exactly `0` are removed. Such locations are a common error of tracking devices.
5. **Duplicated records:** if a track contains more than one location with the same timestamp, only one of them is kept: the record with the fewest missing values (`NA`) across all columns. If several records have the same number of missing values, the first one is kept. The data are then ordered again by track and time.

For each step, the number of removed locations is written to the log. At the end, a summary table with the number of removed locations per step and per track, together with some basic statistics of the cleaned data, is written to the log and saved as a csv-file (see Artefacts). The cleaned data are passed on to the next App and are also saved as an `.rds` file. The run time of the cleaning is written to the log.

Note that the **Movebank Location** App already removes empty locations, locations with missing coordinates and duplicated records when downloading data. This App is useful for data from other sources (e.g. uploaded files) and additionally removes locations at (0, 0).

### Application scope
#### Generality of App usability
This App was developed for any taxonomic group.

#### Required data properties
The App should work for any kind of location data.

The removal of (0, 0) coordinates is meant for data in geographic coordinates (longitude/latitude). If the data have been projected to another coordinate reference system (e.g. in metres), the point (0, 0) can be a valid location and would still be removed.

### Input type
`move2::move2_loc`

### Output type
`move2::move2_loc`

### Artefacts
`cleaned_data.rds`: the cleaned data as a `move2` object, identical to the output passed on to the next App. Only created if locations remain after cleaning.

`cleaning_summary.csv`: csv-file with a table of the cleaning results, with one row per track and a final row `ALL` with the results over the whole data set. Columns:
- `track_id`: name of the track (`ALL` for the whole data set)
- `n_input`: number of locations before cleaning
- `n_empty`: number of empty locations removed
- `n_na_coords`: number of locations removed because the X or Y coordinate was missing
- `n_zero`: number of locations at (0, 0) removed
- `n_duplicates`: number of duplicated track/timestamp records removed
- `n_removed`: total number of locations removed
- `n_output`: number of locations after cleaning
- `pct_removed`: percentage of locations removed
- `first_time`: first timestamp after cleaning (UTC)
- `last_time`: last timestamp after cleaning (UTC)
- `median_time_lag_min`: median time between consecutive locations after cleaning. Unit: `minutes`. For the row `ALL`, the median of all time lags within tracks.

### Settings
This App has no settings.

### Changes in output data
The App removes locations from the input data: empty locations, locations with a missing coordinate, locations at (0, 0) and duplicated track/timestamp records. The data are ordered by track and by time within track. No columns are added or removed.

### Errors and null handling
**Input data:** If no locations remain after cleaning (e.g. all locations are at (0, 0)), the App writes a warning to the log and returns `NULL`. The summary table `cleaning_summary.csv` is still created, while `cleaned_data.rds` is not.

**Tracks without remaining locations:** If all locations of a track are removed, the track is still listed in `cleaning_summary.csv` with `n_output = 0` and empty values for `first_time`, `last_time` and `median_time_lag_min`. The same applies to `median_time_lag_min` for tracks with only one remaining location.

### Technical details
- The cleaning is based on the R packages `move2`, `sf` and `dplyr`. Duplicates are removed with `move2::mt_filter_unique(criterion = "first")` after ordering all records by their number of missing values.
- The data are processed on the whole data set at once. The summary statistics are calculated per track.
- The (0, 0) check uses the coordinates in the coordinate reference system of the input data. The data are not reprojected.
- Timestamps in the summary table are given in UTC.
