% AV Zoom: Complete Audio-Visual Tracking, Beamforming, and Analysis
% Outputs a single AVI file with both video and audio, and generates graphs.

%% 1. System Parameters & Setup
inputFile = 'C:\Users\swast\Documents\dsp10video.mp4';
outputFile = 'C:\Users\swast\Documents\Final_AV_Zoom.avi'; 

c = 343;                    % Speed of sound (m/s)
micSpacing = 0.08;          % Distance between mics (8 cm)
cameraFOV = 70;             % Camera Field of View in degrees
zoomScale = 0.5;            % 50% zoom crop factor

disp('Initializing AV Zoom System...');

% Setup Video and Audio Readers
vidReader = VideoReader(inputFile);
[audioIn, fs] = audioread(inputFile);
frameRate = vidReader.FrameRate;
frameWidth = vidReader.Width;
frameHeight = vidReader.Height;

% Verify stereo audio
if size(audioIn, 2) < 2
    error('The input video must contain a stereo audio track (2 channels).');
end

% Setup Face Detector
faceDetector = vision.CascadeObjectDetector('MergeThreshold', 7);

% Setup Video/Audio Muxing Writer (AVI format allows combined AV writing)
vidWriter = vision.VideoFileWriter(outputFile, ...
    'FileFormat', 'AVI', ...
    'AudioInputPort', true, ...
    'FrameRate', frameRate);

% Calculate chunk sizes for audio based on video framerate
samplesPerFrame = floor(fs / frameRate);
totalFrames = floor(size(audioIn, 1) / samplesPerFrame);

% Arrays to store data for graphing
angleHistory = zeros(totalFrames, 1);
delayHistory = zeros(totalFrames, 1);

disp('Starting AV Zoom Loop (Writing to single AVI)...');

%% 2. The Real-Time Synchronization Loop
for frameIdx = 1:totalFrames
    
    if ~hasFrame(vidReader)
        break;
    end
    
    % --- A. CAPTURE ---
    originalFrame = readFrame(vidReader);
    startSample = (frameIdx - 1) * samplesPerFrame + 1;
    endSample = frameIdx * samplesPerFrame;
    audioChunk = audioIn(startSample:endSample, 1:2);
    
    % --- B. VISUAL TARGETING (Computer Vision) ---
    bbox = step(faceDetector, originalFrame);
    
    if ~isempty(bbox)
        faceBox = bbox(1, :); % Grab the first detected face
        faceCenterX = faceBox(1) + (faceBox(3) / 2);
        faceCenterY = faceBox(2) + (faceBox(4) / 2);
        
        % Calculate DoA Angle
        normalizedX = (faceCenterX - (frameWidth / 2)) / (frameWidth / 2);
        targetAngleDeg = normalizedX * (cameraFOV / 2);
        
        % Define crop region for visual zoom
        cropW = frameWidth * zoomScale;
        cropH = frameHeight * zoomScale;
        cropX = max(1, faceCenterX - (cropW / 2));
        cropY = max(1, faceCenterY - (cropH / 2));
        cropRect = [cropX, cropY, cropW, cropH];
    else
        % Fallback if face is lost
        targetAngleDeg = 0;
        cropRect = [(frameWidth*(1-zoomScale))/2, (frameHeight*(1-zoomScale))/2, ...
                    frameWidth*zoomScale, frameHeight*zoomScale];
    end
    
    % Apply visual crop and resize back to original resolution
    zoomedFrame = imcrop(originalFrame, cropRect);
    finalFrame = imresize(zoomedFrame, [frameHeight, frameWidth]);
    
    % --- C. AUDIO BEAMFORMING (DSP) ---
    targetAngleRad = deg2rad(targetAngleDeg);
    timeDelay = (micSpacing * sin(targetAngleRad)) / c;
    sampleDelay = round(timeDelay * fs);
    
    % Store data for graphs
    angleHistory(frameIdx) = targetAngleDeg;
    delayHistory(frameIdx) = sampleDelay;
    
    zoomedAudio = zeros(samplesPerFrame, 1);
    if sampleDelay > 0
        shiftedMic1 = [zeros(sampleDelay, 1); audioChunk(1:end-sampleDelay, 1)];
        zoomedAudio = (shiftedMic1 + audioChunk(:, 2)) / 2;
    elseif sampleDelay < 0
        sampleDelay = abs(sampleDelay); 
        shiftedMic2 = [zeros(sampleDelay, 1); audioChunk(1:end-sampleDelay, 2)];
        zoomedAudio = (audioChunk(:, 1) + shiftedMic2) / 2;
    else
        zoomedAudio = (audioChunk(:, 1) + audioChunk(:, 2)) / 2;
    end
    
    % --- D. WRITE COMBINED OUTPUT ---
    % Write both the visual frame and the audio chunk at the exact same time
    step(vidWriter, finalFrame, zoomedAudio);
    
    if mod(frameIdx, 30) == 0
        fprintf('Processed Frame %d/%d (Angle: %0.1f deg)\n', frameIdx, totalFrames, targetAngleDeg);
    end
end

%% 3. Finalize and Save
release(vidWriter);
disp('Processing Complete!');
disp(['Combined AV file saved to: ', outputFile]);

%% 4. Generate System Analysis Graphs
figure('Name', 'AV Zoom System Analysis', 'Position', [100, 100, 800, 600]);

% Graph 1: Visual Tracking Angle
subplot(2,1,1);
plot(1:totalFrames, angleHistory, 'b-', 'LineWidth', 1.5);
title('Computer Vision: Tracked Face Angle (Direction of Arrival)');
xlabel('Frame Number');
ylabel('Angle (Degrees)');
grid on;

% Graph 2: DSP Audio Delay
subplot(2,1,2);
plot(1:totalFrames, delayHistory, 'r-', 'LineWidth', 1.5);
title('DSP: Dynamic Audio Sample Delay Applied');
xlabel('Frame Number');
ylabel('Delay (Samples)');
grid on;
