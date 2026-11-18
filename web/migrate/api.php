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
		foreach ($users as $u) {
			[$rc, $raw, $json] = migrate_exec(
				"$bin /usr/local/hestia/bin/v-migrate-analyze " .
					escapeshellarg($session) .
					" " .
					escapeshellarg($u)
			);
			$results[] = $json ?: ["ok" => false, "user" => $u, "verdict" => "blocked", "error" => $raw, "code" => $rc];
		}
		echo json_encode(["ok" => true, "results" => $results]);
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
		if ($session === "" || !$users) {
			echo json_encode(["ok" => false, "error" => "session and users required"]);
			exit();
		}
		$cmd = "$bin /usr/local/hestia/bin/v-migrate-start-batch " . escapeshellarg($session) . " " . escapeshellarg($accept);
		foreach ($users as $u) {
			$cmd .= " " . escapeshellarg($u);
		}
		[$rc, $raw, $json] = migrate_exec($cmd);
		if (is_array($json) && !empty($json["first_job"])) {
			$_SESSION["migrate_job"] = $json["first_job"];
			$_SESSION["migrate_batch_users"] = $users;
		}
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw, "code" => $rc]);
		break;

	case "status":
		$job = escapeshellarg($_GET["job"] ?? ($_SESSION["migrate_job"] ?? ""));
		[$rc, $raw, $json] = migrate_exec("$bin /usr/local/hestia/bin/v-migrate-status $job");
		echo $json ? json_encode($json) : json_encode(["ok" => false, "error" => $raw]);
		break;

	case "jobs_for_users":
		$users_raw = trim($_GET["users"] ?? ($_POST["users"] ?? ""));
		$users = array_values(array_filter(array_map("trim", preg_split('/[\s,]+/', $users_raw))));
		$dir = "/usr/local/hestia/data/hestia-migrate/jobs";
		$found = [];
		foreach ($users as $u) {
			$matches = glob("$dir/*-$u");
			if ($matches) {
				rsort($matches);
				$found[$u] = basename($matches[0]);
			}
		}
		echo json_encode(["ok" => true, "jobs" => $found]);
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
