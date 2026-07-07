classdef MaskCodeClass

    methods(Static)

       function envPreset(callbackContext)
             
           parameterObj = callbackContext.ParameterObject; 
           blkHandle = callbackContext.BlockHandle;
           
           mdl = bdroot(blkHandle);
           mws = get_param(mdl, 'ModelWorkspace');
           caseVal = parameterObj.Value;
           
           switch caseVal
                case 'Sea Level Standard (1.0x)'
                    value = 1;
                case 'Aero Design West — Van Nuys CA (1.1×)'
                    value = 2;
                case 'Aero Design East FL — Lakeland (1.2x)'
                    value = 3;
                case 'Aero Design East TX — Fort Worth (1.3x)'
                    value = 4;
                case 'Hot Day — Chennai India (1.5x)'
                    value = 5; 
                case 'Cold Windy Day — Toronto (1.6×)'
                    value = 6;
                case 'Afternoon Gusts — Lakeland, FL (2.0x)'
                    value = 7;
                case 'High Altitude — Denver-type (2.5x)'
                    value = 8;
            end
            env = environmentLibrary(value);
            Initialization;
            % Save output to model workspace
            assignin(mws, 'env', env);
            
        end
    end
end