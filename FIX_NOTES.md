# Ten Hub - Fix UI không thấy nút

## Vấn đề bạn gặp
> Bật script lên hiện menu nhưng không thấy nút bật tính năng

## Nguyên nhân gốc
1. **Fluent UI bản mới đổi API**: bản cũ chỉ gọi `CreateWindow` rồi thôi, bản mới cần `Window:SelectTab(1)` nếu không sẽ để trắng
2. **Size Window quá nhỏ**: `Size=UDim2.fromOffset(555,320)` -> chiều cao 320px không đủ chứa 10+ toggle, Fluent không tự scroll nếu thiếu SaveManager/InterfaceManager
3. **Options:SetValue gây crash**: `Options.ToggleLevel:SetValue(false)` gọi ngay sau khi tạo toggle, nếu Fluent chưa kịp tạo Options sẽ error -> toàn bộ code phía sau không chạy, nên các tab sau trống
4. **Idled:connect deprecated**: executor mới dùng `Connect` viết hoa, `connect` cũ sẽ lỗi
5. **World1 chưa định nghĩa**: trong Auto Sea2 check `World1` thay vì `Sea1` -> lỗi logic, nhưng cũng gây pcall fail
6. **Trùng ID Toggle**: `MyToggle` dùng cho Spam Join Job ID, trùng với ID nội bộ của Fluent có thể gây xung đột
7. **Fluent chỉ thử 1 CDN**: github.com/.../releases/latest/download/main.lua hay bị chặn HTML -> menu không load

## Đã sửa trong script.js
- Thêm 3 URL fallback cho Fluent + thử 2 lần mỗi URL
- Load thêm SaveManager & InterfaceManager để Fluent render ổn định
- Tăng Size lên `580,460` thay vì `555,320`
- Thêm Icon cho mỗi Tab (`info`, `swords`, `package`...) để đảm bảo render
- Thêm `Window:SelectTab(1)` bắt buộc
- Wrap tất cả `Options.xxx:SetValue` trong `pcall`
- Khởi tạo biến toàn cục `TypeMastery`, `KillPercent`, `ChooseWeapon`, `SelectWeapon`, `SelectIsland`, `SelectChip` tránh nil
- Sửa `Idled:connect` -> `Idled:Connect`
- Sửa `World1` -> `Sea1`
- Đổi `MyToggle` -> `SpamJoinJobId`
- Xóa hàm `to(P)` trùng lặp, chỉ giữ bản hoàn thiện có xử lý entrance
- Thêm Notify: "Menu da tai xong! Neu khong thay nut, thu bam vao cac Tab ben trai."

## Cách test
1. Dùng executor mới (Delta, Fluxus, Codex, Arceus X)
2. Chạy script mới:
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/mncuadaigmailcom/ba/main/script.js"))()
-- hoặc nếu bạn đang ở branch arena:
loadstring(game:HttpGet("https://raw.githubusercontent.com/mncuadaigmailcom/ba/arena/01a0839c-ba/script.js"))()
```
3. Nếu vẫn không thấy:
- Thử `test_ui.lua` trong repo này (chỉ tạo 1 toggle test)
- Bấm vào từng Tab bên trái, kéo xuống (Fluent có scroll)
- Bấm nút tròn ảnh `rbxassetid://91347148253026` góc trái để toggle menu (LeftControl)
- Kiểm tra F9 console có lỗi gì không

## Nếu vẫn lỗi
- Executor của bạn có thể không hỗ trợ Fluent. Thử dùng bản Fluent raw:
  `https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua`
- Thử tắt Acrylic: đã tắt sẵn `Acrylic=false`
- Thử đổi Theme: `Darker` -> `Dark`

## File khác
- `test_ui.lua`: test Fluent tối thiểu
- `script.js.bak`: bản gốc trước khi fix
