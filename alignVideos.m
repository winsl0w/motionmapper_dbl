function [varargout] = alignVideos

%add utilities folder to path
addpath(genpath('./utilities/'));

info = what;

% prompt user for file path
[fDir] = uigetdir(info.path,...
    'Select directory containing .avi files to be aligned');

% find all avi files in 'filePath'
imageFiles = getHiddenMatDir(fDir,'ext','.avi');
L = length(imageFiles);
numZeros = ceil(log10(L+1e-10));

%define any desired parameter changes here
parameters.samplingFreq = 100;
parameters.trainingSetSize = 20000;

%initialize parameters
parameters = setRunParameters(parameters);

firstFrame = 1;
lastFrame = [];

%% Run Alignment

% prompt user to select target directory for aligned movies
[alignmentDirectory] = uigetdir(info.path,...
    'Select location to save aligned movies');
if ~exist(alignmentDirectory,'dir')
    mkdir(alignmentDirectory);
end
    

%run alignment for all files in the directory
fprintf(1,'Aligning Files\n');
alignmentFolders = cell(L,1);
fLabels = cell(L,1);
for i=1:L    
    
    fprintf(1,'\t Aligning File #%4i out of %4i\n',i,L);
    fileNum = [repmat('0',1,numZeros-length(num2str(i))) num2str(i)];
    [~,tmpLabel,~] = fileparts(imageFiles{i});
    fLabels(i) = {tmpLabel};
    tempDir = [alignmentDirectory 'alignment_' tmpLabel '/'];
    alignmentFolders{i} = tempDir;
    
    outputStruct = runAlignment(imageFiles{i},tempDir,firstFrame,lastFrame,parameters);
    
    save([tempDir '_outputStruct.mat'],'outputStruct');
    
    clear outputStruct
    clear fileNum
    clear tempDirectory
    
end


%% get aligned video files and labels
%{
alignmentFiles = getHiddenMatDir(alignmentDirectory,'ext','.avi');

% find all avi files in 'filePath'
a=dir(alignmentDirectory);
fLabel = cell(length(a),1);

for i = 1:length(a)
    if ~any(strcmp(a(i).name,{'.','..'}))
        fLabel(i) = {a(i).name};
    end
end

fLabel(cellfun(@isempty,fLabel)) = [];
%}

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


projectionsDirectory = [filePath './projections/'];
if ~exist(projectionsDirectory,'dir')
    mkdir(projectionsDirectory);
end

fprintf(1,'Finding Projections\n');
for i=1:L
    
    fprintf(1,'\t Finding Projections for File #%4i out of %4i\n',i,L);
    projections = findProjections(alignmentFolders{i},vecs,meanValues,pixels,parameters);
    projections = medfilt1(projections,3,[],1);
    fileNum = [repmat('0',1,numZeros-length(num2str(i))) num2str(i)];
    fileName = imageFiles{i};
    
    save([projectionsDirectory 'projections_' fileNum '.mat'],'projections','fileName');
    
    clear projections
    clear fileNum
    clear fileName 
    
end


%% Use subsampled t-SNE to find training set 

fprintf(1,'Finding Training Set\n');
[trainingSetData,trainingSetAmps,projectionFiles] = ...
    runEmbeddingSubSampling(projectionsDirectory,parameters);

%% Run t-SNE on training set
tic

fprintf(1,'Finding t-SNE Embedding for the Training Set\n');
[trainingEmbedding,betas,P,errors] = run_tSne(trainingSetData,parameters);
toc

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

