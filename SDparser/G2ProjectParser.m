function success = G2ProjectParser(projectfolder)
% function to read in relevant JSON files of a Tobii Projects folder and
% create a human-readable lookup table in the project folder that can then
% be used by recordingSelector, which selects a recording for the
% glassesviewer or GazeCode

[projects, nproj] = FolderFromFolder(projectfolder);

if ~isempty(which('matlab.internal.webservices.fromJSON'))
    jsondecoder = @matlab.internal.webservices.fromJSON;
elseif ~isempty(which('jsondecode'))
    jsondecoder = @jsondecode;
else
    error('Your MATLAB version does not provide a way to decode json (which means its really old), upgrade to something newer');
end

fid = [];   % only open the lookup file once we have something to write in it
for p = 1:nproj
    % for each folder in projects find projectName in project.json
    projects(p).jsonfile = fullfile(projectfolder, projects(p).name, 'project.json');
    if exist(projects(p).jsonfile,'file')~=2
        warning('No project.json file found for: %s\n',projectfolder);
        continue;
    end
    
    json = jsondecoder(fileread(projects(p).jsonfile));
    
    projects(p).ID          = json.pr_id;
    if isfield(json.pr_info,'Name')
        projects(p).name = json.pr_info.Name;
    else
        projects(p).name = json.pr_info.name;
    end
    projects(p).createdate  = datenum(json.pr_created,'yyyy-mm-ddTHH:MM:SS');    % G2 times are always UTC (denoted by +0000 suffix), which we can ignore.
    
    % get what recording folders we have -- required
    recorddir = fullfile(projectfolder, projects(p).ID, 'recordings');
    assert(exist(recorddir,'dir')==7,'Recordings directory missing, expected: %s\n',recorddir);
    recmappen = FolderFromFolder(recorddir);
    
    % get what calibration folders we have -- optional but recommended to
    % keep these, as they are the only place where calibration status is
    % noted
    calibdir = fullfile(projectfolder, projects(p).ID, 'calibrations');
    qHaveCalibs = exist(calibdir,'dir')==7;
    if ~qHaveCalibs
        warning('Calibrations directory missing, cannot determine calibration status of recordings. Expected: %s\n',calibdir);
    end
    
    % get what participant folders we have -- only contain redundant info,
    % but lets warn anyway if they are missing
    partdir = fullfile(projectfolder, projects(p).ID, 'participants');
    if ~exist(partdir,'dir')==7
        warning('Participants directory missing, expected %s\n',partdir);
    end
    
    
    % run over recordings, copying over relevant calibrations and
    % participant info as we go
    clear recs
    [recs(1:length(recmappen)).recID] = recmappen.name;
    for q=1:length(recs)
        [...
            recs(q).recName,recs(q).recStartT,recs(q).recNotes,...
            recs(q).partID,recs(q).partName,recs(q).partNotes,...
            recs(q).calID,recs(q).calStatus,...
            recs(q).sysFWVersion,recs(q).sysHUSerial,recs(q).sysRUSerial,recs(q).sysEyeCamSetting,recs(q).sysSceneCamSetting...
            ] = deal('!!unknown');
        
        recjson = jsondecoder(fileread((fullfile(recorddir, recs(q).recID, 'recording.json'))));
        
        % get recording info
        if isfield(recjson.rec_info,'Name')
            recs(q).recName = recjson.rec_info.Name;
        else
            recs(q).recName = recjson.rec_info.name;
        end
        if isfield(recjson.rec_info,'Notes')
            recs(q).recNotes= recjson.rec_info.Notes;
        elseif isfield(recjson.rec_info,'notes')
            recs(q).recNotes= recjson.rec_info.notes;
        end
        if isfield(recjson,'rec_created')
            recs(q).recStartT = datenum(recjson.rec_created,'yyyy-mm-ddTHH:MM:SS');
        end
        
        % get participant info
        if isfield(recjson,'rec_participant')
            recs(q).partID = recjson.rec_participant;
            partjsonfile = fullfile(recorddir, recs(q).recID, 'participant.json');
            if exist(partjsonfile,'file')==2
                partjson = jsondecoder(fileread(partjsonfile));
                if isfield(partjson.pa_info,'Name')
                    recs(q).partName = partjson.pa_info.Name;
                else
                    recs(q).partName = partjson.pa_info.name;
                end
                if isfield(partjson.pa_info,'Notes')
                    recs(q).partNotes= partjson.pa_info.Notes;
                elseif isfield(partjson.pa_info,'notes')
                    recs(q).partNotes= partjson.pa_info.notes;
                end
            end
        end
        
        % get calibration info
        if isfield(recjson,'rec_calibration')
            recs(q).calID = recjson.rec_calibration;
            caljsonfile = fullfile(calibdir,recs(q).calID,'calibration.json');
            if qHaveCalibs && exist(caljsonfile,'file')==2
                calibjson = jsondecoder(fileread(caljsonfile));
                recs(q).calStatus = calibjson.ca_state;
            end
        end
        
        % get system/setup info
        sysjsonfile = fullfile(recorddir, recs(q).recID, 'sysinfo.json');
        if exist(sysjsonfile,'file')==2
            sysjson = jsondecoder(fileread(sysjsonfile));
            if isfield(sysjson,'servicemanager_version')
                recs(q).sysFWVersion = sysjson.servicemanager_version;
            end
            if isfield(sysjson,'hu_serial')
                recs(q).sysHUSerial = sysjson.hu_serial;
            end
            if isfield(sysjson,'ru_serial')
                recs(q).sysRUSerial = sysjson.ru_serial;
            end
            if isfield(sysjson,'sys_ec_preset')
                recs(q).sysEyeCamSetting = sysjson.sys_ec_preset;
            end
            if isfield(sysjson,'sys_sc_preset')
                recs(q).sysSceneCamSetting = sysjson.sys_sc_preset;
            end
        end
        
        if isempty(fid)
            fid = fopen(fullfile(projectfolder,'lookup.xls'),'wt');
            fprintf(fid,'ProjectID\tParticipantID\tRecordingID\tCalibrationID\tProjectName\tProjectCreateTime\tParticipantName\tParticipantNotes\tRecordingName\tRecordingStartTime\tRecordingNotes\tCalibrationStatus\tFirmwareVersion\tHeadUnitSerial\tRecordingUnitSerial\tEyeCameraSetting\tSceneCameraSetting\n');
        end
        
        fmt = repmat('%s\t',1,17); fmt(end) = 'n';
        fprintf(fid,fmt,projects(p).ID,recs(q).partID,recs(q).recID,recs(q).calID,projects(p).name,datestr(projects(p).createdate,'yyyy-mm-dd HH:MM:SS'),recs(q).partName,recs(q).partNotes,recs(q).recName,datestr(recs(q).recStartT,'yyyy-mm-dd HH:MM:SS'),recs(q).recNotes,recs(q).calStatus,recs(q).sysFWVersion,recs(q).sysHUSerial,recs(q).sysRUSerial,recs(q).sysEyeCamSetting,recs(q).sysSceneCamSetting);
    end
end
success = ~isempty(fid);
if success
    fclose(fid);
end