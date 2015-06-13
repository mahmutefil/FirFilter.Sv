% This file is part of FirFilter.Sv (Trivial SystemVerilog implementation
% of FIR filters)
%
% Copyright (C) 2015  Leonid Azarenkov < leonid AT rezonics DOT com >
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%
% * Redistributions of source code must retain the above copyright notice, this
%   list of conditions and the following disclaimer.
%
% * Redistributions in binary form must reproduce the above copyright notice,
%   this list of conditions and the following disclaimer in the documentation
%   and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
% OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

clear all
close all
clc
format long

%% Parameters
% define input parameters here

FiltDescr    = 'Low-pass equiripple FIR filter (lp_filter.fda)';
FiltSymmetry = 1; % 0 - non-symmetric, 1 - symmetric, 2 - anti-symmetric

% coefficients, floating point
FiltCoeffs = [-0.00431402930730814,-0.0130913216218316,-0.0165150877272552,-0.00643058443337610,0.00981787626662560,0.0108018802381368,-0.00656741371282848,-0.0168048296226862,0.000653253913101224,0.0224712800873412,0.0101471314679487,-0.0256577409885416,-0.0265589606190970,0.0230483928540287,0.0503852903895159,-0.00929120358802459,-0.0879185034417772,-0.0337703300143187,0.187334796517400,0.401505729847994,0.401505729847994,0.187334796517400,-0.0337703300143187,-0.0879185034417772,-0.00929120358802459,0.0503852903895159,0.0230483928540287,-0.0265589606190970,-0.0256577409885416,0.0101471314679487,0.0224712800873412,0.000653253913101224,-0.0168048296226862,-0.00656741371282848,0.0108018802381368,0.00981787626662560,-0.00643058443337610,-0.0165150877272552,-0.0130913216218316,-0.00431402930730814];

TapsNum = length(FiltCoeffs);

% Fixed-point system parameters
CoeffBits = 16;
DataBits  = 16;

% Data file names
FiltSpecFile = 'filter_descr.txt'; % filter specification/description
SigFileRe  = 'sigdata_re.dax'; %test signal
SigFileIm  = 'sigdata_im.dax'; %test signal
RefFileRe  = 'refdata_re.dax'; %reference data (filtered signal)
RefFileIm  = 'refdata_im.dax'; %reference data (filtered signal)
TestFileRe = 'tstdata_re.dax'; %test data from simulator (filtered signal)
TestFileIm = 'tstdata_im.dax'; %test data from simulator (filtered signal)

%% Filter Quantization
ATarget = 2^(CoeffBits - 1) - 1;
ScaleFactor2 = 2^(floor(log2(ATarget / max(abs(FiltCoeffs)))));
FiltCoeffsFixP = round(FiltCoeffs * ScaleFactor2);
OutputBitsFullPrecision = DataBits + ceil(log2(sum(abs(FiltCoeffsFixP))));

FiltCoeffsFixP = fi(FiltCoeffsFixP, 1, CoeffBits, 0);

%% Print filter specification
SpecStr = '';
SpecStr = [SpecStr sprintf('Filter description: %s\n', FiltDescr)];
SpecStr = [SpecStr sprintf('\n')];
SpecStr = [SpecStr sprintf('Number of taps: %d\n', TapsNum)];
SpecStr = [SpecStr sprintf('Symmetry      : %d\n', FiltSymmetry)];
SpecStr = [SpecStr sprintf('Coefficients unscaled: [%s]\n', num2csstr(FiltCoeffs))];
SpecStr = [SpecStr sprintf('CoeffBits : %d\n', CoeffBits)];
SpecStr = [SpecStr sprintf('DataBits  : %d\n', DataBits)];
SpecStr = [SpecStr sprintf('ResultBits: %d\n', OutputBitsFullPrecision)];
SpecStr = [SpecStr sprintf('Coefficient scale factor: %d\n', ScaleFactor2)];
SpecStr = [SpecStr sprintf('Coefficients scaled: [%s]\n', num2csstr(int64(FiltCoeffsFixP)))];
SpecStr = [SpecStr sprintf('\n')];
disp(SpecStr);

specFid = fopen(FiltSpecFile, 'w');
if specFid < 0
    error('Couldn''t open filter specification file for writing');
end
fprintf(specFid, '%s', SpecStr);
fclose(specFid);

%% Test signal, sine
% change test signal parameters as necessary
Fs = 10000; %Hz
Ts = 1/Fs;
Np = 1000;
t = 0 : Ts : (Np - 1)*Ts;
w = 50; %Hz
ZScaleFactor2 = 2^(DataBits - 1) - 1;

% test signal
z_sine = exp(2*pi*1i*w*t);
z_sine_fixp = round(z_sine * ZScaleFactor2);
z_sine_fixp = fi(z_sine_fixp, 1, DataBits, 0);

% filtered signal
y_sine = filter(FiltCoeffs, 1, z_sine);
y_sine_fixp = filter(FiltCoeffsFixP, 1, z_sine_fixp);
y_sine_fixp = fi(y_sine_fixp, 1, OutputBitsFullPrecision, 0);

figure(1)
title('Sine wave test');
plot(t, real(z_sine_fixp), 'b');
hold on
plot(t, real(y_sine_fixp)/ScaleFactor2, 'g');
legend('original', 'filtered');

%save test signal and golden results
saveSignalFixp(SigFileRe, real(z_sine_fixp));
saveSignalFixp(SigFileIm, imag(z_sine_fixp));
saveSignalFixp(RefFileRe, real(y_sine_fixp));
saveSignalFixp(RefFileIm, imag(y_sine_fixp));

%% Test signal, sweep
