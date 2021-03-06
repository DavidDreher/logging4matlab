classdef logging < handle
  %LOGGING Simple logging framework.
  %
  % Author:
  %     Dominique Orban <dominique.orban@gmail.com>
  % Heavily modified version of 'log4m': http://goo.gl/qDUcvZ
  %

  properties (Constant)
    ALL      = int8(0);
    TRACE    = int8(1);
    DEBUG    = int8(2);
    INFO     = int8(3);
    WARNING  = int8(4);
    ERROR    = int8(5);
    CRITICAL = int8(6);
    OFF      = int8(7);

    colors_terminal = containers.Map(...
      {'normal', 'red', 'green', 'yellow', 'blue', 'brightred'}, ...
      {'%s', '\033[31m%s\033[0m', '\033[32m%s\033[0m', '\033[33m%s\033[0m', ...
       '\033[34m%s\033[0m', '\033[1;31m%s\033[0m'});

    level_colors = containers.Map(...
      {logging.logging.INFO, logging.logging.ERROR, logging.logging.TRACE, ...
       logging.logging.WARNING, logging.logging.DEBUG, logging.logging.CRITICAL}, ...
       {'normal', 'red', 'green', 'yellow', 'blue', 'brightred'});

    levels = containers.Map(...
      {logging.logging.ALL,      logging.logging.TRACE,   logging.logging.DEBUG, ...
       logging.logging.INFO,     logging.logging.WARNING, logging.logging.ERROR, ...
       logging.logging.CRITICAL, logging.logging.OFF}, ...
      {'ALL', 'TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL', 'OFF'});
    
    log_styles = containers.Map(...
        {'caller', 'timestamp', 'level', 'message'}, ...
        {'%-s', '%-23s', '%-8s', '%s'});

  end
  
  properties (SetAccess=immutable)
    level_numbers;
    level_range;
  end

  properties (SetAccess=protected)
    name;
    fullpath = 'logging.log';  % Default log file
%     logfmt = '%-s %-23s %-8s %s\n';
    logfid = -1;
    logcolors = logging.logging.colors_terminal;
    using_terminal;
  end

  properties (Hidden,SetAccess=protected)
    datefmt_ = 'yyyy-mm-dd HH:MM:SS,FFF';
    logLevel_ = logging.logging.INFO;
    commandWindowLevel_ = logging.logging.INFO;
    logOrder_ = {'caller', 'timestamp', 'level', 'message'};
  end
  
  properties (Dependent)
    datefmt;
    logLevel;
    commandWindowLevel;
    logOrder;
  end

  methods(Static)
    function [name, line] = getCallerInfo(self)
      
      if nargin > 0 && self.ignoreLogging()
          name = [];
          line = [];
          return
      end
      [ST, ~] = dbstack();
      offset = min(size(ST, 1), 3);
      name = ST(offset).name;
      line = ST(offset).line;
    end
  end

  methods

    function setFilename(self, logPath)
      [self.logfid, message] = fopen(logPath, 'a');

      if self.logfid < 0
        warning(['Problem with supplied logfile path: ' message]);
        self.logLevel_ = logging.logging.OFF;
      end

      self.fullpath = logPath;
    end

    function setCommandWindowLevel(self, level)
      self.commandWindowLevel = level;
    end

    function setLogLevel(self, level)
      self.logLevel = level;
    end
    
    function tf = ignoreLogging(self)
        tf = self.commandWindowLevel_ == self.OFF && self.logLevel_ == self.OFF;
    end

    function trace(self, message, caller_name)
      if nargin < 3 || isempty(caller_name)  
        [caller_name, ~] = self.getCallerInfo(self);
      end
      self.writeLog(self.TRACE, caller_name, message);
    end

    function debug(self, message, caller_name)
      if nargin < 3 || isempty(caller_name)  
        [caller_name, ~] = self.getCallerInfo(self);
      end
      self.writeLog(self.DEBUG, caller_name, message);
    end

    function info(self, message, caller_name)
      if nargin < 3 || isempty(caller_name)  
        [caller_name, ~] = self.getCallerInfo(self);
      end
      self.writeLog(self.INFO, caller_name, message);
    end

    function warn(self, message, caller_name)
      if nargin < 3 || isempty(caller_name)  
        [caller_name, ~] = self.getCallerInfo(self);
      end
      self.writeLog(self.WARNING, caller_name, message);
    end

    function error(self, message, caller_name)
      if nargin < 3 || isempty(caller_name)  
        [caller_name, ~] = self.getCallerInfo(self);
      end
      self.writeLog(self.ERROR, caller_name, message);
    end

    function critical(self, message, caller_name)
      if nargin < 3 || isempty(caller_name)  
        [caller_name, ~] = self.getCallerInfo(self);
      end
      self.writeLog(self.CRITICAL, caller_name, message);
    end
    
    function exception(self, ME)
        validateattributes(ME, {'MException'}, {'scalar'}, [class(self), ...
            '.exception'], 'ME', 2);
        caller_name = ME.stack(1).name;
        self.error(ME.message, caller_name);
        self.debug(ME.identifier, caller_name);
        self.trace(getReport(ME), caller_name);
    end

    function self = logging(name, varargin)
      levelkeys = self.levels.keys;
      self.level_numbers = containers.Map(...
          self.levels.values, levelkeys);
      levelkeys = cell2mat(self.levels.keys);
      self.level_range = [min(levelkeys), max(levelkeys)];
      
      p = inputParser();
      p.addRequired('name', @ischar);
      p.addParameter('path', '', @ischar);
      p.addParameter('logLevel', self.logLevel);
      p.addParameter('commandWindowLevel', self.commandWindowLevel);
      p.addParameter('datefmt', self.datefmt_);
      p.addParameter('logOrder', self.logOrder_);
      p.parse(name, varargin{:});
      r = p.Results; 
      
      self.name = r.name;
      self.commandWindowLevel = r.commandWindowLevel;
      self.datefmt = r.datefmt;
      if ~isempty(r.path)
        self.setFilename(r.path);  % Opens the log file.
        self.logLevel = r.logLevel;
      else
        self.logLevel_ = logging.logging.OFF;
      end
      % Use terminal logging if swing is disabled in matlab environment.
      swingError = javachk('swing');
      self.using_terminal = (~ isempty(swingError) && strcmp(swingError.identifier, 'MATLAB:javachk:thisFeatureNotAvailable')) || ~desktop('-inuse');
    end

    function delete(self)
      if self.logfid > -1
        fclose(self.logfid);
      end
    end

    function writeLog(self, level, caller, message)
      level = self.getLevelNumber(level);
      if self.commandWindowLevel_ <= level || self.logLevel_ <= level
        timestamp = datestr(now, self.datefmt_);
        levelStr = logging.logging.levels(level);
        
        supportedInputs = struct('caller',      caller, ...
                                 'timestamp',   timestamp, ...
                                 'level',       levelStr, ...
                                 'message',     self.getMessage(message));
        
        order = self.logOrder;
        inputs = cell(1, numel(order));
        for iL = 1:numel(order)
            if iL == 1
                formatSpec = self.log_styles(order{iL});
            else
                formatSpec = [formatSpec, ' ', self.log_styles(order{iL})]; %#ok<AGROW>
            end
            inputs{iL} = supportedInputs.(order{iL});
        end
        formatSpec = [formatSpec, '\n'];
%         logline = sprintf(self.logfmt, caller, timestamp, levelStr, self.getMessage(message));
        logline = sprintf(formatSpec, inputs{:});
      end

      if self.commandWindowLevel_ <= level
        if self.using_terminal
          level_color = self.level_colors(level);
        else
          level_color = self.level_colors(logging.logging.INFO);
        end
        fprintf(self.logcolors(level_color), logline);
      end

      if self.logLevel_ <= level && self.logfid > -1
        fprintf(self.logfid, logline);
      end
    end        
    
    function set.datefmt(self, fmt)
      try
        datestr(now(), fmt);
      catch
        error('Invalid date format');
      end
      self.datefmt_ = fmt;
    end

    function fmt = get.datefmt(self)
      fmt = self.datefmt_;
    end
    
    function set.logLevel(self, level)
      level = self.getLevelNumber(level);
      if level > logging.logging.OFF || level < logging.logging.ALL
        error('invalid logging level');
      end
      self.logLevel_ = level;
    end
    
    function level = get.logLevel(self)
      level = self.logLevel_;
    end
    
    function set.commandWindowLevel(self, level)
      self.commandWindowLevel_ = self.getLevelNumber(level);
    end
    
    function level = get.commandWindowLevel(self)
      level = self.commandWindowLevel_;
    end
    
    function set.logOrder(self, order)
      supportedOrders = self.log_styles.keys;
      validateattributes(order, {'cell'}, {'nonempty', 'vector'}, ...
          [class(self), '.set.logOrder'], 'order', 2)
      cellfun(@(x) validateattributes(x, {'char'}, {'scalartext', 'nonempty'},  ...
          [class(self), '.set.logOrder'], 'order', 2), order);
      order = lower(order);
      assert( all(ismember(order, supportedOrders)), [mfilename, ':invalidOrderKey'], ...
          ['Invalid order key encountered, order must be a cell array with entries' , ...
          ' corresponding to: ', strjoin(supportedOrders, ', ')]);
      self.logOrder_ = order;
    end
    
    function order = get.logOrder(self)
      order = self.logOrder_;  
    end
        
        
  end
  
  methods (Hidden)
    function level = getLevelNumber(self, level)
    % LEVEL = GETLEVELNUMBER(LEVEL)
    %
    % Converts charecter-based level names to level numbers
    % used internally by logging.
    %
    % If given a number, it makes sure the number is valid
    % then returns it unchanged.
    %
    % This allows users to specify levels by name or number.
      if isinteger(level) && self.level_range(1) <= level && level <= self.level_range(2)
        return
      else
        level = self.level_numbers(level);
      end
    end
      
    function message = getMessage(~, message)
    
      if isa(message, 'function_handle')
        message = message();
      end
      [rows, ~] = size(message);
      if rows > 1
        message = sprintf('\n %s', evalc('disp(message)'));
      end
    end
  
 end
end
