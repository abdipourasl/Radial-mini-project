clear all
clc
close all
mat=load('sample_data.mat');
ecg= mat.sample_data;
fs=500;
gr=1;
% function [qrs_amp_raw,qrs_i_raw,delay]=pan_tompkin(ecg,fs,gr)

ecg = ecg(:); % vectorize
%% Initialize
qrs_c =[]; %amplitude of R
qrs_i =[]; %index
SIG_LEV = 0; 
nois_c =[];
nois_i =[];
delay = 0;
skip = 0; % becomes one when a T wave is detected
not_nois = 0; % it is not noise when not_nois = 1
selected_RR =[]; % Selected RR intervals
m_selected_RR = 0;
mean_RR = 0;
qrs_i_raw =[];
qrs_amp_raw=[];
ser_back = 0; 
test_m = 0;
SIGL_buf = [];
NOISL_buf = [];
THRS_buf = [];
SIGL_buf1 = [];
NOISL_buf1 = [];
THRS_buf1 = [];
%% Plot differently based on filtering settings
if gr
 if fs == 500
  figure,  ax(1)=subplot(321);plot(ecg);axis tight;title('Raw ECG Signal');
 else
  figure,  ax(1)=subplot(3,2,[1 2]);plot(ecg);axis tight;title('Raw ECG Signal');
 end
end    
%% Noise cancelation(Filtering) % Filters (Filter in between 5-15 Hz)
if fs == 500
%% Low Pass Filter  H(z) = ((1 - z^(-6))^2)/(1 - z^(-1))^2
b = [1 0 0 0 0 0 -2 0 0 0 0 0 1];
a = [1 -2 1];
h_l = filter(b,a,[1 zeros(1,12)]); 
ecg_l = conv (ecg ,h_l);
ecg_l = ecg_l/ max( abs(ecg_l));
delay = 6; %based on the paper
if gr
ax(2)=subplot(322);plot(ecg_l);axis tight;title('Low pass filtered');
end
%% High Pass filter H(z) = (-1+32z^(-16)+z^(-32))/(1+z^(-1))
b = [-1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 32 -32 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1];
a = [1 -1];
h_h = filter(b,a,[1 zeros(1,32)]); 
ecg_h = conv (ecg_l ,h_h);
ecg_h = ecg_h/ max( abs(ecg_h));
delay = delay + 16; % 16 samples for highpass filtering
if gr
ax(3)=subplot(323);plot(ecg_h);axis tight;title('High Pass Filtered');
end
else
%% bandpass filter for Noise cancelation of other sampling frequencies(Filtering)
f1=0.1; %cuttoff low frequency to get rid of baseline wander
f2=40; %cuttoff frequency to discard high frequency noise
Wn=[f1 f2]*2/fs; % cutt off based on fs
N = 6; % order of 3 less processing
[a,b] = butter(N,Wn); %bandpass filtering
ecg_h = filtfilt(a,b,ecg);
ecg_h = ecg_h/ max(abs(ecg_h));
if gr
ax(3)=subplot(323);plot(ecg_h);axis tight;title('Band Pass Filtered');
end
end
%% derivative filter H(z) = (1/8T)(-z^(-2) - 2z^(-1) + 2z + z^(2))
h_d = [-1 -2 0 2 1]*(1/8);%1/8*fs
ecg_d = conv (ecg_h ,h_d);
ecg_d = ecg_d/max(ecg_d);
delay = delay + 2; % delay of derivative filter 2 samples
if gr
ax(4)=subplot(324);plot(ecg_d);axis tight;title('Filtered with the derivative filter');
end
%% Squaring nonlinearly enhance the dominant peaks
ecg_s = ecg_d.^2;
if gr
ax(5)=subplot(325);plot(ecg_s);axis tight;title('Squared');
end
%% Moving average Y(nt) = (1/N)[x(nT-(N - 1)T)+ x(nT - (N - 2)T)+...+x(nT)]
ecg_m = conv(ecg_s ,ones(1 ,round(0.150*fs))/round(0.150*fs));
delay = delay + 15;
if gr
ax(6)=subplot(326);plot(ecg_m);axis tight;title('Averaged with 30 samples length,Black noise,Green Adaptive Threshold,RED Sig Level,Red circles QRS adaptive threshold');
axis tight;
end

[pks,locs] = findpeaks(ecg_m,'MINPEAKDISTANCE',round(0.2*fs));
%% initialize the training phase (2 seconds of the signal) to determine the THR_SIG and THR_NOISE
THR_SIG = max(ecg_m(1:2*fs))*1/3; % 0.25 of the max amplitude 
THR_NOISE = mean(ecg_m(1:2*fs))*1/2; % 0.5 of the mean signal is considered to be noise
SIG_LEV= THR_SIG;
NOISE_LEV = THR_NOISE;
%% Initialize bandpath filter threshold(2 seconds of the bandpass signal)
THR_SIG1 = max(ecg_h(1:2*fs))*1/3; % 0.25 of the max amplitude 
THR_NOISE1 = mean(ecg_h(1:2*fs))*1/2; %
SIG_LEV1 = THR_SIG1; % Signal level in Bandpassed filter
NOISE_LEV1 = THR_NOISE1; % Noise level in Bandpassed filter
%% Thresholding and online desicion rule
for i = 1 : length(pks)
   %% locate the corresponding peak in the filtered signal 
    if locs(i)-round(0.150*fs)>= 1 && locs(i)<= length(ecg_h)
          [y_i x_i] = max(ecg_h(locs(i)-round(0.150*fs):locs(i)));
       else
          if i == 1
            [y_i x_i] = max(ecg_h(1:locs(i)));
            ser_back = 1;
          elseif locs(i)>= length(ecg_h)
            [y_i x_i] = max(ecg_h(locs(i)-round(0.150*fs):end));
          end
        
     end
  %% update the heart_rate (Two heart rate means one the most recent and the other selected)
    if length(qrs_c) >= 9 
        diffRR = diff(qrs_i(end-8:end)); %calculate RR interval
        mean_RR = mean(diffRR); % calculate the mean of 8 previous R waves interval
        comp =qrs_i(end)-qrs_i(end-1); %latest RR
        if comp <= 0.92*mean_RR || comp >= 1.16*mean_RR
            % lower down thresholds to detect better in MVI
                THR_SIG = 0.5*(THR_SIG);
                %THR_NOISE = 0.5*(THR_SIG);  
               % lower down thresholds to detect better in Bandpass filtered 
                THR_SIG1 = 0.5*(THR_SIG1);
                %THR_NOISE1 = 0.5*(THR_SIG1); 
                
        else
            m_selected_RR = mean_RR; %the latest regular beats mean
        end 
          
    end
      %% calculate the mean of the last 8 R waves to make sure that QRS is not
       % missing(If no R detected , trigger a search back) 1.66*mean
       if m_selected_RR
           test_m = m_selected_RR; %if the regular RR availabe use it   
       elseif mean_RR && m_selected_RR == 0
           test_m = mean_RR;   
       else
           test_m = 0;
       end
    if test_m
          if (locs(i) - qrs_i(end)) >= round(1.66*test_m)% it shows a QRS is missed 
              [pks_temp,locs_temp] = max(ecg_m(qrs_i(end)+ round(0.200*fs):locs(i)-round(0.200*fs))); % search back and locate the max in this interval
              locs_temp = qrs_i(end)+ round(0.200*fs) + locs_temp -1; %location 
             
              if pks_temp > THR_NOISE
               qrs_c = [qrs_c pks_temp];
               qrs_i = [qrs_i locs_temp];
              
               % find the location in filtered sig
               if locs_temp <= length(ecg_h)
                [y_i_t x_i_t] = max(ecg_h(locs_temp-round(0.150*fs):locs_temp));
               else
                [y_i_t x_i_t] = max(ecg_h(locs_temp-round(0.150*fs):end));
               end
               % take care of bandpass signal threshold
               if y_i_t > THR_NOISE1       
                      qrs_i_raw = [qrs_i_raw locs_temp-round(0.150*fs)+ (x_i_t - 1)];% save index of bandpass 
                      qrs_amp_raw =[qrs_amp_raw y_i_t]; %save amplitude of bandpass 
                      SIG_LEV1 = 0.25*y_i_t + 0.75*SIG_LEV1; %when found with the second thres 
               end
               not_nois = 1;
               SIG_LEV = 0.25*pks_temp + 0.75*SIG_LEV ;  %when found with the second threshold             
             end 
              
          else
              not_nois = 0;
              
          end
    end
    %%  find noise and QRS peaks
    if pks(i) >= THR_SIG
        
                 % if a QRS candidate occurs within 360ms of the previous QRS
                 % ,the algorithm determines if its T wave or QRS
                 if length(qrs_c) >= 3
                      if (locs(i)-qrs_i(end)) <= round(0.3600*fs)
                        Slope1 = mean(diff(ecg_m(locs(i)-round(0.075*fs):locs(i)))); %mean slope of the waveform at that position
                        Slope2 = mean(diff(ecg_m(qrs_i(end)-round(0.075*fs):qrs_i(end)))); %mean slope of previous R wave
                             if abs(Slope1) <= abs(0.5*(Slope2))  % slope less then 0.5 of previous R
                                 nois_c = [nois_c pks(i)];
                                 nois_i = [nois_i locs(i)];
                                 skip = 1; % T wave identification
                                 % adjust noise level in both filtered and
                                 % MVI
                                 NOISE_LEV1 = 0.125*y_i + 0.875*NOISE_LEV1;
                                 NOISE_LEV = 0.125*pks(i) + 0.875*NOISE_LEV; 
                             else
                                 skip = 0;
                             end
                      end
                 end
        if skip == 0  % skip is 1 when a T wave is detected       
        qrs_c = [qrs_c pks(i)];
        qrs_i = [qrs_i locs(i)];
        % bandpass filter check threshold
         if y_i >= THR_SIG1
                        if ser_back 
                           qrs_i_raw = [qrs_i_raw x_i];  % save index of bandpass 
                        else
                           qrs_i_raw = [qrs_i_raw locs(i)-round(0.150*fs)+ (x_i - 1)];% save index of bandpass 
                        end
                           qrs_amp_raw =[qrs_amp_raw y_i];% save amplitude of bandpass 
          SIG_LEV1 = 0.125*y_i + 0.875*SIG_LEV1;% adjust threshold for bandpass filtered sig
         end
         
        % adjust Signal level
        SIG_LEV = 0.125*pks(i) + 0.875*SIG_LEV ;
        end
    elseif THR_NOISE <= pks(i) && pks(i)<THR_SIG
        
         %adjust Noise level in filtered sig
         NOISE_LEV1 = 0.125*y_i + 0.875*NOISE_LEV1;
         %adjust Noise level in MVI
         NOISE_LEV = 0.125*pks(i) + 0.875*NOISE_LEV; 
    elseif pks(i) < THR_NOISE
        nois_c = [nois_c pks(i)];
        nois_i = [nois_i locs(i)];
        
        % noise level in filtered signal
        NOISE_LEV1 = 0.125*y_i + 0.875*NOISE_LEV1;
        %end
        
         %adjust Noise level in MVI
        NOISE_LEV = 0.125*pks(i) + 0.875*NOISE_LEV;    
    end
    %% adjust the threshold with SNR
    if NOISE_LEV ~= 0 || SIG_LEV ~= 0
        THR_SIG = NOISE_LEV + 0.25*(abs(SIG_LEV - NOISE_LEV));
        THR_NOISE = 0.5*(THR_SIG);
    end
    
    % adjust the threshold with SNR for bandpassed signal
    if NOISE_LEV1 ~= 0 || SIG_LEV1 ~= 0
        THR_SIG1 = NOISE_LEV1 + 0.25*(abs(SIG_LEV1 - NOISE_LEV1));
        THR_NOISE1 = 0.5*(THR_SIG1);
    end
    
% take a track of thresholds of smoothed signal
SIGL_buf = [SIGL_buf SIG_LEV];
NOISL_buf = [NOISL_buf NOISE_LEV];
THRS_buf = [THRS_buf THR_SIG];
% take a track of thresholds of filtered signal
SIGL_buf1 = [SIGL_buf1 SIG_LEV1];
NOISL_buf1 = [NOISL_buf1 NOISE_LEV1];
THRS_buf1 = [THRS_buf1 THR_SIG1];
    
 skip = 0; %reset parameters
 not_nois = 0; %reset parameters
 ser_back = 0;  %reset bandpass param   
end
if gr
hold on,scatter(qrs_i,qrs_c,'m');
hold on,plot(locs,NOISL_buf,'--k','LineWidth',2);
hold on,plot(locs,SIGL_buf,'--r','LineWidth',2);
hold on,plot(locs,THRS_buf,'--g','LineWidth',2);
%if ax(:)
linkaxes(ax,'x');
zoom on;
%end
end
%% overlay on the signals
if gr
figure,az(1)=subplot(311);plot(ecg_h);title('QRS on Filtered Signal');axis tight;
hold on,scatter(qrs_i_raw,qrs_amp_raw,'m');
hold on,plot(locs,NOISL_buf1,'LineWidth',2,'Linestyle','--','color','k');
hold on,plot(locs,SIGL_buf1,'LineWidth',2,'Linestyle','-.','color','r');
hold on,plot(locs,THRS_buf1,'LineWidth',2,'Linestyle','-.','color','g');
az(2)=subplot(312);plot(ecg_m);title('QRS on MVI signal and Noise level(black),Signal Level (red) and Adaptive Threshold(green)');axis tight;
hold on,scatter(qrs_i,qrs_c,'m');
hold on,plot(locs,NOISL_buf,'LineWidth',2,'Linestyle','--','color','k');
hold on,plot(locs,SIGL_buf,'LineWidth',2,'Linestyle','-.','color','r');
hold on,plot(locs,THRS_buf,'LineWidth',2,'Linestyle','-.','color','g');
az(3)=subplot(313);plot(ecg-mean(ecg));title('Pulse train of the found QRS on ECG signal');axis tight;
line(repmat(qrs_i_raw,[2 1]),repmat([min(ecg-mean(ecg))/2; max(ecg-mean(ecg))/2],size(qrs_i_raw)),'LineWidth',2.5,'LineStyle','-.','Color','r');
linkaxes(az,'x');
zoom on;
end
