/*
# cpanel - whostmgr/docroot/js2/edituser.js        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

 */
/* globals LANG: false, original_values: false, user_package: false, childNodeOptions: false */
/* eslint-disable camelcase */
/* eslint-disable strict */
var VALID = {};

var MAX_USERNAME_LENGTH = 16;
var isRtl = CPANEL.dom.isRtl();

function update_displayed_package_values() {
    var pkg_vals = user_package;
    if (pkg_vals) {
        for (var key in pkg_vals) {
            if (key in original_values) {
                if (String(pkg_vals[key]) === String(original_values[key])) {
                    DOM.setStyle("package_value_label_" + key, "display", "none");
                } else {
                    DOM.setStyle("package_value_label_" + key, "display", "");

                    var val = pkg_vals[key];
                    var formatted = val;
                    if (!isNaN(parseFloat(val)) && isFinite(val)) {
                        if (key == "BWLIMIT" || key == "QUOTA") {
                            formatted = LOCALE.numf(val / 1048576);
                        } else {
                            formatted = BOOLEAN_PACKAGE_VALUES[key] ? ON_OFF[ !!parseInt(val)] : LOCALE.numf(val);
                        }
                    }

                    // package extensions may not have this element
                    // in their subforms, and the element doesn't seem essential
                    // so only set the value if the form element actually exists

                    var packageValueElement = DOM.get("package_value_" + key);

                    if (packageValueElement) {
                        packageValueElement.innerHTML = formatted;
                    }
                }
            }
        }
    } else {
        CPANEL.Y.all(".package-value-label").forEach(function(el) {
            DOM.setStyle(el, "display", "none");
        });
    }
}

/**
 * remove the missing extensions warning on successful save if
 * "remove" checkbox is checked
 *
 * @method  check_for_missing_extensions
 */

function check_for_missing_extensions() {
    var missingExtensionsDiv = DOM.get("missingExtensionsGroup");
    var missing_extensions_checkbox = DOM.get("missingPackageExtensionsCheckbox");
    if (missingExtensionsDiv && missing_extensions_checkbox.checked == true) {
        DOM.addClass(missingExtensionsDiv, "hidden");
        missingExtensionsDiv.parentNode.removeChild(missingExtensionsDiv);
    }
}

function check_submit(clicked_el) {
    var form = document.getElementById("edituser_form");
    var form_data = CPANEL.dom.get_data_from_form("edituser_form", {
        include_unchecked_checkboxes: 0,
    });
    var hasshell = form.HASSHELL;

    for (var key in form_data) {
        var match = key.match(/^(.*)_chooser$/);
        if (match) {
            if (form_data[key] !== "custom") {
                form_data[match[1]] = form_data[key];
            }
            delete form_data[key];
        }
    }

    var package_altered = false;

    // the API wants bytes
    ["QUOTA", "BWLIMIT"].forEach(function(k) {
        if ((k in form_data) && (form_data[k] !== "unlimited")) {
            form_data[k] = parseInt(form_data[k]) * 1048576;
        }
    });

    // Check username, domain, and contact email "manually" since
    // these are spelled differently in different places.
    var something_changed = form_data.newuser !== original_values.USER || form_data.domain !== original_values.DOMAIN || form_data.contactemail !== original_values.CONTACTEMAILS;

    // use fuzzy equality checks here since Perl does not typecast reliably
    /* jshint -W116 */
    for (key in form_data) {
        if ((key in original_values) && form_data[key] != original_values[key]) {

            // HASSHELL is a checkbox, but has its value set to the path of the
            // current shell. We just need to see if the checkbox is checked
            // and if that is different from the original value, which would be either
            // a "0" or a "1".
            if (key === "HASSHELL" && hasshell.checked == original_values["HASSHELL"]) {
                continue;
            }

            something_changed = true;
            if (user_package && (key !== "LOCALE") && (key in user_package) && (form_data[key] !== user_package[key])) {
                package_altered = true;
            }

        }

        // only enhancements that are checked have a non-zero value
        if (key.startsWith("account_enhancements-")) {
            if (parseInt(form_data[key], 10) === 0) {
                delete form_data[key];
            }
        }

    }
    /* jshint +W116 */

    // check to see if remove missing packages is checked

    var missing_extensions_checkbox = DOM.get("missingPackageExtensionsCheckbox");
    if (missing_extensions_checkbox && missing_extensions_checkbox.checked == true) {

        // force something_changed and package_altered to true if checked
        something_changed = true;

        // if PLAN is not undefined, force the reconciliation dialog
        if (original_values.PLAN && original_values.PLAN !== "undefined") {
            package_altered = true;
        }
    }

    // nothing changed, so do nothing
    if (!something_changed) {
        alert(LANG.must_change);
        return;
    }

    // make sure we have valid data
    if (!CPANEL.util.values(VALID).every(function(v) {
        return v.is_valid();
    })) {
        return;
    }

    form_data.user = original_values.USER;

    delete form_data._submit;

    var status_html = package_altered ? LANG.checking_for_matches : YAHOO.lang.substitute(LANG.saving, form_data);

    var progress_panel = new CPANEL.ajax.Progress_Panel(null, {
        show_status: true,
        status_html: status_html,
    });

    progress_panel.show_from_source(clicked_el);

    // no change of package values, so we just save and go on
    if (!package_altered) {
        save_without_dialog(form_data, progress_panel);
        return;
    }

    // Change the package values, so offer these options:
    // 1. Change this account to a package matching the new values.
    //   (requires an AJAX call before showing the dialog box)
    // 2. Add a package with the new values and set the account to use it.
    // 3. Change the package (and all its users) to have the new values.
    // 4. Take the account off the package, and save the values.
    // 5. Save the account's new values and leave the package setting in place.

    var callback = CPANEL.ajax.build_callback(
        function(o) {
            var packages = o.cpanel_data;
            var form_template;
            if (packages && packages.length > 0) {
                form_template = CPANEL.ajax.templates.submit_with_match_template;
            } else {
                form_template = CPANEL.ajax.templates.submit_no_match_template;
            }

            if (form_template) {
                var packages_html = packages.map(function(p) {
                    return "<option value='" + p.name.html_encode() + "'>" + p.name.elide(50).html_encode() + "</option>";
                });

                if (can_add_package) {
                    form_template += CPANEL.ajax.templates._submit_add_pkg_template;
                }

                form_template += CPANEL.ajax.templates._submit_include_template;

                var form_template_variables = {
                    package_options_html: packages_html,
                    PLAN: original_values.PLAN.elide(50).html_encode(),
                };

                var dialog_opts = {
                    header_html: LANG.plan_conflict_resolution,
                    form_template: form_template,
                    form_template_variables: form_template_variables,
                    clicked_element: clicked_el,
                    show_status: true,
                    success_status: LOCALE.maketext("Success!"),
                    success_function: function() {
                        delete form_data["PLAN"];
                        check_for_missing_extensions();
                        update_original_values(form_data);
                    },
                };

                save_with_dialog(form_data, progress_panel, dialog_opts);
            }
        }, {
            current: progress_panel,
        }, {
            keep_current_on_success: true,
            whm: true,
        }
    );

    if (user_package) {
        form_data.exclude = original_values.PLAN;
    }

    CPANEL.api({
        application: "whm",
        func: "matchpkgs",
        data: form_data,
        callback: callback,
    });
}

function getChangedChildNodeOptions(original_values, new_values) {
    return Object.keys(childNodeOptions).filter(function(key) {
        var parameter = childNodeOptions[key].parameter;
        if (original_values[parameter] !== new_values[parameter]) {
            return true;
        }
        return false;
    }).map(function(key) {
        return childNodeOptions[key].parameter;
    });
}

function update_original_values(new_values) {
    for (var original_key in original_values) {
        if (original_key.startsWith("account_enhancements-")) {
            new_values[original_key] = new_values[original_key] || 0;
        }
    }

    for (var key in original_values) {
        if (key in new_values) {
            original_values[key] = new_values[key];
        }
    }

    if ("newuser" in new_values) {
        const upgradeUrlEl = document.getElementById("selectupgrade_url");
        if (upgradeUrlEl) {
            upgradeUrlEl.innerHTML = upgradeUrlEl.innerHTML.replace( "=" + original_values.USER, "=" + new_values.newuser );
        }

        update_original_value_for("USER", new_values.newuser);
        ORGUSER = new_values.newuser;
        CPANEL.util.set_text_content("editing_user", new_values.newuser);
    }

    if ("domain" in new_values) {
        update_original_value_for("DOMAIN", new_values.domain);
        ORGDOMAIN = new_values.domain;
        CPANEL.util.set_text_content("editing_domain", new_values.domain);
    }

    if ("contactemail" in new_values) {
        update_original_value_for("CONTACTEMAILS", new_values.contactemail);
    }

    noticeCollection.updateAllOriginalValues();
    hide_domain_data_warning();

    var showResellerWarning = Number(original_values.reseller);
    DOM.setStyle("reseller_warning", "display", showResellerWarning ? "" : "none");
    DOM.setStyle("basic_info_notes", "display", showResellerWarning ? "" : "none");

    update_displayed_package_values();

}

function update_user_package(new_values) {
    for (var key in user_package) {
        if (key in new_values) {
            user_package[key] = new_values[key];
        }
    }

    update_displayed_package_values();
}

function save_without_dialog(form_data, progress_panel) {
    var callback = CPANEL.ajax.build_callback(
        function(o) {
            progress_panel.cfg.setProperty("effect", CPANEL.ajax.FADE_MODAL);
            progress_panel.hide();
            new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("Success!"),
                level: "success",
            });
            check_for_missing_extensions();
            update_original_values(form_data);

            var json_response = YAHOO.lang.JSON.parse(o.responseText);
            if (json_response && json_response.metadata && json_response.metadata.output) {
                if (json_response.metadata.output.messages && json_response.metadata.output.messages.length) {
                    new CPANEL.widgets.Dynamic_Page_Notice({
                        level: "info",
                        content: json_response.metadata.output.messages.map(function(s) {
                            return s.html_encode();
                        }).join("<br />"),
                        container: "edituser_messages",
                    });
                }
                if (json_response.metadata.output.warnings && json_response.metadata.output.warnings.length) {
                    new CPANEL.widgets.Dynamic_Page_Notice({
                        level: "warn",
                        content: json_response.metadata.output.warnings.map(function(s) {
                            return s.html_encode();
                        }).join("<br />"),
                        container: "edituser_warnings",
                    });
                }
            }
        }, {
            current: progress_panel,
        }, {
            keep_current_on_success: true,
            whm: true,
        }
    );

    form_data.rename_database_objects = _read__rename_database_objects(form_data);

    CPANEL.api({
        application: "whm",
        func: "modifyacct",
        data: form_data,
        callback: callback,
    });
}

function _read__rename_database_objects(form_data) {
    if ("rename_database_objects" in form_data) {
        return form_data.rename_database_objects ? 1 : 0;
    }

    return 1;
}

function save_with_dialog(form_data, progress_panel, dialog_opts) {
    var the_dialog = new CPANEL.ajax.Common_Action_Dialog("confirm_dialog", dialog_opts);

    the_dialog.beforeShowEvent.subscribe(function initdialog() {
        the_dialog.beforeShowEvent.unsubscribe(initdialog);

        // Set the overlay element to a smaller width so it does not need to cover the side navigation
        DOM.setStyle(the_dialog.element, "width", "80%");

        // center the element so that horizontal and vertical centering is handled (vertical centering value will not change after this)
        this.center();

        var asideSize = document.querySelector("#cp-main-menu-container").getBoundingClientRect();
        var newSize = asideSize.width + (asideSize.width * 0.1);

        // move the overlay element horizontally the width of the side navigation element + 10%
        if (isRtl) {
            this.moveTo(newSize * -1);
        } else {
            this.moveTo(newSize);
        }


        DOM.getElementBy(
            function(el) {
                return el.type.toLowerCase() === "radio";
            },
            "input",
            the_dialog.form
        ).checked = true;

        var grouped_input_set = new CPANEL.ajax.Grouped_Input_Set(the_dialog.form);
    });

    the_dialog.beforeSubmitEvent.subscribe(function() {

        var non_package_values = {};
        for (var key in form_data) {
            if (!(key in original_values)) {
                continue;
            }
            if (key === "PLAN") {
                continue;
            }

            if (form_data[key] !== original_values[key]) {
                non_package_values[key] = form_data[key];
            }
        }

        if (original_values.USER !== form_data.newuser) {
            non_package_values.newuser = form_data.newuser;
        }
        if (original_values.DOMAIN !== form_data.domain) {
            non_package_values.domain = form_data.domain;
        }
        if (original_values.CONTACTEMAILS !== form_data.contactemail) {
            non_package_values.contactemail = form_data.contactemail;
        }

        var dialog_data = CPANEL.dom.get_data_from_form(this.form);

        var api_calls = [];
        if (Object.keys(non_package_values).length) {
            non_package_values.user = original_values.USER;
            non_package_values.rename_database_objects = _read__rename_database_objects(form_data);

            api_calls.push({
                api_application: "whm",
                api_function: "modifyacct",
                data: non_package_values,
                status_template: LOCALE.maketext("Saving non-package values …"),
                success_function: function(o) {
                    update_original_values(non_package_values);
                    var json_response = YAHOO.lang.JSON.parse(o.responseText);
                    if (json_response && json_response.metadata && json_response.metadata.output) {
                        if (json_response.metadata.output.messages && json_response.metadata.output.messages.length) {
                            new CPANEL.widgets.Dynamic_Page_Notice({
                                level: "info",
                                content: json_response.metadata.output.messages.map(function(s) {
                                    return s.html_encode();
                                }).join("<br />"),
                                container: "edituser_messages",
                            });
                        }
                        if (json_response.metadata.output.warnings && json_response.metadata.output.warnings.length) {
                            new CPANEL.widgets.Dynamic_Page_Notice({
                                level: "warn",
                                content: json_response.metadata.output.warnings.map(function(s) {
                                    return s.html_encode();
                                }).join("<br />"),
                                container: "edituser_warnings",
                            });
                        }
                    }
                },
            });
        }

        if (dialog_data.plan_change_resolution === "modify_pkg") {
            form_data.pkgname = original_values.PLAN;
            api_calls.unshift({
                api_application: "whm",
                api_function: "editpkg",
                data: form_data,
                status_template: LANG.updating_package,
                success_function: function() {
                    update_user_package(form_data);
                },
            });
        } else if (can_add_package && dialog_data.plan_change_resolution === "add_pkg") {
            form_data.pkgname = dialog_data.ADDPLAN;

            // restore the values that were removed
            YAHOO.lang.augmentObject(form_data, original_values);

            // the actual package name might differ slightly from what we submit
            var created_package = {};

            api_calls.unshift({
                api_application: "whm",
                api_function: "addpkg",
                data: form_data,
                status_template: LANG.creating_package,
                success_function: function(result) {
                    created_package.name = result.cpanel_data.pkg;
                },
            }, {
                api_application: "whm",
                api_function: "changepackage",
                data: function() {
                    return {
                        user: original_values.USER,
                        pkg: created_package.name,
                    };
                },
                status_template: LANG.assigning_account_to_package,
                success_function: function() {
                    CPANEL.util.set_text_content("package_name", created_package.name);
                    update_original_value_for("PLAN", created_package.name);
                    update_user_package(form_data);
                },
            });
        } else if (dialog_data.plan_change_resolution === "change_pkg") {
            api_calls.unshift({
                api_application: "whm",
                api_function: "changepackage",
                data: {
                    user: original_values.USER,
                    pkg: dialog_data.CHANGEPLAN,
                },
                status_template: LANG.assigning_account_to_package,
                success_function: function() {
                    CPANEL.util.set_text_content("package_name", dialog_data.CHANGEPLAN);
                    update_original_value_for("PLAN", dialog_data.CHANGEPLAN);
                    update_user_package(form_data);
                },
            });
        } else {
            form_data.USER = original_values.USER;

            form_data.rename_database_objects = _read__rename_database_objects(form_data);

            api_calls = [{
                api_application: "whm",
                api_function: "modifyacct",
                data: form_data,
                status_template: LANG.saving,
            }];

            if (dialog_data.plan_change_resolution === "undefined") {
                form_data.PLAN = "undefined";
                api_calls[0].success_function = function() {
                    CPANEL.util.set_text_content("package_name", "undefined");
                    user_package = null;
                    update_original_value_for("PLAN", "undefined");

                    // Hide the "package value" notices.
                    var dummy = document.createElement("div");
                    dummy.innerHTML = "<style>.package-value-label {display:none}</style>";
                    document.body.appendChild(dummy.firstChild);
                };
            } else {
                api_calls[0].success_function = function() {
                    update_original_values(form_data);
                };
            }
        }

        the_dialog.cfg.setProperty("api_calls", api_calls);
    });

    progress_panel.fade_to(the_dialog);
}

function update_original_value_for(k, v) {
    window.original_values[k] = v;
    return;
}

function limits_chooser(limittype, choosername) {
    var working_id = document.getElementById(choosername + "_text");
    if (/custom/i.test(limittype)) {
        working_id.style.color = "#000";
        working_id.disabled = false;
        working_id.focus();
    } else {
        working_id.style.color = "#ccc";
        working_id.disabled = true;
    }
    VALID[choosername].clear_messages();
    VALID[choosername].verify();
}

function limits_chooser_custommod(choosername) {
    document.getElementById(choosername + "_text").style.color = "#000";
    document.getElementById(choosername + "_chooser_custom").checked = true;
    VALID[choosername].clear_messages();
    VALID[choosername].verify();
}

function display_domain_data_warning() {
    YAHOO.util.Dom.replaceClass("domain_data_warning", "hidden", "note");
}

function hide_domain_data_warning() {
    YAHOO.util.Dom.replaceClass("domain_data_warning", "note", "hidden");
}

function dismiss_paper_lantern_warning(clicked_el) {  // eslint-disable-line no-unused-vars
    YAHOO.util.Dom.replaceClass("paper_lantern_warning", "note", "hidden");

    var request = new XMLHttpRequest();
    request.open("POST", CPANEL.security_token + "/json-api/personalization_set");
    request.setRequestHeader("Content-Type", "application/json");
    request.send(JSON.stringify({ "api.version": 1, "personalization": { "hide_paper_lantern_notice": 1 } }));
}

var add_new_validation = function() {  // eslint-disable-line strict
    // eslint-disable-next-line new-cap
    VALID["domain"] = new CPANEL.validate.validator(LOCALE.maketext("Domain"));
    VALID["domain"].add("domain", "fqdn", LANG.must_be_fqdn);
    VALID["domain"].add("domain", function() {
        var domain = YAHOO.util.Dom.get("domain").value;
        if ( domain !== ORGDOMAIN && DOMAINS_WITH_DATA.indexOf(domain) !== -1 ) {
            display_domain_data_warning();
        } else {
            hide_domain_data_warning();
        }
        return true; // always return true, because we will still allow the attempt even though it could be risky
    }, LOCALE.maketext("It is dangerous to change the account’s primary domain to one that already has data associated with it."));
    VALID["domain"].attach();

    if (document.getElementById("newuser")) {
        var username_length = function() {
            var username = YAHOO.util.Dom.get("newuser").value;
            if (username === ORGNAME) {
                return true;
            }

            return CPANEL.validate.max_length(username, MAX_USERNAME_LENGTH);
        };
        var username_stupidstuff = function() {
            var username = YAHOO.util.Dom.get("newuser").value;
            return CPANEL.validate.alpha(username.charAt(0));
        };
        var valid_username = function() {
            var value = document.getElementById("newuser").value;
            return (new RegExp(window.username_regexp)).test(value);
        };
        // eslint-disable-next-line new-cap
        VALID["newuser"] = new CPANEL.validate.validator(LOCALE.maketext("Username"));
        VALID["newuser"].add("newuser", "no_chars(%input%,' ')", LOCALE.maketext("A username cannot have spaces."));
        VALID["newuser"].add("newuser", username_length, LOCALE.maketext("A username cannot be longer than [quant,_1,character,characters].", MAX_USERNAME_LENGTH));
        VALID["newuser"].add("newuser", username_stupidstuff, LOCALE.maketext("A username cannot start with a number."));
        VALID["newuser"].add("newuser", valid_username, LOCALE.maketext("A username must only contain lowercase alphanumeric characters."));
        VALID["newuser"].add("newuser", function() {

            // We allow understores if DB prefixing is disabled.
            if ( !HAS_DB_PREFIX ) {
                return 1;
            }

            // If the value has not changed there is no need to validate it
            // as we want to allow everything that already exists in.
            if ( document.getElementById("newuser").value === document.getElementById("newuser").defaultValue ) {
                return 1;
            }
            // eslint-disable-next-line no-useless-escape
            return !/\_/.test(document.getElementById("newuser").value);
        }, LOCALE.maketext("Usernames may not contain underscores."));
        VALID["newuser"].attach();
    }

    if (DOM.get("contactemail")) {
        var valid_emails = function() {
            var contactemail = DOM.get("contactemail").value.trim();

            if (!contactemail) {
                return true;
            }

            contactemail = contactemail.split(/[\s;,]+/);
            if (contactemail.length > 2) {
                return false;
            }

            return contactemail.every(CPANEL.validate.email);
        };
        // eslint-disable-next-line new-cap
        VALID["contactemail"] = new CPANEL.validate.validator(LOCALE.maketext("Contact Email"));
        VALID["contactemail"].add("contactemail", valid_emails, LOCALE.maketext("You must provide one or two valid contact emails."));
        VALID["contactemail"].attach();
    }

    CPANEL.validate.validate_limits = function(val, el) {
        var el2 = document.getElementById(el + "_chooser_custom").checked;
        return (el2 && CPANEL.validate.positive_integer(val));
    };

    els = YAHOO.util.Dom.getElementsByClassName("validation_selector");

    for (var i = els.length - 1; i >= 0; i--) {
        var cur_el = els[i];

        var maxvar = cur_el.id.split("_text")[0];
        VALID[maxvar] = new CPANEL.validate.validator(VARHEADERS[maxvar]);
        VALID[maxvar].add(cur_el.id, 'validate_limits($INPUT$,"' + maxvar + '")', LANG.must_be_number.replace("{label}", VARHEADERS[maxvar]));
        VALID[maxvar].attach();

        var cell = DOM.getAncestorByTagName(cur_el, "div");
        var inputs = cell.getElementsByTagName("input");

        if (inputs[0].type.toLowerCase() === "radio") {
            var gset = new CPANEL.ajax.Grouped_Input_Set(cur_el.form, inputs[0], inputs[inputs.length - 1]);

            // In some scenarios the layout seems to change after the
            // Grouped_Input_Set object is created. When that happens
            // the gset object goes out of alignment with its underlying
            // <input> element. Ideally we’d install some sort of hook to
            // align after such layout changes, but there seems no obvious
            // way to do that. The below is inelegant, but it’s also simple,
            // and it does fix the problem for all practical purposes.
            //
            setInterval( gset.align.bind(gset), 0.01 );

            (function() {
                var my_el = cur_el,
                    validator = VALID[maxvar],
                    err_el = DOM.get(maxvar + "_text_error");
                gset.onrefresh = function(grp) {
                    if (grp.inputs[0] === my_el) {
                        err_el.style.display = "";
                        validator.verify();
                    } else {
                        err_el.style.display = "none";
                        validator.hide_all_panels();
                    }
                };
            }());
        }

    }

    if (DOM.get("max_team_users_field")) {
        var valid_max_team_users = function() {
            var max_team_users_field = DOM.get("max_team_users_field").value.trim();

            if (!max_team_users_field) {
                return false;
            }

            max_team_users_field = max_team_users_field.split(/[\s;,]+/);
            if (max_team_users_field.length > 2) {
                return false;
            }

            if ( max_team_users_field < 0 || max_team_users_field > window.PAGE.SERVER_MAX_TEAM_USERS ) {
                return false;
            }

            return true;
        };
        // eslint-disable-next-line new-cap
        VALID["max_team_users_field"] = new CPANEL.validate.validator(
            LOCALE.maketext("Max Team Users with Roles")
        );
        VALID["max_team_users_field"].add(
            "max_team_users_field",
            valid_max_team_users,
            LOCALE.maketext(
                "The input must be a number between “[_1]” and “[_2]”.",
                0,
                window.PAGE.SERVER_MAX_TEAM_USERS
            )
        );
        VALID["max_team_users_field"].attach();
    }

    CPANEL.validate.attach_to_form("submitit", VALID);
};

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

/**
 * Show and hide the change notices
 */
var Notice = (function() {

    function Notice(notice_id, input_id) {
        this.noticeElem = document.getElementById(notice_id);
        this.inputElem  = document.getElementById(input_id);
        this.originalInputVal = this.inputElem.value;
        this.clicked = false;
        this.focused = false;
    }

    Notice.prototype.show = function() {
        YAHOO.util.Dom.replaceClass(this.noticeElem, "hidden", "note");
    };

    Notice.prototype.hide = function() {
        YAHOO.util.Dom.replaceClass(this.noticeElem, "note", "hidden");
    };

    Notice.prototype.render = function() {
        var changed = this.inputElem.value !== this.originalInputVal;

        if (changed || this.clicked || this.focused) {
            this.show();
        } else {
            this.hide();
        }
    };

    Notice.prototype.clearFlags = function() {
        this.clicked = this.focused = false;
    };

    return Notice;
})();

var noticesList = [
    new Notice("domain_change_notice", "domain"),
];

if (document.getElementById("newuser")) {
    noticesList.push(
        new Notice("username_change_warning", "newuser")
    );
}

var noticeCollection = {
    notices: noticesList,
    updateAllOriginalValues: function() {
        this.notices.forEach(function(notice) {
            notice.clicked = false;
            notice.focused = false;
            notice.originalInputVal = notice.inputElem.value;
        });
        this.renderAll();
    },
    renderAll: function() {
        this.notices.forEach(function(notice) {
            notice.render();
        });
    },
    clearFlagsAll: function() {
        this.notices.forEach(function(notice) {
            notice.clearFlags();
        });
    },
    findByNotice: function(noticeElem) {
        var found;
        this.notices.some(function(notice) {
            if (notice.noticeElem === noticeElem) {
                found = notice;
                return true;
            }
        });
        return found;
    },
    findByInput: function(inputElem) {
        var found;
        this.notices.some(function(notice) {
            if (notice.inputElem === inputElem) {
                found = notice;
                return true;
            }
        });
        return found;
    },
    addEventListeners: function() {
        var self = this;

        // Loop through the notice objects to attach the individual event listeners.
        this.notices.forEach(function(notice) {

            /**
             * When focusing an element with a notice, we should show that notice and remove any
             * state from other notices.
             *
             * @method processInputFocus
             */
            YAHOO.util.Event.addListener(notice.inputElem, "focus", function processInputFocus() {
                self.clearFlagsAll();
                notice.focused = true;
                self.renderAll();
            });

            /**
             * When blurring an element with a notice, we should adjust the focused state from the
             * associated notice and render all notices again (in case any have the clicked state).
             *
             * @method processInputFocus
             */
            YAHOO.util.Event.addListener(notice.inputElem, "blur", function processInputBlur() {
                notice.focused = false;
                self.renderAll();
            });
        });

        /**
         * We want to respond to clicks registered anywhere in the document. Once fired, we need
         * to determine if it originated from within a notice or not. If not, then we only want
         * to show notices for fields that have changed or are focused.
         *
         * We listen on mousedown instead of click, because that event fires before blur.
         *
         * @method processClick
         * @param  {Event} e   The click Event object.
         */
        YAHOO.util.Event.addListener(document.body, "mousedown", function processClick(e) {
            var clickedNotice = YAHOO.util.Dom.getAncestorByClassName(e.target, "note");
            var clickedInput = self.findByInput(e.target);
            var notice;

            if (clickedNotice) {

                // No need to render after setting clicked to true, because:
                // - We don't want the view to change just because they clicked on the notice.
                // - The blur handler will call the render method anyhow.
                notice = self.findByNotice(clickedNotice);
                if (notice) {
                    notice.clicked = true;
                }
            } else if (!clickedInput) { // Don't trigger if they clicked the same focused input.
                self.clearFlagsAll();
                self.renderAll();
            }
        });

        /**
         * When a focus event originates from somewhere other than one of our notices or inputs,
         * we only want to show notices belonging to changed inputs.
         *
         * We need to use the useCapture parameter to be able to grab bubbled focus events, so we
         * can't use the YAHOO method for adding the listener.
         *
         * @method processBubbledFocus
         * @param  {Event} e   The focus Event object.
         */
        document.body.addEventListener("focus", function processBubbledFocus(e) {
            var insideNotice = YAHOO.util.Dom.getAncestorByClassName(e.target, "note");
            if ( !self.findByInput(e.target) && !insideNotice ) {
                self.clearFlagsAll();
                self.renderAll();
            }
        }, true);
    },
};


var BOOLEAN_PACKAGE_VALUES = {
    HASCGI: 1,
    HASSHELL: 1,
};


noticeCollection.addEventListeners();

YAHOO.util.Event.onDOMReady(add_new_validation);
YAHOO.util.Event.onDOMReady(update_displayed_package_values);
YAHOO.util.Event.onDOMReady(addLastStyleToPropertyGroups);
