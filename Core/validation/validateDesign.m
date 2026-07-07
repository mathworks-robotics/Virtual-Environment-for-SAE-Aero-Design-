% =========================================================================
% validateDesign.m
%
% CORE FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% This file is part of the CORE/validation/ layer of the simulation
% framework. It enforces SAE Aero Design Regular Class competition rules
% and performs basic reasonableness checks on your aircraft data.
%
% Modifying rule thresholds or check logic will invalidate your results
% relative to other teams using the standard framework.
%
% If you believe there is a bug or a rule has changed, contact your team
% advisor or the MathWorks Aerospace Education Team.
% =========================================================================
%
% RULE REFERENCE:
%   SAE Aero Design Regular Class — 2024/2025 Competition Rules
%   All numeric limits are taken directly from the official rulebook.
%
% CHECKS PERFORMED HERE (based on available setup data):
%   Critical  — Wingspan, gross weight, battery voltage, T/W floor
%   Advisory  — Wing loading, aspect ratio, CG position, aero data coverage,
%               propulsion table coverage, CLmax, CLalpha, CD0
%
% CHECKS DEFERRED TO ANALYSIS FILES (require additional computed data):
%   Stall speed, takeoff distance  → analyzePerformance.m
%   Eigenvalues, static margin     → analyzeStability.m
%
% =========================================================================

function report = validateDesign(geometry, initial, propulsionData, aeroData)
% VALIDATEDESIGN  Check aircraft design against SAE Regular Class rules
%
% SYNTAX:
%   report = validateDesign(geometry, initial, propulsionData, aeroData)
%
% INPUTS:
%   geometry       - struct:
%                      .Span [m], .Area [m^2], .MAC [m], .Length [m]
%                      .AR [-], .PropArm [m], .CG_percentMAC [%MAC]
%   initial        - struct:
%                      .Mass.Empty [kg], .Mass.Payload [kg], .Mass.GrossTO [kg]
%                      .Inertia [kg.m^2]
%   propulsionData - struct from importPropulsionData:
%                      .Throttle, .Thrust_Newtons, .Power_Input, .Amperage
%                      .batteryCells [-], .maxThrust_N [N], .maxVoltage_V [V]
%   aeroData       - struct from setup file + extractAeroSummary:
%                      .elevatorData, .rudderData, .aileronData
%                      .CLmax [-], .CD0 [-], .CLalpha_perDeg [1/deg]
%
% OUTPUT:
%   report - struct:
%       .passed        - logical: true if all critical SAE rules satisfied
%       .violations    - cell array of critical violation strings
%       .warnings      - cell array of advisory warning strings
%       .performance   - struct: AR, wingLoading_kgm2, TW, maxThrust_N

    fprintf('\n');
    fprintf('=======================================================\n');
    fprintf('  SAE AERO DESIGN — DESIGN VALIDATION\n');
    fprintf('=======================================================\n\n');

    % ---- SAE Regular Class rule limits (2024/2025) ----------------------
    rules.maxWingspan_m      = 3.048;   % 10 ft
    rules.maxGrossWeight_kg  = 24.95;   % 55 lbs
    rules.maxBatteryCells    = 6;       % 6S LiPo max
    rules.maxVoltage_V       = 25.2;    % 6 × 4.2 V
    rules.minThrustToWeight  = 0.30;    % minimum viable T/W

    % ---- Initialise report ---------------------------------------------
    report.passed     = true;
    report.violations = {};
    report.warnings   = {};

    % ---- Derived quantities --------------------------------------------
    grossMass_kg     = initial.Mass.GrossTO;               % [kg]
    wingspan_m       = geometry.Span;                      % [m]
    wingArea_m2      = geometry.Area;                      % [m^2]
    g                = 9.81;                               % [m/s^2]
    weight_N         = grossMass_kg * g;                   % [N]
    wingLoading_kgm2 = grossMass_kg / wingArea_m2;         % [kg/m^2]
    TW               = propulsionData.maxThrust_N / weight_N;  % [-]

    % =====================================================================
    %% CRITICAL CHECKS
    % =====================================================================
    fprintf('--- Critical SAE Rule Checks ---\n');

    % Check 1: Wingspan
    if wingspan_m > rules.maxWingspan_m
        msg = sprintf('WINGSPAN: %.3f m (%.1f ft) exceeds limit of %.3f m (10 ft)', ...
            wingspan_m, wingspan_m/0.3048, rules.maxWingspan_m);
        report = addViolation(report, msg);
        fprintf('  ❌ %s\n', msg);
    else
        fprintf('  ✓  Wingspan:        %.3f m  (%.1f ft)   limit: %.3f m (10 ft)\n', ...
            wingspan_m, wingspan_m/0.3048, rules.maxWingspan_m);
    end

    % Check 2: Gross weight
    if grossMass_kg > rules.maxGrossWeight_kg
        msg = sprintf('GROSS WEIGHT: %.2f kg (%.1f lbs) exceeds limit of %.2f kg (55 lbs)', ...
            grossMass_kg, grossMass_kg/0.4536, rules.maxGrossWeight_kg);
        report = addViolation(report, msg);
        fprintf('  ❌ %s\n', msg);
    else
        fprintf('  ✓  Gross weight:    %.2f kg  (%.2f lbs)  limit: %.2f kg (55 lbs)\n', ...
            grossMass_kg, grossMass_kg/0.4536, rules.maxGrossWeight_kg);
    end

    % Check 3: Battery voltage
    if propulsionData.batteryCells > rules.maxBatteryCells
        msg = sprintf('BATTERY: %dS (%.1fV) exceeds SAE limit of %dS (%.1fV)', ...
            propulsionData.batteryCells, propulsionData.maxVoltage_V, ...
            rules.maxBatteryCells, rules.maxVoltage_V);
        report = addViolation(report, msg);
        fprintf('  ❌ %s\n', msg);
    else
        fprintf('  ✓  Battery:         %dS  (%.1fV max)   limit: %dS (%.1fV)\n', ...
            propulsionData.batteryCells, propulsionData.maxVoltage_V, ...
            rules.maxBatteryCells, rules.maxVoltage_V);
    end

    % Check 4: Thrust-to-weight
    if TW < rules.minThrustToWeight
        msg = sprintf('THRUST/WEIGHT: %.2f is below minimum %.2f — aircraft unlikely to take off', ...
            TW, rules.minThrustToWeight);
        report = addViolation(report, msg);
        fprintf('  ❌ %s\n', msg);
    else
        fprintf('  ✓  Thrust/Weight:   %.2f              minimum: %.2f\n', ...
            TW, rules.minThrustToWeight);
    end

    fprintf('\n');

    % =====================================================================
    %% ADVISORY CHECKS
    % =====================================================================
    fprintf('--- Design Reasonableness Checks ---\n');

    % Check 5: Wing loading
    wingLoading_lbft2 = (grossMass_kg/0.4536) / (wingArea_m2/0.0929);
    fprintf('  Wing loading:      %.2f kg/m²  (%.2f lb/ft²)\n', ...
        wingLoading_kgm2, wingLoading_lbft2);
    if wingLoading_kgm2 < 7.3 || wingLoading_kgm2 > 19.5
        msg = sprintf('Wing loading %.2f kg/m² outside typical SAE range (7.3–19.5 kg/m²)', ...
            wingLoading_kgm2);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
        fprintf('       Low = easy takeoff, poor cruise  |  High = good cruise, long takeoff roll\n');
    else
        fprintf('    ✓  Within typical range (7.3–19.5 kg/m²)\n');
    end

    % Check 6: Aspect ratio
    fprintf('  Aspect ratio:      %.2f\n', geometry.AR);
    if geometry.AR < 4 || geometry.AR > 10
        msg = sprintf('Aspect ratio %.2f outside typical range (4–10)', geometry.AR);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
        fprintf('       Low AR = compact/maneuverable  |  High AR = efficient, structurally demanding\n');
    else
        fprintf('    ✓  Within typical range (4–10)\n');
    end

    % Check 7: CG position
    fprintf('  CG position:       %.1f %%MAC\n', geometry.CG_percentMAC);
    if geometry.CG_percentMAC < 15 || geometry.CG_percentMAC > 35
        msg = sprintf('CG at %.1f%%MAC is outside typical range (15–35%%MAC)', ...
            geometry.CG_percentMAC);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
        fprintf('       Forward CG = stable but sluggish  |  Aft CG = agile but potentially unstable\n');
    else
        fprintf('    ✓  Within typical range (15–35%%MAC)\n');
    end

    % Check 8: CLmax
    fprintf('  CLmax:             %.3f\n', aeroData.CLmax);
    if aeroData.CLmax < 0.8 || aeroData.CLmax > 2.0
        msg = sprintf('CLmax %.3f is outside typical range (0.8–2.0)', aeroData.CLmax);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
    else
        fprintf('    ✓  Within typical range (0.8–2.0)\n');
    end

    % Check 9: CLalpha
    fprintf('  CLalpha:           %.4f /deg\n', aeroData.CLalpha_perDeg);
    if aeroData.CLalpha_perDeg < 0.05 || aeroData.CLalpha_perDeg > 0.15
        msg = sprintf('CLalpha %.4f /deg is outside typical range (0.05–0.15 /deg)', ...
            aeroData.CLalpha_perDeg);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
    else
        fprintf('    ✓  Within typical range (0.05–0.15 /deg)\n');
    end

    % Check 10: CD0
    fprintf('  CD0:               %.4f\n', aeroData.CD0);
    if aeroData.CD0 < 0.015 || aeroData.CD0 > 0.060
        msg = sprintf('CD0 %.4f is outside typical range (0.015–0.060)', aeroData.CD0);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
    else
        fprintf('    ✓  Within typical range (0.015–0.060)\n');
    end

    % Check 11: Alpha range — informational display + stall-capture check
    % The meaningful check (whether CLmax is at the boundary of the data)
    % is performed in extractAeroSummary and stored in aeroData.stallCaptured.
    fprintf('  Alpha range:       %.1f to %.1f deg\n', ...
        aeroData.elevatorData.Alpha(1), aeroData.elevatorData.Alpha(end));
    if isfield(aeroData, 'stallCaptured') && ~aeroData.stallCaptured
        msg = sprintf(['CLmax occurs at the last alpha point (%.1f deg) — ' ...
            'data may not capture full stall. Extend alpha range beyond %.1f deg.'], ...
            aeroData.elevatorData.Alpha(end), aeroData.elevatorData.Alpha(end));
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
    else
        fprintf('    ✓  CLmax found within alpha range — stall behaviour captured\n');
    end

    % Check 12: Propulsion table coverage
    maxThrottle = propulsionData.Throttle(end);
    fprintf('  Throttle range:    0 to %.0f%%\n', maxThrottle);
    if maxThrottle < 100
        msg = sprintf('Propulsion table only reaches %.0f%% throttle — extend to 100%%', maxThrottle);
        report = addWarning(report, msg);
        fprintf('    ⚠  %s\n', msg);
    else
        fprintf('    ✓  Full throttle range covered (0–100%%)\n');
    end

    fprintf('\n');

    % =====================================================================
    %% SUMMARY
    % =====================================================================
    fprintf('=======================================================\n');
    fprintf('  VALIDATION SUMMARY\n');
    fprintf('=======================================================\n\n');

    nViolations = length(report.violations);
    nWarnings   = length(report.warnings);

    if report.passed
        fprintf('  ✓  All critical SAE rules satisfied\n');
        if nWarnings == 0
            fprintf('  ✓  No advisory warnings\n');
        else
            fprintf('  ⚠  %d advisory warning(s) — review output above\n', nWarnings);
        end
        fprintf('\n  READY TO PROCEED\n');
        fprintf('  Next: run Initialization.mlx, then SimulationChallenge.slx\n');
    else
        fprintf('  ❌  %d critical violation(s) — CANNOT PROCEED TO SIMULATION\n\n', nViolations);
        for i = 1:nViolations
            fprintf('      %d. %s\n', i, report.violations{i});
        end
        fprintf('\n  Fix violations in your setup file and re-run.\n');
    end

    fprintf('\n');

    % ---- Store derived values for caller --------------------------------
    report.performance.AR               = geometry.AR;
    report.performance.wingLoading_kgm2 = wingLoading_kgm2;
    report.performance.TW               = TW;
    report.performance.maxThrust_N      = propulsionData.maxThrust_N;
end


% =========================================================================
function report = addViolation(report, msg)
    report.passed            = false;
    report.violations{end+1} = msg;
end

function report = addWarning(report, msg)
    report.warnings{end+1} = msg;
end
