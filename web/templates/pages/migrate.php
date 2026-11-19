<link rel="stylesheet" href="/migrate/assets/migrate.css">

<!-- Begin toolbar -->
<div class="toolbar">
	<div class="toolbar-inner">
		<div class="toolbar-buttons">
			<a class="button button-secondary button-back js-button-back" href="/list/user/">
				<i class="fas fa-arrow-left icon-blue"></i><?= tohtml(_("Back")) ?>
			</a>
			<button type="button" class="button button-secondary" id="hmig-goto-history">
				<i class="fas fa-clock-rotate-left icon-orange"></i><?= tohtml(_("History")) ?>
			</button>
		</div>
		<div class="toolbar-buttons">
			<span class="u-text-small" id="hmig-version">
				<i class="fas fa-people-arrows icon-purple"></i>
				hestia-migrate
				<?= tohtml(trim(@file_get_contents("/usr/local/hestia-migrate/VERSION") ?: "")) ?>
			</span>
		</div>
	</div>
</div>
<!-- End toolbar -->

<div class="container units">
	<div class="hmig-wrap" id="hmig-app"
		data-token="<?= htmlentities($_SESSION["token"] ?? "") ?>"
		data-session="<?= htmlentities($_SESSION["migrate_session"] ?? "") ?>"
		data-job="<?= htmlentities($_SESSION["migrate_job"] ?? "") ?>">

		<ol class="hmig-steps">
			<li class="is-active" data-step="1"><i class="fas fa-server"></i> <?= _("Server") ?></li>
			<li data-step="2"><i class="fas fa-users"></i> <?= _("Users") ?></li>
			<li data-step="3"><i class="fas fa-clipboard-check"></i> <?= _("Analysis") ?></li>
			<li data-step="4"><i class="fas fa-cloud-arrow-down"></i> <?= _("Transfer") ?></li>
			<li data-step="5"><i class="fas fa-wrench"></i> <?= _("Repair") ?></li>
			<li data-step="6"><i class="fas fa-globe"></i> <?= _("DNS") ?></li>
		</ol>

		<section class="hmig-panel is-active" data-panel="1">
			<h1 class="u-mb10">
				<i class="fas fa-people-arrows icon-purple"></i>
				<?= _("Import user from another Hestia server") ?>
			</h1>
			<p class="u-mb20"><?= _("Connect over SSH to the SOURCE Hestia server (the old one). Password is used once and not stored. A temporary key is created for the session and wiped when you disconnect or after import finishes.") ?></p>
			<p class="u-mb20 u-text-small"><?= _("On this destination server, sshpass is recommended:") ?> <code>apt-get install -y sshpass</code></p>
			<form id="hmig-connect-form" class="form">
				<div class="form-group">
					<label class="form-label" for="hmig-host">
						<i class="fas fa-network-wired icon-blue"></i> <?= _("Source hostname or IP") ?>
					</label>
					<input class="form-control" type="text" id="hmig-host" name="host" required placeholder="source.example.com" autocomplete="off">
					<span class="hint"><?= _("Not this server — the remote Hestia you import FROM") ?></span>
				</div>
				<div class="form-group">
					<label class="form-label" for="hmig-port">
						<i class="fas fa-ethernet icon-blue"></i> <?= _("SSH port") ?>
					</label>
					<input class="form-control" type="number" id="hmig-port" name="port" value="22" min="1" max="65535">
				</div>
				<div class="hmig-grid">
					<div class="form-group">
						<label class="form-label" for="hmig-ssh-user">
							<i class="fas fa-terminal icon-orange"></i> <?= _("SSH login") ?>
						</label>
						<input class="form-control" type="text" id="hmig-ssh-user" name="ssh_user" value="root" required autocomplete="username">
					</div>
					<div class="form-group">
						<label class="form-label" for="hmig-password">
							<i class="fas fa-key icon-orange"></i> <?= _("SSH password") ?>
						</label>
						<input class="form-control" type="password" id="hmig-password" name="password" required autocomplete="current-password">
					</div>
				</div>
				<button type="submit" class="button" id="hmig-connect-btn">
					<i class="fas fa-users"></i> <?= _("Connect &amp; list users") ?>
				</button>
				<button type="button" class="button button-secondary" id="hmig-disconnect-btn" hidden>
					<i class="fas fa-shield-halved"></i> <?= _("Disconnect &amp; wipe SSH keys") ?>
				</button>
			</form>
			<pre class="hmig-log" id="hmig-connect-log" hidden></pre>

			<div class="u-mt20" id="hmig-recent-wrap">
				<h2 class="u-mb10"><i class="fas fa-clock-rotate-left"></i> <?= _("Recent imports") ?></h2>
				<p class="u-mb10 u-text-small"><?= _("Open a job to repair, or delete it to free disk (removes history + leftover archive).") ?></p>
				<div id="hmig-recent-list" class="hmig-history-list"></div>
			</div>
		</section>

		<section class="hmig-panel" data-panel="2">
			<h1 class="u-mb10"><i class="fas fa-users icon-blue"></i> <?= _("Select users to import") ?></h1>
			<p class="u-mb10" id="hmig-remote-label"></p>
			<p class="u-mb10 u-text-small" id="hmig-users-count"></p>
			<div class="u-mb10">
				<button type="button" class="button button-secondary" id="hmig-select-all"><i class="fas fa-check-double"></i> <?= _("Select all") ?></button>
				<button type="button" class="button button-secondary" id="hmig-select-none"><i class="fas fa-xmark"></i> <?= _("Clear") ?></button>
				<button type="button" class="button" id="hmig-analyze-selected" disabled>
					<i class="fas fa-clipboard-check"></i> <?= _("Check compatibility") ?>
				</button>
				<button type="button" class="button button-secondary" id="hmig-disconnect-btn-2">
					<i class="fas fa-shield-halved"></i> <?= _("Wipe SSH keys") ?>
				</button>
			</div>
			<div class="table-wrapper">
				<table class="units-table">
					<thead>
						<tr>
							<th></th>
							<th><?= _("User") ?></th>
							<th><?= _("Package") ?></th>
							<th><?= _("Disk") ?></th>
							<th><?= _("Web") ?></th>
							<th><?= _("DB") ?></th>
							<th><?= _("Mail") ?></th>
							<th><?= _("Role") ?></th>
						</tr>
					</thead>
					<tbody id="hmig-users-body">
						<tr><td colspan="8"><?= _("Loading…") ?></td></tr>
					</tbody>
				</table>
			</div>
		</section>

		<section class="hmig-panel" data-panel="3">
			<h1 class="u-mb10"><i class="fas fa-clipboard-check icon-blue"></i> <?= _("Compatibility &amp; preview") ?></h1>
			<p class="u-mb10"><?= _("Review what will be imported for each selected account before starting.") ?></p>
			<div id="hmig-batch-summary" class="hmig-box u-mb20"></div>
			<div id="hmig-software-box" class="hmig-box u-mb20" hidden></div>
			<div id="hmig-batch-results"></div>
			<label class="u-mt10" id="hmig-accept-wrap" hidden>
				<input type="checkbox" id="hmig-accept"> <?= _("I accept warnings and want to continue") ?>
			</label>
			<label class="u-mt10" id="hmig-accept-sw-wrap" hidden>
				<input type="checkbox" id="hmig-accept-sw"> <?= _("Install the listed PHP versions on this server before importing (via Hestia multiphp)") ?>
			</label>
			<div class="u-mt20">
				<button type="button" class="button button-secondary" id="hmig-back-users">
					<i class="fas fa-arrow-left"></i> <?= _("Back") ?>
				</button>
				<button type="button" class="button" id="hmig-start" disabled>
					<i class="fas fa-people-arrows"></i> <?= _("Import selected") ?>
				</button>
			</div>
		</section>

		<section class="hmig-panel" data-panel="4">
			<h1 class="u-mb10"><i class="fas fa-cloud-arrow-down icon-blue"></i> <?= _("Transfer in progress") ?></h1>
			<div class="hmig-progress">
				<div class="hmig-progress-bar" id="hmig-bar" style="width:0%"></div>
			</div>
			<p id="hmig-progress-msg" class="u-mt10"></p>
			<div id="hmig-job-cards" class="u-mt10"></div>
			<pre class="hmig-log" id="hmig-progress-log"></pre>
			<button type="button" class="button button-secondary u-mt10" id="hmig-goto-repair" hidden>
				<i class="fas fa-wrench"></i> <?= _("Open repair for failed / partial jobs") ?>
			</button>
		</section>

		<section class="hmig-panel" data-panel="5">
			<h1 class="u-mb10"><i class="fas fa-wrench icon-orange"></i> <?= _("Repair incomplete import") ?></h1>
			<p class="u-mb10"><?= _("Select a job from history. If the archive is already on this server but something failed (DB, nginx, cron…), finish it with the buttons below.") ?></p>
			<div class="form-group">
				<label class="form-label" for="hmig-repair-job-select"><?= _("Import job") ?></label>
				<select class="form-select" id="hmig-repair-job-select">
					<option value=""><?= _("Loading history…") ?></option>
				</select>
			</div>
			<div class="form-group">
				<label class="form-label" for="hmig-repair-job"><?= _("Or paste job id") ?></label>
				<input class="form-control" type="text" id="hmig-repair-job" placeholder="20260101120000-username" autocomplete="off">
			</div>
			<button type="button" class="button button-secondary" id="hmig-inspect-btn">
				<i class="fas fa-magnifying-glass"></i> <?= _("Inspect what is missing") ?>
			</button>
			<div id="hmig-inspect-out" class="u-mt20"></div>
			<div id="hmig-repair-actions" class="u-mt20"></div>
			<pre class="hmig-log" id="hmig-repair-log" hidden></pre>
		</section>

		<section class="hmig-panel" data-panel="6">
			<h1 class="u-mb10"><i class="fas fa-globe icon-blue"></i> <?= _("Local verify &amp; DNS checklist") ?></h1>
			<p><?= _("Test each site against the new IP before changing DNS at the registrar.") ?></p>
			<button type="button" class="button button-secondary u-mb20" id="hmig-verify-btn">
				<i class="fas fa-stethoscope"></i> <?= _("Probe domains on new IP") ?>
			</button>
			<div id="hmig-verify-out" class="hmig-box u-mb20"></div>
			<pre id="hmig-dns" class="hmig-box"></pre>
			<button type="button" class="button u-mt20" id="hmig-le-btn">
				<i class="fas fa-lock"></i> <?= _("DNS already switched — issue Let's Encrypt") ?>
			</button>
			<p class="u-mt10">
				<a id="hmig-user-link" href="/list/user/">
					<i class="fas fa-users"></i> <?= _("Open users list") ?>
				</a>
			</p>
		</section>

		<section class="hmig-panel" data-panel="7">
			<h1 class="u-mb10"><i class="fas fa-clock-rotate-left icon-blue"></i> <?= _("Import history") ?></h1>
			<p class="u-mb10"><?= _("Delete a job to remove its history entry and any leftover import archive under /backup.") ?></p>
			<button type="button" class="button button-secondary u-mb10" id="hmig-history-refresh">
				<i class="fas fa-rotate"></i> <?= _("Refresh") ?>
			</button>
			<div id="hmig-history-table" class="hmig-history-list"></div>
		</section>
	</div>
</div>

<script src="/migrate/assets/migrate.js"></script>
