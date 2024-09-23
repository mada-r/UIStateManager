--[[
	File: UIStateManager.lua
	Author(s): Refactor
	Created: 06/27/2023 @ 18:03:09
	Version: 1.0.0
--]]

--[ Root ]--

local UIStateManager = { }

--[ Exports & Types & Defaults ]--

export type StateProperties = {
	Hides: { string }?,
	Shows: { string }?,
	CoreGui: {
		Shows: { string }?,
		Hides: { string }?,
	}?,
	TouchControlsEnabled: boolean?,
	MovementEnabled: boolean?,
}

--[ Roblox Services ]--

local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

--[ Dependencies ]--

local Signal = require(script.Parent:WaitForChild("signal"))

--[ Object References ]--

local ControlModule

--[ Constants ]--

local COMPONENT_NOT_FOUND_STR = "[UIStateManager] UIComponent %s could not be found."
local MISSING_METHOD_STR = "[UIStateManager] UIComponent %s is missing method %s."
local STATE_NOT_FOUND_STR = "[UIStateManager]State %s could not be found."

--[ Variables ]--

local states = {}
local components = {}

local EventHooks = {
	StateChange = {},
	BeforeStateChange = {},
	AfterStateChange = {},
	CoreGuiChange = {},
}

--[ Shorthands ]--

--[ Local Functions ]--

local function runHook(hookName: string, newState: string, oldState: string?): ()
	if EventHooks[hookName] then
		for _, hook in EventHooks[hookName] do
			hook(newState, oldState)
		end
	end
end

local function hideComponents(state: string, uiState: {}): ()
	local toHide = uiState.Hides or {}
	local toShow = uiState.Shows or {}

	if table.find(toHide, "*") then
		for name, component in components do
			if name == state or table.find(toShow, name) ~= nil then
				continue
			end
			task.spawn(function()
				component:Hide()
			end)
		end
	else
		for _, name in toHide do
			if table.find(toShow, name) ~= nil then
				continue
			end

			-- check if an entry is a group "GROUPNAME_*"
			local isComponentGroup = name:sub(-2) == "_*"

			if isComponentGroup then
				-- support for component groups (ex: HUD_BottomBar)
				for id, component in components do
					if id:find(name:sub(1, -1)) then
						task.spawn(function()
							component:Hide()
						end)
					end
				end
			else
				local component = components[name]
				if not component then
					warn(COMPONENT_NOT_FOUND_STR:format(name))
				end

				if table.find(toShow, name) ~= nil then
					continue
				end

				task.spawn(function()
					component:Hide()
				end)
			end
		end
	end
end

local function showComponents(state: string, uiState: {}, props: { any }): ()
	local toShow = uiState.Shows or {}

	if table.find(toShow, "*") then
		for name, component in components do
			if name == state then
				continue
			end
			component:Show(props)
		end
	else
		for _, name in toShow do
			-- check if an entry is a group "GROUPNAME_*"
			local isComponentGroup = name:sub(-2) == "_*"

			if isComponentGroup then
				-- support for component groups (ex: HUD_BottomBar)
				for id, component in components do
					if id:find(name:sub(1, -1)) then
						component:Show(props)
					end
				end
			else
				local component = components[name]
				if not component then
					warn(COMPONENT_NOT_FOUND_STR:format(name))
				end

				component:Show(props)
			end
		end
	end
end

local function hideCoreUI(toHide: { string }): ()
	if table.find(toHide, "*") then
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	else
		for _, name in toHide do
			StarterGui:SetCoreGuiEnabled(name, false)
		end
	end
end

local function showCoreUI(toShow: { string }): ()
	if table.find(toShow, "*") then
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	else
		for _, name in toShow do
			StarterGui:SetCoreGuiEnabled(name, true)
		end
	end
end

--[ Public Functions ]--

--[[
   Set the UIState to the desired state.

   Parameters:
    - state (string): The name of the state to set.

   Returns:
    - success (boolean): Returns a state to inform if state was set or blocked. If false, state was blocked.
	- reason (string?): Returns the reason as to why the state was blocked.

   Description:
    This function sets the UIState to the specified state and performs associated operations,
    such as hiding/showing components based on the configuration of that state.
    If the specified state does not exist, a warning is issued and no state change occurs.
    If the state configuration includes CoreGui changes, the corresponding CoreGui components
    are shown/hidden accordingly.
]]
function UIStateManager:SetState(state: string, args: {}?): ()
	local uiState = states[state]

	if not uiState then
		warn(STATE_NOT_FOUND_STR:format(state))
		return false, `State {state} was not found.`
	end

	if self.currentState then
		local currentStateObject = states[self.currentState]
		local force = args and args.Force

		if not force and currentStateObject.Blocks then
			if table.find(currentStateObject.Blocks, "*") or table.find(currentStateObject.Blocks, state) then
				return false, `State was blocked by {self.currentState}`
			end
		end

		self.previousState = self.currentState
	end

	self.currentState = state

	-- reversed so we can get the prior state
	runHook("BeforeStateChange", self.previousState, state)

	-- new: disable movement if state has "MovementDisabled"
	local controls = ControlModule:GetControls()

	if uiState.MovementEnabled ~= nil then
		if uiState.MovementEnabled then
			controls:Enable()
		else
			controls:Disable()
		end
	else
		controls:Enable()
	end

	if args and args.Properties then
		self.stateProps = args.Properties
	end

	hideComponents(state, uiState)
	showComponents(state, uiState, args and args.Properties)

	runHook("AfterStateChange", state, self.previousState)

	if uiState.CoreGui then
		showCoreUI(uiState.CoreGui.Shows or {})
		hideCoreUI(uiState.CoreGui.Hides or {})
		runHook("CoreGuiChange", state, self.previousState)
	end

	if uiState.TouchControlsEnabled ~= nil then
		GuiService.TouchControlsEnabled = uiState.TouchControlsEnabled
	end

	runHook("StateChange", state, self.previousState)

	return true
end

--[[
   Register a new UIState with the specified name and properties.

   Parameters:
    - name (string): The name of the UIState to register.
    - properties (StateProperties): The properties and configuration for the UIState.

   Returns:
    - None

   Description:
    This function registers a new UIState with the given name and properties.
    If a UIState with the same name already exists, a warning is issued, and the registration is skipped.
    The UIState properties define the configuration for the state, including the components to hide/show
    and any CoreGui changes.
]]
function UIStateManager:RegisterState(name: string, properties: StateProperties): ()
	if states[name] then
		warn(`UIState {name} already exists.`)
		return
	end

	states[name] = properties
end

--[[
    Unregister a UIState with the specified name.

    Parameters:
    - name (string): The name of the UIState to unregister.

    Description:
]]
function UIStateManager:UnregisterState(name: string)
	if not states[name] then
		warn(`UIState {name} does not exist.`)
		return
	end

	if self.defaultState == name then
		warn(`Could not unbind default state {name}. Change default state and try again.`)
		return
	end

	if self:GetState() == name then
		self:SetDefault()
	end

	states[name] = nil
end

--[[
   Register a new UIComponent with the specified name and class.

   Parameters:
    - name (string): The name of the UIComponent to register.
    - class ({}): The class representing the UIComponent.

   Returns:
    - None

   Description:
    This function registers a new UIComponent with the given name and class.
    If a UIComponent with the same name already exists, a warning is issued, and the registration is skipped.
    The UIComponent class represents the behavior and functionality of the component.
    The class should include the methods :Hide() and :Show() to control the visibility of the component.
    Once registered, the UIComponent can be used in the configuration of UIStates to show or hide the component as needed.
]]
function UIStateManager:RegisterComponent(
	name: string,
	class: { [any]: any },
	defaultProperties: { any }?
): ()
	if components[name] then
		warn(`UIComponent {name} already exists.`)
		return
	end

	if not class.Show then
		warn(MISSING_METHOD_STR:format("Show"))
	end

	if not class.Hide then
		warn(MISSING_METHOD_STR:format("Hide"))
	end

	components[name] = class

	-- Try to show the component if it is registered after the state has been set.
	self:ShowComponent(name, defaultProperties or {})
end

--[[
   Unregister a UIComponent with the specified name.

   Parameters:
    - name (string): The name of the UIComponent to register.
    - hideOnUnregister: Should the components hide method be called before removing?

   Returns:
    - None

   Description:
    This function unregisters a UIComponent with the given name if it exists.
]]
function UIStateManager:UnregisterComponent(name: string, hideOnUnregister: boolean?)
	local component = components[name]
	if not component then
		warn(`Failed to unregister component {name}, component did not exist.`)
		return
	end

	if hideOnUnregister and component.Hide ~= nil then
		component:Hide()
	end

	components[name] = nil
end

--[[
	  Show a component by name.

		Parameters:
		- name (string): The name of the UIComponent to show.
		- props ({}): The properties to pass to the UIComponent.

		Returns:
		- None

		Description:
		Display a component by name. If the component is not whitelisted or the whitelist is empty, the component will not be shown.
]]
function UIStateManager:ShowComponent(name: string, props: { any })
	local component = components[name]
	if not component then
		warn(`Failed to show UIComponent {name}, component did not exist!`)
		return
	end

    local currentState = self:GetState()
	local allowedComponents = {}

	if currentState and currentState.Shows then
		allowedComponents = table.clone(currentState.Shows)

		if currentState.Whitelist then
			for _, whitelistedComponent in currentState.Whitelist do
				table.insert(allowedComponents, whitelistedComponent)
			end
		end
	end

	if props.BypassWhitelist or table.find(allowedComponents, name) then
		component:Show(props.Properties)
	end
end

function UIStateManager:HideComponent(name: string, props: { any })
	local component = components[name]
	if not component then
		warn(`Failed to hide UIComponent {name}, component did not exist!`)
		return
	end

	component:Hide()
end

--[[
   Returns the current UI State.

   Parameters:
    - None

   Returns:
    - string

   Description:
	If there is a current state this method will return it as a string.
]]
function UIStateManager:GetState()
	return self.currentState
end

--[[
   Revert to the previous UIState.

   Parameters:
    - None

   Returns:
    - None

   Description:
    This function reverts the UIState to the previous state if available.
    It checks if a previous state exists and calls the `SetState` function with the previous state as the parameter.
]]
function UIStateManager:PreviousState(): ()
	if self.previousState then
		self:SetState(self.previousState)
	end
end

--[[
	Set state to default state.

   Parameters:
    - None

   Returns:
    - boolean | nil `success state`
	- string? `failure reason`

   Description:
	Checks if a DefaultState is registered and if there is a default state it will set current state to it.
]]
function UIStateManager:SetDefault(): (boolean | nil, string?)
	if not self.defaultState then
		return nil, "Could not set state to default. No default state registered."
	end

	self:SetState(self.defaultState, {
		Force = true,
	})
	return true
end

--[[
	Registers a default state for `:SetDefault()` method.

   Parameters:
    - string `state name`

   Returns:
    - boolean | nil `success state`
	- string? `failure reason`

   Description:
]]
function UIStateManager:RegisterDefaultState(name: string): (boolean | nil, string?)
	if not states[name] then
		return nil, "Could not set default UI state. State did not exist."
	end

	self.defaultState = name
	return true
end

--[[
	Registers an event hook to listen for specific events triggered by the UIStateManager
	and execute custom callback functions in response.


	Valid States & Argument Order for Callback:
	- StateChange(newState, oldState)
	- BeforeStateChange (oldState, newState)
	- AfterStateChange (newState, oldState)
	- CoreGuiChange (newState, oldState)

	Parameters:
    - eventName (string): The name of the event hook.
    - callback (function): The callback function to be executed when the event occurs. It should accept a string parameter representing the state associated with the event.

   Returns:
    - None

   Description:
    This function allows you to register an event hook to listen for specific events triggered by the UIStateManager. The event hook can be used to execute custom logic or trigger additional actions in response to the events.

   Example:
    UIStateManager:RegisterEventHook("StateChange", function(state)
      print("UI State changed to:", state)
      -- Perform additional actions based on the state change
    end)
]]
function UIStateManager:RegisterEventHook(eventName: string, callback: (newState: string, oldState: string) -> ()): ()
	if EventHooks[eventName] then
		table.insert(EventHooks[eventName], callback)
	else
		warn(`Unsupported event hook {eventName}`)
	end
end

--[ Initializers ]--

function UIStateManager:Init()
	-- Default State to show hud elements for gameplay
	self:RegisterState("Gameplay", {
		Shows = { },
		Hides = { "*" },
		CoreGui = { Shows = { "*" } },
		TouchControlsEnabled = true,
	})

	self:RegisterDefaultState("Gameplay")

	-- Default State to hide all ui
	self:RegisterState("HideAll", {
		Hides = { "*" },
		Shows = {},
		CoreGui = {
			Hides = { "*" },
		},
		TouchControlsEnabled = false,
	})

	-- Signal for when state changes incase you prefer that over an event hook.
	self.StateChanged = Signal.new()

	self:RegisterEventHook("StateChange", function(newState, oldState)
		self.StateChanged:Fire(newState, oldState)
	end)

	-- Get ControlModule for TouchControlsEnabled
	ControlModule = shared(game.Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
end

--[ Return Job ]--
return UIStateManager