clear; clc; close all; rng(1);

%% 1. DESIGN PARAMETERS ---------------------------------------------------
hw.sensorNames = {'Front crossmember','Mid side-rail','Rear axle mount'};
hw.nSensors = numel(hw.sensorNames);

% Accelerometer: ADXL335 (analog, +-3 g, 3 axes; we use the vertical axis)
hw.Vsup      = 3.3;          % V supply
hw.sens      = 0.300;        % V/g sensitivity (typ. at 3.3 V)
hw.Vzero     = hw.Vsup/2;    % V at 0 g
hw.noiseDens = 300e-6;       % g/sqrt(Hz) (worst-case Z axis)
hw.Rint      = 32e3;         % ohm internal output resistor (sets filter with external Cx)

% Sampling chain
hw.fs      = 1024;           % Hz  effective sample rate used for analysis
hw.osr     = 4;              % oversampling ratio (ADC runs at fs*osr, then averaged)
hw.fadc    = hw.fs*hw.osr;   % Hz  raw ADC rate
hw.fmax    = 250;            % Hz  highest frequency of interest (chassis modes < 250 Hz)
hw.adcBits = 12;             % STM32 12-bit ADC
hw.Vref    = 3.3;            % V

% Decision logic
hw.persist = 3;              % consecutive abnormal 1-s windows before RED
hw.kSigma  = 4;              % threshold = baseline mean + kSigma*std

%% 2. COMPONENT CALCULATIONS ----------------------------------------------
E12 = [1.0 1.2 1.5 1.8 2.2 2.7 3.3 3.9 4.7 5.6 6.8 8.2];
E24 = [1.0 1.1 1.2 1.3 1.5 1.6 1.8 2.0 2.2 2.4 2.7 3.0 3.3 3.6 3.9 4.3 4.7 5.1 5.6 6.2 6.8 7.5 8.2 9.1];

% (a) Anti-alias capacitor: fc = 1/(2*pi*Rint*Cx)
CxIdeal   = 1/(2*pi*hw.Rint*hw.fmax);
hw.Cx     = nearestStd(CxIdeal, E12);
hw.fcAct  = 1/(2*pi*hw.Rint*hw.Cx);

% (b) ADC resolution in g
lsbV = hw.Vref/2^hw.adcBits;
lsbG = lsbV/hw.sens;
noiseRmsG = hw.noiseDens*sqrt(hw.fcAct*pi/2);      % noise inside filter bandwidth
dynRangeDb = 20*log10(3/noiseRmsG);

% (c) LED current-limiting resistors (GPIO 3.3 V, target 10 mA)
led.names = {'GREEN','AMBER','RED'};
led.Vf    = [2.1 2.0 2.0];      % forward voltage (V)
led.Itgt  = 10e-3;              % A
led.R     = zeros(1,3); led.Iact = zeros(1,3);
for i = 1:3
    led.R(i)    = nearestStd((3.3-led.Vf(i))/led.Itgt, E24);
    led.Iact(i) = (3.3-led.Vf(i))/led.R(i);
end

% (d) Power budget (12 V vehicle supply, 9-16 V range)
pw.Vbat = 12;
pw.items = {'MCU (STM32F4 @ ~100 MHz)', 30e-3; ...
            '3x ADXL335 (0.35 mA each)', 3*0.35e-3; ...
            'LED (one lit at a time)',   led.Itgt; ...
            'Regulator quiescent',       5e-3};
pw.I     = sum([pw.items{:,2}]);               % A total at 3.3 V
pw.P3v3  = pw.I*3.3;
pw.effBuck = 0.85;
pw.PinBuck = pw.P3v3/pw.effBuck;
pw.PldoDiss = (pw.Vbat-3.3)*pw.I;              % heat if an LDO were used

% (e) MCU load / memory (rough estimates)
mcu.clk      = 100e6;
mcu.fftCycles = 30*1024*log2(1024);            % assumed ~30 cycles per N*log2N
mcu.tFFT     = mcu.fftCycles/mcu.clk;          % s per channel per window
mcu.load     = hw.nSensors*mcu.tFFT/1.0;       % fraction of 1 s window
mcu.ramRaw   = hw.nSensors*1024*2;             % bytes, int16 samples
mcu.ramFFT   = 1024*4*2;                       % bytes, float32 work buffer

fprintf('\n=========== HARDWARE DESIGN SUMMARY ===========\n');
fprintf('Anti-alias cap Cx      : ideal %.1f nF -> use %.0f nF (E12), fc = %.0f Hz\n', CxIdeal*1e9, hw.Cx*1e9, hw.fcAct);
fprintf('ADC                    : %d-bit, LSB = %.3f mV = %.2f mg\n', hw.adcBits, lsbV*1e3, lsbG*1e3);
fprintf('Sensor noise (in band) : %.2f mg rms | dynamic range ~ %.0f dB\n', noiseRmsG*1e3, dynRangeDb);
fprintf('Sampling               : ADC %d Hz, x%d oversample -> %d Hz\n', hw.fadc, hw.osr, hw.fs);
for i = 1:3
    fprintf('LED %-5s              : R = %4.0f ohm (E24), I = %.1f mA\n', led.names{i}, led.R(i), led.Iact(i)*1e3);
end
fprintf('Total load @3.3 V      : %.1f mA (%.0f mW)\n', pw.I*1e3, pw.P3v3*1e3);
fprintf('Buck (85%%) input power : %.0f mW  | LDO would burn %.0f mW as heat -> use buck\n', pw.PinBuck*1e3, pw.PldoDiss*1e3);
fprintf('FFT 1024-pt (est.)     : %.1f ms/channel, CPU load ~ %.1f %%\n', mcu.tFFT*1e3, mcu.load*100);
fprintf('RAM (est.)             : raw %.1f kB + FFT buffer %.1f kB\n', mcu.ramRaw/1024, mcu.ramFFT/1024);

%% 3. FIGURE 1 - BLOCK DIAGRAM -------------------------------------------
figure('Name','Block diagram','Color','w','Position',[50 50 1150 520]);
axes('Position',[0 0 1 1]); hold on; axis([0 16 0 7]); axis off;
drawBlock( 0.3,3.6,2.9,2.4,{'3x ADXL335','accelerometers','(front / mid / rear','chassis points)'},[0.80 0.90 1.00]);
drawBlock( 3.9,3.6,2.3,2.4,{'Anti-alias','filter','Cx to GND','(with 32k int.)'},[0.85 1.00 0.85]);
drawBlock( 6.9,3.6,3.4,2.4,{'STM32 MCU','12-bit ADC x4 oversample','FFT / RMS / kurtosis','threshold + persistence'},[1.00 0.95 0.75]);
drawBlock(11.0,3.6,2.2,2.4,{'GPIO + R','130-150 ohm'},[1.00 0.85 0.85]);
drawBlock(13.7,3.6,2.0,2.4,{'Telltale','GREEN/AMBER/RED','LED (+buzzer)'},[1.00 0.75 0.75]);
drawBlock( 0.3,0.6,3.6,1.8,{'12 V battery','fuse + reverse','protection + TVS'},[0.90 0.90 0.90]);
drawBlock( 5.0,0.6,3.0,1.8,{'Buck converter','12 V -> 3.3 V'},[0.90 0.90 0.90]);
drawBlock(10.0,0.6,3.6,1.8,{'Optional: UART/CAN','to logger / cluster'},[0.95 0.95 1.00]);
arr(3.2,4.8,3.9,4.8); arr(6.2,4.8,6.9,4.8); arr(10.3,4.8,11.0,4.8); arr(13.2,4.8,13.7,4.8);
arr(3.9,1.5,5.0,1.5); arr(8.0,1.5,8.6,3.6); arr(6.5,2.4,1.8,3.6); arr(9.4,3.6,10.8,2.4);
text(8.0,6.55,'Smart Chassis Vibration Analysis - Hardware Block Diagram','HorizontalAlignment','center','FontSize',13,'FontWeight','bold');
text(6.9,2.9,'3.3 V rail powers MCU + sensors','FontSize',8,'Color',[0.3 0.3 0.3]);

%% 4. FIGURE 2 - ANTI-ALIAS RESPONSE --------------------------------------
f  = logspace(0, log10(hw.fadc/2), 500);
Hrc  = 1./sqrt(1+(f/hw.fcAct).^2);
x    = pi*f/hw.fadc;
Hav  = abs(sin(hw.osr*x)./(hw.osr*sin(x))); Hav(x==0) = 1;   % boxcar average (decimation filter)
Htot = Hrc.*Hav;
fAlias = hw.fs - hw.fmax;      % frequency that folds onto fmax after decimation
xa = pi*fAlias/hw.fadc;
attAlias = 20*log10( (1/sqrt(1+(fAlias/hw.fcAct)^2)) * abs(sin(hw.osr*xa)/(hw.osr*sin(xa))) );
fprintf('Alias rejection        : %.1f dB at %d Hz (folds onto %d Hz after decimation)\n', attAlias, fAlias, hw.fmax);

figure('Name','Anti-alias filter','Color','w');
semilogx(f,20*log10(Hrc),'--','LineWidth',1.2); hold on;
semilogx(f,20*log10(Hav),':','LineWidth',1.2);
semilogx(f,20*log10(Htot),'r','LineWidth',2); grid on;
plot([hw.fmax hw.fmax],[-60 3],'k:'); plot([hw.fs/2 hw.fs/2],[-60 3],'k--');
xlabel('Frequency (Hz)'); ylabel('Gain (dB)'); ylim([-60 3]);
title(sprintf('Analog RC (fc=%.0f Hz) x averaging filter | %.0f dB at %d Hz', hw.fcAct, attAlias, fAlias));
legend('Analog Cx filter','x4 averaging','Combined','f_{max}','f_s/2','Location','southwest');

%% 5. SIGNAL CHAIN DEMO: physical vibration vs what the MCU actually sees --
aTrue = chassisSignal('loose', 0.8, hw.fadc, 1);
[xMcu, counts] = acquire(aTrue, hw);
tt = (0:hw.fs-1)'/hw.fs;
aRef = mean(reshape(aTrue,hw.osr,[]),1)';
figure('Name','Signal chain','Color','w','Position',[100 100 1000 600]);
subplot(2,1,1); plot(tt,aRef,'Color',[0.6 0.6 0.6]); hold on; plot(tt,xMcu,'b'); grid on;
ylabel('g'); legend('True vibration','After sensor + filter + ADC'); title('Loose-joint vibration through the hardware chain');
subplot(2,1,2); plot((0:numel(counts)-1)/hw.fadc, counts,'.','MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel('ADC counts (0-4095)'); title('Raw 12-bit ADC output (before decimation)');

%% 6. BASELINE + THRESHOLDS (learned on the healthy car) ------------------
nBase = 30; base = zeros(nBase, hw.nSensors, 3);
for k = 1:nBase
    for s = 1:hw.nSensors
        xk = acquire(chassisSignal('healthy',0,hw.fadc,1), hw);
        base(k,s,:) = mcuFeatures(xk, hw.fs);
    end
end
thr = zeros(hw.nSensors,3);
for s = 1:hw.nSensors
    B = reshape(base(:,s,:), nBase, 3);
    thr(s,:) = mean(B,1) + hw.kSigma*std(B,0,1);
end
fprintf('\nThresholds [RMS(g) kurtosis HF-ratio] per sensor:\n'); disp(thr);

%% 7. DRIVE SIMULATION: pothole at t=11 s, crack starts at rear sensor t=19 s
nWin = 30; F = zeros(nWin, hw.nSensors, 3); abn = false(nWin, hw.nSensors);
for k = 1:nWin
    for s = 1:hw.nSensors
        cond = 'healthy'; sev = 0;
        if k >= 19 && s == 3, cond = 'crack'; sev = 0.7; end
        a = chassisSignal(cond, sev, hw.fadc, 1);
        if k == 11                                   % one big road shock, all sensors
            L = round(0.03*hw.fadc); i0 = round(0.4*hw.fadc);
            a(i0:i0+L-1) = a(i0:i0+L-1) + 0.5*exp(-(0:L-1)'/(0.008*hw.fadc));
        end
        F(k,s,:) = mcuFeatures(acquire(a,hw), hw.fs);
        abn(k,s) = any(reshape(F(k,s,:),1,3) > thr(s,:));
    end
end
consec = 0; state = zeros(nWin,1);                  % 0=GREEN 1=AMBER 2=RED
for k = 1:nWin
    if any(abn(k,:)), consec = consec + 1; else, consec = 0; end
    if consec == 0, state(k) = 0; elseif consec < hw.persist, state(k) = 1; else, state(k) = 2; end
end
firstRed = find(state==2,1);
fprintf('Pothole window (t=11 s) telltale : %s\n', led.names{state(11)+1});
if isempty(firstRed), fprintf('No RED raised\n'); else, fprintf('First RED at t = %d s (crack began t = 19 s)\n', firstRed); end

figure('Name','Telltale simulation','Color','w','Position',[120 120 1000 600]);
subplot(2,1,1); hold on;
cols = lines(3);
for s = 1:hw.nSensors
    hLine(s) = plot(1:nWin, F(:,s,1), '-o','Color',cols(s,:),'LineWidth',1.2);
    plot([1 nWin],[thr(s,1) thr(s,1)],'--','Color',cols(s,:));
end
grid on; ylabel('RMS (g)'); legend(hLine, hw.sensorNames, 'Location','northwest'); title('Vibration RMS per sensor (dashed = threshold)');
subplot(2,1,2); hold on; axis([0.5 nWin+0.5 0 1]); set(gca,'YTick',[]);
stateCol = [0.2 0.8 0.2; 1 0.75 0; 0.9 0.1 0.1];
for k = 1:nWin
    rectangle('Position',[k-0.5 0 1 1],'FaceColor',stateCol(state(k)+1,:),'EdgeColor','w');
end
xlabel('Time (s)'); title('Telltale LED state (green / amber / red)');

%% 8. SPECTRUM SEEN BY THE MCU: healthy vs cracked ------------------------
P0 = 0; P1 = 0;
for k = 1:8
    [fr, p0] = mcuSpectrum(acquire(chassisSignal('healthy',0,hw.fadc,1),hw), hw.fs); P0 = P0 + p0/8;
    [~,  p1] = mcuSpectrum(acquire(chassisSignal('crack',0.9,hw.fadc,1),hw),  hw.fs); P1 = P1 + p1/8;
end
band = fr>=8 & fr<20;
[~,i0] = max(P0.*band); [~,i1] = max(P1.*band);
figure('Name','Spectrum','Color','w');
semilogy(fr,P0,'g','LineWidth',1.3); hold on; semilogy(fr,P1,'r','LineWidth',1.3); grid on; xlim([0 300]);
xlabel('Frequency (Hz)'); ylabel('Power (a.u.)'); legend('Healthy','Crack (severity 0.9)');
title(sprintf('First resonance: %.0f Hz -> %.0f Hz (frequency drop = crack indicator)', fr(i0), fr(i1)));

%% 9. BILL OF MATERIALS + PIN MAP -----------------------------------------
BOM = {
 'Accelerometer',  'ADXL335 breakout (analog)',       3, 'Vibration sensing at 3 chassis points';
 'Microcontroller','STM32F4 (e.g. Nucleo-F411RE)',    1, '12-bit ADC, FPU + DSP for FFT';
 'Filter cap',     sprintf('%.0f nF ceramic (X7R)',hw.Cx*1e9), 3, 'Anti-alias filter, one per sensor axis used';
 'LED',            'Green / Amber / Red 5 mm',        3, 'Telltale indicator';
 'LED resistors',  sprintf('%.0f / %.0f / %.0f ohm',led.R(1),led.R(2),led.R(3)), 3, 'Limit LED current to ~10 mA';
 'Regulator',      'Buck module 12 V -> 3.3 V (e.g. LM2596/MP1584)', 1, 'Efficient power (LDO would run hot)';
 'Protection',     'Fuse 1 A, diode, TVS (SMBJ18A)',  1, 'Reverse polarity + load-dump protection';
 'Optional',       'Piezo buzzer, CAN transceiver',   1, 'Audible alert / vehicle bus link'};
fprintf('\n=========== BILL OF MATERIALS ===========\n');
for i = 1:size(BOM,1)
    fprintf('%-16s | %-46s | x%d | %s\n', BOM{i,1}, BOM{i,2}, BOM{i,3}, BOM{i,4});
end
PIN = {'PA0','ADC1_IN0','Front sensor output';  'PA1','ADC1_IN1','Mid sensor output'; 'PA4','ADC1_IN4','Rear sensor output';
       'PB0','GPIO out','GREEN LED';            'PB1','GPIO out','AMBER LED';          'PB2','GPIO out','RED LED';
       '3V3','Power','Sensors VCC + ADC Vref';  'GND','Power','Common ground (star point)'};
fprintf('\n=========== PIN MAP ===========\n');
for i = 1:size(PIN,1), fprintf('%-4s  %-9s  %s\n', PIN{i,1}, PIN{i,2}, PIN{i,3}); end
fprintf('\nWiring tips: keep sensor leads short/shielded, mount sensors rigidly on the chassis,\nuse one ground star point, and place Cx close to each sensor output.\n');

%% ===================== LOCAL FUNCTIONS ==================================
function v = nearestStd(val, series)
    dec = 10^floor(log10(val));
    cand = [series*dec, 10*dec*series(1)];
    [~,i] = min(abs(cand - val));
    v = cand(i);
end

function a = chassisSignal(cond, sev, fsim, T)
% Simulated chassis acceleration (g) at one sensor
    n = round(fsim*T); t = (0:n-1)'/fsim;
    modes = [14 0.030 1.0; 33 0.030 0.7; 58 0.025 0.5; 95 0.020 0.3];   % Hz, damping, amplitude
    a = zeros(n,1);
    for k = 1:size(modes,1)
        f = modes(k,1); z = modes(k,2); A = modes(k,3);
        if strcmp(cond,'crack')
            if k <= 3, f = f*(1-0.15*sev); end     % stiffness loss -> lower frequency
            z = z*(1+4*sev); A = A*(1+1.2*sev);    % more damping and amplitude
        end
        th = 2*pi*f/fsim; r = exp(-z*th);          % resonator pole radius
        m = filter(1-r, [1 -2*r*cos(th) r^2], randn(n,1));
        a = a + A*m/std(m);
    end
    a = 0.05*a;
    road = filter(0.02, [1 -0.98], randn(n,1)); road = 0.02*road/std(road);
    a = a + road + 0.02*sin(2*pi*30*t+2*pi*rand) + 0.008*sin(2*pi*60*t+2*pi*rand);   % + engine 30/60 Hz
    if strcmp(cond,'loose')                        % rattling impacts
        Lb = round(0.06*fsim); tb = (0:Lb-1)'/fsim;
        for q = 1:round(2+10*sev)
            k0 = randi(n-Lb); fr = 150+100*rand; sg = 2*(rand>0.5)-1;
            a(k0:k0+Lb-1) = a(k0:k0+Lb-1) + (0.15+0.35*sev)*sg*exp(-tb/0.012).*sin(2*pi*fr*tb);
        end
    end
end

function [xg, counts] = acquire(a, hw)
% Sensor -> analog filter -> ADC -> oversample/average. Returns g at hw.fs.
    n = numel(a);
    v = hw.Vzero + hw.sens*a + hw.noiseDens*sqrt(hw.fadc/2)*hw.sens*randn(n,1);   % sensor + noise
    alpha = (1/hw.fadc)/(1/(2*pi*hw.fcAct) + 1/hw.fadc);
    v = filter(alpha, [1 alpha-1], v, (1-alpha)*hw.Vzero);                          % RC filter
    lsb = hw.Vref/2^hw.adcBits;
    v = v + 0.5*lsb*randn(n,1);                                                     % ADC noise
    counts = min(max(round(v/lsb),0), 2^hw.adcBits-1);                              % quantise + clip
    g = (counts*lsb - hw.Vzero)/hw.sens;
    xg = mean(reshape(g, hw.osr, []), 1)';                                          % decimate
end

function [fr, P] = mcuSpectrum(x, fs)
    x = x - mean(x); N = numel(x);
    w = 0.5 - 0.5*cos(2*pi*(0:N-1)'/(N-1));
    X = abs(fft(x.*w)).^2; P = X(1:N/2); fr = (0:N/2-1)'*fs/N;
end

function F = mcuFeatures(x, fs)
% What the microcontroller computes each second: [RMS, kurtosis, HF energy ratio]
    x = x - mean(x);
    rmsv = sqrt(mean(x.^2));
    kurt = mean(x.^4)/(mean(x.^2)^2) - 3;
    [fr, P] = mcuSpectrum(x, fs);
    hf = sum(P(fr>=100))/sum(P);
    F = [rmsv kurt hf];
end

function drawBlock(x, y, w, h, lbl, col)
    rectangle('Position',[x y w h],'Curvature',0.08,'FaceColor',col,'EdgeColor',[0.2 0.2 0.2],'LineWidth',1.2);
    text(x+w/2, y+h/2, lbl, 'HorizontalAlignment','center','FontSize',9);
end

function arr(x1, y1, x2, y2)
    quiver(x1, y1, x2-x1, y2-y1, 0, 'k', 'LineWidth',1.4, 'MaxHeadSize',0.6);
end
