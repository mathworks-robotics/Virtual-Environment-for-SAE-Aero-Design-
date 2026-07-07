%% 
% =========================================================================
% Initialization.m
%
% CORE FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% This file sets the fixed initial conditions for the SAE Aero Design
% Simulation Challenge. All teams use identical initial conditions so
% that simulation results are directly comparable across entries.
%
% HOW THIS FILE IS CALLED:
%   This file is set as the InitFcn callback of SimulationChallenge.slx.
%   It runs automatically every time the Simulink model is opened or
%   executed, ensuring buses and initial conditions are always loaded.
%   You can also run it manually from the Command Window: >> Initialization
%
% WHAT THIS FILE SETS:
%   — Fixed start position, attitude, and velocity (same for all teams)
%   — Simulink bus object definitions (ACStatesBus, PilotInputsBus, etc.)
%   — NED frame initial position vector for the 6-DOF block
%
% WHAT THIS FILE DOES NOT SET:
%   — CG body position (set in geometry section of your setup file)
%   — Propulsion arm location (set in geometry section of your setup file)
%   — Input device mode / pilotInput (set in your setup file, Section 5)
%
% If you believe there is a bug or need a change, contact your team
% advisor or the MathWorks Aerospace Education Team.
% =========================================================================
%
%
% ALTITUDE CONVENTION:
%   Altitude_MSL — height above mean sea level (WGS84 ellipsoid)
%                  Used by: ISA atmosphere block, 6-DOF NED frame (z = -Altitude_MSL)
%   Altitude_AGL — height above ground level at KVNY field
%                  Used by: mission logic, landing detection, obstacle clearance
%   Relationship during simulation:
%                  Altitude_AGL = Altitude_MSL_current - initial.Altitude_MSL
%                  At start: Altitude_AGL = 0 (aircraft on runway)
%
% FIXED START CONDITIONS (same for all teams):
%   Position  — runway threshold, KVNY
%   Heading   — -135 deg (runway heading)
%   Pitch     — 7.47 deg (typical ground attitude with main gear on ground)
%   Roll/Yaw  — 0 (wings level, aligned with runway)
%   Velocity  — near-zero (u = 0.1 m/s to avoid singularity at startup)
%   Ang rates — 0 (stationary on ground)
%
% =========================================================================


%% Aircraft Orientation and Angular Rates
% Fixed runway start attitude. All angles in radians.

initial.Heading  = deg2rad(-135);    % [rad]  Runway heading (-135 deg at KVNY)
initial.Roll    = 0;                % [rad]  Wings level on runway
initial.Pitch   = 0.1303;          % [rad]  Ground attitude (~7.5 deg, nose-up with gear)
initial.Yaw     = initial.Heading;  % [rad]  Aligned with runway heading at start

initial.p = 0;                      % [rad/s]  Roll rate  — stationary on ground
initial.q = 0.0001;                      % [rad/s]  Pitch rate — stationary on ground
initial.r = 00.0001;                      % [rad/s]  Yaw rate   — stationary on ground

% Initial velocity components in body frame [m/s]
% u = 0.1 m/s (near-zero) avoids a divide-by-zero singularity in the
% aerodynamic force computation at t = 0. This is not a launch velocity.
initial.u = 0.1;                    % [m/s]  Forward velocity (body x-axis)
initial.v = 0;                      % [m/s]  Lateral velocity (body y-axis)
initial.w = 0.001;                      % [m/s]  Vertical velocity (body z-axis, positive down)


%% Initial Position — Van Nuys Airport (KVNY)
% All teams start from the same runway threshold position.
% Field elevation (243.8 m) is used for ISA atmosphere initialisation —
% a 2.3% density difference vs sea level that meaningfully affects
% stall speed and available thrust estimates.

initial.Latitude     = 0; %env.Location.Latitude_deg;  % [deg]  KVNY runway threshold latitude
initial.Longitude    = 0; %env.Location.Longitude_deg; % [deg]  KVNY runway threshold longitude
initial.Altitude_MSL = 0;                         % [m]
                                                    %       Used by ISA atmosphere and NED frame init
initial.Altitude_AGL =  0;                   % [m]    Height above ground at start (on runway)
                                             %        Used by mission logic and landing detection
                                             %        During simulation:
                                             %        Altitude_AGL = Altitude_MSL_current
                                             %                       - initial.Altitude_MSL

% Initial inertial position vector [x, y, z] in NED frame
% NED origin coincides with the runway threshold (start position).
% The Simulink flat-earth block uses initial.Latitude, initial.Longitude,
% and initial.Altitude_MSL directly — no separate origin_ variables needed.
% Aircraft starts at the NED origin — x=North, y=East, z=Down
initial.CGInertial.X = 0;                     % [m]  North from runway threshold
initial.CGInertial.Y = 0;                     % [m]  East  from runway threshold
initial.CGInertial.Z = -initial.Altitude_MSL; % [m]  Down  (negative = above MSL datum)

initial.Xe = [initial.CGInertial.X, ...
              initial.CGInertial.Y, ...
              initial.CGInertial.Z];      % [m]  Initial position vector for 6-DOF block


