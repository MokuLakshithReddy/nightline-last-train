--!strict
-- Logger.luau
-- Structured logger with tag scoping and log levels

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR"

local LogLevels: { [LogLevel]: number } = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

local CURRENT_LOG_LEVEL = LogLevels.INFO

local Logger = {}
Logger.__index = Logger

type LoggerInstance = {
	Tag: string,
	Debug: (self: LoggerInstance, message: string, context: { [string]: any }?) -> (),
	Info: (self: LoggerInstance, message: string, context: { [string]: any }?) -> (),
	Warn: (self: LoggerInstance, message: string, context: { [string]: any }?) -> (),
	Error: (self: LoggerInstance, message: string, context: { [string]: any }?) -> (),
}

function Logger.new(tag: string): LoggerInstance
	local self = setmetatable({
		Tag = tag,
	}, Logger)
	return (self :: any) :: LoggerInstance
end

local function formatContext(context: { [string]: any }?): string
	if not context then return "" end
	local parts = {}
	for k, v in pairs(context) do
		table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
	end
	if #parts == 0 then return "" end
	return " | " .. table.concat(parts, " ")
end

local function logInternal(level: LogLevel, tag: string, message: string, context: { [string]: any }?)
	if LogLevels[level] < CURRENT_LOG_LEVEL then return end
	local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
	local formatted = string.format("[%s] [%s] [%s] %s%s", timestamp, level, tag, message, formatContext(context))

	if level == "ERROR" or level == "WARN" then
		warn(formatted)
	else
		print(formatted)
	end
end

function Logger:Debug(message: string, context: { [string]: any }?)
	logInternal("DEBUG", self.Tag, message, context)
end

function Logger:Info(message: string, context: { [string]: any }?)
	logInternal("INFO", self.Tag, message, context)
end

function Logger:Warn(message: string, context: { [string]: any }?)
	logInternal("WARN", self.Tag, message, context)
end

function Logger:Error(message: string, context: { [string]: any }?)
	logInternal("ERROR", self.Tag, message, context)
end

function Logger.SetLogLevel(level: LogLevel)
	if LogLevels[level] then
		CURRENT_LOG_LEVEL = LogLevels[level]
	end
end

return Logger
