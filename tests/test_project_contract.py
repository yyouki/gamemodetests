from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PINNED_ANTICHEAT_COMMIT = "b8e7885395f35f60f64dac1db8f6428730e2674d"


class GameModeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "gamemode" / "ac_test.pwn").read_text(encoding="utf-8")
        cls.config = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
        cls.workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        cls.readme = (ROOT / "README.md").read_text(encoding="utf-8")
        cls.matrix = (ROOT / "docs" / "TEST_MATRIX.md").read_text(encoding="utf-8")

    def test_framework_dependency_is_pinned_and_external(self) -> None:
        self.assertIn(PINNED_ANTICHEAT_COMMIT, self.workflow)
        self.assertIn("git fetch --depth=1 origin", self.workflow)
        self.assertIn("anti-cheat include", self.readme.lower())

    def test_required_v2_callbacks_are_implemented(self) -> None:
        self.assertIn("public AC_OnEvidenceV2(", self.source)
        self.assertIn("public AC_OnStrikeV2(", self.source)
        self.assertIn('"/acstagev2info"', self.source)
        self.assertIn("AC_TestLastStrikeLinked[playerid]", self.source)

    def test_v2_strike_is_correlated_to_evidence_sequence_and_timestamp(self) -> None:
        self.assertRegex(
            self.source,
            re.compile(
                r"AC_TestLastStrikeLinked\[playerid\]\s*=\s*"
                r"\(AC_TestLastEvidenceSequence\[playerid\]\s*==\s*sequence\s*"
                r"&&\s*AC_TestLastEvidenceTimestamp\[playerid\]\s*==\s*timestamp\s*\)",
                re.DOTALL,
            ),
        )

    def test_lifecycle_and_legal_transition_hooks_are_forwarded(self) -> None:
        for token in (
            "AC_OnPlayerConnect(playerid);",
            "AC_OnPlayerDisconnect(playerid);",
            "AC_OnPlayerSpawn(playerid);",
            "AC_OnPlayerDeath(playerid);",
            "AC_OnPlayerStateChange(playerid, newstate, oldstate);",
            "AC_OnPlayerUpdate(playerid);",
            "AC_NotifyLegitimateTeleport(playerid);",
            "AC_NotifyLegitimateInteriorChange(playerid);",
            "AC_NotifyLegitimateVirtualWorldChange(playerid);",
            "AC_NotifyLegitimateSpectateChange(playerid);",
            "AC_NotifyLegitimateVehicleChange(playerid);",
        ):
            with self.subTest(token=token):
                self.assertIn(token, self.source)

    def test_operator_commands_and_scenarios_exist(self) -> None:
        for command in (
            "/acstageauth", "/acstagetest", "/acstageinfo", "/acstagev2info",
            "/acstageevidence", "/acstageteleport", "/acstagevehicle",
            "/acstageinterior", "/acstageworld", "/acstagespectate",
            "/acstageunspectate", "/acstagelogbegin", "/acstagelogend",
        ):
            with self.subTest(command=command):
                self.assertIn(command, self.source + self.readme)
        for scenario in (
            "walk_idle", "jump_fall_land", "admin_teleport", "spawn_death_respawn",
            "interior_roundtrip", "virtual_world_roundtrip", "vehicle_enter_drive_exit",
            "spectate_roundtrip", "disconnect_reconnect", "network_condition_sample",
        ):
            with self.subTest(scenario=scenario):
                self.assertIn(scenario, self.matrix)

    def test_capture_telemetry_is_bounded_and_pseudonymous(self) -> None:
        self.assertIn("#define AC_STAGE_MAX_VEHICLE_TRACE_SAMPLES (3600)", self.source)
        self.assertIn("AC_SAMPLE_INTERVAL_MS", self.source)
        start = self.source.index("stock AC_StageCaptureVehicleTelemetry")
        end = self.source.index("stock AC_StageRequireLoaded", start)
        telemetry = self.source[start:end]
        for forbidden in ("playerid=", "accountid=", "vehicleid=", " x=", " y=", " z="):
            with self.subTest(field=forbidden):
                self.assertNotIn(forbidden, telemetry)
        self.assertIn("[AC-STAGE-VEHICLE]", telemetry)

    def test_private_config_disables_discovery_and_rcon(self) -> None:
        self.assertFalse(self.config["announce"])
        self.assertFalse(self.config["enable_query"])
        self.assertFalse(self.config["rcon"]["enable"])
        self.assertEqual(self.config["pawn"]["main_scripts"], ["ac-test 1"])
        self.assertFalse(self.config["logging"]["log_chat"])
        self.assertFalse(self.config["logging"]["log_connection_messages"])

    def test_no_automatic_punishment_calls(self) -> None:
        self.assertIsNone(re.search(r"\b(?:Kick|Ban|BanEx|SendRconCommand)\s*\(", self.source))

    def test_ci_builds_packages_and_boots_server(self) -> None:
        for token in (
            "pawnc-3.10.11-linux.tar.gz", "open.mp-linux-x86.tar.gz",
            "ac-test.amx", "gamemodetests-package",
        ):
            with self.subTest(token=token):
                self.assertIn(token, self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
