% =========================================================================
% importDatcomData.m
%
% SUPPORT FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% Imports a Digital DATCOM .out file and returns an aeroData struct whose
% four sub-structs are format-identical to importAeroData():
%
%   aeroData.elevatorData          same as importAeroData(file,'Elevator')
%   aeroData.rudderData            same as importAeroData(file,'Rudder')
%   aeroData.aileronData           same as importAeroData(file,'Aileron')
%   aeroData.stabilityDerivatives  same as importAeroData(file,'StabilityDerivatives')
%
% Called in Section 3 of setupData_DATCOM.mlx.
%
% SYNTAX:
%   aeroData = importDatcomData(datcomFile, geometry, datcomMRC)
%   aeroData = importDatcomData(datcomFile, geometry, datcomMRC, Name, Value)
%
% REQUIRED INPUTS:
%   datcomFile  char/string  Path to the DATCOM .out output file.
%   geometry    struct       Aircraft geometry struct (from Section 1 of
%                            setupData_DATCOM.mlx). Fields used:
%                              geometry.MAC    [m]  Mean aerodynamic chord
%                              geometry.Span   [m]  Wing span
%                              geometry.Area   [m^2] Wing reference area
%   datcomMRC   scalar [m]   Moment reference centre used in DATCOM
%                            (XCG= value from your DATCOM input deck, in metres).
%                            Used to compute neutral point location.
%
% OPTIONAL NAME-VALUE PAIRS:
%
%   Mach/Alt selection (default: first condition in file):
%     'Mach'             scalar   Desired Mach; nearest case selected.
%     'Altitude'         scalar   Desired altitude in DATCOM units (ft).
%
%   Elevator (used when DATCOM has no DELTA or SYMFLP card):
%     'CLde_perDeg'      scalar [/deg]   dCL/d(elevator deflection)
%     'Cmde_perDeg'      scalar [/deg]   dCm/d(elevator deflection)
%     'CDde_perDeg'      scalar [/deg]   dCD/d(elevator deflection) (default: 0)
%     'ElevatorDeltas'   vector [deg]    Deflection sweep (default: -20:5:20)
%
%   Aileron (used when DATCOM has no ASYFLP card):
%     'Clda_perDeg'      scalar [/deg]   dCl/d(aileron deflection)
%     'Cnda_perDeg'      scalar [/deg]   dCn/d(aileron deflection) (default: 0)
%     'CYda_perDeg'      scalar [/deg]   dCY/d(aileron deflection) (default: 0)
%     'AileronDeltas'    vector [deg]    Deflection sweep (default: -20:5:20)
%
%   Rudder (DATCOM cannot compute rudder -- always supply for non-zero effect):
%     'CYdr_perDeg'      scalar [/deg]   dCY/d(rudder deflection) (default: 0)
%     'Cndr_perDeg'      scalar [/deg]   dCn/d(rudder deflection) (default: 0)
%     'Cldr_perDeg'      scalar [/deg]   dCl/d(rudder deflection) (default: 0)
%     'RudderDeltas'     vector [deg]    Deflection sweep (default: -25:5:25)
%     'BetaSweep'        vector [deg]    Beta axis for rudder table (default: -15:3:15)
%
% OUTPUT -- aeroData struct:
%
%   aeroData.elevatorData
%     .ControlSurface     'Elevator'
%     .ControlDeflections [nDefl x 1]  deg
%     .Alpha              [nAlpha x 1] deg   (sweep axis)
%     .Beta               0            deg   (scalar, not swept)
%     .CL .CD .Cm .CY .Cl .Cn  [nDefl x nAlpha]
%     .XCP                [nDefl x nAlpha]
%     .RawData            MATLAB table (DATCOM static table at selected Mach/Alt)
%     .CLde_perDeg        scalar [/deg]   slope at alpha~0
%     .Cmde_perDeg        scalar [/deg]
%
%   aeroData.rudderData
%     .ControlSurface     'Rudder'
%     .ControlDeflections [nDefl x 1]  deg
%     .Beta               [nBeta x 1]  deg   (sweep axis)
%     .Alpha              0            deg   (scalar, not swept)
%     .CY .Cn .Cl .CL .CD .Cm  [nDefl x nBeta]
%     .RawData            MATLAB table (beta sweep at dr=0)
%     .CYdr_perDeg        scalar [/deg]
%     .Cndr_perDeg        scalar [/deg]
%
%   aeroData.aileronData
%     .ControlSurface     'Aileron'
%     .ControlDeflections [nDefl x 1]  deg
%     .Alpha              [nAlpha x 1] deg   (sweep axis)
%     .Beta               0            deg   (scalar)
%     .CL .CD .Cm .CY .Cl .Cn  [nDefl x nAlpha]
%     .RawData            MATLAB table
%     .Clda_perDeg        scalar [/deg]
%     .Cnda_perDeg        scalar [/deg]
%
%   aeroData.stabilityDerivatives
%     .CLa  .CLq  .Cma  .Cmq  .CLad .Cmad    Longitudinal
%     .Cxu  .Cxa  .Czu  .Cmu                 Speed derivatives (estimated)
%     .CYb  .CYp  .CYr                        Lateral force
%     .Clb  .Clp  .Clr                        Roll moment
%     .Cnb  .Cnp  .Cnr                        Yaw moment
%     .NeutralPoint_m                          [m] from nose
%     .pitchStable  .yawStable  .rollStable    logical flags
%
% =========================================================================
%
% WHY THREE REQUIRED INPUTS (not just datcomFile):
%   geometry is needed so the function can express outputs in the same
%   reference frame as the manual path (SI units, same MAC/Span/Area).
%   datcomMRC [m] is the XCG= value from your DATCOM input deck -- required
%   to compute the neutral point location correctly.  If you set XCG in
%   DATCOM to match your actual CG, datcomMRC == geometry.CGBody.X.
%
% DATCOM LIMITATION -- RUDDER:
%   Digital DATCOM does not compute rudder effectiveness. Always supply
%   'CYdr_perDeg' and 'Cndr_perDeg' from AVL, OpenVSP, wind tunnel, or
%   handbook methods (DATCOM Section 6.3).  Default is zero.
%
% DATCOM LIMITATION -- CONTROL SURFACES:
%   If your DATCOM run does not include a DELTA (elevator) or ASYFLP
%   (aileron) card, provide CLde_perDeg / Clda_perDeg as Name-Value pairs.
%   The function builds the full [nDefl x nAlpha] table by scaling the
%   per-degree slope across the deflection sweep.
%
% REQUIRES: Aerospace Toolbox (datcomimport function)
% SEE ALSO:  importAeroData, extractAeroSummary, setupData_DATCOM.mlx
%
% =========================================================================

function aeroData = importDatcomData(datcomFile, geometry, datcomMRC, varargin)

    % =====================================================================
    %  Parse and validate inputs
    % =====================================================================
    validateInputs(datcomFile, geometry, datcomMRC);

    p = inputParser;
    addRequired(p,  'datcomFile');
    addRequired(p,  'geometry');
    addRequired(p,  'datcomMRC');
    addParameter(p, 'Mach',            [],           @isnumeric);
    addParameter(p, 'Altitude',        [],           @isnumeric);
    % Elevator fallback
    addParameter(p, 'CLde_perDeg',     [],           @isnumeric);
    addParameter(p, 'Cmde_perDeg',     [],           @isnumeric);
    addParameter(p, 'CDde_perDeg',     0,            @isnumeric);
    addParameter(p, 'ElevatorDeltas',  (-20:5:20)',  @isnumeric);
    % Aileron fallback
    addParameter(p, 'Clda_perDeg',     [],           @isnumeric);
    addParameter(p, 'Cnda_perDeg',     0,            @isnumeric);
    addParameter(p, 'CYda_perDeg',     0,            @isnumeric);
    addParameter(p, 'AileronDeltas',   (-20:5:20)',  @isnumeric);
    % Rudder (always external)
    addParameter(p, 'CYdr_perDeg',     0,            @isnumeric);
    addParameter(p, 'Cndr_perDeg',     0,            @isnumeric);
    addParameter(p, 'Cldr_perDeg',     0,            @isnumeric);
    addParameter(p, 'RudderDeltas',    (-25:5:25)',  @isnumeric);
    addParameter(p, 'BetaSweep',       (-15:3:15)',  @isnumeric);
    parse(p, datcomFile, geometry, datcomMRC, varargin{:});
    opts = p.Results;

    % =====================================================================
    %  Load DATCOM file via Aerospace Toolbox
    % =====================================================================
    fprintf('\nimportDatcomData: reading %s ...\n', datcomFile);

    if ~exist('datcomimport', 'file')
        error('importDatcomData:missingToolbox', ...
            ['Aerospace Toolbox is required (datcomimport). \n' ...
             'Ensure Aerospace Toolbox is installed and licensed.']);
    end

    rawCell = datcomimport(datcomFile, false, 0);
    dc      = rawCell{1};
    dc      = replaceMissing99999(dc);

    % =====================================================================
    %  Mach / Altitude selection
    % =====================================================================
    machVec = safeGet(dc, 'mach', 0.1);
    altVec  = safeGet(dc, 'alt',  0);

    mi = pickIndex(machVec, opts.Mach,     'Mach',     'Mach');
    ai = pickIndex(altVec,  opts.Altitude, 'Altitude', 'Altitude');

    selectedMach = machVec(mi);
    selectedAlt  = altVec(ai);
    fprintf('  Selected: Mach=%.3f  Alt=%.0f ft\n', selectedMach, selectedAlt);

    % =====================================================================
    %  Alpha vector  [nAlpha x 1]  deg
    % =====================================================================
    alpha  = safeGet(dc, 'alpha', []);
    alpha  = alpha(:);
    nAlpha = length(alpha);
    if nAlpha == 0
        error('importDatcomData:noAlpha', ...
            'No alpha values in DATCOM file. Check FLTCON NALPHA card.');
    end

    % =====================================================================
    %  Unit conversion  (DATCOM geometry in ft → m)
    % =====================================================================
    datcomDim = safeGet(dc, 'dim', 'ft');
    toSI      = strcmpi(datcomDim, 'ft');
    FT2M      = 0.3048;

    % =====================================================================
    %  Detect available DATCOM cards
    % =====================================================================
    hasDelta  = safeGet(dc, 'ndelta', 0) > 0;
    hasDamp   = isfield(dc, 'clq')    && ~isempty(dc.clq);
    hasSymFlp = isfield(dc, 'dcl_sym') && ~isempty(dc.dcl_sym);
    hasAsyFlp = isfield(dc, 'dcl_asy') && ~isempty(dc.dcl_asy);
    deltaVec  = safeGet(dc, 'delta', []);

    if ~hasDamp
        warning('importDatcomData:noDamp', ...
            ['No DAMP card found. Dynamic derivatives (CLq, Cmq, Clp, Cnr etc.) \n' ...
             'will be zero. Add DAMP to your DATCOM input deck.']);
    end

    % =====================================================================
    %  Extract static aero at selected Mach/Alt  [1 x nAlpha]
    % =====================================================================
    CL0   = sliceStatic(dc, 'cl',  mi, ai, nAlpha);
    CD0   = sliceStatic(dc, 'cd',  mi, ai, nAlpha);
    Cm0   = sliceStatic(dc, 'cm',  mi, ai, nAlpha);
    XCP0  = sliceStatic(dc, 'xcp', mi, ai, nAlpha);

    CLa_v  = sliceStatic(dc, 'cla', mi, ai, nAlpha);
    CMAa_v = sliceStatic(dc, 'cma', mi, ai, nAlpha);
    CYb_v  = sliceStatic(dc, 'cyb', mi, ai, nAlpha);
    CNb_v  = sliceStatic(dc, 'cnb', mi, ai, nAlpha);
    CLb_v  = sliceStatic(dc, 'clb', mi, ai, nAlpha);

    % Dynamic derivatives from DAMP table  [1 x nAlpha]
    CLq_v  = sliceDynamic(dc, 'clq',  mi, ai, nAlpha);
    CMq_v  = sliceDynamic(dc, 'cmq',  mi, ai, nAlpha);
    CLad_v = sliceDynamic(dc, 'clad', mi, ai, nAlpha);
    CMad_v = sliceDynamic(dc, 'cmad', mi, ai, nAlpha);
    CLp_v  = sliceDynamic(dc, 'clp',  mi, ai, nAlpha);
    CYp_v  = sliceDynamic(dc, 'cyp',  mi, ai, nAlpha);
    CNp_v  = sliceDynamic(dc, 'cnp',  mi, ai, nAlpha);
    CNr_v  = sliceDynamic(dc, 'cnr',  mi, ai, nAlpha);
    CLr_v  = sliceDynamic(dc, 'clr',  mi, ai, nAlpha);

    % Reference index: alpha closest to 0
    [~, i0]  = min(abs(alpha));
    CL_ref   = CL0(i0);
    CD_ref   = CD0(i0);

    % =====================================================================
    %  ELEVATOR DATA  [nDefl x nAlpha]
    % =====================================================================
    fprintf('\n--- Building Elevator table ---\n');
    elevData = buildElevatorData(dc, opts, hasDelta, hasSymFlp, deltaVec, ...
                                  alpha, CL0, CD0, Cm0, XCP0, nAlpha, mi, ai);
    elevData.RawData = buildRawTable(alpha, CL0, CD0, Cm0, CLa_v, CMAa_v, ...
                                      'DATCOM_Static', selectedMach, selectedAlt);
    elevData = appendElevDerivatives(elevData);

    % =====================================================================
    %  AILERON DATA  [nDefl x nAlpha]
    % =====================================================================
    fprintf('\n--- Building Aileron table ---\n');
    ailData = buildAileronData(dc, opts, hasAsyFlp, deltaVec, ...
                                alpha, CL0, CD0, Cm0, nAlpha);
    ailData.RawData = buildRawTable(alpha, CL0, CD0, Cm0, CLa_v, CMAa_v, ...
                                     'DATCOM_Static', selectedMach, selectedAlt);
    ailData = appendAilDerivatives(ailData);

    % =====================================================================
    %  RUDDER DATA  [nDefl x nBeta]
    % =====================================================================
    fprintf('\n--- Building Rudder table ---\n');
    rudData = buildRudderData(opts, CYb_v, CNb_v, CLb_v, i0);

    % =====================================================================
    %  STABILITY DERIVATIVES  (scalars at alpha~0)
    % =====================================================================
    fprintf('\n--- Building StabilityDerivatives ---\n');
    stab = buildStabDerivs(CLa_v, CMAa_v, CLq_v, CMq_v, CLad_v, CMad_v, ...
                            CYb_v, CYp_v, CNb_v, CNp_v, CNr_v, CLb_v, CLp_v, CLr_v, ...
                            CL_ref, CD_ref, i0, datcomMRC, geometry.MAC);

    % =====================================================================
    %  Pack output struct  (same top-level fields as importAeroData results)
    % =====================================================================
    aeroData.elevatorData         = elevData;
    aeroData.rudderData           = rudData;
    aeroData.aileronData          = ailData;
    aeroData.stabilityDerivatives = stab;

    % Convenience geometry (SI)
    if toSI
        aeroData.geometry.Span = safeGet(dc,'blref',geometry.Span/FT2M) * FT2M;
        aeroData.geometry.Area = safeGet(dc,'sref', geometry.Area/FT2M^2) * FT2M^2;
        aeroData.geometry.MAC  = safeGet(dc,'cbar', geometry.MAC/FT2M) * FT2M;
    else
        aeroData.geometry.Span = safeGet(dc,'blref', geometry.Span);
        aeroData.geometry.Area = safeGet(dc,'sref',  geometry.Area);
        aeroData.geometry.MAC  = safeGet(dc,'cbar',  geometry.MAC);
    end
    if aeroData.geometry.Area > 0
        aeroData.geometry.AR = aeroData.geometry.Span^2 / aeroData.geometry.Area;
    end
    aeroData.geometry.Units   = 'm';
    aeroData.source           = datcomFile;
    aeroData.selectedMach     = selectedMach;
    aeroData.selectedAltitude = selectedAlt;

    printSummary(aeroData, alpha, elevData, rudData, ailData);
end


% =========================================================================
%  ELEVATOR BUILDER
% =========================================================================

function d = buildElevatorData(dc, opts, hasDelta, hasSymFlp, deltaVec, ...
                                 alpha, CL0, CD0, Cm0, XCP0, nAlpha, mi, ai)
    d.ControlSurface = 'Elevator';
    d.Alpha          = alpha;
    d.Beta           = 0;

    if hasDelta
        elevDeltas = deltaVec(:);
        nDefl = length(elevDeltas);
        fprintf('  DELTA card: %d deflections.\n', nDefl);
        d.ControlDeflections = elevDeltas;
        d.CL  = extractDeltaTable(dc, 'cl',  mi, ai, nAlpha, nDefl);
        d.CD  = extractDeltaTable(dc, 'cd',  mi, ai, nAlpha, nDefl);
        d.Cm  = extractDeltaTable(dc, 'cm',  mi, ai, nAlpha, nDefl);
        d.XCP = extractDeltaTable(dc, 'xcp', mi, ai, nAlpha, nDefl);
        d.CY  = zeros(nDefl, nAlpha);
        d.Cl  = zeros(nDefl, nAlpha);
        d.Cn  = zeros(nDefl, nAlpha);

    elseif hasSymFlp
        elevDeltas = pickDeltas(opts.ElevatorDeltas, deltaVec);
        nDefl = length(elevDeltas);
        fprintf('  SYMFLP card: synthesising %d-deflection table.\n', nDefl);
        dCL = getIncr(dc, 'dcl_sym', nAlpha);
        dCD = getIncr(dc, 'dcd_sym', nAlpha);
        dCm = getIncr(dc, 'dcm_sym', nAlpha);
        d.ControlDeflections = elevDeltas;
        d.CL  = buildTable(CL0, dCL, elevDeltas);
        d.CD  = buildTable(CD0, dCD, elevDeltas);
        d.Cm  = buildTable(Cm0, dCm, elevDeltas);
        d.XCP = repmat(XCP0, nDefl, 1);
        d.CY  = zeros(nDefl, nAlpha);
        d.Cl  = zeros(nDefl, nAlpha);
        d.Cn  = zeros(nDefl, nAlpha);

    elseif ~isempty(opts.CLde_perDeg) && ~isempty(opts.Cmde_perDeg)
        elevDeltas = pickDeltas(opts.ElevatorDeltas, deltaVec);
        nDefl = length(elevDeltas);
        fprintf('  User-provided CLde=%.4f, Cmde=%.4f: %d deflections.\n', ...
            opts.CLde_perDeg, opts.Cmde_perDeg, nDefl);
        CLde = repmat(opts.CLde_perDeg, 1, nAlpha);
        Cmde = repmat(opts.Cmde_perDeg, 1, nAlpha);
        CDde = repmat(opts.CDde_perDeg, 1, nAlpha);
        d.ControlDeflections = elevDeltas;
        d.CL  = buildTable(CL0, CLde, elevDeltas);
        d.CD  = buildTable(CD0, CDde, elevDeltas);
        d.Cm  = buildTable(Cm0, Cmde, elevDeltas);
        d.XCP = repmat(XCP0, nDefl, 1);
        d.CY  = zeros(nDefl, nAlpha);
        d.Cl  = zeros(nDefl, nAlpha);
        d.Cn  = zeros(nDefl, nAlpha);

    else
        warning('importDatcomData:noElevator', ...
            ['No elevator data found (no DELTA/SYMFLP card, no CLde_perDeg/Cmde_perDeg). \n' ...
             'Elevator will have no effect. Supply ''CLde_perDeg'' and ''Cmde_perDeg''.']);
        d.ControlDeflections = 0;
        d.CL  = CL0;
        d.CD  = CD0;
        d.Cm  = Cm0;
        d.XCP = XCP0;
        d.CY  = zeros(1, nAlpha);
        d.Cl  = zeros(1, nAlpha);
        d.Cn  = zeros(1, nAlpha);
    end
end


% =========================================================================
%  AILERON BUILDER
% =========================================================================

function d = buildAileronData(dc, opts, hasAsyFlp, deltaVec, ...
                                alpha, CL0, CD0, Cm0, nAlpha)
    d.ControlSurface = 'Aileron';
    d.Alpha          = alpha;
    d.Beta           = 0;

    if hasAsyFlp
        ailDeltas = pickDeltas(opts.AileronDeltas, deltaVec);
        nDefl = length(ailDeltas);
        fprintf('  ASYFLP card: synthesising %d-deflection table.\n', nDefl);
        dCl = getIncr(dc, 'dcl_asy', nAlpha);
        dCn = getIncr(dc, 'dcn_asy', nAlpha);
        d.ControlDeflections = ailDeltas;
        d.Cl  = buildTable(zeros(1,nAlpha), dCl, ailDeltas);
        d.Cn  = buildTable(zeros(1,nAlpha), dCn, ailDeltas);
        d.CY  = zeros(nDefl, nAlpha);
        d.CL  = repmat(CL0, nDefl, 1);
        d.CD  = repmat(CD0, nDefl, 1);
        d.Cm  = repmat(Cm0, nDefl, 1);

    elseif ~isempty(opts.Clda_perDeg)
        ailDeltas = pickDeltas(opts.AileronDeltas, deltaVec);
        nDefl = length(ailDeltas);
        fprintf('  User-provided Clda=%.5f: %d deflections.\n', opts.Clda_perDeg, nDefl);
        Clda = repmat(opts.Clda_perDeg, 1, nAlpha);
        Cnda = repmat(opts.Cnda_perDeg, 1, nAlpha);
        CYda = repmat(opts.CYda_perDeg, 1, nAlpha);
        d.ControlDeflections = ailDeltas;
        d.Cl  = buildTable(zeros(1,nAlpha), Clda, ailDeltas);
        d.Cn  = buildTable(zeros(1,nAlpha), Cnda, ailDeltas);
        d.CY  = buildTable(zeros(1,nAlpha), CYda, ailDeltas);
        d.CL  = repmat(CL0, nDefl, 1);
        d.CD  = repmat(CD0, nDefl, 1);
        d.Cm  = repmat(Cm0, nDefl, 1);

    else
        warning('importDatcomData:noAileron', ...
            ['No aileron data found (no ASYFLP card, no Clda_perDeg). \n' ...
             'Ailerons will have no effect. Supply ''Clda_perDeg''.']);
        ailDeltas = pickDeltas(opts.AileronDeltas, deltaVec);
        nDefl = length(ailDeltas);
        d.ControlDeflections = ailDeltas;
        d.Cl  = zeros(nDefl, nAlpha);
        d.Cn  = zeros(nDefl, nAlpha);
        d.CY  = zeros(nDefl, nAlpha);
        d.CL  = repmat(CL0, nDefl, 1);
        d.CD  = repmat(CD0, nDefl, 1);
        d.Cm  = repmat(Cm0, nDefl, 1);
    end
end


% =========================================================================
%  RUDDER BUILDER
%  Synthesises [nDefl x nBeta] table from CYb/CNb background + user dr slope.
%  Format matches importAeroData 'Rudder' exactly (Beta is the sweep axis).
% =========================================================================

function d = buildRudderData(opts, CYb_v, CNb_v, CLb_v, i0)
    if opts.CYdr_perDeg == 0 && opts.Cndr_perDeg == 0
        warning('importDatcomData:noRudder', ...
            ['Rudder derivatives are zero (DATCOM cannot compute rudder). \n' ...
             'Supply ''CYdr_perDeg'' and ''Cndr_perDeg'' from external source.']);
    end

    rudDeltas = pickDeltas(opts.RudderDeltas, []);
    betaSweep = opts.BetaSweep(:);
    nDefl = length(rudDeltas);
    nBeta = length(betaSweep);

    % Background: CY/Cn/Cl at dr=0 from stability derivatives at alpha~0
    CY_bg = CYb_v(i0) * betaSweep';   % [1 x nBeta]
    Cn_bg = CNb_v(i0) * betaSweep';
    Cl_bg = CLb_v(i0) * betaSweep';

    % Rudder increment: constant across beta (linear in dr)
    CYdr_row = repmat(opts.CYdr_perDeg, 1, nBeta);
    Cndr_row = repmat(opts.Cndr_perDeg, 1, nBeta);
    Cldr_row = repmat(opts.Cldr_perDeg, 1, nBeta);

    d.ControlSurface     = 'Rudder';
    d.ControlDeflections = rudDeltas;          % [nDefl x 1]
    d.Beta               = betaSweep;          % [nBeta x 1]  sweep axis
    d.Alpha              = 0;                  % scalar, not swept
    d.CY = buildTable(CY_bg, CYdr_row, rudDeltas);   % [nDefl x nBeta]
    d.Cn = buildTable(Cn_bg, Cndr_row, rudDeltas);
    d.Cl = buildTable(Cl_bg, Cldr_row, rudDeltas);
    d.CL = zeros(nDefl, nBeta);
    d.CD = zeros(nDefl, nBeta);
    d.Cm = zeros(nDefl, nBeta);

    % RawData: beta sweep at dr=0
    d.RawData = table(betaSweep, CY_bg', Cn_bg', Cl_bg', ...
        'VariableNames', {'Beta_deg','CY','Cn','Cl'});

    d = appendRudDerivatives(d);

    fprintf('  Rudder: %d deflections x %d beta (CYdr=%.4f, Cndr=%.4f /deg).\n', ...
        nDefl, nBeta, opts.CYdr_perDeg, opts.Cndr_perDeg);
end


% =========================================================================
%  STABILITY DERIVATIVE BUILDER
% =========================================================================

function s = buildStabDerivs(CLa_v, CMAa_v, CLq_v, CMq_v, CLad_v, CMad_v, ...
                               CYb_v, CYp_v, CNb_v, CNp_v, CNr_v, CLb_v, CLp_v, CLr_v, ...
                               CL_ref, CD_ref, i0, datcomMRC, MAC)
    s = struct();

    % -- Longitudinal --
    s.CLa  = CLa_v(i0);
    s.Cma  = CMAa_v(i0);
    s.CLq  = CLq_v(i0);
    s.Cmq  = CMq_v(i0);
    s.CLad = CLad_v(i0);
    s.Cmad = CMad_v(i0);

    % Speed derivatives: estimated from flight mechanics (M << 1 assumption)
    %   Cxu = -2*CD0  (drag varies as V^2 → slope of CX vs Mach at trim)
    %   Czu = -2*CL0  (lift varies as V^2)
    %   Cxa ~ -CL0    (CX w.r.t alpha at small angle: dCX/dalpha ~ -CL)
    %   Cmu = 0       (compressibility term, negligible at M < 0.3)
    s.Cxu = -2 * CD_ref;
    s.Cxa = -CL_ref;
    s.Czu = -2 * CL_ref;
    s.Cmu = 0;

    % -- Lateral --
    s.CYb = CYb_v(i0);
    s.CYp = CYp_v(i0);
    s.CYr = 0;            % not in standard DATCOM output
    s.Clb = CLb_v(i0);
    s.Clp = CLp_v(i0);
    s.Clr = CLr_v(i0);
    s.Cnb = CNb_v(i0);
    s.Cnp = CNp_v(i0);
    s.Cnr = CNr_v(i0);

    % -- Neutral point --
    % NP (from nose) = datcomMRC - (Cma/CLa) * MAC
    if s.CLa ~= 0
        s.NeutralPoint_m = datcomMRC - (s.Cma / s.CLa) * MAC;
    else
        s.NeutralPoint_m = datcomMRC;
        warning('importDatcomData:zeroCLa', ...
            'CLa=0 at alpha~0. NeutralPoint_m set equal to datcomMRC.');
    end

    % -- Stability flags (same logic as importAeroData) --
    s.pitchStable = s.Cma < 0;   % nose-down restoring
    s.yawStable   = s.Cnb > 0;   % weathercock stability
    s.rollStable  = s.Clb < 0;   % dihedral effect
end


% =========================================================================
%  CONTROL EFFECTIVENESS SCALARS
%  Slope of coefficient vs deflection at reference condition (alpha~0 / beta~0).
%  Same polyfit approach as importAeroData.appendControlDerivatives.
% =========================================================================

function data = appendElevDerivatives(data)
    [~, i0] = min(abs(data.Alpha));
    defl = data.ControlDeflections;
    fprintf('  Elevator derivatives at alpha=%.1f deg:\n', data.Alpha(i0));
    data.CLde_perDeg = computeSlope(defl, data.CL(:, i0), 'CLde');
    data.Cmde_perDeg = computeSlope(defl, data.Cm(:, i0), 'Cmde');
end


function data = appendAilDerivatives(data)
    [~, i0] = min(abs(data.Alpha));
    defl = data.ControlDeflections;
    fprintf('  Aileron derivatives at alpha=%.1f deg:\n', data.Alpha(i0));
    data.Clda_perDeg = computeSlope(defl, data.Cl(:, i0), 'Clda');
    data.Cnda_perDeg = computeSlope(defl, data.Cn(:, i0), 'Cnda');
end


function data = appendRudDerivatives(data)
    [~, iB0] = min(abs(data.Beta));
    defl = data.ControlDeflections;
    fprintf('  Rudder derivatives at beta=%.1f deg:\n', data.Beta(iB0));
    data.CYdr_perDeg = computeSlope(defl, data.CY(:, iB0), 'CYdr');
    data.Cndr_perDeg = computeSlope(defl, data.Cn(:, iB0), 'Cndr');
end


function slope = computeSlope(x, y, label)
% Linear regression slope via polyfit -- identical to importAeroData.
    x = double(x(:)); y = double(y(:));
    if length(unique(x)) < 2
        slope = 0;
        fprintf('    %s = 0.00000 /deg  (single deflection point)\n', label);
        return;
    end
    p     = polyfit(x, y, 1);
    slope = p(1);
    fprintf('    %s = %+.5f /deg  (%d points, %.0f to %.0f deg)\n', ...
        label, slope, length(x), min(x), max(x));
end


% =========================================================================
%  STATIC / DYNAMIC DATA SLICERS
% =========================================================================

function v = sliceStatic(dc, field, mi, ai, nAlpha)
% Extract [1 x nAlpha] from [nAlpha x nMach x nAlt] static array.
    raw = safeGet(dc, field, []);
    if isempty(raw), v = zeros(1, nAlpha); return; end
    sz = size(raw);
    if ndims(raw) >= 3 && sz(1) == nAlpha
        v = reshape(raw(:, mi, ai), 1, nAlpha);
    elseif ismatrix(raw) && sz(1) == nAlpha
        v = reshape(raw(:, min(mi, sz(2))), 1, nAlpha);
    elseif numel(raw) == nAlpha
        v = reshape(raw, 1, nAlpha);
    else
        v = zeros(1, nAlpha);
    end
    v(isnan(v)) = 0;
end


function v = sliceDynamic(dc, field, mi, ai, nAlpha)
% Like sliceStatic but forward-fills NaN gaps (common in DAMP tables).
    v = sliceStatic(dc, field, mi, ai, nAlpha);
    for k = 2:nAlpha
        if isnan(v(k)), v(k) = v(k-1); end
    end
    v(isnan(v)) = 0;
end


function T = extractDeltaTable(dc, field, mi, ai, nAlpha, nDelta)
% Extract [nDelta x nAlpha] from 6D DELTA-indexed array.
    raw = safeGet(dc, field, []);
    T   = zeros(nDelta, nAlpha);
    if isempty(raw), return; end
    sz = size(raw); nd = ndims(raw);
    if nd >= 6 && sz(6) >= nDelta
        for d = 1:nDelta, T(d,:) = raw(:, mi, ai, 1, 1, d)'; end
    elseif nd >= 4 && sz(end) >= nDelta
        for d = 1:nDelta
            if nd==4,     T(d,:) = raw(:, mi, ai, d)';
            elseif nd==5, T(d,:) = raw(:, mi, ai, 1, d)'; end
        end
    else
        T = repmat(sliceStatic(dc, field, mi, ai, nAlpha), nDelta, 1);
    end
end


function d = getIncr(dc, field, nAlpha)
% Get incremental derivative vector for SYMFLP/ASYFLP tables.
    raw = safeGet(dc, field, []);
    if isempty(raw), d = zeros(1, nAlpha); return; end
    if numel(raw) == nAlpha, d = reshape(raw, 1, nAlpha);
    else, d = repmat(raw(1), 1, nAlpha); end
end


function T = buildTable(base, deriv, deltas)
% T(i,:) = base + deltas(i) * deriv    [nDefl x n]
    if isscalar(deriv), deriv = repmat(deriv, 1, length(base)); end
    T = repmat(base, length(deltas), 1) + deltas(:) * deriv;
end


function deltas = pickDeltas(userDeltas, datcomDeltas)
    if ~isempty(userDeltas),  deltas = userDeltas(:);
    elseif ~isempty(datcomDeltas), deltas = datcomDeltas(:);
    else, deltas = (-20:5:20)'; end
end


function idx = pickIndex(vec, userVal, name, label)
    vec = vec(:);
    if length(vec) == 1
        idx = 1;
    elseif ~isempty(userVal)
        [~, idx] = min(abs(vec - userVal));
        fprintf('  %s: requested %.3f, using %.3f.\n', label, userVal, vec(idx));
    else
        idx = 1;
        if length(vec) > 1
            warning('importDatcomData:multiple%s', ...
                'Multiple %s values: %s. Using first (%.3f). Specify ''%s'' to change.', ...
                name, mat2str(vec'), vec(1), name);
        end
    end
end


function dc = replaceMissing99999(dc)
    fn = fieldnames(dc);
    for i = 1:length(fn)
        v = dc.(fn{i});
        if isnumeric(v) && numel(v) > 1
            v(v == 99999)  = 0;
            v(v == -99999) = 0;
            dc.(fn{i}) = v;
        elseif isstruct(v)
            dc.(fn{i}) = replaceMissing99999(v);
        end
    end
end


function v = safeGet(s, field, default)
    if isfield(s, field) && ~isempty(s.(field)), v = s.(field);
    else, v = default; end
end


% =========================================================================
%  RAW DATA TABLE  (matches .RawData spirit from importAeroData)
% =========================================================================

function T = buildRawTable(alpha, CL, CD, Cm, CLa, CMA, source, mach, alt)
    nA    = length(alpha);
    srcCol = repmat({sprintf('%s M=%.2f Alt=%.0fft', source, mach, alt)}, nA, 1);
    T = table(alpha, CL(:), CD(:), Cm(:), CLa(:), CMA(:), srcCol, ...
        'VariableNames', {'alpha_deg','CL','CD','Cm','CLa_perDeg','Cma_perDeg','Source'});
end


% =========================================================================
%  VALIDATION
% =========================================================================

function validateInputs(datcomFile, geometry, datcomMRC)
    if ~ischar(datcomFile) && ~isstring(datcomFile)
        error('importDatcomData:badInput', 'datcomFile must be a char or string.');
    end
    if ~isfile(datcomFile)
        error('importDatcomData:fileNotFound', ...
            'DATCOM file not found: %s\nCheck the path in setupData_DATCOM.mlx Section 3.', ...
            datcomFile);
    end
    if ~isstruct(geometry)
        error('importDatcomData:badGeometry', ...
            'geometry must be a struct (from Section 1 of setupData_DATCOM.mlx).');
    end
    for f = {'MAC','Span','Area'}
        if ~isfield(geometry, f{1})
            error('importDatcomData:missingGeomField', ...
                'geometry.%s is required. Run Section 1 first.', f{1});
        end
    end
    if ~isnumeric(datcomMRC) || ~isscalar(datcomMRC) || datcomMRC <= 0
        error('importDatcomData:badMRC', ...
            'datcomMRC must be a positive scalar [m] matching XCG= in your DATCOM deck.');
    end
end


% =========================================================================
%  SUMMARY PRINT  (mirrors printStabSummary from importAeroData exactly)
% =========================================================================

function printSummary(aeroData, alpha, elevData, rudData, ailData)
    s = aeroData.stabilityDerivatives;
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
    fprintf('  Flags  --  Pitch: %s   Yaw: %s   Roll: %s\n', ...
        flag2str(s.pitchStable), flag2str(s.yawStable), flag2str(s.rollStable));
    fprintf('--------------------------------------------------------------------\n\n');

    fprintf('--- Control surface summary ---\n');
    fprintf('  Source:   %s\n',   aeroData.source);
    fprintf('  Mach:     %.3f    Alt: %.0f ft\n', ...
        aeroData.selectedMach, aeroData.selectedAltitude);
    fprintf('  Alpha:    [%s] deg  (%d pts)\n', ...
        strtrim(num2str(alpha', '%6.1f')), length(alpha));
    fprintf('  Elevator: %d deflections x %d alpha  |  CLde=%+.5f  Cmde=%+.5f /deg\n', ...
        length(elevData.ControlDeflections), length(elevData.Alpha), ...
        elevData.CLde_perDeg, elevData.Cmde_perDeg);
    fprintf('  Rudder:   %d deflections x %d beta   |  CYdr=%+.5f  Cndr=%+.5f /deg\n', ...
        length(rudData.ControlDeflections), length(rudData.Beta), ...
        rudData.CYdr_perDeg, rudData.Cndr_perDeg);
    fprintf('  Aileron:  %d deflections x %d alpha  |  Clda=%+.5f  Cnda=%+.5f /deg\n', ...
        length(ailData.ControlDeflections), length(ailData.Alpha), ...
        ailData.Clda_perDeg, ailData.Cnda_perDeg);
    fprintf('--------------------------------------------------------------------\n\n');
end


function s = flag2str(flag)
    if flag, s = 'STABLE'; else, s = 'UNSTABLE'; end
end
