/*
# cpanel - base/frontend/jupiter/js2/contact/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global Promise */

(function(window, CPANEL, PAGE, LOCALE) {
    "use strict";

    var USER_IS_WEBMAIL = PAGE.username.includes("@") && CPANEL.application === "webmail";
    var CERT_FAILURE_SETTINGS = ["all", "failWarnDefer", "certFailures"];

    var SIMPLE_BOOLEANS = [
        "notify_account_login",
        "notify_account_login_for_known_netblock",
        "notify_account_login_notification_disabled",
    ];

    if (!USER_IS_WEBMAIL) {
        SIMPLE_BOOLEANS.push(
            "notify_bandwidth_limit",
            "notify_contact_address_change",
            "notify_contact_address_change_notification_disabled",
            "notify_disk_limit",
            "notify_email_quota_limit",
            "notify_password_change",
            "notify_password_change_notification_disabled",
            "notify_account_authn_link",
            "notify_account_authn_link_notification_disabled",
            "notify_twofactorauth_change",
            "notify_twofactorauth_change_notification_disabled",
            "notify_ssl_expiry"
        );
    }

    var ALL_BOOLEANS = USER_IS_WEBMAIL
        ? SIMPLE_BOOLEANS
        : SIMPLE_BOOLEANS.concat( [
            "notify_autossl_renewal",
            "notify_autossl_renewal_coverage",
            "notify_autossl_expiry",
            "notify_autossl_expiry_coverage",
            "notify_autossl_renewal_coverage_reduced",
            "notify_autossl_renewal_uncovered_domains",
        ] );

    var EMAIL_FIELDS = ["email", "second_email"];
    var NON_EMAIL_STRINGS = ["pushbullet_access_token"];

    var contactForm = document.getElementById("mainform");
    if (!contactForm) {
        throw "Document lacks `mainform` element??";
    }

    var savedNotice;

    var isTruthy = Boolean;

    /**
     * Determine whether two arrays contain identical content.
     *
     * @param   {any[]}     a
     * @param   {any[]}     b
     *
     * @result  {boolean}
     */
    function arraysDiffer(a, b) {
        return a.length !== b.length || a.some(
            function(v, i) {
                return v !== b[i];
            }
        );
    }

    /**
     * Read the saved email addresses from the given HTML form.
     *
     * @param   {HTMLFormElement}   theForm
     *
     * @result  {string[]}
     */
    function readSavedEmails(theForm) {
        return EMAIL_FIELDS.map(
            function(name) {
                return theForm[name].defaultValue;
            }
        ).filter(isTruthy);
    }

    /**
     * A class to coordinate dynamic interactions with this form.
     * This implements logic to enable/disable the form’s password
     * field, to set that field’s validation text, etc.
     *
     * @constructor
     *
     * @param   {HTMLFormElement}   theForm
     *
     */
    function EmailState(theForm) {
        this.form = theForm;

        this._setDOMListeners();

        this.refresh();
    }

    Object.assign(
        EmailState.prototype,
        {

            /**
             * (Re-)initialize object state.
             *
             */
            refresh: function() {
                this._savedEmails = readSavedEmails(this.form);
                this._updatePasswordField();
            },

            _initAutofill: function() {
                var autofillBtn = this.form.querySelector("#autofill-btn");
                if (!autofillBtn) {
                    return;
                }
                var autofillEmailAddress = this._autofillEmailAddress.bind(this);
                var updateAutofillVisibility = this._updateAutofillVisibility.bind(this);

                autofillBtn.addEventListener( "click", autofillEmailAddress);
                this.form.email.addEventListener( "input", updateAutofillVisibility );
            },

            _setDOMListeners: function() {
                var theForm = this.form;
                var updatePwField = this._updatePasswordField.bind(this);

                this._initAutofill.bind(this)();

                EMAIL_FIELDS.forEach( function(name) {
                    theForm[name].addEventListener( "input", updatePwField );
                } );

                this.form.password.addEventListener(
                    "input",
                    this._updatePasswordValidityMessage.bind(this)
                );
            },

            _updatePasswordField: function() {
                var theForm = this.form;

                var curEmails = EMAIL_FIELDS.map(
                    function(name) {
                        return theForm[name].value.trim();
                    }
                ).filter(isTruthy);

                var emailChanged = arraysDiffer(curEmails, this._savedEmails);

                var pwEl = this.form.password;

                pwEl.disabled = !emailChanged;
                pwEl.required = emailChanged;

                this._updatePasswordValidityMessage();
            },

            _updatePasswordValidityMessage: function() {
                var el = this.form.password;

                var msg;
                if (el.required && !el.value) {
                    msg = LOCALE.maketext("You must enter your password to update your contact email addresses.");
                }

                el.setCustomValidity(msg || "");
            },

            _autofillEmailAddress: function(event) {
                var el = event.target || event.srcElement;
                var email = this.form.email;

                event.preventDefault();

                email.value = el.getAttribute("data-email");
                this._updatePasswordField.bind(this)();
                this._updateAutofillVisibility.bind(this)();
            },

            _updateAutofillVisibility: function(event) {
                var value = event ? event.target.value : this.form.email.value;
                var autofillBtn = this.form.querySelector("#autofill-btn");
                var defaultAddress = autofillBtn.getAttribute("data-email");

                if (value === defaultAddress) {
                    autofillBtn.style = "display: none;";
                } else {
                    autofillBtn.style = "display: initial;";
                }
            },
        }
    );

    var emailState = !USER_IS_WEBMAIL && new EmailState(contactForm);

    function _readNewEmails(formData) {
        return EMAIL_FIELDS.map( function(name) {
            return formData.get(name).trim();
        }).filter(isTruthy);
    }

    /**
     * If the form’s email addresses have changed **and** the user is a
     * cPanel user (regardless of whether we’re in cPanel or Webmail),
     * this saves that new state. If there’s no change, or if the user is
     * a Webmail user, this does nothing.
     *
     * @param   {HTMLFormElement}   theForm
     * @param   {object}            formData
     *
     * @return  {Promise | null}    The save’s promise, or null if no
     *  save happens.
     */
    function saveEmailsIfNeeded(theForm, formData) {

        var newEmails = _readNewEmails(formData);

        var oldEmails = readSavedEmails(theForm);

        if (arraysDiffer(oldEmails, newEmails)) {
            var hasEmails = !!newEmails.length;
            var uapiFunc = hasEmails ? "set_email_addresses" : "unset_email_addresses";

            return new Promise( function(res, rej) {
                CPANEL.api( {
                    version: 3,
                    module: "ContactInformation",
                    func: uapiFunc,
                    data: {
                        address: newEmails,
                        old_address: oldEmails,
                        password: formData.get("password"),     // no trim
                    },
                    callback: {
                        success: function() {
                            EMAIL_FIELDS.forEach( function(name, idx) {
                                var formEl = theForm[name];
                                formEl.value = newEmails[idx] || "";
                                formEl.defaultValue = newEmails[idx] || "";

                                theForm.password.value = "";

                                if (emailState) {
                                    emailState.refresh();
                                }

                                res();
                            } );
                        },
                        failure: rej,
                    },
                } );
            } );
        }

        return null;
    }

    /**
     * Save the state of contact preferences and Pushbullet.
     * For Webmail users this also includes email addresses.
     *
     * @param   {HTMLFormElement}   theForm
     * @param   {object}            formData
     *
     * @return  {Promise}    The save’s promise.
     */
    function saveContactPreferences(theForm, formData) {
        var contactData = {};

        SIMPLE_BOOLEANS.forEach( function(name) {
            contactData[name] = formData.get(name);
        } );

        var stringFields = USER_IS_WEBMAIL ? EMAIL_FIELDS.concat(NON_EMAIL_STRINGS) : NON_EMAIL_STRINGS;

        stringFields.forEach( function(name) {
            contactData[name] = formData.get(name).trim();
        } );

        var autosslNotifications = formData.get("autosslNotifications");

        if (autosslNotifications !== undefined) {
            var notifyOnCertFailures = CERT_FAILURE_SETTINGS.filter(
                function(n) {
                    return n === autosslNotifications;
                }
            ).length;

            contactData.notify_autossl_renewal = (autosslNotifications === "all");
            contactData.notify_autossl_renewal_coverage = notifyOnCertFailures;
            contactData.notify_autossl_expiry = notifyOnCertFailures;
            contactData.notify_autossl_expiry_coverage = notifyOnCertFailures;
            contactData.notify_autossl_renewal_coverage_reduced = notifyOnCertFailures;
            contactData.notify_autossl_renewal_uncovered_domains = (autosslNotifications === "all") || (autosslNotifications === "failWarnDefer");
        }

        ALL_BOOLEANS.forEach( function(name) {
            contactData[name] = contactData[name] ? 1 : 0;
        } );

        return new Promise( function(res, rej) {
            CPANEL.api( {
                version: 2,
                module: "CustInfo",
                func: "savecontactinfo",
                data: contactData,
                callback: {
                    success: res,
                    failure: rej,
                },
            } );
        } );
    }

    /**
     * Save the passed-in form.
     *
     * @param   {HTMLFormElement}   theForm
     */
    function savemailform(theForm) {
        var fieldset = theForm.querySelector("fieldset");
        if (!fieldset) {
            throw "Form lacks a fieldset??";
        }

        var formData = new FormData(theForm);

        fieldset.disabled = true;

        var noticeProperties;

        var uapiEmailsSaved = false;

        var mainPromise;

        if (USER_IS_WEBMAIL) {
            mainPromise = saveContactPreferences(theForm, formData);
        } else {
            var emailsPromise = saveEmailsIfNeeded(theForm, formData);

            mainPromise = Promise.resolve(emailsPromise).then(
                function() {
                    uapiEmailsSaved = !!emailsPromise;
                    return saveContactPreferences(theForm, formData);
                }
            );
        }

        return mainPromise.then(
            function onSuccess() {
                noticeProperties = {
                    level: "success",
                    content: LOCALE.maketext("Success!"),
                };
            },
            function onFailure(o) {
                var errHtml = o.cpanel_error.html_encode();

                var msgHtml;

                if (uapiEmailsSaved) {
                    var emailsCount = _readNewEmails(formData).length;

                    var partialSuccessPhrase1;

                    if (emailsCount) {
                        partialSuccessPhrase1 = LOCALE.maketext("Your new contact email [quant,_1,address has,addresses have] been saved.", emailsCount);
                    } else {
                        partialSuccessPhrase1 = LOCALE.maketext("You have unset your contact email addresses.");
                    }

                    var partialSuccessPhrases = [
                        partialSuccessPhrase1,
                        LOCALE.maketext("The system failed to save your other contact preferences due to the following error: [_1]", errHtml),
                    ];

                    msgHtml = partialSuccessPhrases.join(" ");
                } else {
                    msgHtml = errHtml;
                }

                noticeProperties = {
                    level: "error",
                    content: msgHtml,
                    fade_delay: 0,
                };
            }
        ).finally(
            function() {
                fieldset.disabled = false;

                noticeProperties.replaces = savedNotice;

                savedNotice = new CPANEL.ajax.Dynamic_Notice(noticeProperties);
            }
        );
    }
    window.savemailform = savemailform;
})(window, CPANEL, PAGE, LOCALE);
