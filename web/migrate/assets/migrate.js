(() => {
	const app = document.getElementById("hmig-app");
	if (!app) return;
	const token = app.dataset.token;
	let session = app.dataset.session || "";
	let jobId = app.dataset.job || "";
	let selectedUsers = [];
	let batchResults = [];
	let batchJobs = {};
	let batchSoftware = { needs_install: [], needs_remap: [], php_installed: [], by_version: {} };
	let batchId = "";
	let historyJobs = [];

	const $ = (sel) => document.querySelector(sel);

	function setStep(n) {
		document.querySelectorAll(".hmig-steps li").forEach((li) => {
			const s = Number(li.dataset.step);
			li.classList.toggle("is-active", s === n);
			li.classList.toggle("is-done", n <= 6 && s < n);
		});
		document.querySelectorAll(".hmig-panel").forEach((p) => {
			p.classList.toggle("is-active", Number(p.dataset.panel) === n);
		});
		if (n === 5 || n === 7 || n === 1) loadHistory();
		syncDisconnectVisibility();
	}

	function fmtBytes(n) {
		n = Number(n) || 0;
		if (n < 1024) return n + " B";
		if (n < 1048576) return (n / 1024).toFixed(1) + " KB";
		if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB";
		return (n / 1073741824).toFixed(2) + " GB";
	}

	function sanitizeHost(raw) {
		let h = (raw || "").trim();
		h = h.replace(/^https?:\/\//i, "");
		h = h.replace(/^ttps:\/\//i, "");
		h = h.split("/")[0].split("?")[0].replace(/:\d+$/, "");
		return h.trim();
	}

	function esc(s) {
		return String(s)
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/"/g, "&quot;");
	}

	function syncDisconnectVisibility() {
		const show = !!session;
		const d1 = $("#hmig-disconnect-btn");
		if (d1) d1.hidden = !show;
	}

	async function api(action, data = {}, method = "POST") {
		const opts = { method, headers: { "X-CSRF-TOKEN": token } };
		let url = `/migrate/api.php?action=${encodeURIComponent(action)}&token=${encodeURIComponent(token)}`;
		if (method === "POST") {
			const fd = new FormData();
			fd.append("token", token);
			fd.append("action", action);
			Object.entries(data).forEach(([k, v]) => fd.append(k, Array.isArray(v) ? v.join(",") : v));
			opts.body = fd;
		} else {
			Object.entries(data).forEach(([k, v]) => {
				url += `&${encodeURIComponent(k)}=${encodeURIComponent(Array.isArray(v) ? v.join(",") : v)}`;
			});
		}
		const res = await fetch(url, opts);
		const text = await res.text();
		try {
			return JSON.parse(text);
		} catch (e) {
			return { ok: false, error: text || e.message };
		}
	}

	function fmtSys(s) {
		if (!s) return "";
		return [
			`${s.hostname || ""}`,
			`OS: ${s.os_id || ""} ${s.os_ver || ""} (${s.arch || ""})`,
			`Hestia: ${s.hestia_ver || ""}`,
			`Web: ${s.web_system || ""} / ${s.proxy_system || ""}`,
			`PHP: ${s.php_versions || ""}`,
			`DB: ${s.db_engine || ""} ${s.db_ver || ""}`,
			`Free disk: ${s.disk_free_mb || "?"} MB`,
		].join("\n");
	}

	function stateBadge(state, resultOk) {
		if (state === "done" || resultOk === true) return "ok";
		if (String(state).startsWith("failed") || resultOk === false) return "blocked";
		return "warn";
	}

	function renderHistoryInto(el, jobs, limit) {
		const list = limit ? jobs.slice(0, limit) : jobs;
		if (!list.length) {
			el.innerHTML = `<p class="u-text-small">No import jobs yet.</p>`;
			return;
		}
		el.innerHTML = list
			.map((j) => {
				const badge = stateBadge(j.state, j.result_ok);
				const when = (j.started || "").replace("T", " ").slice(0, 19);
				const arch =
					j.archive_bytes > 0
						? `Archive ${fmtBytes(j.archive_bytes)}`
						: j.job_bytes > 0
							? `Job data ${fmtBytes(j.job_bytes)}`
							: "No archive left";
				return `<div class="hmig-history-item hmig-verdict ${badge}">
					<button type="button" class="hmig-history-body" data-job="${esc(j.id)}">
						<span class="hmig-history-main">
							<strong>${esc(j.user || "?")}</strong>
							<span class="u-text-small">${esc(j.state || "")}${j.percent != null ? " · " + j.percent + "%" : ""} · ${esc(arch)}</span>
						</span>
						<span class="hmig-history-meta">
							${esc(when)} · ${esc(j.host || "—")}<br>
							<code>${esc(j.id)}</code>
						</span>
					</button>
					<div class="hmig-history-actions">
						<button type="button" class="button button-secondary hmig-open-job" data-job="${esc(j.id)}">
							<i class="fas fa-wrench"></i> Repair
						</button>
						<button type="button" class="button button-secondary hmig-del-job" data-job="${esc(j.id)}" data-user="${esc(j.user || "")}">
							<i class="fas fa-trash icon-red"></i> Delete
						</button>
					</div>
				</div>`;
			})
			.join("");
		el.querySelectorAll(".hmig-history-body, .hmig-open-job").forEach((btn) => {
			btn.addEventListener("click", () => openRepairJob(btn.dataset.job));
		});
		el.querySelectorAll(".hmig-del-job").forEach((btn) => {
			btn.addEventListener("click", () => deleteJob(btn.dataset.job, btn.dataset.user));
		});
	}

	async function deleteJob(id, user) {
		const label = user ? `${user} (${id})` : id;
		if (
			!confirm(
				`Delete import history for ${label}?\n\nThis removes the job record and any leftover archive under /backup. The imported Hestia user account is NOT deleted.`
			)
		) {
			return;
		}
		const data = await api("delete_job", { job: id });
		if (!data.ok) {
			alert(data.error || "Delete failed");
			return;
		}
		const freed = fmtBytes(data.freed_bytes || 0);
		if (jobId === id) {
			jobId = "";
			$("#hmig-repair-job").value = "";
		}
		await loadHistory();
		const log = $("#hmig-connect-log");
		if (log) {
			log.hidden = false;
			log.textContent = `Deleted ${id}. Freed ${freed}.`;
		}
	}

	function fillRepairSelect(jobs) {
		const sel = $("#hmig-repair-job-select");
		if (!sel) return;
		const cur = $("#hmig-repair-job").value.trim() || jobId;
		sel.innerHTML =
			`<option value="">— select a job —</option>` +
			jobs
				.map((j) => {
					const label = `${j.user || "?"} · ${j.state || "?"} · ${j.id}`;
					return `<option value="${esc(j.id)}">${esc(label)}</option>`;
				})
				.join("");
		if (cur) {
			sel.value = cur;
			if (sel.value !== cur) {
				// keep typed id even if not in list
				$("#hmig-repair-job").value = cur;
			} else {
				$("#hmig-repair-job").value = cur;
			}
		}
	}

	async function loadHistory() {
		const data = await api("list_jobs", { limit: 50 }, "GET");
		historyJobs = data.ok ? data.jobs || [] : [];
		const recent = $("#hmig-recent-list");
		if (recent) renderHistoryInto(recent, historyJobs, 5);
		const full = $("#hmig-history-table");
		if (full) renderHistoryInto(full, historyJobs);
		fillRepairSelect(historyJobs);
	}

	function openRepairJob(id) {
		jobId = id;
		$("#hmig-repair-job").value = id;
		const sel = $("#hmig-repair-job-select");
		if (sel) sel.value = id;
		setStep(5);
		inspectJob();
	}

	function selectedFromCheckboxes() {
		return Array.from(document.querySelectorAll(".hmig-user-cb:checked")).map((el) => el.value);
	}

	function updateAnalyzeBtn() {
		selectedUsers = selectedFromCheckboxes();
		$("#hmig-analyze-selected").disabled = selectedUsers.length === 0;
	}

	async function wipeSessionKeys(reason) {
		if (!session) return { ok: true, skipped: true };
		const data = await api("wipe_session", { session });
		session = "";
		syncDisconnectVisibility();
		const log = $("#hmig-connect-log");
		if (log) {
			log.hidden = false;
			log.textContent =
				(reason ? reason + "\n" : "") +
				(data.ok
					? `SSH keys wiped${data.remote_key_removed ? " (remote + local)" : " (local; remote may need manual check)"}${
							data.warning ? " — " + data.warning : ""
					  }`
					: data.error || "wipe failed");
		}
		return data;
	}

	$("#hmig-connect-form").addEventListener("submit", async (e) => {
		e.preventDefault();
		const btn = $("#hmig-connect-btn");
		const log = $("#hmig-connect-log");
		const host = sanitizeHost($("#hmig-host").value);
		$("#hmig-host").value = host;
		const sshUser = ($("#hmig-ssh-user").value || "root").trim();
		const password = $("#hmig-password").value;
		const port = $("#hmig-port").value.trim() || "22";
		if (!host || !password) {
			log.hidden = false;
			log.textContent = "Hostname and SSH password are required.";
			return;
		}
		btn.disabled = true;
		log.hidden = false;
		log.textContent = "Connecting…";
		const data = await api("connect", { host, port, ssh_user: sshUser, password });
		$("#hmig-password").value = "";
		if (!data.ok) {
			log.textContent = data.error || JSON.stringify(data);
			btn.disabled = false;
			return;
		}
		session = data.session;
		log.textContent = `OK · SSH ${sshUser}@${host} · temporary key active (will wipe after import / disconnect)`;
		$("#hmig-remote-label").textContent = `Source: ${sshUser}@${host}`;
		syncDisconnectVisibility();
		setStep(2);
		await loadUsers();
		btn.disabled = false;
	});

	async function loadUsers() {
		const body = $("#hmig-users-body");
		body.innerHTML = `<tr><td colspan="8">Loading…</td></tr>`;
		const data = await api("list_users", { session }, "GET");
		if (!data.ok) {
			body.innerHTML = `<tr><td colspan="8"><pre class="hmig-log" style="margin:0">${esc(data.error || "error")}</pre></td></tr>`;
			$("#hmig-users-count").textContent = "";
			return;
		}
		const users = data.users || [];
		$("#hmig-users-count").textContent = `${users.length} account(s) visible to this SSH login`;
		if (!users.length) {
			body.innerHTML = `<tr><td colspan="8">No Hestia users found.</td></tr>`;
			return;
		}
		body.innerHTML = users
			.map((u) => {
				const badge = u.is_root ? ' <span class="u-text-small">(panel admin)</span>' : "";
				return `<tr>
				<td><input type="checkbox" class="hmig-user-cb" value="${esc(u.user)}"></td>
				<td><strong>${esc(u.user)}</strong>${badge}</td>
				<td>${esc(u.package || "")}</td>
				<td>${esc(String(u.disk_mb || 0))} MB</td>
				<td>${esc(String(u.web || 0))}</td>
				<td>${esc(String(u.db || 0))}</td>
				<td>${esc(String(u.mail || 0))}</td>
				<td>${esc(u.role || "")}</td>
			</tr>`;
			})
			.join("");
		body.querySelectorAll(".hmig-user-cb").forEach((cb) => cb.addEventListener("change", updateAnalyzeBtn));
		updateAnalyzeBtn();
	}

	$("#hmig-select-all").addEventListener("click", () => {
		document.querySelectorAll(".hmig-user-cb").forEach((cb) => {
			cb.checked = true;
		});
		updateAnalyzeBtn();
	});
	$("#hmig-select-none").addEventListener("click", () => {
		document.querySelectorAll(".hmig-user-cb").forEach((cb) => (cb.checked = false));
		updateAnalyzeBtn();
	});

	$("#hmig-analyze-selected").addEventListener("click", async () => {
		selectedUsers = selectedFromCheckboxes();
		if (!selectedUsers.length) return;
		setStep(3);
		$("#hmig-batch-summary").textContent = `Analyzing ${selectedUsers.length} user(s): ${selectedUsers.join(", ")}…`;
		$("#hmig-batch-results").innerHTML = "";
		$("#hmig-start").disabled = true;
		const data = await api("analyze_batch", { session, users: selectedUsers });
		if (!data.ok) {
			$("#hmig-batch-summary").textContent = data.error || "Analysis failed";
			return;
		}
		batchResults = data.results || [];
		batchSoftware = data.software || {
			needs_install: [],
			needs_remap: [],
			php_installed: [],
			by_version: {},
		};
		renderBatchResults();
	});

	function softwareReady() {
		const needInstall = batchSoftware.needs_install || [];
		const needRemap = batchSoftware.needs_remap || [];
		if (needInstall.length && !$("#hmig-accept-sw")?.checked) return false;
		for (const ver of needRemap) {
			const sel = document.querySelector(`.hmig-remap[data-from="${ver}"]`);
			if (!sel || !sel.value) return false;
		}
		return true;
	}

	function syncStartEnabled() {
		const blocked = batchResults.filter((r) => r.verdict === "blocked");
		const warn = batchResults.filter((r) => r.verdict === "warn");
		const ok = batchResults.filter((r) => r.verdict === "ok");
		const start = $("#hmig-start");
		const accept = $("#hmig-accept");
		if (blocked.length) {
			start.disabled = true;
			return;
		}
		const importable = ok.length + warn.length;
		if (!importable) {
			start.disabled = true;
			return;
		}
		const warnOk = !warn.length || accept.checked;
		start.disabled = !(warnOk && softwareReady());
	}

	function renderSoftwareBox() {
		const box = $("#hmig-software-box");
		const swWrap = $("#hmig-accept-sw-wrap");
		const swCb = $("#hmig-accept-sw");
		const needInstall = batchSoftware.needs_install || [];
		const needRemap = batchSoftware.needs_remap || [];
		const installed = batchSoftware.php_installed || [];
		const byVer = batchSoftware.by_version || {};
		if (!needInstall.length && !needRemap.length) {
			box.hidden = true;
			box.innerHTML = "";
			swWrap.hidden = true;
			swCb.checked = false;
			return;
		}
		box.hidden = false;
		const lines = [];
		lines.push(`<h3><i class="fas fa-puzzle-piece"></i> Software required before import</h3>`);
		lines.push(
			`<p class="u-text-small">PHP packages are installed with Hestia <code>v-add-web-php</code> before any backup starts. MultiPHP checkboxes in Server settings only reflect domain backends — not whether packages exist.</p>`
		);
		if (installed.length) {
			lines.push(`<p>Already on this server: <strong>${esc(installed.join(", "))}</strong></p>`);
		}
		if (needInstall.length) {
			lines.push(`<p><strong>Will install:</strong></p><ul>`);
			for (const ver of needInstall) {
				const users = (byVer[ver]?.users || []).join(", ");
				lines.push(`<li>PHP ${esc(ver)}${users ? ` — needed by ${esc(users)}` : ""}</li>`);
			}
			lines.push(`</ul>`);
		}
		if (needRemap.length) {
			const opts = installed.length
				? installed.map((v) => `<option value="${esc(v)}">${esc(v)}</option>`).join("")
				: `<option value="">(no PHP installed — install one in Hestia first)</option>`;
			lines.push(`<p><strong>Cannot install — remap required:</strong></p><ul>`);
			for (const ver of needRemap) {
				const users = (byVer[ver]?.users || []).join(", ");
				lines.push(
					`<li>PHP ${esc(ver)}${users ? ` (${esc(users)})` : ""} → <select class="form-select hmig-remap" data-from="${esc(
						ver
					)}"><option value="">Choose target…</option>${opts}</select></li>`
				);
			}
			lines.push(`</ul>`);
		}
		box.innerHTML = lines.join("");
		swWrap.hidden = needInstall.length === 0;
		swCb.checked = false;
		swCb.onchange = syncStartEnabled;
		box.querySelectorAll(".hmig-remap").forEach((sel) => sel.addEventListener("change", syncStartEnabled));
	}

	function renderBatchResults() {
		const blocked = batchResults.filter((r) => r.verdict === "blocked");
		const warn = batchResults.filter((r) => r.verdict === "warn");
		const ok = batchResults.filter((r) => r.verdict === "ok");
		$("#hmig-batch-summary").textContent =
			`Ready: ${ok.length} · Warnings: ${warn.length} · Blocked: ${blocked.length} · Selected: ${batchResults.length}`;

		renderSoftwareBox();

		$("#hmig-batch-results").innerHTML = batchResults
			.map((r) => {
				const u = r.user || r.composition?.user || "?";
				const v = r.verdict || "blocked";
				const comp = r.composition || {};
				const sw = r.software || {};
				const phpLine = (sw.php || [])
					.map((p) => `${p.backend || "?"} → PHP ${p.version || "?"} [${p.action || "?"}]`)
					.join("; ");
				const plan = (r.plan || []).map((p) => `• ${p.object}: ${p.method}`).join("\n");
				const errs = (r.errors || []).map((e) => `✗ ${e}`).join("\n");
				const warns = (r.warnings || []).map((e) => `! ${e}`).join("\n");
				return `<div class="hmig-card hmig-verdict ${v}">
					<h3><i class="fas fa-user"></i> ${esc(u)} — ${esc(v)}</h3>
					<pre class="hmig-box">${esc(
						`Package ${comp.package || ""} · home ${comp.home_mb || 0} MB · hash ${comp.hash_type || ""}\n` +
							`Web=${(comp.web || []).length} DB=${(comp.db || []).length} Mail=${(comp.mail || []).length} DNS=${(comp.dns || []).length} Cron=${comp.cron_jobs || 0}\n` +
							(phpLine ? `PHP: ${phpLine}\n` : "") +
							`\n` +
							(plan || "(no plan)") +
							(errs ? "\n\nErrors:\n" + errs : "") +
							(warns ? "\n\nWarnings:\n" + warns : "")
					)}</pre>
					<details class="u-mt10"><summary>Source / destination</summary>
						<pre class="hmig-box">${esc(fmtSys(r.source))}\n---\n${esc(fmtSys(r.destination))}</pre>
					</details>
				</div>`;
			})
			.join("");

		const acceptWrap = $("#hmig-accept-wrap");
		const start = $("#hmig-start");
		const accept = $("#hmig-accept");
		accept.checked = false;
		accept.onchange = syncStartEnabled;
		if (blocked.length) {
			acceptWrap.hidden = true;
			start.disabled = true;
			start.textContent = "Fix blocked users first";
		} else if (warn.length) {
			acceptWrap.hidden = false;
			start.innerHTML = `<i class="fas fa-people-arrows"></i> Import ${ok.length + warn.length} user(s)`;
			syncStartEnabled();
		} else {
			acceptWrap.hidden = true;
			start.innerHTML = `<i class="fas fa-people-arrows"></i> Import ${ok.length} user(s)`;
			syncStartEnabled();
		}
	}

	$("#hmig-back-users").addEventListener("click", () => setStep(2));

	$("#hmig-start").addEventListener("click", async () => {
		const importable = batchResults
			.filter((r) => r.verdict === "ok" || r.verdict === "warn")
			.map((r) => r.user || r.composition?.user)
			.filter(Boolean);
		if (!importable.length) return;
		if (!softwareReady()) {
			alert("Confirm PHP install and/or choose remap targets before starting.");
			return;
		}
		setStep(4);
		$("#hmig-bar").style.width = "5%";
		$("#hmig-progress-msg").textContent = `Starting import of ${importable.length} user(s)…`;
		$("#hmig-goto-repair").hidden = true;
		const accept = $("#hmig-accept").checked ? "yes" : "no";
		const acceptSw = $("#hmig-accept-sw")?.checked ? "yes" : "no";
		const installPhp = (batchSoftware.needs_install || []).join(",");
		const remapParts = [];
		document.querySelectorAll(".hmig-remap").forEach((sel) => {
			if (sel.dataset.from && sel.value) remapParts.push(`${sel.dataset.from}:${sel.value}`);
		});
		const data = await api("transfer_batch", {
			session,
			users: importable,
			accept_warnings: accept,
			accept_software: acceptSw,
			install_php: installPhp || "none",
			remap_php: remapParts.join(",") || "none",
		});
		$("#hmig-progress-log").textContent = JSON.stringify(data, null, 2);
		if (!data.ok) {
			$("#hmig-progress-msg").textContent = data.error || "Transfer failed to start";
			return;
		}
		jobId = data.first_job || "";
		batchId = data.batch_id || "";
		await pollBatch(importable);
	});

	async function pollBatch(users) {
		for (;;) {
			let batchSt = null;
			if (batchId) {
				batchSt = await api("batch_status", { batch: batchId }, "GET");
				if (batchSt?.ok) {
					const bp = Number(batchSt.percent) || 0;
					if (batchSt.stage === "prep" || batchSt.stage === "prep_php" || batchSt.stage === "queued") {
						$("#hmig-bar").style.width = `${Math.max(5, bp)}%`;
						$("#hmig-progress-msg").textContent = batchSt.message || "Preparing software…";
						$("#hmig-job-cards").innerHTML = `<div class="hmig-card">… ${esc(
							batchSt.message || "Installing PHP / preparing batch"
						)}</div>`;
						if (batchSt.prep && Object.keys(batchSt.prep).length) {
							$("#hmig-progress-log").textContent = JSON.stringify(batchSt.prep, null, 2);
						}
						if (batchSt.stage === "failed") {
							$("#hmig-progress-msg").textContent = batchSt.message || "Batch failed during prep";
							$("#hmig-goto-repair").hidden = false;
							return;
						}
						await new Promise((r) => setTimeout(r, 2000));
						continue;
					}
					if (batchSt.stage === "failed") {
						$("#hmig-progress-msg").textContent = batchSt.message || "Batch failed";
						$("#hmig-progress-log").textContent = batchSt.log_tail || JSON.stringify(batchSt, null, 2);
						$("#hmig-goto-repair").hidden = false;
						return;
					}
				}
			}

			const map = await api("jobs_for_users", { users }, "GET");
			if (map && map.ok === false) {
				$("#hmig-progress-msg").textContent =
					map.error || "Cannot read job status (sudo / jobs-for-users). Reinstall hestia-migrate 1.2.6+.";
				$("#hmig-progress-log").textContent = JSON.stringify(map, null, 2);
			}
			batchJobs = map.jobs || {};
			const cards = [];
			let done = 0;
			let failed = 0;
			let running = 0;
			let activeUser = null;
			const jobCount = Object.keys(batchJobs).length;
			for (const u of users) {
				const jid = batchJobs[u];
				if (!jid) {
					const qmsg =
						batchSt && (batchSt.stage === "prep_done" || batchSt.stage === "transfer")
							? "queued · waiting for previous user (batch is sequential)"
							: "queued · waiting for software prep / previous user";
					cards.push(`<div class="hmig-card">⏳ <strong>${esc(u)}</strong> · ${qmsg}</div>`);
					running++;
					continue;
				}
				const st = await api("status", { job: jid }, "GET");
				const state = st.state || st.progress?.stage || "?";
				const pct = Number(st.progress?.percent) || 0;
				const msg = st.progress?.message || state;
				const isFailed = state === "failed" || String(state).startsWith("failed");
				const isDone = state === "done" || !!st.result?.ok;
				if (isDone) done++;
				else if (isFailed) failed++;
				else {
					running++;
					activeUser = u;
				}
				const icon = isFailed ? "✗" : isDone ? "✓" : "…";
				cards.push(
					`<div class="hmig-card">${icon} <strong>${esc(u)}</strong> · ${esc(state)} · ${pct}% · ${esc(msg)}
					${isFailed ? ` <button type="button" class="button button-secondary hmig-open-repair" data-job="${esc(jid)}">Repair</button>` : ""}
					</div>`
				);
				if (!jobId) jobId = jid;
			}
			$("#hmig-job-cards").innerHTML = cards.join("");
			document.querySelectorAll(".hmig-open-repair").forEach((b) =>
				b.addEventListener("click", () => openRepairJob(b.dataset.job))
			);
			const total = users.length;
			const pctAll = Math.round(((done + failed) / total) * 100);
			const batchPct = Number(batchSt?.percent) || 0;
			$("#hmig-bar").style.width = `${Math.max(5, pctAll || batchPct || (activeUser ? 20 : 5))}%`;
			$("#hmig-progress-msg").textContent = activeUser
				? `Running ${activeUser} · Done ${done}/${total} · Failed ${failed} · Queued ${Math.max(0, running - 1)}`
				: jobCount === 0 && batchSt?.message
					? batchSt.message
					: `Done ${done}/${total} · Failed ${failed} · Running/queued ${running}`;
			if (failed) $("#hmig-goto-repair").hidden = false;

			const batchDone = batchSt && !batchSt.running && (batchSt.stage === "done" || batchSt.stage === "failed");
			if (done + failed >= total && (jobCount >= total || batchDone)) {
				if (batchSt?.stage === "failed" && done + failed < total) {
					$("#hmig-progress-msg").textContent = batchSt.message || "Batch failed";
					$("#hmig-goto-repair").hidden = false;
					return;
				}
				await wipeSessionKeys("Import finished — wiping temporary SSH keys.");
				await loadHistory();
				if (failed === 0) {
					await loadDns();
					setStep(6);
				} else {
					$("#hmig-progress-msg").textContent += " — open Repair to finish incomplete accounts.";
				}
				return;
			}
			if (batchDone && jobCount === 0) {
				$("#hmig-progress-msg").textContent = batchSt.message || "Batch ended before jobs started";
				$("#hmig-progress-log").textContent = batchSt.log_tail || JSON.stringify(batchSt, null, 2);
				$("#hmig-goto-repair").hidden = false;
				return;
			}
			await new Promise((r) => setTimeout(r, 2000));
		}
	}

	$("#hmig-goto-repair").addEventListener("click", () => {
		const failedJob = Object.values(batchJobs).find(Boolean) || jobId;
		if (failedJob) openRepairJob(failedJob);
		else {
			setStep(5);
			loadHistory();
		}
	});

	$("#hmig-goto-history").addEventListener("click", () => setStep(7));
	$("#hmig-history-refresh")?.addEventListener("click", () => loadHistory());

	document.querySelectorAll(".hmig-steps li").forEach((li) => {
		li.addEventListener("click", () => {
			const n = Number(li.dataset.step);
			if ([1, 5, 6].includes(n) || (n === 2 && session)) setStep(n);
		});
	});

	$("#hmig-repair-job-select").addEventListener("change", () => {
		const v = $("#hmig-repair-job-select").value;
		if (v) {
			$("#hmig-repair-job").value = v;
			inspectJob();
		}
	});

	async function inspectJob() {
		const job = $("#hmig-repair-job").value.trim() || $("#hmig-repair-job-select").value || jobId;
		if (!job) {
			$("#hmig-inspect-out").textContent = "Select a job from the list";
			return;
		}
		jobId = job;
		$("#hmig-repair-job").value = job;
		$("#hmig-inspect-out").textContent = "Inspecting…";
		const data = await api("inspect", { job }, "GET");
		if (!data.ok) {
			$("#hmig-inspect-out").innerHTML = `<pre class="hmig-log">${esc(data.error || "error")}</pre>`;
			return;
		}
		const miss = (data.missing || [])
			.map((m) => `<li><strong>${esc(m.title)}</strong> — ${esc(m.detail || "")}</li>`)
			.join("");
		$("#hmig-inspect-out").innerHTML = `
			<div class="hmig-verdict ${data.missing?.length ? "warn" : "ok"}">
				User <strong>${esc(data.user)}</strong> · state ${esc(data.state)} ·
				archive ${data.archive?.present ? "present (" + esc(data.archive.name) + ")" : "MISSING"}
			</div>
			<pre class="hmig-box">${esc(JSON.stringify(data.local, null, 2))}</pre>
			<h3>Missing / incomplete</h3>
			<ul class="hmig-list">${miss || "<li>Nothing critical detected</li>"}</ul>
		`;
		const actions = data.actions || [];
		const extra = [
			{ id: "restore_all", label: "Restore everything from archive" },
			{ id: "fix_nginx", label: "Fix nginx & reload" },
			{ id: "hold_le", label: "Hold Let's Encrypt" },
		];
		const all = [...actions];
		for (const e of extra) {
			if (!all.find((a) => a.id === e.id)) all.push(e);
		}
		$("#hmig-repair-actions").innerHTML = all
			.map(
				(a) =>
					`<button type="button" class="button button-secondary hmig-repair-btn u-mb10" data-action="${esc(
						a.id
					)}"><i class="fas fa-play"></i> ${esc(a.label || a.id)}</button> `
			)
			.join("");
		document.querySelectorAll(".hmig-repair-btn").forEach((btn) => {
			btn.addEventListener("click", () => runRepair(btn.dataset.action));
		});
	}

	$("#hmig-inspect-btn").addEventListener("click", inspectJob);

	async function runRepair(repairAction) {
		const job = $("#hmig-repair-job").value.trim() || jobId;
		const log = $("#hmig-repair-log");
		log.hidden = false;
		log.textContent = `Running ${repairAction}…`;
		const data = await api("repair", { job, repair_action: repairAction });
		log.textContent = JSON.stringify(data, null, 2);
		await inspectJob();
		await loadHistory();
	}

	async function loadDns() {
		if (!jobId) return;
		const st = await api("status", { job: jobId }, "GET");
		const checklist = st.dns_checklist || {};
		const lines = (checklist.records || []).map((r) => `${r.type}\t${r.name}\t→\t${r.value}`);
		$("#hmig-dns").textContent =
			(lines.join("\n") || "No web domains in checklist yet — use Repair/Verify after import.") +
			`\n\nPrimary IP: ${checklist.primary_ip || ""}\n${checklist.note || ""}`;
	}

	$("#hmig-verify-btn").addEventListener("click", async () => {
		$("#hmig-verify-out").textContent = "Probing…";
		const data = await api("verify", { job: jobId, enable_le: "no" });
		$("#hmig-verify-out").textContent = JSON.stringify(data.probes || data, null, 2);
	});
	$("#hmig-le-btn").addEventListener("click", async () => {
		if (!confirm("Issue Let's Encrypt now? Public DNS must already point here.")) return;
		const data = await api("verify", { job: jobId, enable_le: "yes" });
		$("#hmig-verify-out").textContent = JSON.stringify(data, null, 2);
	});

	async function onDisconnect() {
		if (!session) return;
		if (!confirm("Disconnect and permanently wipe temporary SSH keys on this server and (if reachable) the source?"))
			return;
		await wipeSessionKeys("Disconnected.");
		setStep(1);
	}
	$("#hmig-disconnect-btn")?.addEventListener("click", onDisconnect);
	$("#hmig-disconnect-btn-2")?.addEventListener("click", onDisconnect);

	if (jobId) {
		$("#hmig-repair-job").value = jobId;
	}
	syncDisconnectVisibility();
	loadHistory();
})();
