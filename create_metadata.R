library(RSQLite)
library(dplyr)

stations <- read.csv("data/2015_station_data.csv")
trips <- read.csv("data/2015_trip_data.csv")
elevations <- read.csv("data/elevations.txt", header=F)
names(elevations) <- c("terminal", "elevation")

trips <- merge(trips, elevations, by.x="from_station_id", by.y="terminal") %>%
  rename(start_elevation = elevation)
trips <- merge(trips, elevations, by.x="to_station_id", by.y="terminal") %>%
  rename(end_elevation = elevation)
trips$route <- paste(trips$from_station_id, trips$to_station_id, sep="_")

geodetic.distance <- function(point1, point2)
{
  R <- 6371
  p1rad <- point1 * pi/180
  p2rad <- point2 * pi/180
  d <- sin(p1rad[2])*sin(p2rad[2])+cos(p1rad[2])*cos(p2rad[2])*cos(abs(p1rad[1]-p2rad[1]))
  d <- acos(d)
  if(is.nan(d)){
    d <- 0
  }
  R*d * 0.62
} 

trips.summary <-
  trips %>%
  group_by(route) %>%
  do(data.frame(ntrips = length(.$route),
                mean_time = mean(.$tripduration),
                min_time = min(.$tripduration),
                delta_elevation = mean(.$end_elevation - .$start_elevation))) %>%
  mutate(routefraction = ntrips/nrow(trips))

trips.summary$routerank <- rank(-trips.summary$ntrips, ties.method="max")
trips.summary$start <- sapply(strsplit(trips.summary$route, "_"), "[", 1)
trips.summary$end <- sapply(strsplit(trips.summary$route, "_"), "[", 2)

trips.summary <-
  trips.summary %>%
  merge(stations, by.x="start", by.y="terminal") %>%
  rename(station_start=name) %>%
  select(route, ntrips, mean_time, min_time, routefraction, routerank, delta_elevation,
         station_start, start, end) %>%
  mutate(minutes = floor(mean_time/60),
         seconds = floor(mean_time %% 1 * 60),
         min_minutes = floor(min_time/60),
         min_seconds = floor(min_time %% 1 * 60))

trips.summary <-
  trips.summary %>%
  merge(stations, by.x="end", by.y="terminal") %>%
  rename(station_end=name) %>%
  select(route, ntrips, mean_time, min_time, routefraction, routerank, delta_elevation,
         station_start, station_end, start, end,
         minutes, seconds, min_minutes, min_seconds)  

trips.summary[] <- data.frame(sapply(trips.summary, as.character))
trips.summary$seconds <- as.numeric(trips.summary$seconds)
trips.summary$delta_elevation <- as.numeric(trips.summary$delta_elevation)

stations.latlong <- stations %>% select(terminal, lat, long)

trips.summary <- 
  trips.summary %>% merge(stations.latlong, by.x="start", by.y="terminal") %>%
  rename(start_lat = lat, start_long = long) %>%
  merge(stations.latlong, by.x="end", by.y="terminal") %>%
  rename(end_lat = lat, end_long = long)

distances <- c()
for(x in 1:nrow(trips.summary)){
  point1 <- c(trips.summary[x, ]$start_lat, trips.summary[x, ]$start_long)
  point2 <- c(trips.summary[x, ]$end_lat, trips.summary[x, ]$end_long)
  distances <- c(distances, (geodetic.distance(point1, point2)))
}

trips.summary$distance <- distances
trips.summary$delta_elevation <- trips.summary$delta_elevation * 3.28

conn <- dbConnect(SQLite(), dbname = "pronto.db")
dbSendQuery(conn, "DROP TABLE IF EXISTS Trips");
dbWriteTable(conn, "Trips", trips.summary)
dbDisconnect(conn)