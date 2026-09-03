% =========================================================================
% importAeroData.m
%
% SUPPORT FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% Single function that handles all four aerodynamic data sheets:
%
%   importAeroData(file, 'Elevator')               → 3-D arrays + CLde, Cmde
%   importAeroData(file, 'Rudder')                 → 3-D arrays + CYdr, Cndr
%   importAeroData(file, 'Aileron')                → 3-D arrays + Clda, Cnda
%   importAeroData(file, 'StabilityDerivatives')   → flat scalar struct
%
% Called in Section 3 of setupData_Manual.m.
%
% =========================================================================
%
% EXCEL SHEET LAYOUT  (Elevator / Aileron):
%   Row 1–4 : Title, notes, column descriptions, units  (skipped)
%   Row 5   : Short MATLAB variable names  (used as struct field names)
%   Row 6+  : Numeric data
%   Col 1   : Control deflection [deg]   ← sweep axis
%   Col 2   : alpha              [deg]   ← sweep axis
%   Col 3   : Beta               [deg]     (single value = 0, ignored)
%   Col 4+  : Aerodynamic coefficients (CL, CD, Cm, Cl ...)
%   Output  : data.<Coeff>  is  [nDefl × nAlpha]   (clean 2-D)
%
% EXCEL SHEET LAYOUT  (Rudder) — DIFFERENT SWEEP AXIS:
%   Col 1   : Rudder deflection  [deg]   ← sweep axis
%   Col 2   : alpha              [deg]     (single value = 0, ignored)
%   Col 3   : Beta               [deg]   ← sweep axis
%   Col 4+  : CY, Cn, Cl, CL, CD, Cm
%   Output  : data.<Coeff>  is  [nDefl × nBeta]    (clean 2-D)
%
%   WHY: Rudder generates side force (CY) and yaw moment (Cn) as a
%   function of SIDESLIP (beta), not AoA. The XFLR5 source is a
%   Type 2 beta-sweep at fixed alpha=0.
%
% STABILITYDERIVATIVES SHEET:
%   Row 5   : Headers  Derivative | Value
%   Row 6+  : One derivative per row
%   Col A   : Derivative name  (case-sensitive, must match exactly)
%   Col B   : Numeric value
%   Section-header rows (non-numeric Value) are automatically skipped.
%
% =========================================================================

function data = importAeroData(filename, sheetName)
% IMPORTAERODATA  Import aerodynamic data from the Excel template.
%
% SYNTAX:
%   data = importAeroData(filename, sheetName)
%
% OUTPUT — Elevator / Aileron:
%   .ControlSurface      string
%   .ControlDeflections  [nDefl × 1]    deg
%   .Alpha               [nAlpha × 1]   deg   sweep axis
%   .Beta                0              deg   scalar (not swept)
%   .<CoeffName>         [nDefl × nAlpha]     clean 2-D table
%   .RawData             original table (debug)
%   .CLde_perDeg, .Cmde_perDeg  (Elevator only)
%   .Clda_perDeg, .Cnda_perDeg  (Aileron only)
%
% OUTPUT — Rudder:
%   .ControlSurface      'Rudder'
%   .ControlDeflections  [nDefl × 1]    deg
%   .Beta                [nBeta × 1]    deg   sweep axis
%   .Alpha               0              deg   scalar (not swept)
%   .<CoeffName>         [nDefl × nBeta]      clean 2-D table
%   .RawData             original table (debug)
%   .CYdr_perDeg, .Cndr_perDeg
%
% OUTPUT — StabilityDerivatives:
%   Flat scalar struct. Fields: Cxu Cxa Czu CLa CLq Cmu Cma Cmq
%                               CYb CYp CYr Clb Clp Clr Cnb Cnp Cnr
%                               NeutralPoint_m
%                               pitchStable yawStable rollStable
%
% SIMULINK LUT DIMENSION ORDER:
%   Elevator/Aileron — Dim 1: deflection,  Dim 2: alpha
%   Rudder           — Dim 1: deflection,  Dim 2: beta

    % Route StabilityDerivatives separately
    if strcmp(sheetName, 'StabilityDerivatives')
        data = readStabilityDerivatives(filename);
        return
    end

    validateAeroInputs(filename, sheetName);

    % Route to correct importer — rudder uses a 2-D (dr × beta) table,
    % elevator and aileron use a 2-D (deflection × alpha) table.
    if strcmp(sheetName, 'Rudder')
        data = importRudderSheet(filename);
    else
        data = importElevAilSheet(filename, sheetName);
    end
end


% =========================================================================
%  ELEVATOR / AILERON IMPORTER  —  2-D table: [nDefl × nAlpha]
%  Beta column is constant (= 0) and is ignored after stripping bad rows.
%  Output struct fields include .Alpha breakpoints, .Beta = 0 (scalar).
% =========================================================================
function data = importElevAilSheet(filename, sheetName)

    rawData = readCleanTable(filename, sheetName);

    controlColName     = rawData.Properties.VariableNames{1};
    controlDeflections = unique(rawData.(controlColName), 'sorted');
    alphaValues        = unique(rawData.alpha,            'sorted');

    nControl = length(controlDeflections);
    nAlpha   = length(alphaValues);

    paramNames = coeffColumns(rawData, controlColName);

    % Pre-allocate 2-D arrays [nDefl × nAlpha]
    dataArrays = struct();
    for i = 1:length(paramNames)
        dataArrays.(paramNames{i}) = zeros(nControl, nAlpha);
    end

    for i = 1:height(rawData)
        iCtrl  = controlDeflections == rawData.(controlColName)(i);
        iAlpha = alphaValues        == rawData.alpha(i);
        for j = 1:length(paramNames)
            p = paramNames{j};
            dataArrays.(p)(iCtrl, iAlpha) = rawData.(p)(i);
        end
    end

    data.ControlSurface     = sheetName;
    data.ControlDeflections = controlDeflections;   % [nDefl × 1]
    data.Alpha              = alphaValues;           % [nAlpha × 1]
    data.Beta               = 0;                    % scalar — not a sweep axis
    for i = 1:length(paramNames)
        data.(paramNames{i}) = dataArrays.(paramNames{i});  % [nDefl × nAlpha]
    end
    data.RawData = rawData;

    fprintf('importAeroData: %s loaded — %d deflections × %d alpha\n', ...
        sheetName, nControl, nAlpha);

    data = appendControlDerivatives(data, sheetName);
end


% =========================================================================
%  RUDDER IMPORTER  —  2-D table: [nDefl × nBeta]
%  Alpha column is constant (= 0) and is ignored.
%  CY and Cn are functions of sideslip (beta), not AoA — XFLR5 Type 2 sweep.
%  Output struct fields include .Beta breakpoints, .Alpha = 0 (scalar).
% =========================================================================
function data = importRudderSheet(filename)

    rawData = readCleanTable(filename, 'Rudder');

    controlColName     = rawData.Properties.VariableNames{1};   % 'Rudder'
    controlDeflections = unique(rawData.(controlColName), 'sorted');
    betaValues         = unique(rawData.Beta,              'sorted');

    nControl = length(controlDeflections);
    nBeta    = length(betaValues);

    paramNames = coeffColumns(rawData, controlColName);

    % Pre-allocate 2-D arrays [nDefl × nBeta]
    dataArrays = struct();
    for i = 1:length(paramNames)
        dataArrays.(paramNames{i}) = zeros(nControl, nBeta);
    end

    for i = 1:height(rawData)
        iCtrl = controlDeflections == rawData.(controlColName)(i);
        iBeta = betaValues         == rawData.Beta(i);
        for j = 1:length(paramNames)
            p = paramNames{j};
            dataArrays.(p)(iCtrl, iBeta) = rawData.(p)(i);
        end
    end

    data.ControlSurface     = 'Rudder';
    data.ControlDeflections = controlDeflections;   % [nDefl × 1]
    data.Beta               = betaValues;           % [nBeta × 1]  ← sweep axis
    data.Alpha              = 0;                    % scalar — not a sweep axis
    for i = 1:length(paramNames)
        data.(paramNames{i}) = dataArrays.(paramNames{i});  % [nDefl × nBeta]
    end
    data.RawData = rawData;

    fprintf('importAeroData: Rudder loaded — %d deflections × %d beta\n', ...
        nControl, nBeta);

    data = appendControlDerivatives(data, 'Rudder');
end


% =========================================================================
%  SHARED HELPERS
% =========================================================================

function rawData = readCleanTable(filename, sheetName)
% Read one sheet and strip blank / non-numeric rows.
    opts = detectImportOptions(filename, 'Sheet', sheetName);
    opts.VariableNamesRange = 'A5';
    opts.DataRange          = 'A6';
    opts.VariableNamingRule = 'preserve';
    rawData = readtable(filename, opts);
    rawData = normalizeNumericTable(rawData, sheetName);

    firstColName = rawData.Properties.VariableNames{1};
    firstCol     = rawData.(firstColName);
    badRows      = all(ismissing(rawData), 2) | isnan(firstCol);

    lastGoodRow = find(~badRows, 1, 'last');
    if ~isempty(lastGoodRow) && any(badRows(1:lastGoodRow))
        warning('importAeroData:blankRowsFound', ...
            'Blank or non-numeric rows found mid-table in sheet "%s" — skipped.', ...
            sheetName);
    end
    rawData = rawData(~badRows, :);
    rawData = dropEmptyCoefficientColumns(rawData, firstColName, sheetName);
end


function paramNames = coeffColumns(rawData, controlColName)
% Return coefficient column names (everything except deflection, alpha, Beta).
    allCols  = rawData.Properties.VariableNames;
    excl     = {controlColName, 'alpha', 'Beta'};
    paramNames = setdiff(allCols, excl, 'stable');
end


function rawData = normalizeNumericTable(rawData, sheetName)
% Convert mixed Excel numeric/string/cell columns to double vectors.
% Student-edited workbooks and exported tool data often contain optional
% blank columns that MATLAB imports as cells. Keep numeric values, convert
% empty cells to NaN, then remove empty coefficient columns later.
    for i = 1:width(rawData)
        values = rawData.(i);
        if isnumeric(values)
            rawData.(i) = double(values);
        else
            [numericValues, badMask] = toNumericVector(values);
            if any(badMask)
                warning('importAeroData:nonnumericCells', ...
                    'Sheet "%s", column "%s" contains nonnumeric cells; those entries were set to NaN.', ...
                    sheetName, rawData.Properties.VariableNames{i});
            end
            rawData.(i) = numericValues;
        end
    end
end


function rawData = dropEmptyCoefficientColumns(rawData, controlColName, sheetName)
% Drop coefficient columns that are entirely blank/NaN. These are commonly
% optional outputs such as CDi/CDv/XCP from aero tools and are not used by
% the force/moment model unless populated.
    names = rawData.Properties.VariableNames;
    protected = ismember(names, {controlColName, 'alpha', 'Beta'});
    keep = true(1, width(rawData));
    for i = 1:width(rawData)
        if ~protected(i) && all(isnan(rawData.(i)))
            keep(i) = false;
        end
    end
    dropped = names(~keep);
    if ~isempty(dropped)
        warning('importAeroData:emptyCoeffColumnsDropped', ...
            'Sheet "%s" ignored empty coefficient columns: %s.', ...
            sheetName, strjoin(dropped, ', '));
    end
    rawData = rawData(:, keep);
end


function [numericValues, badMask] = toNumericVector(values)
% Convert a table variable to a double column and mark truly nonnumeric cells.
    if isnumeric(values)
        numericValues = double(values(:));
        badMask = false(size(numericValues));
        return
    end

    if iscell(values)
        numericValues = NaN(numel(values), 1);
        badMask = false(numel(values), 1);
        for k = 1:numel(values)
            item = values{k};
            if isMissingCell(item)
                numericValues(k) = NaN;
            elseif isnumeric(item) && isscalar(item)
                numericValues(k) = double(item);
            elseif ischar(item) || isstring(item)
                text = normalizeNumericText(item);
                parsed = str2double(text);
                numericValues(k) = parsed;
                badMask(k) = isnan(parsed) && strlength(text) > 0;
            else
                numericValues(k) = NaN;
                badMask(k) = true;
            end
        end
        return
    end

    if isstring(values) || ischar(values)
        textValues = normalizeNumericText(values(:));
        numericValues = str2double(textValues);
        badMask = isnan(numericValues) & strlength(textValues) > 0;
        return
    end

    numericValues = NaN(numel(values), 1);
    badMask = true(size(numericValues));
end


function text = normalizeNumericText(rawText)
% Accept common formatted minus signs from spreadsheets and copied reports.
    text = strtrim(string(rawText));
    text = replace(text, char(8722), '-'); % Unicode minus
    text = replace(text, char(8211), '-'); % en dash
    text = replace(text, char(8212), '-'); % em dash
    text = replace(text, char(8209), '-'); % nonbreaking hyphen
    text = replace(text, char(160),  '');  % nonbreaking space
    text = replace(text, char(8239), '');  % narrow nonbreaking space
end


function tf = isMissingCell(item)
    tf = isempty(item);
    if tf
        return
    end
    try
        tf = any(ismissing(item), 'all');
    catch
        tf = false;
    end
end


% =========================================================================
%  STABILITY DERIVATIVES READER
% =========================================================================

function data = readStabilityDerivatives(filename)
% Reads the StabilityDerivatives sheet and returns a flat scalar struct.
% Expects two columns: Derivative (col A) | Value (col B).
% Row 5 = headers, Row 6+ = data. Non-numeric Value rows are skipped.

    validateStabInputs(filename);

    raw = readStabilityDerivativeCells(filename);

    % Drop fully blank name rows. Blank derivative values are retained and
    % defaulted in getVal so the setup remains explicit about unmodeled
    % derivatives.
    raw = raw(~cellfun(@isempty, raw.Derivative), :);

    % Build name → value lookup
    derivMap = containers.Map(raw.Derivative, num2cell(raw.Value));

    % ── Longitudinal ─────────────────────────────────────────────────────
    data.Cxu = getVal(derivMap, 'Cxu');
    data.Cxa = getVal(derivMap, 'Cxa');
    data.Czu = getVal(derivMap, 'Czu');
    data.CLa = getVal(derivMap, 'CLa');
    data.CLq = getVal(derivMap, 'CLq');
    data.Cmu = getVal(derivMap, 'Cmu');
    data.Cma = getVal(derivMap, 'Cma');
    data.Cmq = getVal(derivMap, 'Cmq');

    % ── Lateral ──────────────────────────────────────────────────────────
    data.CYb = getVal(derivMap, 'CYb');
    data.CYp = getVal(derivMap, 'CYp');
    data.CYr = getVal(derivMap, 'CYr');
    data.Clb = getVal(derivMap, 'Clb');
    data.Clp = getVal(derivMap, 'Clp');
    data.Clr = getVal(derivMap, 'Clr');
    data.Cnb = getVal(derivMap, 'Cnb');
    data.Cnp = getVal(derivMap, 'Cnp');
    data.Cnr = getVal(derivMap, 'Cnr');

    % ── Geometry / additional ─────────────────────────────────────────────
    data.NeutralPoint_m = getVal(derivMap, 'NeutralPoint_m');

    % ── Stability flags ───────────────────────────────────────────────────
    data.pitchStable = data.Cma < 0;   % nose-down restoring
    data.yawStable   = data.Cnb > 0;   % weathercock
    data.rollStable  = data.Clb < 0;   % dihedral effect

    printStabSummary(data);
end


function raw = readStabilityDerivativeCells(filename)
% Read derivative/value pairs from either the template row layout or a
% compact exported table with the header near the top of the sheet.
    cells = readcell(filename, 'Sheet', 'StabilityDerivatives');
    headerRow = findHeaderRow(cells, 'Derivative', 'Value');
    if isempty(headerRow)
        error('importAeroData:stabilityHeaderMissing', ...
            'Could not find "Derivative" and "Value" headers in StabilityDerivatives sheet.');
    end

    names = cells(headerRow + 1:end, 1);
    values = cells(headerRow + 1:end, 2);
    derivative = strings(numel(names), 1);
    numericValues = NaN(numel(values), 1);

    for i = 1:numel(names)
        if isMissingCell(names{i})
            derivative(i) = "";
        else
            derivative(i) = strtrim(string(names{i}));
        end

        [value, isBad] = scalarCellToDouble(values{i});
        if isBad && strlength(derivative(i)) > 0
            warning('importAeroData:badStabilityValue', ...
                'Stability derivative "%s" has a nonnumeric value and was set to NaN.', ...
                derivative(i));
        end
        numericValues(i) = value;
    end

    keep = derivative ~= "";
    raw = table(cellstr(derivative(keep)), numericValues(keep), ...
        'VariableNames', {'Derivative', 'Value'});
end


function headerRow = findHeaderRow(cells, firstHeader, secondHeader)
    headerRow = [];
    for i = 1:size(cells, 1)
        if size(cells, 2) < 2
            return
        end
        first = string(cells{i, 1});
        second = string(cells{i, 2});
        if strcmpi(strtrim(first), firstHeader) && strcmpi(strtrim(second), secondHeader)
            headerRow = i;
            return
        end
    end
end


function [value, isBad] = scalarCellToDouble(item)
    isBad = false;
    if isMissingCell(item)
        value = NaN;
    elseif isnumeric(item) && isscalar(item)
        value = double(item);
    elseif ischar(item) || isstring(item)
        text = normalizeNumericText(item);
        value = str2double(text);
        isBad = isnan(value) && strlength(text) > 0;
    else
        value = NaN;
        isBad = true;
    end
end


% =========================================================================
%  CONTROL EFFECTIVENESS SCALARS
%  polyfit slope of coefficient vs deflection at alpha≈0, beta≈0.
%  For Rudder: iA0=1 (only alpha value), iB0 = index of beta=0.
% =========================================================================

function data = appendControlDerivatives(data, sheetName)
% Slope of coefficient vs deflection at the reference condition.
%   Elevator/Aileron: at alpha closest to 0°
%   Rudder:           at beta  closest to 0°
% All tables are now 2-D, so indexing is [nDefl × nRef] with no squeeze needed.

    defl = data.ControlDeflections;

    switch sheetName
        case 'Elevator'
            [~, iA0] = min(abs(data.Alpha));
            fprintf('  Elevator derivatives at alpha=%.1f°:\n', data.Alpha(iA0));
            data.CLde_perDeg = computeSlope(defl, data.CL(:, iA0), 'CLde');
            data.Cmde_perDeg = computeSlope(defl, data.Cm(:, iA0), 'Cmde');

        case 'Rudder'
            [~, iB0] = min(abs(data.Beta));
            fprintf('  Rudder derivatives at beta=%.1f°:\n', data.Beta(iB0));
            data.CYdr_perDeg = computeSlope(defl, data.CY(:, iB0), 'CYdr');
            data.Cndr_perDeg = computeSlope(defl, data.Cn(:, iB0), 'Cndr');

        case 'Aileron'
            [~, iA0] = min(abs(data.Alpha));
            fprintf('  Aileron derivatives at alpha=%.1f°:\n', data.Alpha(iA0));
            data.Clda_perDeg = computeSlope(defl, data.Cl(:, iA0), 'Clda');
            data.Cnda_perDeg = computeSlope(defl, data.Cn(:, iA0), 'Cnda');
    end
end


function slope = computeSlope(x, y, label)
% Linear regression slope via polyfit — more robust than 2-point finite diff.
    x = x(:); y = y(:);
    p     = polyfit(x, y, 1);
    slope = p(1);
    fprintf('    %s = %+.5f /deg  (%d points, %.0f° to %.0f°)\n', ...
        label, slope, length(x), min(x), max(x));
end


% =========================================================================
%  PLOT HELPER
%  Quick visualisation of one coefficient from any sheet.
%  Elevator/Aileron: plots vs alpha (one line per deflection).
%  Rudder:           plots vs beta  (one line per deflection).
%
%  USAGE:
%    plotAeroData(elevData, 'CL')
%    plotAeroData(elevData, 'Cm', 'Beta', 0)
%    plotAeroData(rudData,  'CY')     % auto-detects beta sweep
%    plotAeroData(rudData,  'Cn')
% =========================================================================

function plotAeroData(data, parameter, varargin) %#ok<DEFNU>
% PLOTAERODATA  Quick plot of one coefficient from any aero sheet.
%
%   Elevator/Aileron: coefficient [nDefl × nAlpha] plotted vs alpha.
%   Rudder:           coefficient [nDefl × nBeta]  plotted vs beta.
%
% USAGE:
%   plotAeroData(elevData, 'CL')
%   plotAeroData(elevData, 'Cm')
%   plotAeroData(rudData,  'CY')
%   plotAeroData(rudData,  'Cn')

    isRudder = strcmp(data.ControlSurface, 'Rudder');

    if isRudder
        % Rudder: [nDefl × nBeta] — plot vs beta directly, no squeeze needed
        xData    = data.Beta;
        xLabel   = 'Sideslip Angle \beta (deg)';
        plotData = data.(parameter);   % [nDefl × nBeta]
        titleStr = sprintf('%s vs \\beta', parameter);
    else
        % Elevator/Aileron: [nDefl × nAlpha] — plot vs alpha directly
        xData    = data.Alpha;
        xLabel   = 'Angle of Attack \alpha (deg)';
        plotData = data.(parameter);   % [nDefl × nAlpha]
        titleStr = sprintf('%s vs \\alpha', parameter);
    end

    figure('Name', sprintf('%s — %s', data.ControlSurface, parameter));
    hold on; grid on;
    colors = lines(length(data.ControlDeflections));

    for i = 1:length(data.ControlDeflections)
        plot(xData, plotData(i, :), '-o', ...
            'LineWidth', 1.5, 'Color', colors(i, :), ...
            'MarkerSize', 4,  'MarkerFaceColor', colors(i, :));
    end

    legendEntries = arrayfun( ...
        @(d) sprintf('%s = %.0f°', data.ControlSurface, d), ...
        data.ControlDeflections, 'UniformOutput', false);

    legend(legendEntries, 'Location', 'best', 'FontSize', 9);
    xlabel(xLabel,  'FontSize', 11);
    ylabel(parameter, 'FontSize', 11);
    title(titleStr, 'FontSize', 12, 'FontWeight', 'bold');
    hold off;
end


% =========================================================================
%  VALIDATION
% =========================================================================

function validateAeroInputs(filename, sheetName)
    if ~ischar(filename) && ~isstring(filename)
        error('importAeroData:badInput', 'filename must be a char or string.');
    end
    if ~isfile(filename)
        error('importAeroData:fileNotFound', 'File not found: %s', filename);
    end
    [~, ~, ext] = fileparts(filename);
    if ~ismember(lower(ext), {'.xlsx', '.xls', '.xlsm'})
        error('importAeroData:badExtension', ...
            'File must be .xlsx, .xls, or .xlsm. Got: %s', ext);
    end
    if ~ischar(sheetName) && ~isstring(sheetName)
        error('importAeroData:badInput', 'sheetName must be a char or string.');
    end
    validSheets = {'Elevator', 'Rudder', 'Aileron', 'StabilityDerivatives'};
    if ~ismember(sheetName, validSheets)
        error('importAeroData:badSheet', ...
            'sheetName must be one of: %s', strjoin(validSheets, ', '));
    end
    [~, sheets] = xlsfinfo(filename);
    if ~ismember(sheetName, sheets)
        error('importAeroData:sheetMissing', ...
            'Sheet "%s" not found in %s.\nAvailable: %s', ...
            sheetName, filename, strjoin(sheets, ', '));
    end
end


function validateStabInputs(filename)
    if ~ischar(filename) && ~isstring(filename)
        error('importAeroData:badInput', 'filename must be a char or string.');
    end
    if ~isfile(filename)
        error('importAeroData:fileNotFound', 'File not found: %s', filename);
    end
    [~, sheets] = xlsfinfo(filename);
    if ~ismember('StabilityDerivatives', sheets)
        error('importAeroData:sheetMissing', ...
            ['Sheet "StabilityDerivatives" not found in %s.\n' ...
             'Add this sheet and fill in the derivative values.'], filename);
    end
end


function val = getVal(derivMap, name)
% Fetch one derivative by name. A blank/missing entry means the derivative
% is unavailable in the source data, so use zero and report that assumption.
    if derivMap.isKey(name)
        val = derivMap(name);
        if isnan(val)
            warning('importAeroData:blankDerivativeDefaulted', ...
                'Derivative "%s" is blank; using 0.0 so this derivative is explicitly unmodeled.', ...
                name);
            val = 0;
        end
    else
        warning('importAeroData:missingDerivativeDefaulted', ...
            ['Derivative "%s" not found in StabilityDerivatives sheet. ' ...
             'Using 0.0 so this derivative is explicitly unmodeled.'], name);
        val = 0;
    end
end


% =========================================================================
%  DISPLAY
% =========================================================================

function printStabSummary(s)
    fprintf('\n--- Stability Derivatives loaded -----------------------------------\n');
    fprintf('  Neutral point   %.4f m\n\n', s.NeutralPoint_m);
    fprintf('  Longitudinal:\n');
    fprintf('    CLa  = %+8.4f    CLq  = %+8.4f\n', s.CLa, s.CLq);
    fprintf('    Cma  = %+8.4f    Cmq  = %+8.4f\n', s.Cma, s.Cmq);
    fprintf('    Cxu  = %+8.5f    Cxa  = %+8.4f\n', s.Cxu, s.Cxa);
    fprintf('    Czu  = %+8.6f    Cmu  = %+8.6f\n', s.Czu, s.Cmu);
    fprintf('  Lateral:\n');
    fprintf('    CYb  = %+8.4f    CYp  = %+8.5f    CYr = %+8.5f\n', s.CYb, s.CYp, s.CYr);
    fprintf('    Clb  = %+8.5f    Clp  = %+8.5f    Clr = %+8.5f\n', s.Clb, s.Clp, s.Clr);
    fprintf('    Cnb  = %+8.4f    Cnp  = %+8.5f    Cnr = %+8.5f\n', s.Cnb, s.Cnp, s.Cnr);
    fprintf('  Flags  —  Pitch: %s   Yaw: %s   Roll: %s\n', ...
        flagStr(s.pitchStable), flagStr(s.yawStable), flagStr(s.rollStable));
    fprintf('--------------------------------------------------------------------\n\n');
end

function s = flagStr(flag)
    if flag, s = 'STABLE'; else, s = 'UNSTABLE'; end
end
