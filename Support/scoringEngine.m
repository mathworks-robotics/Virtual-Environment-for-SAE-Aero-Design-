% =========================================================================
% scoringEngine.m
%
% CORE FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% Computes the mission score from Simulink simulation output data.
% Run this after the simulation has completed and states are in the
% MATLAB workspace.
%
% MISSION DEFINITION:
%   - One takeoff per flight, one landing per flight
%   - Cruise altitude target: 50m AGL  (tolerance ±10m accepted)
%   - Each lap: takeoff OR fly outbound 500m, turn, return to runway threshold
%   - Last lap is ONLY counted if the aircraft successfully lands
%     (altitude < landingAlt_m AND within runway proximity)
%   - If last lap is incomplete (no landing), it is discarded
%   - Minimum 1 complete lap with landing required for non-zero score
%
% SCORING FORMULA:
%   MissionScore = LapsCompleted × PayloadRatio × EnvironmentMultiplier
%   where:
%     PayloadRatio         = PayloadMass / EmptyMass
%     EnvironmentMultiplier = environment.ScoreMultiplier
%
% ZERO SCORE CONDITIONS:
%   - Aircraft never reaches cruise altitude (50m ± 10m)
%   - No complete lap with landing within 300s simulation time
%
% SYNTAX:
%   result = scoringEngine(simData, initial, environment)
%
% INPUTS:
%   simData     — struct of simulation outputs logged to workspace:
%                   .time   [Nx1]  time vector [s]
%                   .pos_N  [Nx1]  North position from runway origin [m]
%                   .pos_E  [Nx1]  East position from runway origin  [m]
%                   .alt    [Nx1]  altitude AGL [m]
%                   .psi    [Nx1]  heading [rad]  (optional, for diagnostics)
%
%   initial     — struct from setupData_Manual.m Section 2:
%                   .Mass.Empty    [kg]
%                   .Mass.Payload  [kg]
%
%   environment — struct from environmentLibrary.m:
%                   .ScoreMultiplier  [-]
%                   .name             (for display)
%
% OUTPUT:
%   result — struct with fields:
%     .missionScore         Final score
%     .lapsCompleted        Integer lap count (only laps ending in landing)
%     .payloadRatio         Payload / Empty mass
%     .envMultiplier        From environment preset
%     .altitudeRequirementMet   logical
%     .maxAltitude_m        Peak altitude reached [m]
%     .landingDetected      logical — was landing achieved?
%     .flightTime_s         Time from takeoff to landing [s]
%     .lapLog               struct array with per-lap details
%     .scoreBreakdown       string for display
%
% EXPECTED simData VARIABLE NAMES (from Simulink 'To Workspace' blocks):
%   These match the standard output bus in SimulationChallenge.slx.
%   If your model uses different names, rename before calling this function.
%
% =========================================================================

function result = scoringEngine(simData, initial, environment)

    % ---- Parameters -------------------------------------------------------
    CRUISE_ALT_TARGET_m  = 50;     % [m]  Target cruise altitude
    CRUISE_ALT_TOL_m     = 10;     % [m]  Acceptable altitude band: 40–60m
    RUNWAY_RADIUS_m      = 30;     % [m]  Proximity to runway threshold = lap complete
    LEG_LENGTH_m         = 500;    % [m]  One-way leg distance
    LEG_TOL_m            = 40;     % [m]  Tolerance on leg endpoint detection
    LANDING_ALT_m        = 3;      % [m]  Altitude below which = on ground
    TAKEOFF_ALT_m        = 5;      % [m]  Altitude above which = airborne
    SIM_TIME_s           = 300;    % [s]  Total simulation window

    % ---- Validate inputs --------------------------------------------------
    validateInputs(simData, initial, environment);

    t   = simData.time(:);
    N   = simData.pos_N(:);
    E   = simData.pos_E(:); 
    alt = simData.alt(:);

    distFromRunway = sqrt(N.^2 + E.^2);   % distance from (0,0) origin

    % ---- 1. Altitude requirement check ------------------------------------
    maxAlt = max(alt);
    altReqMet = maxAlt >= (CRUISE_ALT_TARGET_m - CRUISE_ALT_TOL_m);

    % ---- 2. Detect takeoff and landing events -----------------------------
    % Takeoff: first time aircraft exceeds TAKEOFF_ALT_m
    takeoffIdx = find(alt > TAKEOFF_ALT_m, 1, 'first');
    if isempty(takeoffIdx)
        takeoffIdx = 1;
    end

    % ---- 3. Count laps via state machine ----------------------------------
    [lapsCompleted, lapLog, landingDetected] = countLaps( ...
        t, N, E, alt, distFromRunway, ...
        takeoffIdx, ...
        LEG_LENGTH_m, LEG_TOL_m, ...
        RUNWAY_RADIUS_m, LANDING_ALT_m, SIM_TIME_s);

    % ---- 4. Zero-score conditions -----------------------------------------
    if ~altReqMet
        lapsCompleted = 0;
        fprintf('\n  SCORE = 0 — Aircraft never reached cruise altitude.\n');
        fprintf('  Maximum altitude: %.1f m  (required: %.0f ± %.0f m)\n', ...
            maxAlt, CRUISE_ALT_TARGET_m, CRUISE_ALT_TOL_m);
    end

    if lapsCompleted == 0
        fprintf('\n  SCORE = 0 — No complete laps with landing detected.\n');
    end

    % ---- 5. Compute score -------------------------------------------------
    payloadRatio  = initial.Mass.Payload / initial.Mass.Empty;
    envMultiplier = environment.ScoreMultiplier;
    missionScore  = lapsCompleted * payloadRatio * envMultiplier;

    % ---- 6. Flight time ---------------------------------------------------
    landingIdx = find(alt < LANDING_ALT_m & t > t(takeoffIdx), 1, 'last');
    if isempty(landingIdx)
        flightTime_s = t(end) - t(takeoffIdx);
    else
        flightTime_s = t(landingIdx) - t(takeoffIdx);
    end

    % ---- 7. Assemble result -----------------------------------------------
    result.missionScore           = missionScore;
    result.lapsCompleted          = lapsCompleted;
    result.payloadRatio           = payloadRatio;
    result.envMultiplier          = envMultiplier;
    result.altitudeRequirementMet = altReqMet;
    result.maxAltitude_m          = maxAlt;
    result.landingDetected        = landingDetected;
    result.flightTime_s           = flightTime_s;
    result.lapLog                 = lapLog;
    result.scoreBreakdown         = buildBreakdown(result, initial, environment);

    printResult(result, environment);
end


% =========================================================================
%% LAP COUNTER — state machine
% =========================================================================

function [lapsCompleted, lapLog, landingDetected] = countLaps( ...
        t, N, E, alt, distRunway, ...
        takeoffIdx, legLen, legTol, runwayRadius, landingAlt, simTime)

    % State machine states:
    %   0 = on ground / pre-takeoff
    %   1 = airborne, climbing / cruising, heading outbound
    %   2 = outbound leg complete (crossed 500m mark)
    %   3 = inbound (returning toward runway)

    state        = 0;
    lapsCompleted = 0;
    landingDetected = false;
    lapLog       = struct('lapNumber', {}, 'outboundTime_s', {}, ...
                          'returnTime_s', {}, 'landingTime_s', {}, ...
                          'maxAlt_m', {}, 'valid', {});

    lapStart     = takeoffIdx;
    lapPeakAlt   = 0;
    outboundTime = NaN;
    returnTime   = NaN;

    nPts = length(t);

    for i = takeoffIdx:nPts

        h = alt(i);
        d = distRunway(i);

        % Peak altitude tracking for current lap
        lapPeakAlt = max(lapPeakAlt, h);

        switch state

            case 0  % on ground — waiting for takeoff
                if h > 5
                    state = 1;
                    lapStart = i;
                end

            case 1  % airborne — detect outbound leg completion
                % Outbound leg: aircraft has flown >= legLen from runway
                % Use horizontal distance only (NE plane)
                horizDist = sqrt(N(i)^2 + E(i)^2);
                if horizDist >= (legLen - legTol)
                    state = 2;
                    outboundTime = t(i);
                end

            case 2  % outbound complete — detect return toward runway
                % Return leg: aircraft is now coming back (distance reducing)
                % Detect when aircraft is within legTol of runway heading back
                if d <= runwayRadius && h > 5
                    % Crossed runway threshold while still airborne = end of return leg
                    state    = 3;
                    returnTime = t(i);
                end

            case 3  % returned to runway — detect landing
                if h <= landingAlt
                    % Landing confirmed
                    lapsCompleted   = lapsCompleted + 1;
                    landingDetected = true;

                    % Log this lap
                    entry.lapNumber     = lapsCompleted;
                    entry.outboundTime_s = outboundTime;
                    entry.returnTime_s   = returnTime;
                    entry.landingTime_s  = t(i);
                    entry.maxAlt_m       = lapPeakAlt;
                    entry.valid          = true;
                    lapLog(end+1)        = entry; %#ok<AGROW>

                    % Reset for next lap
                    state        = 0;
                    lapPeakAlt   = 0;
                    outboundTime = NaN;
                    returnTime   = NaN;

                elseif t(i) >= simTime
                    % Simulation ended before landing — discard this lap
                    entry.lapNumber      = lapsCompleted + 1;
                    entry.outboundTime_s = outboundTime;
                    entry.returnTime_s   = returnTime;
                    entry.landingTime_s  = NaN;
                    entry.maxAlt_m       = lapPeakAlt;
                    entry.valid          = false;  % no landing = not counted
                    lapLog(end+1)        = entry; %#ok<AGROW>
                end
        end

        % Simulation time expired
        if t(i) >= simTime
            break
        end
    end

    % Handle case where aircraft returned but sim ended before landing
    % (state == 3 at end of loop — already logged as invalid above)
    % Handle case where aircraft was mid-outbound at end of sim (state == 1 or 2)
    if state == 1 || state == 2
        % Incomplete lap — log for diagnostics but don't count
        entry.lapNumber      = lapsCompleted + 1;
        entry.outboundTime_s = outboundTime;
        entry.returnTime_s   = NaN;
        entry.landingTime_s  = NaN;
        entry.maxAlt_m       = lapPeakAlt;
        entry.valid          = false;
        lapLog(end+1) = entry; %#ok<AGROW>
    end
end


% =========================================================================
%% DISPLAY
% =========================================================================

function printResult(r, env)
    fprintf('\n');
    fprintf('╔══════════════════════════════════════════════════════════╗\n');
    fprintf('║  SAE AERO DESIGN — MISSION SCORE RESULT                 ║\n');
    fprintf('╚══════════════════════════════════════════════════════════╝\n');
    fprintf('  Environment     : %s  (multiplier = %.2f)\n', env.name, r.envMultiplier);
    fprintf('  Max altitude    : %.1f m   (req: ≥40 m)   %s\n', ...
        r.maxAltitude_m, checkMark(r.altitudeRequirementMet));
    fprintf('  Landing         : %s\n', checkMark(r.landingDetected));
    fprintf('  Flight time     : %.1f s\n', r.flightTime_s);
    fprintf('\n');
    fprintf('  Laps completed  : %d\n',   r.lapsCompleted);
    fprintf('  Payload ratio   : %.4f  (%.3f kg / %.3f kg)\n', ...
        r.payloadRatio, r.payloadRatio, 1.0);  % ratio shown directly
    fprintf('  Env multiplier  : %.2f\n', r.envMultiplier);
    fprintf('  ─────────────────────────────────────────────────────\n');
    fprintf('  MISSION SCORE   : %.4f\n', r.missionScore);
    fprintf('  ─────────────────────────────────────────────────────\n');

    if ~isempty(r.lapLog)
        fprintf('\n  Lap log:\n');
        for i = 1:length(r.lapLog)
            lap = r.lapLog(i);
            if lap.valid
                fprintf('    Lap %d  — outbound: %.1fs  return: %.1fs  land: %.1fs  peak alt: %.1fm  ✓\n', ...
                    lap.lapNumber, lap.outboundTime_s, lap.returnTime_s, ...
                    lap.landingTime_s, lap.maxAlt_m);
            else
                fprintf('    Lap %d  — INCOMPLETE (no landing before t=300s)  ✗  [not counted]\n', ...
                    lap.lapNumber);
            end
        end
    end
    fprintf('\n');
end


function s = buildBreakdown(r, initial, env)
    s = sprintf(['Score = %d laps × %.4f payload ratio × %.2f env multiplier = %.4f\n' ...
                 'Payload: %.3f kg  |  Empty: %.3f kg  |  Environment: %s'], ...
        r.lapsCompleted, r.payloadRatio, r.envMultiplier, r.missionScore, ...
        initial.Mass.Payload, initial.Mass.Empty, env.name);
end


function s = checkMark(flag)
    if flag, s = '✓'; else, s = '✗'; end
end


% =========================================================================
%% INPUT VALIDATION
% =========================================================================

function validateInputs(simData, initial, environment)
    requiredSim = {'time', 'pos_N', 'pos_E', 'alt'};
    for i = 1:length(requiredSim)
        f = requiredSim{i};
        if ~isfield(simData, f)
            error('scoringEngine:missingField', ...
                'simData.%s is missing. Check your Simulink ''To Workspace'' block names.', f);
        end
    end
    if ~isfield(initial.Mass, 'Empty') || ~isfield(initial.Mass, 'Payload')
        error('scoringEngine:massFields', ...
            'initial.Mass.Empty and initial.Mass.Payload must be set.');
    end
    if initial.Mass.Empty <= 0
        error('scoringEngine:zeroMass', 'initial.Mass.Empty must be > 0.');
    end
    if ~isfield(environment, 'ScoreMultiplier')
        error('scoringEngine:noMultiplier', ...
            'environment.ScoreMultiplier not found. Run environmentLibrary first.');
    end
end
