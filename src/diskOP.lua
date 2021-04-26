-- Disk operation functions
-- Module to Abstract and provide higher level disk operation functions by using the functionality provided by LuaFileSystem


local setmetatable = setmetatable
local type = type
local package = package
local io = io

local lfs = require("lfs")

local M = {}
package.loaded[...] = M
if setfenv and type(setfenv) == "function" then
	setfenv(1,M)	-- Lua 5.1
else
	_ENV = M		-- Lua 5.2
end


local sep = package.config:match("(.-)%s")

-- Converts all path separators to '/' and adds one in the end if not already there
function sanitizePath(path,file)
	path = path:gsub([[\]],sep):gsub([[/]],sep):gsub("^%s*",""):gsub("%s*$","")
	if not file and path:sub(-1,-1) ~= sep and path ~= "" then
		path = path..sep
	end
	return path
end	


-- Function to check whether the path exists
function verifyPath(path)
	if type(path) ~= "string" then
		return nil,"Path should be a string"
	end
	local i,d = lfs.dir(path)
	if not d:next() then
		d:close()
		return false,"Path does not exist"
	end
	d:close()
	return true
end

-- Function to return a iterator to traverse the directory and files from the given path
-- fd is a indicator to indicate what to iterate:
-- 1 = files only
-- 2 = directories only
-- everything else is files and directories both
-- onlyCurrent true means iterate only the current directory items
function recurseIter(path,fd,onlyCurrent)
	fd = fd or 3
	
	local obj = {}	-- iterator object
	local objMeta = {
		__index = {
			next = function(self)
				local item = obj.dObj[#obj.dObj].obj:next()
				if not item then
					if onlyCurrent then
						return nil
					end
					-- go up a level
					while #obj.dObj > 0 and not item do
						obj.dObj[#obj.dObj].obj:close()
						obj.dObj[#obj.dObj] = nil
						if #obj.dObj == 0 then
							break
						end
						item = obj.dObj[#obj.dObj].obj:next()
					end
					if #obj.dObj == 0 then
						-- nothing found
						return nil
					end
				end	-- if not item then ends here
				if item == "." or item == ".." then
					return obj:next()	-- skip these
				end
				-- We have an item now check whether it is file or directory
				if lfs.attributes(obj.dObj[#obj.dObj].path..item,"mode") == "directory" then
					local offset = 1
					if not onlyCurrent then
						-- Set the next iterator by going into the directory
						obj.dObj[#obj.dObj+1] = {path = obj.dObj[#obj.dObj].path..item.."/"}
						local i
						i,obj.dObj[#obj.dObj].obj = lfs.dir(obj.dObj[#obj.dObj].path)
						offset = 0
					end
					if fd == 1 then
						return obj:next()	-- directories not to be returned
					else
						return item,obj.dObj[#obj.dObj-1+offset].path,"directory"
					end
				else
					-- Not a directory object
					if fd == 2 then
						return obj:next()
					else
						return item,obj.dObj[#obj.dObj].path,"file"
					end
				end		-- if lfs.attributes(obj.dObj[#obj.dObj].path..item,"mode") == "directory" then ends
			end
		},
		__newindex = function(t,k,v)
		end,
		__gc = function(t)
			for i = #t.dObj,1,-1 do
				t.dObj[i].obj:close()
			end
		end
	}
	
	obj.dObj = {{path=path}}
	local i
	i,obj.dObj[1].obj=lfs.dir(path)
	setmetatable(obj,objMeta)
	return obj
end

-- fd is a indicator to indicate what to iterate:
-- 1 = files only
-- 2 = directories only
-- everything else is files and directories both
-- oc true means iterate only the current directory items
function listLocalHier(path,fd,oc)
	local ri,msg = recurseIter(path,fd,oc)
	if not ri then return
		nil,msg
	end
	local list = {}
	local item,pth,mode = ri:next()
	while item do
		--print(item,pth,mode)
		list[#list + 1] = {item,pth,mode}
		item,pth,mode = ri:next()
	end
	return list
end

function emptyDir(path)
	local list = listLocalHier(path)
	local count,stat,msg
	for i = #list,1,-1 do
		if list[i][3] == "directory" then
			stat,msg = lfs.rmdir(list[i][2]..[[/]]..list[i][1]) 
		else
			stat,msg = os.remove(list[i][2]..[[/]]..list[i][1])
		end
	end
end

-- Function to extract the file name from the path
function getFileName(path)
	local fName = path:match([[[%/%\%]]..sep..[[]([^%/%\%]]..sep.."]+)$") or path
	return fName
end

-- Function to make sure that the given path exists. 
-- If not then the full hierarchy is created where required to reach the given path
function createPath(path)
	if verifyPath(path) then
		return true
	end
	local p = ""
	local stat,msg
	for pth in path:gmatch("(.-)%"..sep) do
		p = p..pth..sep
		if not verifyPath(p) then
			-- Create this directory
			stat,msg = lfs.mkdir(p)
			if not stat then
				return nil,msg
			end
		end
	end
	return true
end

file_exists = function(file)
	local f,err = io.open(file,"r")
	if not f then
		return false,err
	end
	f:close()
	return true
end 

function copyFile(source,destPath,fileName,chunkSize,overwrite)
	chunkSize = chunkSize or 1000000	-- 1MB chunk size default
	if not verifyPath(destPath) then
		return nil,"Destination path not valid."
	end
	if not file_exists(source) then
		return nil,"Cannot open source file"
	end
	local ret = true
	if file_exists(sanitizePath(destPath)..fileName) then
		if not overwrite then
			return false,"File Exists"
		else
			ret = true,"Overwritten"
		end
	end
	local f = io.open(source,"rb")
	local fd = io.open(sanitizePath(destPath)..fileName,"w+b")
	local chunk = f:read(chunkSize)
	local stat,msg
	while chunk do
		stat,msg = fd:write(chunk)
		if not stat then
			fd:close()
			f:close()
			return nil,"Error writing file: "..msg
		end
		chunk = f:read(chunkSize)
	end
	fd:close()
	f:close()
	return true
end

