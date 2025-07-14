function preprocessingGUI()
    % Create the main GUI window
    fig = uifigure('Name', 'Data Preprocessing GUI', 'Position', [100, 100, 400, 500]);

    % Title Label
    uilabel(fig, 'Position', [100, 450, 200, 40], 'Text', 'Preprocessing Workflow', 'FontSize', 16);

    % Folder Path Input and Browse Button
    folderLabel = uilabel(fig, 'Position', [20, 400, 100, 20], 'Text', 'Folder Path:');
    folderPathField = uieditfield(fig, 'text', 'Position', [120, 400, 180, 20]);
    browseButton = uibutton(fig, 'push', 'Position', [310, 400, 70, 20], 'Text', 'Browse', ...
        'ButtonPushedFcn', @(~, ~) browseFolder(folderPathField));

    % Import and Preprocess Button
    importButton = uibutton(fig, 'push', 'Position', [100, 340, 200, 30], 'Text', '1. Import and Preprocess', ...
        'ButtonPushedFcn', @(~, ~) importPreprocess(folderPathField.Value));

    % Remove Artifacts Button
    artifactButton = uibutton(fig, 'push', 'Position', [100, 290, 200, 30], 'Text', '2. Remove Artifacts', ...
        'ButtonPushedFcn', @(~, ~) removeArtifacts());

    % Segment Data Button
    segmentButton = uibutton(fig, 'push', 'Position', [100, 240, 200, 30], 'Text', '3. Segment Data', ...
        'ButtonPushedFcn', @(~, ~) segmentData());

    % Aggregate Data by Channel Button
    aggregateButton = uibutton(fig, 'push', 'Position', [100, 190, 200, 30], 'Text', '4. Aggregate Data by Channel', ...
        'ButtonPushedFcn', @(~, ~) segmentsByChannel());

    % Status label to show messages
    statusLabel = uilabel(fig, 'Position', [20, 140, 360, 30], 'Text', '', 'FontSize', 12, 'HorizontalAlignment', 'center');
    updateStatus(statusLabel, 'Ready to start preprocessing');
    
    % Nested Helper Functions
    function browseFolder(field)
        folderPath = uigetdir();
        if folderPath ~= 0
            field.Value = folderPath;
        end
    end

    function importPreprocess(folderPath)
        updateStatus(statusLabel, 'Running Import and Preprocess...');
        try
            [dataAll, orig_dataAll] = import_preprocess(folderPath);
            assignin('base', 'dataAll', dataAll);
            assignin('base', 'orig_dataAll', orig_dataAll);
            updateStatus(statusLabel, 'Import and Preprocess completed.');
        catch ME
            updateStatus(statusLabel, ['Error: ' ME.message]);
        end
    end

    function removeArtifacts()
        updateStatus(statusLabel, 'Running Remove Artifacts...');
        try
            dataAll = evalin('base', 'dataAll');
            orig_dataAll = evalin('base', 'orig_dataAll');
            [dataAll, dataset_checker] = remove_artifacts(dataAll, orig_dataAll);
            assignin('base', 'dataAll', dataAll);
            assignin('base', 'dataset_checker', dataset_checker);
            updateStatus(statusLabel, 'Remove Artifacts completed.');
        catch ME
            updateStatus(statusLabel, ['Error: ' ME.message]);
        end
    end

    function segmentData()
        updateStatus(statusLabel, 'Running Segment Data...');
        try
            dataAll = evalin('base', 'dataAll');
            dataset_checker = evalin('base', 'dataset_checker');
            [dataAll_by_dates, dataSegments] = segment_data(dataAll, dataset_checker);
            assignin('base', 'dataAll_by_dates', dataAll_by_dates);
            assignin('base', 'dataSegments', dataSegments);
            updateStatus(statusLabel, 'Segment Data completed.');
        catch ME
            updateStatus(statusLabel, ['Error: ' ME.message]);
        end
    end

    function segmentsByChannel()
        % Input dialog for channel and data type (symptom_onset or non_event)
        prompt = {'Enter channel name:', 'Enter data type (symptom_onset or non_event):'};
        dlgtitle = 'Input';
        dims = [1 50];
        definput = {'C_1', 'symptom_onset'};
        answer = inputdlg(prompt, dlgtitle, dims, definput);
        
        if ~isempty(answer)
            channel = answer{1};
            dataType = answer{2};
            updateStatus(statusLabel, 'Running Aggregate Data by Channel...');
            try
                dataSegments = evalin('base', 'dataSegments');
                segments_channel = segments_by_channel(dataSegments, channel, dataType);
                assignin('base', 'segments_channel', segments_channel);
                updateStatus(statusLabel, 'Aggregate Data by Channel completed.');
            catch ME
                updateStatus(statusLabel, ['Error: ' ME.message]);
            end
        else
            updateStatus(statusLabel, 'Channel aggregation canceled.');
        end
    end

    function updateStatus(label, message)
        label.Text = message;
    end
end