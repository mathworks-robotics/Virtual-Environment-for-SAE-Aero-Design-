classdef EnvironmentMask
%ENVIRONMENTMASK Resolve and validate preset or custom environments.

    methods (Static)
        function initialize(blockPath)
            if nargin < 1 || isempty(blockPath)
                blockPath = gcb;
            end

            mask = Simulink.Mask.get(blockPath);
            if isempty(mask)
                error('EnvironmentMask:MissingMask', ...
                    'Environment block is not masked: %s', blockPath);
            end

            [environment, sourceMode, customSource, presetSource] = ...
                EnvironmentMask.resolveSourcesForBlock(blockPath);
            workspace = mask.getWorkspace;
            workspace.set('envCustomSource', customSource);
            workspace.set('envPresetSource', presetSource);
            workspace.set('envActive', environment);
            workspace.set('environmentSourceMode', sourceMode);
            workspace.set('environmentName', environment.Name);

            EnvironmentMask.configureWindBlocks(blockPath, environment);
        end

        function selectionChanged(blockPath)
            if nargin < 1 || isempty(blockPath)
                blockPath = gcb;
            end

            mask = Simulink.Mask.get(blockPath);
            selection = mask.getParameter('envPreset').Value;
            customTabs = mask.getDialogControl('customEnvironmentTabs');
            customTabs.Visible = EnvironmentMask.onOff( ...
                EnvironmentMask.isCustomSelection(selection));
        end

        function environment = resolveForBlock(blockPath)
            environment = EnvironmentMask.resolveSourcesForBlock(blockPath);
        end

        function [environment, sourceMode, customSource, presetSource] = ...
                resolveSourcesForBlock(blockPath)
            mask = Simulink.Mask.get(blockPath);
            values = EnvironmentMask.readMaskValues(mask);
            catalog = slResolve('envCatalog', blockPath);
            if isa(catalog, 'Simulink.Parameter')
                catalog = catalog.Value;
            end

            [environment, sourceMode, customSource, presetSource] = ...
                EnvironmentMask.resolveSources( ...
                values.envPreset, catalog, values);
        end

        function environment = resolve(selection, catalog, values)
            environment = EnvironmentMask.resolveSources( ...
                selection, catalog, values);
        end

        function options = presetOptions()
            options = { ...
                'Custom environment', ...
                'Sea Level Standard (1.0x)', ...
                'Aero Design West - Van Nuys CA (1.1x)', ...
                'Aero Design East FL - Lakeland (1.2x)', ...
                'Aero Design East TX - Fort Worth (1.3x)', ...
                'Hot Day - Chennai India (1.5x)', ...
                'Cold Windy Day - Toronto (1.6x)', ...
                'Afternoon Gusts - Lakeland FL (2.0x)', ...
                'High Altitude - Denver-type (2.5x)'};
        end

        function option = customOption()
            options = EnvironmentMask.presetOptions;
            option = options{1};
        end

        function option = optionForPreset(presetNumber)
            validateattributes(presetNumber, {'numeric'}, ...
                {'real', 'finite', 'integer', 'scalar', '>=', 1, '<=', 8});
            options = EnvironmentMask.presetOptions;
            option = options{presetNumber + 1};
        end

        function mode = sourceMode(selection)
            if EnvironmentMask.isCustomSelection(selection)
                mode = 1;
            else
                mode = 2;
            end
        end

        function label = formatIconLabel(environmentName)
            label = strtrim(char(string(environmentName)));
            if isempty(label)
                label = 'Environment';
                return;
            end

            maxLineLength = 28;
            if numel(label) <= maxLineLength
                return;
            end

            splitCandidates = strfind(label, ' (');
            if isempty(splitCandidates)
                splitCandidates = find(label == ' ');
                if isempty(splitCandidates)
                    return;
                end
                [~, nearestIndex] = min( ...
                    abs(splitCandidates - numel(label) / 2));
                splitIndex = splitCandidates(nearestIndex);
            else
                splitIndex = splitCandidates(1);
            end

            label = sprintf('%s\n%s', ...
                strtrim(label(1:splitIndex - 1)), ...
                strtrim(label(splitIndex + 1:end)));
        end
    end

    methods (Static, Access = private)
        function values = readMaskValues(mask)
            variables = mask.getWorkspaceVariables;
            values = struct;
            for index = 1:numel(variables)
                if isvarname(variables(index).Name)
                    values.(variables(index).Name) = variables(index).Value;
                end
            end
        end

        function [environment, sourceMode, customSource, presetSource] = ...
                resolveSources(selection, catalog, values)
            if ~isstruct(catalog) || numel(catalog) < 8
                error('EnvironmentMask:InvalidCatalog', ...
                    'envCatalog must contain all eight predefined environments.');
            end

            presetNumber = EnvironmentMask.selectionPresetNumber(selection);
            if presetNumber == 0
                customSource = EnvironmentMask.buildCustomEnvironment(values);
                EnvironmentMask.validateEnvironment(customSource);
                presetSource = catalog(1);
                environment = customSource;
                sourceMode = 1;
            else
                presetSource = catalog(presetNumber);
                EnvironmentMask.validateEnvironment(presetSource);
                customSource = catalog(1);
                environment = presetSource;
                sourceMode = 2;
            end
        end

        function presetNumber = selectionPresetNumber(selection)
            if isnumeric(selection)
                numericSelection = double(selection);
            else
                selection = strtrim(char(selection));
                numericSelection = str2double(selection);
            end

            if exist('numericSelection', 'var') && ...
                    isfinite(numericSelection)
                if ismember(numericSelection, [0 9])
                    presetNumber = 0;
                else
                    presetNumber = numericSelection;
                end
            else
                options = EnvironmentMask.presetOptions;
                optionIndex = find(strcmp(selection, options), 1);
                if isempty(optionIndex)
                    presetNumber = [];
                elseif optionIndex == 1
                    presetNumber = 0;
                else
                    presetNumber = optionIndex - 1;
                end

                if isempty(presetNumber)
                    if contains(selection, 'Custom', 'IgnoreCase', true)
                        presetNumber = 0;
                    elseif contains(selection, 'Sea Level', 'IgnoreCase', true)
                        presetNumber = 1;
                    elseif contains(selection, 'Van Nuys', 'IgnoreCase', true)
                        presetNumber = 2;
                    elseif contains(selection, 'Lakeland', 'IgnoreCase', true) && ...
                            ~contains(selection, 'Gust', 'IgnoreCase', true)
                        presetNumber = 3;
                    elseif contains(selection, 'Fort Worth', 'IgnoreCase', true)
                        presetNumber = 4;
                    elseif contains(selection, 'Hot Day', 'IgnoreCase', true)
                        presetNumber = 5;
                    elseif contains(selection, 'Cold Windy', 'IgnoreCase', true)
                        presetNumber = 6;
                    elseif contains(selection, 'Gust', 'IgnoreCase', true)
                        presetNumber = 7;
                    elseif contains(selection, 'High Altitude', 'IgnoreCase', true)
                        presetNumber = 8;
                    end
                end
            end

            if isempty(presetNumber) || ~isscalar(presetNumber) || ...
                    ~ismember(presetNumber, 0:8)
                error('EnvironmentMask:UnknownSelection', ...
                    'Unknown environment selection.');
            end
        end

        function isCustom = isCustomSelection(selection)
            isCustom = ...
                EnvironmentMask.selectionPresetNumber(selection) == 0;
        end

        function environment = buildCustomEnvironment(values)
            environment.Name = EnvironmentMask.textValue( ...
                values.customName, 'Environment name', false);
            environment.Description = EnvironmentMask.textValue( ...
                values.customDescription, 'Description', true);
            environment.Multiplier = EnvironmentMask.scalarValue( ...
                values.customMultiplier, 'Score multiplier');
            environment.CompetitionSite = EnvironmentMask.logicalValue( ...
                values.customCompetitionSite, 'Competition site');

            environment.Location.Name = EnvironmentMask.textValue( ...
                values.customLocationName, 'Location name', false);
            environment.Location.City = EnvironmentMask.textValue( ...
                values.customCity, 'City', true);
            environment.Location.Country = EnvironmentMask.textValue( ...
                values.customCountry, 'Country', true);
            environment.Location.Latitude_deg = EnvironmentMask.scalarValue( ...
                values.customLatitude_deg, 'Latitude');
            environment.Location.Longitude_deg = EnvironmentMask.scalarValue( ...
                values.customLongitude_deg, 'Longitude');
            environment.Location.Elevation_MSL_m = EnvironmentMask.scalarValue( ...
                values.customElevation_MSL_m, 'Location elevation');

            environment.Atmosphere.Elevation_MSL_m = EnvironmentMask.scalarValue( ...
                values.customAtmosphereElevation_MSL_m, ...
                'Atmosphere reference elevation');
            environment.Atmosphere.ISA_Deviation_C = EnvironmentMask.scalarValue( ...
                values.customISADeviation_C, 'ISA temperature deviation');
            environment.Atmosphere.Temperature_C = EnvironmentMask.scalarValue( ...
                values.customTemperature_C, 'Temperature');
            environment.Atmosphere.Pressure_Pa = EnvironmentMask.scalarValue( ...
                values.customPressure_Pa, 'Pressure');
            environment.Atmosphere.Density_kgm3 = EnvironmentMask.scalarValue( ...
                values.customDensity_kgm3, 'Air density');
            environment.Atmosphere.DensityRatio = ...
                environment.Atmosphere.Density_kgm3 / 1.2250;

            environment.WindShear.Speed_6m_mps = EnvironmentMask.scalarValue( ...
                values.customWindShearSpeed_mps, 'Wind shear speed');
            environment.WindShear.Direction_deg = EnvironmentMask.scalarValue( ...
                values.customWindShearDirection_deg, 'Wind shear direction');
            environment.WindShear.Exponent = EnvironmentMask.scalarValue( ...
                values.customWindShearExponent, 'Wind shear exponent');

            environment.Turbulence.Speed_6m_mps = EnvironmentMask.scalarValue( ...
                values.customTurbulenceSpeed_mps, 'Turbulence wind speed');
            environment.Turbulence.Direction_deg = EnvironmentMask.scalarValue( ...
                values.customTurbulenceDirection_deg, 'Turbulence direction');
            environment.Turbulence.Sigma_mps = EnvironmentMask.scalarValue( ...
                values.customTurbulenceSigma_mps, 'Turbulence sigma');
            environment.Turbulence.Scale_Lu_m = EnvironmentMask.scalarValue( ...
                values.customTurbulenceScale_m, 'Turbulence scale length');
            environment.Turbulence.TurbulenceOn = EnvironmentMask.logicalValue( ...
                values.customTurbulenceOn, 'Turbulence enabled');
            environment.Turbulence.NoiseSeeds = EnvironmentMask.vectorValue( ...
                values.customNoiseSeeds, 4, 'Turbulence noise seeds');

            environment.Gust.Amplitude_mps = EnvironmentMask.vectorValue( ...
                values.customGustAmplitude_mps, 3, 'Gust amplitude');
            environment.Gust.Length_m = EnvironmentMask.vectorValue( ...
                values.customGustLength_m, 3, 'Gust length');
            environment.Gust.StartTime_s = EnvironmentMask.scalarValue( ...
                values.customGustStartTime_s, 'Gust start time', true);
            environment.Gust.StartAltitude_AGL_m = EnvironmentMask.scalarValue( ...
                values.customGustStartAltitude_AGL_m, 'Gust start altitude');
            environment.Gust.EnableU = EnvironmentMask.logicalValue( ...
                values.customGustEnableU, 'Gust U enabled');
            environment.Gust.EnableV = EnvironmentMask.logicalValue( ...
                values.customGustEnableV, 'Gust V enabled');
            environment.Gust.EnableW = EnvironmentMask.logicalValue( ...
                values.customGustEnableW, 'Gust W enabled');

            environment.Latitude_deg = environment.Location.Latitude_deg;
            environment.Longitude_deg = environment.Location.Longitude_deg;
            environment.Elevation_MSL_m = environment.Location.Elevation_MSL_m;
        end

        function validateEnvironment(environment)
            validateattributes(environment.Multiplier, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'positive'}, '', 'Multiplier');
            validateattributes(environment.Location.Latitude_deg, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>=', -90, '<=', 90}, '', ...
                'Location.Latitude_deg');
            validateattributes(environment.Location.Longitude_deg, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>=', -180, '<=', 180}, '', ...
                'Location.Longitude_deg');
            validateattributes(environment.Atmosphere.Temperature_C, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>', -273.15}, '', ...
                'Atmosphere.Temperature_C');
            validateattributes(environment.Atmosphere.Pressure_Pa, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'positive'}, '', ...
                'Atmosphere.Pressure_Pa');
            validateattributes(environment.Atmosphere.Density_kgm3, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'positive'}, '', ...
                'Atmosphere.Density_kgm3');
            validateattributes(environment.WindShear.Speed_6m_mps, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'nonnegative'}, '', ...
                'WindShear.Speed_6m_mps');
            validateattributes(environment.WindShear.Direction_deg, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>=', 0, '<=', 360}, '', ...
                'WindShear.Direction_deg');
            validateattributes(environment.WindShear.Exponent, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'positive'}, '', ...
                'WindShear.Exponent');
            validateattributes(environment.Turbulence.Speed_6m_mps, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'nonnegative'}, '', ...
                'Turbulence.Speed_6m_mps');
            validateattributes(environment.Turbulence.Direction_deg, {'numeric'}, ...
                {'real', 'finite', 'scalar', '>=', 0, '<=', 360}, '', ...
                'Turbulence.Direction_deg');
            validateattributes(environment.Turbulence.Sigma_mps, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'nonnegative'}, '', ...
                'Turbulence.Sigma_mps');
            validateattributes(environment.Turbulence.Scale_Lu_m, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'positive'}, '', ...
                'Turbulence.Scale_Lu_m');
            validateattributes(environment.Turbulence.NoiseSeeds, {'numeric'}, ...
                {'real', 'finite', 'integer', 'nonnegative', 'numel', 4}, '', ...
                'Turbulence.NoiseSeeds');
            validateattributes(environment.Gust.Amplitude_mps, {'numeric'}, ...
                {'real', 'finite', 'numel', 3}, '', 'Gust.Amplitude_mps');
            validateattributes(environment.Gust.Length_m, {'numeric'}, ...
                {'real', 'finite', 'positive', 'numel', 3}, '', ...
                'Gust.Length_m');
            validateattributes(environment.Gust.StartAltitude_AGL_m, {'numeric'}, ...
                {'real', 'finite', 'scalar', 'nonnegative'}, '', ...
                'Gust.StartAltitude_AGL_m');

            startTime = environment.Gust.StartTime_s;
            if ~isnumeric(startTime) || ~isscalar(startTime) || ...
                    ~isreal(startTime) || isnan(startTime) || startTime < 0
                error('EnvironmentMask:InvalidGustStartTime', ...
                    'Gust.StartTime_s must be nonnegative or Inf.');
            end
        end

        function configureWindBlocks(blockPath, environment)
            gustBlocks = find_system(blockPath, 'SearchDepth', 2, ...
                'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
                'MatchFilter', @Simulink.match.allVariants, ...
                'MaskType', 'Discrete Wind Gust Model');
            turbulenceBlocks = find_system(blockPath, 'SearchDepth', 2, ...
                'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
                'MatchFilter', @Simulink.match.allVariants, ...
                'MaskType', 'Wind Turbulence Model');
            shearBlocks = find_system(blockPath, 'SearchDepth', 2, ...
                'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
                'MatchFilter', @Simulink.match.allVariants, ...
                'MaskType', 'Wind Shear Model');

            if numel(gustBlocks) ~= 1 || numel(turbulenceBlocks) ~= 1 || ...
                    numel(shearBlocks) ~= 1
                error('EnvironmentMask:UnexpectedWindModel', ...
                    'Expected one gust, turbulence, and wind shear block.');
            end

            EnvironmentMask.setIfDifferent(gustBlocks{1}, 'Gx', ...
                EnvironmentMask.onOff(environment.Gust.EnableU));
            EnvironmentMask.setIfDifferent(gustBlocks{1}, 'Gy', ...
                EnvironmentMask.onOff(environment.Gust.EnableV));
            EnvironmentMask.setIfDifferent(gustBlocks{1}, 'Gz', ...
                EnvironmentMask.onOff(environment.Gust.EnableW));

            EnvironmentMask.setIfDifferent(turbulenceBlocks{1}, 'T_on', ...
                EnvironmentMask.onOff(environment.Turbulence.TurbulenceOn));
            EnvironmentMask.setIfDifferent(turbulenceBlocks{1}, 'TurbProb', ...
                EnvironmentMask.turbulenceProbability( ...
                environment.Turbulence.Sigma_mps));

            if environment.WindShear.Exponent <= 0.15
                phase = 'Category C - Terminal Flight Phase';
            else
                phase = 'Other';
            end
            EnvironmentMask.setIfDifferent(shearBlocks{1}, 'phase', phase);
        end

        function probability = turbulenceProbability(sigma)
            if sigma <= 1.5
                probability = '10^-2 - Light';
            elseif sigma <= 3.0
                probability = '10^-3 - Moderate';
            else
                probability = '10^-5 - Severe';
            end
        end

        function setIfDifferent(blockPath, parameter, value)
            if ~strcmp(get_param(blockPath, parameter), value)
                set_param(blockPath, parameter, value);
            end
        end

        function value = scalarValue(rawValue, label, allowInf)
            if nargin < 3
                allowInf = false;
            end
            if ~isnumeric(rawValue) || ~isreal(rawValue) || ...
                    ~isscalar(rawValue) || isnan(rawValue) || ...
                    (~allowInf && ~isfinite(rawValue))
                error('EnvironmentMask:InvalidScalar', ...
                    '%s must be a real numeric scalar.', label);
            end
            value = double(rawValue);
        end

        function value = vectorValue(rawValue, count, label)
            if ~isnumeric(rawValue) || ~isreal(rawValue) || ...
                    numel(rawValue) ~= count || any(~isfinite(rawValue(:)))
                error('EnvironmentMask:InvalidVector', ...
                    '%s must contain %d finite numeric values.', label, count);
            end
            value = reshape(double(rawValue), 1, count);
        end

        function value = logicalValue(rawValue, label)
            if islogical(rawValue) && isscalar(rawValue)
                value = rawValue;
                return;
            end
            if isnumeric(rawValue) && isscalar(rawValue) && ...
                    ismember(rawValue, [0 1])
                value = logical(rawValue);
                return;
            end
            if ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue))
                text = lower(strtrim(char(rawValue)));
                if ismember(text, {'on', 'true', '1'})
                    value = true;
                    return;
                elseif ismember(text, {'off', 'false', '0'})
                    value = false;
                    return;
                end
            end
            error('EnvironmentMask:InvalidLogical', ...
                '%s must be on or off.', label);
        end

        function value = textValue(rawValue, label, allowEmpty)
            if ~(ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue)))
                error('EnvironmentMask:InvalidText', ...
                    '%s must be text.', label);
            end
            value = strtrim(char(rawValue));
            if ~allowEmpty && isempty(value)
                error('EnvironmentMask:EmptyText', ...
                    '%s cannot be empty.', label);
            end
        end

        function value = onOff(condition)
            if condition
                value = 'on';
            else
                value = 'off';
            end
        end
    end
end
