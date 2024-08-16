if (typeof CPANEL == "undefined" || !CPANEL) {

    /**
     * The CPANEL global namespace object.  If CPANEL is already defined, the
     * existing CPANEL object will not be overwritten so that defined
     * namespaces are preserved.
     * @class CPANEL
     * @static
     */
    alert("The cjt has not been loaded, and must be loaded before this script: fetch_mail_queue.js");
}


( function() {

    var unixtimeToDate = function(sData) {
        return new Date( 1000 * sData );
    };
    var formatRecps = function(elCell, oRecord, col, oData) { // oData is now an array of receps
        elCell.innerHTML = oData
            .map(String.prototype.html_encode.call, String.prototype.html_encode)
            .join(" , <br /> ")
        ;
    };

    var _queued_row;
    var _frozen_row;

    var makeActionLinks = function(elCell, oRecord, tbl, oData) {
        var rowData = oRecord.getData();

        if ( rowData.frozen ) {
            var currentint = get_start_end_times();
            var opts = {
                unixstarttime: currentint[0] && (currentint[0].getTime() / 1000)
            };
            YAHOO.lang.augmentObject( opts, rowData );

            if ( !_frozen_row) {
                _frozen_row = DOM.get("frozen_row_template").text;
            }

            elCell.innerHTML = YAHOO.lang.substitute( _frozen_row, opts );
        } else {
            if ( !_queued_row) {
                _queued_row = DOM.get("queued_row_template").text;
            }

            elCell.innerHTML = YAHOO.lang.substitute( _queued_row, rowData );
        }
    };

    var toLocaleDate = function(el, rec, col, dat) {
        var date = new Date(dat);
        if (/invalid date/i.test(date)) {
            el.innerHTML = LOCALE.maketext("Invalid Date");
        } else {
            el.innerHTML = date.toCpLocaleString();
        }
    };
    var format_sender = function(elCell, oRecord, tbl, oData) {
        var trimmed = String(oData).trim();
        CPANEL.util.set_text_content( elCell, trimmed || "[" + LOCALE.maketext("System") + "]" );
    };
    var format_frozen = function(cell, rec, col, d) {
        CPANEL.util.set_text_content( cell, d ? LOCALE.maketext("Frozen") : LOCALE.maketext("Queued") );
    };

    var format_size = function(cell, rec, col, d) {
        cell.innerHTML = LOCALE.format_bytes(d);
    };

    // Column definitions
    var myColumnDefs = [
        { key: "check", label: "", width: "30", formatter: YAHOO.widget.DataTable.formatCheckbox },
        { key: "time", label: LOCALE.maketext("Time Received"), sortable: true, formatter: toLocaleDate },
        { key: "sender", label: LOCALE.maketext("Sender"), sortable: true, formatter: format_sender },
        { key: "msgid", label: LOCALE.maketext("Message ID"), sortable: true, formatter: "text" },
        { key: "recipients", formatter: formatRecps, label: LOCALE.maketext("Recipient(s)") },
        { key: "size", formatter: format_size, sortable: true, label: LOCALE.maketext("Size") },
        { key: "frozen", label: LOCALE.maketext("Status"), sortable: true, formatter: format_frozen },
        { key: "actions", label: LOCALE.maketext("Actions"), formatter: makeActionLinks }
    ];

    CPANEL.MailQueue = function(oConfigs) {
        for (var setting in oConfigs) {
            if (typeof this[setting] != "undefined") {
                this[setting] = oConfigs[setting];
            }
        }

        init_start_end_times( this.starttime );
    };

    CPANEL.MailQueue.prototype = {
        unixstarttime: null,

        unixendtime: null,

        starttime: "yesterday",

        statsfail: function(o) {
            for (var i = 0; i < o.argument.statlist.length; i++) {
                var statname = o.argument.statlist[i];
                document.getElementById("deliverystats_" + statname).innerHTML = LOCALE.maketext("The fetch returned no data.");
            }
        },

        loadUnixTimes: function() {
            var currentint = get_start_end_times();
            this.unixstarttime = currentint[0] && (currentint[0].getTime() / 1000);
            this.unixendtime = currentint[1] && (currentint[1].getTime() / 1000);
        },

        buildDeliveryReport: function() {
            var MailQueueObj = this;

            this.loadUnixTimes();

            // DataSource instance
            var myDataSource = new CPANEL.datasource.CPANEL_XHRDataSource( {
                func: "fetch_mail_queue",
                fields: [
                    { key: "frozen", parser: "number" },  // 1 or 0
                    { key: "time", parser: unixtimeToDate },
                    "sender",
                    "msgid",
                    { key: "size", parser: "number" },
                    "recipients"
                ]
            } );

            // Summary configuration
            var myConfigs = {
                initialLoad: false,
                generateRequest: function(state, dt) {
                    var req = CPANEL.datatable.get_api_data(state);
                    if (req.sort) {
                        if ( /^!?(?:size|time)$/.test(req.sort[0]) ) {
                            req.sort[0] = [ req.sort[0], "numeric" ];
                        }
                    }

                    if ( MailQueueObj.unixstarttime ) {
                        req.filter.push( [ "time", "gt", MailQueueObj.unixstarttime - 1 ] );
                    }
                    if ( MailQueueObj.unixendtime ) {
                        req.filter.push( [ "time", "lt", MailQueueObj.unixendtime + 1 ] );
                    }

                    var search = CPANEL.dom.get_data_from_form("search-fields");
                    if (search.freeform && search.mainkey && search.searchmatch) {
                        req.filter.push( [search.mainkey, search.searchmatch, search.freeform] );
                    }

                    var quick = DOM.get("quicksearch").value.trim();
                    if (quick) {
                        req.filter.push( ["*", "contains", quick] );
                    }

                    return { api_data: req };
                },
                dynamicData: true, // Enables dynamic server-driven data
                sortedBy: CPANEL.nvdata.initial && CPANEL.nvdata.initial.table_sort || { key: "time", dir: YAHOO.widget.DataTable.CLASS_DESC },
                paginator: THE_PAGINATOR
            };

            // Summary instance
            var mySummary = new YAHOO.widget.DataTable("mailqueuetbl", myColumnDefs, myDataSource, myConfigs);
            mySummary.subscribe("checkboxClickEvent", function(oArgs) {
                var elCheckbox = oArgs.target;
                var oRecord = this.getRecord(elCheckbox);
                oRecord.setData("check", elCheckbox.checked);
            });

            // Update totalRecords on the fly with value from server
            mySummary.handleDataReturnPayload = function(oRequest, oResponse, oPayload) {
                var totalRecords = parseInt(oResponse.meta.total_records);
                oPayload.totalRecords = totalRecords;
                return oPayload;
            };

            return {
                ds: myDataSource,
                dt: mySummary
            };
        },

        updatedata: function() {
            if ( !this.deliveryreport ) {
                this.deliveryreport = this.buildDeliveryReport();
            }

            // Sends a request to the DataSource for more data
            var oCallback = {
                success: this.deliveryreport.dt.onDataReturnReplaceRows,
                failure: window.handle_ajax_error,
                scope: this.deliveryreport.dt,
                argument: this.deliveryreport.dt.getState()
            };

            this.deliveryreport.dt._oRecordSet.reset();
            this.deliveryreport.dt.render();

            this.loadUnixTimes();

            var request = this.deliveryreport.dt.get("generateRequest")( this.deliveryreport.dt.getState(), this.deliveryreport.dt );
            this.deliveryreport.ds.sendRequest(request, oCallback);
        },

        deliverSelected: function() {
            this.multiAction("../scripts11/deliver_messages_mail_queue", 1);
        },
        deleteSelected: function() {
            this.multiAction("../scripts11/remove_messages_mail_queue", 1);
        },
        deleteAll: function() {
            if (confirm(LOCALE.maketext("Are you sure you wish to purge the entire mail queue?"))) {
                this.multiAction("../scripts11/purge_mail_queue", 0);
            }
        },
        deliverAll: function() {
            if (confirm(LOCALE.maketext("Are you sure you wish to attempt to deliver the entire mail queue?"))) {
                this.multiAction("../scripts11/deliver_mail_queue", 0);
            }
        },
        multiAction: function(multiAction, need_msg_ids) {
            var records = this.deliveryreport.dt.getRecordSet().getRecords();
            var msgids = [];
            if (need_msg_ids) {
                for (i = 0; i < records.length; i++) {
                    if (!records[i]) {
                        continue;
                    }
                    var oData = records[i].getData();
                    if (oData.check) {
                        msgids.push(oData.msgid);
                    }
                }
                document.getElementById("msgids").value = msgids.join(",");
                if (msgids.length == 0) {
                    alert(LOCALE.maketext("You must first select at least one message in the queue."));
                    return false;
                }
            } else {
                document.getElementById("msgids").value = msgids.join(",");
            }
            document.getElementById("multiactionform").action = multiAction;
            document.getElementById("multiactionform").submit();
        },

        selectAll: function(unsel) {
            var records = this.deliveryreport.dt.getRecordSet().getRecords();
            for (i = 0; i < records.length; i++) {
                this.deliveryreport.dt.getRecordSet().updateKey(records[i], "check", (unsel ? "" : "true"));
            }
            this.deliveryreport.dt.render();
        },

        unselectAll: function() {
            this.selectAll(1);
        }

    };
})();
