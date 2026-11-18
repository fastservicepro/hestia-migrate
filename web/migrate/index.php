<?php
// hestia-migrate wizard — admin only
ob_start();
include $_SERVER["DOCUMENT_ROOT"] . "/inc/main.php";

if ($_SESSION["userContext"] !== "admin" || !empty($_SESSION["look"])) {
	header("Location: /list/user/");
	exit();
}

$hmig = $_SESSION["HESTIA_MIGRATE"] ?? "true";
if ($hmig !== "true" && $hmig !== "yes") {
	$_SESSION["error_msg"] = _("User Import plugin is disabled. Enable it under Settings → Plugins.");
	header("Location: /edit/server/");
	exit();
}

$TAB = "USER";
$v_session = $_SESSION["migrate_session"] ?? "";
render_page($_SESSION["user"], $TAB, "migrate");
