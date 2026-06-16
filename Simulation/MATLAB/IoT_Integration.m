%% SMART HOME – IOT AND PV OPTIMISATION
clear; clc; close all;

%% ------------------------------------------------
% 1. LOAD DATA
% -------------------------------------------------
data = readtable('final.csv','VariableNamingRule','preserve');
vars = data.Properties.VariableNames;
N = height(data);
time = (1:N)';

% Locate Columns
plug_col = vars(contains(vars,'InteriorEquipment:Electricity') & contains(vars,'Hourly'));
heat_cols = vars(contains(vars,'Ideal Loads Supply Air Total Heating Rate') & contains(vars,'Hourly'));
cool_cols = vars(contains(vars,'Ideal Loads Supply Air Total Cooling Rate') & contains(vars,'Hourly'));
dhw_cols = vars(contains(vars,'Water Use Equipment Heating Rate') & contains(vars,'Hourly') );
light_cols = vars(contains(vars,'InteriorLights:Electricity') & contains(vars,'Hourly') );

%% ------------------------------------------------
% 2. LOAD PVsyst OUTPUT
% -------------------------------------------------
pv = readmatrix('NZEB_Residential_Project - Copy_VC0_HourlyRes_1.CSV');
pv_dc = pv(:,2); pv_dc(isnan(pv_dc)) = 0;
E_system_annual = 8918; % Final result from PVsyst simulation
pv_ac = pv_dc * (E_system_annual / sum(pv_dc));
pv_ac = pv_ac(1:N);

%% ------------------------------------------------
% 3. EXTRACT LOADS & APPLY COPs
% -------------------------------------------------
% Base plug loads
if ~isempty(plug_col)
    plug_e = data.(plug_col{1}) / 3.6e6;
else
    plug_e = zeros(N,1);
end

if ~isempty(light_cols)
    light_e = data.(light_cols{1}) / 3.6e6;
else
    light_e = zeros(N,1);
end

% Convert HVAC Thermal to Electrical
heat_raw = zeros(N,1); cool_raw = zeros(N,1); dhw_raw = zeros(N,1);

for i = 1:length(heat_cols)
    heat_raw = heat_raw + data.(heat_cols{i});
end
for i = 1:length(cool_cols)
    cool_raw = cool_raw + data.(cool_cols{i});
end
for i = 1:length(dhw_cols)
    dhw_raw = dhw_raw + data.(dhw_cols{i});
end

% Efficiency for Heat Pump System
COP_heat = 3.5;
COP_cool = 3;
COP_dhw = 2;

heat_e = (heat_raw / 1000) / COP_heat;
cool_e = (cool_raw / 1000) / COP_cool;
dhw_e  = (dhw_raw  / 1000) / COP_dhw;
hvac_e = heat_e + cool_e + dhw_e;

energy_base = light_e + plug_e + hvac_e;

%% -------------------------------------------------
% 4. IoT OPTIMISATION LOGIC
% -------------------------------------------------
% Occupancy Model
occupied = false(N,1);
for i = 1:N
    h = mod(i-1,24);
    d = floor((i-1)/24);
    day_of_week = mod(d,7);
    % Weekday
    if day_of_week <= 5
        if (h >= 6 && h <= 9) || (h >= 17 && h <= 23)
            occupied(i) = true;
        end
    else
        % Weekend
        if (h >= 8 && h <= 23)
            occupied(i) = true;
        end
    end
end

energy_iot = zeros(N,1);
plug_base_load = min(plug_e);
% aggressive energy saving
hvac_min = quantile(hvac_e, 0.1);

for i = 1:N
    if occupied(i)
        % Prioritise resident comfort
        energy_iot(i) = energy_base(i);
    else
        if pv_ac(i) > (0.3 * max(pv_ac))
            % Active Demand-side Management
            energy_iot(i) = (light_e(i)*0) + (plug_e(i)*0.8) + (hvac_e(i)*1.1);
        else
            % Setback
            energy_iot(i) = (light_e(i)*0) + (plug_e(i)*0.3) + hvac_min;
        end
    end
end

%% -------------------------------------------------
% 5. ENERGY BALANCE & BATTERY SIMULATION (11.06 kWh)
% -------------------------------------------------
battery_cap = 11.0;
charge_eff = 0.95;
discharge_eff = 0.95;

% Run Dual Simulations
[grid_imp_base, grid_exp_base, ~] = battery_engine(energy_base, pv_ac, battery_cap, charge_eff, discharge_eff);
[grid_imp_iot, grid_exp_iot, ~] = battery_engine(energy_iot, pv_ac, battery_cap, charge_eff, discharge_eff);

% Calculate Totals
total_imp_base = sum(grid_imp_base);
total_exp_base = sum(grid_exp_base);
total_imp_iot  = sum(grid_imp_iot);
total_exp_iot  = sum(grid_exp_iot);
self_cons_base = sum(pv_ac) - total_exp_base;
self_cons_iot  = sum(pv_ac) - total_exp_iot;

%% -------------------------------------------------
% 6. PRINT FINAL BALANCE SHEET
% -------------------------------------------------
fprintf('\n---------------------------------------------------------\n');
fprintf('METRIC (Annual kWh)      | BASELINE      | IoT OPTIMIZED \n');
fprintf('---------------------------------------------------------\n');
fprintf('Total House Demand       | %10.2f    | %10.2f \n', sum(energy_base), sum(energy_iot));
fprintf('Total PV Generation      | %10.2f    | %10.2f \n', sum(pv_ac), sum(pv_ac));
fprintf('---------------------------------------------------------\n');
fprintf('GRID IMPORT   | %10.2f    | %10.2f \n', total_imp_base, total_imp_iot);
fprintf('GRID EXPORT   | %10.2f    | %10.2f \n', total_exp_base, total_exp_iot);
fprintf('---------------------------------------------------------\n');
fprintf('Solar Self-Consumption %% | %9.1f%%    | %9.1f%% \n', (self_cons_base/sum(pv_ac))*100, (self_cons_iot/sum(pv_ac))*100);
fprintf('Solar Fraction (Supply) %%| %9.1f%%    | %9.1f%% \n', (self_cons_base/sum(energy_base))*100, (self_cons_iot/sum(energy_iot))*100);
fprintf('---------------------------------------------------------\n');
fprintf('IoT Total Energy Savings : %.2f kWh (%.1f%%)\n', sum(energy_base)-sum(energy_iot), ((sum(energy_base)-sum(energy_iot))/sum(energy_base))*100);
fprintf('---------------------------------------------------------\n');

%% -------------------------------------------------
% 7. PERFORMANCE VISUALISATION
% -------------------------------------------------
% Annual Demand Shifting
figure;
plot(time, movmean(energy_base, 24), 'r', 'LineWidth', 1);
hold on;
plot(time, movmean(energy_iot, 24), 'b', 'LineWidth', 1.2);
title('Annual Load Shifting');
ylabel('kWh');
xlabel('Hour of Year');
legend('Baseline','IoT Optimized');
grid on;

% Seasonal Grid Reliance
figure;
subplot(2,1,1);
seasons = {'Winter','Spring','Summer','Autumn'};
m = 730;
% Winter: Jan(1), Nov(11), Dec(12)
winter_idx = [1:m, (10*m+1):N];
% Spring: Feb(2), Mar(3), Apr(4)
spring_idx = (m+1):(4*m);
% Summer: May(5), Jun(6), Jul(7)
summer_idx = (4*m+1):(7*m);
% Autumn: Aug(8), Sep(9), Oct(10)
autumn_idx = (7*m+1):(10*m);
seas_data = [sum(grid_imp_base(winter_idx)), sum(grid_imp_iot(winter_idx));
    sum(grid_imp_base(spring_idx)), sum(grid_imp_iot(spring_idx));
    sum(grid_imp_base(summer_idx)), sum(grid_imp_iot(summer_idx));
    sum(grid_imp_base(autumn_idx)), sum(grid_imp_iot(autumn_idx))];
bar(seas_data);
set(gca, 'XTickLabel', seasons);
title('Seasonal Grid Import');
ylabel('kWh');
legend(['Baseline Total Import = ', num2str(sum(grid_imp_base), '%.2f'), 'kWh'], ['IoT Total Import = ', num2str(sum(grid_imp_iot), '%.2f'), 'kWh']);
grid on;

subplot(2,1,2);
seas_data1 = [sum(grid_exp_base(winter_idx)), sum(grid_exp_iot(winter_idx));
    sum(grid_exp_base(spring_idx)), sum(grid_exp_iot(spring_idx));
    sum(grid_exp_base(summer_idx)), sum(grid_exp_iot(summer_idx));
    sum(grid_exp_base(autumn_idx)), sum(grid_exp_iot(autumn_idx))];
bar(seas_data1);
set(gca, 'XTickLabel', seasons);
title('Seasonal Grid Export');
ylabel('kWh');
legend(['Baseline Total Export = ', num2str(sum(grid_exp_base), '%.2f'), 'kWh'], ['IoT Total Export = ', num2str(sum(grid_exp_iot), '%.2f'), 'kWh']);
grid on;

% Final Energy Mix (Baseline and Iot)
figure;
subplot(1,2,1);
pie([self_cons_iot, total_imp_base]);
title('Baseline Scenario Energy Sourcing');
legend('Solar + Battery','Utility Grid','Location','southoutside');

subplot(1,2,2);
pie([self_cons_iot, total_imp_iot]);
title('IoT Scenario Energy Sourcing');
legend('Solar + Battery','Utility Grid','Location','southoutside');

% Winter Performance Snapshot Base
figure;
subplot(3, 2, 1)
plot(winter_idx, energy_base(winter_idx), 'r', winter_idx, pv_ac(winter_idx), 'y');
xlim([min(winter_idx), 730]);
title('Baseline Winter (January) Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['Baseline Demand = ', num2str(sum(energy_base(min(winter_idx):730)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(min(winter_idx):730)), '%.2f'), 'kWh']);
grid on;

subplot(3, 2, 2)
plot(winter_idx, energy_base(winter_idx), 'r', winter_idx, pv_ac(winter_idx), 'y');
xlim([7301, max(winter_idx)]);
title('Baseline Winter (November, December) Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['Baseline Demand = ', num2str(sum(energy_iot(7301:max(winter_idx))), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(7301:max(winter_idx))), '%.2f'), 'kWh']);
grid on;

% Spring Performance Snapshot Base
subplot(3, 2, 3)
plot(spring_idx, energy_base(spring_idx), 'r', spring_idx, pv_ac(spring_idx), 'y');
xlim([min(spring_idx), max(spring_idx)]);
title('Baseline Spring Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['Baseline Demand = ', num2str(sum(energy_base(spring_idx)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(spring_idx)), '%.2f'), 'kWh']);
grid on;

% Summer Performance Snapshot Base
subplot(3, 2, 4)
plot(summer_idx, energy_base(summer_idx), 'r', summer_idx, pv_ac(summer_idx), 'y');
xlim([min(summer_idx), max(summer_idx)]);
title('Baseline Summer Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['Baseline Demand = ', num2str(sum(energy_base(summer_idx)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(summer_idx)), '%.2f'), 'kWh']);
grid on;

% Autumn Performance Snapshot Base
subplot(3, 2, 5)
plot(autumn_idx, energy_base(autumn_idx), 'r', autumn_idx, pv_ac(autumn_idx), 'y');
xlim([min(autumn_idx), max(autumn_idx)]);
title('Baseline Autumn Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['Baseline Demand = ', num2str(sum(energy_base(autumn_idx)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(autumn_idx)), '%.2f'), 'kWh']);
grid on;

% Winter Performance Snapshot IoT
figure;
subplot(3, 2, 1)
plot(winter_idx, energy_iot(winter_idx), 'r', winter_idx, pv_ac(winter_idx), 'y');
xlim([min(winter_idx), 730]);
title('IoT Winter (January) Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['IoT Demand = ', num2str(sum(energy_iot(min(winter_idx):730)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(min(winter_idx):730)), '%.2f'), 'kWh']);
grid on;

subplot(3, 2, 2)
plot(winter_idx, energy_iot(winter_idx), 'r', winter_idx, pv_ac(winter_idx), 'y');
xlim([7301, max(winter_idx)]);
title('IoT Winter (November, December) Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['IoT Demand = ', num2str(sum(energy_iot(7301:max(winter_idx))), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(7301:max(winter_idx))), '%.2f'), 'kWh']);
grid on;

% Spring Performance Snapshot IoT
subplot(3, 2, 3)
plot(spring_idx, energy_iot(spring_idx), 'r', spring_idx, pv_ac(spring_idx), 'y');
xlim([min(spring_idx), max(spring_idx)]);
title('IoT Spring Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['IoT Demand = ', num2str(sum(energy_iot(spring_idx)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(spring_idx)), '%.2f'), 'kWh']);
grid on;

% Summer Performance Snapshot IoT
subplot(3, 2, 4)
plot(summer_idx, energy_iot(summer_idx), 'r', summer_idx, pv_ac(summer_idx), 'y');
xlim([min(summer_idx), max(summer_idx)]);
title('IoT Summer Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['IoT Demand = ', num2str(sum(energy_iot(summer_idx)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(summer_idx)), '%.2f'), 'kWh']);
grid on;

% Autumn Performance Snapshot IoT
subplot(3, 2, 5)
plot(autumn_idx, energy_iot(autumn_idx), 'r', autumn_idx, pv_ac(autumn_idx), 'y');
xlim([min(autumn_idx), max(autumn_idx)]);
title('IoT Autumn Snapshot');
ylabel('kWh');
xlabel('Hour');
legend(['IoT Demand = ', num2str(sum(energy_iot(autumn_idx)), '%.2f'), 'kWh'], ['Solar Output = ', num2str(sum(pv_ac(autumn_idx)), '%.2f'), 'kWh']);
grid on;

%% -------------------------------------------------
% FUNCTIONS
% -------------------------------------------------
function [imp, exp, soc_trace] = battery_engine(L, P, cap, c_eff, d_eff)
N = length(L); imp = zeros(N,1);
exp = zeros(N,1);
soc_trace = zeros(N,1);
% Start at 60% SOC
soc = 0.6 * cap;
for i = 1:N
    net = P(i) - L(i);
    % Surplus Solar
    if net > 0
        chg = min(net * c_eff, cap - soc);
        soc = soc + chg;
        exp(i) = net - (chg/c_eff);
    else
        % Energy Deficit
        need = abs(net);
        % 20% DoD Limit
        dis = min(need / d_eff, soc - (0.2 * cap));
        soc = soc - dis;
        imp(i) = need - (dis * d_eff);
    end
    soc_trace(i) = soc;
end
end