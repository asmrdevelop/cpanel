(function(window) {

    "use strict";

    var EVENT = window.EVENT;
    var CPANEL = window.CPANEL;
    var LOCALE = window.LOCALE;
    var document = window.document;

    /**
     * Handle a click for setting a website as primary on its IP.
     *
     * @param e {Object} The click event object.
     */

    function primary_button_click_listener(e) {
        var clicked_el = e.target;
        var servername = clicked_el.getAttribute("data-servername");

        var pp = new CPANEL.ajax.Progress_Panel(null, {
            status_html: LOCALE.maketext("Setting “[_1]” as its IP address’s primary SSL website …", servername.html_encode()),
            effect: CPANEL.ajax.FADE_MODAL
        });

        pp.show_from_source(clicked_el);

        CPANEL.api({
            func: "set_primary_servername",
            data: {
                type: "ssl",
                servername: servername
            },
            callback: CPANEL.ajax.build_page_callback(function() {
                on_set_primary_success(pp, servername);
            }, {
                on_error: pp.hide.bind(pp)
            })
        });
    }

    /**
     * Handle a successful response from setting primary.
     *
     * @param progress_panel {CPANEL.ajax.Progress_Panel} The progress panel to replace.
     * @param servername {String} The new primary's servername.
     */

    function on_set_primary_success(progress_panel, servername) {
        var dialog = new CPANEL.ajax.Common_Dialog(null, {
            buttons: [{
                text: LOCALE.maketext("OK"),
                isDefault: true,
                handler: reload_button_handler,
                classes: "input-button"
            }]
        });

        dialog.setHeader(LOCALE.maketext("Primary SSL Website Set Successfully"));
        dialog.beforeShowEvent.subscribe(function() {
            this.form.innerHTML = LOCALE.maketext("“[_1]” is now the primary SSL website on its IP address.", servername.html_encode());
            this.center();
        });

        progress_panel.fade_to(dialog);
    }

    /**
     * What to do with an "OK" click when the page is to reload.
     */

    function reload_button_handler(e, dialog) {
        var this_button = dialog.getButtons()[0];
        this_button.disabled = true;

        if (document.activeElement === this_button) {
            this_button.blur();
        }

        // Strip out a query from the URL, and reload.
        window.location.href = window.location.pathname;
    }

    /**
     * Handles formatting arguments to be sent as part of an api call.
     * Supports sending a api argument that has mulitple values.
     *
     * An argument with one value shows up as:
     * {
     *     argname: value
     * }
     *
     * An argument with multiple values shows up as:
     * {
     *     argname: value,
     *     argname-1: value1,
     *     argname-2: value2,
     *     ...
     * }
     *
     * @param argname {string} name of the argument to send to the api
     * @param list {array} the list of values for the above argument
     */
    function formatArguments(argname, list) {
        var arg = {};
        for (var i = 0, len = list.length; i < len; i++) {
            if (i === 0) {
                arg[argname] = list[i];
            } else {
                arg[argname + "-" + i] = list[i];
            }
        }
        return arg;
    }

    /**
     * Handles the toggling of checkboxes
     *
     * @param toggle {boolean} controls setting the checked state of the checkboxes
     */
    function toggle_select_all(toggle) {
        var checkboxes = document.querySelectorAll("input[type='checkbox']");
        for (var i = 0, len = checkboxes.length; i < len; i++) {
            checkboxes[i].checked = toggle;
        }
    }

    /**
     * Gets all the currently selected items in the table
     */
    function get_selected_items() {
        var items = [];
        var checkboxes = Array.prototype.slice.call(document.querySelectorAll("input[type='checkbox']:checked"));
        checkboxes = checkboxes.filter(function(element) {
            if (element.id !== "selectAll") {
                return element;
            }
        });
        checkboxes.forEach(function(element) {
            var host = element.getAttribute("data-host");
            items.push(host);
        });
        return items;
    }

    EVENT.onDOMReady(function() {
        var primary_buttons = document.querySelectorAll(".make-primary-button");
        for (var b = 0; b < primary_buttons.length; b++) {
            EVENT.on(primary_buttons[b], "click", primary_button_click_listener);
        }

        // add check all functionality to the table
        var selectAllToggle = document.getElementById("selectAll");
        EVENT.on(selectAllToggle, "click", function() {
            toggle_select_all(selectAllToggle.checked);
        });
    });

})(window);
