% =========================================================================
% extractAeroSummary.m
%
% SUPPORT FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% This file is part of the SUPPORT/ layer of the simulation framework.
% It extracts scalar aerodynamic summary values from the imported lookup
% tables and stores them back into the aeroData struct.
%
% These scalars are used by validateDesign.m and analyzePerformance.m.
% They are always derived from the lookup tables — never entered manually —
% so they are guaranteed to stay in sync with the simulation data.
%
% If you believe there is a bug or need a change, contact your team
% advisor or the MathWorks Aerospace Education Team.
% =========================================================================
%
% EXTRACTED SCALARS (all at zero elevator deflection, beta = 0):
%
%   aeroData.CLmax          - Maximum lift coefficient                   [-]
%                             max(CL) at zero deflection, across all alpha
%
%   aeroData.stallCaptured  - logical: true if CLmax is in the interior of
%                             the alpha range (lift curve peaked within data)
%                             false if CLmax is at the last alpha point
%                             (data may not extend past stall)
%
%   aeroData.CD0            - Zero-lift drag coefficient                 [-]
%                             CD at zero deflection AND alpha = 0
%                             (total drag at zero lift — profile + viscous)
%
%   aeroData.CLalpha_perDeg - Lift curve slope                      [1/deg]
%                             mean dCL/dalpha at zero deflection
%
% INTERPOLATION POLICY:
%   Zero deflection — exact match used if present, otherwise linear
%   interpolation between the two nearest deflection values.
%   Alpha = 0 for CD0 — exact match used if present, otherwise linear
%   interpolation between the two nearest alpha values.
%
% =========================================================================

function aeroData = extractAeroSummary(aeroData)
% EXTRACTAEROSUMMARY  Derive scalar aero coefficients from imported tables
%
% SYNTAX:
%   aeroData = extractAeroSummary(aeroData)
%
% INPUT / OUTPUT:
%   aeroData - struct from setup file, with fields:
%                .elevatorData  (from importAeroData)
%                .rudderData
%                .aileronData
%              On return, three scalar fields are added:
%                .CLmax          [-]
%                .CD0            [-]
%                .CLalpha_perDeg [1/deg]

    % ---- Extract elevator table components ------------------------------
    deflections = aeroData.elevatorData.ControlDeflections;  % [nDefl x 1]
    alphaVec    = aeroData.elevatorData.Alpha;                % [nAlpha x 1]

    % Both import paths (importAeroData and importDatcomData) produce clean
    % 2D arrays [nDefl x nAlpha] — no third beta dimension.
    CL_2D = aeroData.elevatorData.CL;   % [nDefl x nAlpha]
    CD_2D = aeroData.elevatorData.CD;   % [nDefl x nAlpha]

    % ---- Step 1: get rows at zero elevator deflection -------------------
    CL_zeroDefl = interpolateAtZero(deflections, CL_2D);   % [1 x nAlpha]
    CD_zeroDefl = interpolateAtZero(deflections, CD_2D);   % [1 x nAlpha]

    % ---- CLmax and stall-capture check ---------------------------------
    % Maximum CL across the entire alpha sweep at zero deflection
    [aeroData.CLmax, CLmaxIdx] = max(CL_zeroDefl);

    % stallCaptured = true  if CLmax is in the interior of the alpha range
    % stallCaptured = false if CLmax is at the last alpha point, meaning the
    % lift curve is still rising at the table boundary — stall not captured
    aeroData.stallCaptured = (CLmaxIdx < length(alphaVec));
    if ~aeroData.stallCaptured
        fprintf(['extractAeroSummary: WARNING — CLmax occurs at the last alpha point ' ...
            '(%.1f deg). Consider extending your alpha range past stall.\n'], ...
            alphaVec(end));
    end

    % ---- CD0 ------------------------------------------------------------
    % Zero-lift drag: CD at zero deflection AND alpha = 0
    % Evaluated at zero elevator deflection AND alpha = 0
    aeroData.CD0 = interpolateAtAlphaZero(alphaVec, CD_zeroDefl);

    % ---- CLalpha [1/deg] ------------------------------------------------
    % Mean lift curve slope across the alpha sweep at zero deflection
    dCL    = diff(CL_zeroDefl);
    dAlpha = diff(alphaVec(:)');          % ensure row vector
    aeroData.CLalpha_perDeg = mean(dCL ./ dAlpha);

    fprintf(['extractAeroSummary: ' ...
             'CLmax = %.3f | CD0 (CD @ alpha=0) = %.4f | CLalpha = %.4f /deg\n'], ...
        aeroData.CLmax, aeroData.CD0, aeroData.CLalpha_perDeg);
end


% =========================================================================
function rowAtZero = interpolateAtZero(deflections, data2D)
% Extract or interpolate a [1 x nAlpha] row at elevator deflection = 0.
%
% INPUTS:
%   deflections - [nDefl x 1] sorted deflection breakpoints [deg]
%   data2D      - [nDefl x nAlpha] coefficient table
%
% OUTPUT:
%   rowAtZero   - [1 x nAlpha] values at zero deflection

    exactIdx = find(deflections == 0, 1);
    if ~isempty(exactIdx)
        rowAtZero = data2D(exactIdx, :);
        return;
    end

    % Linear interpolation between bracketing deflections
    lowerIdx = find(deflections < 0, 1, 'last');
    upperIdx = find(deflections > 0, 1, 'first');

    if isempty(lowerIdx) || isempty(upperIdx)
        error('extractAeroSummary:noZeroBracket', ...
            ['Cannot interpolate to zero deflection — table deflections are [%s].\n' ...
             'Add a zero-deflection row to your Excel template.'], ...
            num2str(deflections', '%.1f '));
    end

    d_lo = deflections(lowerIdx);
    d_hi = deflections(upperIdx);
    w    = (0 - d_lo) / (d_hi - d_lo);
    rowAtZero = (1 - w) * data2D(lowerIdx, :) + w * data2D(upperIdx, :);

    fprintf(['extractAeroSummary: zero deflection not in table — ' ...
             'interpolated from %.1f and %.1f deg\n'], d_lo, d_hi);
end


% =========================================================================
function valueAtZero = interpolateAtAlphaZero(alphaVec, rowData)
% Extract or interpolate a scalar value at alpha = 0 from a [1 x nAlpha] row.
%
% INPUTS:
%   alphaVec - [nAlpha x 1] sorted alpha breakpoints [deg]
%   rowData  - [1 x nAlpha] coefficient values (already at zero deflection)
%
% OUTPUT:
%   valueAtZero - scalar value at alpha = 0

    exactIdx = find(alphaVec == 0, 1);
    if ~isempty(exactIdx)
        valueAtZero = rowData(exactIdx);
        return;
    end

    % Linear interpolation between bracketing alpha values
    lowerIdx = find(alphaVec < 0, 1, 'last');
    upperIdx = find(alphaVec > 0, 1, 'first');

    if isempty(lowerIdx) || isempty(upperIdx)
        error('extractAeroSummary:noAlphaZeroBracket', ...
            ['Cannot interpolate CD0 to alpha = 0 — alpha values are [%s].\n' ...
             'Add an alpha = 0 row to your Excel template.'], ...
            num2str(alphaVec', '%.1f '));
    end

    a_lo = alphaVec(lowerIdx);
    a_hi = alphaVec(upperIdx);
    w    = (0 - a_lo) / (a_hi - a_lo);
    valueAtZero = (1 - w) * rowData(lowerIdx) + w * rowData(upperIdx);

    fprintf(['extractAeroSummary: alpha = 0 not in table — ' ...
             'CD0 interpolated from alpha = %.1f and %.1f deg\n'], a_lo, a_hi);
end
