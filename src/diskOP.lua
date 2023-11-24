-- Disk operation functions
-- Module to Abstract and provide higher level disk operation functions by using the functionality provided by LuaFileSystem


local setmetatable = setmetatable
local type = type
local package = package
local io = io
local os = os
local table = table

--local print = print

local lfs = require("lfs")

local M = {}
package.loaded[...] = M
if setfenv and type(setfenv) == "function" then
	setfenv(1,M)	-- Lua 5.1
else
	_ENV = M		-- Lua 5.2
end

_VERSION = "1.23.11.24"


local sep = package.config:match("(.-)%s")

-- Converts all path separators to '/' and adds one in the end if not already there if file is false.
-- if file is true then treats the path as a path for a file
function sanitizePath(path,file)
	path = path:gsub([[\]],sep):gsub([[/]],sep):gsub("^%s*",""):gsub("%s*$","")
	if not file and path:sub(-1,-1) ~= sep and path ~= "" then
		path = path..sep
	end
	return path
end	

-- Conert path2 to relative path
-- Example:
-- path1 = E:\Records and Finances\Finances\Spendings
-- path2 = E:\Records and Finances\Invoices
-- reurns ..\..\Invoices
function convertToRelativePath(path1, path2)
    
    -- Split the paths into individual components
    local components1 = {}
    for component in path1:gmatch("[^" .. sep .. "]+") do
        table.insert(components1, component)
    end
    
    local components2 = {}
    for component in path2:gmatch("[^" .. sep .. "]+") do
        table.insert(components2, component)
    end
    
    -- Find the common root directory
    local i = 1
    while components1[i] == components2[i] do
        i = i + 1
    end
    
    -- Build the relative path
    local relativePath = ""
    for j = i, #components1 do
        relativePath = relativePath .. ".." .. sep
    end
    
    for j = i, #components2 do
        relativePath = relativePath .. components2[j] .. sep
    end
    
    -- Remove the trailing path separator if present
    relativePath = relativePath:gsub("[" .. sep .. "]$", "")
    
    return sanitizePath(relativePath)
end

function convertToAbsolutePath(basePath, relativePath)
    
    -- Split the base path into individual components
    local components = {}
    for component in basePath:gmatch("[^" .. sep .. "]+") do
        table.insert(components, component)
    end
    
    -- Split the relative path into individual components
    local relativeComponents = {}
    for component in relativePath:gmatch("[^" .. sep .. "]+") do
        table.insert(relativeComponents, component)
    end
    
    -- Build the absolute path
    for i = 1,#relativeComponents do
		local component = relativeComponents[i]
        if component == ".." then
            table.remove(components, #components)
        else
            table.insert(components, component)
        end
    end
    
    -- Join the components to form the absolute path
    local absolutePath = table.concat(components, sep)
    
    return sanitizePath(absolutePath)
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

function fileCreatable(file)
	if fileExists(file) then
		return nil,"File already exists"
	end
	local f,msg = io.open(file,"w+")
	if not f then
		return nil,msg
	end
	f:close()
	os.remove(file)
	return true
end

-- Function to return a iterator to traverse the directory and files from the given path
-- fd is a indicator to indicate what to iterate:
-- 1 = files only
-- 2 = directories only
-- everything else is files and directories both
-- onlyCurrent true means iterate only the current directory items
function recurseIter(path,fd,onlyCurrent)
	local stat,msg = verifyPath(path)
	if not stat then return nil,msg end
	path = sanitizePath(path)
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
-- function if given should be a function that is called to filter which items to include in the list
function listLocalHier(path,fd,oc,func)
	func = (type(func) == "function" and func) or function(item,pth,mode) return true end
	local ri,msg = recurseIter(path,fd,oc)
	if not ri then return
		nil,msg
	end
	local list = {}
	local item,pth,mode = ri:next()
	while item do
		--print(item,pth,mode)
		if func(item,pth,mode) then
			list[#list + 1] = {item,pth,mode}
		end
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

-- To get the extension of the file
function getFileExt(path)
	local fName = getFileName(path)
	return fName:match("%.([^%.]+)$") or ""
end

-- Function to make sure that the given path exists. 
-- If not then the full hierarchy is created where required to reach the given path
function createPath(path)
	if verifyPath(path) then
		return true
	end
	path = sanitizePath(path)
	local p = ""
	local stat,msg
	for pth in path:gmatch("(.-)%"..sep) do
		p = p..pth..sep
		--print(p)
		if not verifyPath(p) then
			-- Create this directory
			--print("mkdir "..p)
			stat,msg = lfs.mkdir(p)
			if not stat then
				return nil,msg
			end
		end
	end
	return true
end

fileExists = function(file)
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
	if not fileExists(source) then
		return nil,"Cannot open source file"
	end
	local ret = true
	if fileExists(sanitizePath(destPath)..fileName) then
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

