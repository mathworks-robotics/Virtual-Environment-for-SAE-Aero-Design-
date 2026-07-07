classdef Calibrated_Controller
    methods(Static)

        function MaskInitialization(maskInitContext)
            if nargin < 1, return; end

            try
                maskObj     = maskInitContext.MaskObject;
                blockHandle = maskInitContext.BlockHandle;
                blockPath   = getfullname(blockHandle);
                mws         = maskInitContext.MaskWorkspace;

                configFileName = strtrim(maskObj.getParameter('configName').Value);

                % Case 1: No file configured — load safe defaults
                if isempty(configFileName) || strcmp(configFileName, '0')
                    Calibrated_Controller.loadDefaults(mws);
                    Calibrated_Controller.pushJoystickFromMask(maskObj, blockPath);
                    return;
                end

                % Case 2: Struct already in base workspace — use it directly
                if evalin('base', 'exist(''pilotCfgActive'', ''var'')')
                    cfg = evalin('base', 'pilotCfgActive');
                    Calibrated_Controller.flattenToMaskWorkspace(mws, cfg);
                    Calibrated_Controller.pushJoystickFromMask(maskObj, blockPath);
                    return;
                end

                % Case 3: File path stored — try auto-loading from disk
                if ~isfile(configFileName)
                    warning('CalibratedInput:fileNotFound', ...
                        'CalibratedInput: Config file "%s" not found. Using defaults.', ...
                        configFileName);
                    Calibrated_Controller.loadDefaults(mws);
                    Calibrated_Controller.pushJoystickFromMask(maskObj, blockPath);
                    return;
                end

                try
                    loaded = load(configFileName);
                catch
                    warning('CalibratedInput:readError', ...
                        'CalibratedInput: Could not read "%s". Using defaults.', ...
                        configFileName);
                    Calibrated_Controller.loadDefaults(mws);
                    Calibrated_Controller.pushJoystickFromMask(maskObj, blockPath);
                    return;
                end

                % Find valid struct inside file
                fields = fieldnames(loaded);
                cfg    = [];
                for i = 1:length(fields)
                    candidate = loaded.(fields{i});
                    if isstruct(candidate) && isfield(candidate, 'joystickID')
                        cfg = candidate;
                        break;
                    end
                end

                if isempty(cfg)
                    warning('CalibratedInput:noValidStruct', ...
                        'CalibratedInput: No valid pilot config in "%s". Using defaults.', ...
                        configFileName);
                    Calibrated_Controller.loadDefaults(mws);
                    Calibrated_Controller.pushJoystickFromMask(maskObj, blockPath);
                    return;
                end

                % Success — push to workspace and flatten
                assignin('base', 'pilotCfgActive', cfg);
                Calibrated_Controller.flattenToMaskWorkspace(mws, cfg);

                % First load from file — set dropdown FROM cfg then push
                Calibrated_Controller.pushJoystick(maskObj, blockPath, cfg);

            catch
            end
        end


        function pushJoystick(maskObj, blockPath, cfg)
            try
                joyParam = maskObj.getParameter('joystickID');
                if ismember(cfg.joystickID, joyParam.TypeOptions)
                    joyParam.Value = cfg.joystickID;
                end
                set_param([blockPath '/Pilot Joystick All'], ...
                    'JoystickID', cfg.joystickID);
            catch
            end
        end


        function pushJoystickFromMask(maskObj, blockPath)
            try
                joyID = maskObj.getParameter('joystickID').Value;
                set_param([blockPath '/Pilot Joystick All'], ...
                    'JoystickID', joyID);
            catch
            end
        end


        function joystickID(callbackContext)
            joyID     = callbackContext.ParameterObject.Value;
            blockPath = getfullname(callbackContext.BlockHandle);
            try
                set_param([blockPath '/Pilot Joystick All'], ...
                    'JoystickID', joyID);
            catch
            end
        end


        function success = loadFromFile(maskObj, blockPath, fullPath)
            success = false;

            try
                loaded = load(fullPath);
            catch
                errordlg(sprintf('Could not load file:\n%s', fullPath), ...
                    'File Error');
                return;
            end

            % Find valid struct
            fields = fieldnames(loaded);
            cfg    = [];
            for i = 1:length(fields)
                candidate = loaded.(fields{i});
                if isstruct(candidate) && isfield(candidate, 'joystickID')
                    cfg = candidate;
                    break;
                end
            end

            if isempty(cfg)
                errordlg(sprintf( ...
                    'No valid pilot config struct found in:\n%s\n\nMake sure it was saved from the calibration model.', ...
                    fullPath), 'Load Error');
                return;
            end

            % Validate required fields
            requiredFields = { ...
                'joystickID', ...
                'rollCh',    'rollDB',    'uRollMin',    'uRollMax',    'dirRoll', ...
                'pitchCh',   'pitchDB',   'uPitchMin',   'uPitchMax',   'dirPitch', ...
                'yawCh',     'yawDB',     'uYawMin',     'uYawMax',     'dirYaw', ...
                'throttleCh','throttleDB','uThrottleMin','uThrottleMax','dirThrottle', ...
                'aileronMin','aileronMax','elevatorMin', 'elevatorMax'};

            missingFields = {};
            for i = 1:length(requiredFields)
                if ~isfield(cfg, requiredFields{i})
                    missingFields{end+1} = requiredFields{i}; %#ok<AGROW>
                end
            end

            if ~isempty(missingFields)
                errordlg(sprintf('Config is missing fields:\n%s', ...
                    strjoin(missingFields, ', ')), 'Invalid Config');
                return;
            end

            % Store full path and push to workspace
            maskObj.getParameter('configName').Value = fullPath;
            assignin('base', 'pilotCfgActive', cfg);

            % ✅ Use shared helper — consistent with rest of class
            Calibrated_Controller.pushJoystick(maskObj, blockPath, cfg);

            % Trigger MaskInitialization
            try
                mask = Simulink.Mask.get(blockPath);
                mask.Initialization = mask.Initialization;
            catch
            end

            success = true;

            msgbox(sprintf( ...
                'Loaded:  %s\n\nJoystick   :  %s\nRoll       :  ch %d\nPitch      :  ch %d\nYaw        :  ch %d\nThrottle   :  ch %d', ...
                fullPath, cfg.joystickID, ...
                cfg.rollCh, cfg.pitchCh, cfg.yawCh, cfg.throttleCh), ...
                'Configuration Loaded');
        end


        function loadConfig(callbackContext)
            maskObj   = Simulink.Mask.get(callbackContext.BlockHandle);
            blockPath = getfullname(callbackContext.BlockHandle);

            [fileName, filePath] = uigetfile('*.mat', ...
                'Select Pilot Configuration File');
            if isequal(fileName, 0), return; end

            Calibrated_Controller.loadFromFile(maskObj, blockPath, ...
                fullfile(filePath, fileName));
        end


        function flattenToMaskWorkspace(mws, cfg)
            mws.set('joystickID',    cfg.joystickID);

            mws.set('rollCh',        cfg.rollCh);
            mws.set('rollDB',        cfg.rollDB);
            mws.set('uRollMin',      cfg.uRollMin);
            mws.set('uRollMax',      cfg.uRollMax);
            mws.set('dirRoll',       cfg.dirRoll);

            mws.set('pitchCh',       cfg.pitchCh);
            mws.set('pitchDB',       cfg.pitchDB);
            mws.set('uPitchMin',     cfg.uPitchMin);
            mws.set('uPitchMax',     cfg.uPitchMax);
            mws.set('dirPitch',      cfg.dirPitch);

            mws.set('yawCh',         cfg.yawCh);
            mws.set('yawDB',         cfg.yawDB);
            mws.set('uYawMin',       cfg.uYawMin);
            mws.set('uYawMax',       cfg.uYawMax);
            mws.set('dirYaw',        cfg.dirYaw);

            mws.set('throttleCh',    cfg.throttleCh);
            mws.set('throttleDB',    cfg.throttleDB);
            mws.set('uThrottleMin',  cfg.uThrottleMin);
            mws.set('uThrottleMax',  cfg.uThrottleMax);
            mws.set('dirThrottle',   cfg.dirThrottle);

            mws.set('aileronMin',    cfg.aileronMin);
            mws.set('aileronMax',    cfg.aileronMax);
            mws.set('elevatorMin',   cfg.elevatorMin);
            mws.set('elevatorMax',   cfg.elevatorMax);
        end


        function loadDefaults(mws)
            mws.set('joystickID',    'Joystick1');

            mws.set('rollCh',        1);
            mws.set('rollDB',        0.05);
            mws.set('uRollMin',      -1);
            mws.set('uRollMax',      1);
            mws.set('dirRoll',       1);

            mws.set('pitchCh',       2);
            mws.set('pitchDB',       0.05);
            mws.set('uPitchMin',     -1);
            mws.set('uPitchMax',     1);
            mws.set('dirPitch',      1);

            mws.set('yawCh',         3);
            mws.set('yawDB',         0.05);
            mws.set('uYawMin',       -1);
            mws.set('uYawMax',       1);
            mws.set('dirYaw',        1);

            mws.set('throttleCh',    4);
            mws.set('throttleDB',    0.02);
            mws.set('uThrottleMin',  0);
            mws.set('uThrottleMax',  1);
            mws.set('dirThrottle',   1);

            mws.set('aileronMin',    -15);
            mws.set('aileronMax',    15);
            mws.set('elevatorMin',   -25);
            mws.set('elevatorMax',   25);
        end

    end
end