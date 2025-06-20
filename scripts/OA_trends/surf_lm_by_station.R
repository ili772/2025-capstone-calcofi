# surf_lm_by_station.R

library(tidyverse)
library(gt)
library(sf)
library(rnaturalearth)
library(scales)
library(latex2exp)
library(FDRestimation)
library(stringr)
library(ggrepel)

# READ AND PROCESS DATA ---------------------------------------------------

# Load seasonal detrending function
source("scripts/OA_trends/detrend_data.R")

# Load merged bottle data and CO2SYS output
merged_bottle_data <- read_csv("data/merged_bottle_data.csv")
co2sys_out <- read_csv("data/CO2SYS_out.csv")

# Combine merged bottle data and CO2SYS output and filter out anomalies
bottle_co2sys <- bind_cols(merged_bottle_data, co2sys_out) %>%
  filter(
    Salnty > 30,
    Depth < 1000
  )

# Create vector of variables to be detrended
qty <- c("T_degC","Salnty","TA","DIC","pCO2in","RFin","pHin","CO3in","OmegaCAin","OmegaARin")

# Detrend variables of interest
bottle_co2sys <- sea_dtd_data(qty, bottle_co2sys, "Date.cc")

# Get the names of all CalCOFI stations in the data and their locations
stations <- bottle_co2sys %>%
  group_by(
    Station_ID
  ) %>%
  summarize(
    lat = mean(Latitude),
    lon = mean(Longitude),
    observations = n()
  )

# FIT LINEAR MODELS -------------------------------------------------------

# create fits and results objects for surface (<20m)
surf_fits <- NULL
surf_results <- NULL

# iterate through stations and fit linear models for each quantity
for (i in 1:nrow(stations)) {
  # extract data for station i
  data <- bottle_co2sys %>% filter((Station_ID == stations$Station_ID[i]) & (Depth <= 20))
  for (j in 1:length(qty)) {
    # check if all values are NA
    if (data %>% select(paste0(qty[j],"_dtd")) %>% is.na() %>% `!`() %>% sum() == 0) {
      # if so, add NA to list of fits
      surf_fits[[(i-1)*length(qty)+j]] <- NA
      # and add row of NA values to surf_results for the corresponding quantity and station
      surf_results <- bind_rows(surf_results, c(
        station = stations$Station_ID[i],
        lat = stations$lat[i],
        lon = stations$lon[i],
        qty = qty[j], 
        c(Estimate = NA, `Std. Error` = NA, `t value` = NA, `Pr(>|t|)` = NA), 
        n = NA, 
        r2 = NA))
    }
    else { # fit the linear model
      fit <- lm(as.formula(paste(paste0(qty[j],"_dtd"),"~","Date_Dec")), data = data, na.action = na.exclude)
      # add fit to list of fits
      surf_fits[[(i-1)*length(qty)+j]] <- fit
      # add coefficient estimate and regression statistics in a new row to surf_results
      surf_results <- bind_rows(surf_results, c(
        station = stations$Station_ID[i],
        lat = stations$lat[i],
        lon = stations$lon[i], 
        qty = qty[j], 
        if(nrow(coef(summary(fit))) == 1) c(Estimate = NA, `Std. Error` = NA, `t value` = NA, `Pr(>|t|)` = NA) else coef(summary(fit))[2,], 
        n = summary(fit)$df[2] + 2, 
        r2 = summary(fit)$r.squared))
    }
  }
}

# PLOT FIT RESULTS ----------------------------------------------------


surf_results <- surf_results %>%
  # convert numeric columns to numeric vectors
  mutate(
    across(-c(station, qty), as.numeric)
  ) |> 
  filter(!is.na(`Pr(>|t|)`))

surf_results <- surf_results |> 
  mutate(adj_p_value = (p.fdr(pvalues = surf_results$`Pr(>|t|)`))$fdrs) |> 
  mutate(sigp = factor(ifelse(adj_p_value < 0.05, 1, 0), levels = c(1,0), labels = c("Yes", "No")),
         sigp_ind = ifelse(adj_p_value < 0.05, 1, 0),
         sig_label = ifelse(adj_p_value < 0.05, paste("(",station,",",signif(Estimate, digits = 4), ")"), "")) |> 
  filter(n >= 10)


sign_stations <- surf_results |> group_by(station) |> 
  summarize(min_n = min(n),
            max_n = max(n),
            mean_n = mean(n),
            lat = mean(lat),
            lon = mean(lon),
            num_sig = sum(sigp_ind),
            prop_sig = mean(sigp_ind)) |> 
  ungroup()

# import map for plotting
world <- ne_countries(scale = "medium", returnclass = "sf")

# create vector of (full) names for each quantity
qty_names <- c("Temperature", "Salinity", "TA", "DIC", "pCO2", "Revelle Factor", "pH", "CO3$^{2-}$", "$\\Omega_{calcite}$", "$\\Omega_{aragonite}$")

# create vector of units for each quantity
units <- c("$^\\circ$C yr$^{-1}$", "yr$^{-1}$", "µmol kg$^{-1}$ yr$^{-1}$", 
           "µmol kg$^{-1}$ yr$^{-1}$", "µatm yr$^{-1}$","yr$^{-1}$", 
           "yr$^{-1}$", "µmol kg$^{-1}$ yr$^{-1}$", "yr$^{-1}$", "yr$^{-1}$")

# generate plots for surface fits
for (i in 1:10) {
  # extract data for quantity i
  data <- surf_results %>%
    filter(
      qty == qty[i]
    ) %>%
    # filter out stations with n<=15 observations used in the fit
    filter(
      (!is.na(Estimate)) & (n > 15)
    )
  
  # create plot of slope by station
  ggplot(
    data = world
  ) +
    geom_sf(fill = "antiquewhite1") +
    geom_point(
      data = data,
      aes(
        x = lon,
        y = lat,
        fill = Estimate, # estimated slope
        size = n, # number of observations
        shape = sigp # if estimate is statistically significant
      ),
      color = "black",
      show.legend=TRUE # force shape to always show in legend
    ) + 
    geom_text_repel(data = data, aes(x = lon, y = lat, label=sig_label), max.overlaps = 30, box.padding = 1) +
    # manually adjust coordinates
    coord_sf(
      xlim = c(surf_results$lon %>% min() - 2, surf_results$lon %>% max() + 2),
      ylim = c(surf_results$lat %>% min(), surf_results$lat %>% max())
    ) +
    # create color scale for slope estimates
    scale_fill_gradient2(
      low = "#d7191c",
      high = "#2c7bb6",
      mid = "#ffffbf"
    ) +
    # create custom shape scale
    scale_shape_manual(
      values = c("Yes" = 24, "No" = 21),
      drop = FALSE # force both shapes to always show in legend
    ) +
    theme(
      panel.grid.major = element_line(
        color = gray(0.5), 
        linetype = "solid", 
        linewidth = 0.5
      ), 
      panel.background = element_rect(fill = "aliceblue")
    ) +
    # fix the order of the legends
    guides(
      fill = guide_colorbar(order = 1),
      size = guide_legend(order = 50),
      shape = guide_legend(order = 98)
    ) +
    labs(
      x = NULL,
      y = NULL,
      title = TeX(paste("Estimated Slope for", qty_names[i], "by Station at Surface (Depth<=20m, N>15)", paste0("[",units[i],"]"))),
      color = "Estimate",
      size = "N",
      shape = "adjusted p<0.05",
      # caption = TeX(paste("Mean Slope (weighted by $N$):", format(round(weighted.mean(data$Estimate, data$n), 4), nsmall = 4), units[i]))
    )
  
  # save plots
  ggsave(paste0("images/OA_trends/surf_", qty[i], "_by_station.png"), bg = "white", units = "in", width = 8, height = 8)
}

ggplot(
  data = world
) +
  geom_sf(fill = "antiquewhite1") +
  geom_point(
    data = sign_stations,
    aes(
      x = lon,
      y = lat,
      fill = mean_n, # mean number of observations used for models
      size = prop_sig, # number of significany predictors
    ),
    color = "black",
    pch = 21,
    show.legend=TRUE # force shape to always show in legend
  ) +
#  geom_text(data = sign_stations, nudge_y = -.07 , size = 2, aes(x = lon, y = lat, label = station)) + 
  # manually adjust coordinates
  coord_sf(
    xlim = c(sign_stations$lon %>% min() - 2, sign_stations$lon %>% max() + 2),
    ylim = c(sign_stations$lat %>% min(), sign_stations$lat %>% max())
  ) +
  # create color scale for slope estimates
  scale_fill_gradient2(
    low = "#d7191c",
    high = "#2c7bb6",
    mid = "#ffffbf"
  ) +
  # create custom shape scale
  scale_shape_manual(
    values = c("Yes" = 24, "No" = 21),
    drop = FALSE # force both shapes to always show in legend
  ) +
  theme(
    panel.grid.major = element_line(
      color = gray(0.5), 
      linetype = "solid", 
      linewidth = 0.5
    ), 
    panel.background = element_rect(fill = "aliceblue")
  ) +
  # fix the order of the legends
  guides(
    fill = guide_colorbar(order = 1),
    size = guide_legend(order = 50),
    shape = guide_legend(order = 98)
  ) +
  labs(
    x = NULL,
    y = NULL,
    title = "Number of Time Significant Variables by Station at Surface (Depth<=20m)",
    fill = "Mean Observations per Model",
    size = str_wrap("Proportion of Variables of Interest with Significant Temporal Trend", 40)
  )

st_test <- stations
st_test$st <- 0
st_test$line <- 0
for (i in 1:nrow(st_test)){
  st_test$st[i] <- str_split(st_test$Station_ID[i], " ")[[1]][1]
  st_test$line[i] <- str_split(st_test$Station_ID[i], " ")[[1]][2]
}
st_test <- st_test |> 
mutate(coastal = case_when(
  (as.numeric(st) <= 86) & (as.numeric(line) < 70) ~ TRUE,
  (as.numeric(st) < 90) & (as.numeric(line) < 40) ~ TRUE,
  (as.numeric(st)) >= 90 & (as.numeric(line) < 35) ~ TRUE,
  TRUE ~ FALSE
))

ggplot(
  data = world
) +
  geom_sf(fill = "antiquewhite1") +
  geom_point(
    data = st_test,
    aes(
      x = lon,
      y = lat,
      color = coastal,
      size = observations
    ),
    show.legend=TRUE # force shape to always show in legend
  ) +
  # manually adjust coordinates
  coord_sf(
    xlim = c(st_test$lon %>% min() - 2, st_test$lon %>% max() + 2),
    ylim = c(st_test$lat %>% min(), st_test$lat %>% max())
  ) +
  # create custom shape scale
  scale_shape_manual(
    values = c("Yes" = 24, "No" = 21),
    drop = FALSE # force both shapes to always show in legend
  ) +
  scale_color_manual(labels = c("No", "Yes"), values = c("#F8766D", "#619CFF")) + 
  theme(
    panel.grid.major = element_line(
      color = gray(0.5), 
      linetype = "solid", 
      linewidth = 0.5
    ), 
    panel.background = element_rect(fill = "aliceblue")
  ) +
  # fix the order of the legends
  guides(
    fill = guide_colorbar(order = 1),
    size = guide_legend(order = 50),
    shape = guide_legend(order = 98)
  ) + 
  labs(
    title = "Map of Sampling Stations",
    x = "Longitude",
    y = "Latidude",
    size = "Observations",
    col = "Coastal"
  ) + 
  theme(
    plot.title = element_text(size = 28, hjust = 0.5),      # Title
    legend.title = element_text(size = 20),                 # Legend title
    legend.text = element_text(size = 18),                                  # Legend labels
    axis.title = element_text(size = 20)
  )

ggsave("images/OA_trends/coastal_stations.png", bg = "white", units = "in", width = 8, height = 8)



surf_results$st <- 0
surf_results$line <- 0
for (i in 1:nrow(surf_results)){
  surf_results$st[i] <- str_split(surf_results$station[i], " ")[[1]][1]
  surf_results$line[i] <- str_split(surf_results$station[i], " ")[[1]][2]
}
surf_results <- surf_results |> 
  mutate(coastal = case_when(
    (as.numeric(st) <= 86) & (as.numeric(line) < 70) ~ TRUE,
    (as.numeric(st) < 90) & (as.numeric(line) < 40) ~ TRUE,
    (as.numeric(st)) >= 90 & (as.numeric(line) < 35) ~ TRUE,
    TRUE ~ FALSE
  ))

surf_results |> group_by(coastal, qty) |> 
  summarize(time_effect = sum(Estimate*n)/sum(n))
surf_results |> group_by(coastal, qty) |> 
  summarize(n = sum(n)) |> 
  group_by(coastal) |> 
  summarize(n = mean(n))
