local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local function downloadFile(path, func)
	if not isfile(path) then
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/burgueralt07-crypto/VapeCompiled/'..readfile('vapeburguer/profiles/commit.txt')..'/'..select(1, path:gsub('vapeburguer/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

local function wipeFolder(path)
	if not isfolder(path) then return end
	for _, file in listfiles(path) do
		if file:find('loader') then continue end
		if isfile(file) and select(1, readfile(file):find('--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.')) == 1 then
			delfile(file)
		end
	end
end

for _, folder in {'vapeburguer', 'vapeburguer/games', 'vapeburguer/profiles', 'vapeburguer/assets', 'vapeburguer/libraries', 'vapeburguer/guis'} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

if not shared.VapeDeveloper then
	local _, subbed = pcall(function()
		return game:HttpGet('https://github.com/burgueralt07-crypto/VapeCompiled')
	end)

	local assetVer = '1'
	local commit = subbed:find('currentOid')
	commit = commit and subbed:sub(commit + 13, commit + 52) or nil
	commit = commit and #commit == 40 and commit or 'main'

	if commit == 'main' or (isfile('vapeburguer/profiles/commit.txt') and readfile('vapeburguer/profiles/commit.txt') or '') ~= commit then
		wipeFolder('vapeburguer')
		wipeFolder('vapeburguer/games')
		wipeFolder('vapeburguer/guis')
		wipeFolder('vapeburguer/libraries')
	end

	if (isfile('vapeburguer/profiles/asset.txt') and readfile('vapeburguer/profiles/asset.txt') or '') ~= assetVer then
		wipeFolder('vapeburguer/assets')
	end

	writefile('vapeburguer/profiles/asset.txt', assetVer)
	writefile('vapeburguer/profiles/commit.txt', commit)
end

return loadstring(downloadFile('vapeburguer/main.lua'), 'main')()