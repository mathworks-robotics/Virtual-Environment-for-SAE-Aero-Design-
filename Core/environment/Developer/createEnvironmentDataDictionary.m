function dictionaryPath = createEnvironmentDataDictionary(outputFolder)
%CREATEENVIRONMENTDATADICTIONARY Build the environment data dictionary.
%   DICTIONARYPATH = CREATEENVIRONMENTDATADICTIONARY() creates or updates
%   environmentData.sldd beside environmentLibrary.m. The dictionary stores
%   all eight environment presets and selects preset 1 by default.

    if nargin < 1 || strlength(string(outputFolder)) == 0
        outputFolder = fileparts(mfilename('fullpath'));
    end

    outputFolder = char(outputFolder);
    if ~isfolder(outputFolder)
        error('createEnvironmentDataDictionary:FolderNotFound', ...
            'Output folder does not exist: %s', outputFolder);
    end

    envCatalog = environmentLibrary(1);
    envCatalog(8) = envCatalog;
    for presetNumber = 2:8
        envCatalog(presetNumber) = environmentLibrary(presetNumber);
    end
    envPreset = 1;

    dictionaryPath = fullfile(outputFolder, 'environmentData.sldd');
    if isfile(dictionaryPath)
        dictionary = Simulink.data.dictionary.open(dictionaryPath);
    else
        dictionary = Simulink.data.dictionary.create(dictionaryPath);
    end
    dictionaryCleanup = onCleanup(@() close(dictionary));

    designData = getSection(dictionary, 'Design Data');
    upsertEntry(designData, 'envCatalog', envCatalog);
    upsertEntry(designData, 'envPreset', envPreset);
    saveChanges(dictionary);

    fprintf('Environment dictionary updated: %s\n', dictionaryPath);
end

function upsertEntry(section, name, value)
    if exist(section, name)
        setValue(getEntry(section, name), value);
    else
        addEntry(section, name, value);
    end
end
