if (typeof CPANEL == "undefined" || !CPANEL) {

    /**
     * The CPANEL global namespace object.  If CPANEL is already defined, the
     * existing CPANEL object will not be overwritten so that defined
     * namespaces are preserved.
     * @class CPANEL
     * @static
     */
    alert("The cjt has not been loaded, and must be loaded before this script: emailstats_summary.js");
}

( function() {
    window.DEFAULT_ROWS_PER_PAGE = 100;

    CPANEL.EximStatsSummary = function(oConfigs) {

        for (var setting in oConfigs) {
            if (typeof this[setting] != "undefined") {
                this[setting] = oConfigs[setting];
            }
        }

        init_start_end_times( this.starttime );
    };

    CPANEL.EximStatsSummary.mytimezone = YAHOO.util.Date.format(new Date(), { format: "%z" }),

    CPANEL.EximStatsSummary.oneday = (86400 * 1000);

    CPANEL.EximStatsSummary.thirtyonedays = (86400 * 1000 * 30);


    CPANEL.EximStatsSummary.prototype = {
        unixstarttime: null,

        initialsort: "SUCCESSCOUNT",

        group: "user",

        deliverytype: null,

        unixendtime: null,

        timebuffer: (60 * 60 * 4 * 1000),

        columns: ["USER", "DOMAIN", "SENDCOUNT", "TOTALSIZE"],

        userstatsuri: "/json-api/emailtrack_user_stats?",

        useruri: "emailstats_search",

        starttime: "yesterday",

        statsfail: function(o) {
            for (var i = 0; i < o.argument.statlist.length; i++) {
                var statname = o.argument.statlist[i];
                document.getElementById("deliverystats_" + statname).innerHTML = "Failed to fetch data";
            }
        },

        loadUnixTimes: function() {
            var currentint = get_start_end_times();
            this.unixstarttime = currentint[0] && (currentint[0].getTime() / 1000);
            this.unixendtime = currentint[1] && (currentint[1].getTime() / 1000);
        },

        buildDeliveryReport: function() {
            var EximStatsSumObj = this;

            this.loadUnixTimes();

            var unixtimeToDate = function(sData) {
                return new Date(parseInt(sData) * 1000);
            };

            var _img_lookup = {
                0: CPANEL.icons.success24,
                1: CPANEL.icons.error24
            };
            var lookupImg = function(oData) {
                return _img_lookup[oData] || _img_lookup[1];
            };

            var typetoImg = function(elCell, oRecord, tbl, oData) {
                elCell.innerHTML = lookupImg(oData) + (oData ? " " + oData : "");
            };

            var format_bytes = function(cell, rec, col, d) {
                cell.innerHTML = LOCALE.format_bytes(d);
            };
            var format_num = function(cell, rec, col, d) {
                cell.innerHTML = LOCALE.numf(d);
            };

            var possibleColumns = {
                "REACHED_MAXEMAILS": { "column": { key: "REACHED_MAXEMAILS", label: LOCALE.maketext("Relay per Hour"), sortable: true, formatter: typetoImg }, "schema": { key: "REACHED_MAXEMAILS", parser: "number" } },
                "REACHED_MAXDEFERFAIL": { "column": { key: "REACHED_MAXDEFERFAIL", label: LOCALE.maketext("Defer+Fail Per Hour"), sortable: true, formatter: typetoImg }, "schema": { key: "REACHED_MAXDEFERFAIL", parser: "number" } },
                "USER": { "column": { key: "USER", label: LOCALE.maketext("User"), sortable: true, formatter: "text" }, "schema": { key: "USER" } },
                "DOMAIN": { "column": { key: "DOMAIN", label: LOCALE.maketext("Domain"), sortable: true, formatter: "text" }, "schema": { key: "DOMAIN" } },
                "SUCCESSCOUNT": { "column": { key: "SUCCESSCOUNT", label: LOCALE.maketext("Successful"), formatter: format_num, sortable: true }, "schema": { key: "SUCCESSCOUNT", parser: "number" } },
                "FAILCOUNT": { "column": { key: "FAILCOUNT", label: LOCALE.maketext("Failures"), formatter: format_num, sortable: true }, "schema": { key: "FAILCOUNT", parser: "number" } },
                "DEFERCOUNT": { "column": { key: "DEFERCOUNT", label: LOCALE.maketext("Deferrals"), formatter: format_num, sortable: true }, "schema": { key: "DEFERCOUNT", parser: "number" } },
                "TOTALSIZE": { "column": { key: "TOTALSIZE", label: LOCALE.maketext("Data Sent"), formatter: format_bytes, sortable: true }, "schema": { key: "TOTALSIZE", parser: "number" } },
                "SENDCOUNT": { "column": { key: "SENDCOUNT", label: LOCALE.maketext("Total Messages"), formatter: format_num, sortable: true }, "schema": { key: "SENDCOUNT", parser: "number" } },
                "DEFERFAILCOUNT": { "column": { key: "DEFERFAILCOUNT", label: LOCALE.maketext("Failed and Deferred"), formatter: format_num, sortable: true }, "schema": { key: "DEFERFAILCOUNT", parser: "number" } }
            };

            // Column definitions
            var myColumnDefs = [];
            var fields = [];

            for (var i = 0; i < this.columns.length; i++) {
                myColumnDefs.push( possibleColumns[this.columns[i]].column );
                fields.push( possibleColumns[this.columns[i]].schema );
            }

            // DataSource instance
            var myDataSource = new CPANEL.datasource.CPANEL_XHRDataSource( {
                func: "emailtrack_user_stats",
                request_data: {
                    user: this.user || null,
                    group: EximStatsSumObj.group
                }
            } );

            // Summary configuration
            var myConfigs = {
                initialLoad: false,
                generateRequest: function(state, dt) {
                    var api = CPANEL.datatable.get_api_data(state);

                    api.filter = [];
                    if ( /remote/.test(EximStatsSumObj.deliverytype) ) {
                        api.filter.push( ["SUCCESSCOUNT", "gt", 0] );
                    }

                    var quick = DOM.get("quicksearch").value.trim();
                    if (quick) {
                        api.filter.push( ["*", "contains", quick] );
                    }

                    // Don't display all-zero rows for the relayers query.
                    return { api_data: api, data: {
                        deliverytype: EximStatsSumObj.deliverytype || null,
                        starttime: EximStatsSumObj.unixstarttime || null,
                        endtime: EximStatsSumObj.unixendtime || null
                    } };
                },
                dynamicData: true, // Enables dynamic server-driven data
                sortedBy: CPANEL.nvdata.initial && CPANEL.nvdata.initial.table_sort || { key: this.initialsort, dir: YAHOO.widget.DataTable.CLASS_DESC }, // Sets UI initial sort arrow
                paginator: THE_PAGINATOR
            };

            // Summary instance
            var mySummary = new YAHOO.widget.DataTable("eximstatssummary", myColumnDefs, myDataSource, myConfigs);

            // Update totalRecords on the fly with value from server
            mySummary.handleDataReturnPayload = function(oRequest, oResponse, oPayload) {
                oPayload.totalRecords = parseInt(oResponse.meta.total_records);
                return oPayload;
            };

            mySummary.getTableEl().title = LOCALE.maketext("Click a row to show a detailed report.");

            var handleRowClick = function(e) {
                var targetRow = e.target;
                var oRecord = this.getRecord(targetRow);
                var oData = oRecord.getData();

                EximStatsSumObj.loadUnixTimes();

                // Send "" for empty start/end times since otherwise the page
                // defaults to something based on the current time.
                var query_str = CPANEL.util.make_query_string( {
                    user: oData.USER,
                    unixstarttime: EximStatsSumObj.unixstarttime || "",
                    unixendtime: EximStatsSumObj.unixendtime || "",
                    deliverytype: EximStatsSumObj.deliverytype || null,
                    showAll: window.RELAY_ALL_BY_DEFAULT ? "true" : null
                } );
                window.location.href = EximStatsSumObj.useruri + "?" + query_str;
            };

            mySummary.subscribe("rowClickEvent", handleRowClick);

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

            this.loadUnixTimes();

            var dt = this.deliveryreport.dt;
            var req = dt.get("generateRequest")( dt.getState(), dt );
            this.deliveryreport.ds.sendRequest(req, oCallback);
        }
    };

})();
