"use strict";
"require view";
"require rpc";
"require ui";
"require request";

/* Must match PARTITION_SIZE in appsbl-patch.c - used here only for an
 * early, friendlier client-side check before uploading; the server side
 * re-checks authoritatively regardless. */
var APPSBL_PARTITION_SIZE = 1310720;

return view.extend({
	callProbe: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "probe",
		expect: {},
	}),

	callApply: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "apply",
		expect: {},
	}),

	callGetKeys: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "get_keys",
		expect: {},
	}),

	callSetKey: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "set_key",
		params: ["name", "value"],
		expect: {},
	}),

	callBackup: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "backup",
		expect: {},
	}),

	callRestoreFactory: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "restore_factory",
		expect: {},
	}),

	callWriteAppsbl: rpc.declare({
		object: "luci.appsbl-dualkey-patch",
		method: "write_appsbl",
		expect: {},
	}),

	load: function () {
		return Promise.all([this.callProbe(), this.callGetKeys()]);
	},

	renderResult: function (res) {
		var ok = res && res.ok;
		var banner = E(
			"p",
			{
				class: ok
					? "alert-message success"
					: "alert-message error",
			},
			ok ? _("OK - hashes matched.") : _("Failed - see details below.")
		);
		var out = E("pre", {}, (res && res.output) || _("(no output)"));
		return E("div", {}, [banner, out]);
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

	// Shows the probe/dry-run result as a centered popup, like the Apply
	// flow's modals - the whole point of probing is to tell the user
	// clearly, before they ever click Apply, whether the patch would
	// succeed and whether writing to flash would be safe.
	showProbeResultModal: function (res) {
		var ok = res && res.ok;

		ui.showModal(ok ? _("Probe OK - safe to write") : _("Probe failed - do not write"), [
			this.renderResult(res),
			E("div", { class: "right" }, [E("button", { class: "btn cbi-button", click: ui.hideModal }, _("Close"))]),
		]);
	},

	handleProbe: function (container, ev) {
		var btn = ev.target;
		this.setBusy(btn, _("Probing..."));
		return this.callProbe()
			.then(
				L.bind(function (res) {
					container.replaceChildren(this.renderResult(res));
					this.showProbeResultModal(res);
				}, this)
			)
			.catch(
				L.bind(function (e) {
					container.replaceChildren(E("pre", { class: "alert-message error" }, e.message));
					this.showProbeResultModal({ ok: false, output: e.message });
				}, this)
			)
			.finally(
				L.bind(function () {
					this.clearBusy(btn);
				}, this)
			);
	},

	handleApply: function (container, ev) {
		var openerBtn = ev.target;

		ui.showModal(_("Patch 0:APPSBL"), [
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"This writes to the live bootloader partition (0:APPSBL). " +
						"The tool refuses to run unless this is the exact stock " +
						"APPSBL the patch was built for (verified by SHA-256) and " +
						"aborts before writing anything if the patched result does " +
						"not hash to the expected dual-key image. Still, only do " +
						"this from the initramfs, with a serial console open. " +
						"Research-only software, no warranty - proceeding is entirely " +
						"at your own risk and your own responsibility."
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
							this.setBusy(openerBtn, _("Patching..."));
							ui.showModal(_("Patching..."), [
								E("p", { class: "spinning" }, _("Reading, hashing, patching and writing 0:APPSBL - do not power off...")),
							]);
							this.callApply()
								.then(
									L.bind(function (res) {
										ui.hideModal();
										container.replaceChildren(this.renderResult(res));
										if (res && res.ok) {
											ui.addNotification(null, E("p", _("0:APPSBL patched and verified successfully.")), "info");
										} else {
											ui.addNotification(
												null,
												[
													E("p", _("Patch failed. Nothing may have been written - see the output below for the reason:")),
													E("pre", {}, (res && res.output) || _("(no output)")),
												],
												"error"
											);
										}
									}, this)
								)
								.catch(
									L.bind(function (e) {
										ui.hideModal();
										container.replaceChildren(E("pre", { class: "alert-message error" }, e.message));
										ui.addNotification(null, E("p", _("Patch failed: %s").format(e.message)), "error");
									}, this)
								)
								.finally(
									L.bind(function () {
										this.clearBusy(openerBtn);
									}, this)
								);
						}, this),
					},
					_("Write to flash")
				),
			]),
		]);
	},

	handleRestoreFactory: function (container, ev) {
		var openerBtn = ev.target;

		ui.showModal(_("Restore factory 0:APPSBL"), [
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"This reverses the dual-key patch and writes back the exact " +
						"original factory 0:APPSBL - no backup file needed, the tool " +
						"reconstructs it from the live partition and verifies the " +
						"result against the same factory hash the patch itself " +
						"carries before writing anything. This REMOVES the extra " +
						"fallback key entirely, not just resets it. Still only do " +
						"this from the initramfs, with a serial console open. " +
						"Research-only software, no warranty - proceeding is entirely " +
						"at your own risk and your own responsibility."
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
							ui.showModal(_("Restoring..."), [
								E("p", { class: "spinning" }, _("Reconstructing and writing the factory 0:APPSBL - do not power off...")),
							]);
							this.callRestoreFactory()
								.then(
									L.bind(function (res) {
										ui.hideModal();
										container.replaceChildren(this.renderResult(res));
										if (res && res.ok) {
											ui.addNotification(null, E("p", _("0:APPSBL restored to factory and verified successfully.")), "info");
										} else {
											ui.addNotification(
												null,
												[
													E("p", _("Restore failed. Nothing may have been written - see the output below for the reason:")),
													E("pre", {}, (res && res.output) || _("(no output)")),
												],
												"error"
											);
										}
									}, this)
								)
								.catch(
									L.bind(function (e) {
										ui.hideModal();
										container.replaceChildren(E("pre", { class: "alert-message error" }, e.message));
										ui.addNotification(null, E("p", _("Restore failed: %s").format(e.message)), "error");
									}, this)
								)
								.finally(
									L.bind(function () {
										this.clearBusy(openerBtn);
									}, this)
								);
						}, this),
					},
					_("Restore factory image")
				),
			]),
		]);
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
				// The file is written under /www with a random, unguessable
				// name (see the ucode backend) so a plain navigation is
				// enough to download it - uhttpd serves it directly.
				var a = E("a", { href: res.url, download: res.filename || "appsbl-backup.bin" });
				document.body.appendChild(a);
				a.click();
				a.remove();
				ui.addNotification(null, E("p", _("Backup downloaded (%s).").format(res.filename || "appsbl-backup.bin")), "info");
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

	// Raw multipart POST to cgi-io's upload endpoint (same mechanism LuCI's
	// own sysupgrade page uses for firmware uploads) - not base64-through-
	// ubus, for the same reason backup() avoids that: a ubus call has a
	// fixed ~30s timeout and encoding ~1.25 MiB in ucode is too slow. The
	// server only accepts this upload at the one path granted in this
	// app's ACL (/tmp/appsbl-upload.bin), so it can't be used to write
	// anywhere else.
	uploadAppsblFile: function (file, progressCb) {
		var data = new FormData();
		data.append("sessionid", L.env.sessionid);
		data.append("filename", "/tmp/appsbl-upload.bin");
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

	handleUploadAndWrite: function (container, ev) {
		var openerBtn = ev.target;
		var fileInput = openerBtn.parentNode.querySelector('input[type="file"]');
		var file = fileInput.files[0];

		if (!file) {
			ui.addNotification(null, E("p", _("Choose a file first.")), "error");
			return;
		}
		if (file.size !== APPSBL_PARTITION_SIZE) {
			ui.addNotification(
				null,
				E(
					"p",
					_("This file is %d bytes, expected exactly %d (0:APPSBL partition size) - not uploading.").format(
						file.size,
						APPSBL_PARTITION_SIZE
					)
				),
				"error"
			);
			return;
		}

		ui.showModal(_("Write uploaded file to 0:APPSBL"), [
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"This writes the uploaded file to the live bootloader partition " +
						"AS-IS. Unlike Apply or Restore factory, there is no structural " +
						"check here beyond the file being exactly the right size - " +
						"you are trusting the file itself. Only use this with a file " +
						"you know is a genuine 0:APPSBL image (e.g. your own earlier " +
						"backup). Still only do this from the initramfs, with a serial " +
						"console open. Research-only software, no warranty - proceeding " +
						"is entirely at your own risk and your own responsibility."
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
							this.uploadAppsblFile(
								file,
								L.bind(function (ev) {
									ui.showModal(_("Uploading..."), [
										E("p", { class: "spinning" }, _("Uploading file... %.0f%%").format((ev.loaded / ev.total) * 100)),
									]);
								}, this)
							)
								.then(
									L.bind(function () {
										ui.showModal(_("Writing..."), [
											E("p", { class: "spinning" }, _("Writing 0:APPSBL from the uploaded file - do not power off...")),
										]);
										return this.callWriteAppsbl();
									}, this)
								)
								.then(
									L.bind(function (res) {
										ui.hideModal();
										container.replaceChildren(this.renderResult(res));
										if (res && res.ok) {
											ui.addNotification(null, E("p", _("0:APPSBL written and verified from the uploaded file.")), "info");
											fileInput.value = "";
										} else {
											ui.addNotification(
												null,
												[
													E("p", _("Write failed. Nothing may have been written - see the output below for the reason:")),
													E("pre", {}, (res && res.output) || _("(no output)")),
												],
												"error"
											);
										}
									}, this)
								)
								.catch(
									L.bind(function (e) {
										ui.hideModal();
										container.replaceChildren(E("pre", { class: "alert-message error" }, e.message));
										ui.addNotification(null, E("p", _("Upload/write failed: %s").format(e.message)), "error");
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

	renderKeyField: function (name, info) {
		var textarea = E("textarea", {
			rows: 4,
			style: "width: 100%; font-family: monospace; font-size: 11px;",
		}, [info.value || ""]);
		var expectedLen = (info.value || "").length;
		var status = E("span", { class: "cbi-value-description" }, "");
		var saveBtn = E(
			"button",
			{ class: "btn cbi-button" },
			_("Save")
		);

		saveBtn.addEventListener(
			"click",
			L.bind(function () {
				var value = textarea.value.trim();
				if (expectedLen && value.length != expectedLen) {
					status.textContent = _("Rejected: %d characters, expected exactly %d - only a same-size key fits this field.").format(value.length, expectedLen);
					status.className = "cbi-value-description alert-message error";
					return;
				}
				this.setBusy(saveBtn, _("Saving..."));
				this.callSetKey(name, value)
					.then(
						L.bind(function (res) {
							if (res && res.ok) {
								status.textContent = _("Saved and validated.");
								status.className = "cbi-value-description alert-message success";
								expectedLen = value.length;
							} else {
								status.textContent = (res && res.output) || _("Rejected - see server output.");
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
							this.clearBusy(saveBtn);
						}, this)
					);
			}, this)
		);

		return E("div", { class: "cbi-value" }, [
			E("label", { class: "cbi-value-title" }, _("%s (%d-bit)").format(name, info.bits)),
			E("div", { class: "cbi-value-field" }, [
				textarea,
				E("div", { class: "right", style: "margin-top: 4px;" }, [saveBtn]),
				status,
			]),
		]);
	},

	render: function (data) {
		var initialResult = data[0];
		var keys = data[1] || {};

		var container = E("div", { class: "cbi-section" }, [
			this.renderResult(initialResult),
		]);

		var keysContainer = E("div", { class: "cbi-section" });
		for (var name in keys)
			keysContainer.appendChild(this.renderKeyField(name, keys[name]));

		return E([
			E("h2", _("APPSBL Dual-Key Patch")),
			E(
				"p",
				{ class: "alert-message warning" },
				_(
					"WARNING: research-only, no-warranty software that rewrites your " +
						"device's bootloader partition. Read the safety notes below " +
						"before using any button on this page. Using this tool - " +
						"probing, editing keys, backing up, and especially writing to " +
						"flash - is entirely at your own risk. You, not the authors of " +
						"this tool, are responsible for what happens to your device."
				)
			),
			E(
				"p",
				_(
					"Patches the live 0:APPSBL partition to accept this project's " +
						"own signing key alongside TP-Link/Mercusys's original one - " +
						"real OEM-signed firmware still verifies first, the extra key " +
						"is only ever a fallback. This targets the same firmware-" +
						"signing scheme (nm_fwup.c/handle_fw_cloud) TP-Link reuses " +
						"across many of its own and Mercusys-branded devices; this " +
						"specific package currently supports the Mercusys MR80X v2/v5 " +
						"(also sold as the MR3000X)."
				)
			),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Backup")),
				E("p", _("Reads the current 0:APPSBL and downloads it - always do this before writing anything.")),
				E("div", { class: "right" }, [
					E(
						"button",
						{
							class: "btn cbi-button",
							click: L.bind(this.handleBackup, this),
						},
						_("Backup 0:APPSBL")
					),
				]),
			]),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Fallback key fields")),
				E(
					"p",
					_(
						"Each field must be exactly the same length as the value " +
							"already there - a different-size key cannot fit this " +
							"slot and is rejected before anything is saved."
					)
				),
				keysContainer,
			]),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Probe / apply")),
				E("div", { class: "right" }, [
					E(
						"button",
						{
							class: "btn cbi-button",
							click: L.bind(this.handleProbe, this, container),
						},
						_("Probe (writes nothing)")
					),
					" ",
					E(
						"button",
						{
							class: "btn cbi-button-negative",
							click: L.bind(this.handleApply, this, container),
						},
						_("Apply patch...")
					),
				]),
			]),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Restore factory image")),
				E(
					"p",
					_(
						"Reverses the dual-key patch and writes back the exact " +
							"original factory 0:APPSBL, reconstructed from the live " +
							"partition and verified against the same factory hash the " +
							"patch itself carries - no separate backup file needed. " +
							"This removes the extra fallback key entirely."
					)
				),
				E("div", { class: "right" }, [
					E(
						"button",
						{
							class: "btn cbi-button-negative",
							click: L.bind(this.handleRestoreFactory, this, container),
						},
						_("Restore factory image...")
					),
				]),
			]),
			E("div", { class: "cbi-section" }, [
				E("h3", _("Upload and write appsbl")),
				E(
					"p",
					_(
						"Raw escape hatch: upload a file and write it to 0:APPSBL " +
							"exactly as-is. No structural checks beyond its size - " +
							"only use this with a file you know is a genuine 0:APPSBL " +
							"image, such as your own earlier backup."
					)
				),
				E("div", { class: "right" }, [
					E("input", { type: "file" }),
					" ",
					E(
						"button",
						{
							class: "btn cbi-button-negative",
							click: L.bind(this.handleUploadAndWrite, this, container),
						},
						_("Upload and write...")
					),
				]),
			]),
			container,
		]);
	},
});
