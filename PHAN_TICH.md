# Báo cáo phân tích mã nguồn — Ten Hub (script Blox Fruits)

**Repo:** `mncuadaigmailcom/ba` · **Nhánh:** `arena/01a08393-ba` · **Commit gốc:** `6b02525`
**Ngày phân tích:** 09/09/2026 · **Phương pháp:** phân tích tĩnh (AST + heuristic), **không** chạy trong Roblox.

---

## 0. Tóm tắt nhanh (TL;DR)

| Hạng mục | Kết quả |
|---|---|
| Kích thước | `script.js` 9.375 dòng / 446 KB (Lua/Luau) · `index.html` 9.346 dòng / 489 KB (bản mirror cũ) |
| Cú pháp | ✅ Parse toàn bộ **không lỗi** (luaparse, grammar 5.3). Lỗi duy nhất dưới grammar 5.1 là `break;` trong đoạn code decompile của game (Luau hợp lệ) |
| Quy mô UI | 16 tab · **118 toggle** · **78 nút** · 10 dropdown · 4 input · 1 slider · 35 section |
| Lỗi làm **tính năng chết/gãy** | **19 lỗi** (nhóm A+B dưới đây), trong đó ~10 lỗi do **biến không hề tồn tại (nil)** |
| Code trùng | **~748 dòng** nằm trong 15 khối trùng lặp; **13 hàm bị định nghĩa 2–4 lần** |
| Vòng lặp | **147** `spawn(function() while wait() ...` + **118** callback toggle tự mở vòng lặp riêng |
| Rủi ro lớn nhất | `loadstring(game:HttpGet(...))()` không kiểm tra → RCE; 253 lần `CommF_:InvokeServer` → rủi ro khoá tài khoản |

> **Kết luận:** script chạy được (đã được vá 22 lỗi ở commit trước), nhưng còn **ít nhất 9 tính năng đang chết hoặc gãy hoàn toàn** do biến nil/sai tên, và **2 tính năng bị hỏng do trùng tên hàm global** (Auto Ship, Auto GhostShip). Kiến trúc hiện tại (mỗi toggle một vòng lặp + `_G.` rải rác) là nguồn gốc của hầu hết lỗi còn lại.

---

## 1. Phương pháp & công cụ

| Bước | Công cụ | Kết quả |
|---|---|---|
| Kiểm tra cú pháp | `luaparse` (npm), grammar Lua 5.3 | Parse OK, 669 node gốc |
| Phân tích scope/phạm vi | AST walk tự viết (Node.js) | 121 global được khai báo · **27 global đọc nhưng không hề tồn tại** · **36 chỗ đọc trước khi khai báo** |
| Tìm code trùng | Hash cửa sổ 15 dòng + so sánh thân hàm cùng tên | 15 nhóm trùng (lớn nhất 227 dòng ×2) · 13 hàm định nghĩa lặp |
| Đếm pattern rủi ro | regex | 147 spawn, 156 while, 357 `wait()`, 155 pcall, 263 InvokeServer, 439 toạ độ hard-code |
| So sánh phiên bản | `diff` `index.html` (giải mã HTML) ↔ `script.js` | 415 dòng cũ bị xoá / 454 dòng mới thêm |

**Giới hạn:** đây là phân tích tĩnh. Một số lỗi chỉ biểu hiện khi chạy (phụ thuộc vào phiên bản game, executor, tốc độ mạng). Mọi số dòng trích dẫn là của `script.js` tại commit hiện tại.

---

## 2. Kiến trúc tổng thể

### 2.1 Luồng khởi động

```
game:IsLoaded()                                  (dòng 11)
  └─ _G.FastAttack = true → Module.FastAttack    (dòng 13-260, hook RE/RegisterAttack + RegisterHit)
       ├─ Chờ LocalPlayer, đọc Remotes/CommF_, CommE, workspace
       ├─ Tự chọn team (_env.Team) - đã pcall     (dòng 158-192)
       └─ Anti-AFK (Idled → VirtualUser)          (dòng 262-267)
  └─ Tải Fluent từ GitHub (thử 3 lần, có pcall)  (dòng 206-228)
  └─ Fluent:CreateWindow → 16 tab                (dòng 230-258)
  └─ Khoá PlaceId (Sea1/Sea2/Sea3), sai game → error()  (dòng 260-261)
  └─ Định nghĩa dữ liệu: CheckLevel (663 dòng), CheckBossQuest (251), MaterialMon (93)
  └─ Engine: Tween/Tween2/BKP/to/EquipTool/AttackNoCoolDown
  └─ Hàng trăm toggle + vòng lặp spawn farm/ESP/noclip
```

### 2.2 Thành phần chính

| Thành phần | Vị trí | Ghi chú |
|---|---|---|
| **Fast Attack** | 13–260 | Hook remote `RE/RegisterAttack`, `RegisterHit`; có cache `_ENV.rz_FastAttack` |
| **Dữ liệu level/quest** | 269–1275 | `CheckLevel()` 663 dòng if-elseif theo level; `CheckBossQuest()` 251 dòng; `MaterialMon()` |
| **Engine di chuyển** | 2114–2346 | `Tween` (TweenService), `Tween2`, `BKP`, `to()`, `EquipTool`, `AttackNoCoolDown` |
| **Chống xung đột** | 2157 & 2174 | 2 điều kiện OR khổng lồ (~50 flag) để bật NoClip/BodyVelocity — **trùng nhau** |
| **ESP / Chams** | 1276–2130, 7497–7700 | 4 bản copy gần giống hệt nhau (Player/DevilFruit/Chest/Flower/RealFruit/Island/Mirage) |
| **Farm** | 2450–9300 | Auto level, mastery, bone, cake, boss, material, elite, sea event, raid, race v4, item quest |
| **Shop / Misc** | 6230–9359 | 40+ nút mua vũ khí/chiến đấu, redeem code, đổi server, team |

### 2.3 Số liệu tĩnh

| Chỉ số | Giá trị | Nhận xét |
|---|---|---|
| Hàm global / tổng số hàm | 58 / 160 | Rất ít hàm, phần lớn là code UI tuyến tính |
| `spawn(function` | 147 | Mỗi tính năng 1 thread polling riêng |
| `while` / `repeat` | 156 / 90 | Polling thay vì event-driven |
| `wait()` / `task.wait()` | 357 / 51 | `wait()` deprecated, không đồng bộ với frame |
| `pcall` | 155 | 36/147 vòng lặp **không** có pcall ở phần đầu → 1 lỗi làm chết cả tính năng |
| `CommF_:InvokeServer` | 253 | Remote spam → dễ bị phát hiện/rate-limit |
| `CFrame.new(...)` hard-code | 439 | Gãy ngay khi game cập nhật map |
| `Connect` / `Disconnect` | 10 / 1 | Hầu như không bao giờ ngắt kết nối |
| API exploit | `sethiddenproperty` 11, `fireclickdetector` 21, `hookfunction` 5 | Bề mặt bị phát hiện lớn |

---

## 3. Lỗi chi tiết

### 3.1 Nhóm A — Biến không tồn tại (luôn `nil`) → tính năng chết hoặc văng lỗi

| # | Biến | Dòng | Hậu quả | Sửa |
|---|---|---|---|---|
| A1 | `GetMaterial(...)` | 5703, 5712, 5721, 5730, 5739, 5748, 5757, 5949, 6087 | **Không hề được định nghĩa**. Hàm tương tự là `CheckMaterial(matname)` (dòng 2195). Mỗi lần gọi → `attempt to call a nil value` → **Auto Dual Katana / Yama / Tushita gãy hoàn toàn** | Thay `GetMaterial(` → `CheckMaterial(` (9 chỗ) |
| A2 | `pos` | 5770 | `Tween(v.HumanoidRootPart.CFrame*pos)` → `pos` nil → lỗi toán học. (Biến `pos` **có** tồn tại nhưng là `local` ở dòng 7781 → không nhìn thấy ở đây) | `Tween(v.HumanoidRootPart.CFrame*CFrame.new(0,0,-2))` (như các chỗ khác) |
| A3 | `Tweem(...)` | 5939 | **Gõ nhầm** `Tween`. Toàn bộ chuỗi mỏ đuốc Hell Dimension (Auto Hallow) dừng lại ở Torch2 | `Tweem(` → `Tween(` |
| A4 | `FarmPossEsp` | 5848, 5849 | Dùng như một CFrame nhưng không bao giờ được gán → Auto Yama giai đoạn 2 gãy | Thay bằng `game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame` |
| A5 | `World1` | 6876 | `if MyLevel>=700 and World1 then` — `World1` không tồn tại (biến đúng là `Sea1`, dòng 261) → **Auto Sea 2 không bao giờ chạy** | `World1` → `Sea1` |
| A6 | `MirageIslandESP` | 1985, 7665 | Toggle "Mirage" (7646) gán `IslandMirageEsp`, còn hàm lại đọc `MirageIslandESP` → **ESP Mirage chết** (khác tên) | Đổi `MirageIslandESP` → `IslandMirageEsp` |
| A7 | `ChestESP` | 1358, 1649, 7534 | **Không toggle nào gán biến này** → ESP rương không bao giờ bật (dù `UpdateChestChams` tồn tại 2 bản) | Thêm toggle `Chest` gán `ChestESP=true`, hoặc xoá nhánh chết |
| A8 | `RealFruitESP` | 1478, 1508, 1538, 1769, 1799, 1829, **7545** | Toggle gán `RealFruitEsp` (chữ `p` thường) → nhánh `RealFruitESP` trong vòng lặp ESP chung (7545) và 2 bản `UpdateRealFruitChams` (1475/1766) **không bao giờ chạy** | Đổi `RealFruitESP` → `RealFruitEsp` (hoặc xoá 2 bản hàm thừa ở 1475/1766) |
| A9 | `MobESP`, `SeaESP`, `NpcESP`, `AuraESP`, `LADESP`, `GearESP`, `MirageIslandESP` | 1861, 1900, 1939, 2018, 2051, 2084 | 6 vòng lặp ESP (1858–1974, 2015–2110) chạy liên tục nhưng điều kiện **luôn nil** → tốn CPU, không làm gì cả. (`LADESP` còn sai chính tả so với `UpdateLSDESP`) | Xoá 4 khối `spawn` chết, hoặc gắn toggle cho từng flag |
| A10 | `SelectMonster` | 272…(87 chỗ) | Biến chọn quái thủ công **không bao giờ được gán** → 87 phép so sánh vô nghĩa trong `CheckLevel` | Xoá `or SelectMonster=="..."` hoặc gắn với dropdown |
| A11 | `SelectBoss` | 934…(37 chỗ) | Tương tự, 37 so sánh chết trong `CheckBossQuest` | Xoá hoặc gắn dropdown boss |
| A12 | `Mon` | 2307, 3966 | `elseif Mon=="God's Guard"` trong `to()` — `Mon` không tồn tại → **nhánh dịch chuyển God's Guard chết** | Dùng `NameMon` (đang được gán trong `CheckLevel`) |
| A13 | `Auto_Raid` | 2302 | `not Auto_Raid` → nil → luôn `true`; raid không bị loại khỏi nhánh teleport | Gán từ toggle raid (`_G.Auto_Raid`) |
| A14 | `Triple_A` | 6240 | Flag rác, không ai gán | Xoá |
| A15 | `Sword` | 5769 | `EquipTool(Sword)` → `EquipTool(nil)` → không trang bị gì | `EquipTool(SelectWeapon)` hoặc `EquipTool("Tushita")` |
| A16 | `_G.StopTween`, `_G.StopTween2` | 2143, 2122 | **Không có chỗ nào gán** → không bao giờ huỷ được Tween đang chạy | Thêm nút/phím tắt gán `_G.StopTween=true` |
| A17 | `_G.bjirFishBoat` | 4512, 4534 | Vòng lặp thuyền ma đọc flag này, trong khi toggle "Auto GhostShip" gán `_G.GhostShip` → **Auto GhostShip chết hoàn toàn** | Đổi `_G.bjirFishBoat` → `_G.GhostShip` |
| A18 | `_G.UseSkill` / `_G.UseSkillGun` | 2806… | Được gán nội bộ (2862/2864) nhưng không có toggle bật/tắt → người dùng không điều khiển được | Thêm toggle trong tab Setting |
| A19 | `MasteryType` | 2878…(13 chỗ) | Không tồn tại **và** sai ưu tiên toán tử (xem B1) | Bỏ điều kiện hoặc dùng `TypeMastery` |

### 3.2 Nhóm B — Trùng định nghĩa / sai phạm vi (scoping)

| # | Lỗi | Dòng | Hậu quả | Sửa |
|---|---|---|---|---|
| B1 | **Trùng hàm `CheckPirateBoat`** | 4465 & 4501 | Định nghĩa 2 (danh sách `FishBoat`) **ghi đè** định nghĩa 1 (`PirateGrandBrigade`, `PirateBrigade`) → **Auto Ship tìm sai thuyền** | Đổi tên: `CheckPirateShip()` / `CheckFishBoat()`, hoặc truyền danh sách vào tham số |
| B2 | `spawn(Tween(...), 1)` | 4484 | **Sai cú pháp:** `Tween(...)` được gọi ngay, `spawn` nhận `nil` → lỗi trong `pcall`, vòng lặp Auto Ship không bao giờ hoàn thành | `spawn(function() Tween(v.Engine.CFrame*CFrame.new(0,-20,0)) end)` |
| B3 | `AutoFarmRace` đọc ở 2157/2174 nhưng `local` khai báo ở **8199** | 2157, 2174 | Lua phân giải tên lúc biên dịch → đọc **global** `AutoFarmRace` (luôn nil). Điều kiện chống xung đột **không bao giờ thấy** tính năng này → 2 farm cùng chạy, giành teleport | Xoá `local` (thành global) hoặc chuyển khai báo lên trước dòng 2157 |
| B4 | `round()` dùng ở 1298 trước khi `local function round` (1312) | 1298 | Nếu bản `UpdateIslandESP` (1276) được gọi → lỗi nil call. Hiện **chưa vỡ** vì bản thứ 2 (1567) ghi đè, nhưng là bug tiềm ẩn | Xoá bản copy 1276–1308 (bản 1567 đã thay thế) |
| B5 | `to()` định nghĩa 2 lần (khác thân) | 2292 & 2300 | Bản 1 mất tác dụng; bản 2 tham chiếu `Mon` (nil, xem A12) | Gộp thành 1 hàm, dùng `NameMon` |
| B6 | 11 hàm định nghĩa lặp: `isnil` ×4, `round` ×4, `UpdateIslandESP`/`UpdatePlayerChams`/`UpdateChestChams`/`UpdateDevilChams`/`UpdateFlowerChams`/`UpdateRealFruitChams` ×2, `tpToMyBoat` ×2, `equipAndUseSkill` ×2 | 1276–2130, 7497–7700 | Bản sau ghi đè bản trước; 2 bản `UpdateIslandESP`/`UpdatePlayerChams` **khác nhau** (màu chữ, font) → bản đầu là dead code; người sửa nhầm bản sẽ không thấy kết quả | Xoá các bản copy, giữ 1 bản; tốt nhất gom thành module `ESP.lua` |
| B7 | `FindFirstChild("BodyClip"):Destroy()` | 2179–2180 | Khi không có BodyClip → index nil → **lỗi mỗi frame** (bị pcall nuốt) → nhánh tắt NoClip không bao gỡ được | `local b=hrp:FindFirstChild("BodyClip"); if b then b:Destroy() end` |
| B8 | `not X == 'Y'` (sai ưu tiên) | 2878, 2920, 2968, 3016, 3061, 3100, 3189, 3231, 3279, 3335, 3374, 3411 | Lua hiểu là `(not X) == 'Y'` → **luôn false** → vòng lặp mastery chỉ thoát theo điều kiện đầu | `X ~= 'Y'` |
| B9 | Điều kiện chống xung đột khổng lồ trùng 2 lần | 2157 & 2174 | ~50 flag × 2 bản; mỗi lần thêm tính năng phải sửa 2 nơi; 5 flag trong danh sách (`AutoFarmRace`, `AutoEvoRace`, `AutoBartilo`, `Musketeer`, `AutoFarmRaceQuest`) **không bao giờ đúng** | Tạo hàm `local function AnyFarmActive()` duyệt một bảng flag |
| B10 | `SelectBoss`, `AutoBartilo`, `Musketeer`, `AutoFarmRaceQuest` chỉ xuất hiện trong điều kiện chống xung đột | 2157/2174 | Không toggle nào gán → điều kiện vô nghĩa | Xoá khỏi danh sách |

### 3.3 Nhóm C — Độ bền & hiệu năng

| # | Vấn đề | Số lượng | Tác động | Đề xuất |
|---|---|---|---|---|
| C1 | Mỗi callback `OnChanged` chứa `while ... do wait()` | **118** | Bật/tắt nhanh → **nhiều vòng lặp chồng nhau** cùng farm/teleport → giật lag, quái bị kéo loạn | Chuyển sang 1 vòng lặp trung tâm đọc flag |
| C2 | Vòng lặp `spawn(function() while wait() do` | **147** | ~147 thread polling liên tục, mỗi thread lại gọi `game:GetService` và `pairs(workspace.Enemies)` mỗi chu kỳ | Gom theo nhóm (1 loop farm, 1 loop ESP, 1 loop noclip) |
| C3 | Vòng lặp không có `pcall` ở phần đầu | **36/147** | Một lỗi (quái mất, `Character` nil lúc respawn) → chết vòng lặp, tính năng "tắt ngầm" | Bọc thân vòng lặp trong `pcall` + `task.wait()` |
| C4 | `wait()` deprecated | 357 | Không đồng bộ frame, throttle kém | `task.wait()` |
| C5 | Toạ độ `CFrame.new(...)` hard-code | **439** | Game cập nhật map là gãy hàng loạt | Lấy vị trí từ `workspace._WorldOrigin.Locations` (script đã có sẵn `Locations`) |
| C6 | Kết nối sự kiện không ngắt | 10 `Connect` / **1** `Disconnect` | Rò rỉ khi rejoin/respawn | Lưu connection và `Disconnect()` khi tắt toggle |
| C7 | Lỗi encoding (mojibake) | dòng 7819 `Title="Thá»©c Tá»‰nh"` | Hiển thị sai tiếng Việt trong UI | Sửa lại thành `Thức Tỉnh` |
| C8 | `error()` khi không phải Blox Fruits | 261 | Hành vi đúng, nhưng người dùng thấy lỗi đỏ khó hiểu | Giữ + thông báo rõ (đã có notification) |
| C9 | Mã lấy từ module nội bộ game (deobfuscate) | 7189–7225 (`v129`, `p15`…) | Phụ thuộc cấu trúc internal, dễ lỗi khi game cập nhật | Bọc toàn bộ trong `pcall` (đã bọc một phần) |

### 3.4 Nhóm D — Bảo mật & rủi ro tài khoản

| # | Rủi ro | Vị trí | Mức | Ghi chú / khắc phục |
|---|---|---|---|---|
| D1 | **`loadstring(game:HttpGet(url))()`** tải Fluent từ GitHub release "latest", không checksum, không pin version | 206–219 | 🔴 Cao | Nếu repo/tài khoản GitHub bị xâm nhập hoặc MITM → **chạy mã tuỳ ý** trong executor của người dùng. Nên pin tag cụ thể + so hash, hoặc nhúng Fluent vào repo |
| D2 | Vi phạm Điều khoản Roblox | toàn bộ | 🔴 Cao | Đây là script exploit: auto farm, ESP, teleport, chỉnh `Data.Level` (dòng 7207–7217), spam 253 `InvokeServer` → nguy cơ khoá tài khoản vĩnh viễn |
| D3 | Remote spam | 253 `CommF_:InvokeServer`, 12 `FireServer` | 🟠 TB | Không có throttle/cooldown; dễ bị server flag. Thêm khoảng nghề tối thiểu giữa 2 lần gọi |
| D4 | Bề mặt bị phát hiện | `sethiddenproperty` ×11, `fireclickdetector` ×21, `hookfunction` ×5, `getrawmetatable` | 🟠 TB | Các API này bị nhiều anti-cheat giám sát |
| D5 | Tự đổi server khi gặp Admin | Misc (toggle) | 🟡 Thấp | Chức năng né admin; tự nó cũng là tín hiệu vi phạm |
| D6 | Ghi trực tiếp `Data.Level/Exp/Beli` | 7194–7225 | 🔴 Cao | Sửa giá trị phía client thường bị server ghi đè **và** là hành vi bị phát hiện mạnh nhất |
| D7 | Lộ thông tin | `setclipboard` JobId, Discord/Youtube/Facebook | 🟡 Thấp | Bình thường với hub, nhưng nên ghi rõ trong README |

### 3.5 Nhóm E — Code trùng & bảo trì

- **~748 dòng** nằm trong 15 khối trùng lặp: lớn nhất 227 dòng ×2 (1339–1565, khối Chams/ESP), 47 ×2 (3658–3704), 32 ×2 (1297–1328), 32 ×2 (4575–4606), 27 ×4 (1987–2013, tạo BillboardGui), 16–17 ×6 (2860–2876 / 3171–3187, mastery).
- **13 hàm bị định nghĩa 2–4 lần** (xem B6).
- Hai điều kiện chống xung đột ~50 flag viết tay, trùng 2 nơi (2157, 2174) — mỗi lần thêm tính năng phải sửa 2 chỗ rất dễ sót.
- Không có cấu trúc module: 9.375 dòng trong một file, 2.278 dòng ở cột 0 (global namespace), **121 biến/hàm global** → rủi ro ghi đè (đây chính là nguyên nhân của B1/B5).

---

## 4. So sánh `index.html` ↔ `script.js`

`index.html` **không phải** bản dựng của `script.js`: nó là bản mirror cũ (dạng `<pre>` HTML-escape) của phiên bản **trước** khi vá 22 lỗi.

| | `index.html` (cũ) | `script.js` (mới) |
|---|---|---|
| Dòng | 9.346 | 9.375 |
| Khác biệt | — | **415 dòng cũ bị xoá, 454 dòng mới thêm** (`diff`) |
| Tải Fluent | 1 lần, không pcall → hỏng mạng là script chết | Thử 3 lần, kiểm tra `#code>5000`, báo lỗi rõ ràng |
| Chọn team | `repeat ... until player.Team` → **treo vĩnh viễn** nếu không hiện UI | `getgenv().Team` + `pcall`, không chờ |
| Sai game | `game:Shutdown()` (đóng game!) | Thông báo + `error()` |
| Hook | `hookfunction(...)` trần, không pcall | Bọc `pcall` |
| Encoding | **Mojibake** ("KhĂƒÂƒĂ‚Â´ng tĂƒÂƒĂ‚Â¬m...") | Tiếng Việt không dấu, một chỗ còn mojibake (7819) |
| Biến | Có `World2`/`Sea1=false` ghi đè sai | `Sea1/Sea2/Sea3` đúng |

**Khuyến nghị:** tạo `index.html` bằng script sinh tự động từ `script.js` (escape HTML) trong cùng một bước commit, hoặc xoá `index.html` để tránh người dùng tải nhầm bản cũ.

---

## 5. Kế hoạch sửa theo ưu tiên

### P0 — Sửa ngay (tính năng đang gãy), ~20 dòng thay đổi

```lua
-- 1. Auto Dual Katana / Yama / Tushita  (dòng 5703,5712,5721,5730,5739,5748,5757,5949,6087)
-  if GetMaterial("Alucard Fragment")==0 then
+  if CheckMaterial("Alucard Fragment")==0 then

-- 2. Auto Hallow – mỏ đuốc  (dòng 5939)
-  Tweem(game:GetService("Workspace").Map.HellDimension.Torch2.CFrame)
+  Tween(game:GetService("Workspace").Map.HellDimension.Torch2.CFrame)

-- 3. Auto Sea 2  (dòng 6876)
-  if MyLevel>=700 and World1 then
+  if MyLevel>=700 and Sea1 then

-- 4. ESP Mirage  (dòng 1985, 7665)
-  if MirageIslandESP then
+  if IslandMirageEsp then

-- 5. ESP Real Fruit trong vòng lặp chung  (dòng 7545)
-  if RealFruitESP then
+  if RealFruitEsp then

-- 6. Auto GhostShip  (dòng 4512, 4534)
-  if _G.bjirFishBoat then
+  if _G.GhostShip then

-- 7. Auto Ship – sai thuyền & sai spawn  (dòng 4465 đổi tên; dòng 4484)
-  function CheckPirateBoat()            -- bản 1 (PirateGrandBrigade)
+  function CheckPirateShip()
-  spawn(Tween(v.Engine.CFrame*CFrame.new(0,-20, 0)), 1)
+  spawn(function() Tween(v.Engine.CFrame*CFrame.new(0,-20,0)) end)

-- 8. Di chuyển đến quái  (dòng 5769-5770)
-  EquipTool(Sword)  /  Tween(v.HumanoidRootPart.CFrame*pos)
+  EquipTool(SelectWeapon)  /  Tween(v.HumanoidRootPart.CFrame*CFrame.new(0,0,-2))

-- 9. Kéo quái Auto Yama  (dòng 5848-5849)
-  (v.HumanoidRootPart.Position-FarmPossEsp.Position).magnitude<=300
+  (v.HumanoidRootPart.Position-game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude<=300
```

### P1 — Chống xung đột & độ bền (nửa ngày)

1. Thay 2 điều kiện OR khổng lồ (2157, 2174) bằng:
   ```lua
   local ActiveFlags = { "AutoEvoRace","Auto_Sea3","Auto_Sea2","AutoLevel","AutoBoss", ... }
   local function AnyFarmActive()
       for _, f in ipairs(ActiveFlags) do if _G[f] then return true end end
       return AutoFarmRace or AutoFarmMasDevilFruit or AutoFarmMasGun
   end
   ```
2. Sửa 12 chỗ `not X == 'Y'` → `X ~= 'Y'`.
3. Bọc `FindFirstChild("BodyClip"):Destroy()` bằng kiểm tra nil (B7).
4. Thêm `pcall` cho 36 vòng lặp còn trống; đổi `wait()` → `task.wait()`.

### P2 — Tái cấu trúc (1–2 ngày)

1. **Một bảng flag tập trung** thay vì 112 biến `_G.` rải rác:
   ```lua
   local Flags = setmetatable({}, {__index=function() return false end})
   ```
2. **Một scheduler duy nhất** thay cho 147 + 118 vòng lặp: duyệt `Features = { {flag="AutoLevel", fn=FarmLevel}, ... }` theo `task.wait()`.
3. **Xoá ~750 dòng trùng** và 13 hàm định nghĩa lặp; gom ESP thành 1 module.
4. Thay toạ độ hard-code bằng đọc từ `workspace._WorldOrigin.Locations` (đã có sẵn biến `Locations`).

### P3 — Bảo mật & vận hành

1. Pin version Fluent + kiểm tra hash trước `loadstring` (hoặc nhúng thẳng file Fluent vào repo).
2. Thêm throttle cho `InvokeServer` (ví dụ tối thiểu 0,15 s giữa 2 lần gọi cùng remote).
3. Thêm `Disconnect()` cho connection khi tắt toggle.
4. Sinh `index.html` tự động từ `script.js`, sửa mojibake dòng 7819 (`Thức Tỉnh`).
5. Thêm README ghi rõ: yêu cầu executor, rủi ro khoá tài khoản, cách báo lỗi.

---

## 6. Phụ lục — Danh sách đầy đủ

### 6.1 Biến đọc nhưng không hề tồn tại (từ AST scope analysis)

`GetMaterial`, `pos`(5770), `Tweem`, `FarmPossEsp`, `World1`, `MirageIslandESP`, `ChestESP`, `RealFruitESP`, `MobESP`, `SeaESP`, `NpcESP`, `AuraESP`, `LADESP`, `GearESP`, `SelectMonster`, `SelectBoss`, `Mon`, `Auto_Raid`, `Triple_A`, `Sword`(5769), `AutoBartilo`, `Musketeer`, `AutoFarmRaceQuest`, `AutoEvoRace`, `_G.bjirFishBoat`, `_G.StopTween`, `_G.StopTween2`, `_G.Clip2`
*(Loại trừ: `debug`, `firetouchinterest`, `NumberSequenceKeypoint` — API hợp lệ của Roblox/executor; `_G.UseSkill`/`_G.UseSkillGun`, `_G.FastAttackVxeze_Mode`, `_G.Job`, `_G.IsFlying` — được gán ở nơi khác, chỉ là thiếu toggle điều khiển.)*

### 6.2 Hàm bị định nghĩa lặp

`isnil` ×4 (1309/1600/1975/7655) · `round` ×4 (1312/1603/1978/7658) · `UpdateIslandESP` ×2 (1276/1567, khác nhau) · `UpdatePlayerChams` ×2 (1316/1607, khác nhau) · `UpdateChestChams` ×2 · `UpdateDevilChams` ×2 · `UpdateFlowerChams` ×2 · `UpdateRealFruitChams` ×2 · `to` ×2 (2292/2300, khác nhau) · **`CheckPirateBoat` ×2 (4465/4501, khác nhau → bug)** · `tpToMyBoat` ×2 · `equipAndUseSkill` ×2

### 6.3 Phân bổ UI (16 tab)

| Tab | Nội dung chính |
|---|---|
| Info | Thông tin tài khoản, link Discord/YouTube/Facebook |
| Fram | Auto level, Mob aura, Mastery (fruit/gun), Bone, Cake Prince, Ectoplasm, Boss, Material, Elite |
| Fram Other | Castle Raid, Auto Sea 2/3, Yama, Tushita, Holy, Factory, Swan, Race V2, Draco craft |
| Sea Event | Kitsune, thuyền (Terror Shark/Piranha/Shark/FishCrew/Ship/GhostShip), Mystic Island, Leviathan, Volcano |
| Stack Fram | Saber, PoleV1, Saw, Warden, Hallow, Canvander, Musketeer, ObservationV2, Rainbow Haki, Skull Guitar, Buddy, Dual Katana, Rengoku |
| Setting | V3/V4/Ken, Save spawn, Bring mob, Remove notify/white, 5 skill toggle |
| Status / Stats | Join/Copy Job ID, cộng điểm Melee/Defense/Sword/Gun/Fruit |
| Player / Teleport / Visual | Teleport player, Walk on water, Speed, NoClip, PVP; dịch chuyển sea/đảo; chỉnh Level/EXP/Beli/Fragment |
| Fruit | Mua/trữ/teleport/random trái; ESP Player/Fruit/Island/Flower/Real Fruit/Mirage |
| Raid / Race / Shop / Misc | Chip raid, Awakening (mojibake); Trial v4, Train race; ~40 nút mua vật phẩm; team, redeem code, titles, đổi server |

---

*Tài liệu được tạo bằng phân tích tĩnh; các khẳng định về "tính năng chết" dựa trên việc biến không bao giờ được gán giá trị trong toàn bộ file — cần xác nhận lại bằng một lần chạy thực tế với executor.*
