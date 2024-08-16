/* Legacy code with lots of snake case. Disable ESLINT rule for camelcase in this file as such. */
/* eslint-disable camelcase */
(function(window) {
    "use strict";

    var EVENT = window.EVENT;
    var CPANEL = window.CPANEL;

    var domain_browser_box;
    var progress_panel;

    var service_cert = {};
    var service_description = {};
    var service_group = {};

    var services_ssl_table;

    var PAGE = window.PAGE;
    var nvdata = PAGE.nvdata;

    PAGE.filter_value = "default";

    var service_table_sort = nvdata && nvdata.service_table_sort || {
        key: "service_description"
    };

    /**
     * Send the install off.
     *
     * @method sendInstall
     * @param form {DOM} The form's DOM object.
     */
    var sendInstall = function(form) {
        form = DOM.get(form);

        var progress = new CPANEL.ajax.Progress_Panel(null, {
            show_status: true,
            status_html: LOCALE.maketext("Installing …")
        });
        progress.show_from_source(form);

        var install_data = CPANEL.dom.get_data_from_form(form);

        if (typeof install_data.service !== "object") {
            install_data.service = [install_data.service];
        }

        var batch = install_data.service.map(function(cur_svc) {
            var cur_install = {
                func: "install_service_ssl_certificate",
                data: Object.create(install_data)
            };

            cur_install.data.service = cur_svc;
            return cur_install;
        });

        var callback = {
            success: _installSuccess,
            failure: _installFailure,
            argument: install_data
        };
        callback.argument = install_data;
        callback.argument.progress_panel = progress;

        CPANEL.api({
            batch: batch,
            callback: callback
        });
    };

    /**
     * CPANEL.api() handler for when the install AJAX fails.
     *
     * @method _installFailure
     * @param o {Object} The response object from CPANEL.api().
     */
    var _installFailure = function(o) {
        var message_html;

        var batch_results = o.cpanel_data;

        o.argument.progress_panel.hide();

        if (batch_results && (typeof batch_results === "object")) {
            var service_list = o.argument.service;

            var succeeded = [];
            var failed = [];

            for (var r = 0; r < batch_results.length; r++) {
                var cur_service = service_list[r];
                var description = service_description[cur_service];

                if (batch_results[r].cpanel_status) {
                    succeeded.push(description);
                    service_cert[cur_service] = o.argument.crt;
                } else {
                    failed.push({
                        name: description,
                        error: batch_results[r].cpanel_error
                    });
                }
            }

            if (succeeded.length) {
                message_html = LOCALE.maketext("The system successfully updated the SSL certificate for [list_and_quoted,_1]; however, it failed to update the following [numerate,_2,service,services]:", succeeded, failed.length);
            } else {
                message_html = LOCALE.maketext("The SSL certificate update failed.");
            }

            message_html += Handlebars.compile(DOM.get("batch_failure_template").text)({
                service: failed
            });
        }

        CPANEL.ajax.show_api_error(message_html || o);
    };

    /**
     * CPANEL.api() handler for when the install AJAX succeeds.
     *
     * @method _installSuccess
     * @param o {Object} The response object from CPANEL.api().
     */
    var _installSuccess = function(o) {
        o.argument.progress_panel.hide();
        var service_names_html = o.argument.service.map(
            function(sn) {
                return service_description[sn].html_encode();
            }
        );

        var notice = new CPANEL.widgets.Dynamic_Page_Notice({
            closable: true,
            level: "success",
            content: LOCALE.maketext("You have successfully updated the SSL certificate for [list_and_quoted,_1].", service_names_html)
        });

        var scroll_window = true;

        // Shouldn't need an AJAX call to refresh the table here because we've already got the cert.
        o.argument.service.forEach(function(cur_svc) {
            service_cert[cur_svc] = o.argument.crt.trim();
            if (cur_svc === "cpanel") {
                _display_restart_cpsrvd_dialog();
                scroll_window = false;
            }
        });

        if (scroll_window) {
            var windowScroll = new CPANEL.animate.WindowScroll("ssl_table_area");
            windowScroll.animate();
        }

        _load_table_data();
    };

    /**
     * Display a restart cpsrvd notification asking users if they wish to restart cpsrvd
     *
     * @method _display_restart_cpsrvd_dialog
     */

    var _display_restart_cpsrvd_dialog = function() {
        var restart_control = new CPANEL.ajax.Common_Dialog(null, {
            effect: CPANEL.ajax.FADE_MODAL,
            show_status: true,
            close: true,
            status_html: LOCALE.maketext("Restarting [asis,cpsrvd] …")
        });

        restart_control.setHeader(CPANEL.widgets.Dialog.applyDialogHeader(LOCALE.maketext("Restart [asis,cpsrvd]")));
        restart_control.setBody("");

        restart_control.render(document.body);
        restart_control.form.innerHTML = Handlebars.compile(DOM.get("display_restart_dialog").text)({});

        var deferred_refresh = function() {
            setTimeout(function() {
                parent.location.reload();
            }, 10000);
        };

        restart_control.submitEvent.subscribe(function(e) {
            CPANEL.api({
                func: "restartservice",
                data: {
                    service: "cpsrvd"
                },
                callback: CPANEL.ajax.build_page_callback(deferred_refresh),
            });
            CPANEL.api({
                func: "restartservice",
                data: {
                    service: "cpdavd"
                },
                callback: CPANEL.ajax.build_page_callback(deferred_refresh),
            });
        });

        restart_control.show_from_source(DOM.get("sslbrowse"));
    };

    /**
     * Resets the certicate form
     *
     * @method _reset_certificate_form
     *
     * @param args {Object} The args object from _table_link_listener.
     *
     * @return {None} None
     *
     */
    var _reset_certificate_form = function(args) {
        var form = DOM.get("mainform");
        var record = args.record;

        if (record) {
            CPANEL.dom.set_form_el_value(form.service, record.getData("service_name"));
        }

        form.crt.value = "";
        form.key.value = "";
        form.cabundle.value = "";

        CPANEL.sharedjs.sslinstall.runValidation();
        CPANEL.sharedjs.sslinstall.updateUI();
    };


    /**
     * Handler for updating a given service's cert.
     *
     * @method _update_record_certificate
     * @private
     * @param args {Object} The args object from _table_link_listener.
     */
    var _update_record_certificate = function(args) {
        var form = DOM.get("mainform");

        _reset_certificate_form(args);

        var windowScroll = new CPANEL.animate.WindowScroll(form);
        windowScroll.animate();
    };

    /**
     * Handler for applying a given service's cert to another service.
     *
     * @method _apply_record_cert_to_another_service
     * @private
     * @param args {Object} The args object from _table_link_listener.
     */
    var _apply_record_cert_to_another_service = function(args) {
        CPANEL.sharedjs.sslinstall.showFormProgressOverlay();

        var windowScroll = new CPANEL.animate.WindowScroll("mainform");
        windowScroll.animate();

        var record = args.record;

        CPANEL.api({
            func: "fetch_service_ssl_components",
            api_data: {
                filter: [
                    ["service", "eq", record.getData("service_name")]
                ]
            },
            callback: CPANEL.ajax.build_page_callback(
                CPANEL.sharedjs.sslinstall.populate_form_with_ssl_components, {
                    on_error: CPANEL.sharedjs.sslinstall.hideFormProgressOverlay
                }
            )
        });
    };

    /**
     * Immediate handler for service cert reset.
     *
     * @method _confirm_reset_record_certificate
     * @private
     * @param args {Object} The args object from _table_link_listener.
     */
    var _confirm_reset_record_certificate = function(args) {
        var record = args.record;
        var clicked_el = args.clicked_el;

        // TODO: Common_Action_Dialog was designed for this kind of interaction,
        // but it uses Dynamic_Notice for success notices, which doesn't seem
        // to be the direction where we're doing. There is a lot here, though, that
        // could be refactored to reduce logic duplication elsewhere.
        var confirmation = new CPANEL.ajax.Common_Dialog(null, {
            effect: CPANEL.ajax.FADE_MODAL,
            show_status: true,
            close: true,
            status_html: LOCALE.maketext("Resetting SSL certificate for “[_1]” …", record.getData("service_description"))
        });
        DOM.addClass(confirmation.element, "reset-confirmation");
        confirmation.setHeader(CPANEL.widgets.Dialog.applyDialogHeader(LOCALE.maketext("Confirm SSL Certificate Reset")));
        confirmation.setBody("");
        confirmation.render(document.body);
        confirmation.form.innerHTML = Handlebars.compile(DOM.get("reset_confirm_template").text)({
            service: record.getData("service_description")
        });

        confirmation.submitEvent.subscribe(function(e) {
            _do_reset(record.getData("service_name"), confirmation);
        });

        confirmation.show_from_source(clicked_el);
    };

    /**
     * Do service cert reset, after the user confirmed the action.
     *
     * @method _do_reset
     * @private
     * @param service_name {String} The name of the service whose SSL to reset
     * @param dialog_box {Dialog} The YUI Dialog instance where the user confirmed this action.
     */
    var _do_reset = function(service_name, dialog_box) {

        var callback = CPANEL.ajax.build_page_callback(
            _on_reset_success, {
                hide_on_return: dialog_box
            }
        );
        callback.argument = {
            service: service_name,
            progress_panel: progress_panel
        };

        CPANEL.api({
            func: "reset_service_ssl_certificate",
            data: {
                service: service_name
            },
            callback: callback
        });
    };

    /**
     * Handler for service cert reset success
     *
     * @method _on_reset_success
     * @private
     * @param o {Object} The event object from CPANEL.api()
     */
    var _on_reset_success = function(o) {
        var service_name = o.argument.service;
        service_cert[service_name] = o.cpanel_data.certificate;

        _load_table_data();
        if (service_name === "cpanel") {
            _display_restart_cpsrvd_dialog();
            scroll_window = false;
        }
        new CPANEL.widgets.Dynamic_Page_Notice({
            level: "success",
            content: LOCALE.maketext("You have successfully reset the SSL certificate for “[_1]”.", service_description[service_name].html_encode())
        });
    };

    /**
     * Handler for showing/hiding a service cert's details.
     *
     * @method _toggle_record_certificate_details
     * @private
     * @param args {Object} The args object from the handler.
     */
    var _toggle_record_certificate_details = function(args) {
        args.datatable.toggleRowExpansion(args.row);
    };

    var link_class_action = {
        "update-link": _update_record_certificate,
        "details-link": _toggle_record_certificate_details,
        "other-service-link": _apply_record_cert_to_another_service,
        "reset-link": _confirm_reset_record_certificate
    };

    /**
     * Generic handler for SSL service cert table actions.
     *
     * @method _table_link_listener
     * @private
     * @param e {Object} The event object from the YUI DOM listener.
     * @param args {Object} The arguments object from the YUI DOM listener.
     */
    var _table_link_listener = function(e, args) {
        var link = this;
        var row_el = DOM.getAncestorByTagName(link, "tr");
        var record = args.datatable.getRecord(row_el);

        var link_classes = link.className.split(/\s+/);
        var link_class = link_classes.filter(function(c) {
            return (c in link_class_action);
        })[0];

        link_class_action[link_class]({
            record: record,
            clicked_el: link,
            datatable: args.datatable,
            row: row_el
        });
    };

    /**
     * Attach services SSL table click listeners.
     *
     * @method _attach_table_click_listeners
     * @private
     */
    var _attach_table_click_listeners = function() {
        var links = CPANEL.Y.all("#services_ssl_table .action-links a");
        EVENT.on(links, "click", _table_link_listener, {
            datatable: services_ssl_table
        });
    };

    /**
     * Create and render the services SSL table.
     *
     * @method _render_services_ssl_table
     * @private
     */
    var _render_services_ssl_table = function(table_id) {
        if (!services_ssl_table) {
            services_ssl_table = new YAHOO.widget.RowExpansionDataTable(
                table_id,
                table_columns,
                new YAHOO.util.LocalDataSource(), // dummy for the initial load
                {
                    initialLoad: false,
                    sortedBy: service_table_sort,
                    rowExpansionTemplate: function(args) {
                        var svcName = args.data.getData("service_name");
                        var isAPNS = ( svcName === "mail_apns" || svcName === "caldav_apns" );
                        return CPANEL.widgets.ssltable.detailsExpand(
                            args,
                            { "is_apns": isAPNS }
                        );
                    },
                }
            );

            CPANEL.nvdata.register("service_table_sort", function() {
                var sort = services_ssl_table.get("sortedBy");
                return {
                    key: sort.key,
                    dir: sort.dir
                };
            });

            services_ssl_table.subscribe("postRenderEvent", _attach_table_click_listeners);
        }
    };

    // Wrapper around CPANEL.nvdata.save to ensure that no args are passed in.
    var _save_nvdata_on_column_sort = function() {
        CPANEL.nvdata.save();
    };

    /**
     * Create and render the services SSL table.
     *
     * @method _load_table_data
     * @private
     */
    var _load_table_data = function() {
        var service_names = Object.keys(service_cert);
        var table_data = service_names.filter(function(name) {
            if (PAGE.filter_value && PAGE.filter_value !== service_group[name]) {
                return;
            }

            return true;
        }).map(function(name) {
            var cert_text = service_cert[name];

            // This will throw if the cert text is invalid.
            var cert_parse;
            try {
                cert_parse = CPANEL.ssl.parseCertificateText(cert_text);
            } catch (e) {
                cert_parse = {};
            }

            return {
                service_name: name,
                service_description: service_description[name],
                certificate_text: service_cert[name],
                certificate_domains: cert_parse.domains || [], // i.e., domains that the cert covers
                certificate_key_type: cert_parse.getKeyType(),
                certificate_not_after: cert_parse.notAfter,
            };
        });

        var datasource = new YAHOO.util.LocalDataSource(
            table_data, {
                responseSchema: {
                    fields: table_data_fields
                }
            }
        );

        // Urrgh. YUI 2 DataTable doesn't have a "columnClickSortEvent" distinct from a
        // programmatic "columnSortEvent". Or a way to do a "quiet" sortColumn().
        // This is needed to prevent a needless nvdata save here.
        services_ssl_table.unsubscribe("columnSortEvent", _save_nvdata_on_column_sort);

        var resubscribe = function() {
            this.unsubscribe("columnSortEvent", resubscribe);
            this.subscribe("columnSortEvent", _save_nvdata_on_column_sort);
        };
        services_ssl_table.subscribe("columnSortEvent", resubscribe);

        CPANEL.widgets.ssltable.loadTableAndSort(
            services_ssl_table, {
                datasource: datasource
            }
        );
    };

    var table_data_fields = [
        "service_name",
        "service_description",
        "service_description",
        "certificate_domains",
        "grouptype",
        "certificate_text",
        "certificate_key_type",
        {
            key: "certificate_not_after",
            parser: CPANEL.widgets.ssltable.parseUnixDate
        },
    ];

    /**
     * DataTable sorter for the "domains" field
     *
     * @param a {YAHOO.widget.Record} The first sort item
     * @param b {YAHOO.widget.Record} The second sort item
     * @param desc {Boolean} Whether the sort is a descending sort or not
     * @return {Number} -1, 0, or 1
     */
    var sort_domains = function(a, b, desc) {
        return CPANEL.widgets.ssltable.sorterStringArray(
            a.getData("certificate_domains"),
            b.getData("certificate_domains")
        ) * (desc ? -1 : 1);
    };

    /**
     * DataTable sorter for key-type strings
     *
     * @param a {YAHOO.widget.Record} The first sort item
     * @param b {YAHOO.widget.Record} The second sort item
     * @param desc {Boolean} Whether the sort is a descending sort or not
     * @return {Number} -1, 0, or 1
     */
    function sort_key_type(a, b, desc) {
        return CPANEL.widgets.ssltable.sorterKeyType(
            a.getData("certificate_key_type"),
            b.getData("certificate_key_type")
        ) * (desc ? -1 : 1);
    }

    /**
     * YUI 2 DataTable formatter for domains. Similar to what we do on Apache's SSL
     * pages but without the concept of domain matching.
     *
     * @param elCell {HTMLElement} DOM object for the cell.
     * @param oRecord {YAHOO.widget.Record} Record for this row.
     * @param oColumn {YAHOO.widget.Column} Column definition for this cell.
     * @param oData {Object} Data for the specific cell.
     */
    var format_domains = function(elCell, oRecord, oColumn, oData) {
        var items = oData.map(function(i) {
            return {
                text: i
            };
        });
        elCell.innerHTML = CPANEL.widgets.ssltable.listTemplate({
            items: items
        });
    };

    /**
     * Formatter for the datatable's "actions" column.
     *
     * @param el {HTMLElement} The element to format with the markup.
     * @param rec {YAHOO.widget.Record} Record instance.
     * @param col {YAHOO.widget.Column} Column instance.
     */

    function format_actions(el, rec, col) {
        el.innerHTML = actions_template;
    }

    function filterTable(filterKey) {
        if (services_ssl_table) {
            PAGE.filter_value = filterKey;
            _load_table_data();
        }
    }

    var actions_template = DOM.get("table_action_template").text;

    var table_columns = [
        {
            key: "service_description",
            label: LOCALE.maketext("Service"),
            sortable: true
        },
        {
            key: "certificate_domains",
            label: LOCALE.maketext("Certificate Properties"),
            sortable: true,
            sortOptions: {
                sortFunction: sort_domains
            },
            formatter: format_domains
        },
        {
            key: "certificate_not_after",
            label: LOCALE.maketext("Certificate Expiration"),
            sortable: true,
            formatter: CPANEL.widgets.ssltable.formatCertificateExpiration
        },
        {
            key: "certificate_key_type",
            label: LOCALE.maketext("Certificate Key"),
            sortable: true,
            sortOptions: {
                sortFunction: sort_key_type,
            },
            formatter: CPANEL.widgets.ssltable.formatCertificateKeyType,
        },
        {
            key: "actions",
            label: LOCALE.maketext("Actions"),
            sortable: false,
            formatter: format_actions
        },
    ];

    var TABS = {
        "IOS_CERTS": "iOScertifiates",
        "CERTS": "certificates"
    };

    var file_selector = document.getElementById("sslfilebrowse");
    var sslcrt = document.getElementById("sslcrt");
    var sslprivatekey = document.getElementById("sslkey");
    var sslpassword = document.getElementById("sslpassword");
    var sslpassword_success = document.getElementById("sslpassword_success");
    var passwordblock = document.getElementById("sslpasswordblock");
    var btnInstall = document.getElementById("btnInstall");
    var sslbrowse_btn = document.getElementById("sslbrowse");

    var password_validator;

    var current_asn1;
    var current_p12;    // i.e., decoded

    var reader = new FileReader();

    reader.onload = function(evt) {
        sslcrt.value = "";
        sslprivatekey.value = "";

        CPANEL.sharedjs.sslinstall.clearValidation();

        // Because readAsByteString() is deprecated, and because
        // forge.js doesn’t support browser ArrayBuffer.
        var byte_buffer = new forge.util.ByteBuffer(evt.target.result);

        var parsed;
        try {
            current_asn1 = forge.asn1.fromDer(byte_buffer);

            // Attempt Parse with no password (or an empty one)
            parsed = _attemptParseCert("");
        } catch (err) {
            _display_error( LOCALE.maketext("Your browser failed to parse “[_1]” as [asis,DER] because of an error: [_2]", _upload_filename(), err.message ) );
            return;
        };

        // Still nothing. We need a password
        if (!parsed) {
            DOM.get("sslpassword_label").textContent = LOCALE.maketext("Enter the password for “[_1]”:", _upload_filename());

            sslpassword_success.style.display = "none";
            passwordblock.style.display = "block";
            sslpassword.disabled = false;

            password_validator = new CPANEL.validate.validator( LOCALE.maketext("[asis,PKCS #12] Password") );
            password_validator.add(
                "sslpassword",
                function() {
                    return !!current_p12;
                },
                function() {
                    if (sslpassword.value.length) {
                        return LOCALE.maketext("The password you entered does not match “[_1]”.", _upload_filename());
                    }

                    return LOCALE.maketext("“[_1]” is encrypted. Enter this archive’s password to proceed.", _upload_filename());
                }
            );
            password_validator.attach();
            password_validator.verify(); // Show the validation logo right away

            sslpassword.focus();
        } else {
            btnInstall.focus();
        }

    };

    reader.onerror = function(evt) {
        _display_error( LOCALE.maketext("Your browser failed to load “[_1]” because of an error ([_2]): [_3]", _upload_filename(), evt.target.error.name, evt.target.error.message) );
    };

    function _upload_filename() {
        return file_selector.files[0] && file_selector.files[0].name;
    }

    function _certPasswordOnInput(event) {

        // Just in case this would otherwise be taken as a form submission.
        if (event.keyCode && event.keyCode === 13) {
            event.preventDefault();
        }

        var password = sslpassword.value;
        var cert;

        var parsed = _attemptParseCert(password);

        if (parsed) {
            sslpassword.disabled = true;
            btnInstall.focus();
        }
    }

    // cache by asn1, then password
    // var parse_cache = {};

    function _attemptParseCert(password) {
        if (current_asn1) {

            /*
            if ( parse_cache[current_asn1] ) {
                if (password in parse_cache[current_asn1] ) {
                    return parse_cache[current_asn1][password]
                }
            }
            else {
                parse_cache[current_asn1] = {};
            }
            */

            current_p12 = CPANEL.pkcs12.pkcs12FromAsn1(current_asn1, password);

            if (current_p12) {
                sslpassword_success.textContent = LOCALE.maketext("You have entered the correct password for “[_1]”.", _upload_filename());
                sslpassword_success.style.display = "block";
                DOM.get("btnInstall").disabled = false;

                if (password_validator) {
                    password_validator.verify();
                }

                try {
                    sslcrt.value = CPANEL.pkcs12.extractOnlyCertificatePem(current_p12);
                } catch (err) {
                    _display_error( LOCALE.maketext("Your browser failed to parse a certificate from “[_1]” because of an error: [_2]", _upload_filename(), err.message) );
                }

                try {
                    sslprivatekey.value = CPANEL.pkcs12.extractOnlyPrivateKeyPem(current_p12);
                } catch (err) {
                    _display_error( LOCALE.maketext("Your browser failed to parse a key from “[_1]” because of an error: [_2]", _upload_filename(), err.message) );
                }

                CPANEL.sharedjs.sslinstall.updateUI( { is_apns: true } );

                CPANEL.sharedjs.sslinstall.runValidation();

                file_selector.value = ""; // empty out the file selector so 1password doesnt trigger it later

                return true;
            }
        }

        // DOM.get("btnInstall").disabled = true;

        return;
    }

    function _display_error(str) {
        new CPANEL.widgets.Dynamic_Page_Notice({
            level: "error",
            content: str.html_encode()
        });
    }

    function _handleFileSelect(file_sel) {
        passwordblock.style.display = "none";
        sslpassword.value = null;

        var files = file_sel.files;
        var file = files[0];

        current_asn1 = null;
        current_p12 = null;

        // In case it was enabled from a correct parse.
        // DOM.get("btnInstall").disabled = true;

        // readAsByteString() would be ideal, but it’s been deprecated.
        reader.readAsArrayBuffer(file);
    }

    var last_tab;

    function _viewTab(tabName) {
        last_tab = tabName;

        var iOSmailSGLinks = document.querySelectorAll(".APNS-service-group");
        var defaultSGLinks = document.querySelectorAll(".install-service-group");

        var serviceCheckboxes = document.querySelectorAll(".install-service-group input[type=checkbox]");
        var iOSRadios = document.querySelectorAll(".APNS-service-group input[type=radio]");
        serviceCheckboxes.forEach(function(e) {
            e.checked = false;
        });

        window.PAGE.resetSSLForm();

        var HIDE_FOR_IOS = [
            document.getElementById("service_ssl_explanation"),

            // the descriptions are useless since we don’t expect
            // users to paste in the cert & key
            document.getElementById("sslcrt_description"),
            document.getElementById("sslkey_description"),
            sslbrowse_btn,
            document.getElementById("sslcab_section"),
            document.querySelector("#mainform .middle-buttons"),

            // The reset control
            document.getElementById("clear-bottom"),
        ].concat(Array.from(defaultSGLinks)).filter(function(e) {
            return e !== null;
        });

        var SHOW_FOR_IOS = [
            document.getElementById("ssl_pkcs12"),
            document.getElementById("sslupload"),
            document.getElementById("apns_explanation"),
            document.getElementById("ios_client_explanation"),
            document.getElementById("APNSFormButtons"),
        ].concat(Array.from(iOSmailSGLinks)).filter(function(e) {
            return e !== null;
        });

        var INVISIBLE_FOR_IOS = [

            // XXX HACK HACK XXX
            // No autofill-by-certificate button. Except we have code
            // in sslinstall.js that shows/hides this button, so we’ll
            // cheat and use visibility.
            document.getElementById("fetch-cert"),
        ];

        if (tabName === TABS.IOS_CERTS) {
            PAGE.parse_certs_for_apns = true;
            HIDE_FOR_IOS.forEach(function(e) {
                e.style.display = "none";
            });
            SHOW_FOR_IOS.forEach(function(e) {
                e.style.display = null;
            });
            INVISIBLE_FOR_IOS.forEach(function(e) {
                e.style.visibility = "hidden";
            });
            serviceCheckboxes.forEach(function(e) {
                e.disabled = true;
            });
            iOSRadios.forEach(function(e) {
                e.disabled = false;
            });

            window.PAGE.filterTable("ios_mail");
            document.body.classList.add("no-reset-links");

        } else if (tabName === TABS.CERTS) {
            PAGE.parse_certs_for_apns = false;
            HIDE_FOR_IOS.forEach(function(e) {
                e.style.display = null;
            });
            SHOW_FOR_IOS.forEach(function(e) {
                e.style.display = "none";
            });
            INVISIBLE_FOR_IOS.forEach(function(e) {
                e.style.visibility = null;
            });
            serviceCheckboxes.forEach(function(e) {
                e.disabled = false;
            });
            iOSRadios.forEach(function(e) {
                e.disabled = true;
            });

            window.PAGE.filterTable("default");
            document.body.classList.remove("no-reset-links");
            document.getElementById("sslpasswordblock").style.display = "none";
            document.getElementById("btnInstall").disabled = false;
        }
    }

    EVENT.on(
        "mainform",
        "submit",
        function(e) {
            if (last_tab === TABS.IOS_CERTS && !current_p12) {
                EVENT.preventDefault(e);
                return false;
            }
        }
    );

    EVENT.onDOMReady(function() {
        var myTabs = new YAHOO.widget.TabView("tabSet");

        myTabs.getTab(0).addListener("click", function() {
            _viewTab(TABS.CERTS);
        });
        myTabs.getTab(1).addListener("click", function() {
            _viewTab(TABS.IOS_CERTS);
        });
        window.PAGE.certPasswordOnInput = _certPasswordOnInput;

        PAGE.sendInstall = sendInstall;

        for (var s = 0; s < PAGE.services.length; s++) {
            var service_data = PAGE.services[s];
            service_cert[service_data.name] = service_data.certificate_text;
            service_description[service_data.name] = service_data.description;
            service_group[service_data.name] = service_data.grouptype;
        }

        _render_services_ssl_table("services_ssl_table");

        DOM.setStyle("fetch-cert", "display", "");

        if (window.location.hash && window.location.hash.indexOf("/certificates/iOS-mail") > -1) {
            myTabs.selectTab(1);
            _viewTab(TABS.IOS_CERTS);
        } else {
            _viewTab(TABS.CERTS);
        }

    });

    PAGE.handleFileSelect = _handleFileSelect;

    PAGE.filterTable = filterTable;
    PAGE.resetSSLForm = function() {
        _reset_certificate_form({});
    };

})(window);
