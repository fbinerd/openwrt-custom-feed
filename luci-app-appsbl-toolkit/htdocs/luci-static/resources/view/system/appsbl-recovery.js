"use strict";
"require view";
"require rpc";
"require ui";
"require request";

return view.extend({
	callRestoreBaseline: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "restore_baseline",
		expect: {},
	}),

	callVerifyAndRestore: rpc.declare({
		object: "luci.appsbl-env-tool",
		method: "verify_and_restore",
		params: ["unpatch"],
		expect: {},
	}),

	load: function () {
		return Promise.resolve();
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

	// Same raw multipart POST mechanism as the Dual-Key Patch/Environment
	// pages' upload-and-write - not base64-through-ubus (30s timeout / size).
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

	handleRestoreBaseline: function (ev) {
		var openerBtn = ev.target;

		ui.showModal(_("Restore env baseline"), [
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"This sets ONLY bootcmd, bootdelay and tp_boot_idx back to this " +
						"project's own known-good values (the same three variables its " +
						"own installer sets). It never touches device-unique fields " +
						"such as ethaddr. This project has no captured reference for a " +
						"genuine untouched OEM-factory env, so this is NOT a factory " +
						"restore - only a return to this project's own known-good " +
						"baseline. Research-only software, no warranty - proceeding is " +
						"entirely at your own risk."
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
							this.setBusy(openerBtn, _("Restoring..."));
							this.callRestoreBaseline()
								.then(
									L.bind(function (res) {
										this.showResultModal(_("Restore env baseline"), res);
									}, this)
								)
								.catch(
									L.bind(function (e) {
										this.showResultModal(_("Restore env baseline"), { ok: false, output: e.message });
									}, this)
								)
								.finally(
									L.bind(function () {
										this.clearBusy(openerBtn);
									}, this)
								);
						}, this),
					},
					_("Restore baseline")
				),
			]),
		]);
	},

	handleVerifyAndRestore: function (container, ev) {
		var openerBtn = ev.target;
		var fileInput = container.querySelector('input[type="file"]');
		var checkbox = container.querySelector('input[type="checkbox"]');
		var file = fileInput.files[0];
		var unpatch = checkbox.checked;

		if (!file) {
			ui.addNotification(null, E("p", _("Choose an official TP-Link/Mercusys firmware file first.")), "error");
			return;
		}

		ui.showModal(_("Verify official image and restore"), [
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"This checks the uploaded file's RSA signature against TP-Link/" +
						"Mercusys's REAL public firmware-signing key - only if that " +
						"check passes does anything happen. On success this restores " +
						"the env baseline (bootcmd/bootdelay/tp_boot_idx only, never " +
						"device-unique fields)."
				) +
					(unpatch
						? " " +
						  _(
								"UNPATCH APPSBL IS CHECKED: this will ALSO reverse the dual-key " +
									"patch on 0:APPSBL back to the exact stock image, removing the " +
									"research fallback key entirely."
						  )
						: " " + _("Unpatch appsbl is NOT checked, so 0:APPSBL itself will not be touched.")) +
					" " +
					_("Research-only software, no warranty - proceeding is entirely at your own risk.")
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
								"/tmp/appsbl-verify-upload.bin",
								L.bind(function (ev2) {
									ui.showModal(_("Uploading..."), [
										E("p", { class: "spinning" }, _("Uploading file... %.0f%%").format((ev2.loaded / ev2.total) * 100)),
									]);
								}, this)
							)
								.then(
									L.bind(function () {
										ui.showModal(_("Verifying and restoring..."), [
											E("p", { class: "spinning" }, _("Verifying signature and restoring - do not power off...")),
										]);
										return this.callVerifyAndRestore(unpatch);
									}, this)
								)
								.then(
									L.bind(function (res) {
										ui.hideModal();
										this.showResultModal(_("Verify official image and restore"), res);
										if (res && res.ok) fileInput.value = "";
									}, this)
								)
								.catch(
									L.bind(function (e) {
										ui.hideModal();
										this.showResultModal(_("Verify official image and restore"), { ok: false, output: e.message });
									}, this)
								)
								.finally(
									L.bind(function () {
										this.clearBusy(openerBtn);
									}, this)
								);
						}, this),
					},
					_("Verify and restore...")
				),
			]),
		]);
	},

	render: function () {
		var verifyContainer = E("div", {}, [
			E("div", { class: "right" }, [E("input", { type: "file" })]),
			E("div", { class: "cbi-value" }, [
				E("label", { class: "cbi-value-title" }, _("Unpatch appsbl")),
				E("div", { class: "cbi-value-field" }, [
					E("input", { type: "checkbox", id: "appsbl-recovery-unpatch-cb" }),
					" ",
					E(
						"span",
						{ class: "cbi-value-description" },
						_("Off by default. If checked, ALSO reverses the dual-key patch on 0:APPSBL back to stock.")
					),
				]),
			]),
		]);

		return E([
			E("h2", _("APPSBL OEM Recovery")),
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"WARNING: research-only, no-warranty software that can rewrite " +
						"your device's U-Boot environment and bootloader partition. " +
						"Read the safety notes below before using any button on this " +
						"page. Using this tool is entirely at your own risk - you, not " +
						"the authors of this tool, are responsible for what happens to " +
						"your device."
				)
			),
			E(
				"p",
				_(
					"Two ways back to a known-good state on a Mercusys MR80X v2/v5: " +
						"restore this project's own known-good env baseline directly, " +
						"or - gated behind a genuine official TP-Link/Mercusys firmware " +
						"signature - restore the env baseline and optionally also " +
						"remove the dual-key patch entirely."
				)
			),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Restore baseline")),
				E(
					"p",
					_(
						"Sets ONLY bootcmd/bootdelay/tp_boot_idx back to this project's " +
							"own known-good values - NOT a genuine OEM-factory restore " +
							"(no reference for that is captured anywhere in this project)."
					)
				),
				E("div", { class: "right" }, [
					E("button", { class: "btn cbi-button-negative", click: L.bind(this.handleRestoreBaseline, this) }, _("Restore baseline...")),
				]),
			]),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Verify official image and restore")),
				E(
					"p",
					_(
						"Upload an official TP-Link/Mercusys firmware image - its RSA signature " +
							"is checked against the REAL vendor public key before anything " +
							"happens. On success, restores the env baseline, and (only if " +
							"'Unpatch appsbl' is checked) also reverses the dual-key patch " +
							"on 0:APPSBL back to stock."
					)
				),
				verifyContainer,
				E("div", { class: "right", style: "margin-top: 4px;" }, [
					E(
						"button",
						{ class: "btn cbi-button-negative", click: L.bind(this.handleVerifyAndRestore, this, verifyContainer) },
						_("Verify and restore...")
					),
				]),
			]),
		]);
	},
});
