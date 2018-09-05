function [obj, deleteLogger] = getLogger(name, varargin)
  persistent loggers;
  logger_found = false;
  if ~isempty(loggers)
      loggerNames = {loggers.name};
      loggerIdx = strcmp(loggerNames, name);
      if any(loggerIdx)
          obj = loggers(loggerIdx);
          logger_found = true;
      end
  end
  if ~logger_found
    obj = mlog.logger(name, varargin{:});
    loggers = [loggers, obj];
  end
  
  deleteLogger = @() deleteLogInstance();
  
  function deleteLogInstance() 
      if ~logger_found
          error(['logger for file [ ' name ' ] not found'])
      end
      loggers = loggers(loggers ~= obj);
      delete(obj);
      clear('obj');
  end
end
