local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local inputService = cloneref(game:GetService('UserInputService'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local collectionService = cloneref(game:GetService('CollectionService'))
local runService = cloneref(game:GetService('RunService'))
local coreGui = cloneref(game:GetService('CoreGui'))

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local getvapeasset = vape.Libraries.getvapeasset

--[[
	Realistic Street Soccer - base (placeid 14315258385 / 4v4 normal)

	Os modulos ficam na pasta 'Utility' e sao concatenados abaixo deste arquivo pelo bundler,
	no mesmo escopo. Este arquivo cria as categorias 'realista' e 'farmRSS' (que aparecem
	apenas neste jogo) e os modulos esperam encontrar as seguintes variaveis por aqui:

		run, vape, lplr, entitylib, inputService, runService, getvapeasset
]]

-- Categorias proprias do Realistic Street Soccer (aparecem apenas neste jogo)
vape:CreateCategory({
	Name = 'realista',
	Icon = getvapeasset('vapeburguer/assets/new/world.png'),
	Size = UDim2.fromOffset(16, 14)
})
vape:CreateCategory({
	Name = 'farmRSS',
	Icon = getvapeasset('vapeburguer/assets/new/world.png'),
	Size = UDim2.fromOffset(16, 14)
})
