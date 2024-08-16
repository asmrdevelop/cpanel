/* global LOCALE */

(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var CPANEL = window.CPANEL;

    var EVENT = YAHOO.util.Event,
        DOM = YAHOO.util.Dom,
        METADATA_SHOWN = false,
        variableRowTemplate = CPANEL.Y.one("#variableRowTemplate").text.trim(),
        sortRowTemplate = CPANEL.Y.one("#sortRowTemplate").text.trim(),
        filterRowTemplate = CPANEL.Y.one("#filterRowTemplate").text.trim(),
        columnRowTemplate = CPANEL.Y.one("#columnRowTemplate").text.trim(),
        inputsOnPageLoad = 3,
        api_comboboxes = {},
        DATATABLE_WIDTH = "700px";

    var views = new YAHOO.widget.TabView("views_container");

    /**
    * Initializer method which sets up event listeners, templates, and creates the tab view.
    *   Fired onDomReady.
    *
    * @method init
    */
    function init() {
        EVENT.on("api_form", "mouseup", update_api_call);
        EVENT.on("api_form", "keyup", update_api_call);
        EVENT.on("api_form", "submit", run_api_call);

        EVENT.on("metadataToggle", "click", toggle_metadata);
        EVENT.on("addVariableButton", "click", add_variable);
        EVENT.on("addSortButton", "click", add_sort);
        EVENT.on("addFilterButton", "click", add_filter);
        EVENT.on("addColumnButton", "click", add_column);

        EVENT.on(CPANEL.Y.all(".delete-link"), "click", deleteInput);

        var api_form = DOM.get("api_form");

        EVENT.on( CPANEL.Y(api_form).all("select"), "change", update_api_call );

        initialize_comboboxes();
        refresh_page_data();
    }

    function refresh_comboboxes() {
        var form_data = CPANEL.dom.get_data_from_form( "api_form" );
        var api_version = form_data.api_version;

        for (var key in api_comboboxes) {
            var cur_api_combobox = api_comboboxes[key];
            if ( key === api_version ) {
                cur_api_combobox.enable();
            } else {
                cur_api_combobox.disable();
            }
        }
    }

    function refresh_page_data() {
        refresh_comboboxes();
        update_api_call();
    }

    function initialize_comboboxes() {
        var wrappers = CPANEL.Y.all("div.cjt-combobox-wrapper");

        wrappers.forEach( function(wrapper) {
            var api_version = wrapper.id.match(/(\d+)$/)[0];
            var api_calls = window.PAGE.api_calls[api_version];

            var input = CPANEL.Y(wrapper).one("input");
            var expander = CPANEL.Y(wrapper).one(".cjt-combobox-expander");

            var radio = CPANEL.Y.one("#api_radio_" + api_version);

            var combobox = new CPANEL.widgets.Combobox(
                input,
                null,
                api_calls,
                {
                    queryMatchContains: true,

                    // Prevent YUI 2 AutoComplete from creating zillions of
                    // unused <li> elements.
                    maxResultsDisplayed: api_calls.length,

                    expander: expander
                }
            );

            // Prevent API calls from being displayed as RTL text.
            combobox.getListEl().dir = "ltr";

            // NOTE: In YUI 3, this would make a nice "smart disable" plugin.
            // If we need more of this behavior in YUI 2, though, it probably
            // should just move to the Combobox prototype.
            combobox.disableEvent.subscribe( function(e) {
                var overlay = combobox._disable_overlay;
                if ( !overlay ) {
                    overlay = new CPANEL.dom.Smart_Disable_Overlay(wrapper);
                    overlay.render(wrapper);
                    combobox._disable_overlay = overlay;

                    EVENT.on(overlay.element, "mousedown", function(e) {
                        overlay.hide();

                        radio.checked = true;
                        refresh_page_data();

                        input.focus();

                        // Apparently, a browser's default action from mousedown
                        // on a non-focusable element (e.g., overlay.element)
                        // is to focus document.body.
                        EVENT.preventDefault(e);
                    } );

                }

                overlay.align();
                overlay.show();
            } );

            combobox.enableEvent.subscribe( function(e) {
                if (combobox._disable_overlay) {
                    combobox._disable_overlay.hide();
                }
            } );

            api_comboboxes[api_version] = combobox;

            EVENT.on( radio, "click", refresh_page_data );
        } );
    }

    // So we don’t render the same raw data twice.
    var tId_rendered = {};

    function display_raw_response(o) {
        if (!tId_rendered[o.response.tId]) {
            CPANEL.util.set_text_content("raw_status", o.response.status + " " + o.response.statusText);
            DOM.get("raw_response").value = o.response.responseText;
            DOM.get("raw_headers").value = o.response.getAllResponseHeaders.trim();

            var http_cont_len = o.response.getResponseHeader["Content-Length"];
            if (http_cont_len) {
                http_cont_len = parseInt(http_cont_len, 10);
            }

            var comp, uncomp;
            var is_gzipped = (o.response.getResponseHeader["Content-Encoding"] === "gzip");

            if ( is_gzipped ) {
                comp = http_cont_len;
            } else {
                uncomp = http_cont_len;
            }

            if (uncomp === undefined) {
                uncomp = CPANEL.util.byte_length(o.response.responseText);
            }

            if ( comp !== undefined ) {
                DOM.get("resp_length").innerHTML = LOCALE.maketext("[format_bytes,_1] compressed, [format_bytes,_2] uncompressed", comp, uncomp);
            } else if ( is_gzipped ) {
                DOM.get("resp_length").innerHTML = LOCALE.maketext("compressed size unknown, [format_bytes,_1] uncompressed", uncomp);
            } else {
                DOM.get("resp_length").innerHTML = LOCALE.format_bytes(uncomp);
            }
        }
    }

    /**
    * Function which takes the API call object and executes it.  It also subscribes
    *   events to handle failure / success and draw the content in the tab view.
    *
    * @method run_api_call
    */
    function run_api_call(e) {
        var LOCALE = window.LOCALE || new CPANEL.Locale();

        var api_call = make_api_call_from_form();
        if (!CPANEL.api.construct_url_path(api_call)) {
            EVENT.stopEvent(e);
        }
        var datasource = new CPANEL.datasource.CPANEL_XHRDataSource( {
            api_version: api_call.version,
            module: api_call.module,
            func: api_call.func
        } );

        var overlay = new CPANEL.ajax.Page_Progress_Overlay( null, {
            covers: "api_form",
            status_html: LOCALE.maketext("Retrieving API call results …")
        } );
        overlay.show();

        var overlay_is_hidden = false;

        datasource.subscribe( "dataErrorEvent", function(oArgs) {
            if (!overlay_is_hidden) {
                overlay.hide();
                overlay_is_hidden = true;
            }

            display_raw_response(oArgs);

            views.selectTab(2);     // select the raw view

            var message = oArgs.message;
            if (oArgs.message === YAHOO.util.DataSourceBase.ERROR_DATANULL) {
                message = LOCALE.maketext("Table View is unavailable for this function’s data.");
            }
            CPANEL.util.set_text_content("table_container", message);
            DOM.get("table_record_count").innerHTML = "";
        } );

        datasource.subscribe( "responseParseEvent", function(oArgs) {
            var records = oArgs.response.results,
                columns;

            if ( records ) {
                if (records.length && (typeof records[0] === "object")) {
                    var keys = Object.keys(records[0]).sort();
                    var has_object_values = false;
                    columns = keys.map( function(k) {
                        if (typeof records[0][k] === "object") {
                            has_object_values = true;
                        }

                        return {
                            key: k,
                            resizeable: true,
                            formatter: "text",
                            sortable: true
                        };
                    } );

                    if (has_object_values) {
                        CPANEL.util.set_text_content("table_container", LOCALE.maketext("Table View is unavailable for this function’s data."));
                        DOM.get("table_record_count").innerHTML = "";
                        columns = [];
                        return;
                    }

                    DOM.get("table_record_count").innerHTML = LOCALE.maketext("[quant,_1,record,records], [quant,_2,field,fields] per record", records.length, keys.length);
                } else {
                    CPANEL.util.set_text_content("table_container", LOCALE.maketext("Table View is unavailable for this function’s data."));
                    DOM.get("table_record_count").innerHTML = "";
                    columns = [];
                    return;
                }

                var recordsDatasource = new YAHOO.util.LocalDataSource(records);
                var datatable = new YAHOO.widget.ScrollingDataTable("table_container", columns, recordsDatasource, {
                    initialLoad: false,
                    draggableColumns: true,
                    width: DATATABLE_WIDTH
                } );

                // This prevents a "jerk" of the page from re-rendering the table on sort.
                var table_container_height;
                datatable.subscribe( "beforeRenderEvent", function() {
                    table_container_height = CPANEL.dom.get_content_height("table_container");
                    DOM.setStyle("table_container", "height", table_container_height + "px");
                } );
                datatable.subscribe( "postRenderEvent", function() {
                    if (table_container_height) {
                        table_container_height = null;
                        DOM.setStyle("table_container", "height", "");
                    }
                } );

                datatable.load();
            } else {
                CPANEL.util.set_text_content("table_container", LOCALE.maketext("Table View is unavailable for this function’s data."));
            }
        } );

        datasource.subscribe( "responseEvent", function(o) {
            if (!overlay_is_hidden) {
                overlay.hide();
                overlay_is_hidden = true;
            }

            display_raw_response(o);

            var response_obj;
            try {
                response_obj = YAHOO.lang.JSON.parse(o.response.responseText);
            } catch (e) {}

            if ( response_obj ) {
                var treeview_data = make_treeview_data_from_object(response_obj);
                var treeview = new YAHOO.widget.TreeView( "response_treeview", treeview_data );
                treeview.render();
            } else {
                CPANEL.util.set_text_content("response_treeview", LOCALE.maketext("Invalid JSON."));
            }
        } );

        datasource.makeConnection( api_call );
    }

    /**
    * Function which generates a treeview by recursively traversing the object.
    *
    * @method make_treeview_data_from_object
    * @param {Object} obj The data object to generate the treeview from.
    */
    function make_treeview_data_from_object(obj) {
        var items = [];

        var obj_keys = Object.keys(obj);
        if ( !(obj instanceof Array) ) {
            obj_keys.sort();
        }

        for (var k = 0; k < obj_keys.length; k++) {
            var key = obj_keys[k];

            var new_item = { type: "Text" };
            if ( YAHOO.lang.isObject(obj[key]) ) {
                var obj_symbol;
                if (YAHOO.lang.isArray(obj[key])) {
                    obj_symbol = "[ " + obj[key].length + " ]";
                } else {
                    obj_symbol = "{ " + Object.keys(obj[key]).length + " }";
                }
                new_item.label = key + ": " + obj_symbol;
                new_item.children = make_treeview_data_from_object( obj[key], new_item );
                new_item.expanded = true;
            } else {
                new_item.label = key + ": " + YAHOO.lang.JSON.stringify(obj[key]);
            }

            items.push(new_item);
        }

        return items;
    }

    /**
    * Function which parses the form for data to generate an object used in making the API
    *   call.
    *
    * @method make_api_call_from_form
    * @return {Object} Returns an api_call object which stores all the values for the call
    */
    function make_api_call_from_form() {

        // This changes when we move to updated API system
        var form_data =         CPANEL.dom.get_data_from_form( "api_form" ),
            selectedAPI =       form_data["api_version"],
            api_call =          {};

        var column = "",
            num = "";


        var full_func = form_data.functionSelect;
        if (/:/.test(full_func)) {
            api_call.module = ( full_func.match(/^[^:]+/) || [] )[0];
            api_call.func = ( full_func.match(/[^:]+$/) || [] )[0];
        } else {
            api_call.func = full_func;
        }

        if ( selectedAPI ) {
            api_call.version = selectedAPI;
        }

        for (var key in form_data) {
            if ( !form_data[key] ) {
                continue;
            }

            if ( /^variable_/.test(key) ) {
                var variableMatch = key.match(/^variable_key_(.*)/);
                if ( variableMatch ) {
                    if ( !("data" in api_call) ) {
                        api_call.data = {};
                    }
                    api_call.data[form_data[key]] = form_data["variable_value_" + variableMatch[1]];
                }
            } else if ( /^sort_/.test(key) ) {
                var sortMatch = key.match(/^sort_column_(.*)/);
                if ( sortMatch ) {
                    var sort_index = sortMatch[1],
                        sort_type = form_data["sort_type_" + sort_index],
                        is_reverse = form_data["sort_reverse_" + sort_index];

                    column = form_data[key];
                    if ( is_reverse ) {
                        column = "!" + column;
                    }

                    if ( !("api_data" in api_call) ) {
                        api_call.api_data = {};
                    }
                    if ( !("sort" in api_call.api_data) ) {
                        api_call.api_data.sort = [];
                    }
                    api_call.api_data.sort.push( [ column, sort_type ] );
                }
            } else if ( /^filter_/.test(key) ) {
                var filterMatch = key.match(/^filter_type_(.*)/);
                if ( filterMatch ) {
                    var filter_index = filterMatch[1],
                        filter_type = form_data[key],
                        filter_term = form_data["filter_term_" + filter_index];

                    column = form_data["filter_column_" + filter_index];
                    if (column === undefined) {
                        column = "*";
                    }

                    if (filter_term && filter_type && column) {
                        if ( !("api_data" in api_call) ) {
                            api_call.api_data = {};
                        }
                        if ( !("filter" in api_call.api_data) ) {
                            api_call.api_data.filter = [];
                        }
                        api_call.api_data.filter.push( [ column, filter_type, filter_term ] );
                    }
                }
            } else if ( /^columns_/.test(key) ) {
                if ( !("api_data" in api_call) ) {
                    api_call.api_data = {};
                }
                if ( !("columns" in api_call.api_data) ) {
                    api_call.api_data.columns = [];
                }

                api_call.api_data.columns.push(form_data[key]);
            }
        }

        if (form_data["page_start"]) {
            num = Number(form_data["page_start"]);
            if (num) {
                if ( !("api_data" in api_call) ) {
                    api_call.api_data = {};
                }
                if ( !api_call.api_data.paginate ) {
                    api_call.api_data.paginate = {};
                }
                api_call.api_data.paginate.start = num;
            }
        }

        if (form_data["page_size"]) {
            num = Number(form_data["page_size"]);
            if (num) {
                if ( !("api_data" in api_call) ) {
                    api_call.api_data = {};
                }
                if ( !api_call.api_data.paginate ) {
                    api_call.api_data.paginate = {};
                }
                api_call.api_data.paginate.size = num;
            }
        }

        return api_call;
    }

    /**
    * Function which updates the API call.  This includes regenerating the API call object and redrawing
    *   elements on the page such as the API tree view.
    *
    * @method update_api_call
    */
    function update_api_call() {
        var api_call = make_api_call_from_form(),
            api_call_treeview_data = make_treeview_data_from_object(api_call),
            api_call_treeview = new YAHOO.widget.TreeView( "api_treeview", api_call_treeview_data );

        var query_url = CPANEL.api.construct_url_path(api_call) || "";
        if ( query_url ) {
            var query = CPANEL.api.construct_query(api_call);
            if (query) {
                query_url += "?" + query;
            }

            api_call_treeview.render();
        }

        DOM.get("submit_button").disabled = !query_url;
        DOM[ !!query_url ? "removeClass" : "addClass" ]( "api_treeview", "invalid-data" );

        CPANEL.util.set_text_content("url", query_url.replace( new RegExp("^" + CPANEL.security_token), "" ) );
    }

    /**
    * Function which takes in a template node and inserts it into the caller's associated
    *   .inputContainer.  Once these nodes are inserted an onClick event is tied to the .delete-link
    *   so that the user can easily remove it.
    *
    * @method addInputWithTemplate
    * @param {String} template A Template to be cloned and appended to the caller
    * @param {Object} caller The scope in which to find the parent.
    */
    function addInputWithTemplate(template, caller) {
        var inputContainer = DOM.getAncestorByClassName(caller, "inputContainer"),
            inputFields = CPANEL.Y(inputContainer).one(".inputFields"),
            inputFieldCount = CPANEL.Y(inputContainer).all(".inputField").length,
            docFragment = document.createDocumentFragment(),
            div = document.createElement("div");

        div.innerHTML = YAHOO.lang.substitute( template, { index: DOM.generateId() } );
        docFragment.appendChild(div);

        var cloneNode = docFragment.firstChild.firstChild;

        if ( !inputFieldCount ) {
            CPANEL.animate.slide_up(CPANEL.Y(inputFields).one(".noneField"));
            inputFields.appendChild(cloneNode);
        } else {
            inputFields.appendChild(cloneNode);
        }
        CPANEL.animate.slide_down(cloneNode);

        EVENT.on(CPANEL.Y(cloneNode).one(".delete-link"), "click", deleteInput);
        EVENT.on(CPANEL.Y(cloneNode).one("input[name^='sort_reverse']"), "change", update_api_call);
        EVENT.on(CPANEL.Y(cloneNode).one("input[type='text']"), "paste", update_api_call);
        EVENT.on(CPANEL.Y(cloneNode).one("input[type='text']"), "input", update_api_call);
    }

    /**
    * Function which removes associated input field.
    *  Bound to ".delete-link" onClick events.
    *
    * @method deleteInput
    */
    function deleteInput() {
        EVENT.purgeElement(this);// We remove the event listener to prevent double clicking
        var inputToDelete = DOM.getAncestorByClassName(this, "inputField"),
            parentContainer = DOM.getAncestorByClassName(this, "inputContainer"),
            slideAnimation = CPANEL.animate.slide_toggle(inputToDelete);
        slideAnimation.onComplete.subscribe( function() {
            inputToDelete.parentNode.removeChild(inputToDelete);
            update_api_call();

            var inputField = CPANEL.Y(parentContainer).all(".inputField");
            if ( !inputField.length ) {
                CPANEL.animate.slide_toggle(CPANEL.Y(parentContainer).one(".noneField"));
            }
        });
    }

    /**
    * Event handle function which adds variable input fields to parent div.
    *  Bound to ".addVariableButton" onClick events.
    *
    * @method add_variable
    */
    function add_variable() {
        addInputWithTemplate(variableRowTemplate, this);
    }

    /**
    * Event handle function which adds sort input fields to parent div.
    *  Bound to ".addSortButton" onClick events.
    *
    * @method add_sort
    */
    function add_sort() {
        addInputWithTemplate(sortRowTemplate, this);
    }

    /**
    * Event handle function which adds filter input fields to parent div.
    *  Bound to ".addFilterButton" onClick events.
    *
    * @method add_filter
    */
    function add_filter() {
        addInputWithTemplate(filterRowTemplate, this);
    }

    /**
    * Event handle function which adds filter input fields to parent div.
    *  Bound to ".addFilterButton" onClick events.
    *
    * @method add_column
    */
    function add_column() {
        addInputWithTemplate(columnRowTemplate, this);
    }

    /**
    * Function which shows and hides the metadata div.
    *
    * @method toggle_metadata
    */
    function toggle_metadata() {
        var metadataButton = CPANEL.Y.one("#metadataToggle");
        if ( METADATA_SHOWN ) {
            CPANEL.animate.slide_toggle("metadata");
            metadataButton.innerHTML = LOCALE.maketext("Show Sort/Filter/Paginate Options");
        } else {
            CPANEL.animate.slide_toggle("metadata");
            metadataButton.innerHTML = LOCALE.maketext("Hide Sort/Filter/Paginate Options");
        }

        METADATA_SHOWN = !METADATA_SHOWN;

    }

    for (var x = 0; x < inputsOnPageLoad; x++) {
        addInputWithTemplate(variableRowTemplate, CPANEL.Y.one("#addVariableButton"));
    }

    views.addTab( new YAHOO.widget.Tab( {
        label: LOCALE.maketext("Tree view"),
        contentEl: DOM.get("tree_view_container"),
        active: true
    } ) );
    views.addTab( new YAHOO.widget.Tab( {
        label: LOCALE.maketext("Table view"),
        contentEl: DOM.get("table_view_container")
    } ) );
    views.addTab( new YAHOO.widget.Tab( {
        label: LOCALE.maketext("Raw view"),
        contentEl: DOM.get("raw_view_container")
    } ) );

    EVENT.onDOMReady(init);
})(window);
