% ---------- USER INPUT ----------
aim_record_folder = '/Users/sihanliang/monkeylab/LFP/dog_newdata/dog_202407_cracked/2024_07_08';
IPG_SN = '1030L00016';
PKT_TOTAL_POINTS = 40;
MAX_TI_GAP = 500;
% ---------------------------------

record_subfolders = getsubfolders(aim_record_folder);
disp('>>>> aim_record_folder = '); disp(aim_record_folder);
disp('>>>> Found subfolders (direct children):');
if isempty(record_subfolders)
    error('No subfolders found one level under aim_record_folder. Point to the DATE-level folder.');
end
disp(strjoin(record_subfolders, ' | '));
sel = contains(record_subfolders, IPG_SN) & ~contains(record_subfolders, 'pro_');
if ~any(sel)
    warning('No subfolders matched IPG_SN = %s. Falling back to all non-pro_ subfolders.', IPG_SN);
    sel = ~contains(record_subfolders, 'pro_');
end
record_subfolders = record_subfolders(sel);

for i = 1:numel(record_subfolders)
    fprintf('\n>>>> Processing: %s\n', record_subfolders{i});
    tmp_record_subfolder = fullfile(aim_record_folder, record_subfolders{i});
    tmp_record_files = getfiles(tmp_record_subfolder);

    txtIdx = find(endsWith(tmp_record_files, '.txt', 'IgnoreCase', true), 1);
    uvIdx  = find(endsWith(tmp_record_files, '_uv.csv', 'IgnoreCase', true), 1);
    if isempty(uvIdx)
        uvIdx = find(endsWith(tmp_record_files, '.csv', 'IgnoreCase', true), 1);
    end
    if isempty(txtIdx) || isempty(uvIdx)
        fprintf('>>>> SKIP (missing .txt or .csv): %s\n', tmp_record_subfolder);
        continue
    end

    txtFile = fullfile(tmp_record_subfolder, tmp_record_files{txtIdx});
    uvFile  = fullfile(tmp_record_subfolder, tmp_record_files{uvIdx});
    tmp_data_tbl = readtable(uvFile, 'VariableNamingRule','preserve');
    if height(tmp_data_tbl) < 3
        fprintf('>>>> SKIP (CSV empty): %s\n', uvFile);
        continue
    end

    % Determine Time Index column
    if ismember('Time Index', tmp_data_tbl.Properties.VariableNames)
        TI = tmp_data_tbl.('Time Index');
    elseif ismember('Packet Index', tmp_data_tbl.Properties.VariableNames)
        TI = tmp_data_tbl.('Packet Index');
        fprintf('>>>> Using Packet Index as Time Index.\n');
    else
        warning('>>>> Neither Time Index nor Packet Index found. Skipping session.');
        continue
    end
    assert(isnumeric(TI), 'Time Index is not numeric.');

    fileID = fopen(txtFile,'r');
    assert(fileID > 0, 'fopen failed: %s', txtFile);
    tmp_txt_cell = textscan(fileID, '%s', 'Delimiter', '\n', 'Whitespace','');
    fclose(fileID);
    tmp_txt_cell = tmp_txt_cell{1};

    % --- Channel and sample rate
    electrodes_line = tmp_txt_cell{find(contains(tmp_txt_cell,'Electrodes'), 1)};
    str = regexprep(electrodes_line, 'Electrodes\s+', '');
    num_pairs = strtrim(strsplit(str, ','));
    num_ch = numel(num_pairs);
    sampleRate_line = tmp_txt_cell{find(contains(tmp_txt_cell, 'Sample Frequency'), 1)};
    sr_tokens = regexp(sampleRate_line, '\d+', 'match');
    sampleRate = str2double(sr_tokens{1});

    % --- Time
    startLineIdx = find(contains(tmp_txt_cell, '[Start Time]'), 1);
    endLineIdx   = find(contains(tmp_txt_cell, '[End Time]'), 1);
    has_start = ~isempty(startLineIdx) && (startLineIdx + 1 <= numel(tmp_txt_cell));
    has_end   = ~isempty(endLineIdx) && (endLineIdx + 1 <= numel(tmp_txt_cell));

    if has_start
        startTime = tmp_txt_cell{startLineIdx + 1};
        startTime_obj = datetime(startTime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
    else
        [~, base_name, ~] = fileparts(txtFile);
        tokens = regexp(base_name, '\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}$', 'match');
        assert(~isempty(tokens), 'Cannot infer time from filename: %s', base_name);
        dt_parts = str2double(strsplit(tokens{1}, '_'));
        startTime_obj = datetime(dt_parts, 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
        startTime = datestr(startTime_obj, 'yyyy-mm-dd HH:MM:SS.FFF');
        fprintf('>>>> [Start Time] missing, using from filename: %s\n', startTime);
    end

    points_per_ch_per_row = round(PKT_TOTAL_POINTS / num_ch);
    num_samples = height(tmp_data_tbl) * points_per_ch_per_row;

    if has_end
        endTime = tmp_txt_cell{endLineIdx + 1};
        endTime_obj = datetime(endTime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
    else
        dur_sec = num_samples / sampleRate;
        endTime_obj = startTime_obj + seconds(dur_sec);
        endTime = datestr(endTime_obj, 'yyyy-mm-dd HH:MM:SS.FFF');
        fprintf('>>>> [End Time] missing, estimated as: %s\n', endTime);
    end
    recDur = seconds(endTime_obj - startTime_obj);
    fprintf('>>>> Duration: %.2f seconds\n', recDur);

    % --- Reconstruct time series
    disp(">>>> Reconstructing time series ...");
    use_tag = ismember('Tag Index', tmp_data_tbl.Properties.VariableNames) && ...
              isnumeric(tmp_data_tbl.('Tag Index'));
    if use_tag
        [~, order] = sortrows([TI, tmp_data_tbl.('Tag Index')], [1 2]);
    else
        [~, order] = sortrows(TI, 1);
    end
    tmp_data_tbl = tmp_data_tbl(order, :);
    TI = TI(order);

    channels_data = cell(1, num_ch);
    global_pack = -1; prev_TI = [];
    for r = 1:height(tmp_data_tbl)
        this_TI = TI(r);
        if ~isempty(prev_TI)
            gap = this_TI - prev_TI;
            if gap > 1 && gap <= MAX_TI_GAP
                for g = 1:(gap - 1)
                    global_pack = global_pack + 1;
                    for k = 1:num_ch
                        nan_block = [repmat(global_pack, points_per_ch_per_row, 1), ...
                                     nan(points_per_ch_per_row, 1)];
                        channels_data{k}(end+1:end+points_per_ch_per_row, :) = nan_block;
                    end
                end
            elseif gap > MAX_TI_GAP
                fprintf('>>>> Warning: abnormal TI gap = %d, skipping filler.\n', gap);
            end
        end
        global_pack = global_pack + 1;
        row = tmp_data_tbl(r, :);
        for k = 1:num_ch
            ch_col = ['CH', num2str(k)];
            is_ch = ~cellfun(@isempty, regexp(row.Properties.VariableNames, ['^', ch_col], 'once'));
            vals = row{1, is_ch}; vals = vals(:);
            vals = padarray(vals, max(0, points_per_ch_per_row - numel(vals)), nan, 'post');
            vals = vals(1:points_per_ch_per_row);
            block = [repmat(global_pack, points_per_ch_per_row, 1), vals];
            channels_data{k}(end+1:end+points_per_ch_per_row, :) = block;
        end
        prev_TI = this_TI;
    end

    % --- Final assembly
    N = size(channels_data{1},1);
    data_matrix = nan(N, 1+num_ch);
    data_matrix(:,1) = channels_data{1}(:,1);
    for k = 1:num_ch
        data_matrix(:,1+k) = channels_data{k}(:,2);
    end

    lossRate = cellfun(@(x) sum(isnan(x(:,2)))/size(x,1), channels_data);
    lossStr = strjoin(arrayfun(@(x) sprintf('%.2f%%', x*100), lossRate, 'UniformOutput', false), ', ');
    fprintf('>>>> Data loss: [%s]\n', lossStr);

    % --- Plot
    t = (1:N) ./ sampleRate;
    figure('Visible','on'); plot(t, data_matrix(:,2:end));
    title(strrep(uvFile, '_', '\_'));
    xlabel('Time (s)'); ylabel('Amplitude (µV)');
    legend(num_pairs, 'Location', 'best');
    try, movegui(gcf, 'center'); catch, end

    % --- Save
    out_folder = fullfile(aim_record_folder, ['pro_', record_subfolders{i}]);
    if ~exist(out_folder, 'dir'); mkdir(out_folder); end
    [~, base, ~] = fileparts(uvFile);
    out_csv = [base, '_sr.csv'];
    out_fig = [base, '_tsr.fig'];
    loss_tbl = array2table(lossRate, 'VariableNames', matlab.lang.makeValidName(num_pairs));
    loss_file = [base, '_DataLoss.csv'];

    writetable(array2table(data_matrix, ...
        'VariableNames', ['PackageIdx', matlab.lang.makeValidName(num_pairs)]), ...
        fullfile(out_folder, out_csv));
    writetable(loss_tbl, fullfile(out_folder, loss_file));
    savefig(gcf, fullfile(out_folder, out_fig));
    close(gcf);
end

% --------- UTIL ---------
function subfolders = getsubfolders(folder_path)
    d = dir(folder_path);
    subfolders = {d([d.isdir] & ~ismember({d.name},{'.','..'})).name};
end

function files = getfiles(folder_path)
    d = dir(folder_path);
    files = {d(~[d.isdir]).name};
end
