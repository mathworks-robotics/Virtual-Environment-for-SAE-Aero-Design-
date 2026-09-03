% =========================================================================
% importPropulsionData.m
%
% SUPPORT FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% This file is part of the SUPPORT/ layer of the simulation framework.
% It is shared infrastructure used by both the Manual and DATCOM setup
% paths. Modifying it may break the import pipeline for all users.
%
% If you believe there is a bug or need a change, contact your team
% advisor or the MathWorks Aerospace Education Team.
% =========================================================================
%
% EXPECTED EXCEL TEMPLATE FORMAT (Aero_Prop_ManualData_Template.xlsx):
%   Row 1  — Sheet title                    (skipped)
%   Row 2  — Data source note               (skipped)
%   Row 3  — Long descriptive column names  (skipped)
%   Row 4  — Units                          (skipped)
%   Row 5  — Short MATLAB variable names    (used as struct field names)
%   Row 6+ — Numeric data
%
%   Column 1 : Breakpoint (independent variable, e.g. Throttle [%])
%   Column 2+: Output vectors (e.g. Thrust_Newtons, Power_Input, Amperage)
%
% =========================================================================

function propulsionData = importPropulsionData(filename, sheetName, propulsionData)
% IMPORTPROPULSIONDATA  Import propulsion performance table from Excel template
%
% Reads a propulsion sheet from the SAE Aero Design Manual Data Template
% and appends the imported lookup vectors to the propulsionData struct
% that was partially populated in the setup file (e.g. with batteryCells).
% All propulsion fields are kept together in a single struct.
%
% SYNTAX:
%   propulsionData = importPropulsionData(filename, sheetName, propulsionData)
%
% INPUTS:
%   filename       - char/string: path to Excel file
%                    e.g. 'Aero_Prop_ManualData_Template.xlsx'
%   sheetName      - char/string: name of the propulsion sheet
%                    e.g. 'Propulsion'
%   propulsionData - struct: pre-populated from setup file
%                    must contain .batteryCells at minimum
%
% OUTPUT:
%   propulsionData - input struct with additional fields added:
%       .BreakpointName   - Name of the breakpoint column (string)
%       .<BreakpointName> - Breakpoint vector, sorted ascending
%                           e.g. propulsionData.Throttle  [%]
%       .<OutputCol>      - One field per output column in the sheet
%                           e.g. propulsionData.Thrust_Newtons  [N]
%                               propulsionData.Power_Input      [W]
%                               propulsionData.Amperage         [A]
%       .RawData          - Original table (for inspection/debugging)
%
%   NOTE: .maxThrust_N and .maxVoltage_V are computed in the setup file
%   after this call, not here, to keep this function single-responsibility.
%
% SIMULINK USAGE (1-D Lookup Table block):
%   Breakpoints : propulsionData.Throttle
%   Table data  : propulsionData.Thrust_Newtons   (or any output column)
%
% EXAMPLE:
%   propulsionData.batteryCells = 4;
%   propulsionData = importPropulsionData('Aero_Prop_ManualData_Template.xlsx', ...
%                                         'Propulsion', propulsionData);

    % ---- Validate inputs ------------------------------------------------
    validateInputs(filename, sheetName, propulsionData);

    % ---- Read Excel -----------------------------------------------------
    % The original template stores short MATLAB-friendly names on row 5, but
    % exported motor data often has a compact table with headers higher in the
    % sheet. Detect the header row instead of hardcoding one layout.
    rawData = readPropulsionTable(filename, sheetName);

    % ---- Remove invalid rows --------------------------------------------
    % Two types of invalid rows can appear in the Excel template:
    %   1. Blank rows — all columns are NaN/missing (student may add these
    %      for readability, or they appear as the trailing blank row)
    %   2. Disclaimer text row — non-numeric content in the first column
    %      (e.g. "Replace example rows above with your motor/propeller data.")
    %
    % Strategy: remove rows where ALL columns are missing OR where the
    % first column is non-numeric/NaN. Warn if any bad rows were found
    % before the last valid data row (mid-table), since these likely
    % indicate accidental formatting that could affect the lookup table.
    firstColName = rawData.Properties.VariableNames{1};
    firstCol     = rawData.(firstColName);
    allMissing   = all(ismissing(rawData), 2);
    badRows      = allMissing | isnan(firstCol);

    % Warn if bad rows exist before the last good row (mid-table)
    lastGoodRow = find(~badRows, 1, 'last');
    if ~isempty(lastGoodRow) && any(badRows(1:lastGoodRow))
        warning('importPropulsionData:blankRowsFound', ...
            ['Blank or non-numeric rows found in sheet "%s" before the last data row. ' ...
             'These rows were skipped. Remove blank rows from your data table ' ...
             'to avoid unexpected results.'], sheetName);
    end

    rawData = rawData(~badRows, :);

    if width(rawData) < 2
        error('importPropulsionData:insufficientColumns', ...
            'Sheet "%s" must have at least 2 columns (1 breakpoint + 1 output).', ...
            sheetName);
    end

    % ---- Identify column roles ------------------------------------------
    colNames       = rawData.Properties.VariableNames;
    breakpointName = colNames{1};     % first column = independent variable
    outputNames    = colNames(2:end); % remaining columns = dependent variables

    % ---- Sort by breakpoint (required for Simulink lookup tables) -------
    rawData = sortrows(rawData, breakpointName);

    % ---- Append imported data to existing struct -----------------------
    propulsionData.BreakpointName   = breakpointName;
    propulsionData.(breakpointName) = rawData.(breakpointName);

    for i = 1:length(outputNames)
        propulsionData.(outputNames{i}) = rawData.(outputNames{i});
    end

    propulsionData.RawData = rawData;

    % ---- Confirmation message -------------------------------------------
    fprintf('importPropulsionData: loaded "%s" — breakpoint: %s (%d points), outputs: %s\n', ...
        sheetName, breakpointName, length(propulsionData.(breakpointName)), ...
        strjoin(outputNames, ', '));
end


% =========================================================================
function rawData = readPropulsionTable(filename, sheetName)
% Read a propulsion table by detecting the header row, then converting
% mixed Excel numeric/string/cell values to numeric columns.
    cells = readcell(filename, 'Sheet', sheetName);
    headerRow = findPropulsionHeaderRow(cells);
    if isempty(headerRow)
        error('importPropulsionData:headerMissing', ...
            'Could not find a propulsion table header row in sheet "%s".', sheetName);
    end

    header = cells(headerRow, :);
    lastHeaderCol = find(~cellfun(@isMissingCell, header), 1, 'last');
    header = header(1:lastHeaderCol);
    names = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(string(header)));

    dataCells = cells(headerRow + 1:end, 1:lastHeaderCol);
    data = NaN(size(dataCells));
    badMask = false(size(dataCells));
    for row = 1:size(dataCells, 1)
        for col = 1:size(dataCells, 2)
            [data(row, col), badMask(row, col)] = scalarCellToDouble(dataCells{row, col});
        end
    end

    if any(badMask(:))
        warning('importPropulsionData:nonnumericCells', ...
            'Sheet "%s" contains nonnumeric cells in the propulsion table; those entries were set to NaN.', ...
            sheetName);
    end

    rawData = array2table(data, 'VariableNames', cellstr(names));
end


function headerRow = findPropulsionHeaderRow(cells)
    headerRow = [];
    for row = 1:size(cells, 1)
        first = cells{row, 1};
        if isMissingCell(first) || ~(ischar(first) || isstring(first))
            continue
        end
        firstText = lower(strtrim(string(first)));
        if contains(firstText, "throttle")
            nonmissingHeaderCount = 0;
            for col = 1:size(cells, 2)
                if ~isMissingCell(cells{row, col})
                    nonmissingHeaderCount = nonmissingHeaderCount + 1;
                end
            end
            if nonmissingHeaderCount >= 2
                headerRow = row;
                return
            end
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
        text = strtrim(string(item));
        value = str2double(text);
        isBad = isnan(value) && strlength(text) > 0;
    else
        value = NaN;
        isBad = true;
    end
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
function validateInputs(filename, sheetName, propulsionData)
% Validate file, sheet, and incoming struct.

    if ~ischar(filename) && ~isstring(filename)
        error('importPropulsionData:badInput', 'filename must be a char or string.');
    end
    if ~isfile(filename)
        error('importPropulsionData:fileNotFound', 'File not found: %s', filename);
    end
    [~, ~, ext] = fileparts(filename);
    if ~ismember(lower(ext), {'.xlsx', '.xls', '.xlsm'})
        error('importPropulsionData:badExtension', ...
            'File must be an Excel file (.xlsx, .xls, or .xlsm). Got: %s', ext);
    end
    if ~ischar(sheetName) && ~isstring(sheetName)
        error('importPropulsionData:badInput', 'sheetName must be a char or string.');
    end
    [~, sheets] = xlsfinfo(filename);
    if ~ismember(sheetName, sheets)
        error('importPropulsionData:sheetMissing', ...
            'Sheet "%s" not found in %s.\nAvailable sheets: %s', ...
            sheetName, filename, strjoin(sheets, ', '));
    end
    if ~isstruct(propulsionData) || ~isfield(propulsionData, 'batteryCells')
        error('importPropulsionData:missingBatteryCells', ...
            'propulsionData.batteryCells must be set in the setup file before calling this function.');
    end
end
