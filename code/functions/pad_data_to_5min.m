function dataAll_padded = pad_data_to_5min(dataAll, fsample)
    if nargin < 2
        fsample = 415;
    end
    target_len = 5 * 60 * fsample; % 124500 samples for 5 minutes

    dataAll_padded = dataAll;

    for i = 1:numel(dataAll)
        if isempty(dataAll{i}) || ~isfield(dataAll{i}, 'trial'), continue; end

        trial_mat = dataAll{i}.trial{1};  % [channels x samples]
        time_vec = dataAll{i}.time{1};    % [1 x samples]
        current_len = size(trial_mat, 2);

        if current_len < target_len
            pad_len = target_len - current_len;

            % pad trial with 0s
            trial_padded = [trial_mat, zeros(size(trial_mat,1), pad_len)];

            % pad time with correct dt
            dt = 1 / fsample;
            time_padded = [time_vec, time_vec(end) + dt*(1:pad_len)];

            % assign back
            dataAll_padded{i}.trial{1} = trial_padded;
            dataAll_padded{i}.time{1} = time_padded;
            dataAll_padded{i}.sampleinfo = [1 target_len];
            
        
            
        end
    end
end