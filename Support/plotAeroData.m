% =========================================================================
% plotAeroData.m
%
% SUPPORT FILE — DO NOT MODIFY
% -------------------------------------------------------------------------
% Generates aerodynamic coefficient plots from imported data tables.
% Called from Section 3 of setupData_Manual.m after importAeroData and
% extractStabilityDerivatives are complete.
%
% Each control surface gets its own figure with a layout matched to the
% aerodynamically meaningful axes for that surface:
%
%   Elevator — longitudinal: CL, CD, Cm vs alpha, each deflection as a series
%   Aileron  — lateral:      Cl, CL, CD vs alpha, each deflection as a series
%   Rudder   — directional:  Cn, CY vs beta,      each deflection as a series
%
% PURPOSE:
%   Sanity-check your aerodynamic data before running the simulation.
%   A physically unreasonable slope, sign flip, or missing stall break
%   is much easier to catch in a plot than in a table.
%
% SYNTAX:
%   plotAeroData(aeroData)             % plot all three surfaces
%   plotAeroData(aeroData, 'Elevator') % plot one surface only
%   plotAeroData(aeroData, 'Rudder')
%   plotAeroData(aeroData, 'Aileron')
%
% INPUT:
%   aeroData — struct from importAeroData + extractStabilityDerivatives
%              Must contain .elevatorData, .rudderData, .aileronData
%
% =========================================================================

function plotAeroData(aeroData, surface)

    if nargin < 2
        surface = 'All';
    end

    switch lower(surface)
        case {'all', ''}
            plotElevator(aeroData.elevatorData);
            plotAileron(aeroData.aileronData);
            plotRudder(aeroData.rudderData);
        case 'elevator'
            plotElevator(aeroData.elevatorData);
        case 'aileron'
            plotAileron(aeroData.aileronData);
        case 'rudder'
            plotRudder(aeroData.rudderData);
        otherwise
            error('plotAeroData:badInput', ...
                'surface must be ''Elevator'', ''Aileron'', ''Rudder'', or ''All''.');
    end
end


% =========================================================================
%% ELEVATOR — CL, CD, Cm vs alpha  (1 series per deflection setting)
% =========================================================================
function plotElevator(elev)

    defl   = elev.ControlDeflections;
    alpha  = elev.Alpha;
    nDefl  = length(defl);
    colors = lines(nDefl);

    % β=0 index for all plots
    [~, iB0] = min(abs(elev.Beta));

    fig = figure('Name', 'Elevator Aerodynamics', ...
                 'NumberTitle', 'off', ...
                 'Position', [100 100 1100 380]);

    % ── Subplot 1: CL vs alpha ──────────────────────────────────────────
    ax1 = subplot(1, 3, 1);
    hold(ax1, 'on'); grid(ax1, 'on');
    for i = 1:nDefl
        CL_slice = squeeze(elev.CL(i, :, iB0));
        plot(ax1, alpha, CL_slice, '-o', ...
            'Color', colors(i,:), 'LineWidth', 1.6, ...
            'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
    end
    xlabel(ax1, '\alpha (deg)', 'FontSize', 10);
    ylabel(ax1, 'C_L',         'FontSize', 10);
    title(ax1,  'C_L vs \alpha', 'FontSize', 11, 'FontWeight', 'bold');
    legend(ax1, deflLegend('Elevator', defl), 'Location', 'northwest', 'FontSize', 8);
    hold(ax1, 'off');

    % ── Subplot 2: CD vs alpha ──────────────────────────────────────────
    ax2 = subplot(1, 3, 2);
    hold(ax2, 'on'); grid(ax2, 'on');
    % Prefer CDv (viscous only) if available, fall back to CD
    if isfield(elev, 'CDv')
        cdField = 'CDv'; cdLabel = 'C_{Dv}';
        titleNote = '(viscous — source of CD_0)';
    else
        cdField = 'CD';  cdLabel = 'C_D';
        titleNote = '(total drag)';
    end
    for i = 1:nDefl
        CD_slice = squeeze(elev.(cdField)(i, :, iB0));
        plot(ax2, alpha, CD_slice, '-o', ...
            'Color', colors(i,:), 'LineWidth', 1.6, ...
            'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
    end
    xlabel(ax2, '\alpha (deg)', 'FontSize', 10);
    ylabel(ax2, cdLabel,        'FontSize', 10);
    title(ax2,  [cdLabel ' vs \alpha  ' titleNote], 'FontSize', 11, 'FontWeight', 'bold');
    legend(ax2, deflLegend('Elevator', defl), 'Location', 'best', 'FontSize', 8);
    hold(ax2, 'off');

    % ── Subplot 3: Cm vs alpha ──────────────────────────────────────────
    ax3 = subplot(1, 3, 3);
    hold(ax3, 'on'); grid(ax3, 'on');
    yline(ax3, 0, '--k', 'LineWidth', 0.8);     % zero-moment reference
    for i = 1:nDefl
        Cm_slice = squeeze(elev.Cm(i, :, iB0));
        plot(ax3, alpha, Cm_slice, '-o', ...
            'Color', colors(i,:), 'LineWidth', 1.6, ...
            'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
    end
    xlabel(ax3, '\alpha (deg)', 'FontSize', 10);
    ylabel(ax3, 'C_m',          'FontSize', 10);
    title(ax3,  'C_m vs \alpha  (Cm\alpha < 0 = stable)', ...
          'FontSize', 11, 'FontWeight', 'bold');
    legend(ax3, deflLegend('Elevator', defl), 'Location', 'best', 'FontSize', 8);
    hold(ax3, 'off');

    sgtitle(fig, 'Elevator Data — \beta = 0°', ...
            'FontSize', 13, 'FontWeight', 'bold');
end


% =========================================================================
%% AILERON — Cl, CL, CD vs alpha  (1 series per deflection setting)
% =========================================================================
function plotAileron(ailer)

    defl   = ailer.ControlDeflections;
    alpha  = ailer.Alpha;
    nDefl  = length(defl);
    colors = lines(nDefl);

    [~, iB0] = min(abs(ailer.Beta));

    fig = figure('Name', 'Aileron Aerodynamics', ...
                 'NumberTitle', 'off', ...
                 'Position', [150 150 1100 380]);

    % ── Subplot 1: Cl vs alpha (rolling moment — primary aileron output) ─
    ax1 = subplot(1, 3, 1);
    hold(ax1, 'on'); grid(ax1, 'on');
    yline(ax1, 0, '--k', 'LineWidth', 0.8);
    for i = 1:nDefl
        Cl_slice = squeeze(ailer.Cl(i, :, iB0));
        plot(ax1, alpha, Cl_slice, '-o', ...
            'Color', colors(i,:), 'LineWidth', 1.6, ...
            'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
    end
    xlabel(ax1, '\alpha (deg)', 'FontSize', 10);
    ylabel(ax1, 'C_l (rolling moment)', 'FontSize', 10);
    title(ax1,  'C_l vs \alpha', 'FontSize', 11, 'FontWeight', 'bold');
    legend(ax1, deflLegend('Aileron', defl), 'Location', 'best', 'FontSize', 8);
    hold(ax1, 'off');

    % ── Subplot 2: CL vs alpha ──────────────────────────────────────────
    ax2 = subplot(1, 3, 2);
    hold(ax2, 'on'); grid(ax2, 'on');
    for i = 1:nDefl
        CL_slice = squeeze(ailer.CL(i, :, iB0));
        plot(ax2, alpha, CL_slice, '-o', ...
            'Color', colors(i,:), 'LineWidth', 1.6, ...
            'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
    end
    xlabel(ax2, '\alpha (deg)', 'FontSize', 10);
    ylabel(ax2, 'C_L',          'FontSize', 10);
    title(ax2,  'C_L vs \alpha', 'FontSize', 11, 'FontWeight', 'bold');
    legend(ax2, deflLegend('Aileron', defl), 'Location', 'northwest', 'FontSize', 8);
    hold(ax2, 'off');

    % ── Subplot 3: CD vs alpha ──────────────────────────────────────────
    ax3 = subplot(1, 3, 3);
    hold(ax3, 'on'); grid(ax3, 'on');
    for i = 1:nDefl
        CD_slice = squeeze(ailer.CD(i, :, iB0));
        plot(ax3, alpha, CD_slice, '-o', ...
            'Color', colors(i,:), 'LineWidth', 1.6, ...
            'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
    end
    xlabel(ax3, '\alpha (deg)', 'FontSize', 10);
    ylabel(ax3, 'C_D',          'FontSize', 10);
    title(ax3,  'C_D vs \alpha  (aileron drag penalty)', ...
          'FontSize', 11, 'FontWeight', 'bold');
    legend(ax3, deflLegend('Aileron', defl), 'Location', 'best', 'FontSize', 8);
    hold(ax3, 'off');

    sgtitle(fig, 'Aileron Data — \beta = 0°', ...
            'FontSize', 13, 'FontWeight', 'bold');
end


% =========================================================================
%% RUDDER — Cn, CY vs beta  (1 series per deflection setting)
% =========================================================================
function plotRudder(rudd)

    defl   = rudd.ControlDeflections;
    beta   = rudd.Beta;
    nDefl  = length(defl);
    colors = lines(nDefl);

    % alpha=0 index
    [~, iA0] = min(abs(rudd.Alpha));

    fig = figure('Name', 'Rudder Aerodynamics', ...
                 'NumberTitle', 'off', ...
                 'Position', [200 200 780 420]);

    if length(beta) < 2
        % Only β=0 available — plot vs alpha instead with a note
        fprintf(['plotAeroData (Rudder): Only β=0 in data.\n' ...
                 'Showing Cn and CY vs alpha instead of vs beta.\n' ...
                 'Add a beta sweep to Rudder sheet for directional plots.\n']);

        ax1 = subplot(1, 2, 1);
        hold(ax1, 'on'); grid(ax1, 'on');
        yline(ax1, 0, '--k', 'LineWidth', 0.8);
        [~, iB0] = min(abs(rudd.Beta));
        for i = 1:nDefl
            Cn_slice = squeeze(rudd.Cn(i, :, iB0));
            plot(ax1, rudd.Alpha, Cn_slice, '-o', ...
                'Color', colors(i,:), 'LineWidth', 1.6, ...
                'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
        end
        xlabel(ax1, '\alpha (deg)', 'FontSize', 10);
        ylabel(ax1, 'C_n',          'FontSize', 10);
        title(ax1,  'C_n vs \alpha  (β=0 only)', 'FontSize', 11, 'FontWeight', 'bold');
        legend(ax1, deflLegend('Rudder', defl), 'Location', 'best', 'FontSize', 8);
        hold(ax1, 'off');

        ax2 = subplot(1, 2, 2);
        hold(ax2, 'on'); grid(ax2, 'on');
        yline(ax2, 0, '--k', 'LineWidth', 0.8);
        for i = 1:nDefl
            CY_slice = squeeze(rudd.CY(i, :, iB0));
            plot(ax2, rudd.Alpha, CY_slice, '-o', ...
                'Color', colors(i,:), 'LineWidth', 1.6, ...
                'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
        end
        xlabel(ax2, '\alpha (deg)', 'FontSize', 10);
        ylabel(ax2, 'C_Y',          'FontSize', 10);
        title(ax2,  'C_Y vs \alpha  (β=0 only)', 'FontSize', 11, 'FontWeight', 'bold');
        legend(ax2, deflLegend('Rudder', defl), 'Location', 'best', 'FontSize', 8);
        hold(ax2, 'off');

        annStr = sprintf('⚠  Only β=0 in data — add beta sweep for directional derivatives');
        annotation(fig, 'textbox', [0.1 0.01 0.8 0.06], ...
            'String', annStr, 'EdgeColor', [0.9 0.6 0], ...
            'BackgroundColor', [1 0.97 0.8], 'FontSize', 9, 'HorizontalAlignment', 'center');
    else
        % Full beta sweep available — plot vs beta (directionally meaningful)
        ax1 = subplot(1, 2, 1);
        hold(ax1, 'on'); grid(ax1, 'on');
        yline(ax1, 0, '--k', 'LineWidth', 0.8);
        for i = 1:nDefl
            Cn_slice = squeeze(rudd.Cn(i, iA0, :));
            plot(ax1, beta, Cn_slice, '-o', ...
                'Color', colors(i,:), 'LineWidth', 1.6, ...
                'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
        end
        xlabel(ax1, '\beta (deg)', 'FontSize', 10);
        ylabel(ax1, 'C_n',         'FontSize', 10);
        title(ax1,  'C_n vs \beta  (Cn\beta > 0 = yaw stable)', ...
              'FontSize', 11, 'FontWeight', 'bold');
        legend(ax1, deflLegend('Rudder', defl), 'Location', 'best', 'FontSize', 8);
        hold(ax1, 'off');

        ax2 = subplot(1, 2, 2);
        hold(ax2, 'on'); grid(ax2, 'on');
        yline(ax2, 0, '--k', 'LineWidth', 0.8);
        for i = 1:nDefl
            CY_slice = squeeze(rudd.CY(i, iA0, :));
            plot(ax2, beta, CY_slice, '-o', ...
                'Color', colors(i,:), 'LineWidth', 1.6, ...
                'MarkerSize', 4, 'MarkerFaceColor', colors(i,:));
        end
        xlabel(ax2, '\beta (deg)', 'FontSize', 10);
        ylabel(ax2, 'C_Y',         'FontSize', 10);
        title(ax2,  'C_Y vs \beta  (\alpha = 0°)', ...
              'FontSize', 11, 'FontWeight', 'bold');
        legend(ax2, deflLegend('Rudder', defl), 'Location', 'best', 'FontSize', 8);
        hold(ax2, 'off');
    end

    sgtitle(fig, 'Rudder Data', 'FontSize', 13, 'FontWeight', 'bold');
end


% =========================================================================
%% LOCAL HELPER
% =========================================================================
function entries = deflLegend(surfaceName, deflections)
% Build legend strings: 'Elevator = -6°', 'Elevator = 0°', etc.
    entries = arrayfun(@(d) sprintf('%s = %.0f°', surfaceName, d), ...
        deflections, 'UniformOutput', false);
end
