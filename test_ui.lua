-- Test Fluent UI tối thiểu - dùng để kiểm tra executor có hỗ trợ Fluent không
if not game:IsLoaded() then game.Loaded:Wait() end

local Fluent = nil
local urls = {
    "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua",
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua"
}
for _, url in ipairs(urls) do
    local ok, result = pcall(function()
        local code = game:HttpGet(url)
        return loadstring(code)()
    end)
    if ok and result then
        Fluent = result
        print("Loaded Fluent from: "..url)
        break
    end
end

if not Fluent then
    warn("Không tải được Fluent!")
    return
end

local Window = Fluent:CreateWindow({
    Title = "Test UI",
    SubTitle = "Kiểm tra nút có hiện không",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Test", Icon = "check" }),
    Setting = Window:AddTab({ Title = "Setting", Icon = "settings" })
}

local Options = Fluent.Options

Tabs.Main:AddParagraph({
    Title = "Test",
    Content = "Nếu bạn thấy dòng này và các nút bên dưới thì Fluent hoạt động OK"
})

local Toggle = Tabs.Main:AddToggle("TestToggle", { Title = "Nút Test", Default = false })
Toggle:OnChanged(function(Value)
    print("Toggle value:", Value)
    Fluent:Notify({
        Title = "Test",
        Content = "Toggle = "..tostring(Value),
        Duration = 3
    })
end)

pcall(function() Options.TestToggle:SetValue(false) end)

Tabs.Main:AddButton({
    Title = "Button Test",
    Description = "Bấm thử",
    Callback = function()
        Fluent:Notify({ Title="Test", Content="Button hoạt động!", Duration=3 })
    end
})

Tabs.Main:AddDropdown("TestDropdown", {
    Title = "Dropdown Test",
    Values = {"A", "B", "C"},
    Multi = false,
    Default = 1
})

Window:SelectTab(1)

Fluent:Notify({
    Title = "Test UI",
    Content = "Nếu thấy thông báo này + thấy nút ở tab Test là OK",
    Duration = 5
})

print("Test UI loaded - hãy bấm qua lại các Tab và kéo xuống xem có nút không")
