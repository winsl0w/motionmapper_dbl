%%example script that will run the code for a set of .avi files that are
%%found in filePath

%add utilities folder to path
addpath(genpath('./utilities/'));

info = what;
[parameters.mapdir,~,~] = fileparts(which('runExample'));
addpath(genpath(mapdir));

% prompt user for file path
[fDir] = uigetdir(info.path,...
    'Select directory containing .avi files to be aligned');

% find all avi files in 'filePath'
imageFiles = getHiddenMatDir(fDir,'ext','.avi');
L = length(imageFiles);
numZeros = ceil(log10(L+1e-10));

%define any desired parameter changes here
parameters.samplingFreq = 100;
parameters.trainingSetSize = 5000;
parameters.mapdir = mapdir;

%initialize parameters
parameters = setRunParameters(parameters);

firstFrame = 1;
lastFrame = [];

%% Run Alignment

% prompt user to select target directory for aligned movies
[alignmentDirectory] = uigetdir(info.path,...
    'Select location to save aligned movies');
alignmentDirectory = [alignmentDirectory '\'];
if ~exist(alignmentDirectory,'dir')
    mkdir(alignmentDirectory);
end
    

%run alignment for all files in the directory
fprintf(1,'Aligning Files\n');
alignmentFolders = cell(L,1);
for i=1:L    
    
    fprintf(1,'\t Aligning File #%4i out of %4i\n',i,L);
    
    fileNum = [repmat('0',1,numZeros-length(num2str(i))) num2str(i)];
    [~,fLabel,~] = fileparts(imageFiles{i});
    tempDirectory = [alignmentDirectory 'alignment_' fLabel '/'];
    alignmentFolders{i} = tempDirectory;
    
    outputStruct = runAlignment(imageFiles{i},tempDirectory,firstFrame,lastFrame,parameters);
    
    save([tempDirectory 'outputStruct.mat'],'outputStruct');
    
    clear outputStruct
    clear fileNum
    clear tempDirectory
    
end


%% Find image subset statistics (a gui will pop-up here)

fprintf(1,'Finding Subset Statistics\n');
numToTest = parameters.pca_batchSize;
[pixels,thetas,means,stDevs,vidObjs] = findRadonPixels(alignmentDirectory,numToTest,parameters);

%% Find postural eigenmodes

fprintf(1,'Finding Postural Eigenmodes\n');
[vecs,vals,meanValues] = findPosturalEigenmodes(vidObjs,pixels,parameters);

vecs = vecs(:,1:parameters.numProjections);

figure
makeMultiComponentPlot_radon_fromVecs(vecs(:,1:25),25,thetas,pixels,[201 90]);
caxis([-3e-3 3e-3])
colorbar
title('First 25 Postural Eigenmodes','fontsize',14,'fontweight','bold');
drawnow;


%% Find projections for each data set

projectionsDirectory = [alignmentDirectory './projections/'];
if ~exist(projectionsDirectory,'dir')
    mkdir(projectionsDirectory);
end

fprintf(1,'Finding Projections\n');
for i=5:L
    
    fprintf(1,'\t Finding Projections for File #%4i out of %4i\n',i,L);
    projections = findProjections(alignmentFolders{i},vecs,meanValues,pixels,parameters);
    projections = medfilt1(projections,3,[],1);
    [~,fLabel,~] = fileparts(alignmentFolders{i});
    
    save([projectionsDirectory 'projections_' fLabel '.mat'],'projections');
    
    clear projections
    clear fileNum
    clear fileName 
    
end


%% Use subsampled t-SNE to find training set 

fprintf(1,'Finding Training Set\n');
[trainingSetData,trainingSetAmps,projectionFiles] = ...
    runEmbeddingSubSampling(projectionsDirectory,parameters);

%% Run t-SNE on training set


fprintf(1,'Finding t-SNE Embedding for the Training Set\n');
[trainingEmbedding,betas,P,errors] = run_tSne(trainingSetData,parameters);


%% Find Embeddings for each file

fprintf(1,'Finding t-SNE Embedding for each file\n');
embeddingValues = cell(L,1);
for i=1:L
    
    fprintf(1,'\t Finding Embbeddings for File #%4i out of %4i\n',i,L);
    
    load(projectionFiles{i},'projections');
    projections = projections(:,1:parameters.pcaModes);
    
    [embeddingValues{i},~] = ...
        findEmbeddings(projections,trainingSetData,trainingEmbedding,parameters);

    clear projections
    
end

embeddingDirectory = [alignmentDirectory 'embeddingValues\'];
if ~exist(embeddingDirectory,'dir')
    mkdir(embeddingDirectory);
end
save([embeddingDirectory 'embeddingValues.mat'],'embeddingValues');

%% Make density plots


addpath(genpath('./t_sne/'));
addpath(genpath('./utilities/'));

maxVal = max(max(abs(combineCells(embeddingValues))));
maxVal = round(maxVal * 1.1);

sigma = maxVal / 40;
numPoints = 501;
rangeVals = [-maxVal maxVal];

[xx,density] = findPointDensity(combineCells(embeddingValues),sigma,numPoints,rangeVals);

densities = zeros(numPoints,numPoints,L);
for i=1:L
    [~,densities(:,:,i)] = findPointDensity(embeddingValues{i},sigma,numPoints,rangeVals);
end


figure
maxDensity = max(density(:));
imagesc(xx,xx,density)
axis equal tight off xy
caxis([0 maxDensity * .8])
colormap(jet)
colorbar



figure

N = ceil(sqrt(L));
M = ceil(L/N);
maxDensity = max(densities(:));
for i=1:L
    subplot(M,N,i)
    imagesc(xx,xx,densities(:,:,i))
    axis equal tight off xy
    caxis([0 maxDensity * .8])
    colormap(jet)
    title(['Data Set #' num2str(i)],'fontsize',12,'fontweight','bold');
end



%% get speed in t-SNE space

z = cellfun(@(x) sqrt([0;diff(x(:,1))].^2 + [0;diff(x(:,2))].^2).*100,...
    embeddingValues,'UniformOutput',false);

figure();
c=ceil(sqrt(L));
r = ceil(L/c);

for i = 1:L
    
    subplot(r,c,i);
    histogram(log10(z{i}),linspace(-4,4,500));
    set(gca,'XLim',[-2 5],'Ytick',[]);
    xlabel('log(speed)');
    title(['embedded speed histogram fly #' num2str(i)]);
    
end

%% plot position sample

figure();
f1 = 50000;
frame_range = f1:f1+20*100;

for i = 1:L
    
    subplot(r,c,i);
    hold on
    plot(embeddingValues{i}(frame_range,1),'r','Linewidth',1.5);
    plot(embeddingValues{i}(frame_range,2),'b','Linewidth',1.5);
    hold off
    set(gca,'YLim',[-100 100],'XLim',[1 length(frame_range)],...
        'Xtick',linspace(1,length(frame_range),5),'XTickLabel',0:5:20);
    ylabel('position');
    xlabel('time(s)');
    title(['fly #' num2str(i)]);
    
    
end

%% assign classification identity to all points

frameIDs = cell(size(embeddingValues));

for i=1:length(embeddingValues)
    
    % shift embedding values to image indices
    emIdx = round(embeddingValues{i}.*(numPoints/abs(diff(rangeVals)))+(numPoints/2));
    emIdx = sub2ind(size(idxMap),emIdx(:,2),emIdx(:,1));
    frameIDs(i) = {idxMap(emIdx)};
    
end

%% color watershed by number of individuals per mode

modeIDs = unique(idxMap(:));
pdfs = cellfun(@(x) histc(x,1:length(modeIDs))',frameIDs,'UniformOutput',false)';
pdfs = cat(1,pdfs{:});
pdfs = pdfs./repmat(sum(pdfs,2),1,size(pdfs,2));
figure;
subplot(2,1,1);
imagesc(pdfs);
axis equal tight
colorbar
subplot(2,1,2);
imagesc(log(pdfs));
axis equal tight
colorbar
molaspass=interp1([1 51 102 153 204 256],[0 0 0; 0 0 .75; .5 0 .8; 1 .1 0; 1 .9 0; 1 1 1],1:256);
colormap(molaspass);
title('behavioral mode PDFs');
ylabel('individual flies');
xlabel('mode no.');

% count a fly as visiting a mode at least once if move than 10 frames are
% labeled as a particular identity
figure;
fliesPerMode = sum(pdfs>2.7778e-05)./size(pdfs,1);
fpm = zeros(size(idxMap));
modeCentroid = NaN(length(modeIDs),2);
idxMap_bordered = idxMap;
idxMap_bordered(binim)=0;
mask=density<0.000001;
border = edge(mask,'Canny');
idxMap_bordered(mask)=0;

for i=1:modeIDs(end)
    modeMask = idxMap_bordered==modeIDs(i);
    props = regionprops(modeMask,'Centroid');
    if ~isempty(props)
        modeCentroid(i,:) = props(1).Centroid;
    end
    fpm(modeMask)=fliesPerMode(i);
end

% ensure boundaries are set to blank
fpm(binim)=0;

fpm(mask)=1;
fpm(border)=0;
imagesc(fpm);
axis equal tight off
hm=interp1(round(linspace(1,256,4)),[0 0 0; 0 0 .75; .5 0 .8; 1 .1 0],1:256);
colormap(hm);
colorbar
title('no. flies visiting each mode');

for i=1:length(modeCentroid)
    text(modeCentroid(i,1),modeCentroid(i,2),...
        num2str(modeIDs(i)),'Color',[1 1 1],...
        'HorizontalAlignment','center');
end

%% find examples of each mode

% break up each mode into runs and find all bouts greater than 
% the specified length for sampling
allModes = unique(idxMap);
targetDuration = 70;
[starts,stops,durations,sampleFrames,sampleDurations] = cellfun(@(x) ...
    modeBouts(x,allModes,targetDuration),frameIDs,'UniformOutput',false);

% get the median duration of each mode and find bouts greater than target
durations = cat(2,durations{:});
durations = num2cell(durations,2);
[medianDurations] = cellfun(@(x) modeDurations(x),durations,'UniformOutput',false);
medianDurations = cat(1,medianDurations{:});

% create sample movies of each mode
sampleFrames =cat(2,sampleFrames{:});
nSamples = cellfun(@length,sampleFrames);
samplesPerMode = sum(nSamples,2);

% generate sampling vector for each mode
movieVec = cellfun(@getModeMovieVector,num2cell(sampleFrames,2),...
    num2cell(nSamples,2),'UniformOutput',false);

%% make mode movies

% select directory containing video Files
[fDir] = uigetdir(info.path,...
    'Select directory containing videos for mode sampling');
vidFiles = getHiddenMatDir(fDir,'ext','.avi')';
if length(vidFiles) > length(alignmentFolders)
    %[dirs,~,~]=cellfun(@fileparts,vidFiles,'UniformOutput',false);
   vidFiles = reshape(vidFiles',4,length(vidFiles)/4)';
   vidFiles = num2cell(vidFiles,2);
end    

% initialize video reader objects
vidObjs = cellfun(@initializeVidObjs,vidFiles,'UniformOutput',false);
if iscell(vidObjs{1})
    vidObjs = cat(1,vidObjs{:});
end

% prompt user for save path
[saveDir] = uigetdir(info.path,...
    'Select directory to save videos');
nTiles = [8 8];
for i=1:size(movieVec,1)
    
    savePath = [saveDir '\tiledSample_mode' num2str(i) '.avi'];
    modeMovie(movieVec{i},vidObjs,nTiles,targetDuration,savePath,i);

end







