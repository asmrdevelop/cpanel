/*
PAGE variables:
    db_prefix    - optional, string (indicates what the DB prefix is, if any)
    db_engine    - either "mysql" or "postgresql"
    rename_url   - used when renaming a PostgreSQL user
*/
(function(window) {
    "use strict";

    var LOCALE = window.LOCALE;
    var CPANEL = window.CPANEL;
    var PAGE = window.PAGE;

    var HEADER_TEXT = {
        db: LOCALE.maketext("Rename Database"),
        user: LOCALE.maketext("Rename Database User"),
    };

    var PROGRESS_STATUS = {
        db: LOCALE.maketext("Renaming database …"),
        user: LOCALE.maketext("Renaming database user …"),
    };

    var API_FUNC;
    if (CPANEL.is_whm()) {
        API_FUNC = {
            mysql: {
                db: "rename_mysql_database",
                user: "rename_mysql_user",
            },
            postgresql: {
                db: "rename_postgresql_database",
                user: "rename_postgresql_user",
            },
        };
    } else {
        API_FUNC = {
            db: "rename_database",
            user: "rename_user",
        };

        API_FUNC = {
            mysql: API_FUNC,
            postgresql: JSON.parse(JSON.stringify(API_FUNC)),
        };

        // Since the password generator requires a modal,
        // and we're already in a modal for the rename. :(
        API_FUNC.postgresql.user = "rename_user_no_password";
    }

    var VALIDATOR_MAKER = {
        mysql: {
            db: "make_mysql_dbname_validator",
            user: "make_mysql_username_validator",
        },
        postgresql: {
            db: "make_postgresql_dbname_validator",
            user: "make_postgresql_username_validator",
        },
    };

    var prefix_regexp = PAGE.db_prefix && new RegExp("^" + PAGE.db_prefix.regexp_encode());

    var rename_template = Handlebars.compile(DOM.get("sql_rename_template").text);

    /**
     * Shows a dialog box that handles a rename API call.
     *
     * @param {String} renamee_type Either "db" or "user".
     * @param {DOM} source_el An element from which to show the dialog box.
     * @param {String} dbobj_name The name of the object to rename.
     */
    function show_rename_form(renamee_type, source_el, dbobj_name) {

        var is_pgsql_user_rename = (renamee_type === "user") && (PAGE.db_engine === "postgresql");

        var newname;

        var make_newname = function(name) {
            return CPANEL.sql.add_prefix(name);
        };

        var dialog = new CPANEL.ajax.Common_Action_Dialog("rename_dialog", {
            close: true,
            clicked_element: source_el,
            header_html: HEADER_TEXT[renamee_type],
            strings: {
                "close": LOCALE.maketext("Close"),
            },
            errors_in_notice_box: true,
            show_status: true,
            form_template: rename_template({
                oldname: dbobj_name,
                oldname_no_prefix: prefix_regexp ? dbobj_name.replace(prefix_regexp, "") : dbobj_name,
                is_postgresql_name: is_pgsql_user_rename,
            }),
            no_hide_after_success: true,
            success_function: function() {
                if (is_pgsql_user_rename) {
                    this.progress_overlay.set_status_now(LOCALE.maketext("Success! The browser is now redirecting …"));
                    location.href = PAGE.rename_url + "?" + CPANEL.util.make_query_string({
                        user: newname,
                        action_context: "rename",
                    });
                } else {
                    this.progress_overlay.set_status_now(LOCALE.maketext("Success! This page will now reload."));
                    location.reload();
                }
            },
            success_notice_options: {
                visible: false,
            },
            status_template: PROGRESS_STATUS[renamee_type],
            api_calls: [{
                api_version: CPANEL.is_whm() ? 1 : 3,
                api_module: (PAGE.db_engine === "mysql") ? "Mysql" : "Postgresql",
                api_function: API_FUNC[PAGE.db_engine][renamee_type],
                data: function() {
                    newname = make_newname(this.form.newname.value);

                    return {
                        oldname: dbobj_name,
                        newname: newname,
                    };
                },
            }],
        });
        dialog.beforeShowEvent.subscribe(function classer(evt) {
            this[evt + "Event"].unsubscribe(classer);
            DOM.addClass(this.element, "rename-dialog");

            if (prefix_regexp && !prefix_regexp.test(dbobj_name)) {
                var content = (renamee_type === "db") ?
                    LOCALE.maketext("If you change this database’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.", dbobj_name.html_encode(), PAGE.db_prefix.html_encode()) :
                    LOCALE.maketext("If you change this user’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.", dbobj_name.html_encode(), PAGE.db_prefix.html_encode());

                (new CPANEL.widgets.Page_Notice({
                    level: "warn",
                    content: content,
                    container: CPANEL.Y(this.element).one(".oldname-unprefixed-notice-area"),
                    visible: false,
                })).show();
            }

            if ((renamee_type === "db") && (PAGE.db_engine === "mysql")) {
                var backup_link = CPANEL.security_token + "/getsqlbackup/" + encodeURIComponent(dbobj_name) + ".gz";

                (new CPANEL.widgets.Page_Notice({
                    level: "warn",
                    content: LOCALE.maketext("It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.", backup_link),
                    container: CPANEL.Y(this.element).one(".rename-warning-area"),
                    visible: false,
                })).show();
            }

            var validator_maker_name = VALIDATOR_MAKER[PAGE.db_engine][renamee_type];
            this._validator = CPANEL.sql[validator_maker_name]("rename_newname");

            this._validator.add_for_submit(
                this.form.newname,
                function() {
                    return make_newname(dialog.form.newname.value) !== dbobj_name;
                },
                LOCALE.maketext("The new name must be different from the old name.")
            );
            bindValidationSync(this._validator, this.element);
        });
        dialog.beforeSubmitEvent.subscribe(function() {
            this._validator.verify_for_submit();
            return this._validator.is_valid();
        });
        dialog.animated_show();

        return dialog;
    }

    // Adapter code to show the results of the SQL CJT validations using the Paper Lantern validation markup.
    // Old CJT validation styles are deprecated / broken.
    // This code reuses the existing validation logic and solves the display problems.
    // see FB 117465
    function bindValidationSync(validator, dialog) {
        validator.validateFailure.subscribe(function(type, args) {
            if (args[0] && args[0].is_submit_only_failure) {
                clearErrors(dialog);
            } else {
                syncErrors(dialog);
            }
        });
        validator.validateSuccess.subscribe(function() {
            clearErrors(dialog);
        });
    }

    // Grab the CJT error element, extract validation results from it and update the validation markup.
    function syncErrors(dialog) {
        var $dialog = $(dialog),
            $cjtError = $dialog.find("#rename_newname_error"),
            $errorImg = $cjtError.find("img"),
            $validationContainer = $dialog.find("#newname_validation_container"),
            $validationMessage = $validationContainer.find(".validation_errors_li");
        if ($errorImg.length && $errorImg.attr("alt") === "error") {
            $validationContainer.removeClass("hide");
            $validationMessage.text($errorImg.attr("title"));
        }
    }

    function clearErrors(dialog) {
        var $dialog = $(dialog),
            $validationContainer = $dialog.find("#newname_validation_container"),
            $validationMessage = $validationContainer.find(".validation_errors_li");
        $validationContainer.addClass("hide");
        $validationMessage.text("");
    }

    window.SQLUI = {
        show_rename_form: show_rename_form,
    };

}(window));
