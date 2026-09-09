# Phân tích vòng 2 — Ma trận 117 toggle của Ten Hub

Bổ sung cho [`PHAN_TICH.md`](./PHAN_TICH.md). Vòng 1 phân tích **mã**, vòng 2 này phân tích **từng nút bấm** trong UI:
khi người dùng bật một toggle, tín hiệu có đi tới được vòng lặp thực thi hay không.

---

## 1. Phương pháp

1. Trích xuất **117 toggle** (`Tabs.X:AddToggle("ID", {...})`).
2. Tìm callback `OnChanged` tương ứng, lấy các biến được gán (`Flag = Value` / `_G.Flag = Value`).
3. Tìm **mọi** nơi biến đó được đọc trong toàn bộ 9.375 dòng (trừ chính dòng gán).
4. Phân loại:
   - **LIVE** — có vòng lặp/điều kiện bên ngoài đọc biến → tín hiệu đi tới nơi thực thi.
   - **ACTION** — không dùng biến, gọi remote ngay trong callback (nút kiểu "bấm 1 lần").
   - **DEAD** — biến được gán nhưng không ai đọc.
5. Chồng thêm các lỗi đã phát hiện ở vòng 1 (biến nil, hàm bị ghi đè) để có trạng thái **thật** của tính năng.

> ⚠️ **Cách hiểu kết quả:** `LIVE` chỉ có nghĩa là *dây nối đúng*. Tính năng vẫn có thể gãy vì lỗi bên trong
> (ví dụ Auto Sea 2 nối đúng, nhưng bên trong lại kiểm tra biến `World1` không tồn tại).

---

## 2. Kết quả tổng hợp

| Trạng thái | Số lượng | Ý nghĩa |
|---|---:|---|
| ✅ OK | **102** | Nối đúng và không tìm thấy lỗi |
| ❌ Gãy | **4** | Auto Sea 2, Auto Ship, Auto GhostShip, Auto CDK |
| ❌ Chết | **1** | Mirage (ESP) |
| ⚠️ Một phần | **3** | Auto Fram Fruit, Auto Fram Gun (mastery), Auto Hallow |
| ⚠️ Xung đột | **4** | 2 cặp toggle dùng chung 1 biến |
| 🔥 Rò rỉ | **1** | Receive Quest — vòng lặp không thoát |
| ▶ 1 lần | **2** | Buy Fruit, Trade Permanent Fruit (nút kiểu hành động) |
| **Tổng** | **117** | |

**Nhận xét quan trọng:** phần lớn hệ thống dây nối hoạt động tốt (105/117). Vấn đề nằm ở **phía thực thi** —
các lỗi biến nil và trùng định nghĩa hàm đã tìm ở vòng 1.

---

## 3. Phát hiện mới (chưa có trong báo cáo vòng 1)

### F1 🔥 "Receive Quest" mở vòng lặp vô hạn, tắt toggle không dừng được — dòng 8841

```lua
ToggleReceiveQuest:OnChanged(function(Value)
    _G.AutoReceiveQuest=Value
    if _G.AutoReceiveQuest then
        ...
        spawn(function()
            pcall(function()
                while wait() do                     -- ❌ không điều kiện thoát, không if <flag>
                    ...InvokeServer("RF/DragonHunter")   -- 2 remote mỗi chu kỳ
                end
            end)
        end)
    end
end)
```

- Mỗi lần **bật** toggle lại sinh ra **thêm** một vòng lặp chạy mãi mãi; **tắt toggle không dừng được**.
- Spam 2 remote `RF/DragonHunter` mỗi chu kỳ ⇒ rủi ro bị rate-limit/khoá tài khoản cao.
- **Sửa:**
  ```lua
  while _G.AutoReceiveQuest do
      ...
      task.wait(1)     -- thêm nhịp nghỉ
  end
  ```

### F2 ⚠️ Hai cặp toggle dùng chung một biến (bật 1 cái = bật cả 2)

| Biến | Toggle 1 | Toggle 2 | Hậu quả |
|---|---|---|---|
| `KillAura` | Auto Trial Human/Ghoul (L8043, tab Race) | Auto Kill Golems (L9255, tab Sea) | Bật một cái thì cả hai farm cùng chạy; tắt một cái tắt cả hai |
| `_G.AutoLevel` | Auto Fram Level (L2496, tab Fram) | Auto White Belt (L9029, tab Fram Other) | Bật "White Belt" sẽ **âm thầm bật cả Auto Farm Level** |

**Sửa:** tách biến, ví dụ `KillAuraTrial` / `KillAuraGolem`, `_G.AutoLevel` / `_G.AutoWhiteBelt`.

### F3 ❌ 4 toggle gãy hoàn toàn (nguyên nhân đã phân tích ở vòng 1)

| Toggle | Dòng | Nguyên nhân |
|---|---|---|
| Auto Sea 2 | 6862 | `World1` không tồn tại (phải là `Sea1`) |
| Auto Ship | 4460 | `CheckPirateBoat` bị định nghĩa thứ 2 (FishBoat) ghi đè + `spawn(Tween(...), 1)` sai cú pháp |
| Auto GhostShip | 4496 | Vòng lặp đọc `_G.bjirFishBoat`, toggle gán `_G.GhostShip` |
| Auto CDK | 5669 | `GetMaterial()` không tồn tại (hàm đúng là `CheckMaterial`), cộng thêm `pos`, `Sword`, `FarmPossEsp` nil |

*(Auto Yama (L5120) và Auto Tushita (L5136) có vòng lặp riêng, **không** phụ thuộc `GetMaterial` → vẫn chạy được.)*

### F4 ❌ 1 toggle chết: "Mirage" (ESP) — dòng 7646

Toggle gán `IslandMirageEsp`, nhưng `UpdateIslandMirageEsp()` (7662) lại kiểm tra `MirageIslandESP`
→ vòng lặp chạy nhưng không bao giờ tạo billboard. **Sửa:** đổi tên biến cho khớp.

### F5 ⚠️ 3 toggle chạy một phần

| Toggle | Dòng | Vấn đề |
|---|---|---|
| Auto Fram Fruit (mastery) | 2772 | Điều kiện thoát dùng `MasteryType` (nil) và `not X == 'Y'` (luôn false) → vòng `repeat` chỉ thoát theo điều kiện đầu |
| Auto Fram Gun (mastery) | 2781 | như trên |
| Auto Hallow | 5070 | `Tweem(` gõ nhầm `Tween(` → chuỗi mỏ đuốc dừng ở Torch2 |

### F6 ➕ Thiếu toggle: ESP rương (`ChestESP`)

`UpdateChestChams()` tồn tại (2 bản, dòng 1354 & 1645) và vòng lặp ESP chung có nhánh `if ChestESP then` (7534),
nhưng **không có toggle nào gán `ChestESP`** → tính năng không bao giờ bật được. Cần thêm nút "Chest" trong tab Fruit.

---

## 4. Ma trận đầy đủ 117 toggle

| Tab | Dòng | Toggle | Biến điều khiển | Nối dây | Ghi chú |
|---|---|---|---|---|---|
| Main | 2496 | Auto Fram Level | `_G.AutoLevel` | LIVE | ⚠️ XUNG ĐỘT chung flag `_G.AutoLevel` với *Auto White Belt* (L9029) |
| Main | 2554 | Auto Mob Aura | `_G.AutoNear` | LIVE | ✅ OK  |
| Main | 2772 | Auto Fram Fruit | `AutoFarmMasDevilFruit` | LIVE | ⚠️ MỘT PHẦN `MasteryType` nil + `not X=='Y'` → điều kiện thoát sai |
| Main | 2781 | Auto Fram Gun | `AutoFarmMasGun` | LIVE | ⚠️ MỘT PHẦN `MasteryType` nil + `not X=='Y'` → điều kiện thoát sai |
| Main | 3487 | Auto Fram Bone | `_G.AutoBone` | LIVE | ✅ OK  |
| Main | 3604 | Random Bone | `_G.AutoRandomBone` | LIVE | ✅ OK  |
| Main | 3644 | Auto Fram Cake | `_G.Cake` | LIVE | ✅ OK  |
| Main | 3771 | Spawner Cake Prince | `_G.SpawnCakePrince` | LIVE | ✅ OK  |
| Main | 3797 | Auto Farm Ectoplasm | `_G.Ectoplasm` | LIVE | ✅ OK  |
| Main | 3862 | Auto Fram Boss | `_G.AutoBoss` | LIVE | ✅ OK  |
| Main | 3923 | Auto Fram MateriaList | `_G.AutoMaterial` | LIVE | ✅ OK  |
| Main | 4628 | Auto Fram Elite | `_G.AutoElite` | LIVE | ✅ OK  |
| Main1 | 2599 | Auto Castle Raid | `_G.CastleRaid` | LIVE | ✅ OK  |
| Main1 | 2634 | Auto On Haki | `_G.EnableHakiFortress` | LIVE | ✅ OK  |
| Main1 | 2685 | Auto Chest | `_G.AutoCollectChest` | LIVE | ✅ OK  |
| Main1 | 2718 | Auto Berry and Hop | `_G.AutoCollectBerry` | LIVE | ✅ OK  |
| Main1 | 5120 | Auto Yama | `_G.AutoYama` | LIVE | ✅ OK  |
| Main1 | 5136 | Auto Tushita | `AutoTushita` | LIVE | ✅ OK  |
| Main1 | 5170 | Auto Holy | `_G.Auto_Holy_Torch` | LIVE | ✅ OK  |
| Main1 | 6094 | Auto Factory | `_G.Factory` | LIVE | ✅ OK  |
| Main1 | 6132 | Auto Fram Swan | `_G.Auto_FarmSwan` | LIVE | ✅ OK  |
| Main1 | 6254 | Auto Race V2 | `_G.AutoEvoRace` | LIVE | ✅ OK  |
| Main1 | 6862 | Auto Sea 2 | `_G.Auto_Sea2` | LIVE | ❌ GÃY `World1` không tồn tại (phải là `Sea1`) → không bao giờ chạy |
| Main1 | 6931 | Auto Sea 3 | `_G.Auto_Sea3` | LIVE | ✅ OK  |
| Main1 | 8799 | Auto Blaze Ember | `_G.AutoBlazeEmberFarm` | LIVE | ✅ OK  |
| Main1 | 8841 | Receive Quest | `_G.AutoReceiveQuest` | DEAD | 🔥 RÒ RỈ `while wait()` không có điều kiện thoát → spam remote mãi mãi, tắt toggle không dừng được |
| Main1 | 8898 | Auto Hydra Tree | `_G.AutoHydraTree` | LIVE | ✅ OK  |
| Main1 | 8998 | Collect Blaze Ember | `_G.AutoCollectFireFlowers` | LIVE | ✅ OK  |
| Main1 | 9029 | Auto White Belt | `_G.AutoLevel` | LIVE | ⚠️ XUNG ĐỘT chung flag `_G.AutoLevel` với *Auto Fram Level* (L2496); tự mở vòng lặp farm level |
| Sea | 3997 | Teleport Kitsune Island | `_G.TweenToKitsune` | LIVE | ✅ OK  |
| Sea | 4021 | Auto Collect Azure | `_G.CollectAzure` | LIVE | ✅ OK  |
| Sea | 4157 | Auto Tiki Island | `_G.AutoComeTiki` | LIVE | ✅ OK  |
| Sea | 4195 | Auto Hydra Island | `_G.AutoComeHydra` | LIVE | ✅ OK  |
| Sea | 4298 | Auto Terror Shark | `_G.AutoTerrorshark` | LIVE | ✅ OK  |
| Sea | 4351 | Auto Piranha | `_G.farmpiranya` | LIVE | ✅ OK  |
| Sea | 4386 | Auto Shark | `_G.AutoShark` | LIVE | ✅ OK  |
| Sea | 4423 | Auto FishCrew | `_G.AutoFishCrew` | LIVE | ✅ OK  |
| Sea | 4460 | Auto Ship | `_G.Ship` | LIVE | ❌ GÃY `CheckPirateBoat` bị định nghĩa 2 (FishBoat) ghi đè → tìm sai thuyền; `spawn(Tween(...),1)` sai cú pháp |
| Sea | 4496 | Auto GhostShip | `_G.GhostShip` | LIVE | ❌ GÃY Vòng lặp đọc `_G.bjirFishBoat`, toggle lại gán `_G.GhostShip` |
| Sea | 4744 | Teleport To Advanced Fruit Dealer | `_G.AutoTpAdvanced` | LIVE | ✅ OK  |
| Sea | 4765 | Teleport To Gear | `_G.TweenToGear` | LIVE | ✅ OK  |
| Sea | 4787 | Lock Moon + Use Race | `_G.AutoLockMoon` | LIVE | ✅ OK  |
| Sea | 8738 | Teleport Leviathan Island | `_G.TweenToFrozenDimension` | LIVE | ✅ OK  |
| Sea | 8782 | Collect Blaze Ember | `_G.AutoBlazeEmber` | LIVE | ✅ OK  |
| Sea | 9062 | Teleport Trial Race Draco | `_G.AutoTrialTeleport` | LIVE | ✅ OK  |
| Sea | 9100 | Teleport Volcano Island | `_G.TweenToPrehistoric` | LIVE | ✅ OK  |
| Sea | 9129 | Auto Event | `_G.AutoDefendVolcano` | LIVE | ✅ OK  |
| Sea | 9137 | Use Melee | `_G.UseMelee` | LIVE | ✅ OK  |
| Sea | 9145 | Use Sword | `_G.UseSword` | LIVE | ✅ OK  |
| Sea | 9153 | Use Gun | `_G.UseGun` | LIVE | ✅ OK  |
| Sea | 9255 | Auto Kill Golems | `KillAura` | LIVE | ⚠️ XUNG ĐỘT chung flag `KillAura` với *Auto Trial Human/Ghoul* (L8043) |
| Sea | 9277 | Collect Bone | `_G.AutoCollectBone` | LIVE | ✅ OK  |
| Sea | 9296 | Collect Egg | `_G.AutoCollectEgg` | LIVE | ✅ OK  |
| Item | 4819 | Auto Saber | `_G.Auto_Saber` | LIVE | ✅ OK  |
| Item | 4937 | Auto Pole V1 | `_G.Auto_PoleV1` | LIVE | ✅ OK  |
| Item | 4981 | Auto Saw | `_G.Auto_Saw` | LIVE | ✅ OK  |
| Item | 5025 | Auto Warden | `_G.Auto_Warden` | LIVE | ✅ OK  |
| Item | 5070 | Auto Hallow | `AutoHallowSycthe` | LIVE | ⚠️ MỘT PHẦN `Tweem(` gõ nhầm → dừng ở mỏ đuốc 2 |
| Item | 5194 | Auto Canvander | `_G.Auto_Canvander` | LIVE | ✅ OK  |
| Item | 5238 | Auto MusketeerHat | `_G.Auto_MusketeerHat` | LIVE | ✅ OK  |
| Item | 5326 | Auto Observation v2 | `_G.Auto_ObservationV2` | LIVE | ✅ OK  |
| Item | 5379 | Auto Rainbow Haki | `_G.Auto_RainbowHaki` | LIVE | ✅ OK  |
| Item | 5504 | Auto Skull Guitar | `_G.Auto_SkullGuitar` | LIVE | ✅ OK  |
| Item | 5625 | Auto Buddy | `_G.Auto_Buddy` | LIVE | ✅ OK  |
| Item | 5669 | Auto CDK | `_G.Auto_DualKatana` | LIVE | ❌ GÃY `GetMaterial()` không tồn tại (+ `pos`, `Sword`, `FarmPossEsp` nil) |
| Item | 6171 | Auto Rengoku | `_G.Auto_Regoku` | LIVE | ✅ OK  |
| Setting | 6309 | Auto On V3 | `_G.AutoT` | LIVE | ✅ OK  |
| Setting | 6323 | Auto On V4 | `_G.AutoY` | LIVE | ✅ OK  |
| Setting | 6339 | Auto Ken | `_G.AutoKen` | LIVE | ✅ OK  |
| Setting | 6358 | Save Set Spawn | `_G.SaveSpawn` | LIVE | ✅ OK  |
| Setting | 6424 | Bring Mob | `_G.BringMob` | LIVE | ✅ OK  |
| Setting | 6469 | Remove Notify | `RemoveNotify` | LIVE | ✅ OK  |
| Setting | 6483 | Remove White | `_G.WhiteScreen` | LIVE | ✅ OK  |
| Setting | 6494 | Skill Z | `SkillZ` | LIVE | ✅ OK  |
| Setting | 6499 | Skill X | `SkillX` | LIVE | ✅ OK  |
| Setting | 6504 | Skill C | `SkillC` | LIVE | ✅ OK  |
| Setting | 6509 | Skill V | `SkillV` | LIVE | ✅ OK  |
| Setting | 6514 | Skill F | `SkillF` | LIVE | ✅ OK  |
| Status | 6617 | Spam Join Job ID | `_G.Join` | LIVE | ✅ OK  |
| Stats | 6628 | Add Melee | `_G.Auto_Stats_Melee` | LIVE | ✅ OK  |
| Stats | 6633 | Add Default | `_G.Auto_Stats_Defense` | LIVE | ✅ OK  |
| Stats | 6638 | Add Sword | `_G.Auto_Stats_Sword` | LIVE | ✅ OK  |
| Stats | 6643 | Add Gun | `_G.Auto_Stats_Gun` | LIVE | ✅ OK  |
| Stats | 6648 | Add Fruit | `_G.Auto_Stats_Devil_Fruit` | LIVE | ✅ OK  |
| Player | 6738 | Teleport Player | `_G.TeleportPly` | LIVE | ✅ OK  |
| Player | 6760 | Walk on Water | `_G.WalkonWater` | LIVE | ✅ OK  |
| Player | 6776 | Speed Run | `InfAbility` | LIVE | ✅ OK  |
| Player | 6827 | No Clip | `_G.LOf` | LIVE | ✅ OK  |
| Player | 6845 | Enable PVP | `_G.EnabledPvP` | LIVE | ✅ OK  |
| Fruit | 7287 | Buy Fruit | — | ACTION | ▶ 1 lần thực hiện remote ngay khi bật, không có vòng lặp |
| Fruit | 7314 | Trade Permanent Fruit | — | ACTION | ▶ 1 lần thực hiện remote ngay khi bật, không có vòng lặp |
| Fruit | 7333 | Store Fruit | `_G.AutoStoreFruit` | LIVE | ✅ OK  |
| Fruit | 7451 | Random Fruit | `_G.Random_Auto` | LIVE | ✅ OK  |
| Fruit | 7465 | Teleport Fruit | `_G.CollectFruitTP` | LIVE | ✅ OK  |
| Fruit | 7481 | Collect Fruit | `_G.Tweenfruit` | LIVE | ✅ OK  |
| Fruit | 7498 | Player | `ESPPlayer` | LIVE | ✅ OK  |
| Fruit | 7504 | Fruit | `DevilFruitESP` | LIVE | ✅ OK  |
| Fruit | 7512 | Island | `IslandESP` | LIVE | ✅ OK  |
| Fruit | 7520 | Flower | `FlowerESP` | LIVE | ✅ OK  |
| Fruit | 7545 | Real Fruit | `RealFruitEsp` | LIVE | ✅ OK  |
| Fruit | 7646 | Mirage | `IslandMirageEsp` | DEAD | ❌ CHẾT gán `IslandMirageEsp`, hàm lại đọc `MirageIslandESP` → không làm gì |
| Raid | 7707 | Buy Chip | `_G.Auto_Buy_Chips_Dungeon` | LIVE | ✅ OK  |
| Raid | 7726 | Star Raid | `_G.Auto_StartRaid` | LIVE | ✅ OK  |
| Raid | 7761 | Auto Fram Raid | `AutoNextIsland` | LIVE | ✅ OK  |
| Raid | 7819 | Thá»©c Tá»‰nh | `AutoAwakenAbilities` | LIVE | ✅ OK  |
| Raid | 7833 | Collect Fruit 1M | `_G.Autofruit` | LIVE | ✅ OK  |
| Raid | 7949 | Auto Raid Law | `Auto_Law` | LIVE | ✅ OK  |
| Race | 8043 | Auto Trial Human/Ghoul | `KillAura` | LIVE | ⚠️ XUNG ĐỘT chung flag `KillAura` với *Auto Kill Golems* (L9255) |
| Race | 8048 | Auto Trial | `_G.AutoQuestRace` | LIVE | ✅ OK  |
| Race | 8168 | Kill Player Trial | `_G.AutoKillTrial` | LIVE | ✅ OK  |
| Race | 8198 | Auto Train | `AutoFarmRace` | LIVE | ✅ OK  |
| Race | 8225 | Upgrade Gear | `_G.AutoUpgrade` | LIVE | ✅ OK  |
| Shop | 6214 | Auto Collect Haki | `_G.Auto_Buy_Enchancement` | LIVE | ✅ OK  |
| Shop | 6232 | Auto Sword Legend | `_G.BuyLengendSword` | LIVE | ✅ OK  |
| Misc | 8671 | Rejoin Server | `_G.AutoRejoin` | LIVE | ✅ OK  |
| Misc | 8710 | Anti Band | `_G.AntiBand` | LIVE | ✅ OK  |
| Misc | 9345 | Tu doi server khi gap Admin | `_G.AntiStaffHop` | LIVE | ✅ OK  |
---

## 5. Bổ sung vào kế hoạch sửa (P0)

```lua
-- F1: Receive Quest (dòng 8853) — thêm điều kiện thoát
-  while wait() do
+  while _G.AutoReceiveQuest do
+      task.wait(1)

-- F2a: Auto Kill Golems (dòng 9255) — tách flag
-  KillAura=Value
+  KillAuraGolem=Value
   -- và trong vòng lặp dòng 9258:  if KillAura then  ->  if KillAuraGolem then

-- F2b: Auto White Belt (dòng 9029) — tách flag
-  _G.AutoLevel=Value
+  _G.AutoWhiteBelt=Value
   -- và dòng 9044:  while _G.AutoLevel do  ->  while _G.AutoWhiteBelt do

-- F4: ESP Mirage (dòng 7665) — khớp tên
-  if MirageIslandESP then
+  if IslandMirageEsp then

-- F6: thêm toggle ESP rương (tab Fruit, sau dòng 7520)
+  local ToggleEspChest = Tabs.Fruit:AddToggle("ToggleEspChest",
+      {Title="Chest", Description="", Default=false})
+  ToggleEspChest:OnChanged(function(Value) ChestESP=Value end)
+  Options.ToggleEspChest:SetValue(false)
```

---

*Ma trận được sinh tự động từ phân tích tĩnh; cột "Nối dây" phản ánh việc biến có được đọc ở nơi khác hay không,
không phải kết quả chạy thực tế trong Roblox.*
