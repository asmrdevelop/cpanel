if (typeof CPANEL == "undefined" || !CPANEL) {

    /**
     * The CPANEL global namespace object.  If CPANEL is already defined, the
     * existing CPANEL object will not be overwritten so that defined
     * namespaces are preserved.
     * @class CPANEL
     * @static
     */
    alert("The cjt has not been loaded, and must be loaded before this script: emailstats_search.js");
}

( function() {

    var overflow_warning = LOCALE.maketext("This query produced a result set that exceeds the reportable limit.") + " ";
    switch (CPANEL.application) {
        case "whostmgr":
            overflow_warning += LOCALE.maketext("If you cannot find what you are looking for by paging through these results, please restrict the query further by narrowing your search.");
            break;
        default:
            overflow_warning += LOCALE.maketext("The results available below may not contain the record or records you are looking for.");
    }

    var overlay_manager = new YAHOO.widget.OverlayManager();

    // formatters--------------------------------------------------

    var typetoImg = function(elCell, oRecord, tbl, oData) {
        elCell.innerHTML = lookupImg(oData);
    };

    var unixtimeToDate = function(sData) {
        return new Date(parseInt(sData) * 1000);
    };

    var _img_lookup = {
        success: CPANEL.icons.success24,
        inprogress: CPANEL.icons.unknown24,
        defer: CPANEL.icons.warning24,
        filtered: CPANEL.icons.filtered24,
        archive: CPANEL.icons.archive24,
        rejected: CPANEL.icons.rejected24,
        error: CPANEL.icons.error24
    };

    var _img_lookup16 = {
        success: CPANEL.icons.success,
        inprogress: CPANEL.icons.unknown,
        defer: CPANEL.icons.warning,
        filtered: CPANEL.icons.filtered,
        archive: CPANEL.icons.archive,
        rejected: CPANEL.icons.rejected,
        error: CPANEL.icons.error
    };

    var _img_tooltip_lookup = {
        success: LOCALE.maketext("The mail server delivered this message successfully."),
        inprogress: LOCALE.maketext("The mail server is currently delivering this message."),
        defer: LOCALE.maketext("This message could not be delivered yet. The mail server will attempt delivery again later."),
        filtered: LOCALE.maketext("This message was discarded by an email filter or spam detection software."),
        archive: LOCALE.maketext("This message was saved into an email archive."),
        rejected: LOCALE.maketext("This message was rejected at SMTP time by an RBL, filter, or other configuration."),
        failure: LOCALE.maketext("This message could not be delivered.")
    };

    var lookupImg = function(oData) {
        var Imghtml = _img_lookup[oData] || _img_lookup.error;
        return Imghtml.replace(/\>/, ' alt="' + oData + '" title="' + ( _img_tooltip_lookup[oData] || oData ) + '" align="absmiddle">');
    };
    var lookupImg16 = function(oData) {
        var Imghtml = _img_lookup16[oData] || _img_lookup16.error;
        return Imghtml.replace(/\>/, ' alt="' + oData + '" title="' + ( _img_tooltip_lookup[oData] || oData ) + '" align="absmiddle">');
    };

    var toLocaleDate = function(el, rec, col, dat) {
        var date = new Date(dat);

        if (date.getTime()) {
            el.innerHTML = date.toCpLocaleString(CPANEL.DateTime.datetime_format_medium);
        } else {
            el.innerHTML = LOCALE.maketext("Invalid date.");
        }
    };

    var _actions_html;
    var _local_actions_html;
    var makeActionLinks = function(elCell, oRecord, tbl, oData) {
        var rowData = oRecord.getData();
        elCell.parentNode.className = "action-links-column";

        /* cache the html if its not already loaded */
        if (!_local_actions_html) {
            var localaction_template = DOM.get("local_actions_template");
            _local_actions_html = localaction_template ? localaction_template.text : " ";
        }

        /* If the email is not saved locally we should not display the retrival option */
        /* Only show if the type is success or archive to a local transport if the local_actions_html is available */
        if ( ( rowData.transport && ( rowData["transport"].match("remote_") || rowData["transport"] === "boxtrapper_autowhitelist" ) ) ||
             ( rowData["type"] !== "success" && rowData["type"] !== "archive")  ||
             _local_actions_html === " " ) {

            // Load the template
            if (!_actions_html) {
                _actions_html = DOM.get("actions_template").text;
            };

            // Insert the template
            elCell.innerHTML = _actions_html;
        } else {
            var address;
            if ( rowData["transport"] === "archiver_outgoing" ) {
                address = rowData["sender"];
            } else if ( rowData["transport"] === "local_delivery" || rowData["transport"] === "dovecot_delivery" || rowData["transport"] === "local_delivery_spam" || rowData["transport"] === "dovecot_delivery_spam" || rowData["transport"] === "local_boxtrapper_delivery" ) {
                address = rowData["deliveryuser"];
            } else {
                address = rowData["recipient"];
            }

            /* Email is saved locally and retrival should be possible */
            elCell.innerHTML = YAHOO.lang.substitute( _local_actions_html, {
                "msgid": encodeURIComponent(rowData["msgid"]),
                "transport": encodeURIComponent(rowData["transport"]),
                "address": encodeURIComponent(address),
                "path": encodeURIComponent(rowData["deliveredto"])
            } );
        }
    };
    var toLocaleBytes = function(elCell, oRecord, tbl, oData) {
        elCell.innerHTML = LOCALE.format_bytes(oData);
    };
    var format_sender = function(elCell, oRecord, tbl, oData) {
        var trimmed = String(oData).trim();
        CPANEL.util.set_text_content( elCell, trimmed || "[System]" );
    };

    var possibleColumns = {
        "type": { "column": { key: "type", label: LOCALETEXT.event, sortable: true, formatter: typetoImg } },
        "email": { "column": { key: "email", label: LOCALETEXT.email, sortable: true, formatter: format_sender } },
        "sender": { "column": { key: "sender", label: LOCALETEXT.sender, sortable: true, formatter: format_sender } },
        "user": { "column": { key: "user", label: LOCALETEXT.user, sortable: true, formatter: "text" } },
        "domain": { "column": { key: "domain", label: LOCALETEXT.domain, sortable: true, formatter: "text" } },
        "sendunixtime": { "column": { key: "sendunixtime", label: LOCALETEXT.sent, sortable: true, formatter: toLocaleDate }, "schema": { key: "sendunixtime", parser: unixtimeToDate } },
        "senderhost": { "column": { key: "senderhost", label: LOCALETEXT.sender_host, sortable: true, formatter: "text" } },
        "recipient": { "column": { key: "recipient", label: LOCALETEXT.recipient, sortable: true, formatter: "text" } },
        "deliveredto": { "column": { key: "deliveredto", label: LOCALETEXT.delivered_to, sortable: true, formatter: "text" } },
        "deliveryuser": { "column": { key: "deliveryuser", label: LOCALETEXT.delivery_user, sortable: true, formatter: "text" } },
        "deliverydomain": { "column": { key: "deliverydomain", label: LOCALETEXT.delivery_domain, sortable: true, formatter: "text" } },
        "transport": { "column": { key: "transport", label: LOCALETEXT.transport, sortable: true, formatter: "text" } },
        "router": { "column": { key: "router", label: LOCALETEXT.router, sortable: true, formatter: "text" } },
        "actionunixtime": { "column": { key: "actionunixtime", label: LOCALETEXT.out, sortable: true, formatter: toLocaleDate }, "schema": { key: "actionunixtime", parser: unixtimeToDate } },
        "msgid": { "column": { key: "msgid", label: LOCALETEXT.ID, sortable: true, formatter: "text" } },
        "host": { "column": { key: "host", label: LOCALETEXT.delivery_host, sortable: true, formatter: "text" } },
        "ip": { "column": { key: "ip", label: LOCALETEXT.delivery_ip, sortable: true, formatter: "text" } },
        "size": { "column": { key: "size", label: LOCALETEXT.size, sortable: true, formatter: toLocaleBytes }, "schema": { key: "size", parser: "number" } },
        "senderip": { "column": { key: "senderip", label: LOCALETEXT.sender_ip, sortable: true, formatter: "text" } },
        "senderauth": { "column": { key: "senderauth", label: LOCALETEXT.sender_auth, sortable: true, formatter: "text" } },
        "spamscore": { "column": { key: "spamscore", label: LOCALETEXT.spam_score, sortable: true, formatter: "number" } },
        "message": { "column": { width: 200, key: "message", label: LOCALETEXT.result, sortable: true, formatter: "text" }
        }
    };

    CPANEL.EximStatsDataTable = function(oConfigs) {
        for (var setting in oConfigs) {
            if ( setting in this ) {
                this[setting] = oConfigs[setting];
            }
        }
        this.delayeddisplay = true;

        init_start_end_times( this.starttime );
        if (!this.delayeddisplay) {
            this.deliveryreport = this.buildDeliveryReport();
        }
    };

    CPANEL.EximStatsDataTable.oneday = (86400 * 1000);

    CPANEL.EximStatsDataTable.thirtyonedays = (86400 * 1000 * 30);

    CPANEL.EximStatsDataTable.prototype = {

        mintime: CPANEL.EximStatsDataTable.thirtyonedays,

        unixstarttime: null,

        unixendtime: null,

        deliveryreport: null,

        deliverystats: 0,

        timebuffer: (60 * 60 * 4 * 1000),   // 4 hours

        columns: ["type", "email", "sender", "sendunixtime", "senderhost", "senderip", "senderauth", "spamscore", "recipient", "user", "domain", "deliveredto", "deliveryuser", "deliverydomain", "router", "transport", "actionunixtime", "msgid", "host", "ip", "size", "message", "actions"],

        user: null,

        delayeddisplay: 0,

        starttime: "yesterday",

        buildDeliveryReport: function() {
            var EximStatsDTObj = this;

            if (!this.unixstarttime || !this.unixendtime) {
                this.loadUnixTimes();
            }

            // Column definitions
            var myColumnDefs = []; // sortable:true enables sorting
            var my_fields = [];

            for (var i = 0; i < this.columns.length; i++) {
                if ( this.columns[i] === "actions" ) {
                    myColumnDefs.push( { key: "actions", label: LOCALETEXT.actions, formatter: makeActionLinks } );
                } else {
                    myColumnDefs.push( possibleColumns[this.columns[i]].column );
                    my_fields.push( possibleColumns[this.columns[i]].schema || this.columns[i] );
                }
            }

            var myDataSource = new CPANEL.datasource.CPANEL_XHRDataSource( {
                module: window.cp_exim ? "EmailTrack" : undefined,
                func: window.cp_exim ? "search" : "emailtrack_search",
                fields: my_fields
            } );

            // DataTable configuration
            var myConfigs = {
                initialLoad: false,
                generateRequest: function(state, dt) {
                    var api_data = CPANEL.datatable.get_api_data(state);

                    if (this.user) {
                        api_data.filter.push(["user", "eq", this.user]);
                    }

                    var search_form = CPANEL.dom.get_data_from_form("search-fields");

                    var search_field = search_form.mainkey;
                    if (search_field) {
                        var search_term = search_form.freeform;
                        if (search_term) {
                            var search_type = search_form.searchmatch;
                            if (search_type) {
                                api_data.filter.push([search_field, search_type, search_term]);
                            }
                        }
                    }

                    if (EximStatsDTObj.unixstarttime) {
                        api_data.filter.push(["sendunixtime", "gt", EximStatsDTObj.unixstarttime - 1]);
                    }
                    if (EximStatsDTObj.unixendtime) {
                        api_data.filter.push(["sendunixtime", "lt", EximStatsDTObj.unixendtime + 1]);
                    }
                    var searchall = false;
                    if (DOM.get("quicksearch")) {
                        searchall = DOM.get("quicksearch").value.trim();
                    }
                    if (searchall) {
                        api_data.filter.push(["*", "contains", searchall]);
                    }

                    var data = CPANEL.dom.get_data_from_form("advanced-form");

                    data.deliverytype = search_form.deliverytype || undefined;
                    if (!data.max_results_by_type ) {
                        data.max_results_by_type = EximStatsDTObj._max_results_by_type_value();
                    }

                    return { data: data, api_data: api_data };
                },
                dynamicData: true, // Enables dynamic server-driven data
                sortedBy: CPANEL.nvdata.initial && CPANEL.nvdata.initial.table_sort || { key: "sendunixtime", dir: YAHOO.widget.DataTable.CLASS_DESC }, // Sets UI initial sort arrow
                paginator: THE_PAGINATOR
            };

            // DataTable instance
            var myDataTable = new YAHOO.widget.DataTable("deliveryreport", myColumnDefs, myDataSource, myConfigs);

            // Fix weird IE7 quirk.
            if ( YAHOO.env.ua.ie && (YAHOO.env.ua.ie <= 7) ) {
                if (myDataTable.getTableEl().cellSpacing === "") {
                    myDataTable.getTableEl().cellSpacing = 0;
                }
            }

            // Update totalRecords on the fly with value from server
            myDataTable.handleDataReturnPayload = function(oRequest, oResponse, oPayload) {
                var totalRecords = parseInt(oResponse.meta.total_records);
                oPayload.totalRecords = totalRecords;
                return oPayload;
            };

            var emailreportpanel;

            var shown_records = {};
            var already_shown_notice;

            window.show_details = function(link) {
                var targetRow = DOM.getAncestorByTagName(link, "tr");
                var oRecord = myDataTable.getRecord(targetRow);
                var oData = oRecord.getData();

                var shown_key = CPANEL.util.values(oData).join();
                if ( shown_key in shown_records ) {
                    already_shown_notice = new CPANEL.ajax.Dynamic_Notice( {
                        replaces: already_shown_notice,
                        content: LOCALE.maketext("The specified record’s details are already visible. See the corresponding popup window.")
                    } );
                    shown_records[shown_key].focus();
                    return;
                }

                var printkeys = myDataTable.getColumnSet().flat.map( function(c) {
                    return [ c.key, c.label ];
                } );

                var emailreportpanel = new CPANEL.ajax.Common_Dialog(null, {
                    modal: false,
                    close: true,
                    zIndex: 5,   // make it above Wrapped_Selects
                    buttons: [
                        {
                            text: LOCALE.maketext("Print"),
                            handler: function() {
                                CPANEL.printthispanel( this.innerElement );
                            }
                        },
                        {
                            text: LOCALE.maketext("Close"),
                            classes: "cancel",
                            handler: function() {
                                this.cancel();
                            }
                        }
                    ]
                } );

                shown_records[shown_key] = emailreportpanel;
                emailreportpanel.hideEvent.subscribe( function() {
                    delete shown_records[shown_key];
                } );

                emailreportpanel.setHeader( CPANEL.widgets.Dialog.applyDialogHeader(LOCALE.maketext("Delivery Event Details")) );

                var txt = "<table class='event_details'><tbody>";
                printkeys.forEach( function(keylabel) {
                    var reportkey = keylabel[0];
                    if ( reportkey in oData ) {
                        var label = keylabel[1] || reportkey;
                        var value = oData[reportkey];
                        if ( (value === null) || (value === undefined) ) {
                            value = "";
                        } else if ( value instanceof Date ) {
                            value = value.toCpLocaleString(CPANEL.DateTime.datetime_format_medium);
                        } else if ( reportkey === "size" ) {
                            value = LOCALE.format_bytes(value);
                        } else {
                            value = String(value).html_encode();
                        }

                        if ( reportkey === "type" ) {
                            value += "&nbsp;" + lookupImg16(oData.type);
                        }

                        txt += "<tr><td><b>" + label + "</b>:</td><td>" + value + "</td></tr>";
                    }
                } );
                txt += "</tbody></table>";
                emailreportpanel.setBody(txt);

                overlay_manager.register(emailreportpanel);

                emailreportpanel.show_from_source( link );
                emailreportpanel.focus();
            };

            return {
                ds: myDataSource,
                dt: myDataTable
            };
        },
        _max_results_by_type_value: function() {
            try {
                var the_el = DOM.get("max_results_by_type");
                if (the_el) {
                    if ( the_el.options ) {
                        return 1 * the_el.options[the_el.selectedIndex].value;
                    } else {
                        return 1 * the_el.value;
                    }
                }
            } catch (e) {
                return 250;
            }
            return 250;
        },

        loadUnixTimes: function() {
            var currentint = get_start_end_times();
            this.unixstarttime = currentint[0] && (currentint[0].getTime() / 1000);
            this.unixendtime = currentint[1] && (currentint[1].getTime() / 1000);
        },

        updatedata: function() {
            var advanced = CPANEL.dom.get_data_from_form("advanced-form");
            if ( !advanced.defer && !advanced.failure && !advanced.success && !advanced.inprogress ) {
                alert("You must choose at least one type of event to show.");
                return 0;
            }

            if (!this.unixstarttime || !this.unixendtime) {
                this.loadUnixTimes();
            }

            if (this.delayeddisplay) {
                this.deliveryreport = this.buildDeliveryReport();
                this.delayeddisplay = 0;
            }

            var that = this;
            var success = function(req, resp, results) {
                if ( resp.meta.metadata && (String(resp.meta.metadata.overflowed) === "1") ) {
                    if ( !window.OVERFLOW_WARNING ) {
                        window.OVERFLOW_WARNING = new CPANEL.widgets.Page_Notice( {
                            level: "warn",
                            content: overflow_warning
                        } );
                    }
                } else if ( window.OVERFLOW_WARNING && OVERFLOW_WARNING.cfg ) {
                    OVERFLOW_WARNING.fade_out();
                    delete window.OVERFLOW_WARNING;
                }
                return that.deliveryreport.dt.onDataReturnReplaceRows.apply(this, arguments);
            };

            // Sends a request to the DataSource for more data
            var oCallback = {
                success: success,
                failure: window.handle_ajax_error,
                scope: this.deliveryreport.dt,
                argument: this.deliveryreport.dt.getState()
            };

            var thisRequest = this.deliveryreport.dt.get("generateRequest")( this.deliveryreport.dt.getState(), this.deliveryreport.dt );

            // this.deliveryreport.dt._oRecordSet.reset();
            this.deliveryreport.dt.showTableMessage( LOCALE.maketext("Loading new data …"), YAHOO.widget.DataTable.CLASS_LOADING);

            // this.deliveryreport.dt.render();

            this.deliveryreport.ds.sendRequest(thisRequest, oCallback);
        }
    };


})();


( function() {

    CPANEL.printthispanel = function(panelobj) {
        panelobj = DOM.getAncestorByClassName(panelobj, "yui-panel");
        var panelbody = DOM.getElementsByClassName( "bd", "div", panelobj )[0];
        var panelhead = DOM.getElementsByClassName( "hd", "div", panelobj )[0];

        var strPrintFrame = ("printme-" + (new Date()).getTime());
        var printFrameobj = document.createElement("iframe");
        printFrameobj.setAttribute("name", strPrintFrame);

        document.getElementById("printpanel").appendChild(printFrameobj);

        var printFrameWinobj = printFrameobj.contentWindow || printFrameobj.window;
        var printFrameDocobj = printFrameWinobj.document;

        var doctitle = CPANEL.util.get_text_content(panelhead);

        printFrameDocobj.open();
        printFrameDocobj.write( "<!DOCTYPE html>" );
        printFrameDocobj.write( "<html><head><style>.ft, a { display: none; };</style><title>" + doctitle.html_encode() + "</title></head><body>" + "<h1>" + panelhead.innerHTML + "</h1>" + panelbody.innerHTML + "</body></html>");
        printFrameDocobj.close();

        printFrameWinobj.focus();
        printFrameWinobj.print();

        setTimeout( function() {
            printFrameobj.parentNode.removeChild(printFrameobj);
        }, 120000 );
    };

})();

function restrictAdvanced(restrict) {
    var adv_form = DOM.get("advanced-form");
    var form = CPANEL.dom.get_data_from_form(adv_form);

    if (restrict) {
        var LOCALE = window.LOCALE || new CPANEL.Locale();

        adv_form.defer.disabled = true;
        adv_form.failure.disabled = true;
        adv_form.inprogress.disabled = true;
        adv_form.defer.title = LOCALE.maketext("This can only be selected when [output,class,Delivery Type,code] is [output,class,All,code].");
        adv_form.failure.title = LOCALE.maketext("This can only be selected when [output,class,Delivery Type,code] is [output,class,All,code].");
        adv_form.inprogress.title = LOCALE.maketext("This can only be selected when [output,class,Delivery Type,code] is [output,class,All,code].");
    } else {
        adv_form.defer.disabled = false;
        adv_form.failure.disabled = false;
        adv_form.inprogress.disabled = false;
        adv_form.defer.title = "";
        adv_form.failure.title = "";
        adv_form.inprogress.title = "";
    }
}
