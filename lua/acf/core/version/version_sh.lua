local ACF   = ACF
local Repos = ACF.Repositories
local Realm = SERVER and "Server" or "Client"


do -- Local repository version checking
	local file = file
	local os   = os

	local function LocalToUTC(Time)
		return os.time(os.date("!*t", Time))
	end

	-- Makes sure the owner of the repo is correct, deals with forks
	local function UpdateOwner(Path, Data)
		if not file.Exists(Path .. "/.git/FETCH_HEAD", "GAME") then return end

		local Fetch = file.Read(Path .. "/.git/FETCH_HEAD", "GAME")
		local Start, End = Fetch:find("github.com[/]?[:]?[%w_-]+/")

		if not Start then return end -- File is empty

		Data.Owner = Fetch:sub(Start + 11, End - 1)
	end

	local function GetHeadsPath(Path, Data)
		print("GetHeadsPath:", Path)
		-- "ref: refs/heads/feature/example"
		-- "feature/example"
		local _, _, Head = file.Read(Path .. "/.git/HEAD", "GAME"):find("heads/(.+)$")
		print("Head:", Head)

		-- { "feature", "example" }
		local HeadPrefix = string.Split(Head, "/")
		print("HeadPrefix:")
		PrintTable(HeadPrefix)

		-- "example"
		Head = HeadPrefix[#HeadPrefix]
		print("HeadPrefix[#HeadPrefix]:", Head)

		-- "feature"
		HeadPrefix = table.concat(HeadPrefix, "/", 1, #HeadPrefix - 1)
		print("HeadPrefix", HeadPrefix)

		-- "example"
		Data.Head = Head:Trim()
		print("Data.Head", Data.Head)

		-- "addons/acf-3/.git/refs/heads/feature"
		local Heads = Path .. "/.git/refs/heads/" .. HeadPrefix
		print("Heads", Heads)
		return Heads
	end

	local function CheckPackedRefs(Path, Heads, Data)
		-- "addons/acf-3/.git/refs/heads/feature"
		-- {"addons/acf-3/", "refs/heads/feature"}
		-- "refs/heads/feature"
		print("CheckPackedRefs:", Path, Heads)
		Heads = string.Split(Heads, ".git/")[2]
		print("Heads:", Heads, Data.Head)
		Heads = Heads .. Data.Head
		print("Heads:", Heads)

		-- "addons/acf-3/.git/packed-refs"
		local PackedRefPath = Path .. "/.git/packed-refs"
		print("PackedRefPath:", PackedRefPath)
		if not file.Exists(PackedRefPath, "GAME") then return end

		-- [[# pack-refs with: peeled fully-peeled sorted
		--   ebc5f59a706efe0c04e509b8f69b4394f3620b2f refs/heads/master
		--   02bf26bf4bf6501a0e0aaf0c4e4c68a9d728f294 refs/heads/feature/example
		--   6aa5a99103c1ade703599d374932af27723bf71e refs/remotes/origin/dev]]
		local PackedRef = file.Read(PackedRefPath, "GAME")
		print("PackedRef:")
		print(PackedRef)

		-- "02bf26bf4bf6501a0e0aaf0c4e4c68a9d728f294"
		local _, _, Code = PackedRef:find("^(.+) " .. Heads .. "$")
		print("Pattern: ^(.+) ", Heads, "$")
		print("Code:", Code)

		-- "02bf26b"
		Code = Code:sub(1, 7)
		print("Code:", Code)

		local Date = file.Time(PackedRefPath, "GAME")
		print("Date:", Date)

		return Code, Date
	end

	local function GetGitData(Path, Data)
		print("GetGitData:", Path)
		-- "addons/acf-3/.git/refs/heads/feature/"
		local Heads = GetHeadsPath(Path, Data)
		print("Heads:", Heads)
		local Files = file.Find(Heads .. "*", "GAME")
		print("Files:", #Files)

		-- Sometimes the refs/heads/ dir is just empty
		-- As a fallback, we can also try the packed-refs file
		if #Files == 0 then return CheckPackedRefs(Path, Heads, Data) end

		local Code, Date

		for _, Name in ipairs(Files) do
			-- Name = "example"
			-- Data.Head = "example"
			print("_, Name", Name, Data.Head)
			if Name == Data.Head then
				-- "02bf26bf4bf6501a0e0aaf0c4e4c68a9d728f294"
				local SHA = file.Read(Path, "GAME"):Trim()

				-- "example-02bf26b"
				Code = Name .. "-" .. SHA:sub(1, 7)
				Date = file.Time(Path, "GAME")
				break
			end
		end

		return Code, Date
	end

	-------------------------------------------------------------------

	function ACF.CheckLocalVersion(Name)
		if not isstring(Name) then return end

		local Data = ACF.GetLocalRepo(Name)

		if not Data then return end

		local Path = Data.Path

		if not Path then
			Data.Code    = "Not Installed"
			Data.Date    = 0
			Data.NoFiles = true
		elseif file.Exists(Path .. "/.git/HEAD", "GAME") then
			local Code, Date = GetGitData(Path, Data)

			-- There are some situations where it's
			-- just not possible to get the current git branch
			if not Code then
				Data.Code    = "Git-Unknown"
				Data.Date    = 0
				return
			end

			UpdateOwner(Path, Data)

			Data.Code = "Git-" .. Code
			Data.Date = LocalToUTC(Date)
		elseif file.Exists(Path .. "/LICENSE", "GAME") then
			local Date = file.Time(Path .. "/LICENSE", "GAME")

			Data.Code = "ZIP-Unknown"
			Data.Date = LocalToUTC(Date)
		end

		if not Data.Head then
			Data.Head = "master"
		end
	end
end

do -- Local repository status checking
	local function IsUpdated(Data, Branch)
		if not isnumber(Data.Date) then return false end

		return Data.Date >= Branch.Date
	end

	function ACF.CheckLocalStatus(Name)
		if not isstring(Name) then return end

		local Repo = ACF.GetRepository(Name)

		if not Repo then return end

		local Data     = Repo[Realm]
		local Branches = Repo.Branches
		local Branch   = Branches[Data.Head] or Branches.master

		if not (Branch and Branch.Date) or Data.NoFiles then
			Data.Status = "Unable to check"
		elseif Data.Code == Branch.Code or IsUpdated(Data, Branch) then
			Data.Status = "Up to date"
		else
			Data.Status = "Out of date"
		end
	end
end

do -- Repository functions
	function ACF.AddRepository(Owner, Name, File)
		if not isstring(Owner) then return end
		if not isstring(Name) then return end
		if not isstring(File) then return end
		if Repos[Name] then return end

		local DebugInfo = debug.getinfo( 2, "S" )
		local AddonFolder = string.Split( DebugInfo.short_src, "/lua/" )[1]

		Repos[Name] = {
			[Realm] = {
				Path = AddonFolder,
				Owner = Owner,
				Name = Name,
			},
			Branches = {},
		}

		if CLIENT then
			Repos[Name].Server = {}
		end

		ACF.CheckLocalVersion(Name)
	end

	function ACF.GetRepository(Name)
		if not isstring(Name) then return end

		return Repos[Name]
	end

	function ACF.GetLocalRepo(Name)
		if not isstring(Name) then return end

		local Data = Repos[Name]

		return Data and Data[Realm]
	end

	ACF.AddRepository("Stooberton", "ACF-3", "lua/autorun/acf_loader.lua")
end

do -- Branch functions
	function ACF.GetBranches(Name)
		if not isstring(Name) then return end

		local Data = Repos[Name]

		return Data and Data.Branches
	end

	function ACF.GetBranch(Name, Branch)
		if not isstring(Name) then return end
		if not isstring(Branch) then return end

		local Data = Repos[Name]

		if not Data then return end

		return Data.Branches[Branch]
	end
end
