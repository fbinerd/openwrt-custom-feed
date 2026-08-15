"use strict";
"require view";
"require rpc";
"require ui";
"require request";

return view.extend({
	callListEnv: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "list_env",
		expect: {},
	}),

	callBackup: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "backup",
		expect: {},
	}),

	callSetEnv: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "set_env",
		params: ["name", "value"],
		expect: {},
	}),

	callRemoveEnv: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "remove_env",
		params: ["name"],
		expect: {},
	}),

	callWriteEnv: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "write_env",
		expect: {},
	}),

	load: function () {
		return this.callListEnv();
	},

	renderResult: function (res) {
		var ok = res && res.ok;
		var banner = E(
			"p",
			{ class: ok ? "alert-message success" : "alert-message error" },
			ok ? _("OK.") : _("Failed - see details below.")
		);
		var out = E("pre", {}, (res && res.output) || _("(no output)"));
		return E("div", {}, [banner, out]);
	},

	showResultModal: function (title, res) {
		ui.showModal(title, [
			this.renderResult(res),
			E("div", { class: "right" }, [E("button", { class: "btn cbi-button", click: ui.hideModal }, _("Close"))]),
		]);
	},

	setBusy: function (btn, busyLabel) {
		btn.disabled = true;
		btn.dataset.label = btn.textContent;
		btn.textContent = busyLabel;
		btn.classList.add("spinning");
	},

	clearBusy: function (btn) {
		btn.disabled = false;
		btn.textContent = btn.dataset.label;
		btn.classList.remove("spinning");
	},

	// Same raw multipart POST mechanism as the Dual-Key Patch page's
	// upload-and-write - not base64-through-ubus (30s timeout / size).
	uploadFile: function (file, targetPath, progressCb) {
		var data = new FormData();
		data.append("sessionid", L.env.sessionid);
		data.append("filename", targetPath);
		data.append("filedata", file);

		return request
			.post(L.env.cgi_base + "/cgi-upload", data, { progress: progressCb })
			.then(function (res) {
				var reply = res.json();
				if (reply && reply.failure)
					throw new Error(_("Upload failed: %s").format(reply.message || _("unknown error")));
				return reply;
			});
	},

	refreshEnvList: function () {
		return this.callListEnv().then(
			L.bind(function (res) {
				this.renderEnvList(res && res.ok ? res.vars || [] : []);
				if (!res || !res.ok)
					ui.addNotification(null, E("p", _("Failed to read env: %s").format((res && res.output) || _("unknown error"))), "error");
			}, this)
		);
	},

	handleBackup: function (ev) {
		var btn = ev.target;
		this.setBusy(btn, _("Backing up..."));
		return this.callBackup()
			.then(function (res) {
				if (!res || !res.ok || !res.url) {
					ui.addNotification(null, E("p", _("Backup failed: %s").format((res && res.output) || _("unknown error"))), "error");
					return;
				}
				var a = E("a", { href: res.url, download: res.filename || "appsbl-env-backup.bin" });
				document.body.appendChild(a);
				a.click();
				a.remove();
				ui.addNotification(null, E("p", _("Backup downloaded (%s).").format(res.filename || "appsbl-env-backup.bin")), "info");
			})
			.catch(function (e) {
				ui.addNotification(null, E("p", _("Backup failed: %s").format(e.message)), "error");
			})
			.finally(
				L.bind(function () {
					this.clearBusy(btn);
				}, this)
			);
	},

	handleSaveVar: function (nameEl, valueInput, status, isNew, ev) {
		var btn = ev.target;
		var name = isNew ? nameEl.value.trim() : nameEl;
		var value = valueInput.value;

		if (!name) {
			status.textContent = _("Variable name is required.");
			status.className = "cbi-value-description alert-message error";
			return;
		}

		this.setBusy(btn, _("Saving..."));
		this.callSetEnv(name, value)
			.then(
				L.bind(function (res) {
					if (res && res.ok) {
						if (isNew) this.envAddRowEl.replaceChildren();
						return this.refreshEnvList();
					} else {
						status.textContent = (res && res.output) || _("Failed - see output.");
						status.className = "cbi-value-description alert-message error";
					}
				}, this)
			)
			.catch(
				L.bind(function (e) {
					status.textContent = e.message;
					status.className = "cbi-value-description alert-message error";
				}, this)
			)
			.finally(
				L.bind(function () {
					this.clearBusy(btn);
				}, this)
			);
	},

	handleRemoveVar: function (name, ev) {
		var btn = ev.target;

		if (!confirm(_("Delete env variable '%s'? This writes to 0:appsblenv immediately.").format(name)))
			return;

		this.setBusy(btn, _("Deleting..."));
		this.callRemoveEnv(name)
			.then(
				L.bind(function (res) {
					if (!res || !res.ok)
						ui.addNotification(null, E("p", _("Delete failed: %s").format((res && res.output) || _("unknown error"))), "error");
					return this.refreshEnvList();
				}, this)
			)
			.catch(
				L.bind(function (e) {
					ui.addNotification(null, E("p", _("Delete failed: %s").format(e.message)), "error");
				}, this)
			)
			.finally(
				L.bind(function () {
					this.clearBusy(btn);
				}, this)
			);
	},

	renderVarRow: function (name, value, isNew) {
		var nameEl = isNew ? E("input", { type: "text", placeholder: "name" }) : E("code", {}, name);
		var valueInput = E("input", { type: "text", value: value || "" });
		var status = E("span", { class: "cbi-value-description" }, "");
		var saveBtn = E("button", { class: "btn cbi-button" }, _("Save"));

		var fieldChildren = [valueInput, " ", saveBtn];
		if (!isNew) {
			var removeBtn = E("button", { class: "btn cbi-button-negative" }, _("Remove"));
			removeBtn.addEventListener("click", L.bind(this.handleRemoveVar, this, name));
			fieldChildren.push(" ", removeBtn);
		}
		fieldChildren.push(status);

		var row = E("div", { class: "cbi-value" }, [
			E("label", { class: "cbi-value-title" }, [nameEl]),
			E("div", { class: "cbi-value-field" }, fieldChildren),
		]);

		saveBtn.addEventListener("click", L.bind(this.handleSaveVar, this, nameEl, valueInput, status, !!isNew));

		return row;
	},

	renderEnvList: function (vars) {
		var rows = [];
		for (var i = 0; i < vars.length; i++)
			rows.push(this.renderVarRow(vars[i].name, vars[i].value, false));

		this.envListEl.replaceChildren.apply(
			this.envListEl,
			rows.length ? rows : [E("p", { class: "cbi-value-description" }, _("(no variables)"))]
		);
	},

	handleAddVar: function () {
		this.envAddRowEl.replaceChildren(this.renderVarRow("", "", true));
	},

	handleWriteEnv: function (fileInput, ev) {
		var openerBtn = ev.target;
		var file = fileInput.files[0];

		if (!file) {
			ui.addNotification(null, E("p", _("Choose a file first.")), "error");
			return;
		}

		ui.showModal(_("Write uploaded file to 0:appsblenv"), [
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"This writes the uploaded file to the U-Boot environment " +
						"partition AS-IS. No structural checks beyond its size - " +
						"only use this with a file you know is a genuine 0:appsblenv " +
						"image, such as your own earlier backup. Research-only " +
						"software, no warranty - proceeding is entirely at your own risk."
				)
			),
			E("div", { class: "right" }, [
				E("button", { class: "btn", click: ui.hideModal }, _("Cancel")),
				" ",
				E(
					"button",
					{
						class: "btn cbi-button cbi-button-negative important",
						click: L.bind(function () {
							ui.hideModal();
							this.setBusy(openerBtn, _("Uploading..."));
							ui.showModal(_("Uploading..."), [E("p", { class: "spinning" }, _("Uploading file..."))]);
							this.uploadFile(
								file,
								"/tmp/appsbl-env-upload.bin",
								L.bind(function (ev2) {
									ui.showModal(_("Uploading..."), [
										E("p", { class: "spinning" }, _("Uploading file... %.0f%%").format((ev2.loaded / ev2.total) * 100)),
									]);
								}, this)
							)
								.then(
									L.bind(function () {
										ui.showModal(_("Writing..."), [E("p", { class: "spinning" }, _("Writing 0:appsblenv - do not power off..."))]);
										return this.callWriteEnv();
									}, this)
								)
								.then(
									L.bind(function (res) {
										ui.hideModal();
										this.showResultModal(_("Write uploaded file to 0:appsblenv"), res);
										if (res && res.ok) fileInput.value = "";
										return this.refreshEnvList();
									}, this)
								)
								.catch(
									L.bind(function (e) {
										ui.hideModal();
										this.showResultModal(_("Write uploaded file to 0:appsblenv"), { ok: false, output: e.message });
									}, this)
								)
								.finally(
									L.bind(function () {
										this.clearBusy(openerBtn);
									}, this)
								);
						}, this),
					},
					_("Upload and write")
				),
			]),
		]);
	},

	render: function (data) {
		var initialVars = (data && data.ok ? data.vars : []) || [];

		var envRestoreFileInput = E("input", { type: "file" });

		this.envListEl = E("div", {});
		this.envAddRowEl = E("div", {});

		var page = E([
			E("h2", _("APPSBL Environment (envs)")),
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"WARNING: research-only, no-warranty software that can rewrite " +
						"your device's U-Boot environment, including bootcmd. Read the " +
						"safety notes below before using any button on this page. " +
						"Using this tool is entirely at your own risk - you, not the " +
						"authors of this tool, are responsible for what happens to " +
						"your device."
				)
			),
			E(
				"p",
				_(
					"Reads, backs up, and edits the 0:appsblenv (U-Boot environment) " +
						"partition on a Mercusys MR80X v2/v5 - the TP-Link-family device " +
						"this package currently supports. This project has NO captured " +
						"reference for a genuine untouched OEM-factory env - only for " +
						"this project's own known-good baseline (see the OEM Recovery " +
						"tab)."
				)
			),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Backup / restore")),
				E(
					"p",
					_(
						"Backup reads the current 0:appsblenv and downloads it - always do " +
							"this before writing anything. Restore writes an uploaded file " +
							"back to 0:appsblenv as-is (no structural checks beyond size) - " +
							"use it with a file you know is a genuine 0:appsblenv image, " +
							"such as your own earlier backup."
					)
				),
				E("div", { class: "right" }, [
					E("button", { class: "btn cbi-button", click: L.bind(this.handleBackup, this) }, _("Backup 0:appsblenv")),
					" ",
					envRestoreFileInput,
					" ",
					E(
						"button",
						{ class: "btn cbi-button-negative", click: L.bind(this.handleWriteEnv, this, envRestoreFileInput) },
						_("Restore from file...")
					),
				]),
			]),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Environment variables")),
				E("p", _("Free edit - any variable, no restrictions. Changes write to 0:appsblenv immediately.")),
				this.envListEl,
				E("div", { class: "right", style: "margin-top: 8px;" }, [
					E("button", { class: "btn cbi-button", click: L.bind(this.handleAddVar, this) }, _("Add variable")),
				]),
				this.envAddRowEl,
			]),
		]);

		this.renderEnvList(initialVars);

		return page;
	},
});
