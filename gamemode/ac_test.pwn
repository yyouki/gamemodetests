#include <ac>

#define AC_STAGE_STORE_CAPACITY (MAX_PLAYERS)

new AC_StageSavedAccountId[AC_STAGE_STORE_CAPACITY];
new AC_StageSavedScore[AC_STAGE_STORE_CAPACITY];
new AC_StageSavedStrikes[AC_STAGE_STORE_CAPACITY];
new AC_StageSavedScoreDecayAt[AC_STAGE_STORE_CAPACITY];
new AC_StageSavedStrikeDecayAt[AC_STAGE_STORE_CAPACITY];
new AC_StageSavedLastStrikeAt[AC_STAGE_STORE_CAPACITY];
new AC_StageVehicleId[MAX_PLAYERS];
new AC_StageLastVehicleTraceTick[MAX_PLAYERS];
new AC_StageVehicleTraceSampleCount;
new bool:AC_StageVehicleTraceLimitNotified;
new AC_StageLogCaptureOwner = INVALID_PLAYER_ID;

// Runtime counters verify V2 callback delivery without exposing account/session identifiers.
new AC_TestEvidenceV2Count[MAX_PLAYERS];
new AC_TestStrikeV2Count[MAX_PLAYERS];
new AC_TestLastEvidenceSequence[MAX_PLAYERS];
new AC_TestLastEvidenceTimestamp[MAX_PLAYERS];
new AC_TestLastStrikeSequence[MAX_PLAYERS];
new bool:AC_TestLastStrikeLinked[MAX_PLAYERS];

#define AC_STAGE_MAX_VEHICLE_TRACE_SAMPLES (3600)

#define AC_STAGE_TEST_INTERIOR_ID (17)
#define AC_STAGE_TEST_WORLD_ID (9000)

new bool:AC_StageInteriorActive[MAX_PLAYERS];
new AC_StageSavedInterior[MAX_PLAYERS];
new Float:AC_StageSavedInteriorX[MAX_PLAYERS];
new Float:AC_StageSavedInteriorY[MAX_PLAYERS];
new Float:AC_StageSavedInteriorZ[MAX_PLAYERS];

new bool:AC_StageWorldActive[MAX_PLAYERS];
new AC_StageSavedWorld[MAX_PLAYERS];

new bool:AC_StageSpectating[MAX_PLAYERS];
new bool:AC_StagePendingSpectateRestore[MAX_PLAYERS];
new AC_StageSpectateSavedInterior[MAX_PLAYERS];
new AC_StageSpectateSavedWorld[MAX_PLAYERS];
new Float:AC_StageSpectateSavedX[MAX_PLAYERS];
new Float:AC_StageSpectateSavedY[MAX_PLAYERS];
new Float:AC_StageSpectateSavedZ[MAX_PLAYERS];

stock AC_StageFindSavedSlot(accountid)
{
    if (accountid <= 0)
        return -1;

    for (new slot; slot < AC_STAGE_STORE_CAPACITY; slot++)
    {
        if (AC_StageSavedAccountId[slot] == accountid)
            return slot;
    }
    return -1;
}

stock AC_StageGetOrCreateSavedSlot(accountid)
{
    new slot = AC_StageFindSavedSlot(accountid);
    if (slot != -1)
        return slot;

    for (new index; index < AC_STAGE_STORE_CAPACITY; index++)
    {
        if (AC_StageSavedAccountId[index] == 0)
        {
            AC_StageSavedAccountId[index] = accountid;
            return index;
        }
    }
    return -1;
}

stock AC_StageParseAccountId(const value[])
{
    new length = strlen(value);
    if (length == 0 || length > 10)
        return 0;

    new result;
    for (new index; index < length; index++)
    {
        if (value[index] < '0' || value[index] > '9')
            return 0;

        new digit = value[index] - '0';
        if (result > (2147483647 - digit) / 10)
            return 0;

        result = (result * 10) + digit;
    }
    return result;
}

stock AC_StageParsePlayerId(const value[])
{
    new length = strlen(value);
    if (length == 0 || length > 10)
        return -1;

    new result;
    for (new index; index < length; index++)
    {
        if (value[index] < '0' || value[index] > '9')
            return -1;

        new digit = value[index] - '0';
        if (result > (2147483647 - digit) / 10)
            return -1;

        result = (result * 10) + digit;
    }
    return result;
}

stock bool:AC_StageIsTraceVehicleModel(modelid)
{
    // Keep the staging trace command limited to ordinary road cars.
    switch (modelid)
    {
        case 400, 401, 402, 404, 405, 410, 411, 415, 419, 421, 426, 429,
             436, 439, 445, 451, 458, 477, 489, 496, 506, 517, 518, 526,
             527, 533, 541, 546, 547, 550, 555, 560, 562, 565, 566, 567,
             575, 576, 580, 585, 587, 589, 602, 603:
        {
            return true;
        }
    }
    return false;
}

stock AC_StageCaptureVehicleTelemetry(playerid)
{
    if (playerid != AC_StageLogCaptureOwner
        || !AC_IsMonitored(playerid)
        || GetPlayerState(playerid) != PLAYER_STATE_DRIVER)
    {
        return 0;
    }

    if (AC_StageVehicleTraceSampleCount >= AC_STAGE_MAX_VEHICLE_TRACE_SAMPLES)
    {
        if (!AC_StageVehicleTraceLimitNotified)
        {
            print("[AC-STAGE] Vehicle trace sample limit reached; further observations are suppressed.");
            AC_StageVehicleTraceLimitNotified = true;
        }
        return 0;
    }

    new tick = GetTickCount();
    new sample_interval_ms;
    if (AC_StageVehicleTraceSampleCount > 0)
    {
        sample_interval_ms = tick - AC_StageLastVehicleTraceTick[playerid];
        if (sample_interval_ms < AC_SAMPLE_INTERVAL_MS)
            return 0;
    }
    else
    {
        // The first sample has no preceding observation to measure against.
        sample_interval_ms = 0;
    }
    new vehicleid = GetPlayerVehicleID(playerid);
    if (vehicleid == 0 || vehicleid == INVALID_VEHICLE_ID || !IsValidVehicle(vehicleid))
        return 0;

    new modelid = GetVehicleModel(vehicleid);
    if (!AC_StageIsTraceVehicleModel(modelid))
        return 0;

    new Float:vx, Float:vy, Float:vz;
    if (!GetVehicleVelocity(vehicleid, vx, vy, vz))
        return 0;

    // Keep the detector's exact velocity conversion, but record observations only.
    new Float:speed_kmh = floatsqroot((vx * vx) + (vy * vy) + (vz * vz)) * AC_VEHICLE_SPEED_FACTOR;
    new speed_centi_kmh = floatround(speed_kmh * 100.0, floatround_round);
    new ping = AC_GetPing(playerid);
    if (ping < 0)
        ping = GetPlayerPing(playerid);

    // -1 means no fresh host-supplied packet-loss measurement was available.
    new packet_loss_centi_pct = -1;
    if (AC_NetworkPacketLossKnown[playerid]
        && (tick - AC_NetworkQualityTick[playerid]) <= AC_NETWORK_QUALITY_TTL_MS)
    {
        packet_loss_centi_pct = floatround(
            AC_NetworkPacketLoss[playerid] * 100.0,
            floatround_round
        );
    }

    // Update only after a complete observation is ready to be emitted.
    AC_StageLastVehicleTraceTick[playerid] = tick;

    // No player ID, account ID, vehicle ID, or coordinates are written.
    printf(
        "[AC-STAGE-VEHICLE] schema=2 actor=primary sample_interval_ms=%d model=%d speed_centi_kmh=%d ping=%d packet_loss_centi_pct=%d",
        sample_interval_ms,
        modelid,
        speed_centi_kmh,
        ping,
        packet_loss_centi_pct
    );
    AC_StageVehicleTraceSampleCount++;
    return 1;
}

stock AC_StageRequireLoaded(playerid)
{
    if (!AC_IsValidPlayerId(playerid) || !IsPlayerConnected(playerid))
        return 0;

    if (!AC_PlayerLoaded[playerid])
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Authenticate first: /acstageauth <accountid>");
        return 0;
    }
    return 1;
}

stock AC_StageRequireOnFoot(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    if (AC_StageSpectating[playerid] || GetPlayerState(playerid) != PLAYER_STATE_ONFOOT)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] This command requires a loaded player on foot.");
        return 0;
    }
    return 1;
}

stock AC_StageLogEvent(playerid, const event[], const details[])
{
    if (playerid != AC_StageLogCaptureOwner)
        return 0;

    // Use stable test roles only; never place player or account identifiers in this log.
    printf("[AC-STAGE-EVENT] schema=1 event=%s actor=primary%s", event, details);
    return 1;
}

stock AC_StageBeginLogCapture(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    if (AC_StageLogCaptureOwner != INVALID_PLAYER_ID)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Another acceptance capture is already active.");
        return 0;
    }

    AC_StageLogCaptureOwner = playerid;
    AC_StageLastVehicleTraceTick[playerid] = 0;
    AC_StageVehicleTraceSampleCount = 0;
    AC_StageVehicleTraceLimitNotified = false;
    AC_StageLogEvent(playerid, "run_begin", "");
    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Acceptance log capture started.");
    return 1;
}

stock AC_StageEndLogCapture(playerid)
{
    if (playerid != AC_StageLogCaptureOwner)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] You do not own the active acceptance capture.");
        return 0;
    }

    AC_StageLogEvent(playerid, "run_end", "");
    AC_StageLogCaptureOwner = INVALID_PLAYER_ID;
    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Acceptance log capture ended.");
    return 1;
}

stock AC_StageRestoreSpectateContext(playerid)
{
    if (!AC_IsValidPlayerId(playerid) || !AC_StagePendingSpectateRestore[playerid])
        return 0;

    new bool:was_spectating = AC_StageSpectating[playerid];
    AC_StagePendingSpectateRestore[playerid] = false;
    AC_StageSpectating[playerid] = false;

    // Restore the player's original interior before restoring their position.
    new bool:restore_ok = true;
    AC_NotifyLegitimateInteriorChange(playerid);
    if (!SetPlayerInterior(playerid, AC_StageSpectateSavedInterior[playerid]))
        restore_ok = false;

    AC_NotifyLegitimateVirtualWorldChange(playerid);
    if (!SetPlayerVirtualWorld(playerid, AC_StageSpectateSavedWorld[playerid]))
        restore_ok = false;

    AC_NotifyLegitimateTeleport(playerid);
    if (!SetPlayerPos(
        playerid,
        AC_StageSpectateSavedX[playerid],
        AC_StageSpectateSavedY[playerid],
        AC_StageSpectateSavedZ[playerid]
    ))
        restore_ok = false;

    if (was_spectating)
    {
        if (restore_ok)
            AC_StageLogEvent(playerid, "spectate_stop", "");
        else
        {
            AC_StageLogEvent(playerid, "run_abort", " reason=context_restore_failed");
            AC_StageLogCaptureOwner = INVALID_PLAYER_ID;
        }
    }

    if (!restore_ok)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Spectate ended, but context restoration reported a failure.");
        return 0;
    }

    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Spectating ended; your previous position and world were restored.");
    return 1;
}

stock AC_StageToggleInterior(playerid)
{
    if (!AC_StageRequireOnFoot(playerid))
        return 0;

    if (!AC_StageInteriorActive[playerid])
    {
        if (GetPlayerInterior(playerid) != 0)
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Enter the test interior from exterior interior 0.");
            return 0;
        }

        if (!GetPlayerPos(
            playerid,
            AC_StageSavedInteriorX[playerid],
            AC_StageSavedInteriorY[playerid],
            AC_StageSavedInteriorZ[playerid]
        ))
            return 0;

        AC_StageSavedInterior[playerid] = GetPlayerInterior(playerid);

        // Interior notification and teleport notification must precede their actions.
        AC_NotifyLegitimateInteriorChange(playerid);
        if (!SetPlayerInterior(playerid, AC_STAGE_TEST_INTERIOR_ID))
            return 0;

        AC_NotifyLegitimateTeleport(playerid);
        if (!SetPlayerPos(playerid, -25.7220, -187.8216, 1003.5469))
            return 0;

        AC_StageInteriorActive[playerid] = true;
        new details[48];
        format(details, sizeof(details), " from=%d to=%d",
            AC_StageSavedInterior[playerid], AC_STAGE_TEST_INTERIOR_ID);
        AC_StageLogEvent(playerid, "interior_enter", details);
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Entered the 24/7 test interior (17). Run the command again to return.");
    }
    else
    {
        AC_NotifyLegitimateInteriorChange(playerid);
        if (!SetPlayerInterior(playerid, AC_StageSavedInterior[playerid]))
            return 0;

        AC_NotifyLegitimateTeleport(playerid);
        if (!SetPlayerPos(
            playerid,
            AC_StageSavedInteriorX[playerid],
            AC_StageSavedInteriorY[playerid],
            AC_StageSavedInteriorZ[playerid]
        ))
            return 0;

        AC_StageInteriorActive[playerid] = false;
        new details[48];
        format(details, sizeof(details), " from=%d to=%d",
            AC_STAGE_TEST_INTERIOR_ID, AC_StageSavedInterior[playerid]);
        AC_StageLogEvent(playerid, "interior_exit", details);
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Returned to your previous position and interior.");
    }
    return 1;
}

stock AC_StageToggleVirtualWorld(playerid)
{
    if (!AC_StageRequireOnFoot(playerid))
        return 0;

    if (!AC_StageWorldActive[playerid])
    {
        new current_world = GetPlayerVirtualWorld(playerid);
        if (current_world == AC_STAGE_TEST_WORLD_ID)
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] World 9000 is reserved for this staging test.");
            return 0;
        }

        AC_StageSavedWorld[playerid] = current_world;
        AC_NotifyLegitimateVirtualWorldChange(playerid);
        if (!SetPlayerVirtualWorld(playerid, AC_STAGE_TEST_WORLD_ID))
            return 0;

        AC_StageWorldActive[playerid] = true;
        new details[48];
        format(details, sizeof(details), " from=%d to=%d", current_world, AC_STAGE_TEST_WORLD_ID);
        AC_StageLogEvent(playerid, "world_enter", details);
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Entered staging virtual world 9000. Run the command again to return.");
    }
    else
    {
        AC_NotifyLegitimateVirtualWorldChange(playerid);
        if (!SetPlayerVirtualWorld(playerid, AC_StageSavedWorld[playerid]))
            return 0;

        AC_StageWorldActive[playerid] = false;
        new details[48];
        format(details, sizeof(details), " from=%d to=%d",
            AC_STAGE_TEST_WORLD_ID, AC_StageSavedWorld[playerid]);
        AC_StageLogEvent(playerid, "world_exit", details);
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Returned to your previous virtual world.");
    }
    return 1;
}

stock AC_StageStartSpectating(playerid, targetid)
{
    if (!AC_StageRequireOnFoot(playerid))
        return 0;

    if (!AC_IsValidPlayerId(targetid) || !IsPlayerConnected(targetid) || targetid == playerid)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Target must be another connected player.");
        return 0;
    }

    if (GetPlayerState(targetid) == PLAYER_STATE_SPECTATING)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Choose a target who is not spectating.");
        return 0;
    }

    if (!GetPlayerPos(
        playerid,
        AC_StageSpectateSavedX[playerid],
        AC_StageSpectateSavedY[playerid],
        AC_StageSpectateSavedZ[playerid]
    ))
        return 0;

    AC_StageSpectateSavedInterior[playerid] = GetPlayerInterior(playerid);
    AC_StageSpectateSavedWorld[playerid] = GetPlayerVirtualWorld(playerid);

    // The open.mp spectate API requires both players to share interior and world.
    if (AC_StageSpectateSavedInterior[playerid] != GetPlayerInterior(targetid))
    {
        AC_NotifyLegitimateInteriorChange(playerid);
        if (!SetPlayerInterior(playerid, GetPlayerInterior(targetid)))
        {
            AC_StagePendingSpectateRestore[playerid] = true;
            AC_StageRestoreSpectateContext(playerid);
            return 0;
        }
    }

    if (AC_StageSpectateSavedWorld[playerid] != GetPlayerVirtualWorld(targetid))
    {
        AC_NotifyLegitimateVirtualWorldChange(playerid);
        if (!SetPlayerVirtualWorld(playerid, GetPlayerVirtualWorld(targetid)))
        {
            AC_StagePendingSpectateRestore[playerid] = true;
            AC_StageRestoreSpectateContext(playerid);
            return 0;
        }
    }

    AC_NotifyLegitimateSpectateChange(playerid);
    if (!TogglePlayerSpectating(playerid, true))
    {
        AC_StagePendingSpectateRestore[playerid] = true;
        AC_StageRestoreSpectateContext(playerid);
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Could not enable spectating.");
        return 0;
    }

    if (!PlayerSpectatePlayer(playerid, targetid))
    {
        // TogglePlayerSpectating(false) triggers the normal spawn callback.
        AC_StagePendingSpectateRestore[playerid] = true;
        AC_NotifyLegitimateSpectateChange(playerid);
        if (!TogglePlayerSpectating(playerid, false))
            AC_StageRestoreSpectateContext(playerid);
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Could not attach the spectate camera to that target.");
        return 0;
    }

    AC_StageSpectating[playerid] = true;
    AC_StageLogEvent(playerid, "spectate_start", " target=secondary");
    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Spectating target. Use /acstageunspectate to return.");
    return 1;
}

stock AC_StageEndSpectating(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    if (!AC_StageSpectating[playerid])
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] You are not in staging spectate mode.");
        return 0;
    }

    AC_StagePendingSpectateRestore[playerid] = true;
    AC_NotifyLegitimateSpectateChange(playerid);
    if (!TogglePlayerSpectating(playerid, false))
    {
        AC_StagePendingSpectateRestore[playerid] = false;
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Could not disable spectating.");
        return 0;
    }
    return 1;
}

stock AC_StageAuthenticate(playerid, accountid)
{
    if (!AC_IsValidPlayerId(playerid) || !IsPlayerConnected(playerid) || accountid <= 0)
        return 0;

    if (AC_PlayerLoaded[playerid])
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Already authenticated. Reconnect before switching test accounts.");
        return 0;
    }

    new sessiontoken = AC_BeginAccountLoad(playerid, accountid);
    if (sessiontoken <= 0)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Could not begin the test account load.");
        return 0;
    }

    new score;
    new strikes;
    new score_decay_at = gettime();
    new strike_decay_at = gettime();
    new last_strike_at;

    new slot = AC_StageFindSavedSlot(accountid);
    if (slot != -1)
    {
        score = AC_StageSavedScore[slot];
        strikes = AC_StageSavedStrikes[slot];
        score_decay_at = AC_StageSavedScoreDecayAt[slot];
        strike_decay_at = AC_StageSavedStrikeDecayAt[slot];
        last_strike_at = AC_StageSavedLastStrikeAt[slot];
    }

    if (!AC_ApplyPersistentState(
        playerid,
        accountid,
        sessiontoken,
        score,
        strikes,
        score_decay_at,
        strike_decay_at,
        last_strike_at
    ))
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Test account state was rejected.");
        return 0;
    }

    if (slot == -1)
    {
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] New in-memory test account loaded.");
    }
    else
    {
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Saved in-memory test account restored.");
    }

    printf("[AC-STAGE] LOAD accepted score=%d strikes=%d", score, strikes);
    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Use /acstagehelp to list test commands.");
    return 1;
}

stock AC_StageShowInfo(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    new message[144];
    new enabled_text[4];

    if (AC_PlayerEnabled[playerid])
        format(enabled_text, sizeof(enabled_text), "yes");
    else
        format(enabled_text, sizeof(enabled_text), "no");

    format(message, sizeof(message), "[AC-STAGE] Account %d | monitoring: %s",
        AC_AccountKey[playerid], enabled_text);
    SendClientMessage(playerid, 0xD8D8D8FF, message);

    format(message, sizeof(message), "[AC-STAGE] Score: %d/100 | strikes: %d | evidence: %d",
        AC_GetSuspicionScore(playerid),
        AC_GetStrikeCount(playerid),
        AC_GetEvidenceCount(playerid));
    SendClientMessage(playerid, 0xD8D8D8FF, message);

    new PLAYER_STATE:player_state = GetPlayerState(playerid);
    format(message, sizeof(message), "[AC-STAGE] Interior: %d | world: %d | state: %d",
        GetPlayerInterior(playerid),
        GetPlayerVirtualWorld(playerid),
        _:player_state);
    SendClientMessage(playerid, 0xD8D8D8FF, message);
    return 1;
}

stock AC_StageShowV2Info(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    new message[144];
    format(message, sizeof(message), "[AC-TEST] V2 evidence callbacks: %d | V2 strike callbacks: %d",
        AC_TestEvidenceV2Count[playerid], AC_TestStrikeV2Count[playerid]);
    SendClientMessage(playerid, 0xD8D8D8FF, message);

    format(message, sizeof(message), "[AC-TEST] Last evidence sequence/time: %d / %d",
        AC_TestLastEvidenceSequence[playerid], AC_TestLastEvidenceTimestamp[playerid]);
    SendClientMessage(playerid, 0xD8D8D8FF, message);

    if (AC_TestStrikeV2Count[playerid] > 0)
    {
        new linked_text[4];
        if (AC_TestLastStrikeLinked[playerid])
            format(linked_text, sizeof(linked_text), "yes");
        else
            format(linked_text, sizeof(linked_text), "no");

        format(message, sizeof(message), "[AC-TEST] Last strike sequence: %d | linked to latest evidence: %s",
            AC_TestLastStrikeSequence[playerid], linked_text);
        SendClientMessage(playerid, 0xD8D8D8FF, message);
    }
    return 1;
}

stock AC_StageShowEvidence(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    new count = AC_GetEvidenceCount(playerid);
    if (count == 0)
    {
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] No evidence records in this session.");
        return 1;
    }

    new message[144];
    for (new index; index < count; index++)
    {
        new timestamp, category, points, ping;
        new Float:metric;
        new reason[AC_EVIDENCE_REASON_LENGTH];
        new category_name[16];

        if (!AC_GetEvidence(
            playerid, index, timestamp, category, points, ping, metric, reason, sizeof(reason)
        ))
            continue;

        AC_GetCategoryName(category, category_name, sizeof(category_name));
        format(message, sizeof(message), "[AC-STAGE] %s +%d | ping %d | %s",
            category_name, points, ping, reason);
        SendClientMessage(playerid, 0xD8D8D8FF, message);
    }
    return 1;
}

stock AC_StageDestroyVehicle(playerid)
{
    if (!AC_IsValidPlayerId(playerid))
        return 0;

    new vehicleid = AC_StageVehicleId[playerid];
    if (vehicleid != 0 && vehicleid != INVALID_VEHICLE_ID && IsValidVehicle(vehicleid))
        DestroyVehicle(vehicleid);

    AC_StageVehicleId[playerid] = INVALID_VEHICLE_ID;
    return 1;
}

#define AC_STAGE_SELFTEST_ACCOUNT_BASE (2000000000)

stock AC_StageSelfTestCheck(playerid, bool:condition, const label[])
{
    new message[112];

    if (condition)
    {
        format(message, sizeof(message), "[AC-STAGE-TEST] PASS: %s", label);
        printf("%s", message);
        SendClientMessage(playerid, 0x70D890FF, message);
        return 1;
    }

    format(message, sizeof(message), "[AC-STAGE-TEST] FAIL: %s", label);
    printf("%s", message);
    SendClientMessage(playerid, 0xE05A5AFF, message);
    return 0;
}

stock AC_StageRestoreAccountAfterSelfTest(playerid, accountid)
{
    // Simulate a fresh framework session without disconnecting the real game client.
    AC_OnPlayerDisconnect(playerid);
    AC_OnPlayerConnect(playerid);
    return AC_StageAuthenticate(playerid, accountid);
}

stock AC_StageRunPersistenceSelfTest(playerid)
{
    if (!AC_StageRequireLoaded(playerid))
        return 0;

    new original_accountid = AC_AccountKey[playerid];
    new selftest_accountid = AC_STAGE_SELFTEST_ACCOUNT_BASE + playerid;
    if (selftest_accountid == original_accountid)
        selftest_accountid++;

    // Reserve both records before mutating the active player session.
    if (AC_StageGetOrCreateSavedSlot(original_accountid) == -1
        || AC_StageGetOrCreateSavedSlot(selftest_accountid) == -1)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE-TEST] Not enough in-memory account slots.");
        return 0;
    }

    if (!AC_SavePersistentState(playerid))
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE-TEST] Could not preserve your current test account.");
        return 0;
    }

    new passed;
    new failed;
    new now = gettime();
    new score = 27;
    new strikes = 3;
    new score_decay_at = now;
    new strike_decay_at = now;
    new last_strike_at = now - 60;
    new sessiontoken = AC_BeginAccountLoad(playerid, selftest_accountid);

    if (sessiontoken <= 0)
    {
        SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE-TEST] Could not begin synthetic self-test load.");
        AC_StageRestoreAccountAfterSelfTest(playerid, original_accountid);
        return 0;
    }

    new stale_token = sessiontoken - 1;
    if (stale_token <= 0)
        stale_token = sessiontoken + 1;

    if (AC_StageSelfTestCheck(
        playerid,
        !AC_ApplyPersistentState(
            playerid, selftest_accountid, stale_token,
            score, strikes, score_decay_at, strike_decay_at, last_strike_at
        ),
        "stale session token rejected"
    ))
        passed++;
    else
        failed++;

    if (AC_StageSelfTestCheck(
        playerid,
        !AC_ApplyPersistentState(
            playerid, selftest_accountid + 1, sessiontoken,
            score, strikes, score_decay_at, strike_decay_at, last_strike_at
        ),
        "account ID mismatch rejected"
    ))
        passed++;
    else
        failed++;

    if (!AC_ApplyPersistentState(
        playerid,
        selftest_accountid,
        sessiontoken,
        score,
        strikes,
        score_decay_at,
        strike_decay_at,
        last_strike_at
    ))
    {
        AC_StageSelfTestCheck(playerid, false, "valid account state accepted");
        failed++;
        AC_StageRestoreAccountAfterSelfTest(playerid, original_accountid);
        return 0;
    }

    if (AC_StageSelfTestCheck(
        playerid,
        AC_PlayerLoaded[playerid] && AC_PlayerEnabled[playerid],
        "valid account load enables monitoring"
    ))
        passed++;
    else
        failed++;

    if (AC_StageSelfTestCheck(
        playerid,
        !AC_ApplyPersistentState(
            playerid, selftest_accountid, sessiontoken,
            score, strikes, score_decay_at, strike_decay_at, last_strike_at
        ),
        "duplicate account load rejected"
    ))
        passed++;
    else
        failed++;

    if (AC_StageSelfTestCheck(
        playerid,
        AC_LastStrikeAt[playerid] == last_strike_at
            && AC_LastStrikeAt[playerid] != AC_LastStrikeDecayAt[playerid],
        "strike cooldown timestamp remains separate"
    ))
        passed++;
    else
        failed++;

    AC_NotifyLegitimateTeleport(playerid);
    if (AC_StageSelfTestCheck(playerid, AC_IsInGrace(playerid), "legal transition starts grace window"))
        passed++;
    else
        failed++;

    new interior_notice = AC_NotifyLegitimateInteriorChange(playerid);
    if (AC_StageSelfTestCheck(
        playerid,
        interior_notice && AC_IsInGrace(playerid),
        "interior change notification starts grace window"
    ))
        passed++;
    else
        failed++;

    new world_notice = AC_NotifyLegitimateVirtualWorldChange(playerid);
    if (AC_StageSelfTestCheck(
        playerid,
        world_notice && AC_IsInGrace(playerid),
        "virtual world change notification starts grace window"
    ))
        passed++;
    else
        failed++;

    new spectate_notice = AC_NotifyLegitimateSpectateChange(playerid);
    if (AC_StageSelfTestCheck(
        playerid,
        spectate_notice && AC_IsInGrace(playerid),
        "spectate change notification starts grace window"
    ))
        passed++;
    else
        failed++;

    new vehicle_notice = AC_NotifyLegitimateVehicleChange(playerid);
    if (AC_StageSelfTestCheck(playerid, vehicle_notice != 0, "vehicle transition notification accepted"))
        passed++;
    else
        failed++;

    if (AC_SavePersistentState(playerid))
    {
        new saved_slot = AC_StageFindSavedSlot(selftest_accountid);
        if (AC_StageSelfTestCheck(
            playerid,
            saved_slot != -1
                && AC_StageSavedScore[saved_slot] == score
                && AC_StageSavedStrikes[saved_slot] == strikes
                && AC_StageSavedLastStrikeAt[saved_slot] == last_strike_at,
            "persistence callback saves score, strikes and cooldown timestamp"
        ))
            passed++;
        else
            failed++;
    }
    else
    {
        AC_StageSelfTestCheck(playerid, false, "persistence callback accepts save");
        failed++;
    }

    // Exercise the framework's disconnect/connect reset path while keeping this
    // client connected; this is not a substitute for a real network reconnect.
    AC_OnPlayerDisconnect(playerid);
    AC_OnPlayerConnect(playerid);
    if (AC_StageAuthenticate(playerid, selftest_accountid))
    {
        new restored = AC_StageSelfTestCheck(
            playerid,
            AC_GetSuspicionScore(playerid) == score
                && AC_GetStrikeCount(playerid) == strikes
                && AC_LastStrikeAt[playerid] == last_strike_at,
            "saved state restored after simulated session reconnect"
        );
        if (restored)
            passed++;
        else
            failed++;
    }
    else
    {
        AC_StageSelfTestCheck(playerid, false, "saved state restored after simulated session reconnect");
        failed++;
    }

    if (!AC_StageRestoreAccountAfterSelfTest(playerid, original_accountid))
    {
        AC_StageSelfTestCheck(playerid, false, "original synthetic account restored");
        failed++;
    }
    else
    {
        if (AC_StageSelfTestCheck(
            playerid,
            AC_PlayerLoaded[playerid] && AC_AccountKey[playerid] == original_accountid,
            "original synthetic account restored"
        ))
            passed++;
        else
            failed++;
    }

    new summary[96];
    format(summary, sizeof(summary), "[AC-STAGE-TEST] Finished: %d passed, %d failed.", passed, failed);
    SendClientMessage(playerid, failed == 0 ? 0x70D890FF : 0xE05A5AFF, summary);
    printf("%s", summary);
    return failed == 0;
}

public OnGameModeInit()
{
    AC_Init();
    SetGameModeText("Anti-Cheat Test");
    AddPlayerClass(0, 1958.3783, 1343.1572, 15.3746, 269.1425, WEAPON_FIST, 0, WEAPON_FIST, 0, WEAPON_FIST, 0);

    print("[AC-TEST] Gamemode initialized.");
    print("[AC-TEST] Synthetic persistence is RAM-only and resets when the server restarts.");
    return 1;
}

public OnPlayerConnect(playerid)
{
    AC_OnPlayerConnect(playerid);
    AC_StageVehicleId[playerid] = INVALID_VEHICLE_ID;
    AC_StageLastVehicleTraceTick[playerid] = 0;
    AC_StageInteriorActive[playerid] = false;
    AC_StageWorldActive[playerid] = false;
    AC_StageSpectating[playerid] = false;
    AC_StagePendingSpectateRestore[playerid] = false;
    AC_TestEvidenceV2Count[playerid] = 0;
    AC_TestStrikeV2Count[playerid] = 0;
    AC_TestLastEvidenceSequence[playerid] = 0;
    AC_TestLastEvidenceTimestamp[playerid] = 0;
    AC_TestLastStrikeSequence[playerid] = 0;
    AC_TestLastStrikeLinked[playerid] = false;
    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Monitoring is off until you authenticate.");
    SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Authenticate with /acstageauth <accountid>.");
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    #pragma unused reason
    AC_StageDestroyVehicle(playerid);
    AC_StageInteriorActive[playerid] = false;
    AC_StageWorldActive[playerid] = false;
    AC_StageSpectating[playerid] = false;
    AC_StagePendingSpectateRestore[playerid] = false;
    if (AC_StageLogCaptureOwner == playerid)
    {
        AC_StageLogEvent(playerid, "run_abort", " reason=owner_disconnect");
        AC_StageLogCaptureOwner = INVALID_PLAYER_ID;
    }
    AC_OnPlayerDisconnect(playerid);
    return 1;
}

public OnPlayerSpawn(playerid)
{
    AC_OnPlayerSpawn(playerid);
    AC_StageRestoreSpectateContext(playerid);
    return 1;
}

public OnPlayerDeath(playerid, killerid, WEAPON:reason)
{
    #pragma unused killerid, reason
    AC_OnPlayerDeath(playerid);
    return 1;
}

public OnPlayerStateChange(playerid, PLAYER_STATE:newstate, PLAYER_STATE:oldstate)
{
    AC_OnPlayerStateChange(playerid, newstate, oldstate);
    if (playerid == AC_StageLogCaptureOwner)
    {
        if (newstate == PLAYER_STATE_SPECTATING)
            AC_StageLogEvent(playerid, "spectate_state_enter", "");
        else if (oldstate == PLAYER_STATE_SPECTATING)
            AC_StageLogEvent(playerid, "spectate_state_exit", "");
    }
    return 1;
}

public OnPlayerInteriorChange(playerid, newinteriorid, oldinteriorid)
{
    new details[48];
    format(details, sizeof(details), " old=%d new=%d", oldinteriorid, newinteriorid);
    AC_StageLogEvent(playerid, "interior_callback", details);
    return 1;
}

public OnPlayerUpdate(playerid)
{
    AC_OnPlayerUpdate(playerid);
    AC_StageCaptureVehicleTelemetry(playerid);
    return 1;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
    if (!strcmp(cmdtext, "/acstagehelp", true))
    {
        SendClientMessage(playerid, 0xE05A5AFF, "Anti-Cheat staging commands:");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageauth <accountid> - load a synthetic test account");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageinfo - show monitoring and score state");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagev2info - verify versioned evidence callback delivery");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagetest - run session, persistence and transition self-tests");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageevidence - show current evidence records");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagetoggle - enable or disable monitoring");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagesave - save to the temporary memory adapter");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageclear - clear your own review state");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageteleport - test a server-notified legal teleport");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagevehicle [modelid] - spawn an approved road-car trace model (default 411)");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageexitvehicle - leave your current vehicle");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageinterior - enter/exit a real test interior transition");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageworld - enter/exit reserved virtual world 9000");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagespectate <playerid> - spectate another connected player");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstageunspectate - leave spectate and restore your position");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagelogbegin - start a privacy-safe acceptance capture");
        SendClientMessage(playerid, 0xD8D8D8FF, "/acstagelogend - finish the acceptance capture");
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagelogbegin", true))
    {
        AC_StageBeginLogCapture(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagelogend", true))
    {
        AC_StageEndLogCapture(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageauth", true))
    {
        SendClientMessage(playerid, 0xE05A5AFF, "Usage: /acstageauth <positive synthetic account ID>");
        return 1;
    }

    if (strfind(cmdtext, "/acstageauth ", true) == 0)
    {
        new accountid = AC_StageParseAccountId(cmdtext[13]);
        if (accountid <= 0)
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Account ID must be a positive integer.");
            return 1;
        }

        AC_StageAuthenticate(playerid, accountid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageinterior", true))
    {
        AC_StageToggleInterior(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageworld", true))
    {
        AC_StageToggleVirtualWorld(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagespectate", true))
    {
        SendClientMessage(playerid, 0xE05A5AFF, "Usage: /acstagespectate <connected player ID>");
        return 1;
    }

    if (strfind(cmdtext, "/acstagespectate ", true) == 0)
    {
        new targetid = AC_StageParsePlayerId(cmdtext[17]);
        if (targetid < 0 || !AC_IsValidPlayerId(targetid))
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Target player ID is invalid.");
            return 1;
        }
        AC_StageStartSpectating(playerid, targetid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageunspectate", true))
    {
        AC_StageEndSpectating(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagetest", true))
    {
        AC_StageRunPersistenceSelfTest(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageinfo", true))
    {
        AC_StageShowInfo(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagev2info", true))
    {
        AC_StageShowV2Info(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageevidence", true))
    {
        AC_StageShowEvidence(playerid);
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagetoggle", true))
    {
        if (!AC_StageRequireLoaded(playerid))
            return 1;

        new bool:enabled = !AC_PlayerEnabled[playerid];
        if (AC_SetEnabled(playerid, enabled))
        {
            if (enabled)
                SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Monitoring enabled.");
            else
                SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Monitoring disabled.");
        }
        return 1;
    }

    if (!strcmp(cmdtext, "/acstagesave", true))
    {
        if (!AC_StageRequireLoaded(playerid))
            return 1;

        if (AC_SavePersistentState(playerid))
            SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Save accepted by the in-memory adapter.");
        else
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Save was not accepted.");
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageclear", true))
    {
        if (!AC_StageRequireLoaded(playerid))
            return 1;

        if (AC_ClearPlayerReviewState(playerid))
            SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Your review state was cleared.");
        else
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Review state could not be cleared.");
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageteleport", true))
    {
        if (!AC_StageRequireLoaded(playerid))
            return 1;

        new Float:x, Float:y, Float:z;
        if (!GetPlayerPos(playerid, x, y, z))
            return 1;

        // Notify the detector before moving the player through a server-owned action.
        AC_NotifyLegitimateTeleport(playerid);
        SetPlayerPos(playerid, x + 8.0, y, z);
        AC_StageLogEvent(playerid, "teleport", "");
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Legal teleport applied with a grace window.");
        return 1;
    }

    if (strfind(cmdtext, "/acstagevehicle", true) == 0)
    {
        if (!AC_StageRequireLoaded(playerid))
            return 1;

        new modelid = 411;
        if (cmdtext[15] != 0)
        {
            if (cmdtext[15] != ' ')
            {
                SendClientMessage(playerid, 0xE05A5AFF, "Usage: /acstagevehicle [modelid]");
                return 1;
            }
            modelid = AC_StageParsePlayerId(cmdtext[16]);
        }

        if (!AC_StageIsTraceVehicleModel(modelid))
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Unsupported trace model. Use /acstagevehicle [modelid] with an approved road-car model.");
            return 1;
        }

        new Float:x, Float:y, Float:z;
        if (!GetPlayerPos(playerid, x, y, z))
            return 1;

        // Reset the detector baseline before replacing or entering a vehicle.
        AC_NotifyLegitimateVehicleChange(playerid);
        AC_StageDestroyVehicle(playerid);
        new vehicleid = CreateVehicle(modelid, x + 5.0, y, z, 0.0, -1, -1, 60);
        if (vehicleid == 0 || vehicleid == INVALID_VEHICLE_ID)
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] Could not create the test vehicle.");
            return 1;
        }

        AC_StageVehicleId[playerid] = vehicleid;
        PutPlayerInVehicle(playerid, vehicleid, 0);
        AC_StageLogEvent(playerid, "vehicle_enter", "");
        SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Test road car created and server-placed. Drive normally while capture is active to collect telemetry.");
        return 1;
    }

    if (!strcmp(cmdtext, "/acstageexitvehicle", true))
    {
        if (!AC_StageRequireLoaded(playerid))
            return 1;

        if (GetPlayerState(playerid) == PLAYER_STATE_DRIVER
            || GetPlayerState(playerid) == PLAYER_STATE_PASSENGER)
        {
            AC_NotifyLegitimateVehicleChange(playerid);
            RemovePlayerFromVehicle(playerid);
            AC_StageLogEvent(playerid, "vehicle_exit", "");
            SendClientMessage(playerid, 0xD8D8D8FF, "[AC-STAGE] Vehicle exit completed.");
        }
        else
        {
            SendClientMessage(playerid, 0xE05A5AFF, "[AC-STAGE] You are not in a vehicle.");
        }
        return 1;
    }

    return 0;
}

public AC_OnPersistenceSave(playerid, accountid, score, strikes, score_decay_at, strike_decay_at, last_strike_at)
{
    if (!AC_IsValidPlayerId(playerid)
        || !IsPlayerConnected(playerid)
        || !AC_PlayerLoaded[playerid]
        || AC_AccountKey[playerid] != accountid
        || accountid <= 0)
    {
        return 0;
    }

    new slot = AC_StageGetOrCreateSavedSlot(accountid);
    if (slot == -1)
    {
        print("[AC-STAGE] In-memory account store is full; persistence callback rejected the save.");
        return 0;
    }

    AC_StageSavedScore[slot] = score;
    AC_StageSavedStrikes[slot] = strikes;
    AC_StageSavedScoreDecayAt[slot] = score_decay_at;
    AC_StageSavedStrikeDecayAt[slot] = strike_decay_at;
    AC_StageSavedLastStrikeAt[slot] = last_strike_at;

    printf("[AC-STAGE] SAVE accepted score=%d strikes=%d", score, strikes);
    return 1;
}

public AC_OnEvidence(playerid, category, points, ping, const reason[], Float:metric)
{
    #pragma unused reason, metric
    if (playerid == AC_StageLogCaptureOwner)
    {
        new category_name[16];
        new details[80];
        AC_GetCategoryName(category, category_name, sizeof(category_name));
        format(details, sizeof(details), " category=%s points=%d ping=%d",
            category_name, points, ping);
        AC_StageLogEvent(playerid, "evidence", details);
    }
    return 1;
}

public AC_OnStrike(playerid, accountid, strikes, const reason[])
{
    #pragma unused accountid, reason
    if (playerid == AC_StageLogCaptureOwner)
    {
        new details[32];
        format(details, sizeof(details), " strikes=%d", strikes);
        AC_StageLogEvent(playerid, "review_marker", details);
    }
    return 1;
}

public AC_OnEvidenceV2(playerid, accountid, sessiontoken, sequence, timestamp, category, points, ping, const reason[], Float:metric)
{
    #pragma unused accountid, sessiontoken, category, points, ping, reason, metric
    if (!AC_IsValidPlayerId(playerid) || !IsPlayerConnected(playerid))
        return 0;

    AC_TestEvidenceV2Count[playerid]++;
    AC_TestLastEvidenceSequence[playerid] = sequence;
    AC_TestLastEvidenceTimestamp[playerid] = timestamp;
    return 1;
}

public AC_OnStrikeV2(playerid, accountid, sessiontoken, sequence, timestamp, strikes, const reason[])
{
    #pragma unused accountid, sessiontoken, strikes, reason
    if (!AC_IsValidPlayerId(playerid) || !IsPlayerConnected(playerid))
        return 0;

    AC_TestStrikeV2Count[playerid]++;
    AC_TestLastStrikeSequence[playerid] = sequence;
    // Ensure the strike event references the evidence event that caused it.
    AC_TestLastStrikeLinked[playerid] =
        (AC_TestLastEvidenceSequence[playerid] == sequence
            && AC_TestLastEvidenceTimestamp[playerid] == timestamp);
    return 1;
}

public AC_OnAdministrativeReset(adminid, targetid, accountid)
{
    #pragma unused adminid, targetid, accountid
    print("[AC-STAGE] REVIEW_RESET observed");
    return 1;
}
