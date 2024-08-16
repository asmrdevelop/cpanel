/* global setupSSHSession:false, DOM:false */
/* jshint -W100 */
/* jshint -W098 */
/* eslint-disable camelcase, no-undef */
(function(window) {

    "use strict";

    var EVENT = window.EVENT;
    var CPANEL = window.CPANEL;
    var YAHOO = window.YAHOO;
    var LOCALE = window.LOCALE;
    var DOM = YAHOO.util.Dom;

    var whmHelpAnimation;

    var handleSelectWhm = function(e) {
        var remote_server_type = CPANEL.Y.one("#remote_server_type"),
            whmHelpText = CPANEL.Y.one(".help-block.whmHelp");

        if (whmHelpAnimation) {
            EVENT.preventDefault(e);
            return;
        }

        if (remote_server_type.value === "WHM") {
            if (whmHelpText.style.display === "none") {
                whmHelpAnimation = CPANEL.animate.slide_down(whmHelpText);
            }
        } else if (whmHelpText.style.display !== "none") {
            whmHelpAnimation = CPANEL.animate.slide_up(whmHelpText);
        }

        if (whmHelpAnimation) {
            whmHelpAnimation.onComplete.subscribe(function() {
                whmHelpAnimation = null;
            });
        }
    };

    var copyResellerPrivsAnimation;
    var handleRestrictedOptions = function(e) {
        var copyResellerPrivsField = CPANEL.Y.one("#copy_reseller_privs"),
            restrictedRestore = CPANEL.Y.one("#restricted");

        if (!copyResellerPrivsField) {
            return;
        }

        if (copyResellerPrivsAnimation) {
            EVENT.preventDefault(e);
            return;
        }

        if (restrictedRestore.checked) {
            copyResellerPrivsField.disabled = true;
            copyResellerPrivsAnimation = CPANEL.animate.slide_up("copy_reseller_privs_field");
        } else {
            copyResellerPrivsField.disabled = false;
            copyResellerPrivsAnimation = CPANEL.animate.slide_down("copy_reseller_privs_field");
        }

        copyResellerPrivsAnimation.onComplete.subscribe(function() {
            copyResellerPrivsAnimation = null;
        });
    };

    var advancedOptionsAnimation;

    var showHideAdvanced = function(e) {
        var advancedOptions = CPANEL.Y.one("#advancedOptions"),
            showHideToggle = CPANEL.Y.one("#showHideAdvanced");

        if (advancedOptionsAnimation) {
            EVENT.stopEvent(e);
            return;
        }

        if (advancedOptions.style.display === "none") {
            advancedOptionsAnimation = CPANEL.animate.slide_down(advancedOptions);
            showHideToggle.innerHTML = LOCALE.maketext("Hide");
        } else {
            advancedOptionsAnimation = CPANEL.animate.slide_up(advancedOptions);
            showHideToggle.innerHTML = LOCALE.maketext("Show");
        }

        advancedOptionsAnimation.onComplete.subscribe(function() {
            advancedOptionsAnimation = null;
        });
    };
    var updateStatusText = function(label) {
        var overlayText = CPANEL.Y.one(".cjt-progress-overlay-text");
        if (overlayText) {
            overlayText.textContent = label;
        }
    };

    var disableFormAuthInputs = function() {
        var hostInput = CPANEL.Y.one("#host");
        var portInput = CPANEL.Y.one("#server_port");
        var rootUserInput = CPANEL.Y.one("#auth_root");
        var otherUserInput = CPANEL.Y.one("#auth_user");
        var authKeyInput = CPANEL.Y.one("#authtype_publickey");
        var authPasswordInput = CPANEL.Y.one("#authtype_password");
        var passwordInput = CPANEL.Y.one("#authpass");

        var inputs = [hostInput, portInput, rootUserInput, otherUserInput, authKeyInput, authPasswordInput, passwordInput];

        inputs.forEach(function(input) {
            if (input) {
                input.disabled = true;
            }
        });
    };

    var enableFormAuthInputs = function() {
        var hostInput = CPANEL.Y.one("#host");
        var portInput = CPANEL.Y.one("#server_port");
        var rootUserInput = CPANEL.Y.one("#auth_root");
        var otherUserInput = CPANEL.Y.one("#auth_user");
        var authKeyInput = CPANEL.Y.one("#authtype_publickey");
        var authPasswordInput = CPANEL.Y.one("#authtype_password");
        var passwordInput = CPANEL.Y.one("#authpass");

        var inputs = [hostInput, portInput, rootUserInput, otherUserInput, authKeyInput, authPasswordInput, passwordInput];

        inputs.forEach(function(input) {
            if (input) {
                input.disabled = false;
            }
        });
    };

    var hideTLSWarning = function() {
        var formBtn = CPANEL.Y.one("#formSubmitButton");
        var tlsWarning = CPANEL.Y.one("#tlsWarning");
        enableFormAuthInputs();

        if (formBtn) {
            formBtn.classList.remove("hidden");
            formBtn.disabled = false;
        }

        if (tlsWarning) {
            tlsWarning.classList.add("hidden");
        }
    };

    var showTLSWarning = function() {
        var tlsWarning = CPANEL.Y.one("#tlsWarning");
        disableFormAuthInputs();

        if (tlsWarning) {
            tlsWarning.classList.remove("hidden");
        }
    };

    var hideProgressPanel = function() {
        var progressPanel = CPANEL.PAGE.sshProgressPanel;
        if (progressPanel) {
            progressPanel.hide();
        }
    };

    var showProgressPanel = function() {
        var progressPanel = CPANEL.PAGE.sshProgressPanel;
        if (progressPanel) {
            progressPanel.show();
        }
    };

    var whmPrivsValid = function(whmResults) {
        var version = whmResults.versionData.split(".")[1];
        var versionEligible = parseInt(version, 10) >= 89;
        var privsEligible = whmResults.privsData ? true : false;
        return privsEligible && versionEligible;
    };

    var ineligiblePrivsError = function(server, version) {
        var ineligibleWHMMessage = LOCALE.maketext("“[_1]” runs [output,asis,cPanel amp() WHM] version “[_2]”. Update the remote server, or fix its [asis,SSH].", server, version);

        new CPANEL.widgets.Dynamic_Page_Notice({
            content: ineligibleWHMMessage,
            level: "error",
            container: "callback_block"
        });
    };

    // CHECK CREDENTIALS
    var setupTransferSession = function(calls) {
        var state = calls.state;
        var formSubmitButton = calls.formSubmitButton ? calls.formSubmitButton : CPANEL.Y.one("#formSubmitButton");
        var sessionSetupData = calls.sessionSetupData;
        var sshProgressPanel = CPANEL.PAGE.sshProgressPanel;

        sessionSetupData.comm_transport = calls.commTransport;
        sessionSetupData.remote_server_type = CPANEL.Y.one("#remote_server_type").value;
        sessionSetupData.transfer_threads = CPANEL.Y.one("#transfer_threads").value;
        sessionSetupData.restore_threads = CPANEL.Y.one("#restore_threads").value;
        sessionSetupData.session_timeout = CPANEL.Y.one("#session_timeout").value;
        sessionSetupData.unrestricted_restore = CPANEL.Y.one("input[name='restricted']").checked ? 0 : 1;
        sessionSetupData.compressed = CPANEL.Y.one("input[name='compressed']").checked ? 1 : 0;
        sessionSetupData.unencrypted = CPANEL.Y.one("input[name='unencrypted']").checked ? 1 : 0;
        sessionSetupData.use_backups = CPANEL.Y.one("input[name='use_backups']").checked ? 1 : 0;
        sessionSetupData.low_priority = CPANEL.Y.one("input[name='low_priority']").checked ? 1 : 0;
        sessionSetupData.enable_custom_pkgacct = CPANEL.Y.one("input[name='enable_custom_pkgacct']").checked ? 1 : 0;


        var overlayText = CPANEL.Y.one(".cjt-progress-overlay-text");
        overlayText.innerHTML = LOCALE.maketext("Creating Session …");

        state.settingup_session = CPANEL.api({
            func: "create_remote_root_transfer_session",
            data: sessionSetupData,
            callback: CPANEL.ajax.build_page_callback(function(o) {
                state.settingup_session = null;
                formSubmitButton.disabled = false;
                var transfer_session_id = o.cpanel_data.transfer_session_id;
                window.location.href = "transfer_selection?transfer_session_id=" + encodeURIComponent(transfer_session_id);
            }, {
                hide_on_return: sshProgressPanel,
                pagenotice_container: "callback_block",
                on_error: function() {
                    hideProgressPanel();
                    state.settingup_session = null;
                    formSubmitButton.disabled = false;
                }
            })
        });
    };

    var verifySourceWHMTransport = function(e, attemptTLS) {
        EVENT.preventDefault(e);

        var checkWHMData = {};

        checkWHMData["host"] = CPANEL.Y.one("#host").value;
        checkWHMData["username"] = "root";
        checkWHMData["password"] = CPANEL.Y.one("#authpass").value;
        checkWHMData["parameter_name"] = ["command", "command"];
        checkWHMData["parameter_value"] = ["version", "myprivs"];
        checkWHMData["function"] = "batch";

        checkWHMData["tls_verification"] = attemptTLS ? "on" : "off";

        // validation is handled in _sshkey_selection.js
        // this just stops creation of promise
        if (checkWHMData.host && checkWHMData.username && checkWHMData.password) {

            var checkWHMConnection = function(resolveWHM, rejectWHM) {
                return CPANEL.api({
                    func: "execute_remote_whmapi1_with_password",
                    data: checkWHMData,
                    callback: {
                        success: function(whmConn) {
                            var whmData = {
                                host: checkWHMData.host,
                                user: checkWHMData.username,
                                password: checkWHMData.password,
                                versionData: whmConn.cpanel_data[0].data.version,
                                privsData: whmConn.cpanel_data[1].data.privileges[0].all
                            };

                            resolveWHM(whmData);
                        },
                        failure: function(err) {
                            if (!attemptTLS) {
                                hideProgressPanel();
                                new CPANEL.widgets.Dynamic_Page_Notice({
                                    content: err.cpanel_error.html_encode(),
                                    level: "error",
                                    container: "callback_block"
                                });
                            }
                            rejectWHM(err);
                        }
                    }
                });
            };

            var whmPromise = new Promise(checkWHMConnection);
            return whmPromise;
        }
    };

    var retryTransport = function(e) {
        EVENT.preventDefault(e);
        hideTLSWarning();
        showProgressPanel();
        updateStatusText(LOCALE.maketext("Checking connection …"));

        verifySourceWHMTransport(e, false).then(function(retryData) {
            var whmData = {
                commTransport: "whostmgr_insecure",
                sessionSetupData: {
                    user: retryData.user,
                    host: retryData.host,
                    password: retryData.password
                },
                state: {
                    settingup_session: null,
                    checking_ssh: null
                }
            };

            var serverData = {
                privsData: retryData.privsData,
                versionData: retryData.versionData
            };

            var privsEligible = whmPrivsValid(serverData);

            if (privsEligible) {
                setupTransferSession(whmData);
            } else {
                hideProgressPanel();
                ineligiblePrivsError(retryData.host, retryData.versionData);
            }
        });
    };

    var createRetryDetails = function(remoteHost, apiData, sshErr) {
        CPANEL.Y.one("#tlsWarningText1").innerHTML = LOCALE.maketext("The [asis,SSH] connection to “[_1]” failed because of an error:", remoteHost.html_encode());

        CPANEL.Y.one("#tlsWarningText2").innerHTML = LOCALE.maketext("The system also attempted to avoid [asis,SSH] via a direct connection to WHM on “[_1]”. However, the connection failed its [asis,TLS] validation ([_2]). Because of this, “[_1]” cannot prove its identity, and an attacker may be impersonating that server.", remoteHost.html_encode(), apiData.detail.handshake_verify_text.html_encode());

        CPANEL.Y.one("#tlsWarningText3").innerHTML = LOCALE.maketext("It is [output,strong,not] recommended that you continue. You should fix the [asis,TLS] verification problem with “[_1]” before you try again. For more information, read our [output,url,_2,SSL troubleshooting] documentation.", remoteHost.html_encode(), "https://go.cpanel.net/troubleshootsslissues");

        CPANEL.Y.one("#tlsWarningText4").innerHTML = LOCALE.maketext("If you continue, the system will create an insecure connection to “[_1]” to verify its [output,asis,cPanel amp() WHM] version information. The version of [output,asis,cPanel amp() WHM] on “[_1]” [output,strong,must] be version 90 or later.", remoteHost.html_encode());

        CPANEL.Y.one("#sshAPIReturnText pre code").innerHTML = sshErr;
    };

    var toggleRetryContBtn = function() {
        CPANEL.Y.one("#retryTransportBtn").disabled = CPANEL.Y.one("#retryContCheck").checked ? false : true;
    };

    var toggleSSHDetailsText = function() {
        var hideSSHDetails = function() {
            CPANEL.Y.one("#sshAPIReturnText").classList.add("hidden");
            CPANEL.Y.one("#toggleSSHDetails").dataset.visible = false;
            CPANEL.Y.one("#toggleSSHDetails").innerHTML = LOCALE.maketext("Show More") + "\n" + "<i id='showMoreChevron' aria-hidden='true' class='fas fa-chevron-down'></i>";
        };

        var showSSHDetails = function() {
            CPANEL.Y.one("#sshAPIReturnText").classList.remove("hidden");
            CPANEL.Y.one("#toggleSSHDetails").dataset.visible = true;
            CPANEL.Y.one("#toggleSSHDetails").innerHTML = LOCALE.maketext("Show Less") + "\n" + "<i id='showLessChevron' aria-hidden='true' class='fas fa-chevron-up'></i>";
        };

        CPANEL.Y.one("#toggleSSHDetails").dataset.visible === "false" ? showSSHDetails() : hideSSHDetails();
    };

    var handleRootTransfer = function(e) {

        // setupSSHSession is a function on the window object defined in _sshkey_selection.js
        // if there is an input validation error this function will not be defined
        // validation handling is also in _sshkey_selection.js
        var sshSession = setupSSHSession(e, true);

        if (sshSession) {
            sshSession.then(function(sshData) {
                setupTransferSession(sshData);
            }).catch(function(sshErr) {
                var whmVerification = verifySourceWHMTransport(e, true);

                whmVerification.then(function(whmServerData) {
                    var whmData = {
                        commTransport: "whostmgr",
                        state: {
                            checking_ssh: null,
                            settingup_session: null
                        },
                        sessionSetupData: {
                            host: whmServerData.host,
                            user: whmServerData.user,
                            password: whmServerData.password
                        }
                    };

                    var serverData = {
                        privsData: whmServerData.privsData,
                        versionData: whmServerData.versionData
                    };

                    var privsEligible = whmPrivsValid(serverData);

                    if (privsEligible) {
                        setupTransferSession(whmData);
                    } else {
                        ineligiblePrivsError(sessionSetupData.host, whmData.versionData);
                    }
                }).catch(function(whmErr) {
                    var sshErrText = sshErr.cpanel_error;
                    var whmErrText = whmErr.cpanel_error;
                    var whmAPIData = whmErr.cpanel_data;
                    var isTLSErr = whmAPIData && whmAPIData.type === "TLSVerification";

                    if (isTLSErr) {
                        var remoteHost = CPANEL.Y.one("#host").value;

                        createRetryDetails(remoteHost, whmAPIData, sshErrText);
                        hideProgressPanel();

                        // hide regular submit button if TLS warning is shown, as it
                        // contains a submit button
                        CPANEL.Y.one("#formSubmitButton").classList.add("hidden");
                        showTLSWarning();
                    } else {
                        var displayErr = [sshErrText, whmErrText].join("\n").html_encode();
                        hideProgressPanel();
                        CPANEL.Y.one("#formSubmitButton").disabled = false;
                        new CPANEL.widgets.Dynamic_Page_Notice({
                            content: displayErr,
                            level: "error",
                            container: "callback_block"
                        });
                    }
                });
            });
        }
    };

    var init = function() {

        handleRestrictedOptions();
        handleSelectWhm();

        EVENT.on(CPANEL.Y.one("#restricted"), "click", handleRestrictedOptions);

        EVENT.on(CPANEL.Y.one("#remote_server_type"), "change", handleSelectWhm);

        EVENT.on(CPANEL.Y.one("#showHideAdvanced"), "click", showHideAdvanced);

        EVENT.on(CPANEL.Y.one("#cancelRetryTransportBtn"), "click", hideTLSWarning);

        EVENT.on(CPANEL.Y.one("#retryTransportBtn"), "click", retryTransport);

        EVENT.on(CPANEL.Y.one("#retryContCheck"), "click", toggleRetryContBtn);

        EVENT.on(CPANEL.Y.one("#toggleSSHDetails"), "click", toggleSSHDetailsText);

        EVENT.on(CPANEL.Y.one("form[name='copyform']"), "submit", function(e) {

            // only attempt the WS connection if the auth type is password and user is root
            // otherwise just attempt to connect via SSH
            if (CPANEL.Y.one("#authtype_password").checked && CPANEL.Y.one("#auth_root").checked) {
                handleRootTransfer(e);
            } else {
                setupSSHSession(e, false).then(function(sshData) {
                    setupTransferSession(sshData);
                });
            }
        });

        var transfer_threads = CPANEL.Y.one("#transfer_threads"),
            restore_threads = CPANEL.Y.one("#restore_threads");

        EVENT.on(transfer_threads, "keyup", function(e) {
            if (!transfer_threads.setCustomValidity) {
                return;
            }
            transfer_threads.setCustomValidity("");
            if (!transfer_threads.checkValidity()) {
                transfer_threads.setCustomValidity(LOCALE.maketext("You must provide an integer number between 1 and [numf,_1].", CPANEL.PAGE.transfer_threads_hard_limit));
            }
        });

        EVENT.on(restore_threads, "keyup", function(e) {
            if (!restore_threads.setCustomValidity) {
                return;
            }
            restore_threads.setCustomValidity("");
            if (!restore_threads.checkValidity()) {
                restore_threads.setCustomValidity(LOCALE.maketext("You must provide an integer number between 1 and [numf,_1].", CPANEL.PAGE.restore_threads_hard_limit));
            }
        });

        DOM.get("host").focus();
    };

    EVENT.onDOMReady(init);

})(window);
