/* jshint -W100 */
/* eslint-disable camelcase, no-undef */
(function(window) {
    "use strict";

    var EVENT = window.EVENT;
    var CPANEL = window.CPANEL;
    var YAHOO = window.YAHOO;
    var LOCALE = window.LOCALE;
    var DOM = YAHOO.util.Dom;

    var sshAnimation;

    var handleSshKey = function(e) {
        var authtype_publickey = CPANEL.Y.one("#authtype_publickey"),
            public_key_options = CPANEL.Y.one("#public_key_options"),
            public_key_password = CPANEL.Y.one("#public_key_password"),
            public_key_selector = CPANEL.Y.one("#sshkey_selector"),
            escmeth_su = CPANEL.Y.one("#escmeth_su"),
            auth_user = CPANEL.Y.one("#auth_user"),
            user_password = CPANEL.Y.one("#user_password");

        if (sshAnimation) {
            EVENT.preventDefault(e);
            return;
        }

        // If no key exists we don't want to do this
        if (public_key_selector) {
            var current_key = public_key_selector.value;
            var key_list = CPANEL.PAGE.key_list;
            var key_is_encrypted = 1;
            for (var i = 0; i < key_list.length; i++) {
                if (key_list[i].key === current_key) {
                    key_is_encrypted = parseInt(key_list[i].encrypted, 10);
                    break;
                }
            }

            CPANEL.Y.one("#sshkeypass").disabled = !key_is_encrypted;
            DOM.setStyle(public_key_password, "display", key_is_encrypted ? "" : "none");
        }

        // We only need to track one animation since they both have the same animate time and will finish at the same time.
        if (authtype_publickey.checked) {
            if (public_key_options.style.display === "none") {
                sshAnimation = CPANEL.animate.slide_down(public_key_options);
            }
            if (user_password.style.display !== "none") {
                if (escmeth_su.checked || !auth_user.checked) {
                    CPANEL.animate.slide_up(user_password);
                }
            } else {
                if (!escmeth_su.checked && auth_user.checked) {
                    CPANEL.animate.slide_down(user_password);
                }
            }
        } else {
            if (public_key_options.style.display !== "none") {
                sshAnimation = CPANEL.animate.slide_up(public_key_options);
            }
            if (user_password.style.display === "none") {
                CPANEL.animate.slide_down(user_password);
            }
        }
        if (sshAnimation) {
            sshAnimation.onComplete.subscribe(function() {
                sshAnimation = null;
            });
        }
    };

    var suPassAnimation;

    var handleSuSudo = function(e) {
        var escmeth_su = CPANEL.Y.one("#escmeth_su"),
            su_pass = CPANEL.Y.one("#su_pass");

        if ((escmeth_su.checked && su_pass.style.display !== "none") ||
            (!escmeth_su.checked && su_pass.style.display === "none")) {

            if (e) {
                EVENT.preventDefault(e);
            }
            return;
        }

        if (suPassAnimation) {
            EVENT.preventDefault(e);
            return;
        }

        handleSshKey();
        if (CPANEL.Y.one("#escmeth_su").checked) {
            suPassAnimation = CPANEL.animate.slide_down("su_pass");
        } else {
            suPassAnimation = CPANEL.animate.slide_up("su_pass");
        }
        suPassAnimation.onComplete.subscribe(function() {
            suPassAnimation = null;
        });
    };

    var escOptionsAnimation,
        authuserWrapperAnimation;

    var handleUserLabel = function(e) {
        var password_label = CPANEL.Y.one("#user_password_label"),
            auth_user = CPANEL.Y.one("#auth_user"),
            auth_username_field = CPANEL.Y.one("input[name='authuser']");

        password_label.innerHTML = auth_user.checked ?
            LOCALE.maketext("“[_1]” Password:", auth_username_field.value).html_encode() :
            LOCALE.maketext("Root Password:");
    };

    var handleAuthRadio = function(e) {
        var auth_user = CPANEL.Y.one("#auth_user"),
            esc_options = CPANEL.Y.one("#esc_options"),
            authuser_wrapper = CPANEL.Y.one("#authuser_wrapper");


        if ((auth_user.checked && esc_options.style.display !== "none" && authuser_wrapper.style.display !== "none") ||
            (!auth_user.checked && esc_options.style.display === "none" && authuser_wrapper.style.display === "none")) {
            return;
        }

        if (escOptionsAnimation) {
            EVENT.preventDefault(e);
            return;
        }

        if (authuserWrapperAnimation) {
            EVENT.preventDefault(e);
            return;
        }

        if (auth_user.checked) {
            escOptionsAnimation = CPANEL.animate.slide_down("esc_options");
            authuserWrapperAnimation = CPANEL.animate.slide_down("authuser_wrapper");
        } else {
            escOptionsAnimation = CPANEL.animate.slide_up("esc_options");
            authuserWrapperAnimation = CPANEL.animate.slide_up("authuser_wrapper");
        }
        escOptionsAnimation.onComplete.subscribe(function() {
            escOptionsAnimation = null;
        });
        authuserWrapperAnimation.onComplete.subscribe(function() {
            authuserWrapperAnimation = null;
        });
    };

    var validation_notice;
    var state = {};

    // CHECK CREDENTIALS
    window.setupSSHSession = function(e, withWSTransport) {

        EVENT.preventDefault(e);

        CPANEL.namespace("CPANEL.PAGE");

        var formSubmitButton = CPANEL.Y.one("#formSubmitButton");
        var formSubmitButtonTextDiv = CPANEL.Y.one("#formSubmitButton .button-text");
        var preChangeText = formSubmitButtonTextDiv.innerHTML;

        CPANEL.PAGE.sshProgressPanel = new CPANEL.ajax.Progress_Panel(null, {
            show_status: true,
            status_html: preChangeText
        });
        CPANEL.PAGE.sshProgressPanel.show_from_source(formSubmitButton);


        var setupSSHSessionFailed = function() {
            CPANEL.PAGE.sshProgressPanel.hide();
        };
        var updateStatusText = function(label) {
            var overlayText = CPANEL.Y.one(".cjt-progress-overlay-text");
            overlayText.innerHTML = label;
        };

        if (validation_notice) {
            validation_notice.fade_out();
        }

        if (state.checking_ssh || state.settingup_session) {
            setupSSHSessionFailed();
            return;
        }

        // Create appropriate package to send with api call
        var checkSshData = {},
            sessionSetupData = {},
            errors = [];
        sessionSetupData.host = CPANEL.Y.one("#host").value;
        checkSshData.host = sessionSetupData.host;
        if (!sessionSetupData.host.trim().length) {
            errors.push(LOCALE.maketext("You must specify a host name or IP address."));
        }
        sessionSetupData.port = CPANEL.Y.one("#server_port").value;
        checkSshData.port = sessionSetupData.port;
        if (!sessionSetupData.port.trim().length) {
            errors.push(LOCALE.maketext("You must specify a port number."));
        }
        sessionSetupData.user = CPANEL.Y.one("#auth_root").checked ? "root" : CPANEL.Y.one("#authuser").value;
        if (!sessionSetupData.user.trim().length) {
            errors.push(LOCALE.maketext("You must specify a user name."));
        }
        if (CPANEL.Y.one("#authtype_password").checked || (sessionSetupData.user !== "root" && sessionSetupData.root_escalation_method === "sudo")) {
            sessionSetupData.password = CPANEL.Y.one("#authpass").value;
            if (!sessionSetupData.password.trim().length) {
                errors.push(LOCALE.maketext("You must specify the password for your login."));
            }
        } else {
            var sshkey_name = CPANEL.Y.one("#sshkey_selector");
            if (!sshkey_name) {
                errors.push(LOCALE.maketext("No SSH key has been selected."));
            } else {
                sessionSetupData.sshkey_name = CPANEL.Y.one("#sshkey_selector").value;

                var sshKeyInput = CPANEL.Y.one("#sshkeypass");
                if (sshKeyInput.disabled === false) {
                    sessionSetupData.sshkey_passphrase = sshKeyInput.value;
                    if (!sessionSetupData.sshkey_passphrase.trim().length) {
                        errors.push(LOCALE.maketext("You must specify the key phrase for the selected SSH Key."));
                    }
                }
            }
        }
        if (sessionSetupData.user !== "root") {
            sessionSetupData.root_escalation_method = CPANEL.Y.one("#escmeth_su").checked ? "su" : "sudo";
            if (sessionSetupData.root_escalation_method === "su") {
                sessionSetupData.root_password = CPANEL.Y.one("#rootpass").value;
                if (!sessionSetupData.root_password.trim().length) {
                    errors.push(LOCALE.maketext("You must specify the root password for “su” access."));
                }
            } else if (sessionSetupData.root_escalation_method === "sudo") {
                sessionSetupData.password = CPANEL.Y.one("#authpass").value;
            }
        }

        if (errors.length) {
            validation_notice = new CPANEL.widgets.Dynamic_Page_Notice({
                level: "error",
                content: errors.join("<br />"),
                container: "callback_block"
            });
            setupSSHSessionFailed();
        } else {
            formSubmitButton.disabled = true;
            updateStatusText(LOCALE.maketext("Checking connection …"));

            var checkSSHConnection = function(resolveSSH, rejectSSH) {
                return CPANEL.api({
                    func: "check_remote_ssh_connection",
                    data: checkSshData,
                    callback: {
                        success: function(sshConn) {
                            var resp_data = sshConn.cpanel_data;

                            if (resp_data.server_software) {
                                resolveSSH({
                                    state: state,
                                    formSubmitButton: formSubmitButton,
                                    preChangeText: preChangeText,
                                    sessionSetupData: sessionSetupData,
                                    sshProgressPanel: CPANEL.PAGE.sshProgressPanel
                                });
                            } else {

                                var errorData = resp_data.received ? resp_data.received.html_encode() : LOCALE.maketext("Unknown error; No error sent.");

                                if (!withWSTransport) {
                                    state.checking_ssh = null;
                                    formSubmitButton.disabled = false;
                                    updateStatusText(preChangeText);
                                    var failError = LOCALE.maketext("There is no SSH server listening on “[_1]”: [_2]", checkSshData.host.html_encode() + ":" + checkSshData.port.html_encode(), errorData);
                                    setupSSHSessionFailed();
                                    new CPANEL.widgets.Dynamic_Page_Notice({
                                        content: failError,
                                        level: "warn",
                                        container: "callback_block"
                                    });
                                }

                                rejectSSH(errorData);
                            }

                            state.checking_ssh = null;
                        },
                        failure: function(err) {
                            if (!withWSTransport) {
                                setupSSHSessionFailed();
                                state.checking_ssh = null;
                                formSubmitButton.disabled = false;
                                updateStatusText(preChangeText);
                                new CPANEL.widgets.Dynamic_Page_Notice({
                                    content: err.cpanel_error,
                                    level: "error",
                                    container: "callback_block"
                                });
                            }
                            rejectSSH(err);
                        }
                    }
                });
            };
            if (errors.length) {
                return false;
            } else {
                var sshPromise = new Promise(checkSSHConnection);
                return sshPromise;
            }
        }
    };

    var init = function() {
        handleSshKey();
        handleSuSudo();
        handleAuthRadio();
        handleUserLabel();

        CPANEL.dom.normalize_select_arrows("sshkey_selector");

        EVENT.on(CPANEL.Y.all("input[name='authtype']"), "click", handleSshKey);
        EVENT.on(CPANEL.Y.all("#sshkey_selector"), "change", handleSshKey);
        EVENT.on(CPANEL.Y.all("input[name='escmeth']"), "click", handleSuSudo);
        EVENT.on(CPANEL.Y.all("input[name='auth']"), "click", handleAuthRadio);
        EVENT.on(CPANEL.Y.all("input[name='auth']"), "click", handleUserLabel);
        EVENT.on(CPANEL.Y.all("input[name='authuser']"), "keyup", handleUserLabel);

    };


    EVENT.onDOMReady(init);

})(window);