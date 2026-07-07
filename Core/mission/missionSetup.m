%% SAE AERO DESIGN - MISSION SETUP (Using Mission Library)
% =========================================================================
% Mission Configuration - Select from Pre-defined Mission Library
% 
% Instructions:
% 1. Run initialSetup1.m first (loads aircraft parameters)
% 2. Choose mission number below (1-10)
% 3. Run this script to load mission
% 4. Run simulation
%
% Competition Missions (Required):
%   Mission 1: Baseline Flight (1.0x)
%   Mission 2: Warm Day Operations (1.5x)
%   Mission 3: Gusty Conditions (2.0x)
%   Mission 4: High Altitude Challenge (2.5x)
%   Mission 5: Adverse Weather (3.0x)
%
% Advanced Challenge Missions:
%   Mission 6: Precision Landing (1.8x)
%   Mission 7: Maximum Payload (2.2x)
%   Mission 8: Speed Run (1.5x)
%   Mission 9: Endurance Challenge (2.0x)
%   Mission 10: Emergency Procedures (3.5x)
%

% =========================================================================

clc;

%% CHECK AIRCRAFT LOADED
if ~exist('identification', 'var')
    error(['Aircraft parameters not loaded!\n' ...
           'Please run initialSetup1.m first']);
end

fprintf('\n=======================================================\n');
fprintf('MISSION SETUP - %s\n', identification.AircraftName);
fprintf('=======================================================\n\n');

%% SELECT MISSION
% CHANGE THIS NUMBER TO SELECT DIFFERENT MISSION (1-10)
selectedMission = 1;  % ← CHANGE THIS

%% LOAD MISSION FROM LIBRARY
fprintf('Loading mission from library...\n\n');

try
    mission = missionLibrary(selectedMission);
catch ME
    error('Failed to load mission: %s\n%s', ME.message, ...
          'Valid mission numbers: 1-10 (see help missionLibrary)');
end

%% ASSIGN TO WORKSPACE
assignin('base', 'mission', mission);

%% PERFORMANCE ESTIMATES FOR THIS MISSION
fprintf('--- Performance Estimates for This Mission ---\n');

% Get current mass (updated by missionLibrary with mission payload)
mass = evalin('base', 'mass');
geometry = evalin('base', 'geometry');
longitudinal = evalin('base', 'longitudinal');
propulsion = evalin('base', 'propulsion');

% Environmental effects
rho = mission.Environment.AirDensity_kgm3;
rho_SL = 1.225;  % Sea level standard
densityRatio = rho / rho_SL;

fprintf('Density Ratio: %.3f (%.1f%% of sea level)\n', densityRatio, densityRatio*100);

% Adjusted performance
g = 9.81;
V_stall_mps = sqrt((2 * mass.total_kg * g) / (rho * geometry.wingArea_m2 * longitudinal.CLmax));
V_takeoff_mps = 1.2 * V_stall_mps;
V_cruise_mps = 1.3 * V_stall_mps;

fprintf('Stall Speed: %.1f m/s (%.1f mph) - %.0f%% higher than sea level\n', ...
        V_stall_mps, V_stall_mps*2.237, (V_stall_mps/sqrt(densityRatio))/V_stall_mps*100-100);
fprintf('Takeoff Speed: %.1f m/s (%.1f mph)\n', V_takeoff_mps, V_takeoff_mps*2.237);
fprintf('Cruise Speed: %.1f m/s (%.1f mph)\n', V_cruise_mps, V_cruise_mps*2.237);

% Thrust available (scales with density)
thrustAvailable_N = propulsion.maxThrust_N * densityRatio;
weight_N = mass.total_kg * g;
fprintf('Available Thrust: %.1f N (%.0f%% of sea level)\n', ...
        thrustAvailable_N, densityRatio*100);
fprintf('Thrust-to-Weight: %.2f (was %.2f at sea level)\n', ...
        thrustAvailable_N/weight_N, propulsion.maxThrust_N/weight_N);

% Takeoff distance estimate (scales approximately with 1/density)
baseTO_m = 25;  % Estimated base takeoff distance
estimatedTO_m = baseTO_m / densityRatio;
fprintf('Estimated Takeoff Distance: %.1f m (%.0f ft)\n', ...
        estimatedTO_m, estimatedTO_m/0.3048);

if estimatedTO_m > mission.SAE_Limits.MaxTakeoffDistance_m
    fprintf('  ⚠ WARNING: May exceed SAE limit of %.0f m (%.0f ft)\n', ...
            mission.SAE_Limits.MaxTakeoffDistance_m, ...
            mission.SAE_Limits.MaxTakeoffDistance_m/0.3048);
end

% Wind effects
if mission.Environment.WindSpeed_mps > 0
    fprintf('\nWind Effects:\n');
    windAngle_deg = mission.Environment.WindDirection_deg;
    windSpeed_mps = mission.Environment.WindSpeed_mps;
    
    % Headwind/tailwind component
    headwind_mps = windSpeed_mps * cosd(windAngle_deg);
    crosswind_mps = windSpeed_mps * sind(windAngle_deg);
    
    if abs(headwind_mps) > 0.5
        if headwind_mps > 0
            fprintf('  Headwind component: %.1f m/s (reduces groundspeed)\n', headwind_mps);
        else
            fprintf('  Tailwind component: %.1f m/s (increases groundspeed)\n', abs(headwind_mps));
        end
    end
    
    if abs(crosswind_mps) > 0.5
        fprintf('  Crosswind component: %.1f m/s (requires crab angle)\n', abs(crosswind_mps));
        crabAngle_deg = atand(crosswind_mps / V_cruise_mps);
        fprintf('  Required crab angle: %.1f°\n', crabAngle_deg);
    end
    
    if mission.Environment.WindGust_mps > 0
        fprintf('  Gust factor: %.1f m/s (expect turbulence)\n', ...
                mission.Environment.WindGust_mps);
    end
end

fprintf('\n');

%% MISSION DIFFICULTY ASSESSMENT
fprintf('--- Mission Difficulty Assessment ---\n');

difficultyFactors = {};
difficultyScore = 0;

% Density altitude factor
if mission.Environment.DensityAltitude_m > 1500
    difficultyFactors{end+1} = 'High density altitude';
    difficultyScore = difficultyScore + 2;
end

% Wind factor
if mission.Environment.WindSpeed_mps > 5
    difficultyFactors{end+1} = 'Strong winds';
    difficultyScore = difficultyScore + 1;
end

% Gust factor
if mission.Environment.WindGust_mps > 4
    difficultyFactors{end+1} = 'Significant gusts';
    difficultyScore = difficultyScore + 2;
end

% Crosswind factor
if abs(sind(mission.Environment.WindDirection_deg)) > 0.5
    difficultyFactors{end+1} = 'Crosswind landing';
    difficultyScore = difficultyScore + 1;
end

% Turbulence
if strcmp(mission.Environment.Turbulence, 'moderate')
    difficultyFactors{end+1} = 'Moderate turbulence';
    difficultyScore = difficultyScore + 1;
end

% Special conditions
if isfield(mission.Environment, 'WindShear_present') && mission.Environment.WindShear_present
    difficultyFactors{end+1} = 'Wind shear present';
    difficultyScore = difficultyScore + 3;
end

if isfield(mission.Environment, 'MotorFailure') && mission.Environment.MotorFailure
    difficultyFactors{end+1} = 'Simulated motor failure';
    difficultyScore = difficultyScore + 5;
end

fprintf('Difficulty Factors:\n');
if isempty(difficultyFactors)
    fprintf('  None - Nominal conditions\n');
else
    for i = 1:length(difficultyFactors)
        fprintf('  • %s\n', difficultyFactors{i});
    end
end
fprintf('Overall Difficulty: %d/10\n', min(difficultyScore, 10));

fprintf('\n');

%% SAVE MISSION CONFIGURATION
missionFilename = sprintf('mission_%d_%s.mat', ...
                         mission.ID.Number, ...
                         strrep(mission.ID.Name, ' ', '_'));
save(missionFilename, 'mission');
fprintf('✓ Mission saved to: %s\n', missionFilename);

%% READY FOR SIMULATION
fprintf('\n=======================================================\n');
fprintf('MISSION READY: %s\n', mission.ID.Name);
fprintf('=======================================================\n\n');

fprintf('Expected Score: %.2f points\n', mission.Scoring.ExpectedTotalScore);
fprintf('Challenge Level: %s (%.1fx multiplier)\n\n', ...
        mission.ID.ChallengeLevel, mission.Scoring.MissionMultiplier);

fprintf('Next Steps:\n');
fprintf('  1. Review performance estimates above\n');
fprintf('  2. Run validateDesign (optional check)\n');
fprintf('  3. Run runFullSetup (if not already done)\n');
fprintf('  4. Open and run SimulationChallenge.slx\n\n');

fprintf('To select different mission:\n');
fprintf('  1. Edit this file (missionSetup.m)\n');
fprintf('  2. Change selectedMission = %d to desired mission (1-10)\n', selectedMission);
fprintf('  3. Re-run missionSetup\n\n');

% %% MISSION QUICK REFERENCE
% fprintf('=======================================================\n');
% fprintf('MISSION QUICK REFERENCE\n');
% fprintf('=======================================================\n\n');
% 
% fprintf('Core Competition Missions:\n');
% fprintf('  1 - Baseline Flight         (1.0x) Easy\n');
% fprintf('  2 - Warm Day Operations     (1.5x) Moderate\n');
% fprintf('  3 - Gusty Conditions        (2.0x) Moderate-Hard\n');
% fprintf('  4 - High Altitude Challenge (2.5x) Hard\n');
% fprintf('  5 - Adverse Weather         (3.0x) Very Hard\n\n');
% 
% fprintf('Optional Challenge Missions:\n');
% fprintf('  6 - Precision Landing       (1.8x) Moderate\n');
% fprintf('  7 - Maximum Payload         (2.2x) Hard\n');
% fprintf('  8 - Speed Run               (1.5x) Moderate\n');
% fprintf('  9 - Endurance Challenge     (2.0x) Moderate-Hard\n');
% fprintf(' 10 - Emergency Procedures    (3.5x) Extreme\n\n');
