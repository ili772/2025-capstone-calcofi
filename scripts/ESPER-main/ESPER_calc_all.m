% ESPER_calc_all.m

% Use ESPER_LIR, ESPER_NN, and ESPER_Mixed functions to compute TA, DIC, 
% pH, etc. from combined bottle data using all available predictors

% read in combined bottle data
merged_bottle = readtable("../../data/merged_bottle_data.csv");

% select desired output variables
DesiredVars = 1:7;

% extract coordinates from combined bottle data
OutputCoords = merged_bottle{:,["Longitude", "Latitude", "Depth"]};

% select predictors from combined bottle data
PredictorMeasurements = merged_bottle{:,["Salnty","T_degC","PO4uM","NO3uM","SiO3uM","Oxy__mol_Kg"]};

% indicate predictor types
PredictorTypes = 1:6;

% extract dates from combined bottle data
EstDates = decyear(merged_bottle{:,["Year_UTC","Month_UTC","Day_UTC"]});

% compute estimates and uncertainties using ESPER_LIR
[EST_LIR, UNC_LIR] = ESPER_LIR( ...
    DesiredVars, ...
    OutputCoords, ...
    PredictorMeasurements, ...
    PredictorTypes, ...
    'EstDates',EstDates);

% compute estimates and uncertainties using ESPER_NN
[EST_NN, UNC_NN] = ESPER_NN( ...
    DesiredVars, ...
    OutputCoords, ...
    PredictorMeasurements, ...
    PredictorTypes, ...
    'EstDates',EstDates);

% compute estimates and uncertainties using ESPER_Mixed
[EST_MIXED, UNC_MIXED] = ESPER_Mixed( ...
    DesiredVars, ...
    OutputCoords, ...
    PredictorMeasurements, ...
    PredictorTypes, ...
    'EstDates',EstDates);

% convert outputs to table formats
EST_LIR_TAB = splitvars(struct2table(EST_LIR));
UNC_LIR_TAB = splitvars(struct2table(UNC_LIR));
EST_NN_TAB = splitvars(struct2table(EST_NN));
UNC_NN_TAB = splitvars(struct2table(UNC_NN));
EST_MIXED_TAB = splitvars(struct2table(EST_MIXED));
UNC_MIXED_TAB = splitvars(struct2table(UNC_MIXED));

% write output to csv files
writetable(EST_LIR_TAB,"../../data/ESPER_output/ESPER_LIR_est_all.csv")
writetable(UNC_LIR_TAB,"../../data/ESPER_output/ESPER_LIR_unc_all.csv")
writetable(EST_NN_TAB,"../../data/ESPER_output/ESPER_NN_est_all.csv")
writetable(UNC_NN_TAB,"../../data/ESPER_output/ESPER_NN_unc_all.csv")
writetable(EST_MIXED_TAB,"../../data/ESPER_output/ESPER_Mixed_est_all.csv")
writetable(UNC_MIXED_TAB,"../../data/ESPER_output/ESPER_Mixed_unc_all.csv")