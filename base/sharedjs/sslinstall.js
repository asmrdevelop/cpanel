/* global LOCALE:false */

(function(window) {
    "use strict";

    // -----------------------
    //  Shortcuts
    // -----------------------
    var YAHOO = window.YAHOO;
    var CPANEL = window.CPANEL;
    var DOM = YAHOO.util.Dom;
    var EVENT = YAHOO.util.Event;
    var LANG = YAHOO.lang;
    var REGION = YAHOO.util.Region;
    var document = window.document;
    var Handlebars = window.Handlebars;

    var PAGE = window.PAGE;

    var nvdata = PAGE && PAGE.nvdata || {};
    var certificates_table_sort = nvdata.certificates_table_sort || { key: "domains" };

    // -----------------------
    // Constants
    // -----------------------
    var IP_COMBOBOX_CONFIG = {
        useShadow: false,
        expander: "ipexpander",
        applyLocalFilter: true,
        queryMatchCase: false,
        typeAhead: true,
        autoHighlight: false
    };

    var MAX_COLUMN_WIDTH = {
        user: 90,
        apache: 130
    };

    var STAR_DOT_REGEXP = /^[*][.]/;
    var SORRY_COMMA_REGEXP = /sorry,/i;

    // -----------------------
    //  State Variables
    // -----------------------
    var FQDN_TO_CREATED_DOMAIN = {};
    var errorNotice;
    var validators = {};
    var formProgressOverlay;
    var sslResultsPanel;
    var hiddenWhiteSpaceListTemplate;
    var pageHasDomainSelector = false;    // True in cPanel, false in WHM.
    var lastCaughtFocus = null;  // The variable that catchNextFocus() sets.
    var pageProgressPanel;
    var certificatesDataTable = null;  // This is the certificate DataTable shared by changeUserComplete() and searchOk()
    var current_user = null;
    var current_browse_source = nvdata.browse_source || "user";
    var dialogEventsSetup = false;
    var installMessageMaker;
    var ipSelectorItemTemplate;
    var wildcard_subdomain_warning;


    /**
      * Request a list of the certificates.
      * @public
      * @method browsessl
      * @param {object} clicked_el The element from which to expand the progress panel
      * @static
      */
    function browsessl(clicked_el) {
        clearErrorNotice();

        pageProgressPanel = new CPANEL.ajax.Progress_Panel( null, {
            zIndex: 2000,   // to be above CJT validation message overlays
            effect: CPANEL.ajax.FADE_MODAL
        } );

        if (clicked_el) {
            pageProgressPanel.show_from_source(clicked_el);
        } else {
            pageProgressPanel.show();
        }

        pageProgressPanel.after_hideEvent.subscribe( pageProgressPanel.destroy, pageProgressPanel, true );

        var api_call;
        if (CPANEL.is_whm()) {
            if ( current_browse_source === "user" ) {

                // Select the last selected user again
                // so we retain context.
                api_call = {
                    func: "listcrts",
                    data: { user: current_user }
                };
            } else {
                api_call = {
                    func: "fetch_ssl_vhosts"
                };
            }
        } else {
            api_call = {
                version: 3,
                module: "SSL",
                func: "list_certs",
                api_data: {
                    filter: [ [ "domain_is_configured", "eq", 1 ] ]
                }
            };
        }

        api_call.callback = {
            success: searchOk,
            failure: searchFailure
        };

        CPANEL.api(api_call);
    }


    /**
    * Transform a a domain list into a list of simple structures
    * that inform the template whether to make the domain a link.
    */
    var installSuccessDomainListXform = function(d) {
        return { domain: d, makeLink: !/^[*]/.test(d) };
    };


    /**
      * Sends the form data off to do the SSL install for Apache.
      *
      * @method sendApacheInstall
      * @param {String|Object} form The form, or its ID.
      */
    function sendApacheInstall(form) {
        form = DOM.get(form);

        var formdata = CPANEL.dom.get_data_from_form(form);

        // No need to catch exceptions here since validation has already run.
        var certParse = CPANEL.ssl.parseCertificateText(formdata.crt);

        var progress = new CPANEL.ajax.Progress_Panel( null, {
            show_status: true,
            status_html: LOCALE.maketext("Installing …")
        } );
        progress.show_from_source(form);

        progress.after_hideEvent.subscribe( progress.destroy, progress, true );


        /**
        * What to do with an "OK" click when the page is to reload.
        */
        var reload_button_handler = function(e) {
            var this_button = this.getButtons()[0];
            this_button.disabled = true;

            if (document.activeElement === this_button) {
                this_button.blur();
            }

            // Strip out a query from the URL, and reload.
            window.location.href = window.location.pathname;
        };


        /**
        * What to do with an "OK" click when the page doesn't reload.
        */
        var non_reload_button_handler = function(e) {
            this.cancel();
        };


        /**
        * What to call when the install API call returns successfully.
        */
        var onsuccess = function(o) {
            var ip = o.cpanel_data.ip || o.argument && o.argument.ip;

            var tData = {};

            if ( o.cpanel_data.working_domains ) {
                tData.workingDomains = o.cpanel_data.working_domains.map(installSuccessDomainListXform);
                tData.workingDomainsMessage = LOCALE.maketext("The SSL website is now active and accessible via HTTPS on [numerate,_1,this domain,these domains]:", tData.workingDomains.length);
            }

            if ( o.cpanel_data.warning_domains && o.cpanel_data.warning_domains.length ) {
                tData.warningDomains = o.cpanel_data.warning_domains.map(installSuccessDomainListXform);
                tData.warningDomainsMessage = LOCALE.maketext("The SSL website is also accessible via [numerate,_1,this domain,these domains], but the certificate does not support [numerate,_1,it,them]. Web browsers will show a warning when accessing [numerate,_1,this domain,these domains] via HTTPS:", tData.warningDomains.length);
            }

            if ( o.cpanel_data.extra_certificate_domains && o.cpanel_data.extra_certificate_domains.length ) {
                tData.extraCertificateDomains = o.cpanel_data.extra_certificate_domains.map( function(d) {
                    return { domain: d };
                } );
                tData.extraCertificateDomainsMessage = LOCALE.maketext("The SSL certificate also supports [numerate,_1,this domain,these domains], but [numerate,_1,this domain does,these domains do] not refer to the SSL website mentioned above:", tData.extraCertificateDomains.length);
            }

            var okHandler, messageTemplate;
            switch ( o.cpanel_data.action ) {
                case "install":
                    tData.statusMessageHTML = LOCALE.maketext("You have successfully configured SSL.");
                    okHandler = reload_button_handler;
                    tData.needReload = true;
                    break;
                case "update":
                    tData.statusMessageHTML = LOCALE.maketext("You have successfully updated the SSL website’s certificate.");
                    okHandler = reload_button_handler;
                    tData.needReload = true;
                    break;
                case "none":
                    tData.statusMessageHTML = LOCALE.maketext("This SSL certificate was already installed.");
                    okHandler = non_reload_button_handler;
            }

            if (!messageTemplate) {
                messageTemplate = DOM.get("installSuccessTemplate").text;
            }

            if ( !installMessageMaker ) {
                installMessageMaker = Handlebars.compile( messageTemplate );
            }
            var message = installMessageMaker( tData );

            var dialog = new CPANEL.ajax.Common_Dialog( null, {
                effect: CPANEL.ajax.FADE_MODAL,
                buttons: [
                    {
                        text: LOCALE.maketext("OK"),
                        isDefault: true,
                        handler: okHandler
                    }
                ]
            } );
            var header_text;
            if (o.cpanel_data.action === "update") {
                header_text = LOCALE.maketext("SSL Certificate Successfully Updated");
            } else {
                header_text = LOCALE.maketext("SSL Host Successfully Installed");
            }
            dialog.setHeader( CPANEL.widgets.Dialog.applyDialogHeader(header_text) );
            dialog.beforeShowEvent.subscribe( function() {
                dialog.form.innerHTML = message;
                dialog.center();
            } );

            progress.fade_to(dialog);
        };

        var apicall;
        if ( CPANEL.is_cpanel() ) {
            apicall = {
                version: 3,
                module: "SSL",
                func: "install_ssl",
                data: {
                    domain: formdata.domain,
                    cert: formdata.crt,
                    key: formdata.key,
                    cabundle: formdata.cabundle,
                }
            };
        } else {
            apicall = {
                func: "installssl",
                data: {
                    domain: formdata.domain,
                    ip: formdata.ip,
                    crt: formdata.crt,
                    key: formdata.key,
                    cab: formdata.cabundle,
                }
            };
        }

        apicall.callback = CPANEL.ajax.build_page_callback( onsuccess, {
            on_error: function() {
                progress.hide();
            }
        } );
        apicall.callback.argument = { ip: formdata.ip, domain: formdata.domain };

        CPANEL.api(apicall);
    }


    /**
      * Fetches the selected certificate from the dialog box.
      * @method handleBeforeSubmit
      * @param {String} type The CustomEvent type
      * @param {Object[]} args The CustomEvent arguments
      * @param {Object} obj The scope object
      * @static
      */
    function handleBeforeSubmit(type, args, obj) {
        var selected = certificatesDataTable.getSelectedRows()[0];
        var record = certificatesDataTable.getRecord(selected);

        if ( current_browse_source === "user" ) {
            fetchByCertId( record.getData("id"), current_user );
        } else {
            _populateFormByVhost( record.getData("servername") );
        }
    }

    /**
    * Fire off an async call that should eventually populate the form with
    * the indicated SSL vhost's SSL components.
    *
    * @method _populateFormByVhost
    * @private
    * @param servername {String} The servername of the vhost whose information to load.
    */
    function _populateFormByVhost( servername ) {
        CPANEL.sharedjs.sslinstall.showFormProgressOverlay();

        CPANEL.api( {
            func: "fetch_vhost_ssl_components",
            api_data: {
                filter: [ ["servername", "eq", servername] ]
            },
            callback: CPANEL.ajax.build_page_callback(
                populate_form_with_ssl_components,
                {
                    on_error: CPANEL.sharedjs.sslinstall.hideFormProgressOverlay
                }
            )
        }
        );
    }

    /**
    * Schlep the results of an AJAX call into the form.
    * This assumes that the passed-in object is for an API call that returns:
    * [
    *   { certificate:"..", key:"..", cabundle:".." }
    * ]
    *
    * @method populate_form_with_ssl_components
    * @param o {Object} An API response object, as described.
    */
    var populate_form_with_ssl_components = function(o) {
        var payload = o.cpanel_data[0];

        var mainform = DOM.get("mainform");

        mainform.crt.value = payload.certificate;
        mainform.key.value = payload.key;
        mainform.cabundle.value = payload.cabundle || "";

        try {
            _populate_domain_from_parsed_cert(CPANEL.ssl.parseCertificateText( payload.certificate ));
        } catch (e) {}

        CPANEL.sharedjs.sslinstall.hideFormProgressOverlay();

        CPANEL.sharedjs.sslinstall.runValidation();
        CPANEL.sharedjs.sslinstall.updateUI();
    };

    /**
     * Formatter that injects hidden whitespace after a period
     * in a string
     * @param  {Object} elCell  DOM object for the cell.
     * @param  {Object} oRecord Record for this row.
     * @param  {Object} oColumn Column definition for this cell.
     * @param  {Object} oData   Data for the specific cell.
     */
    var injectHiddenWhiteSpace = function(elCell, oRecord, oColumn, oData) {
        if (LANG.isValue(oData)) {
            elCell.innerHTML = oData.html_encode().replace(/\./g, ".<wbr><a class=\"wbr\"></a>");
            elCell.title = oData;
        }
    };


    /**
     * Formatter that injects hidden whitespace after a period
     * in a string
     * @param  {Object} elCell  DOM object for the cell.
     * @param  {Object} oRecord Record for this row.
     * @param  {Object} oColumn Column definition for this cell.
     * @param  {Object} oData   Data for the specific cell.
     */
    var injectHiddenWhiteSpaceList = function(elCell, oRecord, oColumn, oData) {
        if (oData && oData.length) {
            var array = oData;
            var data = [];
            for (var i = 0, l = array.length; i < l; i++) {
                var tmp = array[i].html_encode();
                var item = {
                    title: tmp,
                    value: tmp.replace(/\./g, ".<wbr><a class=\"wbr\"></a>")
                };
                data.push(item);
            }

            // Process the template
            elCell.innerHTML = hiddenWhiteSpaceListTemplate( { data: data });
        }
    };


    /**
     * Formatter that correctly formats date to be
     * international compliant in the users selected language.
     * @param  {Object} elCell  DOM object for the cell.
     * @param  {Object} oRecord Record for this row.
     * @param  {Object} oColumn Column definition for this cell.
     * @param  {Object} oData   Data for the specific cell.
     */
    var formatLocaleDate = function(elCell, oRecord, oColumn, oData) {
        if (LANG.isValue(oData)) {
            elCell.innerHTML = LOCALE.datetime( oData, "date_format_short" );
            elCell.title = LOCALE.datetime( oData, "datetime_format_long" );
        }
    };


    /**
     * Formatter that shows either the issuer or Self-Signed.
     * @param  {Object} elCell  DOM object for the cell.
     * @param  {Object} oRecord Record for this row.
     * @param  {Object} oColumn Column definition for this cell.
     * @param  {Object} oData   Data for the specific cell.
     */
    var formatIssuer = function(elCell, oRecord, oColumn, oData) {
        if (oRecord && oRecord.getData("is_self_signed")) {
            elCell.innerHTML = LOCALE.maketext("Self-Signed");
        } else {
            injectHiddenWhiteSpace.apply(this, arguments);
        }
    };


    /**
     * Formats INPUT TYPE=RADIO elements.
     *
     * @method formatRadio
     * @param el {HTMLElement} The element to format with markup.
     * @param oRecord {YAHOO.widget.Record} Record instance.
     * @param oColumn {YAHOO.widget.Column} Column instance.
     * @param oData {Object} (Optional) Data value for the cell.
     * @param oDataTable {YAHOO.widget.DataTable} DataTable instance.
     * @static
     */
    var formatRadio = function(el, oRecord, oColumn, oData) {
        var value = oData + "";
        el.innerHTML = "<input type=\"radio\"" +
                " name=\"selected-cert\"" +
                " class=\"" + YAHOO.widget.DataTable.CLASS_RADIO + "\"" +
                " value=\"" + value.html_encode() + "\" />";
    };


    /**
     * Converts data to type Date from a linux timestamp.
     * @method parseLinuxTimeStamp
     * @param oData {Date | String | Number} Data to convert.
     * @return {Date} A Date instance.
     */
    var parseLinuxTimeStamp = function(oData) {
        var date = null;

        // Convert to date
        if (LANG.isValue(oData) && !(oData instanceof Date)) {
            date = new Date(parseInt(oData * 1000, 10));
        } else {
            return oData;
        }

        // Validate
        if (date instanceof Date) {
            return date;
        } else {
            YAHOO.log("Could not convert data " + LANG.dump(oData) + " to type Date", "warn", this.toString());
            return null;
        }
    };


    /**
     * Converts data to type Boolean from perl boolean.
     * @method parsePerlBoolean
     * @param oData {Date | String | Number} Data to convert.
     * @return {Boolean} A Boolean instance.
     */
    var parsePerlBoolean = function(oData) {
        var value = null;

        // Convert to boolean
        if (LANG.isValue(oData) && (typeof oData !== "boolean")) {
            if (oData && (parseInt(oData, 10) === 1)) {
                value = true;
            } else {
                value = false;
            }
        } else {
            return oData;
        }

        // Validate
        if (typeof value === "boolean") {
            return value;
        } else {
            YAHOO.log("Could not convert data " + LANG.dump(oData) + " to type Date", "warn", this.toString());
            return null;
        }
    };


    /**
     * Utility method for sorting DataTable by the issuer.
     * This sorts self-signed certs "greater".
     * @method sortIssuer
     * @param a {Record} The first Record to compare.
     * @param b {Record} The second Record to compare.
     * @param desc {Boolean} Whether the sort is a descending sort or not.
     * @return {Number} -1 if a is first, 1 if a is second, 0 if the same
     */
    var sortIssuer = function(a, b, desc) {
        var a_is_self_signed = a.getData("is_self_signed");
        var b_is_self_signed = b.getData("is_self_signed");

        if (a_is_self_signed) {
            if (b_is_self_signed) {
                return 0;
            }
            return desc ? -1 : 1;
        } else if (b_is_self_signed) {
            return desc ? 1 : -1;
        }

        return YAHOO.util.Sort.compare( a.getData("issuer.organizationName"), b.getData("issuer.organizationName"), desc );
    };


    /**
     * Utility method for sorting DataTable by the domains lists.
     * @method sortDomains
     * @param a {Record} The first Record to compare.
     * @param b {Record} The second Record to compare.
     * @param desc {Boolean} Whether the sort is a descending sort or not.
     * @return {Number} -1 if a is first, 1 if a is second, 0 if the same
     */
    var sortDomains = function(a, b, desc) {
        return YAHOO.util.Sort.compare( a.getData("domains").join("\n"), b.getData("domains").join("\n"), desc );
    };


    // Setup the schema definitions for the data source
    var certResponseSchema = {
        fields: [
            "id",
            "domain",
            "issuer.organizationName",
            { key: "not_after", parser: parseLinuxTimeStamp },
            "friendly_name",    // for browsing user
            "servername",       // for browsing apache
            "domains",
            { key: "is_self_signed", parser: parsePerlBoolean }
        ]
    };

    var certColumnDefs = [
        {
            key: "id",
            label: "",
            formatter: formatRadio,
            sortable: false,
            abbr: LOCALE.maketext("Select a certificate below:")
        },
        {
            key: "domains",
            maxAutoWidth: MAX_COLUMN_WIDTH.user,
            label: LOCALE.maketext("Domains"),
            formatter: injectHiddenWhiteSpaceList,
            sortable: true,
            sortOptions: { sortFunction: sortDomains },
            abbr: LOCALE.maketext("Domain names on the certificate.")
        },
        {
            key: "issuer.organizationName",
            maxAutoWidth: MAX_COLUMN_WIDTH.user,
            label: LOCALE.maketext("Issuer"),
            formatter: formatIssuer,
            sortable: true,
            sortOptions: { sortFunction: sortIssuer },
            abbr: LOCALE.maketext("Issuer organization name.")
        },
        {
            key: "not_after",
            label: LOCALE.maketext("Expiration"),
            formatter: formatLocaleDate,
            sortable: true,
            abbr: LOCALE.maketext("The certificate’s expiration date")
        },
        {
            key: "friendly_name",
            maxAutoWidth: MAX_COLUMN_WIDTH.user,
            label: LOCALE.maketext("Description"),
            formatter: injectHiddenWhiteSpace,
            sortable: true,
            abbr: LOCALE.maketext("A user-defined description for the certificate.")
        }
    ];

    /**
      * Handle things that always happen when the change-user AJAX call returns,
      * regardless of success or failure.
      * @method _changeUserOnReturn
      * @param o {Object} CPANEL.api response object
      * @static
      */
    function _changeUserOnReturn(o) {
        var users = DOM.get("users");
        if ( o.argument && (o.argument.oldActiveElement === users) && !lastCaughtFocus ) {
            users.focus();
        }
    }

    /**
      * Handle the case where the user context change triggered
      *  listcrts request succeeds.
      * @method changeUserComplete
      * @param o {Object} CPANEL.api response object
      * @static
      */
    function changeUserComplete(o) {
        _changeUserOnReturn(o);

        _set_column_widths_for_browse_source("user");

        certificatesDataTable.showColumn("friendly_name");

        _update_cert_browser_table_with_new_certs(o.cpanel_data);

        // Update the current user
        current_user = o.argument.user;
    }

    function _set_column_widths_for_browse_source(browse_source) {
        var colset = certificatesDataTable.getColumnSet();
        for (var c = 0; c < colset.flat.length; c++) {
            colset.flat[c].maxAutoWidth = MAX_COLUMN_WIDTH[browse_source];
        }
    }

    // WHM "fetch_ssl_vhosts" returns data in a format that doesn't quite jive
    // with what the cert browser here expects, so this function massages that
    // data to play nicely with the cert browser table.
    function _format_fetch_ssl_vhosts_for_cert_browser(vhosts) {

        var with_cert = vhosts.filter(function(v) {
            return v.crt;
        });

        // Grab "servername" from the "crt" hash.
        var crts = with_cert.map( function(v) {
            v.crt.servername = v.servername;
            return v.crt;
        } );

        // Make sure we show each cert only once.
        var certs_already_seen = {};
        crts = crts.filter( function(c) {
            if ( certs_already_seen[c.id] ) {
                return false;
            }

            certs_already_seen[c.id] = true;
            return true;
        } );

        return crts;
    }

    function loadApacheCertsComplete(o) {

        certificatesDataTable.hideColumn("friendly_name");

        _set_column_widths_for_browse_source("apache");

        var crts = _format_fetch_ssl_vhosts_for_cert_browser( o.cpanel_data );

        _update_cert_browser_table_with_new_certs(crts);
    }

    function _update_cert_browser_table_with_new_certs(crts) {
        _enable_cert_browser_controls();

        // Hide the table message
        certificatesDataTable.hideTableMessage();

        var certDataSource = new YAHOO.util.LocalDataSource(crts);
        certDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
        certDataSource.responseSchema = certResponseSchema;

        certificatesDataTable.load( { datasource: certDataSource } );

        var state = certificatesDataTable.getState();
        if ( state.sortedBy ) {
            certificatesDataTable.sortColumn(
                certificatesDataTable.getColumn( state.sortedBy.key ),
                state.sortedBy.dir
            );
        }

        certificatesDataTable.selectRow(0);
    }

    /**
     * Handle the case where loading new certs fails during the API call.
     * This works for both user and Apache cert browsing.
     *
     * @method chageUserFailed
     * @param  {Object} o Error object.
     * @static
     */
    function loadNewCertsFailed(o) {

        _changeUserOnReturn(o);

        var postRenderOnFail = function() {
            certificatesDataTable.unsubscribe("postRenderEvent", postRenderOnFail);

            // Show an error
            certificatesDataTable.showTableMessage(
                LOCALE.maketext("The certificate list could not be retrieved because of an error: [_1]", o.cpanel_error.html_encode()),
                YAHOO.widget.DataTable.CLASS_ERROR);
        };

        certificatesDataTable.subscribe("postRenderEvent", postRenderOnFail);

        // Remove all the rows
        var length = certificatesDataTable.getRecordSet().getLength();
        if (length > 0) {
            certificatesDataTable.deleteRows(0, length);

            // postRenderOnFail is triggered after the delete completes.
        } else {

            // No records to delete, so call synchronously
            postRenderOnFail();
        }
    }


    /**
      * Set a body listener that catches the next focus event.
      * When it catches one, it sets the "lastCaughtFocus" variable.
      * This is useful for re-focusing an element that you've disabled
      * for an AJAX call, but only doing so if the user hasn’t focused
      * something else in the meantime.
      *
      * TODO: Make this a class that tracks lastCaughtFocus internally.
      *
      * @method catchNextFocus
      * @static
      */
    function catchNextFocus() {
        lastCaughtFocus = null;

        var listener = function(e) {
            EVENT.removeListener( this, "focusin", listener );
            lastCaughtFocus = e;
        };

        EVENT.on( document.body, "focusin", listener );
    }


    /**
    * Convenience wrapper around YAHOO.util.Event.preventDefault()
    */
    var preventDefault = function(e) {
        EVENT.preventDefault(e);
    };

    /**
    * Handler for when the browse source changes.
    *
    * NOTE: Context object MUST be the clicked radio button.
    *
    * @method _onBrowseSourceChange
    * @private
    * @param e {Object} The event object from a YUI 2 DOM listener.
    */
    var _onBrowseSourceChange = function(e) {
        var clicked_el = this;

        current_browse_source = clicked_el.value;

        if ( current_browse_source === "user" ) {

            // Read this manually because get_data_from_form will reject values from
            // disabled form controls.
            var select = DOM.get("users");

            _update_cert_table_for_user( select[select.selectedIndex].value );
        } else {
            _update_cert_table_for_apache();
        }
    };


    /**
    * Handler for when the user in the cert browser popup changes.
    *
    * NOTE: Context object MUST be the user <select>.
    *
    * @method _onUserChange
    * @private
    * @param e {Object} The event object from a YUI 2 DOM listener.
    */
    var _onUserChange = function(e) {
        if (this.selectedIndex === -1) {
            return;
        }

        var new_user = this.options[this.selectedIndex].value;
        if ( new_user !== current_user ) {
            _update_cert_table_for_user(new_user);
        }
    };

    /**
    * Fire off an AJAX call that eventually will update the cert browser table.
    * This is for when we want to query Apache.
    *
    * @method _update_cert_table_for_apache
    * @private
    */
    var _update_cert_table_for_apache = function() {
        var what_to_do = function() {

            // Show the loading message
            certificatesDataTable.showTableMessage(
                LOCALE.maketext("Loading installed Apache certificates …"),
                YAHOO.widget.DataTable.CLASS_LOADING);

            CPANEL.api( {
                func: "fetch_ssl_vhosts",
                callback: {
                    success: loadApacheCertsComplete,
                    failure: loadNewCertsFailed
                }
            } );
        };

        _update_cert_table(what_to_do);
    };

    /**
    * Query the DOM to return the cert browser controls.
    *
    * @method _get_cert_browser_controls
    * @private
    */
    var _get_cert_browser_controls = function() {
        return CPANEL.Y.all("input[name=browse_source], select#users");
    };

    /**
    * Enable or disable the cert browser controls as needed.
    * This is smart enough not to enable the user drop-down when we're
    * browsing Apache.
    *
    * @method _get_cert_browser_controls
    * @private
    */
    var _set_cert_browser_controls_disabled = function(to_disable) {
        _get_cert_browser_controls().forEach( function(el) {

            // Ensure that we don't enable the user selector when we're
            // browsing Apache's certificates.
            if ( to_disable || (current_browse_source === "user") || (el !== DOM.get("users")) ) {
                el.disabled = to_disable;
            }
        } );
    };

    /**
    * Enable the cert browser controls.
    *
    * @method _get_cert_browser_controls
    * @private
    */
    var _enable_cert_browser_controls = function() {
        _set_cert_browser_controls_disabled(false);
    };

    /**
    * Disable the cert browser controls.
    *
    * @method _get_cert_browser_controls
    * @private
    */
    var _disable_cert_browser_controls = function() {
        _set_cert_browser_controls_disabled(true);
    };

    /**
    * Fire off an AJAX call that eventually will update the cert browser table.
    * This is code common to both Apache and user-sslstorage browsing.
    *
    * @method _update_cert_table_for_apache
    * @private
    */
    var _update_cert_table = function(what_to_do_after_clearing_table) {
        _disable_cert_browser_controls();

        // For update_cert_table_for_user. Put it here in case some browser
        // fires "focus" when you disable the activeElement.
        catchNextFocus();

        var postRender = function() {
            certificatesDataTable.unsubscribe("postRenderEvent", postRender);
            return what_to_do_after_clearing_table.apply(this, arguments);
        };

        // Remove all the rows
        var length = certificatesDataTable.getRecordSet().getLength();
        if (length > 0) {
            certificatesDataTable.subscribe("postRenderEvent", postRender);
            certificatesDataTable.deleteRows(0, length);

            // postRender is triggered after the delete completes.
        } else {

            // No records to delete, so call synchronously
            postRender();
        }
    };

    /**
    * Fire off an AJAX call that eventually will update the cert browser table.
    * This is for when we want to query a user's datastore.
    *
    * @method _update_cert_table_for_user
    * @private
    */
    var _update_cert_table_for_user = function(new_user) {

        // If the users drop-down is focused,
        // then we want to restore that focused state when the
        // AJAX call returns, unless the user has focused
        // something else in the meantime.
        var oldActiveElement = document.activeElement;

        /**
        * What to do immediately after the cert datatable is done rendering.
        */
        var postRender = function() {

            // Show the loading message
            certificatesDataTable.showTableMessage(
                LOCALE.maketext("Loading certificates for “[output,strong,_1]” …", new_user),
                YAHOO.widget.DataTable.CLASS_LOADING);

            CPANEL.api( {
                func: "listcrts",
                data: { user: new_user },
                callback: {
                    success: changeUserComplete,
                    failure: loadNewCertsFailed,
                    argument: {
                        user: new_user,
                        oldActiveElement: oldActiveElement
                    }
                }
            } );
        };

        _update_cert_table(postRender);
    };


    /**
      * Handle the case where the listcrts request fails.
      *
      * @method searchFailure
      * @param o {Object} CPANEL.api response object
      * @static
      */
    function searchFailure(o) {
        showErrorNotice( LOCALE.maketext("The certificate list could not be retrieved because of an error: [_1]", o.cpanel_error.html_encode()));
    }


    /**
      * Handle the case where the listcrts request succeeds.
      * @method searchOk
      * @param o {Object} CPANEL.api response object
      * @static
      */
    function searchOk(o) {

        /**
        * The handler for when the SSL cert browser is shown.
        * This event needs to be setup every time the API returns since it
        * changes the table's data.
        */
        var beforeShowResultsPanel = function() {
            sslResultsPanel.beforeShowEvent.unsubscribe(beforeShowResultsPanel);

            // Add to prevent the parent window from scrolling when
            // the popup is scrolling past its top or bottom.
            EVENT.addListener(document.body, "scroll", preventDefault);

            _enable_cert_browser_controls();

            // Set the current user (in WHM)
            if (DOM.get("users")) {
                var users = DOM.get("users");
                CPANEL.dom.set_form_el_value(users, current_user);
            }

            // For Apache certs, we process below
            var crts = o.cpanel_data;

            if ( CPANEL.is_cpanel() && PAGE && PAGE.data ) {
                var c;  // silly jshint

                var installable_domains = PAGE.data.installable_domains;

                // TODO: Implement this using YUI 3's array extras?
                for (c = crts.length - 1; c >= 0; c--) {
                    var l = installable_domains.length;
                    var cert_matches_at_least_one_account_domain = false;
                    for ( var i = 0; i < l; i++ ) {
                        if ( CPANEL.ssl.doesDomainMatchOneOf( installable_domains[i], crts[c].domains ) ) {
                            cert_matches_at_least_one_account_domain = true;
                            break;
                        }
                    }

                    if (!cert_matches_at_least_one_account_domain) {
                        crts.splice(c, 1);
                    }
                }
            } else if ( current_browse_source === "apache" ) {
                crts = _format_fetch_ssl_vhosts_for_cert_browser(crts);

                // We set maxAutoWidth to MAX_COLUMN_WIDTH.user in the column
                // definitions. If case the table's first view is with Apache
                // certs instead, switch maxAutoWidth here to what it needs to be.
                for (var cd = 0; cd < certColumnDefs.length; cd++) {
                    certColumnDefs[cd].maxAutoWidth = MAX_COLUMN_WIDTH.apache;

                    if (certColumnDefs[cd].key === "friendly_name") {
                        certColumnDefs[cd].hidden = true;
                    }
                }
            }

            // Setup the data-source for the data table
            var certDataSource = new YAHOO.util.LocalDataSource(crts);
            certDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
            certDataSource.responseSchema = certResponseSchema;

            // Setup the scrolling data table.
            var list = DOM.get("certlist");
            if (list) {
                certificatesDataTable = new YAHOO.widget.ScrollingDataTable(
                    "certlist",
                    certColumnDefs,
                    certDataSource,
                    {
                        height: "250px",
                        className: "sortable",
                        MSG_EMPTY: LOCALE.maketext("This account does not have any installable certificates.")
                    }
                );

                // Do the sort on the client since the API,
                // as of early 2013, doesn't know how to sort arrays.
                // NOTE: This doesn't work if you put it in the instantiation config
                // since that just tells DataTable how the data is *already* sorted.
                certificatesDataTable.sortColumn(
                    certificatesDataTable.getColumn(certificates_table_sort.key),
                    certificates_table_sort.dir || YAHOO.widget.DataTable.CLASS_ASC
                );

                certificatesDataTable.set("selectionMode", "single");

                certificatesDataTable.subscribe("theadCellClickEvent", function(e) {

                    // This fixes an issue with selected and sorting.
                    if (selectedRecord) {
                        this.unselectAllRows();
                        actionSource = "sort";
                        this.selectRow(selectedRecord);
                    }
                });

                certificatesDataTable.subscribe( "columnSortEvent", function(oArgs) {
                    var the_sort = this.get("sortedBy");
                    certificates_table_sort = {
                        dir: the_sort.dir,
                        key: the_sort.key
                    };
                    CPANEL.nvdata.save();
                } );

                // Capture the source for the select even, we are trying
                // to screen out the ones that are from mouse based actions.
                var actionSource = null;
                var selectedRow = null;
                var selectedRecord = null;

                certificatesDataTable.subscribe("radioClickEvent", function(e) {
                    var radio = e.target;
                    if (radio.checked) {
                        this.unselectAllRows();

                        var row = this.getTrEl(radio);
                        actionSource = "radio";
                        this.selectRow(row);
                    }
                });

                certificatesDataTable.subscribe("rowSelectEvent", function(e) {

                    // Prevent text selection as recommended in datatable
                    this.clearTextSelection();

                    // We only get here for up and down arrow keys
                    var row = e.el;
                    var targetRecord = this.getRecord(row);

                    selectedRecord = targetRecord;

                    // Select the radio button.
                    CPANEL.Y(row).one("input.yui-dt-radio").checked = true;

                    if (actionSource !== null) {
                        selectedRow = row;

                        // Not a keyboard event so reset it and return.
                        actionSource = null;
                        return;
                    }

                    // Scroll as needed
                    var parentContainer = row.offsetParent.parentNode;
                    var regionParent = REGION.getRegion(parentContainer);
                    var regionRow = REGION.getRegion(row);
                    var regionIntersect = regionRow.intersect(regionParent);
                    if (regionIntersect === null ||
                        regionIntersect.getArea() === 0 ||
                        regionIntersect.height < regionRow.height) {

                        // NOTE: There is still a little issue here, but this is
                        // usable. If you scroll the selected item off the screen
                        // then try to use the keyboard to scroll selection, it doesn't
                        // correctly move the selected item into view.

                        // regionIntersect.getArea() === 0 means no overlap
                        // regionIntersect.height < regionRow.height mean partial overlap

                        // Calculate the fudge for partial overlaps
                        var deltaHeight = regionIntersect ? regionIntersect.height : 0;

                        // Determine if we need to scroll to top or scroll to bottom
                        // depending of in we are scrolling up or down.
                        var nextRow = this.getNextTrEl(row);
                        var scrollingUp = selectedRow === nextRow;
                        if (scrollingUp) {
                            parentContainer.scrollTop -= regionRow.height + deltaHeight;
                        } else {
                            parentContainer.scrollTop += regionRow.height + deltaHeight;
                        }
                    }

                    // Update the state variable used to track the previous row.
                    selectedRow = row;
                });

                certificatesDataTable.subscribe("rowDblclickEvent", function(e) {

                    // Prevent text selection as recommended in datatable
                    this.clearTextSelection();

                    EVENT.preventDefault(e);
                    var row = DOM.get(e.target);
                    this.getRecord(row);
                    sslResultsPanel.submit();
                });

                certificatesDataTable.subscribe("rowClickEvent", function(e) {
                    EVENT.preventDefault(e);
                    this.unselectAllRows();

                    var row = DOM.get(e.target);
                    actionSource = "click";
                    this.selectRow(row);
                });

                certificatesDataTable.subscribe("postRenderEvent", function(e) {
                    sslResultsPanel.center();
                });

                certificatesDataTable.selectRow(0);

            }
        };

        if (!dialogEventsSetup) {
            sslResultsPanel.beforeHideEvent.subscribe(function() {

                // Restore normal parent window scrolling behavior.
                EVENT.removeListener(document.body, "scroll", preventDefault);

                // Release the table for garbage collection since
                // we will just recreate it on each show.
                certificatesDataTable.destroy();
                certificatesDataTable = null;
            });

            dialogEventsSetup = true;
        }

        sslResultsPanel.beforeShowEvent.subscribe(beforeShowResultsPanel);

        // Show the popup
        pageProgressPanel.fade_to(sslResultsPanel);
    }


    /**
      * Clears the notice area.
      * @method clearErrorNotice
      * @static
      */
    function clearErrorNotice() {
        if (errorNotice && errorNotice.cfg) {
            errorNotice.hide();
            errorNotice.destroy();
            errorNotice = null;
        }
    }


    /**
      * Shows an error message
      * @method showErrorNotice
      * @param text {String} Error message text.
      * @param extraText {String} Text to add to the collapsible section.
      * @param extraOpenLabel {String} Open collapsable section label.
      * @param extraCloseLabel {String} Close collapsable section label.
      * @static
      */
    function showErrorNotice(text, extraText, extraOpenLabel, extraCloseLabel) {

        if (formProgressOverlay && formProgressOverlay.cfg) {
            formProgressOverlay.hide();
        }
        if (pageProgressPanel && pageProgressPanel.cfg) {
            pageProgressPanel.hide();
        }

        var BUTTON_PREFIX = "en_btn_";
        var AREA_PREFIX = "en_area_";
        var buttonId, areaId;

        var elID = DOM.generateId();

        if (extraText) {
            extraOpenLabel = extraOpenLabel || LOCALE.maketext("Show");
            extraCloseLabel = extraCloseLabel || LOCALE.maketext("Hide");
            buttonId = BUTTON_PREFIX + elID;
            areaId = AREA_PREFIX + elID;

            text += YAHOO.lang.substitute(DOM.get("error-extra-block").text, {
                "btnId": buttonId,
                "areaId": areaId,
                "label": extraOpenLabel,
                "content": extraText.html_encode()
            });
        }

        errorNotice = new CPANEL.widgets.Dynamic_Page_Notice({
            level: "error",
            content: text,
            visible: false
        });

        if (extraText) {

            // Setup the events just before we show the notice
            errorNotice.beforeShowEvent.subscribe(function(e) {
                var theButtonId = buttonId;
                var btn = DOM.get(theButtonId);

                // Setup the toggle event handler
                EVENT.on(btn, "click", function(e) {
                    var el = DOM.get(areaId);

                    if (DOM.getStyle(el, "display") === "none") {
                        DOM.setStyle(el, "display", "");
                        this.innerHTML = extraCloseLabel;
                    } else {
                        DOM.setStyle(el, "display", "none");
                        this.innerHTML = extraOpenLabel;
                    }

                    errorNotice = null;
                });
            });
        }

        errorNotice.show();

        errorNotice.hideEvent.subscribe( function() {
            CPANEL.align_panels_event.fire();
        } );

        CPANEL.align_panels_event.fire();
    }

    /**
      * Set a Page_Progress_Overlay as an AJAX status indicator.
      *
      * @method showFormProgressOverlay
      * @static
      */
    function showFormProgressOverlay(content_html) {
        if ( !formProgressOverlay || !formProgressOverlay.cfg ) {
            formProgressOverlay = new CPANEL.ajax.Page_Progress_Overlay( null, {
                zIndex: 2000,   // to be above CJT validation message overlays
                covers: DOM.get("mainform"),
                show_status: !!content_html,
                status_html: content_html
            } );
        } else {
            formProgressOverlay.set_status_now(content_html);
        }

        formProgressOverlay.show();
    }

    /**
      * Hide the Page_Progress_Overlay AJAX status indicator.
      *
      * @method hideFormProgressOverlay
      * @static
      */
    function hideFormProgressOverlay(content_html) {
        formProgressOverlay.hide();
    }

    /**
      * Validate the domain, allowing wildcards through.
      *
      * @method  validateDomain
      * @return {Boolean}
      */
    var validateDomain = function(el) {
        var val = ( typeof el === "object" ) ? el.value : el;
        val = val.trim();

        return !val || CPANEL.validate.host(val.replace(/^\*\./, ""));
    };

    /**
      * Validate that there is at least one service selected.
      *
      * @method _validate_services_selected
      * @private
      * @return {Boolean}
      */
    function _validate_services_selected() {
        return !!CPANEL.dom.get_data_from_form("mainform").service;
    }


    /**
      * Validate the IP, allowing wildcards through.
      * NOTE: This only works for WHM. In cPanel, there is no need to check an IP.
      *
      * @method  validateIP
      * @return {Boolean}
      */
    var validateIP = function(el) {
        return !validateIP_fail_reason(el) ? true : false;
    };


    /**
      * Give a reason, if any, why the IP is invalid.
      * Returns the empty string otherwise.
      *
      * @method  validateIP_for_domain_fail_reason
      * @return {String}
      */
    var validateIP_fail_reason = function(el) {
        var val = ( typeof el === "object" ) ? el.value : el;

        if (val.length) {
            if ( !CPANEL.validate.ip(val) ) {
                return LOCALE.maketext("Enter a valid IP address.");
            }

            var sslips = PAGE.properties && PAGE.properties.sslips;
            if (sslips && !sslips[val]) {
                return LOCALE.maketext("The IP address “[_1]” is not available, or you do not have permission to use it.", val);
            }
        }

        return "";
    };


    /**
      * Validate the certificate.
      *
      * @method  validateCert
      * @return {Boolean}
      */
    var validateCert = function(el) {
        var val = el.value.trim();
        if (!val) {
            return true;  // Another validator handles empty-string.
        }

        try {
            return !!CPANEL.ssl.parseCertificateText(val);
        } catch (e) {
            return false;
        }

        return true;
    };


    /**
      * Validate the key.
      *
      * @method  validateKey
      * @return {Boolean}
      */
    var validateKey = function(el) {
        var val = el.value.trim();
        if (!val) {
            return true;  // Another validator handles empty-string.
        }

        var parse;
        try {
            parse = CPANEL.ssl.parseKeyText(val);
        } catch (e) {}

        return !!parse;
    };


    /**
      * Validate the CA bundle.
      *
      * @method validateCABundle
      * @return {Boolean}
      */
    var validateCABundle = function(el) {
        var val = el.value.trim();
        if (!val) {
            return true;
        }

        try {
            return !!CPANEL.ssl.parseCABundleText(val);
        } catch (e) {
            return false;
        }

        return true;
    };


    /**
      * Verify that one of these is true:
      *     a) The certificate is invalid.
      *     b) The domain is invalid.
      *     c) The selected domain and certificate match.
      *
      * @method validateDomainCertificateMatch
      * @param  {string} el The DOM element whose value is the certificate text.
      * @return {Boolean}
      */
    var validateDomainCertificateMatch = function(el) {
        var cert = el.value.trim();

        if (!cert) {
            return true;
        }

        var formData = CPANEL.dom.get_data_from_form("mainform");
        var domain = formData.domain;

        if ( !validateDomain(domain) ) {
            return true;
        }

        var all_fqdns = [domain];

        if (pageHasDomainSelector) {
            var alias_subdomains = PAGE.data.domain_aliases[domain] || [];

            all_fqdns = all_fqdns.concat( alias_subdomains.map(
                function(as) {
                    return as + "." + domain;
                }
            ) );
        }

        return all_fqdns.some( function(fqdn) {
            try {
                return CPANEL.ssl.validateCertificateForDomain( cert, fqdn );
            } catch (e) {
                return true;
            }
        } );
    };


    /**
      * Verify that one of these is true:
      *     a) The key is invalid.
      *     b) The certificate is invalid.
      *     c) The key and certificate match.
      * Return true for invalids to prevent validate.js from spooging the user
      * with extra warnings.
      *
      * @method  validateKeyCert
      * @return {Boolean}
      */
    var validateKeyCert = function(el) {
        var val = el.value.trim();
        if (!val) {
            return true;
        }

        try {
            var key_parse = CPANEL.ssl.parseKeyText(val);
            var cert_text = el.form.crt.value.trim();
            var cert_parse = CPANEL.ssl.parseCertificateText(cert_text);

            return cert_parse.modulus === key_parse.modulus;
        } catch (e) {
            return true;
        }
    };


    /**
      * Verify that one of these is true:
      *     a) The CA bundle is invalid.
      *     b) The certificate is invalid.
      *     c) The CA bundle and the certificate match.
      * Return true for invalids to prevent validate.js from spooging the user
      * with extra warnings.
      *
      * @method  validateCABundleCert
      * @return {Boolean}
      */
    var validateCABundleCert = function(el) {
        var cab = el.value.trim();
        if ( !cab ) {
            return true;
        }

        var cert = el.form.crt.value.trim();
        try {
            var cert_parse = CPANEL.ssl.parseCertificateText(cert);
            var cab_parse = CPANEL.ssl.parseCABundleText(cab);

            var cabLeafSubject = JSON.stringify(cab_parse.shift().subjectList);
            var certIssuer = JSON.stringify(cert_parse.issuerList);
            return cabLeafSubject === certIssuer;
        } catch (e) {
            return true;
        }
    };


    /**
      * HTML-escape a string and wrap it in <code>.
      *
      * @method wrapCode
      * @param {string} str The string to process.
      * @return {string} The processed string.
      */
    var wrapCode = function(str) {
        return "<code>" + str.html_encode() + "</code>";
    };


    /**
      * Same as updateUI, but builds in a very small delay for paste events.
      *
      * @param object A set of named parameters; can be:
      *     active_element: The element that "caused" the UI update.
      * @method delayed_updateUI
      */
    var delayed_updateUI = function(opts) {
        window.setTimeout( function() {
            updateUI(opts);
        }, 1 );
    };


    /**
      * Show parsed data and whatever warnings need be,
      * and update which of the "Fetch" buttons shows.
      * NOTE: This does NOT do validation; validate.js handles that separately.
      *
      * @param object A set of named parameters; can be:
      *     active_element: The element that "caused" the UI update. (Not for "services" ui_mode!)
      *     is_apns: Whether we’re parsing certs for APNS or not
      * @method updateUI
      */
    var updateUI = function(opts) {

        var certParse;

        var pageForm = DOM.get("mainform");
        var formData = CPANEL.dom.get_data_from_form(pageForm);
        var formDomain = formData.domain;
        var formCrt = formData.crt;

        try {
            certParse = CPANEL.ssl.parseCertificateText(formCrt);
        } catch (e) {}

        var shown = CPANEL.widgets.ssl.showCertificateParse(
            formCrt.trim(),
            "cert_parse",
            { is_apns: opts && opts.is_apns }
        );
        DOM.setStyle( "cert_parse", "display", shown ? "" : "none" );

        if ( DOM.get("fetch-cert") ) {
            DOM.get("fetch-cert").disabled = !certParse;
        }

        if ( DOM.get("fetch-domain") ) {
            DOM.get("fetch-domain").disabled = !validateDomain( formDomain );
        }

        if (opts && opts.active_element) {
            var domainFieldHasText = (formDomain && formDomain.trim()) ? 1 : 0;
            var crtFieldHasText = (formCrt && formCrt.trim()) ? 1 : 0;

            if ( (opts.active_element === "domain" && domainFieldHasText) ||
                 ( !crtFieldHasText && domainFieldHasText )
            ) {
                if ( DOM.getStyle("fetch-cert", "display") !== "none" ) {
                    CPANEL.animate.fade_out("fetch-cert");
                }
                if ( DOM.getStyle("fetch-domain", "display") === "none" ) {
                    CPANEL.animate.fade_in("fetch-domain");
                }
            } else if (certParse) {
                if ( (PAGE.ui_mode !== "services") && (DOM.getStyle("fetch-domain", "display") !== "none") ) {
                    CPANEL.animate.fade_out("fetch-domain");
                }
                if ( DOM.getStyle("fetch-cert", "display") === "none" ) {
                    CPANEL.animate.fade_in("fetch-cert");
                }
            }
        }

        CPANEL.align_panels_event.fire();
    };


    /**
      * Handle a failed fetch_for_install_form() callback.
      *
      * @method  sslInfoFailure
      * @param  {Object} o The CPANEL.api callback parameter.
      */
    function sslInfoFailure(o) {
        showErrorNotice( LOCALE.maketext("The lookup failed because of an error: [_1]", o.cpanel_error.html_encode()) );
    }


    /**
      * Paste in data from a fetch_for_install_form() callback.
      *
      * @method  sslInfoOk
      * @param  {Object} o The CPANEL.api callback parameter.
      */
    function sslInfoOk(o) {
        formProgressOverlay.hide();

        var result = o.cpanel_data[0] || o.cpanel_data;
        if (!result) {
            return;
        }

        var need = o.argument && o.argument.need;
        var exceptions = o.argument && o.argument.exceptions;

        var formParse = CPANEL.dom.get_data_from_form("mainform");

        var setCert = !o.argument || (o.argument.known !== "crt");
        var setIp = !formParse.ip || !validateIP(formParse.ip);

        // If we "need" the certificate, also paste in the key and CA bundle.
        // We might as well use the "domain" from this API response since then
        // we know that the IP and domain match.

        // All things being equal, we could easily grab a domain from the
        // certificate parse in JS, but that "tricks" the UI into
        // fetching on the domain, which clobbers the cert.

        ["key", "cab", "crt", "domain", "ip"].forEach( function(i) {
            var curResult = result[i];
            var elId = "ssl" + i;

            if ( !exceptions || exceptions.indexOf(elId) === -1 ) {
                if (!curResult || SORRY_COMMA_REGEXP.test(curResult) || !DOM.get(elId) || (need && need !== i)) {
                    return;
                } else if ( setIp && (i === "ip") && !result.user && PAGE.properties.sslips[curResult] ) { // always set ip if we have it
                    CPANEL.dom.set_form_el_value(elId, curResult);
                } else if ( i === "domain" ) {
                    setDomain(curResult);
                } else if ( ( ( i === "crt" ) && setCert ) || i === "key" || i === "cab" ) {
                    CPANEL.dom.set_form_el_value(elId, curResult);
                }
            }
        } );

        if ( !o.cpanel_data.crt && o.cpanel_messages[0] ) {
            var notice = new CPANEL.widgets.Dynamic_Page_Notice( {
                container: "autofill_message_container",
                visible: false,     // capture the slide animation
                level: o.cpanel_messages[0].level,
                content: o.cpanel_messages[0].content.html_encode()
            } );
            var slide = notice.animated_show();
            slide.onTween.subscribe( CPANEL.align_panels );
            notice.hideEvent.subscribe( CPANEL.align_panels );
        }

        updateUI();
        runValidation();
    }


    /**
      * Sets the domain selector, allowing for the www subdomain.
      * If there is nothing that matches, set the empty string.
      *
      * @param {String} domain The domain to attempt setting.
      * @method setDomain
      * @return {string} Which domain we set.
      */
    function setDomain(domain) {
        var domainsToSet = [
            domain,
            domain.replace(STAR_DOT_REGEXP, ""),
            ""
        ];
        var curDomain;

        while ( domainsToSet[0] ) {
            curDomain = domainsToSet.shift();
            if ( CPANEL.dom.set_form_el_value( "ssldomain", curDomain ) ) {
                return curDomain;
            }
        }
    }


    /**
      * Clear CJT validation.
      * If the form is emptied like we do when we click Update SSL
      * We need to clear all the validation messages
      *
      * @method clearValidation
      */
    function clearValidation() {
        ["ip", "domain", "cert", "key", "cab"].forEach( function(validation_type) {
            if ( validators[validation_type] ) {
                validators[validation_type].clear_messages();
            }
        } );
    }

    /**
      * Run CJT validation.
      * NOTE: This does not call the function under CPANEL.validate.form_checkers
      * because that function is designed for when you submit the form, and it'll
      * make validation errors appear if (for example) the entire form is empty.
      *
      * @method runValidation
      */
    function runValidation() {

        // === Do NOT do it this way .. see above.
        // CPANEL.validate.form_checkers.btnInstall( null, 1 );

        var form_values = CPANEL.dom.get_data_from_form("mainform");

        var validation_types = ["cert", "key"];
        if (PAGE.ui_mode !== "services") {
            validation_types.push("domain");
        }

        validation_types.forEach( function(validation_type) {
            validators[validation_type].verify();
        } );

        if (validators.ip && form_values.ip) {
            validators.ip.verify();
        }

        // Validate the CAB separately because it alone can legitimately be empty.
        validators.cab.verify();
    }


    /**
      * Fire off an AJAX lookup by a given certificate ID.
      *
      * @method fetchByCertId
      *
      * @param certId {string} - The id of the certificate to fetch from the server.
      * @param user   {string} - The name of the user to retrieve the certificate from.
      * @return {boolean}
      * @static
      */
    function fetchByCertId(certId, user) {
        showFormProgressOverlay();

        var api_call;
        if (CPANEL.is_whm()) {
            api_call = {
                func: "fetchcrtinfo",
                data: {
                    id: certId,
                    user: user
                }
            };
        } else {
            api_call = {
                version: 3,
                module: "SSL",
                func: "fetch_cert_info",
                data: { id: certId }
            };
        }

        // Ideally this would use build_page_callback; however, that function
        // doesn't (yet) play nicely with WHM API v1 batch calls.
        api_call.callback = {
            success: function(o) {
                formProgressOverlay.hide();

                var certParse;

                if ( o.cpanel_data.certificate ) {
                    DOM.get("sslcrt").value = o.cpanel_data.certificate;

                    // NOTE: For better UCC support, we should show users a drop-down
                    // or a combobox of domains and let them choose.
                    if ( PAGE.ui_mode !== "services" ) {
                        try {
                            certParse = CPANEL.ssl.parseCertificateText( o.cpanel_data.certificate );
                        } catch (e) {}

                        _populate_domain_from_parsed_cert(certParse);
                    }
                }

                if ( o.cpanel_data.key && !SORRY_COMMA_REGEXP.test(o.cpanel_data.key) ) {
                    DOM.get("sslkey").value = o.cpanel_data.key;
                }

                if ( certParse && certParse.isSelfSigned ) {
                    DOM.get("sslcab").value = "";
                } else if ( o.cpanel_data.cabundle && !SORRY_COMMA_REGEXP.test(o.cpanel_data.cabundle) ) {
                    DOM.get("sslcab").value = o.cpanel_data.cabundle;
                }

                updateUI();
                runValidation();
            },
            failure: function(o) {
                showErrorNotice( LOCALE.maketext("The certificate information could not be retrieved because of an error: [_1]", (o.cpanel_error || o.statusText).html_encode() ) );
            }
        };

        CPANEL.api( api_call );
    }


    /**
      * Fetch SSL items that match given criteria.
      *
      * @method  fetch_for_install_form
      * @param  {string} known What we are searching on: domain or sslcrt
      * @param  {Array} exceptions What *not* to touch on the form.
      * @return {Boolean}
      */
    function fetch_for_install_form(known, exceptions) {
        clearErrorNotice();

        var formData = CPANEL.dom.get_data_from_form("mainform");

        var domain = formData.domain;
        if (domain) {
            domain = domain.trim();
        }

        var sslcrt = formData.crt;
        if (sslcrt) {
            sslcrt = sslcrt.trim();
        }

        var callData = {};

        if (known === "crt" && sslcrt && !SORRY_COMMA_REGEXP.test(sslcrt) ) {
            callData.crtdata = sslcrt;  // WHM
            callData.certificate = sslcrt;  // cpanel
        } else if (known === "domain" && domain) {
            callData.domain = domain;
        } else if (sslcrt && !SORRY_COMMA_REGEXP.test(sslcrt)) {
            callData.crtdata = sslcrt;      // WHM
            callData.certificate = sslcrt;  // cpanel
            known = "crt";
        } else if (domain) {
            callData.domain = domain;
            known = "domain";
        } else {
            return;
        }

        var api_req = {
            data: callData,
            callback: {
                success: sslInfoOk,
                failure: sslInfoFailure,
                argument: { known: known, exceptions: exceptions }
            }
        };

        if (known === "domain") {

            // We only want one result. In the future
            // it might be nice to show the user all of
            // the results and have them pick, but for
            // now we just do the one.
            api_req.api_data = {
                paginate: { start: 0, size: 1 },
            };

            var all_domains = [ callData.domain ];

            if ( callData.domain.substr(0, 1) !== "*" ) {
                var aliases;

                if (CPANEL.is_whm()) {
                    aliases = PAGE.auto_domains;
                } else {
                    aliases = PAGE.data.domain_aliases[ callData.domain ];
                }

                aliases = aliases.map( function(ad) {
                    return ad + "." + callData.domain;
                } );

                all_domains.push.apply( all_domains, aliases );
            }

            callData.domains = all_domains.join(",");
            delete callData.domain;
        }

        if ( CPANEL.is_whm() ) {
            api_req.func   = (known === "domain") ? "fetch_ssl_certificates_for_fqdns" : "fetchsslinfo";
        } else {
            api_req.version = 3;
            api_req.module = "SSL";
            api_req.func   = (known === "domain") ? "fetch_certificates_for_fqdns" : "fetch_key_and_cabundle_for_certificate";
        }

        CPANEL.api( api_req );

        if ( formProgressOverlay && formProgressOverlay.cfg ) {
            formProgressOverlay.destroy();
        }

        showFormProgressOverlay();
    }

    /**
    * Initialize the IP drop-down in WHM.
    *
    * @method _initializeIpSelector
    * @private
    */
    var _initializeIpSelector = function() {
        var ips = PAGE.properties.sslips;
        var ip_options = PAGE.properties.ip_options;

        var cfg = YAHOO.lang.augmentObject( { maxResultsDisplayed: ip_options.length }, IP_COMBOBOX_CONFIG );
        var ipcombo = new CPANEL.widgets.Combobox( DOM.get("sslip"), null, ip_options, cfg );

        ipcombo.itemSelectEvent.subscribe(function(type, ACo) {
            var selected_ip = ACo[2][0];
            if (!DOM.get("ssldomain").value && ips[selected_ip] && ips[selected_ip].sslhost) {
                if (ips[selected_ip].hasssl) {
                    DOM.get("ssldomain").value = ips[selected_ip].sslhost;
                } else if (ips[selected_ip].iptype === "dedicated") {

                    /* It might would be nice if we presented them with
                        a popup of all the domains that the user
                        owns and let them select which domain
                        they would like to use */
                }
                ssldomain_change_delayed();
            }
            runValidation();
        });

        ipcombo.formatResult = function(oResultItem, sQuery) {
            var ip = oResultItem[0];

            var ip_info;

            if (ips[ip].primary_ssl_servername) {
                if (ips[ip].primary_ssl_aliases && ips[ip].primary_ssl_aliases.length) {
                    ip_info = LOCALE.maketext("SSL is installed; “[_1]” ([numerate,_2,alias,aliases] [list_and,_3]) is primary.", ips[ip].primary_ssl_servername, ips[ip].primary_ssl_aliases.length, ips[ip].primary_ssl_aliases.sort());
                } else {
                    ip_info = LOCALE.maketext("SSL is installed; “[_1]” is primary.", ips[ip].primary_ssl_servername);
                }
            }

            // TODO: Benchmark this with a large number of IPs.
            // It may need to be assembled without Handlebars for
            // the sake of users in slower environments.
            var sMarkup = ipSelectorItemTemplate( {
                ip: ip,
                hasssl: !!ips[ip].primary_ssl_servername,
                isShared: !!parseInt(ips[ip].is_shared_ip, 10),
                ipInfo_html: ip_info
            } );

            return sMarkup;
        };
    };


    /**
    * Validate the cert and update the UI.
    *
    * @param {object} opts An object to pass to updateUI().
    */
    var parse_and_do_cert_validate = function(opts) {
        updateUI( opts );
        validators.cert.verify();
    };


    /**
    * Validate the cert and update the UI, but do this after a slight delay.
    * This is good for events like "onpaste" that don't immediately change
    * the input value (because they can still be canceled within the handler).
    *
    * @param {object} opts An object to pass to delayed_updateUI().
    */
    var delayed_parse_and_do_cert_validate = function(opts) {
        delayed_updateUI( opts );
        window.setTimeout( validators.cert.verify.bind(validators.cert), 1 );
    };


    /**
    * Thin wrapper around delayed_parse_and_do_cert_validate()
    * that designates the active element as the domain input.
    */
    var ssldomain_change_delayed = function() {
        delayed_parse_and_do_cert_validate( { active_element: "domain" } );
    };


    /**
    * Thin wrapper around parse_and_do_cert_validate()
    * that designates the active element as the domain input.
    */
    var ssldomain_change = function() {
        parse_and_do_cert_validate( { active_element: "domain" } );
    };

    /**
    * Thin wrapper around the IP validation to delay it slightly.
    */
    var delayed_ip_domain_validate = function() {
        window.setTimeout( function() {
            validators.ip.verify();
        }, 1 );
    };


    /**
    * Thin wrapper around the key and CAB validation to delay it slightly.
    */
    var delayed_key_cab_validate = function() {
        window.setTimeout( function() {
            validators.key.verify();
            validators.cab.verify();
        }, 1 );
    };


    /**
    * Thin wrapper around updateUI() to set the certificate input
    * as the active/changed element.
    */
    var sslcrt_change = function() {
        updateUI( {
            active_element: "crt",
            is_apns: !!PAGE.parse_certs_for_apns,
        } );
    };


    /**
    * Thin wrapper around delayed_updateUI() to set the certificate input
    * as the active/changed element.
    */
    var sslcrt_change_delayed = function() {
        delayed_updateUI( { active_element: "crt" } );
    };

    /**
    * Hide the warning, and don't spew if the warning isn't there.
    */
    var _hide_wildcard_subdomain_warning = function() {
        if ( wildcard_subdomain_warning ) {
            wildcard_subdomain_warning.hide();
        }
    };

    /**
    * Maybe show the warning, maybe not, y'know?
    */
    var _process_wildcard_subdomain_warning = function() {
        var formDomain = this.value.trim();

        if (formDomain && /^\*\./.test(formDomain)) {
            var base_domain = formDomain.substr(2) || "domain.com";
            var wildcard_domain = formDomain.substr(0, 2) + base_domain;

            var content = LOCALE.maketext("We recommend that users manage individual subdomains (e.g., “[_1]”, “[_2]”) instead of a single wildcard subdomain (e.g., “[_3]”).", "sample1." + base_domain, "sample2." + base_domain, wildcard_domain);

            if (!wildcard_subdomain_warning) {
                wildcard_subdomain_warning = new CPANEL.widgets.Page_Notice( {
                    container: "wildcard_subdomain_warning",
                    level: "warn",
                    visible: false, /* To avoid animating. */
                    content: content
                } );
            } else {
                wildcard_subdomain_warning.cfg.setProperty("content", content);
            }

            wildcard_subdomain_warning.show();
        } else {
            _hide_wildcard_subdomain_warning();
        }
    };

    /**
      * Initialize the page's "validators" hash
      *
      * @method _set_up_validators
      * @private
      */
    var _set_up_validators = function() {
        if ( PAGE.ui_mode === "services" ) {
            validators.services = new CPANEL.validate.validator( LOCALE.maketext("Service") );
            validators.services.add_for_submit( "service_to_install", _validate_services_selected, LOCALE.maketext("Choose a service.") );
            validators.services.attach();

            EVENT.on( DOM.get("mainform").service, "click", validators.services.verify.bind(validators.services) );
        } else {
            validators.domain = new CPANEL.validate.validator( LOCALE.maketext("Domain") );
            validators.domain.add_for_submit( "ssldomain", "min_length($input$,1)", LOCALE.maketext("Choose a domain.") );
            validators.domain.add( "ssldomain", validateDomain, LOCALE.maketext("This is not a valid domain.") );
            validators.domain.validateSuccess.subscribe(_process_wildcard_subdomain_warning, DOM.get("ssldomain"), true);
            validators.domain.validateFailure.subscribe(_hide_wildcard_subdomain_warning);
            validators.domain.attach();

            if ( DOM.get("sslip") ) {
                validators.ip = new CPANEL.validate.validator( LOCALE.maketext("IP") );
                validators.ip.add_for_submit( "sslip", validateIP, validateIP_fail_reason );
                validators.ip.attach();
            }
        }

        validators.cert = new CPANEL.validate.validator( LOCALE.maketext("Certificate") );
        validators.cert.add_for_submit( "sslcrt", "min_length($input$.trim(),1)", LOCALE.maketext("Provide or retrieve a certificate.") );
        validators.cert.add( "sslcrt", validateCert, LOCALE.maketext("The certificate is not valid.") );

        if ( PAGE.ui_mode !== "services" ) {
            validators.cert.add( "sslcrt", validateDomainCertificateMatch, LOCALE.maketext("The certificate does not match your selected domain.") );
        }

        validators.cert.attach();

        validators.key = new CPANEL.validate.validator( LOCALE.maketext("Key") );
        validators.key.add_for_submit( "sslkey", "min_length($input$.trim(),1)", LOCALE.maketext("Provide or retrieve a key.") );
        validators.key.add( "sslkey", validateKey, LOCALE.maketext("The key is invalid.") );
        validators.key.add( "sslkey", validateKeyCert, LOCALE.maketext("The key does not match the certificate.") );
        validators.key.attach();

        validators.cab = new CPANEL.validate.validator( LOCALE.maketext("Certificate Authority Bundle") );
        validators.cab.add( "sslcab", validateCABundle, LOCALE.maketext("The CA bundle is invalid.") );
        validators.cab.add( "sslcab", validateCABundleCert, LOCALE.maketext("The CA bundle does not match the certificate.") );
        validators.cab.attach();

        var submit_button = CPANEL.Y.one("#mainform input[type=submit], #mainform button[type=submit]");

        CPANEL.validate.attach_to_form( submit_button.id, validators, {
            no_panel: true,
            success_callback: _send_install
        } );
    };

    /**
      * Kick-start the install AJAX.
      *
      * @method _send_install
      * @private
      */
    var _send_install = function() {
        var install_function = ( PAGE.ui_mode === "services" ) ? PAGE.sendInstall : sendApacheInstall;

        return install_function("mainform");
    };

    /**
      * Initialize the page's event listeners, including extra validation triggers.
      * This *MUST NOT* be called before _set_up_validators!!
      *
      * @method _set_up_listeners
      * @private
      */
    var _set_up_listeners = function() {
        EVENT.on("fetch-cert", "click", function(e) {
            fetch_for_install_form("crt");
        });

        if ( DOM.get("fetch-domain") ) {
            EVENT.on("fetch-domain", "click", function(e) {
                fetch_for_install_form("domain");
            });
        }

        if ( PAGE.ui_mode !== "services" ) {
            if ( pageHasDomainSelector ) {
                EVENT.on("ssldomain", "change", ssldomain_change_delayed );
            } else if (CPANEL.dom.has_oninput) {
                EVENT.on( "ssldomain", "input", ssldomain_change );
            } else {
                EVENT.on( "ssldomain", "paste", ssldomain_change_delayed );
                EVENT.on( "ssldomain", "keyup", ssldomain_change_delayed );
                EVENT.on( "ssldomain", "change", ssldomain_change_delayed );
            }
        }

        EVENT.on( "mainform", "reset", function() {
            delayed_updateUI();
            window.setTimeout( runValidation, 1 );
        } );

        // Make key and CAB validation fire also if the cert changes.
        if (CPANEL.dom.has_oninput) {
            EVENT.on( "sslcrt", "input", validators.key.verify.bind(validators.key) );
            EVENT.on( "sslcrt", "input", validators.cab.verify.bind(validators.cab) );
        } else {
            EVENT.on( "sslcrt", "paste", delayed_key_cab_validate );
            EVENT.on( "sslcrt", "keyup", delayed_key_cab_validate );
            EVENT.on( "sslcrt", "change", delayed_key_cab_validate );
        }

        if ( CPANEL.dom.has_oninput ) {
            EVENT.on( "sslcrt", "input", sslcrt_change );
        } else {
            EVENT.on( "sslcrt", "paste", sslcrt_change_delayed );
            EVENT.on( "sslcrt", "keyup", sslcrt_change );
            EVENT.on( "sslcrt", "change", sslcrt_change );
        }

        if ( DOM.get("sslip") ) {
            if (CPANEL.dom.has_oninput) {
                EVENT.on( "ssldomain", "input", validators.ip.verify.bind(validators.ip) );
            } else {
                EVENT.on( "ssldomain", "paste", delayed_ip_domain_validate );
                EVENT.on( "ssldomain", "keyup", delayed_ip_domain_validate );
                EVENT.on( "ssldomain", "change", delayed_ip_domain_validate );
            }
        }
    };

    var make_ssl_browser_panel = function() {
        var new_panel = new YAHOO.widget.Dialog(DOM.generateId(), {
            fixedcenter: true,
            close: true,
            draggable: true,
            modal: true,
            postMethod: "none",
            buttons: [
                { text: LOCALE.maketext("Use Certificate"), handler: function() {
                    this.submit();
                }, isDefault: true },
                { text: LOCALE.maketext("Cancel"), classes: ["cancel"], handler: function() {
                    this.cancel();
                } }
            ],
            visible: false
        });

        new_panel.setBody("");

        DOM.addClass( new_panel.element, "ssl-results-panel" );

        // Render the control into the element
        new_panel.render(document.body);

        return new_panel;
    };

    /**
      * Initialize the page's event listeners, including extra validation triggers.
      *
      * @method _set_up_listeners
      * @private
      */
    var _set_up_ssl_browser = function() {
        sslResultsPanel = make_ssl_browser_panel();

        sslResultsPanel.beforeSubmitEvent.subscribe( handleBeforeSubmit, sslResultsPanel );

        // Setup the current user on loading the page.
        if (PAGE && PAGE.properties) {
            current_user = PAGE.properties.selectedUser;
        }

        // Bug in YUI 2 Dialog: setBody has to happen before render.
        sslResultsPanel.setHeader(CPANEL.widgets.Dialog.applyDialogHeader(LOCALE.maketext("SSL Certificate List")));

        var formTemplate = Handlebars.compile( DOM.get("browsessl_default_form").text );

        var introBlurb;
        if ( CPANEL.is_cpanel() ) {
            introBlurb = LOCALE.maketext("Choose a certificate to install.");

            var limitationBlurb = LOCALE.maketext("Certificates that do not have a domain associated with your account are not listed here.") + " ";

            introBlurb += " " + limitationBlurb + " " + LOCALE.maketext("You can manage all of your saved certificates on the [output,url,_1,“Certificates” page].", "crts.html");
        } else {
            introBlurb = LOCALE.maketext("Choose the account or Apache domain that contains the desired certificate to install. Then, select the certificate.");
        }

        sslResultsPanel.form.innerHTML = formTemplate( {
            introBlurb_html: introBlurb
        } );

        // NOTE: We do NOT call normalize_select_arrows() on the user drop-down
        // because of the disable/enable triggers on that element.
        // Users likely expect their platform's behavior here.

        // Fetch the template for the dialog if it exists
        var template = DOM.get("hiddenWhiteSpaceListTemplate");
        if (template) {
            hiddenWhiteSpaceListTemplate = Handlebars.compile(template.text);
        }

        // This could also have gone into _set_up_listeners().
        EVENT.on("sslbrowse", "click", function(e) {
            browsessl(this);
        });

        EVENT.on( sslResultsPanel.form.users, "change", _onUserChange);

        // A radio button collection
        EVENT.on( sslResultsPanel.form.browse_source, "click", _onBrowseSourceChange );
    };

    function _populate_FQDN_TO_CREATED_DOMAIN() {
        for (var created in PAGE.data.domain_aliases) {
            FQDN_TO_CREATED_DOMAIN[created] = created;

            var aliases = PAGE.data.domain_aliases[created];
            for (var a = 0; a < aliases.length; a++) {
                FQDN_TO_CREATED_DOMAIN[ aliases[a] + "." + created ] = created;
            }
        }
    }

    var _populate_domain_from_parsed_cert = function(certParse) {


        if (certParse) {

            var cert_domains = certParse.domains;

            // In WHM, the SSL domain is just a text input field, not a drop-down selector.
            if ( CPANEL.is_whm() ) {

                // Re-populate the field with the common name when a cert is selected.
                DOM.get("ssldomain").value = cert_domains[0];
            } else {

                var form_data = CPANEL.dom.get_data_from_form("mainform");
                var selected_domain = form_data.domain.trim();

                var sel_dom_matches_cert = CPANEL.ssl.doesDomainMatchOneOf(selected_domain, cert_domains);

                if (!sel_dom_matches_cert) {
                    var set_ok;

                    // First, let’s see if we have any exact
                    // matches for the subject.commonName.
                    // This is good for wildcards but also
                    // just in general.
                    var created_domain = FQDN_TO_CREATED_DOMAIN[ cert_domains[0] ];
                    if (created_domain) {
                        set_ok = CPANEL.dom.set_form_el_value( "ssldomain", created_domain );
                    }

                    if (!set_ok) {
                        MATCH_SEEK:
                        for (var fqdn in FQDN_TO_CREATED_DOMAIN) {
                            if (CPANEL.ssl.doesDomainMatchOneOf(fqdn, cert_domains)) {
                                created_domain = FQDN_TO_CREATED_DOMAIN[fqdn];
                                if (CPANEL.dom.set_form_el_value( "ssldomain", created_domain )) {
                                    break;
                                }
                            }
                        }
                    }

                    // ""  //Reset domain <select> if this is a wildcard.
                }
            }

        }

    };

    /**
      * Initialize the page
      *
      * @method initialize
      * @private
      */
    var initialize = function() {

        if ( PAGE.ui_mode !== "services" ) {
            ( new CPANEL.widgets.Page_Notice( {
                visible: false,
                level: "info", // can also be "warn", "error", "success"
                content: DOM.get("ssl-install-require-template").text
            } ) ).show();

            (new CPANEL.widgets.Page_Notice( null, {
                visible: false,
                level: "info",
                content: LOCALE.maketext("To give website clients the best experience, ensure that each [asis,SSL] website’s certificate matches every domain on the website.") + "<br><br>" + LOCALE.maketext("When you install a valid certificate onto a website, the system also configures email, calendar, web disk, and [asis,cPanel]-related services to use that certificate for all of the website’s domains that match the certificate. Requests to these services from [asis,SNI]-enabled clients via the matching domains will receive the installed certificate.") + "<br><br>" + LOCALE.maketext("For more information, read our [output,url,_1,SSL Installation Workflow] documentation.", "https://go.cpanel.net/whmdocs66sslinstallworkflow")
            } ) ).show();
        }

        pageHasDomainSelector = !!CPANEL.Y.one("select#ssldomain");
        if (pageHasDomainSelector) {
            CPANEL.dom.normalize_select_arrows("ssldomain");
        }

        _set_up_validators();

        _set_up_listeners();

        _set_up_ssl_browser();

        if ( DOM.get("sslip") ) {
            ipSelectorItemTemplate = Handlebars.compile( DOM.get("ipSelectorItemTemplate").text.trim() );
            _initializeIpSelector();
        }

        updateUI();

        if ( DOM.get("sslcrt").value.trim() ) {
            if ( PAGE.ui_mode !== "services" ) {
                DOM.setStyle("fetch-cert", "display", "");
                try {
                    var certParse = CPANEL.ssl.parseCertificateText( DOM.get("sslcrt").value.trim() );

                    var certDomains = certParse.domains.slice(0);
                    while ( certDomains[0] ) {
                        if ( setDomain( certDomains.shift() ) ) {
                            break;
                        }
                    }
                } catch (e) {}
            }

            runValidation();
        }

        CPANEL.namespace( "CPANEL.sharedjs.sslinstall" );
        YAHOO.lang.augmentObject( CPANEL.sharedjs.sslinstall, {
            domain_change_delayed: ssldomain_change_delayed, /* export this to the window for whm ip selector */
            updateUI: updateUI,
            runValidation: runValidation,
            clearValidation: clearValidation,
            showFormProgressOverlay: showFormProgressOverlay,
            hideFormProgressOverlay: hideFormProgressOverlay,
            populate_form_with_ssl_components: populate_form_with_ssl_components,
            make_ssl_browser_panel: make_ssl_browser_panel
        } );

        if (pageHasDomainSelector) {
            _populate_FQDN_TO_CREATED_DOMAIN();
        }
    };

    CPANEL.nvdata.register( "certificates_table_sort", function() {
        return certificates_table_sort;
    } );

    if ( CPANEL.is_whm() ) {
        CPANEL.nvdata.register( "browse_source", function() {
            return current_browse_source;
        } );
    }

    window.fetch_for_install_form = fetch_for_install_form;

    // Register startup events.
    YAHOO.util.Event.onDOMReady(initialize);
})(window);
