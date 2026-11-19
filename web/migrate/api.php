<?php
/**
 * JSON API for hestia-migrate wizard.
 */
ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";
header("Content-Type: application/json; charset=utf-8");

if ($_SESSION["userContext"] !== "admin" || !empty($_SESSION["look"])) {
	http_response_code(403);
	echo json_encode(["ok" => false, "error" => "admin only"]);
	exit();
}

$token = $_SERVER["HTTP_X_CSRF_TOKEN"] ?? ($_POST["token"] ?? ($_GET["token"] ?? ""));
if (empty($token) || $token !== ($_SESSION["token"] ?? "")) {
	http_response_code(403);
	echo json_encode(["ok" => false, "error" => "invalid csrf token"]);
	exit();
}

$action = $_GET["action"] ?? ($_POST["action"] ?? "");
$bin = "/usr/bin/sudo";

function migrate_exec(string $cmd): array {
	$output = [];
	$return_var = 0;
	exec($cmd . " 2>&1", $output, $return_var);
	$raw = implode("\n", $output);
	// Prefer last JSON object/array in output (ignore SSH banners)
	$json = null;
	if (preg_match('/(\{.*\}|\[.*\])\s*$/s', $raw, $m)) {
		$json = json_decode($m[1], true);
	}
	if ($json === null) {
		$json = json_decode($raw, true);
	}
	return [$return_var, $raw, $json];
}

switch ($action) {
	case "connect":
		$host = trim($_POST["host"] ?? "");
		$host = preg_replace("#^https?://#i", "", $host);
		$host = preg_replace("#^ttps://#i", "", $host);
		$host = explode("/", $host, 2)[0];
		$host = explode("?", $host, 2)[0];
		$port = trim($_POST["port"] ?? "22");
		$ssh_user = trim($_POST["ssh_user"] ?? "root") ?: "root";
		$password = $_POST["password"] ?? "";
		if ($host === "" || $password === "") {
			echo json_encode(["ok" => false, "error" => "host and password required"]);
			exit();
		}
		$tmp = tempnam("/tmp", "hmig");
		file_put_contents($tmp, $password);
		chmod($tmp, 0600);
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-connect " .
				escapeshellarg($host) .
				" " .
				escapeshellarg($port) .
				" " .
				escapeshellarg($tmp) .
				" " .
				escapeshellarg($ssh_user)
		);
		@unlink($tmp);
		if (is_array($json) && !empty($json["session"])) {
			$_SESSION["migrate_session"] = $json["session"];
		}
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "list_users":
		$session = escapeshellarg($_SESSION["migrate_session"] ?? ($_GET["session"] ?? ""));
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-list-users $session"
		);
		if (is_array($json) && isset($json["users"])) {
			echo json_encode(["ok" => true, "users" => $json["users"], "count" => $json["count"] ?? count($json["users"])]);
		} elseif (is_array($json) && $json !== [] && array_keys($json) === range(0, count($json) - 1)) {
			echo json_encode(["ok" => true, "users" => $json, "count" => count($json)]);
		} else {
			echo json_encode(["ok" => false, "error" => $raw ?: "empty user list", "code" => $rc]);
		}
		break;

	case "analyze":
		$session = escapeshellarg($_SESSION["migrate_session"] ?? ($_POST["session"] ?? ""));
		$user = escapeshellarg(trim($_POST["user"] ?? ""));
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-analyze $session $user"
		);
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "analyze_batch":
		$session = $_SESSION["migrate_session"] ?? ($_POST["session"] ?? "");
		$users_raw = trim($_POST["users"] ?? "");
		$users = array_values(array_filter(array_map("trim", preg_split('/[\s,]+/', $users_raw))));
		if ($session === "" || !$users) {
			echo json_encode(["ok" => false, "error" => "session and users required"]);
			exit();
		}
		$results = [];
		$needs_install = [];
		$needs_remap = [];
		$php_installed = [];
		$by_version = [];
		foreach ($users as $u) {
			[$rc, $raw, $json] = migrate_exec(
				"$bin /usr/local/hestia/bin/v-migrate-analyze " .
					escapeshellarg($session) .
					" " .
					escapeshellarg($u)
			);
			$row = $json ?: ["ok" => false, "user" => $u, "verdict" => "blocked", "error" => $raw, "code" => $rc];
			$results[] = $row;
			$sw = is_array($row["software"] ?? null) ? $row["software"] : [];
			foreach ($sw["php_installed"] ?? [] as $v) {
				$php_installed[$v] = true;
			}
			foreach ($sw["needs_install"] ?? [] as $v) {
				$needs_install[$v] = true;
				$by_version[$v]["action"] = "needs_install";
				$by_version[$v]["users"][] = $row["user"] ?? $u;
			}
			foreach ($sw["needs_remap"] ?? [] as $v) {
				$needs_remap[$v] = true;
				$by_version[$v]["action"] = "needs_remap";
				$by_version[$v]["users"][] = $row["user"] ?? $u;
			}
		}
		foreach ($by_version as $v => &$meta) {
			$meta["users"] = array_values(array_unique($meta["users"] ?? []));
		}
		unset($meta);
		echo json_encode([
			"ok" => true,
			"results" => $results,
			"software" => [
				"needs_install" => array_keys($needs_install),
				"needs_remap" => array_keys($needs_remap),
				"php_installed" => array_keys($php_installed),
				"by_version" => $by_version,
			],
		]);
		break;

	case "transfer":
		$session = escapeshellarg($_SESSION["migrate_session"] ?? ($_POST["session"] ?? ""));
		$user = escapeshellarg(trim($_POST["user"] ?? ""));
		$accept = escapeshellarg(($_POST["accept_warnings"] ?? "") === "yes" ? "yes" : "no");
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-start $session $user $accept"
		);
		if (is_array($json) && !empty($json["job"])) {
			$_SESSION["migrate_job"] = $json["job"];
		}
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "transfer_batch":
		$session = $_SESSION["migrate_session"] ?? ($_POST["session"] ?? "");
		$users_raw = trim($_POST["users"] ?? "");
		$users = array_values(array_filter(array_map("trim", preg_split('/[\s,]+/', $users_raw))));
		$accept = ($_POST["accept_warnings"] ?? "") === "yes" ? "yes" : "no";
		$accept_sw = ($_POST["accept_software"] ?? "") === "yes" ? "yes" : "no";
		$install_php = trim($_POST["install_php"] ?? "");
		$remap_php = trim($_POST["remap_php"] ?? "");
		if ($install_php === "" || $install_php === "none") {
			$install_php = "-";
		}
		if ($remap_php === "" || $remap_php === "none") {
			$remap_php = "-";
		}
		if ($session === "" || !$users) {
			echo json_encode(["ok" => false, "error" => "session and users required"]);
			exit();
		}
		$cmd =
			"$bin /usr/local/hestia/bin/v-migrate-start-batch " .
			escapeshellarg($session) .
			" " .
			escapeshellarg($accept) .
			" " .
			escapeshellarg($accept_sw) .
			" " .
			escapeshellarg($install_php) .
			" " .
			escapeshellarg($remap_php);
		foreach ($users as $u) {
			$cmd .= " " . escapeshellarg($u);
		}
		[$rc, $raw, $json] = migrate_exec($cmd);
		if (is_array($json) && !empty($json["ok"])) {
			if (!empty($json["first_job"])) {
				$_SESSION["migrate_job"] = $json["first_job"];
			}
			if (!empty($json["batch_id"])) {
				$_SESSION["migrate_batch_id"] = $json["batch_id"];
			}
			$_SESSION["migrate_batch_users"] = $users;
		}
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "batch_status":
		$batch = trim($_GET["batch"] ?? $_POST["batch"] ?? ($_SESSION["migrate_batch_id"] ?? ""));
		$cmd = "$bin /usr/local/hestia/bin/v-migrate-batch-status";
		if ($batch !== "" && preg_match('/^[A-Za-z0-9._-]+$/', $batch)) {
			$cmd .= " " . escapeshellarg($batch);
		}
		[$rc, $raw, $json] = migrate_exec($cmd);
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "status":
		$job = escapeshellarg($_GET["job"] ?? ($_SESSION["migrate_job"] ?? ""));
		[$rc, $raw, $json] = migrate_exec("$bin /usr/local/hestia/bin/v-migrate-status $job");
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw]);
		break;

	case "jobs_for_users":
		// jobs/ is root-only (0700); resolve via sudo CLI, not PHP glob
		$users_raw = trim($_GET["users"] ?? ($_POST["users"] ?? ""));
		$users = array_values(array_filter(array_map("trim", preg_split('/[\s,]+/', $users_raw))));
		if (!$users) {
			echo json_encode(["ok" => true, "jobs" => []]);
			exit();
		}
		$cmd = "$bin /usr/local/hestia/bin/v-migrate-jobs-for-users";
		foreach ($users as $u) {
			if (!preg_match('/^[A-Za-z0-9._-]+$/', $u)) {
				continue;
			}
			$cmd .= " " . escapeshellarg($u);
		}
		[$rc, $raw, $json] = migrate_exec($cmd);
		echo $json
			? json_encode($json)
			: json_encode(["ok" => false, "error" => $raw ?: "jobs lookup failed", "code" => $rc]);
		break;

	case "inspect":
		$job = escapeshellarg($_GET["job"] ?? $_POST["job"] ?? ($_SESSION["migrate_job"] ?? ""));
		[$rc, $raw, $json] = migrate_exec("$bin /usr/local/hestia/bin/v-migrate-inspect-job $job");
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "repair":
		$job = escapeshellarg($_POST["job"] ?? ($_SESSION["migrate_job"] ?? ""));
		$repair_action = escapeshellarg(trim($_POST["repair_action"] ?? ""));
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-repair $job $repair_action"
		);
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "verify":
		$job = escapeshellarg($_POST["job"] ?? ($_SESSION["migrate_job"] ?? ""));
		$le = ($_POST["enable_le"] ?? "") === "yes" ? "yes" : "no";
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-verify $job " . escapeshellarg($le)
		);
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw]);
		break;

	case "list_jobs":
		$limit = preg_replace("/[^0-9]/", "", (string) ($_GET["limit"] ?? $_POST["limit"] ?? "50"));
		if ($limit === "") {
			$limit = "50";
		}
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-list-jobs " . escapeshellarg($limit)
		);
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "wipe_session":
		$session = trim($_POST["session"] ?? ($_SESSION["migrate_session"] ?? ""));
		if ($session === "") {
			echo json_encode(["ok" => false, "error" => "no session"]);
			exit();
		}
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-wipe-session " . escapeshellarg($session)
		);
		unset($_SESSION["migrate_session"]);
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "delete_job":
		$job = trim($_POST["job"] ?? "");
		if ($job === "" || !preg_match('/^[A-Za-z0-9._-]+$/', $job)) {
			echo json_encode(["ok" => false, "error" => "invalid job"]);
			exit();
		}
		[$rc, $raw, $json] = migrate_exec(
			"$bin /usr/local/hestia/bin/v-migrate-delete-job " . escapeshellarg($job)
		);
		if (is_array($json) && !empty($json["ok"])) {
			if (($_SESSION["migrate_job"] ?? "") === $job) {
				unset($_SESSION["migrate_job"]);
			}
		}
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	default:
		echo json_encode(["ok" => false, "error" => "unknown action"]);
}
