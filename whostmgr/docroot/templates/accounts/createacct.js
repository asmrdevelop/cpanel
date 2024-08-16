// Copyright 2023 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

/* eslint-disable new-cap, camelcase */
/**
 * Page-specific javascript for Create Account page in WHM.
 * @module CreateAccount
 **/

(function(window) {
    "use strict";

    const PAGE = window.PAGE;

    if (PAGE.noForm) {
        return;
    }

    var VALID = {},
        DOM = YAHOO.util.Dom,
        EVENT = YAHOO.util.Event,
        CUSTOM_CONTROL_OBJS = PAGE.cPCustomControls,
        CUSTOM_CONTROL_NAMES = PAGE.cPCustomControls.map( c => c.name ),
        mainForm = document.mainform,
        isNumeric = /^\d+$/,
        customControls = [];

    const PKG_RESOURCES = {};
    PAGE.packages.forEach(p => PKG_RESOURCES[p.name] = p.resources);

    const PKG_SELECT_EL = DOM.get("pkgselect");

    const CUSTOM_CONTROL_MAX = {};
    CUSTOM_CONTROL_OBJS.forEach( c => {
        CUSTOM_CONTROL_MAX[c.name] = c.max && parseInt(c.max, 10);
    } );

    const BOOLEANS_IN_PKG = [
        "ip",
        "cgi",
        "hasshell",
        "digestauth",
    ];

    const DROPDOWNS_IN_PKG = [
        "cpmod",
        "featurelist",
        "language",
    ];

    function _formToPkgKey(lcname) {
        if (lcname === "language") {
            return "LANG";
        }

        return lcname.toUpperCase();
    }

    const NO_PACKAGE_DEFAULTS = {};
    for (const [lcname, value] of Object.entries(PAGE.noPackageDefaults)) {
        NO_PACKAGE_DEFAULTS[ _formToPkgKey(lcname) ] = value;
    }

    var MAX_USERNAME_LENGTH = 16;

    // this value gets altered only when the *user* sets a nonempty username;
    // if Javascript sets the username, then it doesn't get set
    var Custom_Username = false;

    var resetacctform = function() {

        var offlist = [mainForm.ip, mainForm.hasshell, mainForm.cgi];

        // resellers don't have this element
        if (DOM.inDocument("manual")) {
            if (DOM.get("manual").checked) {
                var offlistLength = offlist.length;
                for (var i = 0; i < offlistLength; i++) {
                    if (offlist[i]) {
                        offlist[i].value = 1;
                    }
                }
            }
        }
    };

    /**
     * Massages related form values before submit.
     * @method checkacctform
     **/
    var checkacctform = function() {
        var offlist = [mainForm.ip, mainForm.hasshell];

        var savepkgCheckbox = DOM.get("pkgchkbox");

        // resellers don't have this element
        if (DOM.inDocument("manual")) {
            if (DOM.get("manual").checked) {
                for (var i = 0; i < offlist.length; i++) {
                    if (offlist[i] && !offlist[i].checked) {
                        offlist[i].checked = true;
                        offlist[i].value = 0;
                    }
                }
            } else if (savepkgCheckbox) {
                savepkgCheckbox.checked = false;
            }
        }

        var cgi = mainForm.cgi;
        if (cgi && !cgi.checked) {
            cgi.checked = true;
            cgi.value = 0;
        }

        // if save package checkbox is not checked
        // clear any value in the package name field
        // so it won't be displayed on results page

        if (savepkgCheckbox && savepkgCheckbox.checked === false) {
            var pkgNameField = DOM.get("pkgname");
            if (pkgNameField) {
                pkgNameField.value = "";
            }
        }

        // check the custom controls and massage the
        // fields so that only the name/value pair
        // gets submitted with the form
        var customControlNamesLength = CUSTOM_CONTROL_NAMES.length;
        for (var k = 0; k < customControlNamesLength; k++) {
            var controlPrefix = CUSTOM_CONTROL_NAMES[k];
            var customRadioEl = mainForm[controlPrefix + "_custom_radio"];
            var unlimitedRadioEl = mainForm[controlPrefix + "_unlimited_radio"];
            var textBoxEl = mainForm[controlPrefix];
            if (unlimitedRadioEl && unlimitedRadioEl.checked) {
                if (textBoxEl) {
                    textBoxEl.value = "unlimited";
                    textBoxEl.disabled = false;
                }
                unlimitedRadioEl.name = "";
            }
            if (customRadioEl) {
                customRadioEl.name = "";
            }
        }
    };

    var parsexmlnslist = function(o) {
        var nslist = o.responseText.split(":");
        var nstxt = nslist.join("<br />");
        var nstouse = DOM.get("nstouse");
        if ( nstouse ) {
            nstouse.innerHTML = nstxt;
        }
    };

    var ajaxnslist = function() {
        var domain = mainForm.domain.value;
        var useregns = DOM.get("nstouse") && mainForm.useregns.checked ? 1 : 0;

        var nstouse = DOM.get("nstouse");
        if ( nstouse ) {
            nstouse.innerHTML = LOCALE.maketext("Updating …");
        }

        var statcallback = {
            success: parsexmlnslist,
        };
        var sUrl = window.PAGE.nsListUrlPrefix + domain + "&useregns=" + useregns;
        YAHOO.util.Connect.asyncRequest("GET", sUrl, statcallback, null);
    };

    var dologinname = function() {
        if (mainForm.username.value === "" && !Custom_Username) {
            var domain = mainForm.domain.value;
            var username = domain.replace(/^\d+/, "").replace(/\.[^.]+$/, "").replace(/[^A-Za-z0-9]/g, "").substring(0, MAX_USERNAME_LENGTH);
            username = username.toLowerCase();
            mainForm.username.value = username;
        }
    };

    var fixaddress = function() {
        mainForm.domain.value = mainForm.domain.value.toLowerCase();
        mainForm.dbuser.value = mainForm.username.value;
    };

    var setnoplan = function() {
        mainForm.msel.selectedIndex = 0;
    };

    /**
     * Fix the custom resource setting manual control to the proper state.
     * @method fixCustomControl
     * @param {String} prefix the control base name.
     * @param {String} defaultValue the initial setting for the control
     **/
    var fixCustomControl = function(prefix, defaultValue) {
        var textControl = mainForm[prefix];
        var customRadio = mainForm[prefix + "_custom_radio"];
        var unlimitedRadio = mainForm[prefix + "_unlimited_radio"];
        if (textControl && isNumeric.test(defaultValue)) {
            textControl.value = defaultValue;
            if (customRadio) {
                customRadio.checked = true;
            }
            textControl.disabled = false;
        } else if (unlimitedRadio) {
            unlimitedRadio.checked = true;
            if (textControl) {
                textControl.disabled = true;
                textControl.value = textControl.defaultValue;
            }
        }
    };

    /**
     * Checks if an element with a given ID is hidden.
     * @param  {String}  elemId   The element ID in question.
     * @return {Boolean}          True when the element associated with the ID is hidden.
     */
    var isHidden = function(elemId) {
        return DOM.hasClass(elemId, "hidden");
    };

    /**
     * Aligns the Smart_Disable_Overlay div for each Grouped_Input_Set. The overlays
     * use absolute positioning relative to the entire #contentContainer, so they need
     * to be re-aligned any time the visible content changes.
     */
    var _alignCustomControls = function() {
        if (isHidden("mansettings")) {
            return;
        }

        customControls.forEach(function(customControl) {
            customControl.align();
        });
    };

    /**
     * The throttled version of _alignCustomControls. We can have many showHideDiv calls
     * in succession, so this ensures that we only run the function once per render cycle.
     */
    var alignCustomControls = function() {
        if (alignCustomControls.isQueued) {
            return;
        }

        alignCustomControls.isQueued = true;

        requestAnimationFrame(function() {
            alignCustomControls.isQueued = false;
            setTimeout(_alignCustomControls, 0);
        });
    };

    /**
     * Advanced version of showHideDiv that takes a custom canShow function.
     *
     * @param  {Element}  divName Element to show/hide based on the results of the canShow method.
     * @param  {Function} canShow That returns true when the element passed to showHideDiv should
     *                            be shown and false when the div element should be hidden
     */
    var showHideDivAdvanced = function(divName, canShow) {
        if (!canShow || typeof canShow !== "function") {
            throw new Error("Failed to pass the canShow function for " + divName + " processing.");
        }
        if (DOM.get(divName)) {
            if (canShow() === true) {
                DOM.removeClass(divName, "hidden");
            } else {
                DOM.addClass(divName, "hidden");
            }

            alignCustomControls();
        }
    };

    /**
     * Factory to generate a canShow() function for a single checkbox element.
     *
     * @param  {CheckboxInputElement} checkboxEl
     * @return {Function}            That returns true when the div element passed to showHideDiv
     *                               should be shown and false when the div element should be hidden
     */
    var canShowFactory = function( checkboxEl ) {
        return function() {
            if (checkboxEl.checked === true) {
                return true;
            }
            return false;
        };
    };

    /**
     * Toggles the visibility of the given div based on the state of a particular
     * input control.
     * @method showHideDiv
     * @param {String} divName the name of the div to be shown/hidden
     * @param {String|Element} checkboxInput the control whose state determines whether the div is shown/hidden
     **/
    var showHideDiv = function(divName, checkboxInput) {
        var checkboxEl = DOM.get(checkboxInput);
        if (!checkboxEl) {
            return;
        }

        showHideDivAdvanced(divName, canShowFactory(checkboxEl));
    };

    /*
     * Adds "last" class to last property editor within a property group.
     * Makes sure last property editor doesn't have a bottom border
     * (primarily for IE8 compatibility).
     * Called from onDOMReady
     *
     * @method addLastStyleToPropertyGroups
     */
    var addLastStyleToPropertyGroups = function() {
        var packageExtensions = DOM.getElementsByClassName("propertyGroup", "div", "packageExtensions");

        var isLastPropertyEditor = function(el) {
            return DOM.hasClass(el, "propertyEditor");
        };

        var propertyGroupCount = packageExtensions.length;
        for (var j = 0; j < propertyGroupCount; j++) {
            var lastInGroup = DOM.getLastChildBy(packageExtensions[j], isLastPropertyEditor);
            if (lastInGroup) {
                DOM.addClass(lastInGroup, "last");
            }
        }
    };

    var getExtensionFormSuccess = function(args) {
        var extensionsDiv = DOM.get("packageExtensions");
        if (args.cpanel_data.html) {
            extensionsDiv.innerHTML = args.cpanel_data.html.trim();
        } else {
            extensionsDiv.innerHTML = "";
        }
        showHideDiv("packageExtensions", "manual");

        addLastStyleToPropertyGroups();
    };

    var getExtensionFormFailure = function(args) {
        var extensionsDiv = DOM.get("packageExtensions");
        extensionsDiv.innerHTML = "";
        showHideDiv("packageExtensions", "manual");
    };

    /**
     * Fixes the displayed values on the form in response to package change.
     *
     * @method updateform
     * @param {String} nfo comma-delimited list of package values.
     */
    function updateform() {
        let pkgName      = "default";
        let pkgResources = NO_PACKAGE_DEFAULTS;

        if (PKG_SELECT_EL) {
            const pkgopt = PKG_SELECT_EL.options[PKG_SELECT_EL.selectedIndex];
            pkgName = pkgopt.value;

            const selectEl = mainForm.msel;
            selectEl.className = pkgopt.className;

            if (PKG_RESOURCES[pkgName]) {
                pkgResources = PKG_RESOURCES[pkgName];
            }
        }

        BOOLEANS_IN_PKG.forEach( lcname => {
            const el = mainForm[lcname];

            if (el) {
                el.checked = pkgResources[_formToPkgKey(lcname)] === "y";
            }
        } );

        if (mainForm.ip) {
            showHideDiv("ipselect", "ipchkbox");
        }

        var spf_check = DOM.get("spf");
        if (spf_check) {
            var template_to_use = (pkgResources.IP === "n" ? "standardvirtualftp" : "standard");
            var zone_template_spf = window.PAGE.ZONE_TEMPLATE_SPF[template_to_use];
            if (zone_template_spf) {
                spf_check.checked = spf_check.disabled = true;
                DOM.addClass("spf_label", "disabled");
                var link = DOM.get("zone_template_link");
                link.href = link.href.replace(/(template=)[^&]*/, "$1" + template_to_use);
                CPANEL.util.set_text_content("zone_template_spf_string", zone_template_spf);
            } else {
                spf_check.disabled = false;
                spf_check.checked = window.PAGE.spf_checked;
                DOM.removeClass("spf_label", "disabled");
            }
        }

        CUSTOM_CONTROL_OBJS.forEach( cc => {
            const pkgKey = _formToPkgKey(cc.name);
            const value = (pkgKey in pkgResources) ? pkgResources[pkgKey] : cc.default;
            fixCustomControl( cc.name, value );
        } );

        DROPDOWNS_IN_PKG.forEach( lcname => {
            const nameInPkg = _formToPkgKey(lcname);

            const selectEl = mainForm[lcname];

            if (selectEl) {
                for (const opt of selectEl.options) {
                    if (opt.value === pkgResources[nameInPkg]) {
                        selectEl.selectedIndex = opt.index;
                    }
                }
            }
        } );

        if (mainForm.plan) {
            mainForm.plan.value = pkgName;
        }

        CPANEL.api({
            application: "whm",
            func: "_getpkgextensionform",
            data: {
                pkg: pkgName,
            },
            callback: {
                success: getExtensionFormSuccess,
                failure: getExtensionFormFailure,
            },
        });
    }

    var js_upgrade = function() {
        showHideDiv("ipselect", "ipchkbox");
        showHideDiv("resellown", "resell");
        var mansettingsEl = DOM.get("mansettings");
        if (mansettingsEl) {
            DOM.addClass(mansettingsEl, "hidden");
        }
    };

    var validPackageSelected = function() {
        var pkgSelectEl = DOM.get("pkgselect");
        if (pkgSelectEl && pkgSelectEl.value === "---") {
            var manualEl = DOM.get("manual");
            return manualEl && manualEl.checked;
        }
        return pkgSelectEl.selectedIndex >= 0;
    };

    var username_length = function() {
        var username = DOM.get("username").value;

        if (!username) {
            return false;
        }

        return CPANEL.validate.max_length(username, MAX_USERNAME_LENGTH);
    };

    var user_not_pw = function() {
        var user = DOM.get("username").value;
        var pw = DOM.get("password").value;
        if (user.toLowerCase() === pw.toLowerCase()) {
            return false;
        }
        return true;
    };

    var username_stupidstuff = function() {
        if (window.PAGE.ALLOWSTUPIDSTUFF === 1) {
            return true;
        }

        var username = DOM.get("username").value;
        return !username || CPANEL.validate.alpha(username.charAt(0));
    };

    var username_tolowercase = function() {
        DOM.get("username").value = DOM.get("username").value.toLowerCase();
    };

    function _addManualOptValidation(validator, name, func, label) {
        validator.add(
            name,
            (el) => func(el.value.trim()),
            label
        );
    }

    var force_pkgname_validation = 0;
    var add_new_validation = function() {
        var valid_username = function() {
            var value = document.getElementById("username").value;
            return (new RegExp(window.PAGE.username_regexp)).test(value);
        };

        VALID.domain = new CPANEL.validate.validator(LOCALE.maketext("Domain"));
        VALID.domain.add("domain", "fqdn", LOCALE.maketext("This is not a valid domain."));
        VALID.domain.attach();

        var valid_pkgname = function() {

            // only validate if the value will be used
            if (!force_pkgname_validation) {
                if (!document.getElementById("pkgchkbox").checked || !document.getElementById("manual").checked) {
                    return true;
                }
            }

            var svname = document.getElementById("pkgname").value;

            // The window.PAGE.pkgname_regexp approach is complicated (need to adjust template, whostmgr/bin/whostmgr5.pl, and create a get_regexp function w/ tests).
            //    Even then its not flexible enough since its tricky to do this-but-not-that matches in one regexp.
            // The logic below is based on what Whostmgr::Packages::Mod::_modpkg does with $name.
            if (svname === null || svname.length === 0) {
                return false;
            }
            if (/\.\./.test(svname)) {
                return false;
            }
            if (svname === "undefined" || svname === "extensions") {
                return false;
            }
            if (/[^a-zA-z0-9.\- _]/.test(svname)) {
                return false;
            }

            return true;
        };

        if (DOM.get("pkgname")) {
            VALID.pkgname = new CPANEL.validate.validator(LOCALE.maketext("Package Name"));
            VALID.pkgname.add("pkgname", valid_pkgname, LOCALE.maketext("This is not a valid package name."));
            VALID.pkgname.attach();
        }
        VALID.username = new CPANEL.validate.validator(LOCALE.maketext("Username"));
        VALID.username.add("username", "no_chars(%input%,' ')", LOCALE.maketext("A username cannot contain spaces."));
        VALID.username.add("username", username_length, LOCALE.maketext("A username must have between [numf,_1] and [quant,_2,character,characters].", 1, MAX_USERNAME_LENGTH));
        VALID.username.add("username", username_stupidstuff, LOCALE.maketext("A username must start with a letter."));
        VALID.username.add("username", user_not_pw, LOCALE.maketext("The username cannot be the same as the password."));
        VALID.username.add("username", valid_username, LOCALE.maketext("This is not a valid username."));

        VALID.username.attach();
        var password_validators = CPANEL.password.setup("password", "password2", "password_strength", window.PAGE.REQUIRED_PASSWORD_STRENGTH, "create_strong_password", "why_strong_passwords_link", "why_strong_passwords_text");
        VALID.pass1 = password_validators[0];
        VALID.pass2 = password_validators[1];

        // The contact email is optional. We will indicate that it is optional by only
        // showing a validation error if the field has text in it and the text is not a valid
        // email address.
        VALID.email_validator = new CPANEL.validate.validator(LOCALE.maketext("Email"));
        VALID.email_validator.add("contactemail", "if_not_empty(%input%, CPANEL.validate.email)", LOCALE.maketext("The email field must be empty or an email address."));
        VALID.email_validator.attach();

        if (window.PAGE.editaccount) {

            // This validation should only occur for resellers who:
            // - Have the edit-account ACL
            // - Do not have the viewglobalpackages ACLs
            // - Do not have any packages created by/for them
            // In this case it's possible for the user to bypass package selection by opting into the “Select Options Manually” option but
            // if that option is not selected then the user must have a package available and selected.
            //
            // Root-level resellers and resellers with the viewglobalpackages ACL will always have at least “default” in the package list.
            //
            // Resellers who do not have viewglobalpackages or edit-account and also do not have any packages created by/for them
            // should be prevented from seeing the create account form entirely until a package is created by/for them.
            if (PKG_SELECT_EL) {
                VALID.pkg = new CPANEL.validate.validator(LOCALE.maketext("Selected Package"));
                VALID.pkg.add("pkgselect", validPackageSelected, LOCALE.maketext("You must select a package."));
                VALID.pkg.attach();
            }

            /**
             * The edit-account privilege allows us to manually set limits on an account
             * and bypass limits on a given package. The manual resource option inputs are
             * only included in the template with this privilege level.
             */

            CUSTOM_CONTROL_OBJS.forEach( obj => {
                const { name, label, min, max } = obj;

                VALID[name] = new CPANEL.validate.validator(label);

                function _satisfiesMinimum(val) {
                    if (!CPANEL.validate.positive_integer(val)) {
                        return false;
                    }

                    return (val >= min);
                }

                if (max) {
                    _addManualOptValidation(
                        VALID[name],
                        name,
                        (val) => _satisfiesMinimum(val) && (val <= max),
                        LOCALE.maketext("Enter an integer from [numf,_1] to [numf,_2].", min, max)
                    );
                } else if (min) {
                    _addManualOptValidation(
                        VALID[name],
                        name,
                        _satisfiesMinimum,
                        LOCALE.maketext("Enter an integer no less than [numf,_1].", min)
                    );
                } else {
                    _addManualOptValidation(
                        VALID[name],
                        name,
                        CPANEL.validate.positive_integer,
                        LOCALE.maketext("Enter a nonnegative integer.")
                    );
                }

                VALID[name].attach();
            } );
        }

        CPANEL.validate.attach_to_form("submit", VALID);
    };

    var toggle_reseller_options = function() {
        var chkResell      = DOM.get("resell");
        var chkOwnerSelf   = DOM.get("ownerself");
        var labelOwnerSelf = chkOwnerSelf.parentElement;

        if (chkResell.checked) {
            chkOwnerSelf.disabled = false;
            DOM.removeClass(labelOwnerSelf, "disabled");
        } else {
            chkOwnerSelf.disabled = true;
            chkOwnerSelf.checked = false;
            DOM.addClass(labelOwnerSelf, "disabled");
        }
    };

    var init_page = function() {

        if (!mainForm) {
            mainForm = document.mainform;
        }

        /* On cPanel SOLO, it still won't exist. Just return if we can't ever get the mainform. */
        if (!mainForm) {
            return;
        }

        // set up custom controls for manually configured package settings
        // if needed.
        var controlNamesLength = CUSTOM_CONTROL_NAMES.length;
        for (var i = 0; i < controlNamesLength; i++) {
            const unlimitedRadioId = CUSTOM_CONTROL_NAMES[i] + "_unlimited_radio";

            if (document.getElementById(unlimitedRadioId)) {
                const inputSet = new CPANEL.ajax.Grouped_Input_Set(
                    document.forms.mainform,
                    CUSTOM_CONTROL_NAMES[i] + "_custom_radio",
                    unlimitedRadioId
                );

                customControls.push(inputSet);
            }
        }

        EVENT.on("domain", "blur", function() {
            dologinname();
            VALID.username.verify();
        });

        EVENT.on("domain", "change", function() {
            ajaxnslist();
            fixaddress();
        });

        EVENT.on("username", "blur", fixaddress);

        EVENT.on("username", "change", function() {
            Custom_Username = DOM.get("username").value !== "";
        });

        EVENT.on("mainform", "submit", checkacctform);

        EVENT.on("pkgselect", "change", updateform);

        // automatically convert username to lower case
        EVENT.on("username", "change", username_tolowercase);

        EVENT.on("manual", "change", function() {

            VALID.pkg.verify();

            showHideDiv("manoptions", "manual");
            showHideDiv("mansettings", "manual");

            // packageExtensions
            showHideDiv("packageExtensions", "manual");

            var inputEl = DOM.get("manual");
            var saveAsPkgEl = DOM.get("pkgchkbox");
            var manOptsEl = DOM.get("manualOptionsEditor");
            var pkgNameEl = DOM.get("pkgname");

            // remove or restore separator line as
            // necessary. Make sure the package
            // checkbox is correctly checked

            if (manOptsEl && inputEl && inputEl.checked === true) {
                DOM.removeClass(manOptsEl, "last");
                DOM.addClass("mansettings1", "last");
            } else if (manOptsEl && inputEl) {
                DOM.addClass(manOptsEl, "last");
            }

            // extra settings settings
            showHideDiv("dedicatedIp", "manual");
            showHideDiv("allowShell", "manual");
            showHideDiv("allowCGI", "manual");

            // extra package settings
            showHideDiv("mansettings1", "manual"); // save manual settings as a package
            if (saveAsPkgEl && saveAsPkgEl.checked === true) {
                DOM.removeClass("mansettings1", "last");
                showHideDiv("pkgNameEditor", "manual"); // package name
                showHideDiv("featureListEditor", "manual"); // feature list dropdown
                showHideDiv("pkgname_error_panel", "manual"); // package name validation message
                showHideDiv("pkgname_error", "manual");
                if (pkgNameEl) {
                    force_pkgname_validation = 1;
                    VALID.pkgname.verify(); // there is no .validate()
                    force_pkgname_validation = 0;
                }
            }

            CUSTOM_CONTROL_NAMES.forEach( function(control) {
                var chkManualEl = DOM.get("manual");
                var chkEl       = DOM.get(control + "_custom_radio");

                /**
                 * Factory function that enforces the parent/child heirarcy for the manual/manual resource
                 * options sections.
                 *
                 * @param  {CheckboxInputElement} chkManualEl Parent control
                 * @param  {CheckboxInputElement} chkEl       Dependent control
                 * @return {Function}             That returns true when the element should be shown and false when it should not be shown.
                 */
                var _canShowFactory = function(chkManualEl, chkEl) {
                    return function() {
                        if (chkManualEl.checked !== true) {

                            // Manual Options section is not shown
                            return false;
                        } else if (!chkEl || (chkEl.checked === true)) {
                            return true;
                        } else {
                            return false;
                        }
                    };
                };
                var _canCheck = _canShowFactory(chkManualEl, chkEl);

                showHideDivAdvanced(control + "_error", _canCheck);
                showHideDivAdvanced(control + "_error_panel", _canCheck);
            });

        });

        /* Hide validation error messages if the field with the invalid value is not selected (and unlimited is selecetd instead) */
        CUSTOM_CONTROL_NAMES.forEach( function(control) {
            var action = function() {
                var chkEl = DOM.get(control + "_custom_radio");
                showHideDiv(control + "_error", chkEl);
                showHideDiv(control + "_error_panel", chkEl);
            };

            EVENT.on(control + "_custom_radio", "change", action);
            EVENT.on(control, "focus", action); // Needed because clicking in the text box for some reason doesn't fire a ..._custom_radio change event
            EVENT.on(control + "_unlimited_radio", "change", action);

            EVENT.on(control, "paste", function(e) {
                var pastedText = e.clipboardData.getData("text");
                if (pastedText.match(/[^0-9]/)) {
                    e.preventDefault();
                }
            });

        });

        EVENT.on("pkgchkbox", "change", function() {
            var saveAsPkgEl = DOM.get("pkgchkbox");
            if (saveAsPkgEl && saveAsPkgEl.checked === true) {
                DOM.removeClass("mansettings1", "last");
            } else {
                DOM.addClass("mansettings1", "last");
            }

            showHideDiv("pkgNameEditor", "pkgchkbox"); // package name

            showHideDiv("featureListEditor", "pkgchkbox"); // feature list dropdown
            showHideDiv("pkgname_error_panel", "pkgchkbox"); // package name validation message
            showHideDiv("pkgname_error", "pkgchkbox");

            if (DOM.hasClass("pkgNameEditor", "hidden") && VALID.pkgname) {
                VALID.pkgname.detach();
            } else if (VALID.pkgname) {
                VALID.pkgname.attach();
                force_pkgname_validation = 1;
                VALID.pkgname.verify(); // there is no .validate()
                force_pkgname_validation = 0;
            }
        });

        EVENT.on("resell", "click", toggle_reseller_options);

        var manSettingControls = DOM.getElementsByClassName("manualOption", "input", "mansettings");

        EVENT.on(manSettingControls, "change", setnoplan);

        if ( DOM.get("nstouse") ) {
            EVENT.on("useregns", "click", ajaxnslist);
        }

        EVENT.on("ipchkbox", "click", function() {
            showHideDiv("ipSelect", "ipchkbox");
        });

        EVENT.on("spamassassin", "change", function() {

            var spambox = DOM.get("spambox");

            if ( DOM.get("spamassassin").checked ) {
                spambox.disabled = false;
                spambox.title = "";
                DOM.removeClass("spambox_label", "disabled");
            } else {
                spambox.disabled = true;
                spambox.title = LOCALE.maketext("You must enable [asis,Apache SpamAssassin™] to use the Spam Box feature.");
                DOM.addClass("spambox_label", "disabled");
            }

        });

        var helpPanel;
        EVENT.on("spambox_help", "mouseover", function() {

            if ( !DOM.get("spamassassin").checked ) {
                return;
            }

            if ( !helpPanel ) {

                helpPanel = new YAHOO.widget.Panel("spambox_help_panel", {
                    width: "250px",
                    fixedcenter: false,
                    draggable: false,
                    modal: false,
                    visible: false,
                    close: false,
                });

                helpPanel.setHeader(LOCALE.maketext("Enable Spam Box"));
                helpPanel.cfg.setProperty("context", [DOM.get("spambox_help"), "tl", "br"]);
                helpPanel.setBody(DOM.get("spambox_help_content"));
                helpPanel.render(DOM.get("spambox_help"));

                DOM.get("spambox_help_content").style = "";
            }

            helpPanel.show();
        });

        EVENT.on("spambox_help", "mouseout", function() {

            if ( helpPanel ) {
                helpPanel.hide();
            }

        });

        // update nameservers
        ajaxnslist();

        // add validation
        add_new_validation();

        dologinname();
        document.getElementById("username").value = "";
        updateform();

        resetacctform();
        js_upgrade(); // warning, this function can return nothing and stop execution of this function
        // temporary fix: put it at the bottom

        // force the select options manually off on a page reload

        var manualCheckbox = DOM.get("manual");
        if (manualCheckbox) {
            manualCheckbox.checked = false;
        }

        // Submit button is initially enabled
        var submitButton = DOM.get("submit");
        if (submitButton) {
            submitButton.disabled = false;
        }
    };

    EVENT.onDOMReady(init_page);

}(window));
