do
	local vapeAssets = {
		['vapeburguer/assets/new/add.png'] = 'rbxassetid://121642387707174',
		['vapeburguer/assets/new/aim.png'] = 'rbxassetid://122207028123421',
		['vapeburguer/assets/new/allowedicon.png'] = 'rbxassetid://112336790299036',
		['vapeburguer/assets/new/allowediconmini.png'] = 'rbxassetid://90142384730147',
		['vapeburguer/assets/new/back.png'] = 'rbxassetid://80523803497740',
		['vapeburguer/assets/new/backmini.png'] = 'rbxassetid://85859225495272',
		['vapeburguer/assets/new/bind.png'] = 'rbxassetid://81399857677684',
		['vapeburguer/assets/new/bindbkg.png'] = 'rbxassetid://101996225428926',
		['vapeburguer/assets/new/blatant.png'] = 'rbxassetid://126929923309265',
		['vapeburguer/assets/new/blur.png'] = 'rbxassetid://79246816170155',
		['vapeburguer/assets/new/blurnoti.png'] = 'rbxassetid://124705876663719',
		['vapeburguer/assets/new/close.png'] = 'rbxassetid://121816018671466',
		['vapeburguer/assets/new/closemini.png'] = 'rbxassetid://108320409341289',
		['vapeburguer/assets/new/closetiny.png'] = 'rbxassetid://71393233149714',
		['vapeburguer/assets/new/colorpreview.png'] = 'rbxassetid://140438628568318',
		['vapeburguer/assets/new/combat.png'] = 'rbxassetid://94762732349053',
		['vapeburguer/assets/new/customtheme.png'] = 'rbxassetid://91756736022800',
		['vapeburguer/assets/new/discord.png'] = 'rbxassetid://99871463341003',
		['vapeburguer/assets/new/downexpand.png'] = 'rbxassetid://94197751291504',
		['vapeburguer/assets/new/downexpandslider.png'] = 'rbxassetid://90289944682645',
		['vapeburguer/assets/new/edit.png'] = 'rbxassetid://105801951237137',
		['vapeburguer/assets/new/editlarge.png'] = 'rbxassetid://119233876755282',
		['vapeburguer/assets/new/expandarrow.png'] = 'rbxassetid://86360332526471',
		['vapeburguer/assets/new/friends.png'] = 'rbxassetid://92957214042038',
		['vapeburguer/assets/new/inventory.png'] = 'rbxassetid://93264756888499',
		['vapeburguer/assets/new/legit_mode_icon.png'] = 'rbxassetid://102858626075156',
		['vapeburguer/assets/new/legit_switch.png'] = 'rbxassetid://127508881124779',
		['vapeburguer/assets/new/min.png'] = 'rbxassetid://82175054487146',
		['vapeburguer/assets/new/noti_alert.png'] = 'rbxassetid://82356478726846',
		['vapeburguer/assets/new/noti_info.png'] = 'rbxassetid://102614825645099',
		['vapeburguer/assets/new/noti_warning.png'] = 'rbxassetid://119631730212167',
		['vapeburguer/assets/new/notification.png'] = 'rbxassetid://90300780458781',
		['vapeburguer/assets/new/npcs.png'] = 'rbxassetid://104434365485227',
		['vapeburguer/assets/new/overlaydots.png'] = 'rbxassetid://78012624671930',
		['vapeburguer/assets/new/overlays.png'] = 'rbxassetid://136535637407545',
		['vapeburguer/assets/new/overlayslarge.png'] = 'rbxassetid://127574141208160',
		['vapeburguer/assets/new/pin.png'] = 'rbxassetid://92459145800579',
		['vapeburguer/assets/new/players.png'] = 'rbxassetid://105137446428129',
		['vapeburguer/assets/new/profiles.png'] = 'rbxassetid://126051451865127',
		['vapeburguer/assets/new/radar.png'] = 'rbxassetid://97983828696086',
		['vapeburguer/assets/new/rainbow_1.png'] = 'rbxassetid://101329996188554',
		['vapeburguer/assets/new/rainbow_2.png'] = 'rbxassetid://72739074644654',
		['vapeburguer/assets/new/rainbow_3.png'] = 'rbxassetid://100716555253397',
		['vapeburguer/assets/new/rainbow_4.png'] = 'rbxassetid://133424174227092',
		['vapeburguer/assets/new/range.png'] = 'rbxassetid://107794917650053',
		['vapeburguer/assets/new/rangeindicator.png'] = 'rbxassetid://107038094175283',
		['vapeburguer/assets/new/render.png'] = 'rbxassetid://125472576898654',
		['vapeburguer/assets/new/search.png'] = 'rbxassetid://115611852955611',
		['vapeburguer/assets/new/settingdots.png'] = 'rbxassetid://130896840048276',
		['vapeburguer/assets/new/settings.png'] = 'rbxassetid://73820177347303',
		['vapeburguer/assets/new/settingsmini.png'] = 'rbxassetid://115732118290997',
		['vapeburguer/assets/new/targetinfo.png'] = 'rbxassetid://121604266095276',
		['vapeburguer/assets/new/textgui.png'] = 'rbxassetid://99438663817412',
		['vapeburguer/assets/new/theme.png'] = 'rbxassetid://111525258317113',
		['vapeburguer/assets/new/utility.png'] = 'rbxassetid://108303206513893',
		['vapeburguer/assets/new/vape.png'] = 'rbxassetid://92153855792786',
		['vapeburguer/assets/new/vapelogo.png'] = 'rbxassetid://126205920310261',
		['vapeburguer/assets/new/vapelogomini.png'] = 'rbxassetid://109041903452149',
		['vapeburguer/assets/new/v4.png'] = 'rbxassetid://102549752760489',
		['vapeburguer/assets/new/v4mini.png'] = 'rbxassetid://115213099001611',
		['vapeburguer/assets/new/world.png'] = 'rbxassetid://118917453153459'
	}

	local function createDownloader(text)
		if vape.Loaded ~= true then
			local downloader = vape.Downloader
			if not downloader then
				downloader = Instance.new('TextLabel')
				downloader.BackgroundTransparency = 1
				downloader.FontFace = uipallet.Font
				downloader.Size = UDim2.new(1, 0, 0, 40)
				downloader.TextColor3 = Color3.new(1, 1, 1)
				downloader.TextSize = 20
				downloader.TextStrokeTransparency = 0
				downloader.Parent = vape.gui
				vape.Downloader = downloader
			end

			downloader.Text = 'Downloading '..text
		end
	end

	local function downloadFile(path, callback)
		if not isfile(path) then
			createDownloader(path)

			local success, data = pcall(function()
				return game:HttpGet('https://raw.githubusercontent.com/burgueralt07-crypto/VapeCompiled/'..readfile('vapeburguer/profiles/commit.txt')..'/'..select(1, path:gsub('vapeburguer/', '')), true)
			end)

			if not success or data == '404: Not Found' then
				error(data)
			end

			if path:find('.lua') then
				data = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..data
			end

			writefile(path, data)
		end

		return (callback or readfile)(path)
	end

	getvapeasset = not inputService.TouchEnabled and getcustomasset and function(path)
		return downloadFile(path, getcustomasset)
	end or function(path)
		return vapeAssets[path] or ''
	end
end