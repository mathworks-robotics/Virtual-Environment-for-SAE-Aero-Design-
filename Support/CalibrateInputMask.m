classdef CalibrateInputMask

    methods(Static)

        % Following properties of 'maskInitContext' are available to use:
        %  - BlockHandle 
        %  - MaskObject 
        %  - MaskWorkspace: Use get/set APIs to work with mask workspace.
        function MaskInitialization(maskInitContext)
            % Get mask object from context (not gcb)
            maskObj = maskInitContext.MaskObject;
            blockHandle = maskInitContext.BlockHandle;
            blockPath = getfullname(blockHandle);

            % ── Push JoystickID into Pilot_Joystick block ──────
            joyID = maskObj.getParameter('joystickID').Value;
            CalibrateInputMask.setJoystickID(blockPath, joyID);
        end

        % Use the code browser on the left to add the callbacks.


        function joystickID(callbackContext)
            joyID     = callbackContext.ParameterObject.Value;
            blockPath = getfullname(callbackContext.BlockHandle);

            CalibrateInputMask.setJoystickID(blockPath, joyID);
        end

        function saveConfig(callbackContext)
            blockHandle= getfullname(callbackContext.BlockHandle);
            maskObj = Simulink.Mask.get(blockHandle);
            
            
            % ── Step 1: Ask user for config name ──────────────────────
            answer = inputdlg( ...
                'Enter configuration name:', ...
                'Save Pilot Config', ...
                [1 40], ...
                {'pilotConfig'});          % default name pre-filled
            
            % User hit Cancel
            if isempty(answer), return; end

            configName = strtrim(answer{1});

            % Validate — no spaces or special chars
            if isempty(configName) || ~isvarname(configName)
                errordlg( ...
                    'Invalid name. Use letters, numbers, underscores only (no spaces).', ...
                    'Save Failed');
                return;
            end
            
            % ── Step 2: Read all mask values ──────────────────────────
            % maskObj = Simulink.Mask.get(callbackContext.BlockHandle);

            cfg.joystickID  = maskObj.getParameter('joystickID').Value;
            
            cfg.rollCh   = str2double(maskObj.getParameter('rollCh').Value);
            cfg.rollDB   = str2double(maskObj.getParameter('rollDB').Value);
            cfg.uRollMin  = str2double(maskObj.getParameter('uRollMin').Value);
            cfg.uRollMax  = str2double(maskObj.getParameter('uRollMax').Value);
            cfg.dirRoll     = strcmp(maskObj.getParameter('dirRoll').Value,     'on');
            
            cfg.pitchCh  = str2double(maskObj.getParameter('pitchCh').Value);
            cfg.pitchDB  = str2double(maskObj.getParameter('pitchDB').Value);
            cfg.uPitchMin = str2double(maskObj.getParameter('uPitchMin').Value);
            cfg.uPitchMax = str2double(maskObj.getParameter('uPitchMax').Value);
            cfg.dirPitch    = strcmp(maskObj.getParameter('dirPitch').Value,     'on');

            cfg.yawCh    = str2double(maskObj.getParameter('yawCh').Value);
            cfg.yawDB    = str2double(maskObj.getParameter('yawDB').Value);
            cfg.uYawMin   = str2double(maskObj.getParameter('uYawMin').Value);
            cfg.uYawMax   = str2double(maskObj.getParameter('uYawMax').Value);
            cfg.dirYaw      = strcmp(maskObj.getParameter('dirYaw').Value,       'on');

            cfg.throttleCh    = str2double(maskObj.getParameter('throttleCh').Value);
            cfg.throttleDB    = str2double(maskObj.getParameter('throttleDB').Value);
            cfg.uThrottleMin   = str2double(maskObj.getParameter('uThrottleMin').Value);
            cfg.uThrottleMax   = str2double(maskObj.getParameter('uThrottleMax').Value);
            cfg.dirThrottle = strcmp(maskObj.getParameter('dirThrottle').Value,  'on');

            cfg.aileronMin  = str2double(maskObj.getParameter('aileronMin').Value);
            cfg.aileronMax  = str2double(maskObj.getParameter('aileronMax').Value);
            cfg.elevatorMin =  str2double(maskObj.getParameter('elevatorMin').Value);
            cfg.elevatorMax = str2double(maskObj.getParameter('elevatorMax').Value);
            cfg.rudderMin   = str2double(maskObj.getParameter('rudderMin').Value);
            cfg.rudderMax   = str2double(maskObj.getParameter('rudderMax').Value);
            
            cfg.savedAt = char(datetime( ...
                'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            
            % ── Step 3: Save to base workspace ────────────────────────
            assignin('base', configName, cfg);
            
            % ── Step 4: Ask where to save the MAT file ────────────────
            [file, path] = uiputfile( ...
                '*.mat', ...
                'Save MAT file as...', ...
                [configName '.mat']);       % default filename = config name

            if isequal(file, 0)
                % User cancelled file dialog — struct saved, skip MAT
                msgbox( ...
                    sprintf('"%s" saved to workspace only (MAT file skipped).', configName), ...
                    'Saved');
                return;
            end

            % ── Step 5: Save MAT file ─────────────────────────────────
            fullPath = fullfile(path, file);
            builtin('save', fullPath, 'cfg');

            % ── Step 6: Confirm ───────────────────────────────────────
            msgbox( ...
                sprintf('"%s" saved to workspace and:\n%s', configName, fullPath), ...
                'Save Successful');
            
        end

        function setJoystickID(blockPath, joystickID)
            joystickBlocks = find_system(blockPath, ...
                'SearchDepth', 1, ...
                'LookUnderMasks', 'all', ...
                'FollowLinks', 'on', ...
                'IncludeCommented', 'on', ...
                'MaskType', 'Simulation 3D Joystick');
            if numel(joystickBlocks) ~= 1
                error('CalibrateInputMask:JoystickBlockNotFound', ...
                    ['Expected one Simulation 3D Joystick block inside ' ...
                     '"%s", but found %d.'], blockPath, numel(joystickBlocks));
            end
            joystickNumber = CalibrateInputMask.joystickNumber(joystickID);
            if ~isempty(joystickNumber)
                set_param(joystickBlocks{1}, 'joyid', ...
                    sprintf('%d', joystickNumber));
            end
        end

        function joystickNumber = joystickNumber(joystickID)
            joystickText = strtrim(char(string(joystickID)));
            if strcmpi(joystickText, 'None')
                joystickNumber = [];
                return;
            end

            token = regexp(joystickText, ...
                '^Joystick\s*(\d+)$', 'tokens', 'once');
            if isempty(token)
                joystickNumber = str2double(joystickText);
            else
                joystickNumber = str2double(token{1});
            end
            validateattributes(joystickNumber, {'numeric'}, ...
                {'scalar', 'integer', '>=', 1, '<=', 12}, ...
                '', 'joystickID');
        end
    end
end
