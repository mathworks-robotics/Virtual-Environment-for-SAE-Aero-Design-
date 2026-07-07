% =========================================================================
% environmentLibrary.m
%
% CORE FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% Defines all environment presets for the SAE Aero Design Simulation
% Challenge. Each preset populates the workspace struct 'env' which feeds
% the three Aerospace Blockset wind model blocks inside the Environment
% subsystem of SimulationChallenge.slx.
%
% HOW THIS FILE IS CALLED:
%   Called automatically from the Environment subsystem mask callback:
%       env = environmentLibrary(envPreset);
%   where envPreset is the integer selected on the subsystem mask popup.
%   Configure the mask popup string as:
%       'Sea Level Standard|
%        Competition Day — West (Van Nuys CA)|
%        Competition Day — East (Lakeland FL)|
%        Competition Day — East (Fort Worth TX)|
%        Cold Windy Day (Toronto Canada)|
%        Hot Day (Chennai India)|
%        Afternoon Gusts (Lakeland FL)|
%        High Density Altitude (Denver-type)'
%   with values 1|2|3|4|5|6|7|8
%
% =========================================================================
%
% SIMULINK BLOCK PARAMETER MAPPING:
% -------------------------------------------------------------------------
%
%   WGS84 Gravity Model (Taylor Series)
%     Reads env.Latitude_deg and env.Longitude_deg from base workspace.
%     These are flat top-level fields on env — set by environmentLibrary
%     and written to base workspace via assignin in the mask callback.
%     Initialization.m pulls initial.Latitude/Longitude from these fields.
%     GPS fence logic in missionSetup.m also reads env.Latitude_deg /
%     env.Longitude_deg as the course origin reference.
%
%   COESA Atmosphere Model
%     Input:  h (m) — Altitude_MSL from ACStates bus (computed at runtime)
%     Output: T (K), a (m/s), P (Pa), rho (kg/m³)
%     Only rho connected downstream — T, a, P outputs are terminated.
%     env.Atmosphere values are for display/logging only, NOT block inputs.
%
%   Wind Shear Model (Aerospace Blockset)
%     Inputs:  h (m),  DCM_be [3x3]
%     Mask parameters:
%       env.WindShear.Speed_6m_mps     [m/s]  Wind speed at 6 m ref height
%       env.WindShear.Direction_deg    [deg]  Wind direction (FROM, met convention)
%       env.WindShear.Exponent         [-]    Power-law shear exponent
%                                             0.143 = 1/7 law, open flat terrain
%                                             0.160 = suburban/rough terrain
%
%   Dryden Wind Turbulence — Continuous (+q −r) (Aerospace Blockset)
%     Inputs:  h (m),  V (m/s) airspeed,  DCM_be [3x3]
%     Outputs: ug,vg,wg → wind sum bus  |  pg,qg,rg → angular wind bus
%     Mask parameters:
%       env.Turbulence.Speed_6m_mps    [m/s]  Mean wind speed at 6 m
%       env.Turbulence.Direction_deg   [deg]  Wind direction at 6m, clockwise from north
%       env.Turbulence.Sigma_mps       [m/s]  RMS turbulence intensity
%                                             0 = OFF, 1.06 = Light,
%                                             2.12 = Moderate, 4.24 = Severe
%                                             (MIL-HDBK-1797)
%       env.Turbulence.Scale_Lu_m      [m]    Scale length at medium/high altitudes
%                                             SAE cruise 30 m AGL: 205 m
%                                             Block uses one scale length (Lu);
%                                             Lv and Lw are derived internally.
%       env.Turbulence.TurbulenceOn    [bool] Maps to block "Turbulence on" checkbox
%                                             All presets store sigma/scale values
%                                             regardless — flip to true to enable.
%       env.Turbulence.NoiseSeeds      [1x4]  Fixed [23341 23342 23343 23344]
%
%   Discrete Wind Gust Model (Aerospace Blockset)
%     Input:   V (m/s) airspeed
%     Output:  V_wind → wind sum bus
%     Mask parameters:
%       env.Gust.EnableU               [bool] "Gust in u-axis" checkbox
%       env.Gust.EnableV               [bool] "Gust in v-axis" checkbox
%       env.Gust.EnableW               [bool] "Gust in w-axis" checkbox
%                                             Auto-derived: true when corresponding
%                                             amplitude component is nonzero.
%       env.Gust.StartTime_s           [s]    Gust start time; Inf = never fires
%       env.Gust.Length_m              [1x3]  [dx dy dz] gust wavelength per axis [m]
%                                             1-cosine shape. Set to 1 on disabled axes.
%       env.Gust.Amplitude_mps         [1x3]  [ug vg wg] peak gust components [m/s]
%                                             ug = headwind (+ve into nose)
%                                             vg = lateral  (+ve from left)
%                                             wg = vertical (+ve downward)
%
% =========================================================================
%
% SCORE MULTIPLIER:
%   FinalScore = BaseScore × env.Multiplier
%   Assigned directly per preset. Competition presets have equal multipliers
%   (1.0×) — they differ in conditions, not in scoring advantage.
%   Challenge presets scale from 1.5× to 2.5× based on severity.
%
% AVAILABLE PRESETS:
%   ── Baseline ──
%   1  Sea Level Standard           ISA SL, no wind                  1.0×
%
%   ── Competition Sites (all three venues — locations rotate yearly) ──
%   2  Competition Day — West       Apollo XI, Van Nuys CA, April    1.1×
%   3  Competition Day — East FL    KLAL Lakeland FL, March          1.2×
%   4  Competition Day — East TX    Thunderbird, Fort Worth TX, May  1.3×
%
%   Competition multiplier rationale:
%     Van Nuys (1.1×):    239m, ISA+6°C  — mild density loss, light valley wind
%     Lakeland (1.2×):    43m,  ISA+7°C  — low density loss but 5.9 m/s SE crosswind
%     Fort Worth (1.3×):  262m, ISA+12°C — hardest comp site, 6.4% density deficit
%                          stall speed +3.4%, takeoff roll +6.8% vs ISA sea level
%     Note: Lakeland > Van Nuys despite better density because the SE crosswind
%           is the dominant challenge (density penalty is the primary criterion
%           for Van Nuys which has a negligible wind).
%
%   ── Challenge Environments ──
%   5  Hot Day                      Chennai VOMM, March               1.5×  
%   6  Cold Windy Day               Toronto Pearson CYYZ, March       1.6×
%   7  Afternoon Gusts              Lakeland FL afternoon             2.0×
%   8  High Density Altitude        Denver-type 1600m, ISA+10         2.5×
%
% =========================================================================

function env = environmentLibrary(presetNumber)

    if nargin < 1
        error('environmentLibrary:noInput', ...
            'Provide a preset number 1–8. See Environment subsystem mask.');
    end
    if ~isnumeric(presetNumber) || presetNumber ~= round(presetNumber) || ...
       presetNumber < 1 || presetNumber > 8
        error('environmentLibrary:badInput', ...
            ['presetNumber must be integer 1–8:\n' ...
             '  1  Sea Level Standard\n' ...
             '  2  Competition West — Van Nuys CA (April)\n' ...
             '  3  Competition East — Lakeland FL (March)\n' ...
             '  4  Competition East — Fort Worth TX (May)\n' ...
             '  5  Hot Day          — Chennai India\n' ...
             '  6  Cold Windy Day   — Toronto Canada\n' ...
             '  7  Afternoon Gusts  — Lakeland FL\n' ...
             '  8  High Density Altitude']);
    end

    switch presetNumber
        case 1,  env = preset1_SeaLevelStandard();
        case 2,  env = preset2_CompetitionWest_VanNuys();
        case 3,  env = preset3_CompetitionEast_Lakeland();
        case 4,  env = preset4_CompetitionEast_FortWorth();
        case 5,  env = preset5_HotDay();
        case 6,  env = preset6_ColdWindyDay();
        case 7,  env = preset7_AfternoonGusts();
        case 8,  env = preset8_HighDensityAltitude();
    end

    % ── Flat top-level venue fields ───────────────────────────────────────
    % Promoted from env.Location for direct use in:
    %   Simulink mask expressions  — e.g. WGS84 Gravity block params
    %   Initialization.m           — initial.Latitude / Longitude / Altitude_MSL
    %   missionSetup.m             — GPS fence origin reference
    %   Any subsystem needing venue position without navigating nested path
    env.Latitude_deg    = env.Location.Latitude_deg;
    env.Longitude_deg   = env.Location.Longitude_deg;
    env.Elevation_MSL_m = env.Location.Elevation_MSL_m;
    % ─────────────────────────────────────────────────────────────────────

    assignin('base', 'env', env);
    displayEnvironmentSummary(env);
end


% =========================================================================
%% 1 — SEA LEVEL ISA STANDARD
% =========================================================================
function env = preset1_SeaLevelStandard()
% ISA sea level, zero wind — universal reference baseline.
% All teams run this first to establish a baseline score before testing
% at their actual competition site or challenge environments.
% T=15°C, P=101325 Pa, rho=1.2250 kg/m³ (exact ISA sea level)

    env.Name        = 'Sea Level Standard';
    env.Description = 'ISA sea level, zero wind — reference baseline for all teams';
    env.Multiplier  = 1.0;
    env.CompetitionSite = false;

    env.Location = makeLocation('ISA Reference Datum', 'Sea Level', '', 0, 0, 0);
    env.Atmosphere = makeAtmosphere(0, 0, 15.0, 101325, 1.2250);
    env.WindShear  = makeWindShear(0, 0, 0.143);
    env.Turbulence = makeTurbulence(0, 0, 0, 205, false);   % TurbulenceOn=false — reference baseline
    env.Gust       = makeGust([0 0 0], [1 1 1], Inf, 0);    % all axes disabled (zero amplitude)
end


% =========================================================================
%% 2 — COMPETITION DAY WEST: Apollo XI RC Field, Van Nuys CA
% =========================================================================
function env = preset2_CompetitionWest_VanNuys()
% SAE Aero Design West — Apollo XI RC Field, Van Nuys, CA (April)
%
% Exact field coordinates: 34.1809°N, 118.4835°W
% Located in Lake Balboa / Woodley Park, San Fernando Valley
% Adjacent to KVNY (Van Nuys Airport) — uses KVNY elevation data
%
% Real climate data (Van Nuys / KVNY, April historical averages):
%   Temperature:  avg high 21°C / avg low 10°C → competition morning ~19°C
%   ISA deviation: +6°C above standard
%   Wind:         avg 10 mph (4.5 m/s), predominantly from SSW (200°)
%                 San Fernando Valley channels winds from ocean through Sepulveda Pass
%   Elevation:    239 m MSL (784 ft)
%   Density:      rho = 1.1726 kg/m³ (95.7% of sea level)
%
% The valley location creates a characteristic afternoon thermal that
% strengthens as heating increases through the morning. Wind typically
% light (<5 m/s) in the early morning when flights usually occur.
% Multiplier 1.0×: competition site — scoring on even footing with East.

    env.Name        = 'Competition Day — West (Van Nuys CA, April)';
    env.Description = 'Apollo XI RC Field, Van Nuys CA — SAE Aero Design West, April avg';
    env.Multiplier  = 1.1;
    env.CompetitionSite = true;

    env.Location = makeLocation( ...
        'Apollo XI RC Field — SAE Aero Design West', ...
        'Van Nuys', 'CA USA', ...
        34.1809, -118.4835, 239);

    % rho = 1.1726 kg/m³ (95.7% SL): elevation 239m + ISA+6°C
    env.Atmosphere = makeAtmosphere(239, 6, 19.4, 98487, 1.1726);

    % Wind: 4.5 m/s from SSW (200°) — light morning valley wind
    % Open flat field in park, standard 1/7 exponent
    env.WindShear  = makeWindShear(4.5, 200, 0.143);

    % Light turbulence — calm April morning in sheltered valley
    % TurbulenceOn=false: competition baseline, enable for advanced runs
    env.Turbulence = makeTurbulence(4.5, 200, 1.06, 205, false);

    % No discrete gust — typical morning flight window
    env.Gust = makeGust([0 0 0], [1 1 1], Inf, 0);
end


% =========================================================================
%% 3 — COMPETITION DAY EAST: KLAL, Lakeland FL
% =========================================================================
function env = preset3_CompetitionEast_Lakeland()
% SAE Aero Design East — Lakeland Linder Airport (KLAL), FL (March)
%
% VENUE NOTE: East rotates between Lakeland FL and Fort Worth TX annually.
%   2024 East: Lakeland FL   2025 East: Fort Worth TX   2026 East: Lakeland FL
%   Select preset 3 for Lakeland years, preset 4 for Fort Worth years.
%
% Real climate data (KLAL, March historical averages):
%   Temperature:  avg high 25°C / avg low 14°C → morning ~22°C → ISA+7°C
%   Wind:         avg 13 mph (5.9 m/s), predominantly SE (120°)
%   Elevation:    43.3 m MSL (142 ft)
%   Density:      rho = 1.1910 kg/m³ (97.2% of sea level)
%
% SE wind creates crosswind relative to KLAL runway 05 (heading 050°).
% Multiplier 1.2×: wind crosswind challenge is primary; density loss modest.
% Higher than Van Nuys (1.1×) despite better density because 5.9 m/s
% crosswind is the dominant performance factor here.

    env.Name        = 'Competition Day — East FL (Lakeland, March)';
    env.Description = 'KLAL Lakeland FL — SAE Aero Design East, March avg (2024, 2026 venue)';
    env.Multiplier  = 1.2;
    env.CompetitionSite = true;

    env.Location = makeLocation( ...
        'Lakeland Linder Intl Airport (KLAL)', ...
        'Lakeland', 'FL USA', ...
        27.9889, -81.9478, 43.3);

    % rho = 1.1910 kg/m³ (97.2% SL)
    env.Atmosphere = makeAtmosphere(43.3, 7, 22.0, 100806, 1.1910);

    % SE crosswind to runway
    env.WindShear  = makeWindShear(5.9, 120, 0.143);

    % Light turbulence — stable spring morning
    % TurbulenceOn=false: competition baseline, enable for advanced runs
    env.Turbulence = makeTurbulence(5.9, 120, 1.06, 205, false);

    env.Gust = makeGust([0 0 0], [1 1 1], Inf, 0);
end


% =========================================================================
%% 4 — COMPETITION DAY EAST: Thunderbird Field, Fort Worth TX
% =========================================================================
function env = preset4_CompetitionEast_FortWorth()
% SAE Aero Design East — Thunderbird Field, Fort Worth TX (May)
%
% VENUE NOTE: East rotates between Lakeland FL and Fort Worth TX annually.
%   2024 East: Lakeland FL   2025 East: Fort Worth TX   2026 East: Lakeland FL
%   Select preset 4 for Fort Worth years, preset 3 for Lakeland years.
%
% Field address: 4300 Winscott Plover Rd, Fort Worth TX 76126
% Exact coords: 32.5292°N, 97.4797°W — Mustang Park, south shore Benbrook Lake
%
% Real climate data (DFW/Fort Worth, May historical averages):
%   Temperature:  avg high 30°C / avg low 19°C → competition day ~27°C → ISA+12°C
%   Wind:         avg 10.3 mph (4.6 m/s), predominantly S/SE (160°)
%   Elevation:    262 m MSL (860 ft)
%   Density:      rho = 1.1465 kg/m³ (93.6% of sea level)
%
% Fort Worth is the hardest of the three competition sites:
%   Stall speed +3.4%,  takeoff roll +6.8% vs ISA sea level
% Teams who only tested at sea level will be noticeably surprised here.
% DFW May afternoons carry storm risk — competition flights typically morning.
% Multiplier 1.3×: highest competition multiplier, density loss dominant.

    env.Name        = 'Competition Day — East TX (Fort Worth, May)';
    env.Description = 'Thunderbird Field, Fort Worth TX — SAE Aero Design East, May avg (2025 venue)';
    env.Multiplier  = 1.3;
    env.CompetitionSite = true;

    env.Location = makeLocation( ...
        'Thunderbird Field, Mustang Park (SAE Aero Design East)', ...
        'Fort Worth', 'TX USA', ...
        32.5292, -97.4797, 262);

    % rho = 1.1465 kg/m³ (93.6% SL) — lowest density of all three competition sites
    env.Atmosphere = makeAtmosphere(262, 12, 25.3, 98217, 1.1465);

    % S/SE wind, open lake-shore field at Benbrook Lake
    env.WindShear  = makeWindShear(4.6, 160, 0.143);

    % Light turbulence — warm spring morning
    % TurbulenceOn=false: competition baseline, enable for advanced runs
    env.Turbulence = makeTurbulence(4.6, 160, 1.06, 205, false);

    env.Gust = makeGust([0 0 0], [1 1 1], Inf, 0);
end


% =========================================================================
%% 5 — HOT DAY: Chennai International (VOMM), March
% =========================================================================
function env = preset5_HotDay()
% Chennai International Airport (VOMM), Tamil Nadu India — March average.
%
% Real climate data (VOMM, March historical averages):
%   Temperature:  avg max 30°C / avg min 23°C → competition day ~30°C → ISA+15°C
%   Wind:         avg 3.5 m/s (8 mph), SW (230°)
%   Elevation:    16 m MSL (52 ft)
%   Density:      rho = 1.1626 kg/m³ (94.9% of sea level)
%
% 5.1% density reduction: stall speed +2.6%, takeoff roll +5.4%,
% thrust reduced proportionally. Light wind means this is a pure
% density challenge — no wind to help mask the performance deficit.
% Represents Indian subcontinent and similar tropical team environments.
% Multiplier 1.5×: density loss is the dominant performance penalty.

    env.Name        = 'Hot Day (Chennai India, March)';
    env.Description = 'VOMM Chennai India, March avg — hot thin air, reduced thrust and lift';
    env.Multiplier  = 1.5;
    env.CompetitionSite = false;

    env.Location = makeLocation( ...
        'Chennai Intl Airport (VOMM)', ...
        'Chennai', 'Tamil Nadu, India', ...
        12.9941, 80.1709, 16);

    env.Atmosphere = makeAtmosphere(16, 15, 30.0, 101133, 1.1626);

    env.WindShear  = makeWindShear(3.5, 230, 0.143);

    % Light turbulence — stable hot-day boundary layer
    % TurbulenceOn=false: density is the challenge here, not turbulence
    env.Turbulence = makeTurbulence(3.5, 230, 1.06, 205, false);

    env.Gust = makeGust([0 0 0], [1 1 1], Inf, 0);
end


% =========================================================================
%% 6 — COLD WINDY DAY: Toronto Pearson (CYYZ), March
% =========================================================================
function env = preset6_ColdWindyDay()
% Toronto Pearson International Airport (CYYZ), Ontario Canada — March avg.
%
% Real climate data (CYYZ, March historical averages):
%   Temperature:  avg high 4°C / avg low -3°C → midday ~1°C → ISA-14°C
%   Wind:         avg 17.5 mph (7.8 m/s), predominantly NW (315°)
%   Elevation:    173 m MSL (568 ft)
%   Density:      rho = 1.2666 kg/m³ (103.4% of sea level — DENSER)
%
% Cold dense air provides more lift and thrust per unit area — the
% aerodynamics are actually easier. The challenge is the strong gusty NW
% wind from cold front passages typical of Ontario March.
% Moderate turbulence + discrete gust at t=45s simulate cold front event.
% Represents northern/Canadian team home testing conditions.
% Multiplier 1.6×: wind is the dominant challenge; dense air provides no bonus.

    env.Name        = 'Cold Windy Day (Toronto ON, March)';
    env.Description = 'CYYZ Toronto Canada, March avg — cold dense air, strong gusty NW wind';
    env.Multiplier  = 1.6;
    env.CompetitionSite = false;

    env.Location = makeLocation( ...
        'Toronto Pearson Intl Airport (CYYZ)', ...
        'Toronto', 'ON Canada', ...
        43.6772, -79.6306, 173);

    env.Atmosphere = makeAtmosphere(173, -14, 1.0, 99264, 1.2666);

    % NW wind, slightly higher exponent for suburban terrain at Pearson
    env.WindShear  = makeWindShear(7.8, 315, 0.160);

    % Moderate turbulence — gusty cold front
    % TurbulenceOn=true: challenge preset, turbulence is part of the scenario
    env.Turbulence = makeTurbulence(7.8, 315, 2.12, 205, true);

    % 4.0 m/s gust from NW at t=45s cruise, 20m AGL — v-axis lateral component
    % Wind from 315° → lateral gust, same length in all axes
    gustMag = 4.0;
    env.Gust = makeGust( ...
        [gustMag*cosd(135) gustMag*sind(135) 0], [150 150 150], 45, 20);
end



% =========================================================================
%% 7 — AFTERNOON GUSTS: Lakeland FL afternoon convective
% =========================================================================
function env = preset7_AfternoonGusts()
% Lakeland FL (KLAL) — afternoon convective activity, March.
%
% Florida March afternoons: sea breeze and thunderstorm outflows create
% wind shifts SE→SW, stronger winds, and discrete gusts on approach.
%
% Atmosphere: ISA+13°C (hot afternoon), rho = 1.1672 kg/m³ (95.3% SL)
% Wind: 8.0 m/s from SW (220°)
% Gust: 4.0 m/s lateral at t=90s, 15m AGL — approach phase
%   This targets the most likely competition hazard: a crosswind gust
%   from a convective outflow just before touchdown.
% Multiplier 2.0×: combined density + wind + approach gust challenge.

    env.Name        = 'Afternoon Gusts (Lakeland FL)';
    env.Description = 'KLAL Lakeland FL afternoon — SW wind shift, crosswind gust on approach';
    env.Multiplier  = 2.0;
    env.CompetitionSite = false;

    env.Location = makeLocation( ...
        'Lakeland Linder Intl Airport (KLAL)', ...
        'Lakeland', 'FL USA', ...
        27.9889, -81.9478, 43.3);

    env.Atmosphere = makeAtmosphere(43.3, 13, 28.0, 100806, 1.1672);

    env.WindShear  = makeWindShear(8.0, 220, 0.143);

    % Moderate turbulence — afternoon convective
    % TurbulenceOn=true: challenge preset, turbulence is part of the scenario
    env.Turbulence = makeTurbulence(8.0, 220, 2.12, 205, true);

    % 4.0 m/s lateral (v-axis) gust on approach at t=90s, 15m AGL
    % Simulates convective outflow crosswind just before touchdown
    % dx=1 (u disabled by zero amp), dy=200m wavelength, dz=1 (w disabled)
    env.Gust = makeGust([0 4.0 0], [1 200 1], 90, 15);
end


% =========================================================================
%% 8 — HIGH DENSITY ALTITUDE: Denver-type, 1600m ISA+10
% =========================================================================
function env = preset8_HighDensityAltitude()
% High Density Altitude — Denver/Albuquerque-type scenario.
% 1600 m elevation + ISA+10°C → equivalent density altitude ~2400 m.
%
% rho = 1.0112 kg/m³ — only 82.5% of ISA sea level.
%   Stall speed rises:   +10.1%  (must fly ~10% faster to stay airborne)
%   Takeoff roll:        +21.2%  (significantly longer — may exceed 30m limit)
%   Thrust reduction:    ~17.5%  (motor kV and prop efficiency scale with rho)
%   Climb rate:          reduced proportionally
% Many designs that pass sea-level validation will fail here.
% Light wind isolates the density challenge.
% Multiplier 2.5×: hardest preset in the library.

    env.Name        = 'High Density Altitude (Denver-type)';
    env.Description = 'Denver-type 1600m ISA+10 — 82.5% sea-level density, hardest thrust/lift case';
    env.Multiplier  = 2.5;
    env.CompetitionSite = false;

    env.Location = makeLocation( ...
        'High Altitude Reference (KDEN-type)', ...
        'Denver', 'CO USA', ...
        39.8561, -104.6737, 1600);

    env.Atmosphere = makeAtmosphere(1600, 10, 14.6, 83523, 1.0112);

    env.WindShear  = makeWindShear(5.0, 270, 0.143);

    % Light turbulence — calm day to isolate density effect
    % TurbulenceOn=false: density is the challenge, turbulence would confound it
    env.Turbulence = makeTurbulence(5.0, 270, 1.06, 205, false);

    env.Gust = makeGust([0 0 0], [1 1 1], Inf, 0);
end


% =========================================================================
%% HELPER CONSTRUCTORS
% =========================================================================

function loc = makeLocation(name, city, country, lat, lon, elev_m)
    loc.Name             = name;
    loc.City             = city;
    loc.Country          = country;
    loc.Latitude_deg     = lat;
    loc.Longitude_deg    = lon;
    loc.Elevation_MSL_m  = elev_m;
end

function atm = makeAtmosphere(alt_m, ISA_dev_C, T_C, P_Pa, rho)
% Reference values for display and logging.
% COESA block computes atmosphere from altitude at runtime — these
% values are NOT fed into any Simulink block as parameters.
    atm.Elevation_MSL_m  = alt_m;
    atm.ISA_Deviation_C  = ISA_dev_C;
    atm.Temperature_C    = T_C;
    atm.Pressure_Pa      = P_Pa;
    atm.Density_kgm3     = rho;
    atm.DensityRatio     = rho / 1.2250;   % fraction of ISA sea level
end

function ws = makeWindShear(speed_mps, dir_deg, exponent)
% Parameters for Aerospace Blockset Wind Shear Model block.
% Exponent: 0.143 = 1/7 law open flat terrain (all comp sites)
%           0.160 = slightly rough (urban terrain, CYYZ)
    ws.Speed_6m_mps  = speed_mps;  % [m/s]  speed at 6m reference height
    ws.Direction_deg = dir_deg;    % [deg]  FROM this heading (met convention)
    ws.Exponent      = exponent;   % [-]    power-law shear exponent
end

function turb = makeTurbulence(speed_mps, dir_deg, sigma_mps, Lu_m, turbOn)
% Parameters for Aerospace Blockset Dryden Turbulence (Continuous, +q-r) block.
%
% speed_mps  — wind speed at 6m reference height [m/s]
% dir_deg    — wind direction at 6m, degrees clockwise from north [deg]
%              matches block field "Wind direction at 6 m (degrees clockwise from north)"
% sigma_mps  — RMS turbulence intensity [m/s], MIL-HDBK-1797 levels:
%                0 = OFF,  1.06 = Light,  2.12 = Moderate,  4.24 = Severe
% Lu_m       — scale length at medium/high altitudes [m]
%                SAE cruise ~30m AGL: 205m (MIL-HDBK-1797 low-altitude)
%                Block uses one scale length (Lu) — Lv/Lw derived internally
% turbOn     — logical, maps to block "Turbulence on" checkbox
%                true  = turbulence active
%                false = block present but turbulence disabled
%              Values are always populated so the preset can be re-enabled
%              without editing any numbers — just flip TurbulenceOn to true.
%
% NoiseSeeds fixed at [23341 23342 23343 23344] for reproducibility.

    turb.Speed_6m_mps  = speed_mps;
    turb.Direction_deg = dir_deg;
    turb.Sigma_mps     = sigma_mps;
    turb.Scale_Lu_m    = Lu_m;
    turb.TurbulenceOn  = turbOn;
    turb.NoiseSeeds    = [23341 23342 23343 23344];
end

function gust = makeGust(amplitude_mps, length_m, startTime_s, startAlt_AGL_m)
% Parameters for Aerospace Blockset Discrete Wind Gust Model block.
%
% amplitude_mps  [1x3]  [ug vg wg] peak gust components [m/s]
%                         ug = along-body u-axis  (+ve into nose = headwind)
%                         vg = along-body v-axis  (+ve from left = lateral)
%                         wg = along-body w-axis  (+ve downward  = downdraft)
% length_m       [1x3]  [dx dy dz] gust wavelengths per axis [m]
%                         block field: "Gust length [dx dy dz] (m)"
%                         each axis can have a different spatial wavelength
% startTime_s    [s]    simulation time of gust onset
%                         Inf = disabled (never fires regardless of sim duration)
%                         Use Inf, not a large number — Inf is correct by construction
%                         and has no hidden dependency on the 300s simulation window.
% startAlt_AGL_m [m]    AGL altitude at gust onset
%
% Per-axis enable flags — map to block checkboxes:
%   "Gust in u-axis" / "Gust in v-axis" / "Gust in w-axis"
% A flag is set true when the corresponding amplitude component is nonzero.
% Override manually if you want a zero-amplitude axis enabled or vice versa.

    gust.Amplitude_mps       = amplitude_mps;           % [1x3] [ug vg wg]
    gust.Length_m            = length_m;                 % [1x3] [dx dy dz]
    gust.StartTime_s         = startTime_s;
    gust.StartAltitude_AGL_m = startAlt_AGL_m;

    % Per-axis enable flags (auto-derived from amplitude; override if needed)
    gust.EnableU = amplitude_mps(1) ~= 0;   % Gust in u-axis checkbox
    gust.EnableV = amplitude_mps(2) ~= 0;   % Gust in v-axis checkbox
    gust.EnableW = amplitude_mps(3) ~= 0;   % Gust in w-axis checkbox
end


% =========================================================================
%% DISPLAY
% =========================================================================

function displayEnvironmentSummary(env)
    

    if env.CompetitionSite
        fprintf('  ★ COMPETITION SITE PRESET — actual SAE venue conditions\n\n');
    end

    fprintf('  Location     %s, %s\n',   env.Location.City, env.Location.Country);
    % fprintf('  Lat / Lon    %.4f°  %.4f°\n', env.Latitude_deg, env.Longitude_deg);
    % fprintf('  Elevation    %.0f m MSL   (%.0f ft)\n', ...
    %         env.Elevation_MSL_m, ...
    %         env.Elevation_MSL_m / 0.3048);
    % fprintf('\n');
    % 
    % fprintf('  ── Atmosphere (COESA computes at runtime from ACStates altitude) ──\n');
    % fprintf('  ISA offset    %+.0f°C\n',    env.Atmosphere.ISA_Deviation_C);
    % fprintf('  Temperature   %.1f°C\n',      env.Atmosphere.Temperature_C);
    % fprintf('  Pressure      %.0f Pa\n',     env.Atmosphere.Pressure_Pa);
    % fprintf('  Air density   %.4f kg/m³   (%.1f%% of ISA sea level)\n', ...
    %         env.Atmosphere.Density_kgm3, ...
    %         env.Atmosphere.DensityRatio * 100);

    % Performance impact callout for non-standard density
    % dr = env.Atmosphere.DensityRatio;
    % if dr < 0.99
    %     dStall   = (1/sqrt(dr) - 1) * 100;
    %     dTakeoff = (1/dr - 1) * 100;
    %     fprintf('  ▲ Stall speed  +%.1f%%   Takeoff roll +%.1f%%   vs ISA sea level\n', ...
    %             dStall, dTakeoff);
    % elseif dr > 1.01
    %     fprintf('  ▼ Dense air: slightly more lift and thrust than sea level\n');
    % end
    % fprintf('\n');

    % fprintf('  ── Wind Shear block ──\n');
    % fprintf('  Speed @ 6m    %.1f m/s  (%.1f mph)  from %d°\n', ...
    %         env.WindShear.Speed_6m_mps, ...
    %         env.WindShear.Speed_6m_mps * 2.237, ...
    %         env.WindShear.Direction_deg);
    % fprintf('  Exponent      %.3f\n', env.WindShear.Exponent);
    % fprintf('\n');
    % 
    % fprintf('  ── Dryden Turbulence block ──\n');
    % if env.Turbulence.TurbulenceOn
    %     fprintf('  Turbulence    ON\n');
    % else
    %     fprintf('  Turbulence    OFF (values stored — set TurbulenceOn=true to enable)\n');
    % end
    % fprintf('  Sigma         %.2f m/s  (%s)\n', ...
    %         env.Turbulence.Sigma_mps, turbLabel(env.Turbulence.Sigma_mps));
    % fprintf('  Speed @ 6m    %.1f m/s   Direction %d° (clockwise from N)\n', ...
    %         env.Turbulence.Speed_6m_mps, env.Turbulence.Direction_deg);
    % fprintf('  Scale Lu      %.0f m\n', env.Turbulence.Scale_Lu_m);
    % fprintf('\n');
    % 
    % fprintf('  ── Discrete Gust block ──\n');
    % gustMag = norm(env.Gust.Amplitude_mps);
    % axesEnabled = sprintf('%s%s%s', ...
    %     ternary(env.Gust.EnableU, 'u ', ''), ...
    %     ternary(env.Gust.EnableV, 'v ', ''), ...
    %     ternary(env.Gust.EnableW, 'w ', ''));
    % if gustMag > 0.01
    %     fprintf('  Axes active   [%s]\n', strtrim(axesEnabled));
    %     fprintf('  Amplitude     %.1f m/s   [ug=%.1f  vg=%.1f  wg=%.1f]\n', ...
    %             gustMag, ...
    %             env.Gust.Amplitude_mps(1), ...
    %             env.Gust.Amplitude_mps(2), ...
    %             env.Gust.Amplitude_mps(3));
    %     fprintf('  Length [dxdydz] [%.0f  %.0f  %.0f] m\n', ...
    %             env.Gust.Length_m(1), env.Gust.Length_m(2), env.Gust.Length_m(3));
    %     fprintf('  Onset         t = %.0f s,   %.0f m AGL\n', ...
    %             env.Gust.StartTime_s, env.Gust.StartAltitude_AGL_m);
    % else
    %     fprintf('  No discrete gust (all axes disabled)\n');
    % end
    % fprintf('\n');

    % fprintf('  Score multiplier:  %.1f×\n', env.Multiplier);
   
end

function lbl = turbLabel(sigma)
    if sigma == 0
        lbl = 'OFF';
    elseif sigma <= 1.5
        lbl = 'Light    (MIL-HDBK-1797)';
    elseif sigma <= 3.0
        lbl = 'Moderate (MIL-HDBK-1797)';
    else
        lbl = 'Severe   (MIL-HDBK-1797)';
    end
end

function out = ternary(cond, a, b)
% Inline if-else for string building in display functions.
    if cond, out = a; else, out = b; end
end
