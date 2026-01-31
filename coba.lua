--==[ LOOP REJOIN v2 – HOP TERUS + ANTI SERVER SAMA 2 JAM ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

----------------------------------------------------------------------
-- 🔧 KONFIGURASI
----------------------------------------------------------------------
local CONFIG = {
    DelayBeforeCheck      = 8,     -- tunggu world load dulu sebelum cek (detik)

    MinPlayersInfo        = 3,     -- hanya untuk info/log (tidak menghentikan hop)
    HopDelayRame          = 15,    -- jeda hop kalau server >= MinPlayersInfo
    HopDelaySepi          = 6,     -- jeda hop kalau server <  MinPlayersInfo

    VisitedFile           = "server-hop-visited.json",
    VisitedTTLSeconds     = 7200,  -- 2 jam: jangan betah di server yang sama
    RejoinIfVisitedDelay  = 4,     -- kalau ketemu server yang pernah dikunjungi → rejoin cepat

    MaxTeleportFailures   = 3,     -- kalau teleport gagal berkali-kali, stop spam
}

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local placeId      = game.PlaceId
local currentJobId = game.JobId

print("[LoopRejoin] Start. PlaceId:", placeId, "| JobId sekarang:", currentJobId)

----------------------------------------------------------------------
-- 🧠 SISTEM VISITED (ANTI SERVER SAMA)
----------------------------------------------------------------------
local visited = {}  -- [jobId] = timestamp

local function loadVisited()
    if not readfile then
        warn("[LoopRejoin] Executor tidak punya readfile, visited NON-AKTIF (masih tetap hop, tapi tanpa anti-duplicate).")
        return
    end

    local ok, content = pcall(function()
        return readfile(CONFIG.VisitedFile)
    end)

    if not ok or not content or content == "" then
        -- tidak apa-apa, anggap belum ada file
        return
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)

    if okDecode and type(data) == "table" then
        visited = data
    else
        warn("[LoopRejoin] File visited corrupt, reset baru.")
        visited = {}
    end
end

local function saveVisited()
    if not writefile then return end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(visited)
    end)

    if not ok then
        warn("[LoopRejoin] Gagal encode JSON visited:", encoded)
        return
    end

    pcall(function()
        writefile(CONFIG.VisitedFile, encoded)
    end)
end

local function cleanupVisited()
    local now = os.time()
    local ttl = CONFIG.VisitedTTLSeconds
    local removed = 0

    for jobId, ts in pairs(visited) do
        if type(ts) ~= "number" or now - ts > ttl then
            visited[jobId] = nil
            removed += 1
        end
    end

    if removed > 0 then
        print(("[LoopRejoin] Hapus %d server lama dari visited."):format(removed))
        saveVisited()
    end
end

local function isRecentlyVisited(jobId)
    if not jobId then return false end
    local ts = visited[jobId]
    if not ts then return false end
    return (os.time() - ts) <= CONFIG.VisitedTTLSeconds
end

local function markVisited(jobId)
    if not jobId then return end
    visited[jobId] = os.time()
    saveVisited()
end

----------------------------------------------------------------------
-- 🔢 FUNGSI JUMLAH PLAYER
----------------------------------------------------------------------
local function getPlayerCount()
    local count = 0
    -- pcall biar aman kalau ada error aneh
    pcall(function()
        count = #Players:GetPlayers()
    end)
    return count
end

----------------------------------------------------------------------
-- 🚀 FUNGSI TELEPORT WRAPPER (BIAR ADA PROTEKSI GAGAL)
----------------------------------------------------------------------
local teleportFailures = 0

local function safeTeleport(what, arg1, arg2)
    local ok, err = pcall(function()
        if what == "place" then
            TeleportService:Teleport(arg1)
        elseif what == "instance" then
            TeleportService:TeleportToPlaceInstance(arg1, arg2)
        end
    end)

    if not ok then
        teleportFailures += 1
        warn("[LoopRejoin] Teleport gagal ke", what, ":", err,
             "| total gagal:", teleportFailures)

        if teleportFailures >= CONFIG.MaxTeleportFailures then
            warn("[LoopRejoin] Sudah", teleportFailures,
                 "kali gagal teleport. Stop spam, cek koneksi / Roblox.")
        end
    else
        teleportFailures = 0
    end

    return ok
end

----------------------------------------------------------------------
-- 🚀 LOGIKA UTAMA
----------------------------------------------------------------------
task.wait(CONFIG.DelayBeforeCheck)

loadVisited()
cleanupVisited()

-- 1) Kalau server ini sudah pernah dikunjungi dalam 2 jam terakhir → REJOIN CEPAT
if isRecentlyVisited(currentJobId) then
    warn("[LoopRejoin] Server ini SUDAH ada di visited (<= 2 jam). Rejoin cepat...")

    task.wait(CONFIG.RejoinIfVisitedDelay)

    safeTeleport("place", placeId)
    return
end

-- 2) Server baru (belum visited ≤ 2 jam): tandai, cek player, lalu tetap hop
markVisited(currentJobId)

local count = getPlayerCount()
print(("[LoopRejoin] Server saat ini: %d pemain"):format(count))

local hopDelay
if count >= CONFIG.MinPlayersInfo then
    print(("[LoopRejoin] ✅ Rame (>= %d). Akan hop lagi setelah %d detik.")
        :format(CONFIG.MinPlayersInfo, CONFIG.HopDelayRame))
    hopDelay = CONFIG.HopDelayRame
else
    print(("[LoopRejoin] ⚠️ Sepi (< %d). Akan hop lagi lebih cepat (%d detik).")
        :format(CONFIG.MinPlayersInfo, CONFIG.HopDelaySepi))
    hopDelay = CONFIG.HopDelaySepi
end

task.wait(hopDelay)

print("[LoopRejoin] 🔁 Teleport ke server lain...")
safeTeleport("place", placeId)
