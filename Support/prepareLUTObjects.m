function luts = prepareLUTObjects(aeroData, propulsionData)
% Converts raw struct arrays to Simulink.LookupTable objects
% for optimized simulation performance

%% --- ELEVATOR TABLES ---
alpha_e = aeroData.elevatorData.Alpha;          % 1x44
delta_e = double(aeroData.elevatorData.ControlDeflections);  % 1x9

for coeff = {'CL','CD','Cm','CY','Cl','Cn'}
    c = coeff{1};
    lut = Simulink.LookupTable;
    lut.Table.Value        = aeroData.elevatorData.(c);   % 9x44
    lut.Breakpoints(1).Value = delta_e;   % rows
    lut.Breakpoints(2).Value = alpha_e;   % cols
    lut.StructTypeInfo.Name = ['ElevatorLUT_' c];
    luts.elevator.(c) = lut;
end

%% --- RUDDER TABLES ---
beta_r  = double(aeroData.rudderData.Beta);
delta_r = double(aeroData.rudderData.ControlDeflections);

for coeff = {'CL','CD','CY','Cl','Cm','Cn'}
    c = coeff{1};
    lut = Simulink.LookupTable;
    lut.Table.Value          = aeroData.rudderData.(c);   % 9x30
    lut.Breakpoints(1).Value = delta_r;
    lut.Breakpoints(2).Value = beta_r;
    lut.StructTypeInfo.Name  = ['RudderLUT_' c];
    luts.rudder.(c) = lut;
end

%% --- AILERON TABLES ---
alpha_a = aeroData.aileronData.Alpha;
delta_a = double(aeroData.aileronData.ControlDeflections);

for coeff = {'CL','CD','CY','Cl','Cm','Cn'}
    c = coeff{1};
    lut = Simulink.LookupTable;
    lut.Table.Value          = aeroData.aileronData.(c);  % 9x55
    lut.Breakpoints(1).Value = delta_a;
    lut.Breakpoints(2).Value = alpha_a;
    lut.StructTypeInfo.Name  = ['AileronLUT_' c];
    luts.aileron.(c) = lut;
end

%% --- PROPULSION TABLES ---
throttle = double(propulsionData.Throttle);   % 1x21, evenly 0:5:100

for sig = {'Thrust_Newtons','Power_Input','Amperage'}
    s = sig{1};
    lut = Simulink.LookupTable;
    lut.Table.Value          = propulsionData.(s);   % 1x21
    lut.Breakpoints(1).Value = throttle;
    lut.StructTypeInfo.Name  = ['PropLUT_' s];
    luts.propulsion.(s) = lut;
end
end