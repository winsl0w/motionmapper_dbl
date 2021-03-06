function [Xs,Ys,angles,areas,svdskips] = ...
    align_subroutine_parallel_avi_ZW(grouping,initialPhi,segmentationOptions,nDigits,file_path,...
    image_path,readout,processorNum,asymThreshold,initialArea,vidObj,fid,areanorm,initialImage,ref,cenDat,refpad)
%align_subroutine_parallel_avi is a subroutine used within
%alignImages_Radon_parallel_avi in order to parallelize properly
%
%
% (C) Gordon J. Berman, 2014
%     Princeton University


%%
warning off MATLAB:audiovideo:aviread:FunctionToBeRemoved;
L = length(grouping);
Xs = zeros(L,1);
Ys = zeros(L,1);
angles = zeros(L,1);
areas = zeros(L,1);
svdskips = zeros(L,1);
%vidChunk = read(vidObj,[grouping(1) grouping(end)]);

open(image_path);


dilateSize = segmentationOptions.dilateSize;
cannyParameter = segmentationOptions.cannyParameter;
imageThreshold = segmentationOptions.imageThreshold;
spacing = segmentationOptions.spacing;
pixelTol = segmentationOptions.pixelTol;
basis = segmentationOptions.referenceImage;
maxAreaDifference = segmentationOptions.maxAreaDifference;
segmentationOff = segmentationOptions.segmentationOff;
symLine = segmentationOptions.symLine;
minRangeValue = segmentationOptions.minRangeValue;
maxRangeValue = segmentationOptions.maxRangeValue;

s = size(basis);
currentMinArea = ceil(initialArea*(1-maxAreaDifference));
segmentationOptions.area = currentMinArea;


%%
for j=2:L
    %%
    if mod(j,readout) == 0
        fprintf(1,'\t Processor #%2i, Image #%7i of %7i\n',processorNum,j,L);
    end
    
    k = grouping(j);
    nn = nDigits - 1 - floor(log(k+1e-10)/log(10));
    zzs  = repmat('0',1,nn);
    
    originalImage = read(vidObj,grouping(j));
    sCurrent = size(originalImage);

    b = [cenDat(k,1)-99 cenDat(k,2)-99 cenDat(k,1)+100 cenDat(k,2)+100] + refpad;
    refsub = ref(b(2):b(4),b(1):b(3));

    
    if sCurrent(1) < s(1) || sCurrent(2) < s(2)
        originalImage = bufferEdgeFrames(originalImage,imageThreshold,segmentationOptions);
        zz = uint8(zeros(s)+255);
        zz(1:sCurrent(1),1:sCurrent(2)) = originalImage;
        originalImage = zz;
    end
    if ~segmentationOff
        [imageOut,mask,bg] = segmentDiffIm(originalImage,refsub,dilateSize,cannyParameter,...
        imageThreshold,[],[],currentMinArea,true);
    
        xmid = size(originalImage,2)/2;
        xcen = sum(sum(imageOut,1).*(1:size(originalImage,2))./(sum(imageOut(:))));
        xoff = round(xcen-xmid);
        ymid = size(originalImage,1)/2;
        ycen = sum(sum(imageOut,2)'.*(1:size(originalImage,1))./(sum(imageOut(:))));
        yoff = round(ycen-ymid);
        
            if abs(xoff)>0.01*xmid
                tmpim = uint8(zeros(size(imageOut).*[1 2]));
                tmpim(:,xmid-xoff+1:xmid-xoff+size(imageOut,2))=imageOut;
                imageOut = tmpim(:,xmid+1:xmid+size(imageOut,2));
                clear tmpim
            end
            
            if abs(yoff)>0.01*ymid
                tmpim = uint8(zeros(size(imageOut).*[2 1]));
                tmpim(ymid-yoff+1:ymid-yoff+size(imageOut,1),:)=imageOut;
                imageOut = tmpim(ymid+1:ymid+size(imageOut,1),:);
                clear tmpim
            end
    
        imageOut = rescaleImage(imageOut,areanorm);
    else
        imageOut = originalImage;
        imageOut = rescaleImage(imageOut,areanorm);
    end
    
    clearvars originalImage
    
    areas(j) = sum(mask(:));
    currentMinArea = ceil((1-maxAreaDifference)*areas(j));
    segmentationOptions.area = currentMinArea;

    
    
    imageOut2 = imageOut;
    %hg=imageOut2(imageOut2>0);
    %asymThreshold = 180 + (218 - median(hg));
    imageOut2(imageOut2 < asymThreshold) = 0;
    %%
    if max(imageOut2(:)) ~= 0
    %%
        [angles(j),Xs(j),Ys(j),~,~,loopImage] = ...
            alignTwoImages(basis,imageOut2,initialPhi,spacing,pixelTol,false,imageOut);
        
        
        b = loopImage;
        b(b > asymThreshold + bg) = 0;
        
        if minRangeValue > 1
            b(1:minRangeValue-1,:) = 0;
        end
        
        if maxRangeValue < length(basis(:,1))
            b(maxRangeValue+1:end,:) = 0;
        end
        
        q = sum(b) ./ sum(b(:));
        
        asymValue = symLine - sum(q.*(1:s(1)));
        
        if asymValue < 0
           
            initialPhi = mod(initialPhi+180,360);
            [tempAngle,tempX,tempY,~,~,tempImage] = ...
                alignTwoImages(basis,imageOut2,initialPhi,spacing,pixelTol,false,imageOut);
            
            b = tempImage;
            b(b > asymThreshold) = 0;
            if minRangeValue > 1
                b(1:minRangeValue-1,:) = 0;
            end
            if maxRangeValue < length(basis(:,1))
                b(maxRangeValue+1:end,:) = 0;
            end
            
            q = sum(b) ./ sum(b(:));
            asymValue2 = symLine - sum(q.*(1:s(1)));
            
            if asymValue2 > asymValue
                angles(j) = tempAngle;
                Xs(j) = tempX;
                Ys(j) = tempY;
                loopImage = tempImage;
            end
        end
        
        
        %%
        
        initialPhi = angles(j);
        svdskips(j) = 0;
        writeVideo(image_path,loopImage);
        
    else
        
        angles(j) = angles(j-1);
        svdskips(j) = 1;
        loopImage = uint8(zeros(size(imageOut2)));
        writeVideo(image_path,loopImage);
        
    end

end
