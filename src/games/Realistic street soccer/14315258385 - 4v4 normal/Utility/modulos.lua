run(function()
    local AutoTackle
    local DetectRange
    local TackleSpeed
    local AutoWalk
    local WalkTargetDistance
    local WalkSearchRange
    local StrafeInterval
    local WalkReactionDelay
    local FramePerfect
    local MaxBallHeight
    local SmartMode

    local ActionRemote = game:GetService('ReplicatedStorage').Remotes:FindFirstChild('Action')
    local Stats = game:GetService('Stats')
    local UserInputService = game:GetService('UserInputService')
    local PlayerModule = require(lplr.PlayerScripts:WaitForChild('PlayerModule'))
    local Controls = PlayerModule:GetControls()

    local isAttacking = false
    local cachedBall = nil
    local lastEnemyOwner = nil
    local watching = false

    local strafeDirection = 1
    local lastStrafeSwitch = 0

    local currentMoveVector = Vector3.zero
    local pendingMoveVector = Vector3.zero
    local pendingChangeTime = 0
    local hasPendingChange = false
    local controlsDisabled = false

    local charCache = {
        tackleDebounce = nil,
        tackled = nil,
        debounce = nil,
        tackling = nil,
        header = nil,
    }

    local function rebuildCache()
        local char = lplr.Character
        if not char then return end

        local bools = char:FindFirstChild("Bools")
        if not bools then return end

        charCache.tackleDebounce = bools:FindFirstChild("TackleDebounce")
        charCache.tackled = bools:FindFirstChild("Tackled")
        charCache.debounce = bools:FindFirstChild("Debounce")
        charCache.tackling = bools:FindFirstChild("Tackling")
        charCache.header = bools:FindFirstChild("Header")
    end

    local function canTackle()
        if not entitylib.isAlive then return false end
        if charCache.tackleDebounce and charCache.tackleDebounce.Value then return false end
        if charCache.tackled and charCache.tackled.Value then return false end
        if charCache.debounce and charCache.debounce.Value then return false end
        if charCache.tackling and charCache.tackling.Value then return false end
        if charCache.header and charCache.header.Value then return false end

        local wsBools = workspace:FindFirstChild("Bools")
        if wsBools then
            local penalty = wsBools:FindFirstChild("Penalty")
            local kickoff = wsBools:FindFirstChild("Kickoff")
            if penalty and penalty.Value then return false end
            if kickoff and kickoff.Value then return false end
        end

        return true
    end

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, v in workspace:GetChildren() do
            if v.Name:lower() == 'ball' and v:IsA('BasePart') then
                cachedBall = v
                return v
            end
        end

        cachedBall = nil
        return nil
    end

    local function iHaveBall()
        local ball = findBall()
        if not ball then return false end
        local weld = ball:FindFirstChild("playerWeld")
        if not weld or not weld:IsA("Weld") then return false end
        local rootPart = weld.Part0
        if not rootPart then return false end
        return rootPart.Parent == lplr.Character
    end

    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end
        local weld = ball:FindFirstChild("playerWeld")
        if not weld or not weld:IsA("Weld") then return nil end
        local rootPart = weld.Part0
        if not rootPart then return nil end
        local char = rootPart.Parent
        if not char then return nil end
        return game.Players:GetPlayerFromCharacter(char)
    end

    local function getMyGoal()
        local myTeamColor = lplr.TeamColor

        if myTeamColor == BrickColor.new(141) then
            return workspace:FindFirstChild("HomeGoalDetector")
        elseif myTeamColor == BrickColor.new(23) then
            return workspace:FindFirstChild("AwayGoalDetector")
        end

        return nil
    end

    local function getMyFootY()
        local char = lplr.Character
        if not char then return 0 end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")

        if hrp and hum then
            return hrp.Position.Y - hum.HipHeight - (hrp.Size.Y / 2)
        end

        return 0
    end

    local function isBallTooHigh(ball)
        if not ball then return true end

        local footY = getMyFootY()
        local ballY = ball.Position.Y
        local heightFromFoot = ballY - footY

        return heightFromFoot > MaxBallHeight.Value
    end

    local function doTackle()
        if not entitylib.isAlive or not ActionRemote then return end

        local root = entitylib.character.RootPart
        if not root then return end

        ActionRemote:FireServer('TackIe')

        local bv = Instance.new("BodyVelocity")
        bv.Parent = root
        bv.velocity = root.CFrame.lookVector * TackleSpeed.Value
        bv.maxForce = Vector3.new(50000000, 0, 50000000)
        game:GetService("Debris"):AddItem(bv, 0.65)

        local gyro = Instance.new("BodyGyro", root)
        gyro.Name = "TackleGyro"
        gyro.P = 950000
        gyro.MaxTorque = Vector3.new(0, 100000, 0)
        gyro.CFrame = root.CFrame
        game:GetService("Debris"):AddItem(gyro, 0.65)
    end

    local function aimAtBall()
        if not entitylib.isAlive then return end

        local myRoot = entitylib.character.RootPart
        local ball = findBall()
        if not myRoot or not ball then return end

        local dist = (ball.Position - myRoot.Position).Magnitude
        local timeToReach = dist / TackleSpeed.Value
        local ballVel = ball.AssemblyLinearVelocity or Vector3.zero

        local predictedPos = ball.Position + (ballVel * timeToReach)
        local lookAtPos = Vector3.new(predictedPos.X, myRoot.Position.Y, predictedPos.Z)
        myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookAtPos)
    end

    local function framePerfectTackle()
        if isAttacking then return end
        if not canTackle() then return end
        if iHaveBall() then return end

        local ball = findBall()
        if not ball then return end

        local myRoot = entitylib.character.RootPart
        if not myRoot then return end

        local dist = (ball.Position - myRoot.Position).Magnitude
        if dist > DetectRange.Value then return end

        isAttacking = true

        task.spawn(function()
            local wsBools = workspace:FindFirstChild("Bools")
            local cantGrab = wsBools and wsBools:FindFirstChild("cantGrab")

            if not cantGrab then
                isAttacking = false
                return
            end

            local waitStart = tick()
            local maxWait = 1.0

            while cantGrab.Value == true do
                if not AutoTackle.Enabled then
                    isAttacking = false
                    return
                end

                if tick() - waitStart > maxWait then
                    isAttacking = false
                    return
                end

                task.wait()
            end

            local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
            local prediction = ping / 2
            local fireDelay = math.max(0, 0 - prediction)

            if fireDelay > 0 then
                task.wait(fireDelay)
            end

            if not AutoTackle.Enabled then
                isAttacking = false
                return
            end

            if not canTackle() then
                isAttacking = false
                return
            end

            if iHaveBall() then
                isAttacking = false
                return
            end

            local ballNow = findBall()
            if not ballNow then
                isAttacking = false
                return
            end

            if isBallTooHigh(ballNow) then
                isAttacking = false
                return
            end

            local myRootNow = entitylib.character.RootPart
            if not myRootNow then
                isAttacking = false
                return
            end

            local distNow = (ballNow.Position - myRootNow.Position).Magnitude
            if distNow > DetectRange.Value then
                isAttacking = false
                return
            end

            aimAtBall()
            doTackle()
            task.wait(0.1)
            while charCache.tackling and charCache.tackling.Value do
                task.wait()
            end
            isAttacking = false
        end)
    end

    local function normalTackle()
        if isAttacking then return end
        if not canTackle() then return end
        if iHaveBall() then return end

        local ball = findBall()
        if not ball then return end

        local myRoot = entitylib.character.RootPart
        if not myRoot then return end

        local dist = (ball.Position - myRoot.Position).Magnitude
        if dist > DetectRange.Value then return end

        if isBallTooHigh(ball) then return end

        isAttacking = true

        task.spawn(function()
            if not AutoTackle.Enabled then
                isAttacking = false
                return
            end

            if not canTackle() then
                isAttacking = false
                return
            end

            if iHaveBall() then
                isAttacking = false
                return
            end

            local ballNow = findBall()
            if not ballNow then
                isAttacking = false
                return
            end

            if isBallTooHigh(ballNow) then
                isAttacking = false
                return
            end

            local ownerNow = getBallOwner()
            if ownerNow then
                isAttacking = false
                return
            end

            aimAtBall()
            doTackle()
            task.wait(0.1)
            while charCache.tackling and charCache.tackling.Value do
                task.wait()
            end
            isAttacking = false
        end)
    end

    local function tryTackle()
        if FramePerfect.Enabled then
            framePerfectTackle()
        else
            normalTackle()
        end
    end

    local function mainLoop()
        if not entitylib.isAlive then return end
        if isAttacking then return end

        local ball = findBall()
        if not ball then
            lastEnemyOwner = nil
            watching = false
            return
        end

        local currentOwner = getBallOwner()

        if currentOwner and currentOwner ~= lplr and currentOwner.Team ~= lplr.Team then
            lastEnemyOwner = currentOwner
            watching = true
            return
        end

        if watching and lastEnemyOwner and not currentOwner then
            watching = false

            local speed = ball.AssemblyLinearVelocity.Magnitude

            if speed < 35 then
                local myRoot = entitylib.character.RootPart
                if myRoot then
                    local dist = (ball.Position - myRoot.Position).Magnitude
                    if dist <= DetectRange.Value then
                        tryTackle()
                    end
                end
            end

            lastEnemyOwner = nil
            return
        end

        if currentOwner and (currentOwner == lplr or currentOwner.Team == lplr.Team) then
            lastEnemyOwner = nil
            watching = false
        end
    end

    local function vectorsAngleClose(a, b, thresholdDeg)
        if a.Magnitude < 0.01 and b.Magnitude < 0.01 then return true end
        if a.Magnitude < 0.01 or b.Magnitude < 0.01 then return false end

        local dot = a.Unit:Dot(b.Unit)
        dot = math.clamp(dot, -1, 1)
        local angleDeg = math.deg(math.acos(dot))
        return angleDeg <= thresholdDeg
    end

    local function requestMovement(newVector)
        local delayMs = WalkReactionDelay.Value
        local delaySec = delayMs / 1000

        if delaySec <= 0 then
            currentMoveVector = newVector
            hasPendingChange = false
            return
        end

        if vectorsAngleClose(newVector, currentMoveVector, 20) then
            currentMoveVector = newVector
            hasPendingChange = false
            return
        end

        if hasPendingChange and vectorsAngleClose(newVector, pendingMoveVector, 20) then
            pendingMoveVector = newVector

            if (tick() - pendingChangeTime) >= delaySec then
                currentMoveVector = pendingMoveVector
                hasPendingChange = false
            end
            return
        end

        pendingMoveVector = newVector
        pendingChangeTime = tick()
        hasPendingChange = true
    end

    local function forceMovement(newVector)
        currentMoveVector = newVector
        pendingMoveVector = newVector
        hasPendingChange = false
    end

    local function getDirectionToPoint(targetPos)
        local myRoot = entitylib.character.RootPart
        if not myRoot then return Vector3.zero end

        local dir = Vector3.new(
            targetPos.X - myRoot.Position.X,
            0,
            targetPos.Z - myRoot.Position.Z
        )

        if dir.Magnitude < 0.1 then return Vector3.zero end
        return dir.Unit
    end

    local function getStrafeDirection(ballPos)
        local myRoot = entitylib.character.RootPart
        if not myRoot then return Vector3.zero end

        local toBall = Vector3.new(
            ballPos.X - myRoot.Position.X,
            0,
            ballPos.Z - myRoot.Position.Z
        )

        if toBall.Magnitude < 0.1 then return Vector3.zero end
        toBall = toBall.Unit

        if strafeDirection == 1 then
            return Vector3.new(-toBall.Z, 0, toBall.X)
        else
            return Vector3.new(toBall.Z, 0, -toBall.X)
        end
    end

    local function getSmartTargetPos(ballPos)
        local myGoal = getMyGoal()
        if not myGoal then return ballPos end

        local goalPos = Vector3.new(myGoal.Position.X, 0, myGoal.Position.Z)
        local ballFlat = Vector3.new(ballPos.X, 0, ballPos.Z)

        local goalToBall = ballFlat - goalPos
        local distGoalToBall = goalToBall.Magnitude

        if distGoalToBall < 0.1 then return ballPos end

        local directionGoalToBall = goalToBall.Unit
        local targetOffsetFromBall = WalkTargetDistance.Value

        local idealDistFromGoal = distGoalToBall - targetOffsetFromBall

        if idealDistFromGoal < 0 then
            idealDistFromGoal = 0
        end

        local targetPos = goalPos + directionGoalToBall * idealDistFromGoal

        return Vector3.new(targetPos.X, ballPos.Y, targetPos.Z)
    end

    local function enableControlsBlock()
        if not controlsDisabled then
            Controls:Disable()
            controlsDisabled = true
        end
    end

    local function disableControlsBlock()
        if controlsDisabled then
            Controls:Enable()
            controlsDisabled = false

            task.defer(function()
                local pressedKeys = {
                    Enum.KeyCode.W,
                    Enum.KeyCode.A,
                    Enum.KeyCode.S,
                    Enum.KeyCode.D,
                }

                for _, key in pressedKeys do
                    if UserInputService:IsKeyDown(key) then
                        local VIM = game:GetService('VirtualInputManager')
                        VIM:SendKeyEvent(false, key, false, game)
                        task.wait()
                        VIM:SendKeyEvent(true, key, false, game)
                    end
                end
            end)
        end
    end

    local function autoWalkLoop()
        if not AutoTackle.Enabled or not AutoWalk.Enabled then
            currentMoveVector = Vector3.zero
            pendingMoveVector = Vector3.zero
            hasPendingChange = false
            disableControlsBlock()
            return
        end

        if not entitylib.isAlive then
            currentMoveVector = Vector3.zero
            disableControlsBlock()
            return
        end

        if iHaveBall() then
            currentMoveVector = Vector3.zero
            disableControlsBlock()
            return
        end

        local ball = findBall()
        if not ball then
            currentMoveVector = Vector3.zero
            disableControlsBlock()
            return
        end

        local myRoot = entitylib.character.RootPart
        if not myRoot then
            currentMoveVector = Vector3.zero
            disableControlsBlock()
            return
        end

        local distToBall = (ball.Position - myRoot.Position).Magnitude

        if distToBall > WalkSearchRange.Value then
            currentMoveVector = Vector3.zero
            disableControlsBlock()
            return
        end

        enableControlsBlock()

        if isAttacking then
            local desiredDir = getDirectionToPoint(ball.Position)
            forceMovement(desiredDir)
            return
        end

        local desiredDir

        if SmartMode.Enabled then
            local smartTarget = getSmartTargetPos(ball.Position)
            local distToTarget = (Vector3.new(smartTarget.X, 0, smartTarget.Z) - Vector3.new(myRoot.Position.X, 0, myRoot.Position.Z)).Magnitude

            if distToTarget > 1.5 then
                desiredDir = getDirectionToPoint(smartTarget)
            else
                local interval = StrafeInterval.Value / 100
                if tick() - lastStrafeSwitch > interval then
                    strafeDirection = -strafeDirection
                    lastStrafeSwitch = tick()
                end
                desiredDir = getStrafeDirection(ball.Position)
            end
        else
            if distToBall > WalkTargetDistance.Value then
                desiredDir = getDirectionToPoint(ball.Position)
            else
                local interval = StrafeInterval.Value / 100
                if tick() - lastStrafeSwitch > interval then
                    strafeDirection = -strafeDirection
                    lastStrafeSwitch = tick()
                end
                desiredDir = getStrafeDirection(ball.Position)
            end
        end

        requestMovement(desiredDir)
    end

    local function movementApplyLoop()
        if not AutoTackle.Enabled or not AutoWalk.Enabled then return end
        if not controlsDisabled then return end

        local char = lplr.Character
        if not char then return end

        local hum = char:FindFirstChildOfClass('Humanoid')
        if not hum then return end

        hum:Move(currentMoveVector, false)
    end

    AutoTackle = vape.Categories.realista:CreateModule({
        Name = 'demontackle',
        Function = function(callback)
            if callback then
                if not ActionRemote then
                    AutoTackle:Toggle()
                    return
                end

                isAttacking = false
                cachedBall = nil
                lastEnemyOwner = nil
                watching = false
                lastStrafeSwitch = tick()
                strafeDirection = 1
                currentMoveVector = Vector3.zero
                pendingMoveVector = Vector3.zero
                hasPendingChange = false

                rebuildCache()

                AutoTackle:Clean(lplr.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    rebuildCache()
                    cachedBall = nil
                    lastEnemyOwner = nil
                    watching = false
                end))

                AutoTackle:Clean(runService.Heartbeat:Connect(mainLoop))
                AutoTackle:Clean(runService.Heartbeat:Connect(autoWalkLoop))
                AutoTackle:Clean(runService.Stepped:Connect(movementApplyLoop))
            else
                isAttacking = false
                cachedBall = nil
                lastEnemyOwner = nil
                watching = false
                currentMoveVector = Vector3.zero
                disableControlsBlock()
            end
        end,
        Tooltip = 'Detecta chute do inimigo e da tackle no timing perfeito do cantGrab.'
    })

    DetectRange = AutoTackle:CreateSlider({
        Name = 'Detect Range',
        Min = 3, Max = 30, Default = 15,
        Suffix = function(val) return val == 1 and ' stud' or ' studs' end
    })

    TackleSpeed = AutoTackle:CreateSlider({
        Name = 'Tackle Speed',
        Min = 20, Max = 80, Default = 40,
        Suffix = function(val) return ' studs/s' end,
        Tooltip = '40 = velocidade real do jogo'
    })

    MaxBallHeight = AutoTackle:CreateSlider({
        Name = 'Max Ball Height',
        Min = 0, Max = 15, Default = 4,
        Suffix = function(val) return ' studs' end,
        Tooltip = 'Altura maxima da bola em relacao ao seu pe.'
    })

    FramePerfect = AutoTackle:CreateToggle({
        Name = 'Frame Perfect',
        Default = true,
        Tooltip = 'Espera o cantGrab virar false e compensa o ping.'
    })

    AutoWalk = AutoTackle:CreateToggle({
        Name = 'Auto Walk',
        Default = false,
        Tooltip = 'Anda ate a bola e faz jockey (movimento nativo via Humanoid:Move)'
    })

    SmartMode = AutoTackle:CreateToggle({
        Name = 'Smart Mode',
        Default = false,
        Tooltip = 'Marca ficando SEMPRE entre a bola e seu gol. Posicionamento defensivo real.'
    })

    WalkSearchRange = AutoTackle:CreateSlider({
        Name = 'Walk Search Range',
        Min = 10, Max = 100, Default = 40,
        Suffix = function(val) return ' studs' end,
        Tooltip = 'So anda se a bola estiver dentro dessa distancia'
    })

    WalkTargetDistance = AutoTackle:CreateSlider({
        Name = 'Walk Stop Distance',
        Min = 2, Max = 20, Default = 5,
        Suffix = function(val) return ' studs' end,
        Tooltip = 'Distancia que quer manter da bola'
    })

    StrafeInterval = AutoTackle:CreateSlider({
        Name = 'Jockey Speed',
        Min = 20, Max = 150, Default = 40,
        Suffix = function(val) return 'ms (' .. string.format("%.2f", val / 100) .. 's)' end,
        Tooltip = 'Intervalo do toquezinho lateral'
    })

    WalkReactionDelay = AutoTackle:CreateSlider({
        Name = 'Walk Reaction Delay',
        Min = 0, Max = 500, Default = 100,
        Suffix = function(val) return 'ms' end,
        Tooltip = 'Delay antes de mudar direcao no auto walk'
    })
end)

run(function()
    local ManualHeader
    local OnlyWithoutBall
    local ActionMode
    local BicycleRange

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')

    local lplr = lplr or Players.LocalPlayer

    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141
    local FANS_TEAM_COLOR = 199
    local BICYCLE_HEIGHT_THRESHOLD = 10
    local HEADER_COOLDOWN = 2.8

    local ActionRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('Action')

    _G.__HeaderCooldownState = _G.__HeaderCooldownState or { lastFire = 0 }
    local sharedState = _G.__HeaderCooldownState

    _G.__HeaderJump = false

    local cachedBall = nil
    local cachedWeld = nil

    local function isFan()
        local color = lplr.TeamColor and lplr.TeamColor.Number
        return color == FANS_TEAM_COLOR
    end

    local function isHeaderOnCooldown()
        return tick() - sharedState.lastFire < HEADER_COOLDOWN
    end

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function iHaveBall()
        local ball = findBall()
        if not ball then return false end

        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return false
        end

        local rootPart = cachedWeld.Part0
        if not rootPart then return false end

        return rootPart.Parent == lplr.Character
    end

    local function getEnemyGoal()
        local colorNumber = lplr.TeamColor and lplr.TeamColor.Number

        if colorNumber == AWAY_TEAM_COLOR then
            return workspace:FindFirstChild('AwayGoalDetector')
        elseif colorNumber == HOME_TEAM_COLOR then
            return workspace:FindFirstChild('HomeGoalDetector')
        end

        return nil
    end

    local function distanceToEnemyGoal()
        local char = lplr.Character
        local hrp = char and char:FindFirstChild('HumanoidRootPart')
        if not hrp then return math.huge end

        local goal = getEnemyGoal()
        if not goal then return math.huge end

        return (hrp.Position - goal.Position).Magnitude
    end

    local function canDoBicycle()
        return distanceToEnemyGoal() <= BicycleRange.Value
    end

    local function abortModule()
        task.defer(function()
            if ManualHeader.Enabled then
                ManualHeader:Toggle()
            end
        end)
    end

    local function resolveAction()
        local selected = ActionMode.Value

        if selected == 'Header' then
            return 'Header'
        end

        if selected == 'BicycleKick' then
            return canDoBicycle() and 'BicycleKick' or 'Header'
        end

        if selected == 'Auto' then
            local ball = findBall()
            -- 4v4 novo usa ~5.5; 7v7 usava ~10. Auto ainda usa 10 pra bicicleta “alta”
            if ball and ball.Position.Y >= BICYCLE_HEIGHT_THRESHOLD and canDoBicycle() then
                return 'BicycleKick'
            end
            return 'Header'
        end

        if selected == 'Alternate' then
            local action
            if _G.__lastAlternateAction == 'Header' and canDoBicycle() then
                action = 'BicycleKick'
            else
                action = 'Header'
            end
            _G.__lastAlternateAction = action
            return action
        end

        return 'Header'
    end

    local function watchLanding(char)
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        if not hum then return end

        local conn
        conn = hum.StateChanged:Connect(function(_, new)
            if new == Enum.HumanoidStateType.Landed
            or new == Enum.HumanoidStateType.Running
            or new == Enum.HumanoidStateType.RunningNoPhysics then
                _G.__HeaderJump = false
                _G.__AerialReachActive = false
                if conn then conn:Disconnect() end
            end
        end)
    end

    local function performHeader()
        local char = lplr.Character
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        local root = char and char:FindFirstChild('HumanoidRootPart')
        if not hum or not root then return end

        local action = resolveAction()

        _G.__HeaderJump = true
        _G.__AerialReachActive = true
        _G.__LastAerialReachTime = tick()

        -------------------------------------------------
        -- SEMPRE: física nativa JumpPower 35 (4v4 + 7v7)
        -------------------------------------------------
        watchLanding(char)

        hum.JumpPower = 35
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        hum.Jump = true

        ActionRemote:FireServer(action)
        sharedState.lastFire = tick()

        task.spawn(function()
            task.wait(0.2)
            if hum and hum.Parent then
                hum.JumpPower = 0
            end
        end)

        return true
    end

    ManualHeader = vape.Categories.realista:CreateModule({
        Name = 'ManualHeader',
        Function = function(callback)
            if not callback then return end

            if not ActionRemote then
                abortModule()
                return
            end

            if isFan() then
                abortModule()
                return
            end

            if OnlyWithoutBall.Enabled and iHaveBall() then
                abortModule()
                return
            end

            if isHeaderOnCooldown() then
                abortModule()
                return
            end

            performHeader()

            abortModule()
        end,
        Tooltip = 'Header/BicycleKick com pulo nativo 35 (4v4 e 7v7 iguais).'
    })

    lplr.CharacterAdded:Connect(function()
        _G.__HeaderJump = false
        _G.__AerialReachActive = false
    end)

    ActionMode = ManualHeader:CreateDropdown({
        Name = 'Action',
        List = {'Auto', 'Header', 'BicycleKick', 'Alternate'},
        Default = 'Auto',
        Tooltip = 'Auto: pela altura da bola | Header | BicycleKick | Alternate'
    })

    BicycleRange = ManualHeader:CreateSlider({
        Name = 'Bicycle Max Range',
        Min = 10, Max = 150, Default = 60,
        Suffix = function(val) return ' studs' end,
        Tooltip = 'Distância máxima do gol para bicicleta'
    })

    OnlyWithoutBall = ManualHeader:CreateToggle({
        Name = 'Only Without Ball',
        Default = false,
        Tooltip = 'Só dispara se você NÃO estiver com a bola'
    })
end)

run(function()
    local ManualHeaderTackle
    local ServerMode
    local AutoAim
    local AimRange
    local OnlyWithoutBall

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local Debris = game:GetService('Debris')

    local lplr = lplr or Players.LocalPlayer

    local TACKLE_FORCE_DURATION = 0.65
    local FANS_TEAM_COLOR = 199
    local HEADER_COOLDOWN = 2.8

    -- Só a velocidade do tackle muda; PULO existe nos dois modos agora
    local MODE_CONFIG = {
        ['4v4'] = { tackleSpeed = 40 },
        ['7v7'] = { tackleSpeed = 50 },
    }

    local ActionRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('Action')

    _G.__HeaderCooldownState = _G.__HeaderCooldownState or { lastFire = 0 }
    local sharedState = _G.__HeaderCooldownState

    _G.__HeaderJump = false

    local cachedBall = nil
    local cachedWeld = nil

    local charCache = {
        tackleDebounce = nil,
    }

    local function rebuildCache()
        local char = lplr.Character
        if not char then return end

        local bools = char:FindFirstChild('Bools')
        if not bools then return end

        charCache.tackleDebounce = bools:FindFirstChild('TackleDebounce')
    end

    local function getConfig()
        return MODE_CONFIG[ServerMode.Value] or MODE_CONFIG['4v4']
    end

    local function isFan()
        local color = lplr.TeamColor and lplr.TeamColor.Number
        return color == FANS_TEAM_COLOR
    end

    local function isHeaderOnCooldown()
        return tick() - sharedState.lastFire < HEADER_COOLDOWN
    end

    local function isTackleOnCooldown()
        return charCache.tackleDebounce and charCache.tackleDebounce.Value
    end

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function iHaveBall()
        local ball = findBall()
        if not ball then return false end

        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return false
        end

        local rootPart = cachedWeld.Part0
        if not rootPart then return false end

        return rootPart.Parent == lplr.Character
    end

    local function abortModule()
        task.defer(function()
            if ManualHeaderTackle.Enabled then
                ManualHeaderTackle:Toggle()
            end
        end)
    end

    local function aimAtBall(ball, dist)
        local myRoot = (entitylib and entitylib.isAlive and entitylib.character and entitylib.character.RootPart)
            or (lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart'))
        if not myRoot or not ball then return end

        local config = getConfig()
        local timeToReach = dist / config.tackleSpeed
        local ballVel = ball.AssemblyLinearVelocity or Vector3.zero
        local predictedPos = ball.Position + (ballVel * timeToReach)

        local lookAtPos = Vector3.new(predictedPos.X, myRoot.Position.Y, predictedPos.Z)
        myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookAtPos)
    end

    local function watchLanding(char)
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        if not hum then return end

        local conn
        conn = hum.StateChanged:Connect(function(_, new)
            if new == Enum.HumanoidStateType.Landed
            or new == Enum.HumanoidStateType.Running
            or new == Enum.HumanoidStateType.RunningNoPhysics then
                _G.__HeaderJump = false
                _G.__AerialReachActive = false
                if conn then conn:Disconnect() end
            end
        end)
    end

    local function doHeader()
        local char = lplr.Character
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        local root = char and char:FindFirstChild('HumanoidRootPart')
        if not hum or not root then return end

        -- Sinaliza header REAL (BallMagnet / HeaderShield / AutoJuggle)
        _G.__HeaderJump = true
        _G.__AerialReachActive = true
        _G.__LastAerialReachTime = tick()

        -------------------------------------------------
        -- 4v4 E 7v7: Pulo nativo JumpPower = 35 (update do jogo)
        -------------------------------------------------
        watchLanding(char)

        hum.JumpPower = 35
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        hum.Jump = true

        ActionRemote:FireServer('Header')
        sharedState.lastFire = tick()

        task.spawn(function()
            task.wait(0.2)
            if hum and hum.Parent then
                hum.JumpPower = 0
            end
        end)
    end

    local function doTackle()
        local root = (entitylib and entitylib.isAlive and entitylib.character and entitylib.character.RootPart)
            or (lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart'))
        if not root or not ActionRemote then return end

        local config = getConfig()

        ActionRemote:FireServer('TackIe')

        local bv = Instance.new('BodyVelocity')
        bv.Velocity = root.CFrame.LookVector * config.tackleSpeed
        bv.MaxForce = Vector3.new(50000000, 0, 50000000)
        bv.Parent = root
        Debris:AddItem(bv, TACKLE_FORCE_DURATION)

        local gyro = Instance.new('BodyGyro')
        gyro.Name = 'TackleGyro'
        gyro.P = 950000
        gyro.MaxTorque = Vector3.new(0, 100000, 0)
        gyro.CFrame = root.CFrame
        gyro.Parent = root
        Debris:AddItem(gyro, TACKLE_FORCE_DURATION)
    end

    local function tryAutoAim()
        if not AutoAim.Enabled then return end

        local ball = findBall()
        local myRoot = (entitylib and entitylib.isAlive and entitylib.character and entitylib.character.RootPart)
            or (lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart'))
        if not ball or not myRoot then return end

        local dist = (ball.Position - myRoot.Position).Magnitude
        if dist > AimRange.Value then return end

        aimAtBall(ball, dist)
    end

    ManualHeaderTackle = vape.Categories.realista:CreateModule({
        Name = 'sonic jump',
        Function = function(callback)
            if not callback then return end

            if not ActionRemote then
                abortModule()
                return
            end

            if isFan() then
                abortModule()
                return
            end

            rebuildCache()

            if OnlyWithoutBall.Enabled and iHaveBall() then
                abortModule()
                return
            end

            if isHeaderOnCooldown() or isTackleOnCooldown() then
                abortModule()
                return
            end

            tryAutoAim()
            doHeader()
            doTackle()

            abortModule()
        end,
        Tooltip = 'Header + Tackle. Pulo 35 nativo em 4v4 e 7v7. Tackle 40 (4v4) / 50 (7v7).'
    })

    lplr.CharacterAdded:Connect(function()
        _G.__HeaderJump = false
        _G.__AerialReachActive = false
    end)

    ServerMode = ManualHeaderTackle:CreateDropdown({
        Name = 'Game Mode',
        List = {'4v4', '7v7'},
        Default = '4v4',
        Tooltip = 'Só muda velocidade do tackle: 4v4 = 40 | 7v7 = 50. Pulo 35 nos dois.'
    })

    AutoAim = ManualHeaderTackle:CreateToggle({
        Name = 'Auto Aim (na bola)',
        Default = true,
        Function = function(callback)
            if AimRange and AimRange.Object then
                AimRange.Object.Visible = callback
            end
        end,
        Tooltip = 'Vira o corpo pra bola antes de disparar'
    })

    AimRange = ManualHeaderTackle:CreateSlider({
        Name = 'Aim Range',
        Min = 5, Max = 50, Default = 20,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
        Tooltip = 'Só mira se a bola estiver dentro desse range'
    })

    OnlyWithoutBall = ManualHeaderTackle:CreateToggle({
        Name = 'Only Without Ball',
        Default = false,
        Tooltip = 'Só dispara se você NÃO estiver com a bola'
    })
end)

run(function()
    local AutoDribble
    local SafeRadius
    local DangerRadius
    local ThreatThreshold
    local DribbleChance
    local ScanRate

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')

    local TACKLE_ANIM_ID = '14317040670'
    local TACKLE_DASH_SPEED = 35
    local TACKLE_DASH_SPEED_SQ = TACKLE_DASH_SPEED * TACKLE_DASH_SPEED
    local TACKLE_COOLDOWN = 0.8
    local TACKLE_ANIM_WINDOW = 1.5
    local VELOCITY_DOT_MIN = 0.5
    local LOOK_DOT_MIN = 0.5
    local VELOCITY_SCORE_MAX = 40
    local ANIM_SCORE_MAX = 60
    local TACKLING_SCORE = 50
    local LOOK_SCORE_MAX = 20
    local DIST_SCORE_WEIGHT = 0.4
    local SAFE_ZONE_BONUS = 10

    local ActionRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('Action')

    local cachedBall = nil
    local cachedWeld = nil
    local ballConnections = {}
    local lastDribbleTime = 0
    local scanLoopActive = false

    local enemyCache = {}
    local enemyList = {}

    local charCache = {
        tackled = nil,
        debounce = nil,
        iframe = nil,
        tackling = nil,
        dribbleDebounce = nil,
        header = nil,
        powerShooting = nil,
        freeKick = nil,
        penalty = nil,
        kickoff = nil,
        apg = nil,
        hpg = nil,
    }

    local cachedSliders = {
        safeRadiusSq = 25,
        dangerRadius = 18,
        dangerRadiusSq = 324,
        threatThreshold = 70,
        dribbleChance = 100,
    }

    local function updateSliderCache()
        local sr = SafeRadius.Value
        local dr = DangerRadius.Value
        cachedSliders.safeRadiusSq = sr * sr
        cachedSliders.dangerRadius = dr
        cachedSliders.dangerRadiusSq = dr * dr
        cachedSliders.threatThreshold = ThreatThreshold.Value
        cachedSliders.dribbleChance = DribbleChance.Value
    end

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function getBallWeld()
        local ball = findBall()
        if not ball then return nil end

        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return nil
        end

        return cachedWeld
    end

    local function iHaveBall()
        local ball = findBall()
        if not ball then return false end

        local weld = getBallWeld()
        if not weld or not weld.Part0 then return false end
        if weld.Part0.Parent ~= lplr.Character then return false end

        local creator = ball:FindFirstChild('creator')
        if not creator or creator.Value ~= lplr then return false end

        return true
    end

    local function rebuildSelfCache()
        local char = lplr.Character
        if not char then return end

        local bools = char:FindFirstChild('Bools')
        local wsBools = workspace:FindFirstChild('Bools')

        charCache.tackled = bools and bools:FindFirstChild('Tackled')
        charCache.debounce = bools and bools:FindFirstChild('Debounce')
        charCache.iframe = bools and bools:FindFirstChild('iframe')
        charCache.tackling = bools and bools:FindFirstChild('Tackling')
        charCache.dribbleDebounce = bools and bools:FindFirstChild('dribbleDebounce')
        charCache.header = bools and bools:FindFirstChild('Header')
        charCache.powerShooting = bools and bools:FindFirstChild('PowerShooting')
        charCache.freeKick = wsBools and wsBools:FindFirstChild('FreeKick')
        charCache.penalty = wsBools and wsBools:FindFirstChild('Penalty')
        charCache.kickoff = wsBools and wsBools:FindFirstChild('Kickoff')
        charCache.apg = wsBools and wsBools:FindFirstChild('APG')
        charCache.hpg = wsBools and wsBools:FindFirstChild('HPG')
    end

    local function canDribble()
        if not entitylib.isAlive then return false end
        if tick() - lastDribbleTime < TACKLE_COOLDOWN then return false end
        if charCache.apg and charCache.apg.Value == lplr then return false end
        if charCache.hpg and charCache.hpg.Value == lplr then return false end
        if charCache.tackled and charCache.tackled.Value then return false end
        if charCache.debounce and charCache.debounce.Value then return false end
        if charCache.iframe and charCache.iframe.Value then return false end
        if charCache.tackling and charCache.tackling.Value then return false end
        if charCache.dribbleDebounce and charCache.dribbleDebounce.Value then return false end
        if charCache.header and charCache.header.Value then return false end
        if charCache.powerShooting and charCache.powerShooting.Value then return false end
        if charCache.freeKick and charCache.freeKick.Value then return false end
        if charCache.penalty and charCache.penalty.Value then return false end
        if charCache.kickoff and charCache.kickoff.Value then return false end
        return true
    end

    local function doDribble()
        if not ActionRemote then return end
        if not canDribble() then return end
        if not iHaveBall() then return end

        local chance = cachedSliders.dribbleChance
        if chance < 100 then
            if math.random(1, 100) > chance then
                lastDribbleTime = tick()
                return
            end
        end

        lastDribbleTime = tick()
        ActionRemote:FireServer('Deke')
    end

    local function calculateThreatFast(cache, myX, myZ, now)
        local root = cache.root
        if not root or not root.Parent then return 0 end

        local rootPos = root.Position
        local dx = rootPos.X - myX
        local dz = rootPos.Z - myZ
        local distSq = dx * dx + dz * dz

        if distSq > cachedSliders.dangerRadiusSq then return 0 end

        local dist = math.sqrt(distSq)
        local score = 0

        local distScore = (1 - (dist / cachedSliders.dangerRadius)) * 100
        score = score + distScore * DIST_SCORE_WEIGHT

        if cache.tackling and cache.tackling.Value then
            score = score + TACKLING_SCORE
        end

        local timeSinceAnim = now - cache.animSince
        if timeSinceAnim < TACKLE_ANIM_WINDOW then
            score = score + ANIM_SCORE_MAX * (1 - timeSinceAnim / TACKLE_ANIM_WINDOW)
        end

        local vel = root.AssemblyLinearVelocity
        local vx, vz = vel.X, vel.Z
        local speedSq = vx * vx + vz * vz

        if speedSq > TACKLE_DASH_SPEED_SQ then
            local speed = math.sqrt(speedSq)
            local vxN = vx / speed
            local vzN = vz / speed
            local dirX = -dx / dist
            local dirZ = -dz / dist
            local dot = vxN * dirX + vzN * dirZ

            if dot > VELOCITY_DOT_MIN then
                local velScore = math.clamp((speed - TACKLE_DASH_SPEED) / 15, 0, 1) * VELOCITY_SCORE_MAX * dot
                score = score + velScore
            end
        end

        local look = root.CFrame.LookVector
        local lookX, lookZ = look.X, look.Z
        local lookMag = math.sqrt(lookX * lookX + lookZ * lookZ)

        if lookMag > 0.01 then
            local lookXN = lookX / lookMag
            local lookZN = lookZ / lookMag
            local dirX = -dx / dist
            local dirZ = -dz / dist
            local lookDot = lookXN * dirX + lookZN * dirZ

            if lookDot > LOOK_DOT_MIN then
                score = score + LOOK_SCORE_MAX * lookDot
            end
        end

        if distSq <= cachedSliders.safeRadiusSq then
            local minScore = cachedSliders.threatThreshold + SAFE_ZONE_BONUS
            if score < minScore then score = minScore end
        end

        return score
    end

    local function evaluateThreatsNow()
        if not iHaveBall() then return end
        if not entitylib.isAlive then return end

        local char = entitylib.character
        if not char then return end

        local myRoot = char.RootPart
        if not myRoot then return end

        updateSliderCache()

        local myPos = myRoot.Position
        local myX, myZ = myPos.X, myPos.Z
        local now = tick()
        local threshold = cachedSliders.threatThreshold

        local highestThreat = 0

        for i = 1, #enemyList do
            local cache = enemyList[i]
            local threat = calculateThreatFast(cache, myX, myZ, now)
            if threat > highestThreat then
                highestThreat = threat
                if highestThreat >= threshold then
                    doDribble()
                    return
                end
            end
        end
    end

    local function onEnemyTackleDetected(cache)
        if not AutoDribble.Enabled then return end
        cache.animSince = tick()
        task.spawn(evaluateThreatsNow)
    end

    local function rebuildEnemyList()
        table.clear(enemyList)
        for plr, cache in enemyCache do
            if plr.Team ~= lplr.Team and cache.root and cache.root.Parent then
                table.insert(enemyList, cache)
            end
        end
    end

    local function disconnectEnemyConnections(cache)
        if not cache then return end
        if cache.animConnection then cache.animConnection:Disconnect() end
        if cache.tacklingConnection then cache.tacklingConnection:Disconnect() end
    end

    local function cacheEnemy(plr)
        if plr == lplr then return end

        local function setup(char)
            local hum = char:WaitForChild('Humanoid', 5)
            local root = char:WaitForChild('HumanoidRootPart', 5)
            local bools = char:WaitForChild('Bools', 5)
            if not hum or not root or not bools then return end

            local tacklingBool = bools:FindFirstChild('Tackling')

            local cache = {
                player = plr,
                char = char,
                root = root,
                bools = bools,
                tackling = tacklingBool,
                animSince = 0,
                animConnection = nil,
                tacklingConnection = nil,
            }
            enemyCache[plr] = cache

            cache.animConnection = hum.AnimationPlayed:Connect(function(track)
                if not AutoDribble.Enabled then return end

                local anim = track.Animation
                if not anim then return end

                local animId = anim.AnimationId
                if not animId or not animId:find(TACKLE_ANIM_ID) then return end

                onEnemyTackleDetected(cache)
            end)

            if tacklingBool then
                cache.tacklingConnection = tacklingBool:GetPropertyChangedSignal('Value'):Connect(function()
                    if not AutoDribble.Enabled then return end
                    if tacklingBool.Value == true and plr.Team ~= lplr.Team then
                        task.spawn(evaluateThreatsNow)
                    end
                end)
            end

            rebuildEnemyList()
        end

        if plr.Character then
            task.spawn(setup, plr.Character)
        end

        plr.CharacterAdded:Connect(function(char)
            disconnectEnemyConnections(enemyCache[plr])
            enemyCache[plr] = nil
            rebuildEnemyList()
            task.wait(0.3)
            setup(char)
        end)

        plr:GetPropertyChangedSignal('Team'):Connect(rebuildEnemyList)
    end

    local function checkImmediateGrabProtection()
        if not AutoDribble.Enabled or not iHaveBall() then return end

        local myRoot = entitylib.character and entitylib.character.RootPart
        if not myRoot then return end

        updateSliderCache()
        local myPos = myRoot.Position
        local myX, myZ = myPos.X, myPos.Z
        local dangerSq = cachedSliders.dangerRadiusSq

        for i = 1, #enemyList do
            local cache = enemyList[i]
            if cache.tackling and cache.tackling.Value then
                local rp = cache.root.Position
                local dx = rp.X - myX
                local dz = rp.Z - myZ
                if dx * dx + dz * dz <= dangerSq then
                    doDribble()
                    return
                end
            end
        end
    end

    local function setupBallWatcher()
        for _, conn in ballConnections do
            conn:Disconnect()
        end
        table.clear(ballConnections)

        local ball = findBall()
        if not ball then return end

        table.insert(ballConnections, ball.ChildAdded:Connect(function(child)
            if child.Name ~= 'playerWeld' or not child:IsA('Weld') then return end
            cachedWeld = child

            local rootPart = child.Part0
            if not rootPart or rootPart.Parent ~= lplr.Character then return end

            task.defer(checkImmediateGrabProtection)
        end))

        table.insert(ballConnections, ball.ChildRemoved:Connect(function(child)
            if child.Name == 'playerWeld' then
                cachedWeld = nil
            end
        end))
    end

    local function startScanLoop()
        scanLoopActive = true
        task.spawn(function()
            while scanLoopActive and AutoDribble.Enabled do
                task.wait(1 / ScanRate.Value)
                if not scanLoopActive or not AutoDribble.Enabled then break end
                evaluateThreatsNow()
            end
        end)
    end

    AutoDribble = vape.Categories.realista:CreateModule({
        Name = 'AutoDribble',
        Function = function(callback)
            if callback then
                if not ActionRemote then
                    AutoDribble:Toggle()
                    return
                end

                rebuildSelfCache()
                updateSliderCache()
                setupBallWatcher()

                enemyCache = {}
                table.clear(enemyList)

                for _, plr in Players:GetPlayers() do
                    cacheEnemy(plr)
                end

                AutoDribble:Clean(Players.PlayerAdded:Connect(cacheEnemy))

                AutoDribble:Clean(Players.PlayerRemoving:Connect(function(plr)
                    disconnectEnemyConnections(enemyCache[plr])
                    enemyCache[plr] = nil
                    rebuildEnemyList()
                end))

                AutoDribble:Clean(lplr.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    rebuildSelfCache()
                    cachedBall = nil
                    cachedWeld = nil
                    setupBallWatcher()
                end))

                AutoDribble:Clean(lplr:GetPropertyChangedSignal('Team'):Connect(rebuildEnemyList))

                startScanLoop()
            else
                scanLoopActive = false

                for _, conn in ballConnections do
                    conn:Disconnect()
                end
                table.clear(ballConnections)

                for _, cache in enemyCache do
                    disconnectEnemyConnections(cache)
                end

                enemyCache = {}
                table.clear(enemyList)
                cachedBall = nil
                cachedWeld = nil
            end
        end,
        Tooltip = 'AutoDribble com deteccao via animacao + otimizacoes de CPU.'
    })

    ScanRate = AutoDribble:CreateSlider({
        Name = 'Scan Rate',
        Min = 30, Max = 500, Default = 200,
        Suffix = function(val) return ' scans/s' end,
        Tooltip = 'Quantas vezes por segundo avalia ameacas. Independe do FPS.'
    })

    SafeRadius = AutoDribble:CreateSlider({
        Name = 'Safe Radius',
        Min = 0, Max = 10, Default = 5, Decimal = 10,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
        Tooltip = 'Dentro desse raio, ameaca e SEMPRE maxima'
    })

    DangerRadius = AutoDribble:CreateSlider({
        Name = 'Danger Radius',
        Min = 5, Max = 50, Default = 18,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
        Tooltip = 'Distancia maxima para avaliar ameacas'
    })

    ThreatThreshold = AutoDribble:CreateSlider({
        Name = 'Threat Threshold',
        Min = 30, Max = 100, Default = 70,
        Tooltip = 'Score minimo de ameaca pra disparar drible'
    })

    DribbleChance = AutoDribble:CreateSlider({
        Name = 'Dribble Chance',
        Min = 0, Max = 100, Default = 100,
        Suffix = function(val) return '%' end,
        Tooltip = '% de chance do drible disparar'
    })
end)

run(function()
    local BallTP
    local MovementMode
    local Length
    local Delay

    local function findBall()
        for _, v in workspace:GetChildren() do
            if v.Name:lower() == 'ball' and v:IsA('BasePart') then
                return v
            end
        end
    end

    BallTP = vape.Categories.farmRSS:CreateModule({
        Name = 'BallTP',
        Function = function(callback)
            if callback then
                local ball = findBall()
                
                if not ball then
                    BallTP:Toggle()
                    return
                end

                local position = ball.Position

                if MovementMode.Value ~= 'Lerp' then
                    BallTP:Toggle()
                    if entitylib.isAlive then
                        if MovementMode.Value == 'Motor' then
                            motorMove(entitylib.character.RootPart, CFrame.lookAlong(position, entitylib.character.RootPart.CFrame.LookVector))
                        else
                            entitylib.character.RootPart.CFrame = CFrame.lookAlong(position, entitylib.character.RootPart.CFrame.LookVector)
                        end
                    end
                else
                    BallTP:Clean(runService.Heartbeat:Connect(function()
                        if entitylib.isAlive then
                            entitylib.character.RootPart.Velocity = Vector3.zero
                        end
                    end))

                    repeat
                        if entitylib.isAlive then
                            ball = findBall()
                            if ball then
                                position = ball.Position
                            end

                            local direction = CFrame.lookAt(entitylib.character.RootPart.Position, position).LookVector * math.min((entitylib.character.RootPart.Position - position).Magnitude, Length.Value)
                            entitylib.character.RootPart.CFrame += direction

                            if (entitylib.character.RootPart.Position - position).Magnitude < 3 and BallTP.Enabled then
                                BallTP:Toggle()
                            end
                        elseif BallTP.Enabled then
                            BallTP:Toggle()
                        end

                        task.wait(Delay.Value)
                    until not BallTP.Enabled
                end
            end
        end,
        Tooltip = 'Teleports to the Ball in workspace.'
    })

    MovementMode = BallTP:CreateDropdown({
        Name = 'Movement',
        List = {'CFrame', 'Motor', 'Lerp'},
        Function = function(val)
            Length.Object.Visible = val == 'Lerp'
            Delay.Object.Visible = val == 'Lerp'
        end
    })

    Length = BallTP:CreateSlider({
        Name = 'Length',
        Min = 0,
        Max = 150,
        Default = 50,
        Darker = true,
        Visible = false,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })

    Delay = BallTP:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 1,
        Default = 0,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })
end)

run(function()
    local SwitchTeam
    local RoleMode

    local TeamChangeRemote = game:GetService('ReplicatedStorage'):WaitForChild('Remotes'):WaitForChild('TeamChange')

    local function getEnemyTeam()
        local myTeam = lplr.Team
        if not myTeam then return nil end

        for _, t in game:GetService('Teams'):GetChildren() do
            if t ~= myTeam and t.Name:lower() ~= 'fans' then
                return t
            end
        end
        return nil
    end

    SwitchTeam = vape.Categories.farmRSS:CreateModule({
        Name = 'SwitchTeam',
        Function = function(callback)
            if callback then
                local myTeam = lplr.Team

                if not myTeam or myTeam.Name:lower() == 'fans' then
                    SwitchTeam:Toggle()
                    return
                end

                local enemy = getEnemyTeam()
                if not enemy then
                    SwitchTeam:Toggle()
                    return
                end

                TeamChangeRemote:FireServer(enemy.TeamColor, RoleMode.Value)

                SwitchTeam:Toggle()
            end
        end,
        Tooltip = 'Troca para o time inimigo via Remote (funciona no meio da partida).'
    })

    RoleMode = SwitchTeam:CreateDropdown({
        Name = 'Role',
        List = {'Player', 'Goalie'}
    })
end)

run(function()
    local AutoKick
    local KickPower
    local PlayAnim

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local UserInputService = game:GetService('UserInputService')

    local POWER_THRESHOLD_STRONG = 0.5
    local BACKWARD_ANGLE_MIN = 135

    local ShootRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('ShootTheBaII')
    local Animations = ReplicatedStorage:WaitForChild('Animations')

    local shootAnimNormal = Animations:FindFirstChild('RShoot')
    local shootAnimStrong = Animations:FindFirstChild('RShoot2')
    local shootAnimBackward = Animations:FindFirstChild('RShootBackward')

    local cachedBall = nil
    local cachedWeld = nil

    local mouse = lplr:GetMouse()

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function haveBallPossession()
        local ball = findBall()
        if not ball then return false end

        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return false
        end

        local rootPart = cachedWeld.Part0
        if not rootPart then return false end

        return rootPart.Parent == lplr.Character
    end

    local function getCurve()
        local char = lplr.Character
        if not char then return 'None' end

        local bools = char:FindFirstChild('Bools')
        if not bools then return 'None' end

        local curve = bools:FindFirstChild('Curve')
        if not curve then return 'None' end

        return curve.Value
    end

    local function isBackwardShot(direction)
        local char = lplr.Character
        local root = char and char:FindFirstChild('HumanoidRootPart')
        if not root then return false end

        local localDir = root.CFrame:VectorToObjectSpace(direction)
        local deg = math.deg(math.atan2(localDir.X, -localDir.Z))

        return deg > BACKWARD_ANGLE_MIN or deg < -BACKWARD_ANGLE_MIN
    end

    local function pickAnimAsset(power, direction)
        if isBackwardShot(direction) and shootAnimBackward then
            return shootAnimBackward
        end

        if power > POWER_THRESHOLD_STRONG and shootAnimStrong then
            return shootAnimStrong
        end

        return shootAnimNormal
    end

    local function playShootAnim(power, direction)
        if not PlayAnim.Enabled then return end

        local char = lplr.Character
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        if not hum then return end

        local anim = pickAnimAsset(power, direction)
        if not anim then return end

        local track = hum:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action4
        track:Play()
    end

    local function calculateShootParams(ball)
        local hit = mouse.Hit

        if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
            local camLook = workspace.CurrentCamera.CFrame.LookVector
            return camLook, camLook
        end

        local direction = (hit.Position - ball.Position).Unit
        return direction, hit.LookVector
    end

    AutoKick = vape.Categories.realista:CreateModule({
        Name = 'AutoKick',
        Function = function(callback)
            if not callback then return end

            if not ShootRemote or not entitylib.isAlive or not haveBallPossession() then
                AutoKick:Toggle()
                return
            end

            local ball = findBall()
            if not ball then
                AutoKick:Toggle()
                return
            end

            local power = KickPower.Value
            local direction, lookVector = calculateShootParams(ball)
            local curveValue = getCurve()

            playShootAnim(power, direction)

            ShootRemote:FireServer(
                direction,
                ball.CFrame,
                power,
                lookVector,
                false,
                false,
                curveValue,
                nil,
                false
            )

            AutoKick:Toggle()
        end,
        Tooltip = 'Chuta a bola na direcao do mouse com animacao'
    })

    KickPower = AutoKick:CreateSlider({
        Name = 'Power',
        Min = 0.1, Max = 1.5, Default = 1, Decimal = 100,
        Tooltip = '0.5 = RShoot (fraco) | 1.0 = RShoot2 (forte) | 1.5 = PowerShoot'
    })

    PlayAnim = AutoKick:CreateToggle({
        Name = 'Play Animation',
        Default = true
    })
end)

run(function()
    local GKHitboxESP
    local Opacity
    local HitboxColor
    local TeamCheck
    local ShowBots

    local activeHighlights = {}
    local monitorConn = nil

    local function cleanup()
        for hitbox, data in pairs(activeHighlights) do
            if hitbox and hitbox.Parent then
                pcall(function()
                    hitbox.Transparency = data.originalTransparency
                    hitbox.Color = data.originalColor
                    hitbox.Material = data.originalMaterial
                end)
            end
        end
        activeHighlights = {}
    end

    local function applyESP(hitbox)
        if not hitbox or not hitbox:IsA('BasePart') then return end

        if not activeHighlights[hitbox] then
            activeHighlights[hitbox] = {
                originalTransparency = hitbox.Transparency,
                originalColor = hitbox.Color,
                originalMaterial = hitbox.Material
            }
        end

        pcall(function()
            hitbox.Transparency = 1 - (Opacity.Value / 100)
            hitbox.Material = Enum.Material.ForceField
            hitbox.Color = HitboxColor.Value
        end)
    end

    local function restoreHitbox(hitbox)
        local data = activeHighlights[hitbox]
        if not data then return end
        if hitbox and hitbox.Parent then
            pcall(function()
                hitbox.Transparency = data.originalTransparency
                hitbox.Color = data.originalColor
                hitbox.Material = data.originalMaterial
            end)
        end
        activeHighlights[hitbox] = nil
    end

    local function getBotHitbox(modelName)
        local model = workspace:FindFirstChild(modelName)
        if not model then return nil end
        local hitbox = model:FindFirstChild('Hitbox')
        if hitbox and hitbox:IsA('BasePart') then return hitbox end
        return nil
    end

    local function getBotSide(botModel)
        local hitbox = getBotHitbox(botModel)
        if not hitbox then return nil end

        local homeGoal = workspace:FindFirstChild('HomeGoalDetector')
        local awayGoal = workspace:FindFirstChild('AwayGoalDetector')
        if not homeGoal or not awayGoal then return nil end

        local distHome = (hitbox.Position - homeGoal.Position).Magnitude
        local distAway = (hitbox.Position - awayGoal.Position).Magnitude

        if distHome < distAway then
            return 'Home'
        else
            return 'Away'
        end
    end

    local function getMyTeamSide()
        if lplr.TeamColor == BrickColor.new(141) then
            return 'Home'
        elseif lplr.TeamColor == BrickColor.new(23) then
            return 'Away'
        end
        return nil
    end

    local function scanHitboxes()
        local apg = workspace:FindFirstChild('Bools') and workspace.Bools:FindFirstChild('APG')
        local hpg = workspace:FindFirstChild('Bools') and workspace.Bools:FindFirstChild('HPG')

        local currentGoalies = {}
        local mySide = getMyTeamSide()

        local sides = {
            {bool = apg, botModel = 'Goalie'},
            {bool = hpg, botModel = 'HomeGoalie'}
        }

        for _, entry in sides do
            local boolValue = entry.bool

            if boolValue and boolValue.Value then
                local gk = boolValue.Value
                if gk and gk.Character then
                    if TeamCheck.Enabled and gk.TeamColor == lplr.TeamColor then
                        continue
                    end

                    local hitbox = gk.Character:FindFirstChild('Hitbox')
                    if hitbox and hitbox:IsA('BasePart') then
                        currentGoalies[hitbox] = true
                        applyESP(hitbox)
                    end
                end
            elseif ShowBots.Enabled then
                if TeamCheck.Enabled and mySide then
                    local botSide = getBotSide(entry.botModel)
                    if botSide == mySide then
                        continue
                    end
                end

                local hitbox = getBotHitbox(entry.botModel)
                if hitbox then
                    currentGoalies[hitbox] = true
                    applyESP(hitbox)
                end
            end
        end

        for hitbox in pairs(activeHighlights) do
            if not currentGoalies[hitbox] then
                restoreHitbox(hitbox)
            end
        end
    end

    GKHitboxESP = vape.Categories.realista:CreateModule({
        Name = 'GKHitboxESP',
        Function = function(callback)
            if callback then
                scanHitboxes()

                monitorConn = runService.Heartbeat:Connect(function()
                    if not GKHitboxESP.Enabled then return end
                    scanHitboxes()
                end)
            else
                if monitorConn then monitorConn:Disconnect(); monitorConn = nil end
                cleanup()
            end
        end,
        Tooltip = 'Mostra a hitbox real do goleiro (humano ou bot)'
    })

    Opacity = GKHitboxESP:CreateSlider({
        Name = 'Opacity',
        Min = 1,
        Max = 100,
        Default = 50,
        Suffix = '%'
    })

    HitboxColor = GKHitboxESP:CreateColorSlider({
        Name = 'Color',
        Default = Color3.fromRGB(255, 50, 50)
    })

    TeamCheck = GKHitboxESP:CreateToggle({
        Name = 'Team Check',
        Default = true,
        Tooltip = 'Só mostra goleiros do time inimigo'
    })

    ShowBots = GKHitboxESP:CreateToggle({
        Name = 'Show Bots',
        Default = true,
        Tooltip = 'Inclui goleiros bot (HomeGoalie/Goalie)'
    })
end)

run(function()
    local InfStamina
    local ModeDropdown
    local sprintKey = Enum.KeyCode.LeftShift

    local MODES = {
        ['4v4'] = 33,
        ['7v7'] = 37,
    }

    local SEVEN_V_SEVEN_WITH_BALL = 35.5

    local cachedHum = nil
    local cachedRoot = nil
    local bodyVel = nil
    local gameForceActive = false
    local sprintHeld = false
    local currentMode = '7v7'
    local hasBall = false

    local function removeBodyVel()
        if bodyVel and bodyVel.Parent then
            bodyVel:Destroy()
        end
        bodyVel = nil
    end

    local function ensureBodyVel(root)
        if bodyVel and bodyVel.Parent == root then
            return bodyVel
        end
        removeBodyVel()
        local bv = Instance.new("BodyVelocity")
        bv.Name = "InfStaminaBV"
        bv.MaxForce = Vector3.new(1e5, 0, 1e5)
        bv.Velocity = Vector3.zero
        bv.P = 1e4
        bv.Parent = root
        bodyVel = bv
        return bv
    end

    local function isGameForce(child)
        if child.Name == "InfStaminaBV" then return false end
        return child:IsA("BodyVelocity") or child:IsA("LinearVelocity")
    end

    local function getCurrentTarget()
        if currentMode == '7v7' and hasBall then
            return SEVEN_V_SEVEN_WITH_BALL
        end
        return MODES[currentMode] or 37
    end

    local function setupBallWatcher()
        local function checkBall()
            local ball = nil
            for _, v in workspace:GetChildren() do
                if v.Name:lower() == 'ball' and v:IsA('BasePart') then
                    ball = v
                    break
                end
            end

            if not ball then
                hasBall = false
                return
            end

            local weld = ball:FindFirstChild("playerWeld")
            if weld and weld:IsA("Weld") and weld.Part0 then
                hasBall = weld.Part0.Parent == lplr.Character
            else
                hasBall = false
            end

            InfStamina:Clean(ball.ChildAdded:Connect(function(child)
                if child.Name == "playerWeld" and child:IsA("Weld") then
                    if child.Part0 and child.Part0.Parent == lplr.Character then
                        hasBall = true
                    else
                        hasBall = false
                    end
                end
            end))

            InfStamina:Clean(ball.ChildRemoved:Connect(function(child)
                if child.Name == "playerWeld" then
                    hasBall = false
                end
            end))
        end

        checkBall()

        InfStamina:Clean(workspace.ChildAdded:Connect(function(child)
            if child.Name:lower() == 'ball' and child:IsA('BasePart') then
                task.wait(0.1)
                checkBall()
            end
        end))
    end

    local function setupCharacter(char)
        cachedHum = char:WaitForChild("Humanoid", 5)
        cachedRoot = char:WaitForChild("HumanoidRootPart", 5)
        gameForceActive = false

        if not cachedRoot then return end

        for _, c in cachedRoot:GetChildren() do
            if isGameForce(c) then
                gameForceActive = true
                break
            end
        end

        InfStamina:Clean(cachedRoot.ChildAdded:Connect(function(child)
            if isGameForce(child) then
                gameForceActive = true
                removeBodyVel()
            end
        end))

        InfStamina:Clean(cachedRoot.ChildRemoved:Connect(function(child)
            if isGameForce(child) then
                local stillActive = false
                for _, c in cachedRoot:GetChildren() do
                    if isGameForce(c) then
                        stillActive = true
                        break
                    end
                end
                gameForceActive = stillActive
            end
        end))
    end

    local function applyVelocity()
        if not entitylib.isAlive then
            removeBodyVel()
            return
        end

        if not sprintHeld then
            removeBodyVel()
            return
        end

        if not cachedHum or not cachedRoot or not cachedRoot.Parent then
            removeBodyVel()
            return
        end

        if gameForceActive then
            removeBodyVel()
            return
        end

        local moveDir = cachedHum.MoveDirection
        if moveDir.Magnitude < 0.1 then
            removeBodyVel()
            return
        end

        local bv = ensureBodyVel(cachedRoot)
        local horizontalDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
        bv.Velocity = horizontalDir * getCurrentTarget()
    end

    InfStamina = vape.Categories.realista:CreateModule({
        Name = 'InfStamina',
        Function = function(callback)
            if callback then
                currentMode = ModeDropdown.Value
                hasBall = false

                if lplr.Character then
                    setupCharacter(lplr.Character)
                end

                setupBallWatcher()

                InfStamina:Clean(lplr.CharacterAdded:Connect(function(char)
                    removeBodyVel()
                    gameForceActive = false
                    hasBall = false
                    task.wait(0.5)
                    setupCharacter(char)
                    setupBallWatcher()
                end))

                InfStamina:Clean(inputService.InputBegan:Connect(function(input, gpe)
                    if gpe then return end
                    if input.KeyCode == sprintKey then
                        sprintHeld = true
                    end
                end))

                InfStamina:Clean(inputService.InputEnded:Connect(function(input)
                    if input.KeyCode == sprintKey then
                        sprintHeld = false
                    end
                end))

                InfStamina:Clean(runService.Heartbeat:Connect(applyVelocity))
            else
                removeBodyVel()
                gameForceActive = false
                sprintHeld = false
                hasBall = false
            end
        end,
        Tooltip = 'InfStamina inteligente. 4v4 = 33 | 7v7 = 37 (35.5 c/ bola)'
    })

    ModeDropdown = InfStamina:CreateDropdown({
        Name = 'Mode',
        List = {'4v4', '7v7'},
        Function = function(val)
            currentMode = val
        end,
        Tooltip = '4v4 = 33 | 7v7 = 37 (35.5 com bola)'
    })
end)

run(function()
    local AutoGoal
    local Power

    local ShootRemote = game:GetService('ReplicatedStorage').Remotes:FindFirstChild('ShootTheBaII')

    local TRAVE_ESQUERDA_FRENTE = Vector3.new(155.44, 4.76, -1.58)
    local TRAVE_DIREITA_FRENTE  = Vector3.new(156.43, 4.76, 23.46)
    local TRAVE_ESQUERDA_FUNDO  = Vector3.new(165.03, 3.72, -1.77)
    local TRAVE_DIREITA_FUNDO   = Vector3.new(165.03, 3.74, 23.34)

    local function findBall()
        for _, v in workspace:GetChildren() do
            if v.Name:lower() == 'ball' and v:IsA('BasePart') then
                return v
            end
        end
    end

    local function findGoalie()
        local goalCenter = (TRAVE_ESQUERDA_FRENTE + TRAVE_DIREITA_FRENTE) / 2
        local closestPlayer, closestDist = nil, math.huge
        
        for _, plr in game.Players:GetPlayers() do
            if plr ~= lplr and plr.Character and plr.Character:FindFirstChild('HumanoidRootPart') then
                if plr.Team ~= lplr.Team then
                    local pos = plr.Character.HumanoidRootPart.Position
                    local dist = (pos - goalCenter).Magnitude
                    
                    if dist < 15 and dist < closestDist then
                        closestPlayer = plr
                        closestDist = dist
                    end
                end
            end
        end
        
        return closestPlayer
    end

    AutoGoal = vape.Categories.farmRSS:CreateModule({
        Name = 'AutoGoal',
        Function = function(callback)
            if callback then
                if not entitylib.isAlive then
                    AutoGoal:Toggle()
                    return
                end

                if not ShootRemote then
                    AutoGoal:Toggle()
                    return
                end

                local root = entitylib.character.RootPart

                local ball = findBall()
                if not ball then
                    AutoGoal:Toggle()
                    return
                end

                root.CFrame = CFrame.new(ball.Position)
                task.wait(0.3)

                local goalie = findGoalie()
                local goalCenterZ = (TRAVE_ESQUERDA_FRENTE.Z + TRAVE_DIREITA_FRENTE.Z) / 2

                local shootSpot, targetCorner

                if goalie then
                    local gkZ = goalie.Character.HumanoidRootPart.Position.Z
                    
                    if gkZ > goalCenterZ then
                        shootSpot = TRAVE_ESQUERDA_FRENTE
                        targetCorner = TRAVE_ESQUERDA_FUNDO
                    else
                        shootSpot = TRAVE_DIREITA_FRENTE
                        targetCorner = TRAVE_DIREITA_FUNDO
                    end
                else
                    shootSpot = TRAVE_ESQUERDA_FRENTE
                    targetCorner = TRAVE_ESQUERDA_FUNDO
                end

                root = entitylib.character.RootPart
                root.CFrame = CFrame.lookAt(shootSpot, targetCorner)
                task.wait(0.3)

                root = entitylib.character.RootPart
                local lookDir = (targetCorner - root.Position).Unit
                local cameraDir = lookDir

                ShootRemote:FireServer(
                    lookDir,
                    root.CFrame,
                    Power.Value,
                    cameraDir,
                    false,
                    false,
                    'None'
                )

                AutoGoal:Toggle()
            end
        end,
        Tooltip = 'IA: TP na trave oposta ao GK e chuta reto pro fundo.'
    })

    Power = AutoGoal:CreateSlider({
        Name = 'Power',
        Min = 0.05,
        Max = 1,
        Default = 0.3,
        Decimal = 100
    })
end)

run(function()
    local AutoFarmer
    local MaxPlayers
    local MaxGoals
    local FarmTime
    local Power
    local Cooldown
    local AimDelay
    local StealDelay
    local PreStealDelay
    local GoalCheckDelay
    local PossessionCheckDelay
    local KickoffDelay

    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local CoreGui = game:GetService("CoreGui")
    local TeamChangeRemote = game:GetService('ReplicatedStorage').Remotes:FindFirstChild('TeamChange')
    local ShootRemote = game:GetService('ReplicatedStorage').Remotes:FindFirstChild('ShootTheBaII')

    local PERSIST_FILE = "autofarmer_active.txt"

    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141
    local FANS_TEAM_COLOR = 199

    local TRAVE_ESQUERDA_FRENTE = Vector3.new(155.44, 4.76, -1.58)
    local TRAVE_DIREITA_FRENTE  = Vector3.new(156.43, 4.76, 23.46)
    local TRAVE_ESQUERDA_FUNDO  = Vector3.new(165.03, 3.72, -1.77)
    local TRAVE_DIREITA_FUNDO   = Vector3.new(165.03, 3.74, 23.34)

    local BALL_MAX_HEIGHT = 8
    local BALL_MAX_SPEED = 50
    local SMART_RANGE = 15

    local stats = {
        goals = 0, attempts = 0, steals = 0,
        hops = 0, kicks = 0, fouls = 0,
        startTime = 0, sessionGoals = 0
    }

    local lastGoalTime = 0
    local lastEnemyScore = 0
    local kickoffMode = false
    local theirKickoff = false

    ----------------------------------------------------------------
    -- PERSISTÊNCIA
    ----------------------------------------------------------------

    local function setPersist(active)
        pcall(function()
            if active then
                writefile(PERSIST_FILE, "1")
            else
                if isfile(PERSIST_FILE) then
                    delfile(PERSIST_FILE)
                end
            end
        end)
    end

    local function isPersisted()
        local ok, result = pcall(function()
            return isfile(PERSIST_FILE) and readfile(PERSIST_FILE) == "1"
        end)
        return ok and result
    end

    ----------------------------------------------------------------
    -- HELPERS
    ----------------------------------------------------------------

    local function getMyScore()
        local scoreboard = lplr.PlayerGui:FindFirstChild('ScoreboardV2')
        if not scoreboard then return 0 end
        local awayScore = scoreboard:FindFirstChild('Top') and scoreboard.Top:FindFirstChild('AwayScore')
        if not awayScore then return 0 end
        return tonumber(awayScore.Text) or 0
    end

    local function getEnemyScore()
        local scoreboard = lplr.PlayerGui:FindFirstChild('ScoreboardV2')
        if not scoreboard then return 0 end
        local homeScore = scoreboard:FindFirstChild('Top') and scoreboard.Top:FindFirstChild('HomeScore')
        if not homeScore then return 0 end
        return tonumber(homeScore.Text) or 0
    end

    local function findBall()
        for _, v in workspace:GetChildren() do
            if v.Name:lower() == 'ball' and v:IsA('BasePart') then
                return v
            end
        end
    end

    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end
        local weld = ball:FindFirstChild("playerWeld")
        if not weld or not weld:IsA("Weld") then return nil end
        local rootPart = weld.Part0
        if not rootPart then return nil end
        local char = rootPart.Parent
        if not char then return nil end
        return game.Players:GetPlayerFromCharacter(char)
    end

    local function getHomeTeam()
        for _, t in game:GetService('Teams'):GetChildren() do
            if t.TeamColor.Number == HOME_TEAM_COLOR then
                return t
            end
        end
        return nil
    end

    local function amInHomeTeam()
        return lplr.TeamColor and lplr.TeamColor.Number == HOME_TEAM_COLOR
    end

    local function amInFans()
        return lplr.TeamColor and lplr.TeamColor.Number == FANS_TEAM_COLOR
    end

    local function findGoalie()
        local goalCenter = (TRAVE_ESQUERDA_FRENTE + TRAVE_DIREITA_FRENTE) / 2
        local closestGK, closestDist = nil, math.huge

        local botGK = workspace:FindFirstChild('HomeGoalie')
        if botGK and botGK:FindFirstChild('HumanoidRootPart') then
            local dist = (botGK.HumanoidRootPart.Position - goalCenter).Magnitude
            if dist < 15 then
                closestGK = botGK.HumanoidRootPart
                closestDist = dist
            end
        end

        for _, plr in game.Players:GetPlayers() do
            if plr ~= lplr and plr.Character and plr.Character:FindFirstChild('HumanoidRootPart') then
                if plr.Team ~= lplr.Team then
                    local pos = plr.Character.HumanoidRootPart.Position
                    local dist = (pos - goalCenter).Magnitude
                    if dist < 15 and dist < closestDist then
                        closestGK = plr.Character.HumanoidRootPart
                        closestDist = dist
                    end
                end
            end
        end

        return closestGK
    end

    local function getBallStatus(ball)
        local owner = getBallOwner()
        
        if owner == lplr then
            return 'mine', lplr
        elseif owner then
            if owner.Team == lplr.Team then
                return 'ally', owner
            else
                return 'enemy', owner
            end
        end

        return 'free', nil
    end

    local function formatTime(seconds)
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%dm%02ds", mins, secs)
    end

    local function printStats()
        local elapsed = tick() - stats.startTime
        print("===== SESSION REPORT =====")
        print("Tempo: " .. formatTime(elapsed))
        print("Gols: " .. stats.goals)
        print("Tentativas: " .. stats.attempts)
        print("Taxa: " .. (stats.attempts > 0 and math.floor((stats.goals / stats.attempts) * 100) .. "%" or "N/A"))
        print("Steals: " .. stats.steals)
        print("Faltas: " .. stats.fouls)
        print("Server Hops: " .. stats.hops)
        print("Kicks sofridos: " .. stats.kicks)
        print("==========================")
    end

    ----------------------------------------------------------------
    -- SERVER HOP
    ----------------------------------------------------------------

    local function getServers(maxP)
        local servers = {}
        local ok, response = pcall(function()
            return HttpService:JSONDecode(
                game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100")
            )
        end)

        if ok and response and response.data then
            for _, server in ipairs(response.data) do
                if server.id ~= game.JobId
                   and server.playing < server.maxPlayers
                   and server.playing <= (maxP or 999) then
                    table.insert(servers, server)
                end
            end
        end
        return servers
    end

    local function serverHop()
        stats.hops = stats.hops + 1
        printStats()
        notif('AutoFarmer', 'Hopping... (Hop #' .. stats.hops .. ')', 3)
        setPersist(true)

        local servers = getServers(MaxPlayers.Value)
        if #servers > 0 then
            local target = servers[1]
            notif('AutoFarmer', 'Server com ' .. target.playing .. ' players', 2)
            pcall(function()
                TeleportService:TeleportToPlaceInstance(
                    game.PlaceId, target.id, lplr, nil,
                    { autoFarmerActive = true }
                )
            end)
            return true
        end

        pcall(function()
            TeleportService:Teleport(game.PlaceId, lplr, { autoFarmerActive = true })
        end)
        return false
    end

    ----------------------------------------------------------------
    -- CHECKS DO SERVIDOR
    ----------------------------------------------------------------

    local function hasHighLevelPlayer()
        for _, plr in game.Players:GetPlayers() do
            if plr ~= lplr then
                local ls = plr:FindFirstChild("leaderstats")
                if ls and ls:FindFirstChild("Goals") then
                    if ls.Goals.Value >= MaxGoals.Value then
                        notif('AutoFarmer', plr.Name .. ': ' .. ls.Goals.Value .. ' gols!', 3, 'warning')
                        return true
                    end
                end
            end
        end
        return false
    end

    local function isHomeTeamFull()
        local count = 0
        for _, plr in game.Players:GetPlayers() do
            if plr.TeamColor and plr.TeamColor.Number == HOME_TEAM_COLOR then
                count = count + 1
            end
        end
        return count >= 5
    end

    local function isServerTooFull()
        return #game.Players:GetPlayers() > MaxPlayers.Value
    end


    ----------------------------------------------------------------
    -- ANTI-KICK
    ----------------------------------------------------------------

    local function startKickDetector()
        return task.spawn(function()
            while AutoFarmer.Enabled do
                task.wait(0.5)
                local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
                if promptGui then
                    local overlay = promptGui:FindFirstChild("promptOverlay")
                    if overlay and #overlay:GetChildren() > 0 then
                        stats.kicks = stats.kicks + 1
                        notif('AutoFarmer', 'KICK #' .. stats.kicks .. '! Hopping...', 3)
                        task.wait(0.5)
                        serverHop()
                        return
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- ✅ TEAM ENFORCER (checa a cada 5s se tô no time certo)
    ----------------------------------------------------------------

    local function startTeamEnforcer()
        return task.spawn(function()
            while AutoFarmer.Enabled do
                task.wait(5)
                
                -- Se tô no Fans, força entrar no HOME
                if amInFans() then
                    notif('AutoFarmer', '⚠️ Em FANS, entrando HOME...', 2)
                    local homeTeam = getHomeTeam()
                    if TeamChangeRemote and homeTeam then
                        TeamChangeRemote:FireServer(homeTeam.TeamColor, 'Player')
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- DETECTOR DE KICKOFF VIA BOOLS
    ----------------------------------------------------------------

    local function startKickoffDetector()
        local boolsFolder = workspace:FindFirstChild("Bools")
        if not boolsFolder then return end

        local homeCele = boolsFolder:FindFirstChild("homeCele")
        local awayCele = boolsFolder:FindFirstChild("awayCele")
        local timePause = boolsFolder:FindFirstChild("timePause")

        if awayCele then
            AutoFarmer:Clean(awayCele.Changed:Connect(function(newVal)
                if newVal == true and AutoFarmer.Enabled then
                    notif('AutoFarmer', 'Nosso gol! Respeitando cooldown ⏱️', 3)
                    theirKickoff = false
                    kickoffMode = false
                    lastGoalTime = tick()
                end
            end))
        end

        if homeCele then
            AutoFarmer:Clean(homeCele.Changed:Connect(function(newVal)
                if newVal == true and AutoFarmer.Enabled then
                    notif('AutoFarmer', 'Tomamos gol! Kickoff inimigo 😤', 3)
                    theirKickoff = true
                    kickoffMode = false
                    lastEnemyScore = getEnemyScore()
                end
            end))
        end

        if timePause then
            AutoFarmer:Clean(timePause.Changed:Connect(function(newVal)
                if newVal == false and AutoFarmer.Enabled then
                    if theirKickoff then
                        notif('AutoFarmer', 'Kickoff deles acabou!', 2)
                        theirKickoff = false
                    end
                end
            end))
        end
    end

    ----------------------------------------------------------------
    -- PARTE 1: CONSEGUIR A BOLA
    ----------------------------------------------------------------

    local function tryGrabBall(ball)
        if not entitylib.isAlive then return false end
        entitylib.character.RootPart.CFrame = CFrame.new(ball.Position)
        task.wait(PossessionCheckDelay.Value)
        local newBall = findBall()
        if not newBall then return false end
        return getBallStatus(newBall) == 'mine'
    end

    local function tryStealBall(target)
        if not entitylib.isAlive or not target or not target.Character then return false end

        local ownerPos = target.Character.HumanoidRootPart.Position
        local root = entitylib.character.RootPart
        local ball = findBall()
        if not ball then return false end

        local ballPos = ball.Position
        local lookAtPos = Vector3.new(ballPos.X, ownerPos.Y, ballPos.Z)
        root.CFrame = CFrame.lookAt(ownerPos, lookAtPos)

        local aimConnection
        aimConnection = runService.Heartbeat:Connect(function()
            if not entitylib.isAlive then return end
            local currentBall = findBall()
            if not currentBall then return end
            local myRoot = entitylib.character.RootPart
            local bPos = currentBall.Position
            local targetPos = Vector3.new(bPos.X, myRoot.Position.Y, bPos.Z)
            myRoot.CFrame = CFrame.lookAt(myRoot.Position, targetPos)
        end)

        task.wait(AimDelay.Value)
        if aimConnection then aimConnection:Disconnect() end

        local VirtualInputManager = game:GetService('VirtualInputManager')
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)

        task.wait(PossessionCheckDelay.Value)

        local newBall = findBall()
        if not newBall then return false end
        local status = getBallStatus(newBall)

        if status == 'mine' then
            stats.steals = stats.steals + 1
            return true
        else
            stats.fouls = stats.fouls + 1
            return false
        end
    end

    local function tryGetBall()
        local ball = findBall()
        if not ball then return false, 'no_ball' end

        local status, target = getBallStatus(ball)

        if status == 'mine' then
            return true, 'already_mine'

        elseif status == 'ally' then
            if kickoffMode then
                local success = tryGrabBall(ball)
                if success then
                    kickoffMode = false
                    return true, 'kickoff_grab'
                end
                return false, 'kickoff_grab_failed'
            end
            return false, 'ally_has_it'

        elseif status == 'enemy' then
            task.wait(PreStealDelay.Value)
            ball = findBall()
            if not ball then return false, 'no_ball' end
            local newStatus, newTarget = getBallStatus(ball)
            if newStatus ~= 'enemy' then return false, 'status_changed' end

            local success = tryStealBall(newTarget)
            if success then
                return true, 'stole_from_enemy'
            else
                return false, 'tackle_failed_or_foul'
            end

        elseif status == 'free' then
            local success = tryGrabBall(ball)
            if success then
                return true, 'grabbed_free'
            end
            return false, 'grab_failed'
        end

        return false, 'unknown'
    end

    ----------------------------------------------------------------
    -- PARTE 2: FAZER O GOL
    ----------------------------------------------------------------

    local function doShoot()
        if not entitylib.isAlive or not ShootRemote then return false end

        stats.attempts = stats.attempts + 1

        local root = entitylib.character.RootPart
        local goalieRoot = findGoalie()
        local goalCenterZ = (TRAVE_ESQUERDA_FRENTE.Z + TRAVE_DIREITA_FRENTE.Z) / 2

        local shootSpot, targetCorner, lado

        if goalieRoot then
            local gkZ = goalieRoot.Position.Z
            if gkZ > goalCenterZ then
                shootSpot = TRAVE_ESQUERDA_FRENTE
                targetCorner = TRAVE_ESQUERDA_FUNDO
                lado = 'ESQ'
            else
                shootSpot = TRAVE_DIREITA_FRENTE
                targetCorner = TRAVE_DIREITA_FUNDO
                lado = 'DIR'
            end
        else
            shootSpot = TRAVE_ESQUERDA_FRENTE
            targetCorner = TRAVE_ESQUERDA_FUNDO
            lado = 'ESQ (sem GK)'
        end

        root.CFrame = CFrame.lookAt(shootSpot, targetCorner)
        task.wait(0.3)

        if not entitylib.isAlive then return false end

        root = entitylib.character.RootPart
        local lookDir = (targetCorner - root.Position).Unit

        local scoreBefore = getMyScore()

        ShootRemote:FireServer(
            lookDir,
            root.CFrame,
            Power.Value,
            lookDir,
            false,
            false,
            'None'
        )

        notif('AutoFarmer', 'Chute ' .. lado .. ' (#' .. stats.attempts .. ')', 2)

        task.wait(GoalCheckDelay.Value)

        local scoreAfter = getMyScore()

        if scoreAfter > scoreBefore then
            stats.goals = stats.goals + 1
            stats.sessionGoals = stats.sessionGoals + 1
            lastGoalTime = tick()
            local elapsed = tick() - stats.startTime
            notif('AutoFarmer', 'GOL #' .. stats.goals .. '! ⚽ | Tempo: ' .. formatTime(elapsed), 4)
            return true
        else
            notif('AutoFarmer', 'Errou! Tentativa #' .. stats.attempts, 2)
            return false
        end
    end

    ----------------------------------------------------------------
    -- LOOP PRINCIPAL DO FARM
    ----------------------------------------------------------------

    local function farmLoop()
        while AutoFarmer.Enabled do
            -- ✅ Se tô em Fans, espera (o TeamEnforcer cuida de entrar no time)
            if amInFans() then
                task.wait(1)
                continue
            end

            if not amInHomeTeam() then
                task.wait(1)
                continue
            end

            if not entitylib.isAlive then
                task.wait(1)
                continue
            end

            if theirKickoff then
                task.wait(0.5)
                continue
            end

            local timeSinceLastGoal = tick() - lastGoalTime
            if timeSinceLastGoal < Cooldown.Value and not kickoffMode then
                local ball = findBall()
                if ball then
                    local status = getBallStatus(ball)
                    if status ~= 'enemy' then
                        task.wait(0.3)
                        continue
                    end
                else
                    task.wait(0.3)
                    continue
                end
            end

            local gotBall, reason = tryGetBall()

            if not gotBall then
                if reason == 'ally_has_it' then
                    task.wait(1)
                elseif reason == 'tackle_failed_or_foul' then
                    notif('AutoFarmer', 'Tackle falhou (falta?)', 2)
                    task.wait(1)
                elseif reason == 'grab_failed' or reason == 'kickoff_grab_failed' then
                    task.wait(0.3)
                else
                    task.wait(0.5)
                end
                continue
            end

            if reason == 'kickoff_grab' then
                notif('AutoFarmer', 'Kickoff! ⚽', 2)
                task.wait(0.2)
            else
                if reason == 'stole_from_enemy' then
                    notif('AutoFarmer', 'Roubou! (Steal #' .. stats.steals .. ')', 2)
                end
                task.wait(StealDelay.Value)
            end

            local ball = findBall()
            if ball then
                local status = getBallStatus(ball)
                if status == 'mine' then
                    local success = doShoot()

                    while not success and AutoFarmer.Enabled do
                        task.wait(0.5)
                        if not entitylib.isAlive then break end
                        ball = findBall()
                        if not ball then break end
                        local retryStatus = getBallStatus(ball)
                        if retryStatus ~= 'mine' and retryStatus ~= 'free' then break end
                        if retryStatus == 'free' then
                            tryGrabBall(ball)
                            task.wait(0.2)
                        end
                        success = doShoot()
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- MÓDULO PRINCIPAL
    ----------------------------------------------------------------

    AutoFarmer = vape.Categories.farmRSS:CreateModule({
        Name = 'AutoFarmer',
        Function = function(callback)
            if callback then
                stats = {
                    goals = 0, attempts = 0, steals = 0,
                    hops = 0, kicks = 0, fouls = 0,
                    startTime = tick(), sessionGoals = 0
                }
                lastGoalTime = 0
                lastEnemyScore = getEnemyScore()
                kickoffMode = false
                theirKickoff = false

                setPersist(true)

                startKickDetector()
                startKickoffDetector()
                startTeamEnforcer()  -- ✅ NOVO

                AutoFarmer:Clean(task.spawn(function()
                    task.wait(3)

                    while AutoFarmer.Enabled do
                        if isServerTooFull() then
                            notif('AutoFarmer', 'Server tem ' .. #game.Players:GetPlayers() .. ' players (max: ' .. MaxPlayers.Value .. '). Hopping!', 3)
                            task.wait(2)
                            serverHop()
                            return
                        end

                        if hasHighLevelPlayer() then
                            notif('AutoFarmer', 'Player VIP! Hopping...', 3)
                            task.wait(2)
                            serverHop()
                            return
                        end

                        if isHomeTeamFull() then
                            notif('AutoFarmer', 'HOME cheio! Hopping...', 3)
                            task.wait(2)
                            serverHop()
                            return
                        end

                        notif('AutoFarmer', 'Farmando por ' .. FarmTime.Value .. 'min', 4)

                        local farmEnd = tick() + (FarmTime.Value * 60)

                        task.spawn(function()
                            farmLoop()
                        end)

                        while AutoFarmer.Enabled and tick() < farmEnd do
                            task.wait(2)

                            if isServerTooFull() then
                                notif('AutoFarmer', 'Server lotado!', 2)
                                break
                            end

                            if hasHighLevelPlayer() then
                                notif('AutoFarmer', 'Player VIP entrou!', 2)
                                break
                            end
                        end

                        if not AutoFarmer.Enabled then return end

                        printStats()
                        notif('AutoFarmer', 'Session: ' .. stats.sessionGoals .. ' gols em ' .. formatTime(tick() - stats.startTime), 5)

                        task.wait(2)
                        serverHop()
                        return
                    end
                end))
            else
                setPersist(false)
                theirKickoff = false
                printStats()
                notif('AutoFarmer', 'Desativado! Total: ' .. stats.goals .. ' gols', 3)
            end
        end,
        Tooltip = 'Auto farm 24/7: team enforcer a cada 5s, anti-kick, server hop.'
    })

    MaxPlayers = AutoFarmer:CreateSlider({
        Name = 'Max Players',
        Min = 1, Max = 10, Default = 3
    })

    MaxGoals = AutoFarmer:CreateSlider({
        Name = 'Max Goals Limit',
        Min = 100, Max = 5000, Default = 1000
    })

    FarmTime = AutoFarmer:CreateSlider({
        Name = 'Farm Time',
        Min = 1, Max = 60, Default = 15,
        Suffix = function(val)
            return val == 1 and 'minute' or 'minutes'
        end
    })

    Power = AutoFarmer:CreateSlider({
        Name = 'Shoot Power',
        Min = 0.05, Max = 1, Default = 0.3,
        Decimal = 100
    })

    PreStealDelay = AutoFarmer:CreateSlider({
        Name = 'React Delay',
        Min = 0, Max = 2, Default = 0.2,
        Decimal = 100,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    AimDelay = AutoFarmer:CreateSlider({
        Name = 'Steal Aim',
        Min = 0, Max = 1, Default = 0.15,
        Decimal = 100,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    PossessionCheckDelay = AutoFarmer:CreateSlider({
        Name = 'Possession Check',
        Min = 0.1, Max = 1, Default = 0.3,
        Decimal = 100,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    StealDelay = AutoFarmer:CreateSlider({
        Name = 'Pre-Shoot Delay',
        Min = 0, Max = 2, Default = 0.4,
        Decimal = 100,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    GoalCheckDelay = AutoFarmer:CreateSlider({
        Name = 'Goal Check',
        Min = 0.5, Max = 5, Default = 1.5,
        Decimal = 100,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    KickoffDelay = AutoFarmer:CreateSlider({
        Name = 'Kickoff Wait',
        Min = 1, Max = 20, Default = 10,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    Cooldown = AutoFarmer:CreateSlider({
        Name = 'Cooldown',
        Min = 1, Max = 30, Default = 10,
        Suffix = function(val)
            return val == 1 and 'second' or 'seconds'
        end
    })

    task.spawn(function()
        task.wait(5)
        local teleportData = TeleportService:GetLocalPlayerTeleportData()
        local wasTeleported = teleportData and teleportData.autoFarmerActive

        if wasTeleported then
            task.wait(3)
            if not AutoFarmer.Enabled then
                AutoFarmer:Toggle()
                notif('AutoFarmer', 'Auto-resumido!', 3)
            end
        else
            setPersist(false)
        end
    end)
end)

run(function()
    local AutoTackle
    local Mode
    local TargetMode
    local DetectRange
    local GameMode
    local ScanRate
    local MaxAngle

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local Debris = game:GetService('Debris')

    local DRIBBLE_COOLDOWN = 4.2
    local DRIBBLE_VULNERABLE_MIN = 0.5
    local DRIBBLE_VULNERABLE_MAX = DRIBBLE_COOLDOWN - 1
    local GRAB_VULNERABLE_WINDOW = 0.3
    local SMART_CLOSE_RANGE = 5
    local TACKLE_POST_DELAY = 0.1
    local TACKLE_FORCE_DURATION = 0.65

    local TACKLE_SPEEDS = {
        ['4v4'] = 40,
        ['7v7'] = 50,
    }

    local DRIBBLE_ANIM_IDS = {
        '14328586766', '14893581487', '14899049391', '14908212300',
        '15154280353', '16331006011', '17590081108', '17590392784',
        '17743274227', '17748025748', '121059135011282', '140030983315202',
        '133996236884225', '127593117332707', '107226443405165',
    }

    local dribbleAnimSet = {}
    for _, id in DRIBBLE_ANIM_IDS do
        dribbleAnimSet[id] = true
    end

    local ActionRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('Action')
    local wsBools = workspace:WaitForChild('Bools')
    local penaltyBool = wsBools:FindFirstChild('Penalty')
    local kickoffBool = wsBools:FindFirstChild('Kickoff')

    local enemyLastDribbleTime = {}
    local enemyConnections = {}
    local isAttacking = false
    local cachedBall = nil
    local cachedWeld = nil
    local scanLoopActive = false

    local charCache = {
        tackleDebounce = nil,
        tackled = nil,
        debounce = nil,
        tackling = nil,
        header = nil,
    }

    local function rebuildCharCache()
        local char = lplr.Character
        if not char then return end

        local bools = char:FindFirstChild('Bools')
        if not bools then return end

        charCache.tackleDebounce = bools:FindFirstChild('TackleDebounce')
        charCache.tackled = bools:FindFirstChild('Tackled')
        charCache.debounce = bools:FindFirstChild('Debounce')
        charCache.tackling = bools:FindFirstChild('Tackling')
        charCache.header = bools:FindFirstChild('Header')
    end

    local function canTackle()
        if not entitylib.isAlive then return false end
        if charCache.tackleDebounce and charCache.tackleDebounce.Value then return false end
        if charCache.tackled and charCache.tackled.Value then return false end
        if charCache.debounce and charCache.debounce.Value then return false end
        if charCache.tackling and charCache.tackling.Value then return false end
        if charCache.header and charCache.header.Value then return false end
        if penaltyBool and penaltyBool.Value then return false end
        if kickoffBool and kickoffBool.Value then return false end
        return true
    end

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function getBallWeld()
        local ball = findBall()
        if not ball then return nil end

        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return nil
        end

        return cachedWeld
    end

    local function iHaveBall()
        local weld = getBallWeld()
        if not weld or not weld.Part0 then return false end
        return weld.Part0.Parent == lplr.Character
    end

    local function getBallOwner()
        local weld = getBallWeld()
        if not weld or not weld.Part0 then return nil end
        return Players:GetPlayerFromCharacter(weld.Part0.Parent)
    end

    local function isBallOwnedByTeammate()
        local owner = getBallOwner()
        if not owner then return false end
        if owner == lplr then return true end
        return owner.Team == lplr.Team
    end

    local function findEnemyWithBall()
        local owner = getBallOwner()
        if not owner or owner == lplr or owner.Team == lplr.Team then return nil end
        return owner
    end

    local function isEnemyVulnerable(enemy)
        if not enemy or not enemy.Character then return false end

        local bools = enemy.Character:FindFirstChild('Bools')
        if bools then
            local ps = bools:FindFirstChild('PowerShooting')
            if ps and ps.Value then return true end

            local grabTick = bools:FindFirstChild('GrabTick')
            if grabTick and grabTick.Value > 0 then
                if tick() - grabTick.Value < GRAB_VULNERABLE_WINDOW then
                    return true
                end
            end
        end

        local lastDribble = enemyLastDribbleTime[enemy]
        if lastDribble then
            local timeSince = tick() - lastDribble
            if timeSince > DRIBBLE_VULNERABLE_MIN and timeSince < DRIBBLE_VULNERABLE_MAX then
                return true
            end
        end

        return false
    end

    local function getTackleSpeed()
        return TACKLE_SPEEDS[GameMode.Value] or 40
    end

    local function isTargetInFront(targetPos)
        local maxAngle = MaxAngle.Value
        if maxAngle >= 180 then return true end

        local myRoot = entitylib.character and entitylib.character.RootPart
        if not myRoot then return false end

        local myPos = myRoot.Position
        local lookVec = myRoot.CFrame.LookVector

        local toTarget = Vector3.new(
            targetPos.X - myPos.X,
            0,
            targetPos.Z - myPos.Z
        )

        if toTarget.Magnitude < 0.1 then return true end

        local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z)
        if flatLook.Magnitude < 0.01 then return true end

        local dot = flatLook.Unit:Dot(toTarget.Unit)
        dot = math.clamp(dot, -1, 1)

        local angleDeg = math.deg(math.acos(dot))
        return angleDeg <= maxAngle
    end

    local function aimAtPosition(targetPos, targetVel, dist)
        if not entitylib.isAlive then return end

        local myRoot = entitylib.character.RootPart
        if not myRoot or not targetPos then return end

        local timeToReach = dist / getTackleSpeed()
        targetVel = targetVel or Vector3.zero

        local predictedPos = targetPos + (targetVel * timeToReach)
        local lookAtPos = Vector3.new(predictedPos.X, myRoot.Position.Y, predictedPos.Z)
        myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookAtPos)
    end

    local function doTackle()
        if not entitylib.isAlive or not ActionRemote then return end

        local root = entitylib.character.RootPart
        if not root then return end

        ActionRemote:FireServer('TackIe')

        local bv = Instance.new('BodyVelocity')
        bv.Velocity = root.CFrame.LookVector * getTackleSpeed()
        bv.MaxForce = Vector3.new(50000000, 0, 50000000)
        bv.Parent = root
        Debris:AddItem(bv, TACKLE_FORCE_DURATION)

        local gyro = Instance.new('BodyGyro')
        gyro.Name = 'TackleGyro'
        gyro.P = 950000
        gyro.MaxTorque = Vector3.new(0, 100000, 0)
        gyro.CFrame = root.CFrame
        gyro.Parent = root
        Debris:AddItem(gyro, TACKLE_FORCE_DURATION)
    end

    local function getTargetInfo(targetType)
        if targetType == 'Ball' then
            if isBallOwnedByTeammate() then return nil end

            local ball = findBall()
            if not ball then return nil end
            return ball.Position, ball.AssemblyLinearVelocity
        end

        local enemy = findEnemyWithBall()
        if not enemy or not enemy.Character then return nil end

        local enemyRoot = enemy.Character:FindFirstChild('HumanoidRootPart')
        if not enemyRoot then return nil end

        return enemyRoot.Position, enemyRoot.AssemblyLinearVelocity
    end

    local function executeAttack(targetType)
        if isAttacking or not canTackle() or iHaveBall() then return end

        local targetPos, targetVel = getTargetInfo(targetType)
        if not targetPos then return end

        local myRoot = entitylib.character.RootPart
        if not myRoot then return end

        local dist = (targetPos - myRoot.Position).Magnitude
        if dist > DetectRange.Value then return end

        if not isTargetInFront(targetPos) then return end

        isAttacking = true

        task.spawn(function()
            aimAtPosition(targetPos, targetVel, dist)
            doTackle()

            task.wait(TACKLE_POST_DELAY)
            while charCache.tackling and charCache.tackling.Value do
                task.wait()
            end

            isAttacking = false
        end)
    end

    local function shouldAttackByMode(modeName)
        if TargetMode.Value == 'Ball' and isBallOwnedByTeammate() then
            return false
        end

        local enemy = findEnemyWithBall()

        if modeName == 'Eagle Eye' then
            if TargetMode.Value == 'Ball' then
                return findBall() ~= nil
            end
            return enemy ~= nil
        end

        if modeName == 'Only Dribble' then
            return enemy ~= nil and isEnemyVulnerable(enemy)
        end

        if modeName == 'Smart' then
            if enemy and isEnemyVulnerable(enemy) then return true end

            local myRoot = entitylib.character and entitylib.character.RootPart
            if not myRoot then return false end

            if TargetMode.Value == 'Ball' then
                local ball = findBall()
                if not ball then return false end
                return (ball.Position - myRoot.Position).Magnitude < SMART_CLOSE_RANGE
            end

            if enemy and enemy.Character then
                local enemyRoot = enemy.Character:FindFirstChild('HumanoidRootPart')
                if enemyRoot then
                    return (enemyRoot.Position - myRoot.Position).Magnitude < SMART_CLOSE_RANGE
                end
            end
        end

        return false
    end

    local function runMode()
        if not entitylib.isAlive or isAttacking then return end
        if not shouldAttackByMode(Mode.Value) then return end
        executeAttack(TargetMode.Value)
    end

    local function manualTackleMode()
        if not canTackle() or iHaveBall() or not entitylib.isAlive then
            AutoTackle:Toggle()
            return
        end

        if TargetMode.Value == 'Ball' and isBallOwnedByTeammate() then
            AutoTackle:Toggle()
            return
        end

        local targetPos, targetVel = getTargetInfo(TargetMode.Value)
        if not targetPos then
            AutoTackle:Toggle()
            return
        end

        local myRoot = entitylib.character.RootPart
        if not myRoot then
            AutoTackle:Toggle()
            return
        end

        local dist = (targetPos - myRoot.Position).Magnitude
        if dist > DetectRange.Value then
            AutoTackle:Toggle()
            return
        end

        if not isTargetInFront(targetPos) then
            AutoTackle:Toggle()
            return
        end

        aimAtPosition(targetPos, targetVel, dist)
        doTackle()
        AutoTackle:Toggle()
    end

    local function watchPlayerDribbles(plr)
        if plr == lplr then return end

        local function setupChar(char)
            local hum = char:WaitForChild('Humanoid', 5)
            if not hum then return end

            if enemyConnections[plr] then
                enemyConnections[plr]:Disconnect()
            end

            enemyConnections[plr] = hum.AnimationPlayed:Connect(function(track)
                if not AutoTackle.Enabled then return end

                local anim = track.Animation
                if not anim then return end

                local animId = anim.AnimationId
                if not animId then return end

                for id in pairs(dribbleAnimSet) do
                    if animId:find(id) then
                        enemyLastDribbleTime[plr] = tick()
                        return
                    end
                end
            end)
        end

        if plr.Character then
            task.spawn(setupChar, plr.Character)
        end
        plr.CharacterAdded:Connect(setupChar)
    end

    local function startScanLoop()
        scanLoopActive = true
        task.spawn(function()
            while scanLoopActive and AutoTackle.Enabled do
                task.wait(1 / ScanRate.Value)
                if not scanLoopActive or not AutoTackle.Enabled then break end
                runMode()
            end
        end)
    end

    AutoTackle = vape.Categories.realista:CreateModule({
        Name = 'AutoTackle',
        Function = function(callback)
            if callback then
                if not ActionRemote then
                    AutoTackle:Toggle()
                    return
                end

                isAttacking = false
                enemyLastDribbleTime = {}
                enemyConnections = {}
                cachedBall = nil
                cachedWeld = nil

                rebuildCharCache()

                AutoTackle:Clean(lplr.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    rebuildCharCache()
                    cachedBall = nil
                    cachedWeld = nil
                end))

                if Mode.Value == 'Manual Tackle' then
                    manualTackleMode()
                    return
                end

                for _, plr in Players:GetPlayers() do
                    watchPlayerDribbles(plr)
                end

                AutoTackle:Clean(Players.PlayerAdded:Connect(watchPlayerDribbles))

                AutoTackle:Clean(Players.PlayerRemoving:Connect(function(plr)
                    if enemyConnections[plr] then
                        enemyConnections[plr]:Disconnect()
                        enemyConnections[plr] = nil
                    end
                    enemyLastDribbleTime[plr] = nil
                end))

                startScanLoop()
            else
                scanLoopActive = false
                isAttacking = false
                cachedBall = nil
                cachedWeld = nil

                for _, conn in pairs(enemyConnections) do
                    conn:Disconnect()
                end
                enemyConnections = {}
                enemyLastDribbleTime = {}
            end
        end,
        Tooltip = 'Auto tackle com target na bola ou no jogador.'
    })

    Mode = AutoTackle:CreateDropdown({
        Name = 'Mode',
        List = {'Eagle Eye', 'Only Dribble', 'Smart', 'Manual Tackle'},
        Default = 'Smart',
        Tooltip = 'Eagle Eye: sempre | Only Dribble: so vulneravel | Smart: combina | Manual: uma vez'
    })

    TargetMode = AutoTackle:CreateDropdown({
        Name = 'Target',
        List = {'Ball', 'PlayerWeld'},
        Default = 'PlayerWeld',
        Tooltip = 'Ball: mira na bola | PlayerWeld: mira no jogador'
    })

    GameMode = AutoTackle:CreateDropdown({
        Name = 'Game Mode',
        List = {'4v4', '7v7'},
        Default = '4v4',
        Tooltip = '4v4 = 40 studs/s | 7v7 = 50 studs/s'
    })

    DetectRange = AutoTackle:CreateSlider({
        Name = 'Detect Range',
        Min = 3, Max = 30, Default = 15,
        Suffix = function(val) return val == 1 and ' stud' or ' studs' end
    })

    MaxAngle = AutoTackle:CreateSlider({
        Name = 'Max Angle',
        Min = 30, Max = 180, Default = 120,
        Suffix = function(val) return '°' end,
        Tooltip = 'Angulo maximo entre teu LookVector e o alvo. 45=so frente | 120=natural | 180=desligado'
    })

    ScanRate = AutoTackle:CreateSlider({
        Name = 'Scan Rate',
        Min = 30, Max = 500, Default = 200,
        Suffix = function(val) return ' scans/s' end,
        Tooltip = 'Tentativas por segundo. Independe do FPS.'
    })
end)

run(function()
    local AerialReach
    local ServerMode
    local Range
    local Delay
    local MinHeight
    local Timeout

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local UserInputService = game:GetService('UserInputService')
    local runService = game:GetService('RunService')

    local lplr = Players.LocalPlayer

    _G.__AerialReachActive = false
    _G.__LastAerialReachTime = 0

    -- Presets oficiais por modo
    local MODE = {
        ['4v4'] = { dipY = 0.12, minHeightFloor = 2.0 },  -- caimento -0.12 Y
        ['7v7'] = { dipY = 0.00, minHeightFloor = 2.0 },  -- vetor direto
    }

    local PickupRemote = nil
    for _, v in ipairs(ReplicatedStorage:WaitForChild('Remotes'):GetChildren()) do
        if v:IsA('RemoteEvent') and v:GetAttribute('Attribute') then
            PickupRemote = v
            break
        end
    end

    local ShootRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('ShootTheBaII')

    local function getMode()
        local key = ServerMode and ServerMode.Value or '4v4'
        return MODE[key] or MODE['4v4']
    end

    local function playHeaderAnimation(char)
        if not char then return end
        local hum = char:FindFirstChildOfClass('Humanoid')
        if not hum then return end

        local animsFolder = ReplicatedStorage:FindFirstChild('Animations')
        if not animsFolder then return end

        local animObj = animsFolder:FindFirstChild('HeaderV2') or animsFolder:FindFirstChild('Header')
        if not animObj then return end

        local animator = hum:FindFirstChildOfClass('Animator') or hum
        local track = animator:LoadAnimation(animObj)
        track.Priority = Enum.AnimationPriority.Action4
        track:Play()
        track:AdjustSpeed(1.3)
    end

    local function findBall()
        for _, v in ipairs(workspace:GetChildren()) do
            if v.Name:lower() == 'ball' and v:IsA('BasePart') then
                return v
            end
        end
    end

    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end
        local weld = ball:FindFirstChild('playerWeld')
        if not weld or not weld:IsA('Weld') then return nil end
        local rootPart = weld.Part0
        if not rootPart then return nil end
        return Players:GetPlayerFromCharacter(rootPart.Parent)
    end

    local function flatUnit(v)
        if typeof(v) ~= 'Vector3' then return nil end
        local f = Vector3.new(v.X, 0, v.Z)
        if f.Magnitude < 0.05 then return nil end
        return f.Unit
    end

    AerialReach = vape.Categories.realista:CreateModule({
        Name = 'AerialReach',
        Function = function(callback)
            if callback then
                if not PickupRemote or not ShootRemote then
                    AerialReach:Toggle()
                    return
                end

                local wantAerialUntil = 0
                local lastShot = 0

                AerialReach:Clean(UserInputService.InputBegan:Connect(function(input)
                    if UserInputService:GetFocusedTextBox() then return end

                    if input.KeyCode == Enum.KeyCode.Space
                    or input.KeyCode == Enum.KeyCode.ButtonA
                    or input.KeyCode == Enum.KeyCode.ButtonL2 then
                        wantAerialUntil = tick() + Timeout.Value
                    end
                end))

                local function bindCharacter(char)
                    if not char then return end
                    local hum = char:WaitForChild('Humanoid', 5)
                    if not hum then return end

                    AerialReach:Clean(hum.Jumping:Connect(function()
                        wantAerialUntil = tick() + Timeout.Value
                    end))
                end

                if lplr.Character then bindCharacter(lplr.Character) end
                AerialReach:Clean(lplr.CharacterAdded:Connect(bindCharacter))

                AerialReach:Clean(runService.Heartbeat:Connect(function()
                    local char = lplr.Character
                    if not char then return end

                    local hum = char:FindFirstChildOfClass('Humanoid')
                    if not hum or hum.Health <= 0 then return end

                    if tick() > wantAerialUntil then return end
                    if tick() - lastShot < 1.0 then return end

                    local ball = findBall()
                    if not ball then return end
                    if getBallOwner() then return end

                    local root = char:FindFirstChild('HumanoidRootPart')
                    local head = char:FindFirstChild('Head')
                    if not root or not head then return end

                    local cfg = getMode()
                    local minH = math.max(MinHeight.Value, cfg.minHeightFloor or 0)

                    local heightAboveMe = ball.Position.Y - root.Position.Y
                    if heightAboveMe < minH then return end

                    local dist = (root.Position - ball.Position).Magnitude
                    if dist > Range.Value then return end

                    wantAerialUntil = 0
                    lastShot = tick()
                    _G.__AerialReachActive = true
                    _G.__LastAerialReachTime = tick()

                    task.spawn(function()
                        task.wait(1.2)
                        if tick() - (_G.__LastAerialReachTime or 0) >= 1.15 then
                            _G.__AerialReachActive = false
                        end
                    end)

                    if Delay.Value > 0 then
                        task.wait(Delay.Value)
                    end

                    playHeaderAnimation(char)
                    PickupRemote:FireServer(dist)

                    task.wait(0.02)

                    local lookDir = flatUnit(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
                    local isMobile = lplr:FindFirstChild('deviceType') and lplr.deviceType.Value == 'Mobile'

                    -- 4v4: -0.12 Y fixo | 7v7: 0
                    local shootVector = (lookDir * 0.7) - Vector3.new(0, cfg.dipY, 0)
                    local ballHeadCFrame = CFrame.new(ball.Position.X, head.Position.Y, ball.Position.Z)

                    ShootRemote:FireServer(
                        shootVector,
                        ballHeadCFrame,
                        1,
                        lookDir * 2000,
                        false,
                        isMobile or false
                    )
                end))
            else
                _G.__AerialReachActive = false
            end
        end,
        Tooltip = 'Reach aéreo. 4v4: caimento -0.12 Y oficial | 7v7: vetor direto.'
    })

    ServerMode = AerialReach:CreateDropdown({
        Name = 'Server Mode',
        List = { '4v4', '7v7' },
        Default = '4v4',
        Tooltip = '4v4 = dip -0.12 Y | 7v7 = sem dip'
    })

    Range = AerialReach:CreateSlider({
        Name = 'Range',
        Min = 5, Max = 50, Default = 15,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    Delay = AerialReach:CreateSlider({
        Name = 'Delay',
        Min = 0, Max = 2, Default = 0.1, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    MinHeight = AerialReach:CreateSlider({
        Name = 'Min Height Above Me',
        Min = 1.0, Max = 10.0, Default = 2.0, Decimal = 10,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    Timeout = AerialReach:CreateSlider({
        Name = 'Timeout',
        Min = 0.5, Max = 5, Default = 1.5, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })
end)

run(function()
    local AutoShoot
    local Power
    local MaxRange
    local Drag
    local DragFreeZone
    local UseCurve
    local PreferSpin
    local DerivationMult
    local DynamicShoot
    local CenterThreshold
    local TargetMode

    local Players = game:GetService('Players')
    local UserInputService = game:GetService('UserInputService')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')

    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141
    local MAX_GOALIE_DIST = 60
    local GRAVITY = workspace.Gravity
    local BALL_SPEED_PER_POWER = 70

    local ShootRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('ShootTheBaII')

    local Animations = ReplicatedStorage:WaitForChild('Animations')
    local shootAnimNormal = Animations:FindFirstChild('RShoot2') or Animations:FindFirstChild('RShoot')
    local shootAnimBackward = Animations:FindFirstChild('RShootBackward')

    local function findBall()
        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                return obj
            end
        end
        return nil
    end

    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end

        local weld = ball:FindFirstChild('playerWeld')
        if not weld or not weld:IsA('Weld') then return nil end

        local rootPart = weld.Part0
        if not rootPart then return nil end

        return Players:GetPlayerFromCharacter(rootPart.Parent)
    end

    local function haveBallPossession()
        return getBallOwner() == lplr
    end

    local function getTargetGoal()
        local myColor = lplr.TeamColor and lplr.TeamColor.Number

        if myColor == HOME_TEAM_COLOR then
            return workspace:FindFirstChild('HomeGoal')
        elseif myColor == AWAY_TEAM_COLOR then
            return workspace:FindFirstChild('AwayGoal')
        end

        return workspace:FindFirstChild('HomeGoal')
    end

    local function findGoalie(goalPos)
        local closestGK = nil
        local closestDist = math.huge
        local isBot = false

        local myColor = lplr.TeamColor and lplr.TeamColor.Number
        local enemyGoalieName = (myColor == HOME_TEAM_COLOR) and 'HomeGoalie' or 'Goalie'

        local bot = workspace:FindFirstChild(enemyGoalieName)
        if bot then
            local botRoot = bot:FindFirstChild('HumanoidRootPart')
            if botRoot then
                local dist = (botRoot.Position - goalPos).Magnitude
                if dist < MAX_GOALIE_DIST then
                    closestGK = botRoot
                    closestDist = dist
                    isBot = true
                end
            end
        end

        for _, plr in Players:GetPlayers() do
            if plr == lplr or plr.Team == lplr.Team then continue end
            if not plr.Character then continue end

            local root = plr.Character:FindFirstChild('HumanoidRootPart')
            if not root then continue end

            local dist = (root.Position - goalPos).Magnitude
            if dist < MAX_GOALIE_DIST and dist < closestDist then
                closestGK = root
                closestDist = dist
                isBot = false
            end
        end

        return closestGK, isBot
    end

    local function getGoalTargets(goal)
        local targets = goal:FindFirstChild('Targets')
        if not targets then return nil, nil, nil end

        return targets:FindFirstChild('TargetRight'),
               targets:FindFirstChild('TargetLeft'),
               targets:FindFirstChild('TargetCenter')
    end

    local function getGkSide(goal, goalie)
        if not goalie then return 'center' end

        local targetRight, targetLeft, targetCenter = getGoalTargets(goal)
        local goalCenterPos = targetCenter and targetCenter.Position
        if not goalCenterPos and targetRight and targetLeft then
            goalCenterPos = (targetRight.Position + targetLeft.Position) / 2
        end
        if not goalCenterPos then return 'center' end

        return goalie.Position.Z > goalCenterPos.Z and 'right' or 'left'
    end

    local function getBestTargetGoalie(goal)
        local targetRight, targetLeft, targetCenter = getGoalTargets(goal)

        if not targetRight or not targetLeft then
            return targetCenter, nil, false, targetCenter
        end

        local goalCenterPos = targetCenter and targetCenter.Position or
                              (targetRight.Position + targetLeft.Position) / 2

        local goalie, isBot = findGoalie(goalCenterPos)

        if not goalie then
            return targetRight, 'center', false, targetLeft
        end

        local gkSide = getGkSide(goal, goalie)

        local distRight = (targetRight.Position - goalie.Position).Magnitude
        local distLeft = (targetLeft.Position - goalie.Position).Magnitude

        if distRight > distLeft then
            return targetRight, gkSide, isBot, targetLeft
        end

        return targetLeft, gkSide, isBot, targetRight
    end

    local function getBestTargetMouse(goal)
        local targetRight, targetLeft, targetCenter = getGoalTargets(goal)
        local candidates = {}

        if targetRight then table.insert(candidates, targetRight) end
        if targetLeft then table.insert(candidates, targetLeft) end

        if #candidates == 0 and targetCenter then
            table.insert(candidates, targetCenter)
        end

        if #candidates == 0 then
            return nil, nil, false, nil
        end

        local cam = workspace.CurrentCamera
        if not cam then
            return getBestTargetGoalie(goal)
        end

        local mousePos = UserInputService:GetMouseLocation()
        local bestTarget = nil
        local bestDist = math.huge

        for _, target in ipairs(candidates) do
            local screen, onScreen = cam:WorldToViewportPoint(target.Position)
            if screen.Z > 0 then
                local dx = screen.X - mousePos.X
                local dy = screen.Y - mousePos.Y
                local d2 = dx * dx + dy * dy
                if d2 < bestDist then
                    bestDist = d2
                    bestTarget = target
                end
            end
        end

        if not bestTarget then
            bestTarget = targetRight or targetLeft or targetCenter
        end

        local goalCenterPos = targetCenter and targetCenter.Position
        if not goalCenterPos and targetRight and targetLeft then
            goalCenterPos = (targetRight.Position + targetLeft.Position) / 2
        end

        local goalie, isBot = goalCenterPos and findGoalie(goalCenterPos) or nil
        local gkSide = getGkSide(goal, goalie)
        local opposite = (bestTarget == targetRight) and (targetLeft or targetCenter) or (targetRight or targetCenter)

        return bestTarget, gkSide, isBot, opposite
    end

    local function getBestTarget(goal)
        local mode = TargetMode and TargetMode.Value or 'Goalie'
        if mode == 'Mouse' then
            return getBestTargetMouse(goal)
        end
        return getBestTargetGoalie(goal)
    end

    local function isGKCentered(goal, goalie)
        if not goalie then return false end

        local targetRight, targetLeft = getGoalTargets(goal)
        if not targetRight or not targetLeft then return false end

        local goalCenterZ = (targetRight.Position.Z + targetLeft.Position.Z) / 2
        local goalWidth = math.abs(targetRight.Position.Z - targetLeft.Position.Z)

        local gkOffsetFromCenter = math.abs(goalie.Position.Z - goalCenterZ)
        local centerZone = goalWidth * (CenterThreshold.Value / 100)

        return gkOffsetFromCenter <= centerZone
    end

    local function getCurveDirection(gkSide, isBot)
        if not UseCurve.Enabled then return 'None' end
        if not gkSide then return 'None' end
        if PreferSpin.Enabled and isBot then return 'None' end

        if gkSide == 'right' then return 'Left' end
        if gkSide == 'left' then return 'Right' end

        return 'None'
    end

    local function isBackwardShot(shootDir)
        local char = lplr.Character
        local root = char and char:FindFirstChild('HumanoidRootPart')
        if not root then return false end

        local localDir = root.CFrame:VectorToObjectSpace(shootDir)
        local deg = math.deg(math.atan2(localDir.X, -localDir.Z))

        return deg > 135 or deg < -135
    end

    local function playShootAnim(hum, shootDir)
        if not hum then return end

        local anim
        if isBackwardShot(shootDir) and shootAnimBackward then
            anim = shootAnimBackward
        else
            anim = shootAnimNormal
        end

        if not anim then return end

        local track = hum:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action4
        track:Play()
    end

    local function calculateHeightCompensation(distToGoal)
        if distToGoal <= DragFreeZone.Value then return 0 end

        local extraDist = distToGoal - DragFreeZone.Value
        local ballSpeed = Power.Value * BALL_SPEED_PER_POWER
        local timeToTarget = extraDist / ballSpeed

        return 0.5 * GRAVITY * timeToTarget * timeToTarget * Drag.Value
    end

    local function resolveCurveValue(goal, gkSide, isBot)
        if not DynamicShoot.Enabled then
            return getCurveDirection(gkSide, isBot)
        end

        local targetRight, targetLeft = getGoalTargets(goal)
        if not targetRight or not targetLeft then
            return getCurveDirection(gkSide, isBot)
        end

        local goalie = findGoalie((targetRight.Position + targetLeft.Position) / 2)

        if goalie and isGKCentered(goal, goalie) then
            return getCurveDirection(gkSide, isBot)
        end

        return 'None'
    end

    local function calculateAimTarget(target, oppositeTarget, heightCompensation)
        local heightOffset = Vector3.new(0, heightCompensation, 0)
        local basePos = target.Position + heightOffset

        if not oppositeTarget or DerivationMult.Value <= 0 then
            return basePos
        end

        local oppositePos = oppositeTarget.Position + heightOffset
        local factor = DerivationMult.Value / 10

        return basePos:Lerp(oppositePos, factor)
    end

    local function setCurveOnCharacter(char, curveValue)
        local bools = char:FindFirstChild('Bools')
        if not bools then return end

        local curve = bools:FindFirstChild('Curve')
        if curve then
            curve.Value = curveValue
        end
    end

    AutoShoot = vape.Categories.realista:CreateModule({
        Name = 'AutoShoot',
        Function = function(callback)
            if not callback then return end

            if not entitylib.isAlive or not ShootRemote or not haveBallPossession() then
                AutoShoot:Toggle()
                return
            end

            local char = lplr.Character
            local hum = char:FindFirstChild('Humanoid')

            local ball = char:FindFirstChild('ball') or findBall()
            if not ball then
                AutoShoot:Toggle()
                return
            end

            local goal = getTargetGoal()
            if not goal then
                AutoShoot:Toggle()
                return
            end

            local target, gkSide, isBot, oppositeTarget = getBestTarget(goal)
            if not target then
                AutoShoot:Toggle()
                return
            end

            local distToGoal = (ball.Position - target.Position).Magnitude
            if distToGoal > MaxRange.Value then
                AutoShoot:Toggle()
                return
            end

            local heightCompensation = calculateHeightCompensation(distToGoal)
            local curveValue = resolveCurveValue(goal, gkSide, isBot)
            local aimTarget = calculateAimTarget(target, oppositeTarget, heightCompensation)
            local shootDir = (aimTarget - ball.Position).Unit

            setCurveOnCharacter(char, curveValue)
            playShootAnim(hum, shootDir)

            ShootRemote:FireServer(
                shootDir,
                ball.CFrame,
                Power.Value,
                shootDir,
                false,
                false,
                curveValue,
                nil,
                false
            )

            AutoShoot:Toggle()
        end,
        Tooltip = 'AutoShoot com Target Mode (Goalie/Mouse) + DynamicShoot.'
    })

    TargetMode = AutoShoot:CreateDropdown({
        Name = 'Target Mode',
        List = { 'Goalie', 'Mouse' },
        Default = 'Goalie',
        Tooltip = 'Goalie = canto longe do GK | Mouse = canto mais perto do cursor (ignorando o meio)'
    })

    Power = AutoShoot:CreateSlider({
        Name = 'Power',
        Min = 0.1, Max = 1.6, Default = 1, Decimal = 100
    })

    DragFreeZone = AutoShoot:CreateSlider({
        Name = 'Drag Free Zone',
        Min = 10, Max = 150, Default = 80,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    Drag = AutoShoot:CreateSlider({
        Name = 'Drag Compensation',
        Min = 0, Max = 10, Default = 0.6, Decimal = 100
    })

    UseCurve = AutoShoot:CreateToggle({
        Name = 'Use Curve',
        Default = true
    })

    DynamicShoot = AutoShoot:CreateToggle({
        Name = 'Dynamic Shoot',
        Default = false,
        Function = function(callback)
            if CenterThreshold and CenterThreshold.Object then
                CenterThreshold.Object.Visible = callback
            end
        end,
        Tooltip = 'GK centro = curva | GK lado = reto'
    })

    PreferSpin = AutoShoot:CreateToggle({
        Name = 'Prefer Spin',
        Default = false
    })

    DerivationMult = AutoShoot:CreateSlider({
        Name = 'Derivation Mult',
        Min = 0, Max = 10, Default = 0, Decimal = 10
    })

    CenterThreshold = AutoShoot:CreateSlider({
        Name = 'Center Threshold',
        Min = 5, Max = 50, Default = 25,
        Visible = false,
        Suffix = function(val) return '%' end
    })

    MaxRange = AutoShoot:CreateSlider({
        Name = 'Max Range',
        Min = 10, Max = 200, Default = 200,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })
end)

run(function()
    local FarmPro
    local MaxPlayers
    local MaxGoals
    local FarmTime
    local Power
    local Cooldown
    local AimDelay
    local StealDelay
    local PreStealDelay
    local GoalCheckDelay
    local PossessionCheckDelay
    local SwapDelay

    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local CoreGui = game:GetService("CoreGui")
    local TeamChangeRemote = game:GetService('ReplicatedStorage').Remotes:FindFirstChild('TeamChange')
    local ShootRemote = game:GetService('ReplicatedStorage').Remotes:FindFirstChild('ShootTheBaII')

    local PERSIST_FILE = "farmpro_active.txt"

    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141
    local FANS_TEAM_COLOR = 199

    -- ✅ TRAVES DO HOMEGOL (ataco sendo HOME)
    local HOME_TRAVE_ESQ_FRENTE = Vector3.new(155.44, 4.76, -1.58)
    local HOME_TRAVE_DIR_FRENTE = Vector3.new(156.43, 4.76, 23.46)
    local HOME_TRAVE_ESQ_FUNDO  = Vector3.new(165.03, 3.72, -1.77)
    local HOME_TRAVE_DIR_FUNDO  = Vector3.new(165.03, 3.74, 23.34)

    -- ✅ TRAVES DO AWAYGOL (ataco sendo AWAY)
    local AWAY_TRAVE_ESQ_FRENTE = Vector3.new(-160.55, 4.76, -0.83)
    local AWAY_TRAVE_DIR_FRENTE = Vector3.new(-161.39, 4.76, 22.70)
    local AWAY_TRAVE_ESQ_FUNDO  = Vector3.new(-168.51, 4.76, -1.55)
    local AWAY_TRAVE_DIR_FUNDO  = Vector3.new(-168.76, 4.76, 24.16)

    local stats = {
        goals = 0, attempts = 0, steals = 0,
        hops = 0, kicks = 0, fouls = 0, swaps = 0,
        startTime = 0, sessionGoals = 0
    }

    local lastGoalTime = 0
    local lastEnemyScore = 0
    local kickoffMode = false
    local theirKickoff = false

    ----------------------------------------------------------------
    -- PERSISTÊNCIA
    ----------------------------------------------------------------

    local function setPersist(active)
        pcall(function()
            if active then writefile(PERSIST_FILE, "1")
            else if isfile(PERSIST_FILE) then delfile(PERSIST_FILE) end end
        end)
    end

    ----------------------------------------------------------------
    -- HELPERS DINÂMICOS
    ----------------------------------------------------------------

    local function getMyTeamColor()
        return lplr.TeamColor and lplr.TeamColor.Number
    end

    local function amInFans()
        return getMyTeamColor() == FANS_TEAM_COLOR
    end

    local function amInGame()
        local c = getMyTeamColor()
        return c == HOME_TEAM_COLOR or c == AWAY_TEAM_COLOR
    end

    local function amInHomeTeam()
        return getMyTeamColor() == HOME_TEAM_COLOR
    end

    local function shouldSwap()
        return #game.Players:GetPlayers() <= 2
    end

    -- ✅ Placar DINÂMICO
    local function getMyScore()
        local scoreboard = lplr.PlayerGui:FindFirstChild('ScoreboardV2')
        if not scoreboard then return 0 end
        local top = scoreboard:FindFirstChild('Top')
        if not top then return 0 end
        local myColor = getMyTeamColor()
        local scoreName = (myColor == HOME_TEAM_COLOR) and "AwayScore" or "HomeScore"
        local score = top:FindFirstChild(scoreName)
        return score and tonumber(score.Text) or 0
    end

    local function getEnemyScore()
        local scoreboard = lplr.PlayerGui:FindFirstChild('ScoreboardV2')
        if not scoreboard then return 0 end
        local top = scoreboard:FindFirstChild('Top')
        if not top then return 0 end
        local myColor = getMyTeamColor()
        local scoreName = (myColor == HOME_TEAM_COLOR) and "HomeScore" or "AwayScore"
        local score = top:FindFirstChild(scoreName)
        return score and tonumber(score.Text) or 0
    end

    local function findBall()
        for _, v in workspace:GetChildren() do
            if v.Name:lower() == 'ball' and v:IsA('BasePart') then return v end
        end
    end

    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end
        local weld = ball:FindFirstChild("playerWeld")
        if not weld or not weld:IsA("Weld") then return nil end
        local rootPart = weld.Part0
        if not rootPart then return nil end
        local char = rootPart.Parent
        if not char then return nil end
        return game.Players:GetPlayerFromCharacter(char)
    end

    local function getBallStatus(ball)
        local owner = getBallOwner()
        if owner == lplr then return 'mine', lplr
        elseif owner then
            if owner.Team == lplr.Team then return 'ally', owner
            else return 'enemy', owner end
        end
        return 'free', nil
    end

    -- ✅ Traves DINÂMICAS
    local function getMyTraves()
        local myColor = getMyTeamColor()
        if myColor == HOME_TEAM_COLOR then
            return HOME_TRAVE_ESQ_FRENTE, HOME_TRAVE_DIR_FRENTE, 
                   HOME_TRAVE_ESQ_FUNDO, HOME_TRAVE_DIR_FUNDO
        else
            return AWAY_TRAVE_ESQ_FRENTE, AWAY_TRAVE_DIR_FRENTE,
                   AWAY_TRAVE_ESQ_FUNDO, AWAY_TRAVE_DIR_FUNDO
        end
    end

    -- ✅ GK DINÂMICO
    local function findGoalie()
        local traveEsqF, traveDirF = getMyTraves()
        local goalCenter = (traveEsqF + traveDirF) / 2
        local closestGK, closestDist = nil, math.huge
        local myColor = getMyTeamColor()
        local enemyGoalieName = (myColor == HOME_TEAM_COLOR) and "HomeGoalie" or "Goalie"

        local bot = workspace:FindFirstChild(enemyGoalieName)
        if bot and bot:FindFirstChild('HumanoidRootPart') then
            local dist = (bot.HumanoidRootPart.Position - goalCenter).Magnitude
            if dist < 60 then
                closestGK = bot.HumanoidRootPart
                closestDist = dist
            end
        end

        for _, plr in game.Players:GetPlayers() do
            if plr ~= lplr and plr.Team ~= lplr.Team 
               and plr.Character and plr.Character:FindFirstChild('HumanoidRootPart') then
                local pos = plr.Character.HumanoidRootPart.Position
                local dist = (pos - goalCenter).Magnitude
                if dist < 60 and dist < closestDist then
                    closestGK = plr.Character.HumanoidRootPart
                    closestDist = dist
                end
            end
        end

        return closestGK
    end

    local function swapTeam()
        local myColor = getMyTeamColor()
        local targetColor = (myColor == HOME_TEAM_COLOR) and AWAY_TEAM_COLOR or HOME_TEAM_COLOR
        if TeamChangeRemote then
            TeamChangeRemote:FireServer(BrickColor.new(targetColor), 'Player')
            stats.swaps = stats.swaps + 1
            notif('FarmPro', 'Swap #' .. stats.swaps .. '!', 2)
        end
    end

    local function enterTeam(colorNumber)
        if TeamChangeRemote then
            TeamChangeRemote:FireServer(BrickColor.new(colorNumber), 'Player')
        end
    end

    local function getHomeTeam()
        for _, t in game:GetService('Teams'):GetChildren() do
            if t.TeamColor.Number == HOME_TEAM_COLOR then return t end
        end
        return nil
    end

    local function formatTime(seconds)
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%dm%02ds", mins, secs)
    end

    local function printStats()
        local elapsed = tick() - stats.startTime
        print("===== FARMPRO REPORT =====")
        print("Tempo: " .. formatTime(elapsed))
        print("Gols: " .. stats.goals)
        print("Tentativas: " .. stats.attempts)
        print("Swaps: " .. stats.swaps)
        print("Taxa: " .. (stats.attempts > 0 and math.floor((stats.goals / stats.attempts) * 100) .. "%" or "N/A"))
        print("Steals: " .. stats.steals)
        print("Faltas: " .. stats.fouls)
        print("Server Hops: " .. stats.hops)
        print("Kicks sofridos: " .. stats.kicks)
        print("==========================")
    end

    ----------------------------------------------------------------
    -- SERVER HOP
    ----------------------------------------------------------------

    local function getServers(maxP)
        local servers = {}
        local ok, response = pcall(function()
            return HttpService:JSONDecode(
                game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100")
            )
        end)
        if ok and response and response.data then
            for _, server in ipairs(response.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers
                   and server.playing <= (maxP or 999) then
                    table.insert(servers, server)
                end
            end
        end
        return servers
    end

    local function serverHop()
        stats.hops = stats.hops + 1
        printStats()
        notif('FarmPro', 'Hopping... (Hop #' .. stats.hops .. ')', 3)
        setPersist(true)
        local servers = getServers(MaxPlayers.Value)
        if #servers > 0 then
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, lplr, nil, { farmProActive = true })
            end)
            return true
        end
        pcall(function()
            TeleportService:Teleport(game.PlaceId, lplr, { farmProActive = true })
        end)
        return false
    end

    ----------------------------------------------------------------
    -- CHECKS
    ----------------------------------------------------------------

    local function hasHighLevelPlayer()
        for _, plr in game.Players:GetPlayers() do
            if plr ~= lplr then
                local ls = plr:FindFirstChild("leaderstats")
                if ls and ls:FindFirstChild("Goals") then
                    if ls.Goals.Value >= MaxGoals.Value then
                        notif('FarmPro', plr.Name .. ': ' .. ls.Goals.Value .. ' gols!', 3, 'warning')
                        return true
                    end
                end
            end
        end
        return false
    end

    local function isServerTooFull()
        return #game.Players:GetPlayers() > MaxPlayers.Value
    end

    local function isHomeTeamFull()
        local count = 0
        for _, plr in game.Players:GetPlayers() do
            if plr.TeamColor and plr.TeamColor.Number == HOME_TEAM_COLOR then
                count = count + 1
            end
        end
        return count >= 5
    end

    ----------------------------------------------------------------
    -- ANTI-KICK
    ----------------------------------------------------------------

    local function startKickDetector()
        return task.spawn(function()
            while FarmPro.Enabled do
                task.wait(0.5)
                local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
                if promptGui then
                    local overlay = promptGui:FindFirstChild("promptOverlay")
                    if overlay and #overlay:GetChildren() > 0 then
                        stats.kicks = stats.kicks + 1
                        notif('FarmPro', 'KICK! Hopping...', 3)
                        task.wait(0.5)
                        serverHop()
                        return
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- TEAM ENFORCER
    ----------------------------------------------------------------

    local function startTeamEnforcer()
        return task.spawn(function()
            while FarmPro.Enabled do
                task.wait(5)
                if amInFans() then
                    notif('FarmPro', '⚠️ Em FANS, entrando...', 2)
                    enterTeam(HOME_TEAM_COLOR)
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- KICKOFF DETECTOR
    ----------------------------------------------------------------

    local function startKickoffDetector()
        local boolsFolder = workspace:FindFirstChild("Bools")
        if not boolsFolder then return end

        local homeCele = boolsFolder:FindFirstChild("homeCele")
        local awayCele = boolsFolder:FindFirstChild("awayCele")
        local timePause = boolsFolder:FindFirstChild("timePause")

        if awayCele then
            FarmPro:Clean(awayCele.Changed:Connect(function(newVal)
                if newVal == true and FarmPro.Enabled then
                    -- awayCele = gol do time AWAY (que sou eu quando HOME)
                    local myColor = getMyTeamColor()
                    if myColor == HOME_TEAM_COLOR then
                        notif('FarmPro', 'Meu gol! (HOME) ⏱️', 3)
                    else
                        notif('FarmPro', 'Gol inimigo! (AWAY) 😤', 3)
                        theirKickoff = true
                    end
                    kickoffMode = false
                    lastGoalTime = tick()
                end
            end))
        end

        if homeCele then
            FarmPro:Clean(homeCele.Changed:Connect(function(newVal)
                if newVal == true and FarmPro.Enabled then
                    local myColor = getMyTeamColor()
                    if myColor == AWAY_TEAM_COLOR then
                        notif('FarmPro', 'Meu gol! (AWAY) ⏱️', 3)
                    else
                        notif('FarmPro', 'Gol inimigo! (HOME) 😤', 3)
                        theirKickoff = true
                    end
                    kickoffMode = false
                    lastGoalTime = tick()
                end
            end))
        end

        if timePause then
            FarmPro:Clean(timePause.Changed:Connect(function(newVal)
                if newVal == false and FarmPro.Enabled then
                    if theirKickoff then
                        notif('FarmPro', 'Kickoff deles acabou!', 2)
                        theirKickoff = false
                    end
                end
            end))
        end
    end

    ----------------------------------------------------------------
    -- PARTE 1: CONSEGUIR A BOLA
    ----------------------------------------------------------------

    local function tryGrabBall(ball)
        if not entitylib.isAlive then return false end
        entitylib.character.RootPart.CFrame = CFrame.new(ball.Position)
        task.wait(PossessionCheckDelay.Value)
        local newBall = findBall()
        if not newBall then return false end
        return getBallStatus(newBall) == 'mine'
    end

    local function tryStealBall(target)
        if not entitylib.isAlive or not target or not target.Character then return false end

        local ownerPos = target.Character.HumanoidRootPart.Position
        local root = entitylib.character.RootPart
        local ball = findBall()
        if not ball then return false end

        local ballPos = ball.Position
        local lookAtPos = Vector3.new(ballPos.X, ownerPos.Y, ballPos.Z)
        root.CFrame = CFrame.lookAt(ownerPos, lookAtPos)

        local aimConnection
        aimConnection = runService.Heartbeat:Connect(function()
            if not entitylib.isAlive then return end
            local currentBall = findBall()
            if not currentBall then return end
            local myRoot = entitylib.character.RootPart
            local bPos = currentBall.Position
            local targetPos = Vector3.new(bPos.X, myRoot.Position.Y, bPos.Z)
            myRoot.CFrame = CFrame.lookAt(myRoot.Position, targetPos)
        end)

        task.wait(AimDelay.Value)
        if aimConnection then aimConnection:Disconnect() end

        local VirtualInputManager = game:GetService('VirtualInputManager')
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)

        task.wait(PossessionCheckDelay.Value)

        local newBall = findBall()
        if not newBall then return false end
        local status = getBallStatus(newBall)

        if status == 'mine' then
            stats.steals = stats.steals + 1
            return true
        else
            stats.fouls = stats.fouls + 1
            return false
        end
    end

    local function tryGetBall()
        local ball = findBall()
        if not ball then return false, 'no_ball' end

        local status, target = getBallStatus(ball)

        if status == 'mine' then return true, 'already_mine'
        elseif status == 'ally' then
            if kickoffMode then
                local success = tryGrabBall(ball)
                if success then kickoffMode = false return true, 'kickoff_grab' end
                return false, 'kickoff_grab_failed'
            end
            return false, 'ally_has_it'
        elseif status == 'enemy' then
            task.wait(PreStealDelay.Value)
            ball = findBall()
            if not ball then return false, 'no_ball' end
            local newStatus, newTarget = getBallStatus(ball)
            if newStatus ~= 'enemy' then return false, 'status_changed' end
            local success = tryStealBall(newTarget)
            if success then return true, 'stole_from_enemy'
            else return false, 'tackle_failed_or_foul' end
        elseif status == 'free' then
            local success = tryGrabBall(ball)
            if success then return true, 'grabbed_free' end
            return false, 'grab_failed'
        end
        return false, 'unknown'
    end

    ----------------------------------------------------------------
    -- PARTE 2: FAZER O GOL (TP NAS TRAVES DINÂMICO)
    ----------------------------------------------------------------

    local function doShoot()
        if not entitylib.isAlive or not ShootRemote then return false end

        stats.attempts = stats.attempts + 1

        local root = entitylib.character.RootPart
        local goalieRoot = findGoalie()
        local traveEsqF, traveDirF, traveEsqFn, traveDirFn = getMyTraves()
        local goalCenterZ = (traveEsqF.Z + traveDirF.Z) / 2

        local shootSpot, targetCorner, lado

        if goalieRoot then
            local gkZ = goalieRoot.Position.Z
            if gkZ > goalCenterZ then
                -- GK na direita → TP esquerda, chuta fundo esquerdo
                shootSpot = traveEsqF
                targetCorner = traveEsqFn
                lado = 'ESQ'
            else
                -- GK na esquerda → TP direita, chuta fundo direito
                shootSpot = traveDirF
                targetCorner = traveDirFn
                lado = 'DIR'
            end
        else
            shootSpot = traveEsqF
            targetCorner = traveEsqFn
            lado = 'ESQ (sem GK)'
        end

        -- ✅ TP na trave, olhando pro fundo
        root.CFrame = CFrame.lookAt(shootSpot, targetCorner)
        task.wait(0.3)

        if not entitylib.isAlive then return false end

        root = entitylib.character.RootPart
        local lookDir = (targetCorner - root.Position).Unit

        local scoreBefore = getMyScore()

        ShootRemote:FireServer(
            lookDir,
            root.CFrame,
            Power.Value,
            lookDir,
            false,
            false,
            'None'
        )

        notif('FarmPro', 'Chute ' .. lado .. ' (#' .. stats.attempts .. ')', 2)

        task.wait(GoalCheckDelay.Value)

        local scoreAfter = getMyScore()

        if scoreAfter > scoreBefore then
            stats.goals = stats.goals + 1
            stats.sessionGoals = stats.sessionGoals + 1
            lastGoalTime = tick()
            notif('FarmPro', 'GOL #' .. stats.goals .. '! ⚽ | ' .. formatTime(tick() - stats.startTime), 4)
            return true
        else
            notif('FarmPro', 'Errou! #' .. stats.attempts, 2)
            return false
        end
    end

    ----------------------------------------------------------------
    -- LOOP PRINCIPAL (COM TEAM SWAP CONDICIONAL)
    ----------------------------------------------------------------

    local function farmLoop()
        while FarmPro.Enabled do
            if amInFans() then
                task.wait(1)
                continue
            end

            if not amInGame() then
                task.wait(1)
                continue
            end

            if not entitylib.isAlive then
                task.wait(1)
                continue
            end

            if theirKickoff then
                task.wait(0.5)
                continue
            end

            local timeSinceLastGoal = tick() - lastGoalTime
            if timeSinceLastGoal < Cooldown.Value and not kickoffMode then
                local ball = findBall()
                if ball then
                    local status = getBallStatus(ball)
                    if status ~= 'enemy' then
                        task.wait(0.3)
                        continue
                    end
                else
                    task.wait(0.3)
                    continue
                end
            end

            local gotBall, reason = tryGetBall()

            if not gotBall then
                if reason == 'ally_has_it' then task.wait(1)
                elseif reason == 'tackle_failed_or_foul' then
                    notif('FarmPro', 'Tackle falhou', 2)
                    task.wait(1)
                elseif reason == 'grab_failed' or reason == 'kickoff_grab_failed' then task.wait(0.3)
                else task.wait(0.5) end
                continue
            end

            if reason == 'kickoff_grab' then
                notif('FarmPro', 'Kickoff! ⚽', 2)
                task.wait(0.2)
            else
                if reason == 'stole_from_enemy' then
                    notif('FarmPro', 'Roubou! (Steal #' .. stats.steals .. ')', 2)
                end
                task.wait(StealDelay.Value)
            end

            local ball = findBall()
            if ball then
                local status = getBallStatus(ball)
                if status == 'mine' then
                    local success = doShoot()

                    while not success and FarmPro.Enabled do
                        task.wait(0.5)
                        if not entitylib.isAlive then break end
                        ball = findBall()
                        if not ball then break end
                        local retryStatus = getBallStatus(ball)
                        if retryStatus ~= 'mine' and retryStatus ~= 'free' then break end
                        if retryStatus == 'free' then
                            tryGrabBall(ball)
                            task.wait(0.2)
                        end
                        success = doShoot()
                    end

                    -- ✅ TEAM SWAP: só se fez gol E ≤ 2 players no server
                    if success and FarmPro.Enabled and shouldSwap() then
                        task.wait(SwapDelay.Value)
                        
                        if FarmPro.Enabled then
                            swapTeam()
                            
                            -- Espera entrar no novo time
                            local swapStart = tick()
                            while FarmPro.Enabled and tick() - swapStart < 15 do
                                task.wait(0.5)
                                if amInGame() then break end
                            end
                            
                            task.wait(2)
                            kickoffMode = true -- kickoff é meu agora!
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- MÓDULO PRINCIPAL
    ----------------------------------------------------------------

    FarmPro = vape.Categories.farmRSS:CreateModule({
        Name = 'FarmPro',
        Function = function(callback)
            if callback then
                stats = {
                    goals = 0, attempts = 0, steals = 0,
                    hops = 0, kicks = 0, fouls = 0, swaps = 0,
                    startTime = tick(), sessionGoals = 0
                }
                lastGoalTime = 0
                lastEnemyScore = getEnemyScore()
                kickoffMode = false
                theirKickoff = false

                setPersist(true)

                startKickDetector()
                startKickoffDetector()
                startTeamEnforcer()

                FarmPro:Clean(task.spawn(function()
                    task.wait(3)

                    while FarmPro.Enabled do
                        if isServerTooFull() then
                            notif('FarmPro', 'Server lotado! Hopping...', 3)
                            task.wait(2)
                            serverHop()
                            return
                        end

                        if hasHighLevelPlayer() then
                            notif('FarmPro', 'Player VIP! Hopping...', 3)
                            task.wait(2)
                            serverHop()
                            return
                        end

                        if isHomeTeamFull() then
                            notif('FarmPro', 'HOME cheio! Hopping...', 3)
                            task.wait(2)
                            serverHop()
                            return
                        end

                        if not amInGame() then
                            enterTeam(HOME_TEAM_COLOR)
                            task.wait(3)
                        end

                        notif('FarmPro', 'Farmando por ' .. FarmTime.Value .. 'min', 4)

                        local farmEnd = tick() + (FarmTime.Value * 60)

                        task.spawn(function()
                            farmLoop()
                        end)

                        while FarmPro.Enabled and tick() < farmEnd do
                            task.wait(2)
                            if isServerTooFull() then
                                notif('FarmPro', 'Server lotado!', 2)
                                break
                            end
                            if hasHighLevelPlayer() then
                                notif('FarmPro', 'Player VIP!', 2)
                                break
                            end
                        end

                        if not FarmPro.Enabled then return end

                        printStats()
                        notif('FarmPro', 'Session: ' .. stats.sessionGoals .. ' gols | ' .. stats.swaps .. ' swaps', 5)

                        task.wait(2)
                        serverHop()
                        return
                    end
                end))
            else
                setPersist(false)
                theirKickoff = false
                printStats()
                notif('FarmPro', 'Gols: ' .. stats.goals .. ' | Swaps: ' .. stats.swaps, 3)
            end
        end,
        Tooltip = 'AutoFarm + team swap quando sozinho (≤2 players).'
    })

    MaxPlayers = FarmPro:CreateSlider({
        Name = 'Max Players', Min = 1, Max = 10, Default = 3
    })

    MaxGoals = FarmPro:CreateSlider({
        Name = 'Max Goals Limit', Min = 100, Max = 5000, Default = 1000
    })

    FarmTime = FarmPro:CreateSlider({
        Name = 'Farm Time', Min = 1, Max = 60, Default = 15,
        Suffix = function(val) return val == 1 and 'minute' or 'minutes' end
    })

    Power = FarmPro:CreateSlider({
        Name = 'Shoot Power', Min = 0.05, Max = 1, Default = 0.3, Decimal = 100
    })

    SwapDelay = FarmPro:CreateSlider({
        Name = 'Swap Delay', Min = 1, Max = 30, Default = 3,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end,
        Tooltip = 'Tempo após gol antes de trocar de time'
    })

    Cooldown = FarmPro:CreateSlider({
        Name = 'Cooldown', Min = 1, Max = 30, Default = 10,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    PreStealDelay = FarmPro:CreateSlider({
        Name = 'React Delay', Min = 0, Max = 2, Default = 0.2, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    AimDelay = FarmPro:CreateSlider({
        Name = 'Steal Aim', Min = 0, Max = 1, Default = 0.15, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    PossessionCheckDelay = FarmPro:CreateSlider({
        Name = 'Possession Check', Min = 0.1, Max = 1, Default = 0.3, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    StealDelay = FarmPro:CreateSlider({
        Name = 'Pre-Shoot Delay', Min = 0, Max = 2, Default = 0.4, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    GoalCheckDelay = FarmPro:CreateSlider({
        Name = 'Goal Check', Min = 0.5, Max = 5, Default = 1.5, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    -- Auto-resume
    task.spawn(function()
        task.wait(5)
        local teleportData = TeleportService:GetLocalPlayerTeleportData()
        if teleportData and teleportData.farmProActive then
            task.wait(3)
            if not FarmPro.Enabled then
                FarmPro:Toggle()
                notif('FarmPro', 'Auto-resumido!', 3)
            end
        else
            setPersist(false)
        end
    end)
end)

run(function()
    local AerialReach
    local Range
    local Delay
    local MinHeight
    local Timeout
    local AutoAim
    local AimRange
    local DerivationMult
    local DerivationMultY
    local TurnBody

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')

    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141
    local SHOT_COOLDOWN = 3
    local MAX_GOALIE_DIST = 60
    local MOVEMENT_THRESHOLD = 0.5

    local Remotes = ReplicatedStorage:WaitForChild('Remotes')
    local ShootRemote = Remotes:FindFirstChild('ShootTheBaII')

    local PickupRemote
    for _, remote in Remotes:GetChildren() do
        if remote:IsA('RemoteEvent') and remote:GetAttribute('Attribute') then
            PickupRemote = remote
            break
        end
    end

    local wsBools = workspace:WaitForChild('Bools')
    local apgBool = wsBools:FindFirstChild('APG')
    local hpgBool = wsBools:FindFirstChild('HPG')

    local cachedBall = nil
    local cachedWeld = nil
    local turnBodyConnection = nil
    local isTurned = false

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end

        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return nil
        end

        local rootPart = cachedWeld.Part0
        if not rootPart then return nil end

        return Players:GetPlayerFromCharacter(rootPart.Parent)
    end

    local function getTargetGoal()
        local myColor = lplr.TeamColor and lplr.TeamColor.Number

        if myColor == HOME_TEAM_COLOR then
            return workspace:FindFirstChild('HomeGoal')
        elseif myColor == AWAY_TEAM_COLOR then
            return workspace:FindFirstChild('AwayGoal')
        end

        return workspace:FindFirstChild('HomeGoal')
    end

    local function checkGoalieCandidate(bool, goalPos)
        if not bool or not bool.Value then return nil end

        local gk = bool.Value
        if gk == lplr or gk.Team == lplr.Team then return nil end
        if not gk.Character then return nil end

        local root = gk.Character:FindFirstChild('HumanoidRootPart')
        if not root then return nil end

        if (root.Position - goalPos).Magnitude >= MAX_GOALIE_DIST then return nil end

        return root
    end

    local function findGoalie(goalPos)
        local root = checkGoalieCandidate(apgBool, goalPos)
        if root then return root end

        return checkGoalieCandidate(hpgBool, goalPos)
    end

    local function getBestTargets(goal)
        local targets = goal:FindFirstChild('Targets')
        if not targets then return nil, nil end

        local targetRight = targets:FindFirstChild('TargetRight')
        local targetLeft = targets:FindFirstChild('TargetLeft')
        local targetCenter = targets:FindFirstChild('TargetCenter')

        if not targetRight or not targetLeft then
            return targetCenter, targetCenter
        end

        local goalCenterPos = targetCenter and targetCenter.Position or
                              (targetRight.Position + targetLeft.Position) / 2

        local goalie = findGoalie(goalCenterPos)

        if not goalie then
            return targetCenter or targetRight, targetLeft or targetRight
        end

        local distRight = (targetRight.Position - goalie.Position).Magnitude
        local distLeft = (targetLeft.Position - goalie.Position).Magnitude

        if distRight > distLeft then
            return targetRight, targetLeft
        end

        return targetLeft, targetRight
    end

    local function calculateAimDirection(ballPos, targetPos)
        return (targetPos - ballPos).Unit
    end

    local function stopTurnBody()
        if turnBodyConnection then
            turnBodyConnection:Disconnect()
            turnBodyConnection = nil
        end
        isTurned = false
    end

    local function applyTurnBody(root, aimPos)
        stopTurnBody()

        local flatAim = Vector3.new(aimPos.X, root.Position.Y, aimPos.Z)
        root.CFrame = CFrame.lookAt(root.Position, flatAim)
        isTurned = true

        local lastPos = root.Position

        turnBodyConnection = runService.Heartbeat:Connect(function()
            if not root or not root.Parent then
                stopTurnBody()
                return
            end

            local currentPos = root.Position

            if (currentPos - lastPos).Magnitude > MOVEMENT_THRESHOLD then
                stopTurnBody()
                return
            end

            local flat = Vector3.new(aimPos.X, currentPos.Y, aimPos.Z)
            root.CFrame = CFrame.lookAt(currentPos, flat)
        end)
    end

    local function calculateDerivedAimPos(target, opposite)
        local factorXZ = DerivationMult.Value / 10
        local factorY = DerivationMultY.Value / 10

        local aimPos = target.Position:Lerp(opposite.Position, factorXZ)

        if factorY ~= 0 then
            local baseHeight = aimPos.Y
            local finalY

            if factorY >= 0 then
                finalY = baseHeight + 8 * factorY
            else
                finalY = baseHeight + 6 * factorY
            end

            aimPos = Vector3.new(aimPos.X, finalY, aimPos.Z)
        end

        return aimPos
    end

    local function tryAutoAim(root)
        local goal = getTargetGoal()
        if not goal then return nil end

        local targets = goal:FindFirstChild('Targets')
        local goalCenter = targets and targets:FindFirstChild('TargetCenter')
        if not goalCenter then return nil end

        local distToGoal = (root.Position - goalCenter.Position).Magnitude
        if distToGoal > AimRange.Value then return nil end

        local target, opposite = getBestTargets(goal)
        if not target then return nil end

        local aimPos = target.Position

        if opposite and (DerivationMult.Value > 0 or DerivationMultY.Value ~= 0) then
            aimPos = calculateDerivedAimPos(target, opposite)
        end

        return aimPos
    end

    local function executeHeader(root, head, ball)
        local shootDir = root.CFrame.LookVector

        if AutoAim.Enabled then
            local aimPos = tryAutoAim(root)
            if aimPos then
                shootDir = calculateAimDirection(ball.Position, aimPos)

                if TurnBody.Enabled then
                    applyTurnBody(root, aimPos)
                    task.wait()
                    shootDir = calculateAimDirection(ball.Position, aimPos)
                end
            end
        end

        PickupRemote:FireServer(3)
        task.wait()

        ShootRemote:FireServer(
            shootDir * 0.7,
            CFrame.new(root.Position.X, head.CFrame.Y, root.Position.Z),
            1,
            shootDir * 2000,
            false,
            false
        )
    end

    AerialReach = vape.Categories.realista:CreateModule({
        Name = 'AerialReachAim',
        Function = function(callback)
            if callback then
                if not PickupRemote or not ShootRemote then
                    AerialReach:Toggle()
                    return
                end

                local lastShot = 0
                local headerActivatedAt = 0
                local headerProcessed = false

                cachedBall = nil
                cachedWeld = nil

                AerialReach:Clean(runService.Heartbeat:Connect(function()
                    if not entitylib.isAlive then
                        headerProcessed = false
                        headerActivatedAt = 0
                        return
                    end

                    if tick() - lastShot < SHOT_COOLDOWN then return end

                    local char = lplr.Character
                    if not char then return end

                    local bools = char:FindFirstChild('Bools')
                    if not bools then return end

                    local headerBool = bools:FindFirstChild('Header')

                    if not headerBool or not headerBool.Value then
                        headerProcessed = false
                        headerActivatedAt = 0
                        return
                    end

                    if headerActivatedAt == 0 then
                        headerActivatedAt = tick()
                        headerProcessed = false
                        return
                    end

                    if headerProcessed then return end

                    if tick() - headerActivatedAt > Timeout.Value then
                        headerProcessed = true
                        return
                    end

                    if tick() - headerActivatedAt < Delay.Value then return end

                    local ball = findBall()
                    if not ball then return end
                    if getBallOwner() then return end

                    local root = char:FindFirstChild('HumanoidRootPart')
                    local head = char:FindFirstChild('Head')
                    if not root or not head then return end

                    local heightAboveMe = ball.Position.Y - root.Position.Y
                    if heightAboveMe < MinHeight.Value then
                        headerProcessed = true
                        return
                    end

                    local dist = (root.Position - ball.Position).Magnitude
                    if dist > Range.Value then return end

                    headerProcessed = true
                    lastShot = tick()

                    executeHeader(root, head, ball)
                end))

                AerialReach:Clean(lplr.CharacterAdded:Connect(function()
                    cachedBall = nil
                    cachedWeld = nil
                end))
            else
                stopTurnBody()
                cachedBall = nil
                cachedWeld = nil
            end
        end,
        Tooltip = 'Reach aereo com aim no canto oposto ao GK'
    })

    Range = AerialReach:CreateSlider({
        Name = 'Range',
        Min = 5, Max = 50, Default = 15,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    Delay = AerialReach:CreateSlider({
        Name = 'Delay',
        Min = 0, Max = 2, Default = 0.3, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    MinHeight = AerialReach:CreateSlider({
        Name = 'Min Height Above Me',
        Min = 0, Max = 15, Default = 3, Decimal = 10,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
        Tooltip = 'Altura minima da bola acima do seu personagem'
    })

    Timeout = AerialReach:CreateSlider({
        Name = 'Timeout',
        Min = 0.5, Max = 5, Default = 1.5, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })

    AutoAim = AerialReach:CreateToggle({
        Name = 'Auto Aim',
        Default = true,
        Function = function(callback)
            if AimRange and AimRange.Object then AimRange.Object.Visible = callback end
            if DerivationMult and DerivationMult.Object then DerivationMult.Object.Visible = callback end
            if DerivationMultY and DerivationMultY.Object then DerivationMultY.Object.Visible = callback end
            if TurnBody and TurnBody.Object then TurnBody.Object.Visible = callback end
        end
    })

    AimRange = AerialReach:CreateSlider({
        Name = 'Aim Range',
        Min = 10, Max = 200, Default = 80,
        Visible = false,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    DerivationMult = AerialReach:CreateSlider({
        Name = 'Derivation Mult',
        Min = 0, Max = 10, Default = 0, Decimal = 10,
        Visible = false,
        Tooltip = '0=canto exato | 10=mira no lado oposto'
    })

    DerivationMultY = AerialReach:CreateSlider({
        Name = 'Derivation Mult Y',
        Min = -10, Max = 10, Default = 0, Decimal = 10,
        Visible = false,
        Tooltip = '0=altura base | +10=travessao | -10=rente ao chao'
    })

    TurnBody = AerialReach:CreateToggle({
        Name = 'Turn Body',
        Default = true,
        Visible = false,
        Tooltip = 'Vira o corpo pro alvo e mantem ate voce se mover'
    })
end)

run(function()
    local HeaderShield
    local OnlyWithBall
    local ReactiveMode
    local ReactiveDistance
    local ShootBypass
    local AutoActivate
    local Distance

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local runService = game:GetService('RunService')

    local TACKLE_ANIM_ID = '14317040670'
    local REACTION_WINDOW = 0.8
    local BUFF_DURATION_ESTIMATE = 1.0
    local FIRE_COOLDOWN = 0.08
    local HEADER_COOLDOWN = 2.8

    local ActionRemote = ReplicatedStorage:WaitForChild('Remotes'):FindFirstChild('Action')

    -- Comunicação global com AerialReach
    _G.__HeaderShieldActive = false
    _G.__LastShieldHeaderTime = 0

    local mainConn = nil
    local charConn = nil
    local headerChangedConn = nil
    local enemyWatchers = {}

    local cachedChar = nil
    local cachedRoot = nil
    local cachedBall = nil
    local cachedBallWeld = nil
    local headerBool = nil

    local enemyList = {}

    local shieldingActive = false
    local lastFire = 0
    local tackleDetectedUntil = 0
    local buffExpiresAt = 0

    local indexHookInstalled = false
    local oldIndex = nil

    local function getRealHeaderValue()
        if not headerBool then return false end
        if oldIndex then
            return oldIndex(headerBool, 'Value')
        end
        return headerBool.Value
    end

    local function rebuildCharCache()
        cachedChar = lplr.Character
        if not cachedChar then
            cachedRoot = nil
            headerBool = nil
            return
        end

        cachedRoot = cachedChar:FindFirstChild('HumanoidRootPart')
        local bools = cachedChar:FindFirstChild('Bools')
        headerBool = bools and bools:FindFirstChild('Header')
    end

    local function getBall()
        if cachedBall and cachedBall.Parent then
            return cachedBall
        end

        cachedBall = nil
        cachedBallWeld = nil

        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                return obj
            end
        end

        return nil
    end

    local function hasBall()
        local ball = getBall()
        if not ball then return false end

        if not cachedBallWeld or cachedBallWeld.Parent ~= ball then
            cachedBallWeld = ball:FindFirstChild('playerWeld')
        end

        if not cachedBallWeld or not cachedBallWeld:IsA('Weld') then
            cachedBallWeld = nil
            return false
        end

        local rootPart = cachedBallWeld.Part0
        if not rootPart then return false end

        return rootPart.Parent == cachedChar
    end

    local function hasEnemyNear()
        if not cachedRoot then return false end

        local myPos = cachedRoot.Position
        local myTeam = lplr.Team
        local rangeSq = Distance.Value * Distance.Value

        for i = 1, #enemyList do
            local plr = enemyList[i]
            if plr.Team == myTeam then continue end

            local char = plr.Character
            if not char then continue end

            local enemyRoot = char:FindFirstChild('HumanoidRootPart')
            if not enemyRoot then continue end

            local diff = enemyRoot.Position - myPos
            if diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z <= rangeSq then
                return true
            end
        end
        return false
    end

    local function shouldBeActive()
        if not cachedChar or not cachedChar.Parent then return false end

        local hum = cachedChar:FindFirstChildOfClass('Humanoid')
        if not hum or hum.Health <= 0 then return false end

        if not headerBool then return false end

        -- PAUSA quando AerialReach está executando cabeceio aéreo
        if _G.__AerialReachActive then return false end
        if tick() - (_G.__LastAerialReachTime or 0) < 1.2 then return false end

        if OnlyWithBall.Enabled and not hasBall() then return false end

        if ReactiveMode.Enabled then
            return tick() <= tackleDetectedUntil
        end

        if AutoActivate.Enabled and not hasEnemyNear() then return false end

        return true
    end

    local function fireHeader()
        ActionRemote:FireServer('Header')
        lastFire = tick()
        _G.__LastShieldHeaderTime = tick()
        buffExpiresAt = tick() + BUFF_DURATION_ESTIMATE
    end

    local function addEnemy(plr)
        if plr == lplr then return end
        for i = 1, #enemyList do
            if enemyList[i] == plr then return end
        end
        table.insert(enemyList, plr)
    end

    local function removeEnemy(plr)
        for i = 1, #enemyList do
            if enemyList[i] == plr then
                table.remove(enemyList, i)
                return
            end
        end
    end

    local function watchEnemyTackles(plr)
        if plr == lplr then return end
        if enemyWatchers[plr] then return end

        local function setup(char)
            local hum = char:WaitForChild('Humanoid', 5)
            if not hum then return end

            local conn = hum.AnimationPlayed:Connect(function(track)
                if not HeaderShield.Enabled then return end
                if plr.Team == lplr.Team then return end

                local anim = track.Animation
                if not anim then return end
                if not anim.AnimationId:find(TACKLE_ANIM_ID) then return end

                if not cachedRoot then return end
                local enemyRoot = char:FindFirstChild('HumanoidRootPart')
                if not enemyRoot then return end

                local diff = enemyRoot.Position - cachedRoot.Position
                local distSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z

                local range = ReactiveMode.Enabled and ReactiveDistance.Value or Distance.Value
                if distSq > range * range then return end

                tackleDetectedUntil = tick() + REACTION_WINDOW
            end)

            enemyWatchers[plr] = conn
        end

        if plr.Character then task.spawn(setup, plr.Character) end
        plr.CharacterAdded:Connect(setup)
    end

    local function installShootBypass()
        if indexHookInstalled then return end
        if not hookmetamethod then return end

        indexHookInstalled = true

        oldIndex = hookmetamethod(game, '__index', newcclosure(function(self, key)
            if HeaderShield and HeaderShield.Enabled
               and ShootBypass and ShootBypass.Enabled
               and key == 'Value'
               and self == headerBool then

                -- Durante AerialReach, devolve o valor REAL (não bloqueia cabeceio aéreo)
                if _G.__AerialReachActive then
                    return oldIndex(self, key)
                end

                -- ⬇️ GATE REMOVIDO: era isso que travava o tackle após o toque.
                -- if OnlyWithBall and OnlyWithBall.Enabled and not hasBall() then
                --     return oldIndex(self, key)
                -- end

                return false
            end

            return oldIndex(self, key)
        end))
    end

    local function setupHeaderWatcher()
        if headerChangedConn then headerChangedConn:Disconnect() end
        if not headerBool then return end

        headerChangedConn = headerBool.Changed:Connect(function(newValue)
            if not HeaderShield.Enabled then return end

            if newValue == true then
                buffExpiresAt = tick() + BUFF_DURATION_ESTIMATE
                return
            end

            if not shouldBeActive() then return end
            if tick() - lastFire < HEADER_COOLDOWN then return end
            fireHeader()
        end)
    end

    HeaderShield = vape.Categories.realista:CreateModule({
        Name = 'HeaderShield',
        Function = function(callback)
            _G.__HeaderShieldActive = callback == true

            if callback then
                if not ActionRemote or not hookmetamethod then
                    HeaderShield:Toggle()
                    return
                end

                enemyList = {}
                enemyWatchers = {}

                for _, plr in Players:GetPlayers() do
                    addEnemy(plr)
                end

                rebuildCharCache()

                lastFire = 0
                tackleDetectedUntil = 0
                cachedBall = nil
                cachedBallWeld = nil
                shieldingActive = false
                buffExpiresAt = 0

                installShootBypass()
                setupHeaderWatcher()

                for _, plr in Players:GetPlayers() do
                    watchEnemyTackles(plr)
                end

                HeaderShield:Clean(Players.PlayerAdded:Connect(function(plr)
                    addEnemy(plr)
                    watchEnemyTackles(plr)
                end))

                HeaderShield:Clean(Players.PlayerRemoving:Connect(function(plr)
                    if enemyWatchers[plr] then
                        enemyWatchers[plr]:Disconnect()
                        enemyWatchers[plr] = nil
                    end
                    removeEnemy(plr)
                end))

                charConn = lplr.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    if HeaderShield.Enabled then
                        rebuildCharCache()
                        setupHeaderWatcher()
                        cachedBall = nil
                        cachedBallWeld = nil
                    end
                end)

                mainConn = runService.Heartbeat:Connect(function()
                    if not HeaderShield.Enabled then return end

                    if not cachedChar or not cachedChar.Parent then
                        rebuildCharCache()
                        shieldingActive = false
                        return
                    end

                    local hum = cachedChar:FindFirstChildOfClass('Humanoid')
                    if not hum or hum.Health <= 0 then
                        shieldingActive = false
                        return
                    end

                    if not headerBool then
                        rebuildCharCache()
                        return
                    end

                    shieldingActive = shouldBeActive()

                    if not shieldingActive then return end
                    if getRealHeaderValue() then return end
                    if tick() - lastFire < FIRE_COOLDOWN then return end

                    fireHeader()
                end)
            else
                _G.__HeaderShieldActive = false

                if mainConn then mainConn:Disconnect() mainConn = nil end
                if headerChangedConn then headerChangedConn:Disconnect() headerChangedConn = nil end
                if charConn then charConn:Disconnect() charConn = nil end

                for _, conn in pairs(enemyWatchers) do
                    conn:Disconnect()
                end
                enemyWatchers = {}
                enemyList = {}

                shieldingActive = false
                buffExpiresAt = 0
                cachedBall = nil
                cachedBallWeld = nil
            end
        end,
        Tooltip = 'Spamma Header pra manter buff de invencibilidade. Conectado ao AerialReach via _G.'
    })

    OnlyWithBall = HeaderShield:CreateToggle({
        Name = 'Only With Ball',
        Default = true,
        Tooltip = 'So ativa quando com bola'
    })

    ReactiveMode = HeaderShield:CreateToggle({
        Name = 'Reactive Mode',
        Default = false,
        Tooltip = 'Ativa apenas quando detecta tackle proximo',
        Function = function(val)
            if ReactiveDistance and ReactiveDistance.Object then
                ReactiveDistance.Object.Visible = val
            end
        end,
    })

    ReactiveDistance = HeaderShield:CreateSlider({
        Name = 'Reactive Distance',
        Min = 5, Max = 30, Default = 15,
        Visible = false,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
        Tooltip = 'Range de deteccao no modo reactive'
    })

    ShootBypass = HeaderShield:CreateToggle({
        Name = 'Shoot Bypass',
        Default = true,
        Tooltip = 'Permite chutar com Header ativo'
    })

    AutoActivate = HeaderShield:CreateToggle({
        Name = 'Only With Enemy Near',
        Default = true,
        Function = function(val)
            if Distance and Distance.Object then
                Distance.Object.Visible = val
            end
        end,
    })

    Distance = HeaderShield:CreateSlider({
        Name = 'Enemy Detect Range',
        Min = 5, Max = 30, Default = 15,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
    })
end)

run(function()
    local BallMagnet
    local RangeX
    local RangeY
    local MagnetDelay
    local GhostMode
    local PingMultiplier
    local ScanRate

    local Stats = game:GetService('Stats')
    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')

    local PING_SAMPLE_INTERVAL = 0.1
    local PING_SAMPLE_COUNT = 20
    local CANTGRAB_SAMPLE_COUNT = 15
    local CANTGRAB_DEFAULT = 0.43
    local HEADER_DURATION = 1.05 -- Hardcoded: Header dura ~1 segundo

    local pickupRemote
    for _, remote in ReplicatedStorage:WaitForChild('Remotes'):GetChildren() do
        if remote:IsA('RemoteEvent') and remote:GetAttribute('Attribute') then
            pickupRemote = remote
            break
        end
    end

    local pingStat = Stats.Network.ServerStatsItem['Data Ping']
    local wsBools = workspace:WaitForChild('Bools')
    local cantGrabBool = wsBools:WaitForChild('cantGrab')
    local penaltyBool = wsBools:FindFirstChild('Penalty')

    local cachedBall = nil
    local cachedWeld = nil
    local ballConnections = {}
    local charConnections = {}
    local lastPickup = 0
    local scanLoopActive = false

    local pingSamples = {}
    local pingSampleIndex = 1
    local pingLoopActive = false

    local cantGrabSamples = {}
    local cantGrabSampleIndex = 1
    local cantGrabStartTime = 0
    local cantGrabDuration = CANTGRAB_DEFAULT

    -- Cooldown interno do Header (não depende de ler o Value)
    local headerStartTime = 0

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end

        for _, obj in workspace:GetChildren() do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                cachedWeld = nil
                return obj
            end
        end

        cachedBall = nil
        cachedWeld = nil
        return nil
    end

    local function getBallWeld()
        local ball = findBall()
        if not ball then return nil end

        if cachedWeld and cachedWeld.Parent == ball then
            return cachedWeld
        end

        local weld = ball:FindFirstChild('playerWeld')
        if weld and weld:IsA('Weld') then
            cachedWeld = weld
            return weld
        end

        cachedWeld = nil
        return nil
    end

    local function getBallOwner()
        local weld = getBallWeld()
        if not weld or not weld.Part0 then return nil end
        return Players:GetPlayerFromCharacter(weld.Part0.Parent)
    end

    local function iHaveBall()
        return getBallOwner() == lplr
    end

    local function getAveragePing()
        local sum = 0
        local count = 0

        for i = 1, PING_SAMPLE_COUNT do
            local sample = pingSamples[i]
            if sample then
                sum = sum + sample
                count = count + 1
            end
        end

        if count == 0 then
            return pingStat:GetValue() / 1000
        end

        return sum / count
    end

    local function isInPickupRange()
        if not entitylib.isAlive then return false end

        local root = entitylib.character.RootPart
        if not root then return false end

        local ball = findBall()
        if not ball then return false end

        local myPos = root.Position
        local ballPos = ball.Position

        local dx = myPos.X - ballPos.X
        local dz = myPos.Z - ballPos.Z
        local horizontalDistSq = dx * dx + dz * dz
        local rangeX = RangeX.Value

        if horizontalDistSq > rangeX * rangeX then return false end

        local upwardOffset = ballPos.Y - myPos.Y
        local rangeY = RangeY.Value

        if rangeY == 0 then
            return upwardOffset <= 0
        end

        return upwardOffset <= rangeY
    end

    local function canPickup(checkCantGrab)
        if not entitylib.isAlive then return false end
        if tick() - lastPickup < MagnetDelay.Value then return false end
        if getBallOwner() then return false end
        if penaltyBool and penaltyBool.Value then return false end
        if checkCantGrab and cantGrabBool.Value then return false end

        -- Cooldown interno do Header (sem ler o Value!)
        -- Se estamos dentro do tempo de Header E não foi ManualHeader -> bloqueia
        if tick() - headerStartTime < HEADER_DURATION then
            if not _G.__HeaderJump then
                return false
            end
        end

        return true
    end

    local function fireGrab()
        lastPickup = tick()
        pickupRemote:FireServer(0)
    end

    local function attemptScanPickup()
        if not canPickup(true) then return end
        if not isInPickupRange() then return end
        fireGrab()
    end

    local function attemptGhostPickup()
        if not canPickup(false) then return end
        if not isInPickupRange() then return end
        fireGrab()
    end

    local function onBallWeldRemoved()
        if not BallMagnet.Enabled or not GhostMode.Enabled then return end

        local releaseTime = tick()

        task.spawn(function()
            local ping = getAveragePing()
            local pingCompensation = ping * PingMultiplier.Value
            local fireAt = releaseTime + cantGrabDuration - pingCompensation
            local waitTime = fireAt - tick()

            if waitTime > 0 then
                task.wait(waitTime)
            end

            if not BallMagnet.Enabled then return end
            attemptGhostPickup()
        end)
    end

    local function setupBallWatcher()
        for _, conn in ballConnections do
            conn:Disconnect()
        end
        table.clear(ballConnections)

        if not GhostMode.Enabled then return end

        local ball = findBall()
        if not ball then return end

        table.insert(ballConnections, ball.ChildRemoved:Connect(function(child)
            if child.Name == 'playerWeld' then
                cachedWeld = nil
                onBallWeldRemoved()
            end
        end))

        table.insert(ballConnections, ball.ChildAdded:Connect(function(child)
            if child.Name == 'playerWeld' then
                cachedWeld = nil
            end
        end))
    end

    -- === FIX: agora escuta hum.Jumping (evento físico, imune ao hook do HeaderShield) ===
    local function setupHeaderWatcher(char)
        local hum = char:FindFirstChildOfClass('Humanoid') or char:WaitForChild('Humanoid', 5)
        if not hum then return end

        table.insert(charConnections, hum.Jumping:Connect(function()
            -- Pulo do ManualHeader / sonic jump já marca a flag ANTES do ChangeState(Jumping)
            if _G.__HeaderJump then return end

            headerStartTime = tick()
        end))
    end

    local function startScanLoop()
        scanLoopActive = true
        task.spawn(function()
            while scanLoopActive and BallMagnet.Enabled do
                task.wait(1 / ScanRate.Value)
                if not scanLoopActive or not BallMagnet.Enabled then break end
                attemptScanPickup()
            end
        end)
    end

    local function startPingSampler()
        pingLoopActive = true
        task.spawn(function()
            while pingLoopActive and BallMagnet.Enabled do
                pingSamples[pingSampleIndex] = pingStat:GetValue() / 1000
                pingSampleIndex = pingSampleIndex % PING_SAMPLE_COUNT + 1
                task.wait(PING_SAMPLE_INTERVAL)
            end
        end)
    end

    local function setupCantGrabLearner()
        cantGrabBool:GetPropertyChangedSignal('Value'):Connect(function()
            if not BallMagnet.Enabled then return end

            if cantGrabBool.Value then
                cantGrabStartTime = tick()
            else
                if cantGrabStartTime == 0 then return end

                local duration = tick() - cantGrabStartTime
                cantGrabStartTime = 0

                if duration < 0.2 or duration > 1.0 then return end

                cantGrabSamples[cantGrabSampleIndex] = duration
                cantGrabSampleIndex = cantGrabSampleIndex % CANTGRAB_SAMPLE_COUNT + 1

                local sum = 0
                local count = 0
                for i = 1, CANTGRAB_SAMPLE_COUNT do
                    if cantGrabSamples[i] then
                        sum = sum + cantGrabSamples[i]
                        count = count + 1
                    end
                end

                if count > 0 then
                    cantGrabDuration = sum / count
                end
            end
        end)
    end

    BallMagnet = vape.Categories.realista:CreateModule({
        Name = 'BallMagnet',
        Function = function(callback)
            if callback then
                if not pickupRemote then
                    BallMagnet:Toggle()
                    return
                end

                lastPickup = 0
                headerStartTime = 0
                cachedBall = nil
                cachedWeld = nil
                pingSamples = {}
                pingSampleIndex = 1
                cantGrabSamples = {}
                cantGrabSampleIndex = 1
                cantGrabDuration = CANTGRAB_DEFAULT
                cantGrabStartTime = 0

                for _, conn in charConnections do
                    conn:Disconnect()
                end
                table.clear(charConnections)

                if lplr.Character then
                    setupHeaderWatcher(lplr.Character)
                end

                setupBallWatcher()
                setupCantGrabLearner()
                startPingSampler()
                startScanLoop()

                BallMagnet:Clean(lplr.CharacterAdded:Connect(function(char)
                    task.wait(0.5)
                    headerStartTime = 0
                    cachedBall = nil
                    cachedWeld = nil

                    for _, conn in charConnections do
                        conn:Disconnect()
                    end
                    table.clear(charConnections)

                    setupHeaderWatcher(char)
                    setupBallWatcher()
                end))
            else
                scanLoopActive = false
                pingLoopActive = false

                for _, conn in ballConnections do
                    conn:Disconnect()
                end
                table.clear(ballConnections)

                for _, conn in charConnections do
                    conn:Disconnect()
                end
                table.clear(charConnections)

                cachedBall = nil
                cachedWeld = nil
                headerStartTime = 0
            end
        end,
        Tooltip = 'Pickup com scan fixo, Ghost Mode, ping medio movel, aprendizado dinamico de cantGrab e cooldown interno de Header.'
    })

    ScanRate = BallMagnet:CreateSlider({
        Name = 'Scan Rate',
        Min = 30, Max = 500, Default = 200,
        Suffix = function(val) return ' scans/s' end,
        Tooltip = 'Tentativas por segundo. Independe do FPS.'
    })

    RangeX = BallMagnet:CreateSlider({
        Name = 'Range X (Chao)',
        Min = 3, Max = 50, Default = 15,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    RangeY = BallMagnet:CreateSlider({
        Name = 'Range Y (Pra Cima)',
        Min = 0, Max = 30, Default = 5,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    MagnetDelay = BallMagnet:CreateSlider({
        Name = 'Delay',
        Min = 0, Max = 1, Default = 0, Decimal = 100,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end,
        Tooltip = 'Tempo minimo entre cada pickup'
    })

    GhostMode = BallMagnet:CreateToggle({
        Name = 'Ghost Mode',
        Default = true,
        Tooltip = 'Reacao ao release do inimigo com predicao de cantGrab'
    })

    PingMultiplier = BallMagnet:CreateSlider({
        Name = 'Ping Compensation',
        Min = 0, Max = 1, Default = 0.5, Decimal = 100,
        Suffix = function(val) return 'x' end,
        Tooltip = '0.5 = seguro | 0.75 = arriscado | 1.0 = ultra roubado'
    })
end)

run(function()
    local InstantShoot
    local renv = getrenv and getrenv() or _G
    local hookfunction = hookfunction or replaceclosure

    local hooksInitialized = false
    local isHookEnabled = false
    local oldWait
    local oldTaskWait

    local function initHooks()
        if hooksInitialized or not hookfunction then return end
        hooksInitialized = true

        -- Intercepta o wait(0.08)
        if renv.wait then
            oldWait = hookfunction(renv.wait, newcclosure(function(seconds, ...)
                if isHookEnabled and typeof(seconds) == "number" and math.abs(seconds - 0.08) <= 0.005 then
                    return 0 -- ZERA TOTALMENTE O TEMPO
                end
                return oldWait(seconds, ...)
            end))
        end

        -- Intercepta o task.wait(0.08)
        if renv.task and renv.task.wait then
            oldTaskWait = hookfunction(renv.task.wait, newcclosure(function(seconds, ...)
                if isHookEnabled and typeof(seconds) == "number" and math.abs(seconds - 0.08) <= 0.005 then
                    return 0 -- ZERA TOTALMENTE O TEMPO
                end
                return oldTaskWait(seconds, ...)
            end))
        end
    end

    InstantShoot = vape.Categories.realista:CreateModule({
        Name = 'InstantShoot',
        Function = function(callback)
            if callback then
                if not hookfunction then
                    if vape.CreateNotification then
                        vape:CreateNotification('InstantShoot', 'Executor sem suporte a hookfunction!', 5)
                    end
                    InstantShoot:Toggle()
                    return
                end

                initHooks()
                isHookEnabled = true
            else
                isHookEnabled = false
            end
        end,
        Tooltip = 'Remove instantaneamente o delay de 0.08s dos chutes e passes ao soltar o mouse.'
    })
end)

run(function()
    local NoDebounce
    local Players = game:GetService('Players')
    local lplr = Players.LocalPlayer
    
    local targetDebounce = nil

    local function updateTarget(char)
        targetDebounce = nil
        if not char then return end
        local bools = char:WaitForChild("Bools", 5)
        if bools then
            local db = bools:WaitForChild("Debounce", 5)
            if db and db:IsA("BoolValue") then
                targetDebounce = db
            end
        end
    end

    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, index)
        if not checkcaller() and self == targetDebounce and index == "Value" then
            return false
        end
        return oldIndex(self, index)
    end)

    NoDebounce = vape.Categories.realista:CreateModule({
        Name = 'NoDebounce',
        Function = function(callback)
            if callback then
                if lplr.Character then
                    updateTarget(lplr.Character)
                end
                
                lplr.CharacterAdded:Connect(function(char)
                    task.wait(0.5)
                    updateTarget(char)
                end)
            else
                targetDebounce = nil
            end
        end,
        Tooltip = 'Usa Hooking para retornar sempre False ao ler o Debounce.'
    })
end)

run(function()
    local AssistPasser
    local MaxStrangers, FarmTime, TeamSwap, SwapDelay, PasserDelay, ResetDelay

    local MY_REQUIRED_NAME = "ApenasUmNoob60"
    local PARTNER_NAME = "PEIDEIFORTECUIDADO"

    local Players = game:GetService('Players')
    local HttpService = game:GetService('HttpService')
    local TeleportService = game:GetService('TeleportService')
    local GuiService = game:GetService('GuiService')
    local CoreGui = game:GetService('CoreGui')
    local VirtualInputManager = game:GetService('VirtualInputManager')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local lplr = Players.LocalPlayer

    local queueonteleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    local Remotes = ReplicatedStorage:WaitForChild('Remotes')
    local ShootRemote = Remotes:FindFirstChild('ShootTheBaII')
    local TeamChangeRemote = Remotes:FindFirstChild('TeamChange')

    local SHARED_HOP_FILE = "assist_target_server.json"
    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141

    local isFarming = false
    local assistsCount = 0

    local function notif(title, text, duration)
        if vape and vape.CreateNotification then vape:CreateNotification(title, text, duration or 3) end
    end

    local function startAntiAFK()
        task.spawn(function()
            lplr.Idled:Connect(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightControl, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
            end)
            while isFarming and AssistPasser.Enabled do
                task.wait(30)
                if isFarming then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)
                end
            end
        end)
    end

    local function isCorrectAccount() return lplr.Name == MY_REQUIRED_NAME end
    local function getMyRoot() return lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart') end
    local function getMyTeamColor() return lplr.TeamColor and lplr.TeamColor.Number end
    local function amInGame() local c = getMyTeamColor() return c == HOME_TEAM_COLOR or c == AWAY_TEAM_COLOR end
    local function enterTeam(colorNumber) if TeamChangeRemote then TeamChangeRemote:FireServer(BrickColor.new(colorNumber), 'Player') end end
    local function swapTeam() local myColor = getMyTeamColor() if myColor then enterTeam((myColor == HOME_TEAM_COLOR) and AWAY_TEAM_COLOR or HOME_TEAM_COLOR) end end
    local function getPartner() return Players:FindFirstChild(PARTNER_NAME) end
    local function getPickupRemote() for _, r in ipairs(Remotes:GetChildren()) do if r:IsA('RemoteEvent') and r:GetAttribute('Attribute') then return r end end return nil end

    local function getStrangersCount()
        local count = 0
        local partner = getPartner()
        for _, plr in ipairs(Players:GetPlayers()) do if plr ~= lplr and plr ~= partner then count = count + 1 end end
        return count
    end

    local function findBall()
        for _, obj in ipairs(workspace:GetChildren()) do if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then return obj end end
        return nil
    end

    local function iHaveBall()
        local ball = findBall()
        if not ball then return false end
        local weld = ball:FindFirstChild('playerWeld')
        if weld and weld.Part0 and weld.Part0:IsDescendantOf(lplr.Character) then
            return true
        end
        return false
    end

    -- [[ DETECTOR DE GOL PARA SWAP ]]
    local function setupCelebrationWatcher()
        task.spawn(function()
            local boolsFolder = workspace:WaitForChild("Bools", 10)
            if not boolsFolder then return end
            local hCele, aCele = boolsFolder:WaitForChild("homeCele", 5), boolsFolder:WaitForChild("awayCele", 5)

            local function onGoal()
                if isFarming and AssistPasser.Enabled and TeamSwap.Enabled and isCorrectAccount() then
                    task.wait(SwapDelay.Value)
                    if isFarming and AssistPasser.Enabled and isCorrectAccount() then
                        swapTeam()
                        notif('AssistPasser', 'Team Swap OK! (Kickoff transferido)', 2)
                    end
                end
            end
            if hCele then AssistPasser:Clean(hCele.Changed:Connect(function(v) if v then onGoal() end end)) end
            if aCele then AssistPasser:Clean(aCele.Changed:Connect(function(v) if v then onGoal() end end)) end
        end)
    end

    local function initiateDualHop()
        local servers = {}
        local ok, response = pcall(function() return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100")) end)
        local targetJobId = nil
        if ok and response and response.data then
            for _, s in ipairs(response.data) do if s.id ~= game.JobId and s.playing <= 2 then targetJobId = s.id break end end
        end
        pcall(function() if writefile then writefile(SHARED_HOP_FILE, HttpService:JSONEncode({jobId = targetJobId, timestamp = os.time()})) end end)
        if queueonteleport then queueonteleport("task.wait(5) if vape and vape.Modules.AssistPasser then vape.Modules.AssistPasser:Toggle() end") end
        task.wait(1.5)
        if targetJobId then TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, lplr) else TeleportService:Teleport(game.PlaceId, lplr) end
    end

    local function checkFollowerHop()
        if not isfile or not readfile or not isfile(SHARED_HOP_FILE) then return false end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SHARED_HOP_FILE)) end)
        if ok and data and data.timestamp and (os.time() - data.timestamp < 60) then
            if data.jobId and data.jobId ~= game.JobId then
                if queueonteleport then queueonteleport("task.wait(5) if vape and vape.Modules.AssistPasser then vape.Modules.AssistPasser:Toggle() end") end
                TeleportService:TeleportToPlaceInstance(game.PlaceId, data.jobId, lplr)
                return true
            end
        end
        return false
    end

    -- [[ LOOP PRINCIPAL COM ESPERA DE CELEBRAÇÃO ]]
    local function startLoop()
        task.spawn(function()
            local farmEnd = tick() + (FarmTime.Value * 60)
            while isFarming and AssistPasser.Enabled do
                task.wait(0.1)

                if checkFollowerHop() then break end
                if not isCorrectAccount() then continue end

                -- 🕒 1. TRAVA DE CELEBRAÇÃO (O ponto que você pediu!)
                -- Enquanto o jogo estiver comemorando (celebração ativa), o script espera e não faz nada.
                local wsBools = workspace:FindFirstChild('Bools')
                if wsBools then
                    local homeCele = wsBools:FindFirstChild('homeCele')
                    local awayCele = wsBools:FindFirstChild('awayCele')
                    if (homeCele and homeCele.Value == true) or (awayCele and awayCele.Value == true) then
                        task.wait(1)
                        continue -- Volta pro início do loop e checa de novo
                    end
                end

                if getStrangersCount() > MaxStrangers.Value or tick() >= farmEnd then initiateDualHop() break end

                -- Sincroniza time
                local partner = getPartner()
                if partner and partner.TeamColor and partner.TeamColor.Number ~= getMyTeamColor() then
                    enterTeam(partner.TeamColor.Number) task.wait(1.5) continue
                elseif not amInGame() then 
                    enterTeam(HOME_TEAM_COLOR) task.wait(2) continue 
                end

                local ball = findBall()
                if ball then
                    if not iHaveBall() then
                        local weld = ball:FindFirstChild('playerWeld')
                        if not weld then
                            local root = getMyRoot()
                            if root then
                                root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 0.2, 0))
                                local pickup = getPickupRemote()
                                if pickup then pickup:FireServer(0) end
                            end
                            task.wait(0.1)
                        end
                    else
                        task.wait(PasserDelay.Value)
                        local root = getMyRoot()
                        if root and iHaveBall() then
                            local dir = root.CFrame.LookVector
                            ShootRemote:FireServer(dir, ball.CFrame, 0.05, dir * 100, false, false, 'None')
                            assistsCount = assistsCount + 1
                            task.wait(ResetDelay.Value)
                        end
                    end
                end
            end
        end)
    end

    AssistPasser = vape.Categories.farmRSS:CreateModule({
        Name = 'AssistPasser',
        Function = function(callback)
            if callback then
                isFarming = true
                assistsCount = 0
                startAntiAFK()
                if isCorrectAccount() then setupCelebrationWatcher() end
                startLoop()
                notif('AssistPasser', isCorrectAccount() and 'Iniciado (Com espera de gol)!' or 'Monitorando parceiro...', 3)
            else
                isFarming = false
            end
        end
    })
    
    MaxStrangers = AssistPasser:CreateSlider({Name = 'Max Estranhos', Min = 0, Max = 10, Default = 1})
    FarmTime = AssistPasser:CreateSlider({Name = 'Farm Time', Min = 5, Max = 60, Default = 15})
    PasserDelay = AssistPasser:CreateSlider({Name = 'Toque Delay', Min = 0.05, Max = 1, Default = 0.15, Decimal = 100})
    ResetDelay = AssistPasser:CreateSlider({Name = 'Reset Delay', Min = 1.5, Max = 6, Default = 3, Decimal = 100})
    TeamSwap = AssistPasser:CreateToggle({Name = 'Team Swap', Default = true})
    SwapDelay = AssistPasser:CreateSlider({Name = 'Swap Delay', Min = 1, Max = 5, Default = 2, Decimal = 100})
end)

run(function()
    local AssistScorer
    local ShootPower, TeamSwap, SwapDelay, ResetDelay, GrabTimeout

    local MY_REQUIRED_NAME = "PEIDEIFORTECUIDADO"
    local PARTNER_NAME = "ApenasUmNoob60"

    local Players = game:GetService('Players')
    local HttpService = game:GetService('HttpService')
    local TeleportService = game:GetService('TeleportService')
    local GuiService = game:GetService('GuiService')
    local CoreGui = game:GetService('CoreGui')
    local VirtualInputManager = game:GetService('VirtualInputManager')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local lplr = Players.LocalPlayer

    local queueonteleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    local Remotes = ReplicatedStorage:WaitForChild('Remotes')
    local ShootRemote = Remotes:FindFirstChild('ShootTheBaII')
    local TeamChangeRemote = Remotes:FindFirstChild('TeamChange')

    local pickupRemote
    for _, remote in ipairs(Remotes:GetChildren()) do if remote:IsA('RemoteEvent') and remote:GetAttribute('Attribute') then pickupRemote = remote break end end

    local SHARED_HOP_FILE = "assist_target_server.json"
    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141

    -- Traves Dinâmicas
    local HOME_TRAVE_ESQ_FRENTE = Vector3.new(155.44, 4.76, -1.58)
    local HOME_TRAVE_DIR_FRENTE = Vector3.new(156.43, 4.76, 23.46)
    local HOME_TRAVE_ESQ_FUNDO  = Vector3.new(165.03, 3.72, -1.77)
    local HOME_TRAVE_DIR_FUNDO  = Vector3.new(165.03, 3.74, 23.34)
    local AWAY_TRAVE_ESQ_FRENTE = Vector3.new(-160.55, 4.76, -0.83)
    local AWAY_TRAVE_DIR_FRENTE = Vector3.new(-161.39, 4.76, 22.70)
    local AWAY_TRAVE_ESQ_FUNDO  = Vector3.new(-168.51, 4.76, -1.55)
    local AWAY_TRAVE_DIR_FUNDO  = Vector3.new(-168.76, 4.76, 24.16)

    local isFarming = false
    local goalsScored = 0

    local function notif(title, text, duration)
        if vape and vape.CreateNotification then vape:CreateNotification(title, text, duration or 3) end
    end

    local function isCorrectAccount() return lplr.Name == MY_REQUIRED_NAME end
    local function getMyRoot() return lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart') end
    local function getMyTeamColor() return lplr.TeamColor and lplr.TeamColor.Number end
    local function amInGame() local c = getMyTeamColor() return c == HOME_TEAM_COLOR or c == AWAY_TEAM_COLOR end
    local function enterTeam(colorNumber) if TeamChangeRemote then TeamChangeRemote:FireServer(BrickColor.new(colorNumber), 'Player') end end
    local function swapTeam() local myColor = getMyTeamColor() if myColor then enterTeam((myColor == HOME_TEAM_COLOR) and AWAY_TEAM_COLOR or HOME_TEAM_COLOR) end end
    local function getPartner() return Players:FindFirstChild(PARTNER_NAME) end

    -- [[ BUSCA DE SERVIDORES ]]
    local function getEmptyServers()
        local ok, response = pcall(function() return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100")) end)
        if ok and response and response.data then
            for _, s in ipairs(response.data) do if s.id ~= game.JobId and s.playing <= 2 then return s.id end end
        end
        return nil
    end

    -- [[ INICIAR HOP CASO KICKADO ]]
    local function initiateScorerHop()
        notif('AssistScorer', 'KICK! Buscando novo servidor para a dupla...', 5)
        local targetJobId = getEmptyServers()
        
        pcall(function()
            if writefile then
                writefile(SHARED_HOP_FILE, HttpService:JSONEncode({jobId = targetJobId, timestamp = os.time()}))
            end
        end)

        if queueonteleport then
            queueonteleport("task.wait(6) if vape and vape.Modules.AssistScorer then vape.Modules.AssistScorer:Toggle() end")
        end

        task.wait(2)
        if targetJobId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, lplr)
        else
            TeleportService:Teleport(game.PlaceId, lplr)
        end
    end

    local function checkPartnerHop()
        if not isfile or not readfile or not isfile(SHARED_HOP_FILE) then return false end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SHARED_HOP_FILE)) end)
        if ok and data and data.timestamp and (os.time() - data.timestamp < 60) then
            if data.jobId and data.jobId ~= game.JobId then
                if queueonteleport then queueonteleport("task.wait(6) if vape and vape.Modules.AssistScorer then vape.Modules.AssistScorer:Toggle() end") end
                TeleportService:TeleportToPlaceInstance(game.PlaceId, data.jobId, lplr)
                return true
            end
        end
        return false
    end

    -- [[ DETECTOR DE KICK MELHORADO ]]
    local function startKickDetector()
        AssistScorer:Clean(GuiService.ErrorMessageChanged:Connect(function()
            if isFarming and AssistScorer.Enabled and isCorrectAccount() then
                initiateScorerHop()
            end
        end))
        
        task.spawn(function()
            while isFarming and AssistScorer.Enabled do
                task.wait(1)
                local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
                if prompt and prompt:FindFirstChild("promptOverlay") and #prompt.promptOverlay:GetChildren() > 0 then
                    initiateScorerHop()
                    break
                end
            end
        end)
    end

    local function executeGoalShot()
        local root = getMyRoot()
        if not root or not ShootRemote then return false end
        local myColor = getMyTeamColor()
        local tEsqF, tEsqFn = (myColor == HOME_TEAM_COLOR) and HOME_TRAVE_ESQ_FRENTE or AWAY_TRAVE_ESQ_FRENTE, (myColor == HOME_TEAM_COLOR) and HOME_TRAVE_ESQ_FUNDO or AWAY_TRAVE_ESQ_FUNDO
        root.CFrame = CFrame.lookAt(tEsqF, tEsqFn)
        task.wait(0.15)
        local lookDir = (tEsqFn - tEsqF).Unit
        ShootRemote:FireServer(lookDir, root.CFrame, ShootPower.Value, lookDir, false, false, 'None')
        goalsScored = goalsScored + 1
        return true
    end

    local function startLoop()
        task.spawn(function()
            local readyToCatch = false
            while isFarming and AssistScorer.Enabled do
                task.wait(0.02)
                if checkPartnerHop() then break end
                if not isCorrectAccount() then continue end

                local partner = getPartner()
                if partner and partner.TeamColor and partner.TeamColor.Number ~= getMyTeamColor() then
                    enterTeam(partner.TeamColor.Number) task.wait(1.5) continue
                elseif not amInGame() then enterTeam(HOME_TEAM_COLOR) task.wait(2) continue end

                local ball = nil
                for _, v in workspace:GetChildren() do if v.Name:lower() == 'ball' then ball = v break end end
                if not ball or not partner then continue end

                local weld = ball:FindFirstChild('playerWeld')
                local owner = (weld and weld.Part0) and Players:GetPlayerFromCharacter(weld.Part0.Parent) or nil

                if owner == partner then readyToCatch = true end

                if readyToCatch and not owner then
                    readyToCatch = false
                    local start = tick()
                    while isFarming and AssistScorer.Enabled and (tick() - start < GrabTimeout.Value) do
                        local root = getMyRoot()
                        if root then
                            root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 0.2, 0))
                            if pickupRemote then pickupRemote:FireServer(0) end
                        end
                        task.wait(0.12)
                        local curWeld = ball:FindFirstChild('playerWeld')
                        if curWeld and curWeld.Part0 and curWeld.Part0.Parent == lplr.Character then
                            if executeGoalShot() then
                                if TeamSwap.Enabled then task.wait(SwapDelay.Value) swapTeam() end
                                task.wait(ResetDelay.Value)
                            end
                            break
                        end
                    end
                end
            end
        end)
    end

    AssistScorer = vape.Categories.farmRSS:CreateModule({
        Name = 'AssistScorer',
        Function = function(callback)
            if callback then
                isFarming = true
                goalsScored = 0
                startKickDetector()
                startLoop()
                notif('AssistScorer', isCorrectAccount() and 'Ativo!' or 'Monitorando Hop', 3)
            else
                isFarming = false
            end
        end
    })

    ShootPower = AssistScorer:CreateSlider({Name = 'Força', Min = 0.1, Max = 1, Default = 0.35, Decimal = 100})
    TeamSwap = AssistScorer:CreateToggle({Name = 'Team Swap', Default = true})
    SwapDelay = AssistScorer:CreateSlider({Name = 'Delay do Swap', Min = 1, Max = 5, Default = 2, Decimal = 100})
    GrabTimeout = AssistScorer:CreateSlider({Name = 'Grab Timeout', Min = 1, Max = 5, Default = 3, Decimal = 100})
    ResetDelay = AssistScorer:CreateSlider({Name = 'Reset Delay', Min = 1.5, Max = 6, Default = 2.5, Decimal = 100})

    task.spawn(function()
        task.wait(5)
        local teleportData = TeleportService:GetLocalPlayerTeleportData()
        if teleportData and teleportData.assistFarmActive and lplr.Name == MY_REQUIRED_NAME then
            if not AssistScorer.Enabled then AssistScorer:Toggle() end
        end
    end)
end)

run(function()
    local SaveFarmer
    local MaxStrangers, FarmTime, HoldTime, ReleaseDelay

    local MY_REQUIRED_NAME = "ApenasUmNoob60"
    local PARTNER_NAME = "PEIDEIFORTECUIDADO"

    local Players = game:GetService('Players')
    local HttpService = game:GetService('HttpService')
    local TeleportService = game:GetService('TeleportService')
    local GuiService = game:GetService('GuiService')
    local CoreGui = game:GetService('CoreGui')
    local VirtualInputManager = game:GetService('VirtualInputManager')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local lplr = Players.LocalPlayer

    local queueonteleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    local Remotes = ReplicatedStorage:WaitForChild('Remotes')
    local TeamChangeRemote = Remotes:FindFirstChild('TeamChange')
    local ShootRemote = Remotes:FindFirstChild('ShootTheBaII')

    local SHARED_HOP_FILE = "savefarm_target_server.json"
    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141

    local isFarming = false
    local savesCount = 0
    local hopInProgress = false

    local function notif(title, text, duration)
        if vape and vape.CreateNotification then vape:CreateNotification(title, text, duration or 3) end
    end

    local function isCorrectAccount() return lplr.Name == MY_REQUIRED_NAME end
    local function getMyRoot() return lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart') end
    local function getPartner() return Players:FindFirstChild(PARTNER_NAME) end
    local function getPickupRemote()
        for _, r in ipairs(Remotes:GetChildren()) do
            if r:IsA('RemoteEvent') and r:GetAttribute('Attribute') then return r end
        end
        return nil
    end
    local function findBall()
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then return obj end
        end
        return nil
    end
    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end
        local weld = ball:FindFirstChild('playerWeld')
        if not weld or not weld.Part0 or not weld.Part0.Parent then return nil end
        return Players:GetPlayerFromCharacter(weld.Part0.Parent)
    end
    local function iHaveBall() return getBallOwner() == lplr end

    local function isGoalie()
        local wsBools = workspace:FindFirstChild('Bools')
        if not wsBools then return false end
        local hpg, apg = wsBools:FindFirstChild('HPG'), wsBools:FindFirstChild('APG')
        return (hpg and hpg.Value == lplr) or (apg and apg.Value == lplr)
    end

    local function becomeGoalie()
        if not TeamChangeRemote then return end
        TeamChangeRemote:FireServer(BrickColor.new(HOME_TEAM_COLOR), 'Goalie')
        task.wait(1.5)
        if not isGoalie() then
            TeamChangeRemote:FireServer(BrickColor.new(AWAY_TEAM_COLOR), 'Goalie')
        end
    end

    local function getStrangersCount()
        local count = 0
        local partner = getPartner()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lplr and plr ~= partner then count = count + 1 end
        end
        return count
    end

    local function getEmptyServerId()
        local ok, response = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
            ))
        end)
        if ok and response and response.data then
            for _, s in ipairs(response.data) do
                if s.id ~= game.JobId and s.playing <= 2 then
                    return s.id
                end
            end
        end
        return nil
    end

    local function readHopFile()
        if not (isfile and readfile and isfile(SHARED_HOP_FILE)) then return nil end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(SHARED_HOP_FILE))
        end)
        if not ok or not data or not data.timestamp then return nil end
        if (os.time() - data.timestamp) > 90 then return nil end
        return data
    end

    local function writeHopFile(jobId)
        pcall(function()
            if writefile then
                writefile(SHARED_HOP_FILE, HttpService:JSONEncode({
                    jobId = jobId,
                    timestamp = os.time(),
                    from = MY_REQUIRED_NAME
                }))
            end
        end)
    end

    local function teleportTo(jobId)
        if queueonteleport then
            queueonteleport([[
                task.wait(6)
                if vape and vape.Modules and vape.Modules.SaveFarmer then
                    if not vape.Modules.SaveFarmer.Enabled then
                        vape.Modules.SaveFarmer:Toggle()
                    end
                end
            ]])
        end
        if jobId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, lplr, nil, { saveFarmActive = true })
        else
            TeleportService:Teleport(game.PlaceId, lplr, { saveFarmActive = true })
        end
    end

    -- Segue hop existente OU cria um novo (sem sobrescrever hop recente de outra conta)
    local function requestDualHop(reason)
        if hopInProgress then return end
        hopInProgress = true
        notif('SaveFarmer', 'Hop: ' .. (reason or 'sync') .. '...', 3)

        -- 1) Se já existe hop recente de alguém, SEGUE
        local existing = readHopFile()
        if existing and existing.jobId and existing.jobId ~= game.JobId then
            notif('SaveFarmer', 'Seguindo hop do parceiro...', 3)
            task.wait(0.5)
            teleportTo(existing.jobId)
            return
        end

        -- 2) Senão, EU lidero o hop
        local jobId = getEmptyServerId()
        writeHopFile(jobId)

        -- tempo pra outra instância ler o arquivo
        task.wait(3.5)
        teleportTo(jobId)
    end

    local function followHopIfAny()
        local data = readHopFile()
        if data and data.jobId and data.jobId ~= game.JobId then
            if hopInProgress then return true end
            hopInProgress = true
            notif('SaveFarmer', 'Parceiro hopou. Seguindo...', 3)
            teleportTo(data.jobId)
            return true
        end
        return false
    end

    -- Se o parceiro sumiu: espera o arquivo antes de hop próprio
    local function handlePartnerMissing()
        if hopInProgress then return end
        notif('SaveFarmer', 'Parceiro sumiu. Aguardando hop file...', 3)
        for _ = 1, 20 do -- ~10s
            if followHopIfAny() then return end
            if getPartner() then return end -- voltou?
            task.wait(0.5)
        end
        requestDualHop('partner_missing')
    end

    local function startAntiAFK()
        task.spawn(function()
            lplr.Idled:Connect(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightControl, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
            end)
            while isFarming and SaveFarmer.Enabled do
                task.wait(30)
                if isFarming then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)
                end
            end
        end)
    end

    local function startKickDetector()
        SaveFarmer:Clean(GuiService.ErrorMessageChanged:Connect(function()
            if isFarming and SaveFarmer.Enabled and isCorrectAccount() then
                requestDualHop('kick')
            end
        end))
        task.spawn(function()
            while isFarming and SaveFarmer.Enabled do
                task.wait(0.5)
                if not isCorrectAccount() then break end
                local prompt = CoreGui:FindFirstChild('RobloxPromptGui')
                if prompt then
                    local overlay = prompt:FindFirstChild('promptOverlay')
                    if overlay and (#overlay:GetChildren() > 0 or overlay:FindFirstChild('ErrorPrompt') or overlay:FindFirstChild('Prompt')) then
                        requestDualHop('kick_gui')
                        break
                    end
                end
            end
        end)
    end

    local function startLoop()
        task.spawn(function()
            local farmEnd = tick() + (FarmTime.Value * 60)
            local lastSaveTick = 0
            local partnerWasHere = false

            while isFarming and SaveFarmer.Enabled do
                task.wait(0.1)

                -- hop monitor SEMPRE
                if followHopIfAny() then break end

                if not isCorrectAccount() then
                    task.wait(1)
                    continue
                end

                local partner = getPartner()
                if partner then
                    partnerWasHere = true
                elseif partnerWasHere then
                    handlePartnerMissing()
                    break
                end

                if getStrangersCount() > MaxStrangers.Value or tick() >= farmEnd then
                    requestDualHop('full_or_time')
                    break
                end

                if not isGoalie() then
                    becomeGoalie()
                    task.wait(1.5)
                    continue
                end

                if iHaveBall() then
                    if tick() - lastSaveTick > 0.5 then
                        savesCount = savesCount + 1
                        lastSaveTick = tick()
                        notif('SaveFarmer', 'SAVE #' .. savesCount, 2)
                    end
                    task.wait(HoldTime.Value)
                    local root = getMyRoot()
                    local ball = findBall()
                    if root and ball and iHaveBall() then
                        local dir = root.CFrame.LookVector
                        if ShootRemote then
                            ShootRemote:FireServer(dir, ball.CFrame, 0.05, dir * 40, false, false, 'None')
                        end
                    end
                    task.wait(ReleaseDelay.Value)
                else
                    local ball = findBall()
                    local root = getMyRoot()
                    if ball and root and (ball.Position - root.Position).Magnitude <= 18 then
                        local pickup = getPickupRemote()
                        if pickup then pickup:FireServer(0) end
                    end
                end
            end
        end)
    end

    SaveFarmer = vape.Categories.farmRSS:CreateModule({
        Name = 'SaveFarmer',
        Function = function(callback)
            if callback then
                isFarming = true
                hopInProgress = false
                savesCount = 0
                startAntiAFK()
                startKickDetector()
                startLoop()
            else
                isFarming = false
            end
        end
    })

    MaxStrangers = SaveFarmer:CreateSlider({Name = 'Max Estranhos', Min = 0, Max = 10, Default = 0})
    FarmTime = SaveFarmer:CreateSlider({Name = 'Farm Time', Min = 5, Max = 60, Default = 15})
    HoldTime = SaveFarmer:CreateSlider({Name = 'Hold Time', Min = 0.2, Max = 2, Default = 0.6, Decimal = 100})
    ReleaseDelay = SaveFarmer:CreateSlider({Name = 'Release Delay', Min = 0.2, Max = 2, Default = 0.8, Decimal = 100})

    task.spawn(function()
        task.wait(5)
        local td = TeleportService:GetLocalPlayerTeleportData()
        if td and td.saveFarmActive and lplr.Name == MY_REQUIRED_NAME then
            task.wait(2)
            if not SaveFarmer.Enabled then SaveFarmer:Toggle() end
        end
    end)
end)

run(function()
    local SaveShooter
    local CycleDelay, GrabTimeout, MaxStrangers, FarmTime

    local MY_REQUIRED_NAME = "PEIDEIFORTECUIDADO"
    local PARTNER_NAME = "ApenasUmNoob60"

    local Players = game:GetService('Players')
    local HttpService = game:GetService('HttpService')
    local TeleportService = game:GetService('TeleportService')
    local GuiService = game:GetService('GuiService')
    local CoreGui = game:GetService('CoreGui')
    local VirtualInputManager = game:GetService('VirtualInputManager')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local lplr = Players.LocalPlayer

    local queueonteleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    local Remotes = ReplicatedStorage:WaitForChild('Remotes')
    local TeamChangeRemote = Remotes:FindFirstChild('TeamChange')
    local ShootRemote = Remotes:FindFirstChild('ShootTheBaII')

    local SHARED_HOP_FILE = "savefarm_target_server.json"
    local HOME_TEAM_COLOR = 23
    local AWAY_TEAM_COLOR = 141
    local FANS_TEAM_COLOR = 199

    local isFarming = false
    local deliveries = 0
    local hopInProgress = false
    local deliverySideIndex = 1
    local DELIVERY_SIDES = { 'Front', 'Back', 'Left', 'Right' }

    local function notif(title, text, duration)
        if vape and vape.CreateNotification then vape:CreateNotification(title, text, duration or 3) end
    end

    local function isCorrectAccount() return lplr.Name == MY_REQUIRED_NAME end
    local function getMyRoot() return lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart') end
    local function getMyTeamColor() return lplr.TeamColor and lplr.TeamColor.Number end
    local function getPartner() return Players:FindFirstChild(PARTNER_NAME) end
    local function amInGame()
        local c = getMyTeamColor()
        return c == HOME_TEAM_COLOR or c == AWAY_TEAM_COLOR
    end
    local function enterTeam(colorNumber)
        if TeamChangeRemote then
            TeamChangeRemote:FireServer(BrickColor.new(colorNumber), 'Player')
        end
    end
    local function getPickupRemote()
        for _, r in ipairs(Remotes:GetChildren()) do
            if r:IsA('RemoteEvent') and r:GetAttribute('Attribute') then return r end
        end
        return nil
    end
    local function findBall()
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then return obj end
        end
        return nil
    end
    local function getBallOwner()
        local ball = findBall()
        if not ball then return nil end
        local weld = ball:FindFirstChild('playerWeld')
        if not weld or not weld.Part0 or not weld.Part0.Parent then return nil end
        return Players:GetPlayerFromCharacter(weld.Part0.Parent)
    end
    local function iHaveBall() return getBallOwner() == lplr end

    local function getStrangersCount()
        local count = 0
        local partner = getPartner()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lplr and plr ~= partner then count = count + 1 end
        end
        return count
    end

    local function getEmptyServerId()
        local ok, response = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
            ))
        end)
        if ok and response and response.data then
            for _, s in ipairs(response.data) do
                if s.id ~= game.JobId and s.playing <= 2 then return s.id end
            end
        end
        return nil
    end

    local function readHopFile()
        if not (isfile and readfile and isfile(SHARED_HOP_FILE)) then return nil end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(SHARED_HOP_FILE))
        end)
        if not ok or not data or not data.timestamp then return nil end
        if (os.time() - data.timestamp) > 90 then return nil end
        return data
    end

    local function writeHopFile(jobId)
        pcall(function()
            if writefile then
                writefile(SHARED_HOP_FILE, HttpService:JSONEncode({
                    jobId = jobId,
                    timestamp = os.time(),
                    from = MY_REQUIRED_NAME
                }))
            end
        end)
    end

    local function teleportTo(jobId)
        if queueonteleport then
            queueonteleport([[
                task.wait(6)
                if vape and vape.Modules and vape.Modules.SaveShooter then
                    if not vape.Modules.SaveShooter.Enabled then
                        vape.Modules.SaveShooter:Toggle()
                    end
                end
            ]])
        end
        if jobId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, lplr, nil, { saveFarmActive = true })
        else
            TeleportService:Teleport(game.PlaceId, lplr, { saveFarmActive = true })
        end
    end

    local function requestDualHop(reason)
        if hopInProgress then return end
        hopInProgress = true
        notif('SaveShooter', 'Hop: ' .. (reason or 'sync') .. '...', 3)

        local existing = readHopFile()
        if existing and existing.jobId and existing.jobId ~= game.JobId then
            notif('SaveShooter', 'Seguindo hop do parceiro...', 3)
            task.wait(0.5)
            teleportTo(existing.jobId)
            return
        end

        local jobId = getEmptyServerId()
        writeHopFile(jobId)
        task.wait(3.5) -- tempo crítico pra outra conta ler
        teleportTo(jobId)
    end

    local function followHopIfAny()
        local data = readHopFile()
        if data and data.jobId and data.jobId ~= game.JobId then
            if hopInProgress then return true end
            hopInProgress = true
            notif('SaveShooter', 'Parceiro hopou. Seguindo...', 3)
            teleportTo(data.jobId)
            return true
        end
        return false
    end

    local function handlePartnerMissing()
        if hopInProgress then return end
        notif('SaveShooter', 'Parceiro sumiu. Aguardando hop file...', 3)
        for _ = 1, 20 do
            if followHopIfAny() then return end
            if getPartner() then return end
            task.wait(0.5)
        end
        requestDualHop('partner_missing')
    end

    local function getNextDeliveryOffset(partnerRoot, distance)
        local side = DELIVERY_SIDES[deliverySideIndex]
        deliverySideIndex = deliverySideIndex % #DELIVERY_SIDES + 1
        local cf = partnerRoot.CFrame
        if side == 'Front' then return cf.LookVector * distance, side
        elseif side == 'Back' then return -cf.LookVector * distance, side
        elseif side == 'Left' then return -cf.RightVector * distance, side
        else return cf.RightVector * distance, side end
    end

    local function tryGrabBallSafe(timeout)
        local start = tick()
        local pickup = getPickupRemote()
        while isFarming and SaveShooter.Enabled and not iHaveBall() and (tick() - start < timeout) do
            local ball = findBall()
            local root = getMyRoot()
            if not ball or not root or getBallOwner() then break end
            root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 0.5, 0))
            if pickup then pickup:FireServer(0) end
            task.wait(0.2)
        end
        return iHaveBall()
    end

    local function startAntiAFK()
        task.spawn(function()
            lplr.Idled:Connect(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightControl, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
            end)
            while isFarming and SaveShooter.Enabled do
                task.wait(30)
                if isFarming then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)
                end
            end
        end)
    end

    local function startKickDetector()
        SaveShooter:Clean(GuiService.ErrorMessageChanged:Connect(function()
            if isFarming and SaveShooter.Enabled and isCorrectAccount() then
                requestDualHop('kick')
            end
        end))
        task.spawn(function()
            while isFarming and SaveShooter.Enabled do
                task.wait(0.5)
                if not isCorrectAccount() then break end
                local prompt = CoreGui:FindFirstChild('RobloxPromptGui')
                if prompt then
                    local overlay = prompt:FindFirstChild('promptOverlay')
                    if overlay and (#overlay:GetChildren() > 0 or overlay:FindFirstChild('ErrorPrompt') or overlay:FindFirstChild('Prompt')) then
                        requestDualHop('kick_gui')
                        break
                    end
                end
            end
        end)
    end

    local function startLoop()
        task.spawn(function()
            local farmEnd = tick() + (FarmTime.Value * 60)
            local partnerWasHere = false

            while isFarming and SaveShooter.Enabled do
                task.wait(0.1)

                if followHopIfAny() then break end

                if not isCorrectAccount() then
                    task.wait(1)
                    continue
                end

                local partner = getPartner()
                if partner then
                    partnerWasHere = true
                elseif partnerWasHere then
                    handlePartnerMissing()
                    break
                end

                if not amInGame() then
                    local partnerColor = partner and partner.TeamColor and partner.TeamColor.Number
                    if partnerColor == HOME_TEAM_COLOR then
                        enterTeam(AWAY_TEAM_COLOR)
                    elseif partnerColor == AWAY_TEAM_COLOR then
                        enterTeam(HOME_TEAM_COLOR)
                    else
                        enterTeam(AWAY_TEAM_COLOR)
                    end
                    task.wait(2.5)
                    continue
                end

                if partner and partner.TeamColor and partner.TeamColor.Number ~= FANS_TEAM_COLOR then
                    if getMyTeamColor() == partner.TeamColor.Number then
                        enterTeam((getMyTeamColor() == HOME_TEAM_COLOR) and AWAY_TEAM_COLOR or HOME_TEAM_COLOR)
                        task.wait(2.5)
                        continue
                    end
                end

                if getStrangersCount() > MaxStrangers.Value or tick() >= farmEnd then
                    requestDualHop('full_or_time')
                    break
                end

                if not iHaveBall() then
                    tryGrabBallSafe(GrabTimeout.Value)
                else
                    local root = getMyRoot()
                    local partnerRoot = partner and partner.Character and partner.Character:FindFirstChild('HumanoidRootPart')
                    local ball = findBall()

                    if root and partnerRoot and ball then
                        local offset, sideName = getNextDeliveryOffset(partnerRoot, 4)
                        local deliveryPos = partnerRoot.Position + offset
                        deliveryPos = Vector3.new(deliveryPos.X, partnerRoot.Position.Y, deliveryPos.Z)
                        root.CFrame = CFrame.lookAt(deliveryPos, partnerRoot.Position)
                        task.wait(0.2)

                        if iHaveBall() then
                            local dir = (partnerRoot.Position - root.Position)
                            if dir.Magnitude < 0.05 then dir = partnerRoot.CFrame.LookVector end
                            dir = dir.Unit
                            if ShootRemote then
                                ShootRemote:FireServer(dir, ball.CFrame, 0.05, dir * 50, false, false, 'None')
                            end
                            deliveries = deliveries + 1
                            notif('SaveShooter', 'Entrega ' .. sideName .. ' #' .. deliveries, 2)
                        end
                    end
                    task.wait(CycleDelay.Value)
                end
            end
        end)
    end

    SaveShooter = vape.Categories.farmRSS:CreateModule({
        Name = 'SaveShooter',
        Function = function(callback)
            if callback then
                isFarming = true
                hopInProgress = false
                deliveries = 0
                deliverySideIndex = 1
                startAntiAFK()
                startKickDetector()
                startLoop()
            else
                isFarming = false
            end
        end
    })

    CycleDelay = SaveShooter:CreateSlider({Name = 'Delay Ciclo', Min = 0.5, Max = 3, Default = 1.2, Decimal = 100})
    GrabTimeout = SaveShooter:CreateSlider({Name = 'Grab Timeout', Min = 1, Max = 5, Default = 3})
    MaxStrangers = SaveShooter:CreateSlider({Name = 'Max Estranhos', Min = 0, Max = 10, Default = 0})
    FarmTime = SaveShooter:CreateSlider({Name = 'Farm Time', Min = 5, Max = 60, Default = 15})

    task.spawn(function()
        task.wait(5)
        local td = TeleportService:GetLocalPlayerTeleportData()
        if td and td.saveFarmActive and lplr.Name == MY_REQUIRED_NAME then
            task.wait(2)
            if not SaveShooter.Enabled then SaveShooter:Toggle() end
        end
    end)
end)

run(function()
    local DribbleAssist
    local MaxDistance
    local SlideDistance
    local AssistStrength
    local MaxPower -- só toques fracos (drible), não chute forte
    local MaxHeightAboveMe -- CHECK DE BOLA ALTA ESTILO AERIALREACH

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local RunService = game:GetService('RunService')

    local lplr = Players.LocalPlayer

    local ShootRemote = ReplicatedStorage:WaitForChild('Remotes'):WaitForChild('ShootTheBaII', 10)

    local cachedBall = nil

    -- Último toque capturado do ShootTheBaII
    local lastTouchDir = nil      -- Vector3 horizontal unit
    local lastTouchPower = 0
    local lastTouchTime = 0
    local TOUCH_MEMORY = 1.6     -- segundos lembrando a direção do toque

    local namecallHooked = false
    local oldNamecall = nil

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then
            return cachedBall
        end
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                return obj
            end
        end
        cachedBall = nil
        return nil
    end

    local function hasBall()
        local ball = findBall()
        if not ball then return false end
        local weld = ball:FindFirstChild('playerWeld')
        if not weld or not weld:IsA('Weld') then return false end
        local rootPart = weld.Part0
        return rootPart and rootPart.Parent == lplr.Character
    end

    local function flatUnit(v)
        if typeof(v) ~= 'Vector3' then return nil end
        local f = Vector3.new(v.X, 0, v.Z)
        if f.Magnitude < 0.05 then return nil end
        return f.Unit
    end

    -- HOOK ULTRA LIMPO E INVASIVO-ZERO (Impossível travar o chute)
    local function installShootHook()
        if namecallHooked or not hookmetamethod or not ShootRemote then return end
        namecallHooked = true

        oldNamecall = hookmetamethod(game, '__namecall', newcclosure(function(self, ...)
            local method = getnamecallmethod()

            if not checkcaller() and self == ShootRemote and method == 'FireServer' then
                local args = {...}
                local dir = flatUnit(args[1]) or flatUnit(args[4])
                local power = tonumber(args[3]) or 1

                if dir then
                    lastTouchDir = dir
                    lastTouchPower = power
                    lastTouchTime = tick()
                end
            end

            return oldNamecall(self, ...)
        end))
    end

    -- Fallback: direção da velocidade da bola (se o hook falhar)
    local function dirFromBallVelocity(ball)
        return flatUnit(ball.AssemblyLinearVelocity)
    end

    DribbleAssist = vape.Categories.realista:CreateModule({
        Name = 'DribbleAssist',
        Function = function(callback)
            if callback then
                installShootHook()

                local isSliding = false
                local slideDir = nil
                local slideEnd = nil
                local slideStart = 0

                DribbleAssist:Clean(RunService.RenderStepped:Connect(function()
                    if not lplr.Character or not lplr.Character.Parent then
                        isSliding = false
                        return
                    end

                    -- Com bola no pé = não mexe
                    if hasBall() then
                        isSliding = false
                        return
                    end

                    local char = lplr.Character
                    local root = char:FindFirstChild('HumanoidRootPart')
                    local hum = char:FindFirstChildOfClass('Humanoid')
                    if not root or not hum or hum.Health <= 0 then
                        isSliding = false
                        return
                    end

                    local ball = findBall()
                    if not ball then
                        isSliding = false
                        return
                    end

                    -- CHECK DE BOLA ALTA (ESTILO AERIAL REACH)
                    local heightAboveMe = ball.Position.Y - root.Position.Y
                    local isHighBall = heightAboveMe >= (MaxHeightAboveMe and MaxHeightAboveMe.Value or 2.5) or ball:FindFirstChild("PassBV") ~= nil
                    if isHighBall then
                        isSliding = false
                        return
                    end

                    local myPos = Vector3.new(root.Position.X, 0, root.Position.Z)
                    local ballPos = Vector3.new(ball.Position.X, 0, ball.Position.Z)
                    local dist = (ballPos - myPos).Magnitude

                    -------------------------------------------------
                    -- ARMA O SLIDE: só se tiver toque recente (direção do chute)
                    -------------------------------------------------
                    if not isSliding then
                        local recent = (tick() - lastTouchTime) <= TOUCH_MEMORY
                        local softTouch = lastTouchPower <= (MaxPower and MaxPower.Value or 0.55)

                        if not recent then return end
                        if not softTouch then return end -- ignora chute forte
                        if dist > MaxDistance.Value then return end

                        -- Direção PRINCIPAL = a do ShootTheBaII (para onde a bola foi)
                        local dir = lastTouchDir or dirFromBallVelocity(ball)
                        if not dir then return end

                        slideDir = dir
                        -- Destino = posição da bola + slide além na MESMA direção do toque
                        slideEnd = ballPos + slideDir * SlideDistance.Value
                        slideStart = tick()
                        isSliding = true
                    end

                    -------------------------------------------------
                    -- DURANTE O SLIDE: reto na direção do chute, passa da bola
                    -------------------------------------------------
                    if not slideDir or not slideEnd then
                        isSliding = false
                        return
                    end

                    -- Atualiza o fim do slide se a bola ainda estiver andando na mesma linha
                    local liveEnd = ballPos + slideDir * SlideDistance.Value
                    slideEnd = slideEnd:Lerp(liveEnd, 0.15)

                    local toEnd = Vector3.new(slideEnd.X - myPos.X, 0, slideEnd.Z - myPos.Z)
                    local distToEnd = toEnd.Magnitude

                    -- Já passou do ponto final?
                    local passed = (myPos - slideEnd):Dot(slideDir) > 0
                    local timeout = (tick() - slideStart) > 1.6

                    if passed or timeout or distToEnd < 0.25 then
                        isSliding = false
                        return
                    end

                    local moveDir = toEnd.Unit

                    -- Mescla com WASD (opcional, bem leve)
                    local playerDir = hum.MoveDirection
                    if playerDir.Magnitude > 0.05 then
                        local flat = Vector3.new(playerDir.X, 0, playerDir.Z)
                        if flat.Magnitude > 0.05 then
                            local w = math.clamp(AssistStrength.Value / 10, 0.25, 0.95)
                            moveDir = (flat.Unit * (1 - w) + moveDir * w)
                            if moveDir.Magnitude > 0.05 then
                                moveDir = moveDir.Unit
                            else
                                moveDir = slideDir
                            end
                        end
                    end

                    hum:Move(moveDir, false)
                end))
            else
                isSliding = false
            end
        end,
        Tooltip = 'Após toquezinho, anda reto na direção do ShootTheBaII e passa alguns studs da bola (slide).'
    })

    SlideDistance = DribbleAssist:CreateSlider({
        Name = 'Slide Past Ball',
        Min = 1, Max = 8, Default = 3, Decimal = 10,
        Suffix = function(val) return ' studs' end,
        Tooltip = 'Studs a continuar DEPOIS da bola, na direção do toque'
    })

    MaxPower = DribbleAssist:CreateSlider({
        Name = 'Max Touch Power',
        Min = 0.1, Max = 1.0, Default = 0.55, Decimal = 100,
        Suffix = function(val) return ' pwr' end,
        Tooltip = 'Só ativa em toques com power <= este valor (drible). Chute forte ignora.'
    })

    MaxHeightAboveMe = DribbleAssist:CreateSlider({
        Name = 'Max Ball Height',
        Min = 1.0, Max = 10.0, Default = 2.5, Decimal = 10,
        Suffix = function(val) return ' studs' end,
        Tooltip = 'Se a bola estiver acima desta altura em relação a você (estilo AerialReach), NÃO ativa'
    })

    AssistStrength = DribbleAssist:CreateSlider({
        Name = 'Assist Strength',
        Min = 1, Max = 10, Default = 8,
        Suffix = function(val) return '/10' end,
        Tooltip = 'Quanto segue a linha do toque vs seu WASD'
    })

    MaxDistance = DribbleAssist:CreateSlider({
        Name = 'Max Range',
        Min = 3, Max = 20, Default = 12,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end,
        Tooltip = 'Distância máxima da bola para iniciar o slide'
    })
end)

run(function()
    local AutoJuggle
    local AutoWalk
    local DangerRadius
    local MinPower
    local JuggleCooldown
    local FacingDot

    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local RunService = game:GetService('RunService')
    local UserInputService = game:GetService('UserInputService')
    local VIM = game:GetService('VirtualInputManager')
    local lplr = Players.LocalPlayer
    local mouse = lplr:GetMouse()

    local TACKLE_ANIM_ID = '14317040670'
    local DEKE_NAME_HINTS = { 'deke', 'dribble', 'croqueta', 'dirdrag', 'flick' }

    local Remotes = ReplicatedStorage:WaitForChild('Remotes')
    local ShootRemote = Remotes:FindFirstChild('ShootTheBaII')

    local PlayerModule = require(lplr.PlayerScripts:WaitForChild('PlayerModule'))
    local Controls = PlayerModule:GetControls()

    local cachedBall = nil
    local cachedWeld = nil
    local lastJuggleTime = 0
    local cachedWeakKickTrack = nil

    local isAutoWalking = false
    local autoWalkStartTime = 0
    local controlsDisabled = false
    local currentMoveVector = Vector3.zero

    local enemyCache = {}

    local charCache = {
        tackled = nil,
        debounce = nil,
        tackling = nil,
        header = nil,
        powerShooting = nil,
        dribbleDebounce = nil,
        freeKick = nil,
        penalty = nil,
        apg = nil,
        hpg = nil,
    }

    local function enableControlsBlock()
        if not controlsDisabled then
            pcall(function() Controls:Disable() end)
            controlsDisabled = true
        end
    end

    local function disableControlsBlock()
        if controlsDisabled then
            pcall(function() Controls:Enable() end)
            controlsDisabled = false

            task.defer(function()
                local pressedKeys = {
                    Enum.KeyCode.W,
                    Enum.KeyCode.A,
                    Enum.KeyCode.S,
                    Enum.KeyCode.D,
                }

                for _, key in ipairs(pressedKeys) do
                    if UserInputService:IsKeyDown(key) then
                        VIM:SendKeyEvent(false, key, false, game)
                        task.wait()
                        VIM:SendKeyEvent(true, key, false, game)
                    end
                end
            end)
        end
    end

    local function stopAutoWalk()
        isAutoWalking = false
        currentMoveVector = Vector3.zero
        disableControlsBlock()
    end

    local function loadWeakKickAnim(char)
        cachedWeakKickTrack = nil
        if not char then return end
        local hum = char:WaitForChild('Humanoid', 5)
        if not hum then return end

        local animsFolder = ReplicatedStorage:FindFirstChild('Animations')
        if not animsFolder then return end

        local rShootAnim = animsFolder:FindFirstChild('RShoot')
        if rShootAnim then
            local track = hum:LoadAnimation(rShootAnim)
            track.Priority = Enum.AnimationPriority.Action4
            cachedWeakKickTrack = track
        end
    end

    local function findBall()
        if cachedBall and cachedBall.Parent == workspace then return cachedBall end
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('BasePart') and obj.Name:lower() == 'ball' then
                cachedBall = obj
                return obj
            end
        end
        return nil
    end

    local function getBallWeld()
        local ball = findBall()
        if not ball then return nil end
        if not cachedWeld or cachedWeld.Parent ~= ball then
            cachedWeld = ball:FindFirstChild('playerWeld')
        end
        if not cachedWeld or not cachedWeld:IsA('Weld') then
            cachedWeld = nil
            return nil
        end
        return cachedWeld
    end

    local function iHaveBall()
        local ball = findBall()
        if not ball then return false end
        local weld = getBallWeld()
        if not weld or not weld.Part0 or weld.Part0.Parent ~= lplr.Character then return false end
        local creator = ball:FindFirstChild('creator')
        -- 7v7 às vezes atrasa creator; weld no seu char já basta
        if creator and creator.Value ~= nil and creator.Value ~= lplr then
            return false
        end
        return true
    end

    local function rebuildSelfCache()
        local char = lplr.Character
        if not char then return end
        local bools = char:FindFirstChild('Bools')
        local wsBools = workspace:FindFirstChild('Bools')

        charCache.tackled = bools and bools:FindFirstChild('Tackled')
        charCache.debounce = bools and bools:FindFirstChild('Debounce')
        charCache.tackling = bools and bools:FindFirstChild('Tackling')
        charCache.header = bools and bools:FindFirstChild('Header')
        charCache.powerShooting = bools and bools:FindFirstChild('PowerShooting')
        charCache.dribbleDebounce = bools and bools:FindFirstChild('dribbleDebounce')
        charCache.freeKick = wsBools and wsBools:FindFirstChild('FreeKick')
        charCache.penalty = wsBools and wsBools:FindFirstChild('Penalty')
        charCache.apg = wsBools and wsBools:FindFirstChild('APG')
        charCache.hpg = wsBools and wsBools:FindFirstChild('HPG')

        loadWeakKickAnim(char)
    end

    local function isDribbling()
        if charCache.dribbleDebounce and charCache.dribbleDebounce.Value then
            return true
        end

        local char = lplr.Character
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        if not hum then return false end

        for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
            local anim = track.Animation
            if not anim then continue end
            local name = string.lower(anim.Name or '')
            local id = string.lower(anim.AnimationId or '')
            for _, hint in ipairs(DEKE_NAME_HINTS) do
                if name:find(hint, 1, true) or id:find(hint, 1, true) then
                    return true
                end
            end
        end
        return false
    end

    -- Header REAL (não o spam do HeaderShield)
    local function isRealHeadering()
        if _G.__AerialReachActive then return true end
        if _G.__HeaderJump then return true end

        -- Se o HeaderShield está ligado, Header.Value true é só invulnerabilidade
        if _G.__HeaderShieldActive then
            return false
        end

        if charCache.header and charCache.header.Value then
            return true
        end
        return false
    end

    local function isTacklingOrTackled()
        if charCache.tackling and charCache.tackling.Value then return true end
        if charCache.tackled and charCache.tackled.Value then return true end
        return false
    end

    local function isFacingMe(enemyRoot, myRoot)
        if not enemyRoot or not myRoot then return false end

        local toMe = Vector3.new(
            myRoot.Position.X - enemyRoot.Position.X,
            0,
            myRoot.Position.Z - enemyRoot.Position.Z
        )
        if toMe.Magnitude < 0.05 then return true end
        toMe = toMe.Unit

        local look = enemyRoot.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude < 0.05 then return true end
        flatLook = flatLook.Unit

        local minDot = (FacingDot and FacingDot.Value or 2) / 10 -- default 0.20
        return flatLook:Dot(toMe) >= minDot
    end

    local function canJuggle()
        if not entitylib.isAlive then return false end
        if tick() - lastJuggleTime < JuggleCooldown.Value then return false end

        if isTacklingOrTackled() then return false end
        if isRealHeadering() then return false end
        if isDribbling() then return false end

        if charCache.debounce and charCache.debounce.Value then return false end
        if charCache.powerShooting and charCache.powerShooting.Value then return false end
        if charCache.freeKick and charCache.freeKick.Value then return false end
        if charCache.penalty and charCache.penalty.Value then return false end

        if charCache.apg and charCache.apg.Value == lplr then return false end
        if charCache.hpg and charCache.hpg.Value == lplr then return false end

        return true
    end

    local function getMyRoot()
        if entitylib and entitylib.character and entitylib.character.RootPart then
            return entitylib.character.RootPart
        end
        local char = lplr.Character
        return char and char:FindFirstChild('HumanoidRootPart')
    end

    local function getDirectionToPoint(targetPos)
        local myRoot = getMyRoot()
        if not myRoot then return Vector3.zero end

        local dir = Vector3.new(
            targetPos.X - myRoot.Position.X,
            0,
            targetPos.Z - myRoot.Position.Z
        )

        if dir.Magnitude < 0.1 then return Vector3.zero end
        return dir.Unit
    end

    -- [[ AUTOWALK = lógica da SUA versão (não cancela por HeaderShield) ]]
    local function autoWalkLoop()
        if not AutoJuggle.Enabled or not AutoWalk.Enabled or not isAutoWalking then
            if isAutoWalking or controlsDisabled then
                stopAutoWalk()
            end
            return
        end

        if not entitylib.isAlive then
            stopAutoWalk()
            return
        end

        -- Só cancela walk se você tomou/está dando carrinho (não header do shield)
        if isTacklingOrTackled() then
            stopAutoWalk()
            return
        end

        local elapsed = tick() - autoWalkStartTime

        -- Graça um pouco maior no 7v7 (weld/creator demoram mais a limpar)
        if elapsed > 0.35 and iHaveBall() then
            stopAutoWalk()
            return
        end

        if elapsed > 2.5 then
            stopAutoWalk()
            return
        end

        local ball = findBall()
        if not ball then
            stopAutoWalk()
            return
        end

        enableControlsBlock()
        currentMoveVector = getDirectionToPoint(ball.Position)
    end

    local function movementApplyLoop()
        if not AutoJuggle.Enabled or not AutoWalk.Enabled or not isAutoWalking then return end
        if not controlsDisabled then return end

        local char = lplr.Character
        if not char then return end

        local hum = char:FindFirstChildOfClass('Humanoid')
        if not hum then return end

        -- 7v7 às vezes zera Move; reaplica todo Stepped
        if currentMoveVector.Magnitude > 0.01 then
            hum:Move(currentMoveVector, false)
        end
    end

    local function shootTowardsMouse()
        if not canJuggle() or not iHaveBall() or not ShootRemote then return end
        local char = lplr.Character
        local root = char and char:FindFirstChild('HumanoidRootPart')
        local ball = findBall()
        if not root or not ball then return end

        lastJuggleTime = tick()

        if cachedWeakKickTrack then
            cachedWeakKickTrack:Play()
        end

        local mousePos = mouse.Hit and mouse.Hit.Position
        local aimDir

        if mousePos then
            aimDir = (mousePos - root.Position)
            aimDir = Vector3.new(aimDir.X, 0.05, aimDir.Z)
            if aimDir.Magnitude > 0.01 then
                aimDir = aimDir.Unit
            else
                aimDir = root.CFrame.LookVector
            end
        else
            aimDir = root.CFrame.LookVector
        end

        ShootRemote:FireServer(
            aimDir,
            ball.CFrame,
            MinPower.Value,
            aimDir * 1000,
            false,
            false,
            'None'
        )

        -- Inicia walk igual sua versão
        isAutoWalking = true
        autoWalkStartTime = tick()
        currentMoveVector = getDirectionToPoint(ball.Position)
        enableControlsBlock()
    end

    local function onEnemyAnimationPlayed(enemyRoot)
        if not AutoJuggle.Enabled or not iHaveBall() then return end
        if not canJuggle() then return end

        local myRoot = getMyRoot()
        if not myRoot then return end

        local dist = (enemyRoot.Position - myRoot.Position).Magnitude
        if dist > DangerRadius.Value then return end

        if not isFacingMe(enemyRoot, myRoot) then return end

        shootTowardsMouse()
    end

    local function disconnectEnemyConnections(cache)
        if not cache then return end
        if cache.animConnection then cache.animConnection:Disconnect() end
    end

    local function cacheEnemy(plr)
        if plr == lplr then return end

        local function setup(char)
            local hum = char:WaitForChild('Humanoid', 5)
            local root = char:WaitForChild('HumanoidRootPart', 5)
            if not hum or not root then return end

            local cache = {
                player = plr,
                char = char,
                root = root,
                animConnection = nil,
            }
            enemyCache[plr] = cache

            cache.animConnection = hum.AnimationPlayed:Connect(function(track)
                if not AutoJuggle.Enabled then return end

                local anim = track.Animation
                if not anim then return end

                local animId = anim.AnimationId or ''
                local animName = anim.Name or ''

                if animId:find(TACKLE_ANIM_ID) or animName:lower():find('tackle') then
                    if plr.Team ~= lplr.Team then
                        onEnemyAnimationPlayed(root)
                    end
                end
            end)
        end

        if plr.Character then task.spawn(setup, plr.Character) end

        plr.CharacterAdded:Connect(function(char)
            disconnectEnemyConnections(enemyCache[plr])
            enemyCache[plr] = nil
            task.wait(0.3)
            setup(char)
        end)
    end

    AutoJuggle = vape.Categories.realista:CreateModule({
        Name = 'AutoJuggle',
        Function = function(callback)
            if callback then
                if not ShootRemote then AutoJuggle:Toggle() return end
                rebuildSelfCache()
                enemyCache = {}
                for _, plr in ipairs(Players:GetPlayers()) do cacheEnemy(plr) end

                AutoJuggle:Clean(Players.PlayerAdded:Connect(cacheEnemy))
                AutoJuggle:Clean(Players.PlayerRemoving:Connect(function(plr)
                    disconnectEnemyConnections(enemyCache[plr])
                    enemyCache[plr] = nil
                end))
                AutoJuggle:Clean(lplr.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    stopAutoWalk()
                    rebuildSelfCache()
                    cachedBall = nil
                    cachedWeld = nil
                end))

                AutoJuggle:Clean(RunService.Heartbeat:Connect(autoWalkLoop))
                AutoJuggle:Clean(RunService.Stepped:Connect(movementApplyLoop))
            else
                stopAutoWalk()
                for _, cache in pairs(enemyCache) do
                    disconnectEnemyConnections(cache)
                end
                enemyCache = {}
                cachedBall = nil
                cachedWeld = nil
                if cachedWeakKickTrack then
                    cachedWeakKickTrack:Stop()
                end
                cachedWeakKickTrack = nil
            end
        end,
        Tooltip = 'AutoJuggle com AutoWalk compatível 4v4/7v7. Header do HeaderShield não cancela o walk.'
    })

    AutoWalk = AutoJuggle:CreateToggle({
        Name = 'Auto Walk',
        Default = true,
        Tooltip = 'Anda na direção da bola após o toque (funciona 4v4 e 7v7).'
    })

    DangerRadius = AutoJuggle:CreateSlider({
        Name = 'Raio de Detecção',
        Min = 5, Max = 30, Default = 18,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })

    FacingDot = AutoJuggle:CreateSlider({
        Name = 'Facing (Dot Min)',
        Min = -5, Max = 10, Default = 2, Decimal = 10,
        Suffix = function(val) return string.format(' %.2f', val / 10) end,
        Tooltip = '0.20 = cone largo | 0.50 = mais de frente | negativo = quase sempre'
    })

    MinPower = AutoJuggle:CreateSlider({
        Name = 'Força do Chute',
        Min = 0.01, Max = 0.20, Default = 0.03, Decimal = 100
    })

    JuggleCooldown = AutoJuggle:CreateSlider({
        Name = 'Cooldown do Módulo',
        Min = 0.1, Max = 1.0, Default = 0.4, Decimal = 100,
        Suffix = function(val) return 's' end
    })
end)
