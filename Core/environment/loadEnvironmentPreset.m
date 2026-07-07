% =========================================================================
% loadEnvironmentPreset.m
%
% CORE FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% Called automatically from the Environment subsystem mask Initialization
% callback when the student changes the environment dropdown.
%
% Reads the selected preset from the corresponding source .sldd file and
% overwrites all entries in environmentMaster.sldd.
%
% HOW THIS IS CALLED (mask Initialization tab):
%   loadEnvironmentPreset(envPreset);
%
% PREREQUISITES:
%   - createMasterDictionary.m must have been run once
%   - buildEnvironmentDictionaries.m must have been run once
%     (source .sldd files must exist in environments/ folder)
%
% =========================================================================

function loadEnvironmentPreset(presetNumber)

    MASTER_PATH = fullfile('Core\environment', 'environmentMaster.sldd');

    DICT_NAMES = { ...
        'env_01_SeaLevelStandard', ...
        'env_02_CompetitionWest_VanNuys', ...
        'env_03_CompetitionEast_Lakeland', ...
        'env_04_CompetitionEast_FortWorth', ...
        'env_05_ColdWindyDay', ...
        'env_06_HotDay', ...
        'env_07_AfternoonGusts', ...
        'env_08_HighDensityAltitude'};

    % ── Validate input ────────────────────────────────────────────────────
    if ~isnumeric(presetNumber) || presetNumber < 1 || presetNumber > 8
        error('loadEnvironmentPreset:badInput', ...
            'presetNumber must be an integer 1–8.');
    end
    presetNumber = round(presetNumber);

    % ── Check master exists ───────────────────────────────────────────────
    if ~exist(MASTER_PATH, 'file')
        error('loadEnvironmentPreset:noMaster', ...
            ['environmentMaster.sldd not found at: %s\n' ...
             'Run createMasterDictionary() first.'], MASTER_PATH);
    end

    % ── Check source dictionary exists ────────────────────────────────────
    srcPath = fullfile('Core\environment', [DICT_NAMES{presetNumber} '.sldd']);
    if ~exist(srcPath, 'file')
        error('loadEnvironmentPreset:noSource', ...
            ['Source dictionary not found: %s\n' ...
             'Run buildEnvironmentDictionaries() first.'], srcPath);
    end

    % ── Open master and source dictionaries ───────────────────────────────
    master    = Simulink.data.dictionary.open(MASTER_PATH);
    masterSec = getSection(master, 'Design Data');

    src    = Simulink.data.dictionary.open(srcPath);
    srcSec = getSection(src, 'Design Data');

    % ── Copy all entries from source → master ─────────────────────────────
    allEntries = find(srcSec);

    for k = 1:numel(allEntries)
        entryName = allEntries(k).Name;
        srcObj    = getValue(allEntries(k));

        % Extract raw value from Simulink.Parameter wrapper
        if isa(srcObj, 'Simulink.Parameter')
            rawVal = double(srcObj.Value);
        else
            rawVal = double(srcObj);
        end

        % Write into master — add if missing, update if present
        addOrUpdateEntry(masterSec, entryName, rawVal);
    end

    % ── Save master, close both ───────────────────────────────────────────
    saveChanges(master);
    master.close();
    src.close();

    fprintf('Environment loaded: Preset %d — %s\n', ...
        presetNumber, DICT_NAMES{presetNumber});
end


% =========================================================================
%% addOrUpdateEntry  (local copy — mirrors createMasterDictionary.m)
% =========================================================================
% Add a new entry or update an existing one in a dictionary section.
% Always stores values as double to avoid type mismatch errors.
% =========================================================================

function addOrUpdateEntry(sec, name, value)

    value = double(value);

    try
        % Entry exists — update value
        entry    = getEntry(sec, name);
        paramObj = getValue(entry);

        if isa(paramObj, 'Simulink.Parameter')
            paramObj.Value = value;
            setValue(entry, paramObj);
        else
            deleteEntry(sec, name);
            p = Simulink.Parameter(value);
            addEntry(sec, name, p);
        end

    catch
        % Entry missing — create fresh
        p = Simulink.Parameter(value);
        addEntry(sec, name, p);
    end
end
