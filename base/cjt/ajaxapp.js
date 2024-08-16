/**
# cpanel - base/cjt/ajaxapp.js                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint camelcase: 0 */

(function(window) {

    "use strict";

    // -----------------------------
    // Shortcuts
    // -----------------------------
    var document = window.document;
    var YAHOO = window.YAHOO;
    var CPANEL = window.CPANEL;
    var DOM = window.DOM;
    var EVENT = window.EVENT;
    var LOCALE = window.LOCALE;

    // -----------------------------
    // Define the namespace;
    // -----------------------------
    CPANEL.namespace("ajax");
    CPANEL.namespace("datatable");

    // -----------------------------
    // Also modifies:
    // -----------------------------
    //  * String.prototype
    //  * YAHOO.widget.Panel.prototype
    //  * CPANEL.dom
    //  * YAHOO.widget.Module

    // -----------------------------
    // Notes:
    // -----------------------------
    // 1) A library should not be modifying all these other namespaces,
    // if the other namespace need to be modified, it should be done in the
    // file that builds that name space if its CPANEL or in an extension file
    // if for YUI.
    // 2) There are additional TODO's to deal with later as they are more
    // design issues. See below


    // -----------------------------
    //  Constants
    // -----------------------------
    var UNKNOWN_ERROR_MSG = LOCALE.maketext("An unknown error occurred.");
    var rtl = CPANEL.dom.isRtl();
    var ANIM_TIME = 0.25;

    function _masterContainerElement() {
        return document.getElementById("masterContainer") || document.body;
    }

    /**
     * Truncates the string to the length specified and appends the
     * ellipse only in the string is longer that the length.
     *
     * NOTE: This is NOT the correct solution for this; check FB 63640 for that.
     *
     * @elide
     * @param  {Number} length Maximum length of the string
     * @return {String}        Truncated and elided string.
     */
    String.prototype.elide = function(length) {
        var re = new RegExp(rtl ? ".+(.{" + length + "})$" : "^(.{" + length + "}).+");

        if (re.test(this)) {
            return this.replace(re, "$1…"); // see case 62397 post 3 regarding localized elide
        } else {
            return this.valueOf(); // to get a primitive string, not a String obj
        }
    };

    var API_MESSAGE_ICON = {
        info: CPANEL.icons.info,
        warn: CPANEL.icons.warning,
        error: CPANEL.icons.error,
    };


    // Effects
    var FADE_MODAL = {
        effect: CPANEL.animate.ContainerEffect.FADE_MODAL,
        duration: ANIM_TIME,
    };

    CPANEL.ajax.FADE_MODAL = FADE_MODAL;

    /**
     * Cache for the preloaded markup templates loaded by preloadMarkupTemplates
     * @type {Object}
     */
    CPANEL.ajax.templates = {};

    /**
     * Loads all the markup templates that have the mime-type of:
     *   text/plain
     *   text/html
     * @method preloadMarkupTemplates
     */
    var preloadMarkupTemplates = function() {
        var scripts = CPANEL.Y.all("script[type=\"text/plain\"], script[type=\"text/html\"]");
        for (var s = scripts.length - 1; s >= 0; s--) {
            var cur_script = scripts[s];
            CPANEL.ajax.templates[cur_script.id] = cur_script.text.trim();
        }
    };
    YAHOO.util.Event.onDOMReady(preloadMarkupTemplates);


    /**
     * Retrieves the api meta data from the current state of the datatable. To
     * be use in the next call
     * @method  get_api_data
     * @param  {[type]} state "state" can be a DataTable object or a DataTable state.
     * @return {Object}       [description]
     */
    CPANEL.datatable.get_api_data = function(state) {
        if (state.getState) {
            state = state.getState(); // "state" arg was a DT.
        }

        // Build up the data structure.
        var api_data = {

            // Filter structure defined for convenience
            filter: [],

            // Pagination data from the state
            paginate: {
                start: state.pagination.recordOffset,
                size: state.pagination.rowsPerPage,
            },
        };

        // Sort data from the state
        var sort = state.sortedBy && state.sortedBy.key;
        if (sort) {
            if (state.sortedBy.dir === YAHOO.widget.DataTable.CLASS_DESC) {
                sort = "!" + sort;
            }
            api_data.sort = [sort];
        }

        return api_data;
    };

    /**
     * Build the failure markup for an ajax call to one of our apis
     * This treats the first error as "primary".
     * That may or may not be how every API call is designed.
     *
     * @method _make_failure_html
     * @private
     * @param  {Object} o Object returned by a AJAX call.
     * @return {String}   HTML Markup representing the error
     */
    var _make_failure_html = function(o) {

        /* TODO: This needs to be reworked to use a markup island instead of building
         * this in code.
         */

        var error_html;

        if (!o) {
            error_html = UNKNOWN_ERROR_MSG;
        } else if (("status" in o) && o.status !== 200) {
            var async_args = CPANEL.api.get_transaction_args(o.tId);

            // sort the headers
            var headers_html = o.getAllResponseHeaders || "";
            if (headers_html) {
                headers_html = headers_html
                    .trim()
                    .split(/[\r\n]+/)
                    .sort()
                    .join("\n")
                    .html_encode();
            }

            var response_text = o.responseText || "";

            return YAHOO.lang.substitute(CPANEL.ajax.templates.cjt_http_error_dialog_template, {
                status: o.status,
                status_text_html: o.statusText.html_encode(),
                method: async_args ? async_args[0] : "",
                url_html: async_args ? async_args[1].html_encode() : "",
                post_html: (async_args && async_args[3] || "").html_encode(),
                response_html: (headers_html + "\n\n" + response_text.html_encode()).trim(),
            });
        } else if (o.cpanel_messages && o.cpanel_messages.length) {
            var cp_messages = o.cpanel_messages;
            error_html = o.cpanel_error ? "<span class=\"cjt-page-callback-main-error\">" + o.cpanel_error.html_encode() + "</span>" : "";
            error_html += "<ul class=\"cjt-page-callback-messages\">";
            error_html += cp_messages.map(function(m) {
                if (m.level !== "error" || m.content !== o.cpanel_error) {
                    return "<li>" +
                        API_MESSAGE_ICON[m.level] +
                        " " +
                        m.content.html_encode() +
                        "</li>";
                }

                return "";
            }).join("");
            error_html += "</ul>";
        } else if (o.responseText) {
            error_html = o.responseText.html_encode();
        }

        if (!error_html) {
            error_html = String(o).html_encode();
        }

        return error_html;
    };

    // A simple lookup hash is unideal because it depends on string IDs.
    // This allows lookup by either the DOM object reference or the ID.
    function API_Page_Notices_Controller() {
        this._entries = [];
    }
    YAHOO.lang.augmentObject(API_Page_Notices_Controller.prototype, {
        get_notice_for_container: function(container) {
            var entry = this._get_entry_for_container(container);

            return entry && entry.notice;
        },

        set_notice_for_container: function(notice, container) {
            var entry = this._get_entry_for_container(container);

            if (entry) {
                entry.notice = notice;
            } else {
                this._entries.push({
                    container: DOM.get(container),
                    notice: notice,
                });
            }
        },

        _get_entry_for_container: function(containerElOrId) {
            let containerEl = DOM.get(containerElOrId);

            for (var n = 0; n < this._entries.length; n++) {
                if (this._entries[n].container === containerEl) {
                    return this._entries[n];
                }
            }
        },
    });

    var API_PAGE_NOTICES = new API_Page_Notices_Controller();

    /**
     * Shows an error-level Page_Notice instance for the given argument:
     *   If an object, parses the response for a standard format.
     *   Otherwise, display the argument.
     * This tracks a single notice per "container", such that a 2nd notice
     * that this function generates while a 1st notice is still visible
     * in the same "container" will replace the old notice.
     *
     * @param o {Object|String} The object or string to format for display.
     * @param container {DOM|String} The "container" for showing the API error.
     */
    CPANEL.ajax.show_api_error = function(o, container) {
        var error_html;

        if (typeof o === "object") {
            error_html = _make_failure_html(o);
        } else {
            error_html = o;
        }

        var notice_height;

        var the_notice = API_PAGE_NOTICES.get_notice_for_container(container);

        if (the_notice &&
            the_notice.cfg &&
            DOM.inDocument(the_notice.element)) {

            // We already have a Page_Notice so don't create it again.

            // Set the error message into th content.
            the_notice.cfg.setProperty("content", error_html);

            notice_height = the_notice.element.offsetHeight;
        } else {

            // Build and cache a new Page_Notice
            the_notice = new CPANEL.widgets.Dynamic_Page_Notice({
                container: container,
                level: "error",
                content: error_html,
                visible: false, // so we can scroll up or down to the notice
            });

            API_PAGE_NOTICES.set_notice_for_container(the_notice, container);

            // Show it.
            var slide_down = the_notice.animated_show();
            notice_height = slide_down.attributes.height.to;
        }

        // Tie event handlers to the hide/show details link
        EVENT.on(CPANEL.Y.all(".http_error_details_link"), "click", function() {
            var noticeNode = DOM.getAncestorByClassName(this, "http_error_notice");
            var detailsNode = CPANEL.Y(noticeNode).one(".cjt_error_details");
            CPANEL.animate.slide_toggle(detailsNode);
        });

        // Scroll to the notice so it's visible to the user
        var notice_y = DOM.getY(the_notice.element);
        (new CPANEL.animate.WindowScroll(new YAHOO.util.Region(
            notice_y,
            1,
            notice_y + notice_height,
            0
        ))).animate();
    };

    /**
     * builds a callback object for YAHOO.util.Connect.asyncRequest()
     * that assumes error reporting on a CPANEL.widgets.Notice instance.
     * Note that Notices, YUI Dialogs, and YUI Overlays are all subclasses
     * of YUI Module.
     *
     * This does not create an in-progress notice of any kind.
     *
     * TODO: Teach this to do something useful with batch errors.
     *
     * @method build_page_callback
     * @static
     * @param  {Function} success_func Called on success
     * @param  {Hash} opts  Contains the following items:
     *   hide_on_return: a Module or array of Modules to hide when the call returns
     *   pagenotice_container: ID or element, defaults to Page_Notice default.
     *   on_cancel: function to call if the transaction is canceled
     *   on_error: function to call if the transaction errors
     * @return {[type]}              [description]
     */
    CPANEL.ajax.build_page_callback = function(success_func, opts) {

        /* TODO: Call inputs are weird compared to YUI model which we normally follow, consider refactoring */
        if (!opts) {
            opts = {};
        }

        var hide_them = !opts.hide_on_return ? null : function() {
            var to_hide = (opts.hide_on_return instanceof Array) ? opts.hide_on_return : [opts.hide_on_return];
            to_hide.forEach(function(mod) {
                if (mod.animated_hide) {
                    mod.animated_hide();
                } else {
                    mod.hide();
                }
            });
        };

        var cb_obj = {};

        /**
         * Set up the success handler
         */
        cb_obj.success = function() {
            if (hide_them) {
                hide_them();
            }
            if (success_func) {
                success_func.apply(this, arguments);
            }
        };

        /**
         * Setup the failure handler
         * @param  {Object} o Ajax response object
         */
        cb_obj.failure = function(o) {
            if (hide_them) {
                hide_them();
            }

            // -1 means the transaction was aborted.
            if (o && o.status && (o.status === -1)) {
                if (opts.on_cancel) {
                    opts.on_cancel.apply(this, arguments);
                }
                return;
            }

            CPANEL.ajax.show_api_error(o, opts.pagenotice_container);

            if (opts.on_error) {
                opts.on_error(o);
            }
        };

        return cb_obj;
    };

    /**
     * Builds a callback object for YAHOO.util.Connect.asyncRequest()
     * that assumes user input - response based on modal panels
     * @method build_callback
     * @static
     * @param  {Function} success_func [description]
     * @param  {Hash} panels  Contains one or more of the the following elements:
     *    current: the current panel
     *    success: the panel to show on success
     *    after_error: the panel to show after the error panel
     * @param  {Hash} opts Contains one or more of the the following elements:
     *    whm: interpret results as WHM API 1 calls
     *    failure: Executes on failure; see failure in CPANEL.api.
     *    on_error:  callback when user closes error dialog box
     *    on_cancel: callback when the transmission is canceled
     *    keep_current_on_success: Do nothing with panels on success.
     */
    CPANEL.ajax.build_callback = function(success_func, panels, opts) {

        var from_panel,
            after_error_panel;

        if (!opts) {
            opts = {};
        }

        if (panels) {
            from_panel = panels.current;
            after_error_panel = panels.after_error;
        }

        var obj = {};

        /**
         * Builds the failure handler
         * @param  {Object} o Ajax response object
         */
        obj.failure = function(o) {

            // Run the failure method
            if (opts.failure) {
                opts.failure.apply(this, arguments);
            }

            var error_html,
                is_http_error;

            // Figure out what kind of error this is
            if (typeof o === "object") {
                if (("status" in o) && o.status !== 200) {
                    if (o.status >= 0) {
                        is_http_error = true;
                    } else { // 0 and -1 are special YUI Connect values
                        if (opts.on_cancel) {
                            opts.on_cancel.call(this, o);
                        }
                        return;
                    }
                }
            }

            // Build the markup
            error_html = _make_failure_html(o);

            // TODO: Remove in release version
            if ("console" in window) {
                window.console.warn("API error:", o);
            }

            var error_dialog_closer;
            if (after_error_panel) {

                // Context is the error dialog

                /**
                 * Event handler for the dialog close action
                 * @method error_dialog_closer
                 */
                error_dialog_closer = function() {
                    var error_dialog = this;
                    error_dialog.fade_to(after_error_panel);
                    error_dialog.after_hideEvent.subscribe(error_dialog.destroy, error_dialog, true);
                };
            } else {

                // Other context

                /**
                 * Event handler for the dialog close action
                 * @method error_dialog_closer
                 */
                error_dialog_closer = function() {
                    this.cancel();
                };
            }

            // Build the dialog
            var error_dialog = new Error_Dialog(null, {
                buttons: [{
                    text: LOCALE.maketext("OK"),
                    handler: error_dialog_closer,
                    isDefault: true,
                }],
            });

            // Build the header
            var header_html = this.header ? this.header.innerHTML : is_http_error ? LOCALE.maketext("HTTP ERROR") : LOCALE.maketext("ERROR");

            // Setup the title
            header_html = CPANEL.widgets.Dialog.applyDialogHeader(header_html);
            error_dialog.setHeader(header_html);

            // Assemble the body
            if (is_http_error) {
                error_dialog.setBody(error_html);
            } else {
                error_dialog.setBody(YAHOO.lang.substitute(CPANEL.ajax.templates.cjt_error_dialog_template, {
                    "error_html": error_html,
                }));
            }

            error_dialog.render(_masterContainerElement());
            error_dialog.center();

            if (opts.on_error) {
                error_dialog.cancelEvent.subscribe(opts.on_error);
            }

            // Show the dialog one of several ways.
            if (from_panel) {
                from_panel.fade_to(error_dialog);
                if (!after_error_panel) {
                    from_panel.after_hideEvent.subscribe(from_panel.destroy, from_panel, true);
                }
            } else {

                // Show this dialog without a fade-in so it will be "alarming".
                error_dialog.show();
            }

            if (!after_error_panel) {
                error_dialog.cfg.setProperty("effect", FADE_MODAL);
            }
        };

        /**
         * Builds the success handler
         * @param  {Object} o Ajax response object
         */
        obj.success = function(o) {

            // Call the custom success call
            if (success_func) {
                success_func.call(this, o);
            }

            // Do the standard stuff
            if (from_panel && !opts.keep_current_on_success) {
                if (panels.success) {
                    from_panel.fade_to(panels.success);
                } else {
                    var old_effect = from_panel.cfg.getProperty("effect");
                    from_panel.cfg.setProperty("effect", FADE_MODAL);
                    from_panel.after_hideEvent.subscribe(function hider() {

                        // in case a panel isn't destroyed on hide,
                        // we just want to call this once
                        this.after_hideEvent.unsubscribe(hider);
                        this.cfg.setProperty("effect", old_effect);
                        if (from_panel.cfg) {
                            from_panel.destroy();
                        }
                    });
                    from_panel.hide();
                }
            }
        };

        return obj;
    };


    /**
     * A simple overlay with a throbber or spinner and fading status text.
     * @class Progress_Overlay
     * @extends {YAHOO.widget.Overlay}
     * @constructor
     * @param {String} id   Id of the element
     * @param {Hash} opts   Configurable properties include:
     * format: either "throbber" (default) or "spinner"
     *  covers: an element to which the align() method will resize the overlay
     *      i.e., the overlay will exactly "cover" the element.
     *  status_html: a string of HTML to use as a status message
     *  show_status: whether to show the status_html (default: false)
     */
    var Progress_Overlay = function(id, opts) {

        var default_progress_overlay_opts = {
            visible: false,
        };


        if (!id) {
            id = DOM.generateId();
        }

        if (!opts) {
            opts = {};
        }

        if (!("show_status" in opts)) {
            opts.show_status = !!opts.status_html;
        }

        YAHOO.lang.augmentObject(opts, default_progress_overlay_opts);

        // to prevent Overlay() from being called twice from Progress_Panel
        if (!this.cfg) {
            YAHOO.widget.Overlay.call(this, id /* , opts*/ );
        }

        this.beforeInitEvent.fire(Progress_Panel);

        DOM.addClass(this.element, "cjt-progress-overlay");

        this.cfg.applyConfig(opts, true);

        // TODO: Move this to a markup island.
        var body_html = "<div class=\"cjt-progress-overlay-body-liner\">";

        switch (this.cfg.getProperty("format")) {
            case "throbber":
                DOM.addClass(this.element, "throbber");
                body_html += "<div class=\"loader-tool\"><div class=\"loader\"></div></div>";
                break;
            case "spinner":
                DOM.addClass(this.element, "spinner");
                break;
            default:
                throw "PO format";
        }

        if (opts.show_status) {
            body_html += "<div class=\"cjt-progress-overlay-text-container\">" +
                "<span class=\"cjt-progress-overlay-text\">" +
                (opts.status_html || "&nbsp;") + // so it has a line height
            "</span></div>";
            this.renderEvent.subscribe(function add_fade() {
                this.renderEvent.unsubscribe(add_fade);
                var text_field = CPANEL.Y(this.body).one("span.cjt-progress-overlay-text");
                this.fading_text_field = new CPANEL.ajax.Fading_Text_Field(text_field);
            });
        }
        body_html += "</div>";

        this.setBody(body_html);

        this.throbber = this.body.firstChild.firstChild;

        DOM.setStyle(this.body, "border", 0); // in case
    };

    YAHOO.lang.extend(Progress_Overlay, YAHOO.widget.Overlay, {

        /**
         * [throbber description]
         * @this {Progress_Overlay}
         * @property {?} throbber ?
         */
        throbber: null,

        /**
         * [fading_text_field description]
         * @this {Progress_Overlay}
         * @property {?} fading_text_field ?
         */
        fading_text_field: null,

        /**
         * [initDefaultConfig description]
         * @method  initDefaultConfig
         * @param  {Boolean} no_recursion Do not call the supper class
         * version of this method.
         */
        initDefaultConfig: function(no_recursion) {
            if (!no_recursion) {
                Progress_Overlay.superclass.initDefaultConfig.call(this);
            }

            this.cfg.addProperty("show_status", {
                value: false,
            });
            this.cfg.addProperty("status_html", {
                value: "",
            });
            this.cfg.addProperty("covers", {
                value: null,
            });
            this.cfg.addProperty("format", {
                value: "throbber",
            });
        },

        /**
         * [set_status description]
         * @this {Progress_Overlay}
         * @method set_status
         * @param {String} new_html
         */
        set_status: function(new_html) {
            this.cfg.setProperty("status_html", new_html);
            if (this.cfg.getProperty("show_status")) {
                this.fading_text_field.set_html(new_html);
            }
        },

        /**
         * [set_status_now description]
         * @this {Progress_Overlay}
         * @method set_status_now
         * @param {String} new_html
         */
        set_status_now: function(new_html) {
            this.cfg.setProperty("status_html", new_html);
            if (this.cfg.getProperty("show_status")) {
                this.fading_text_field.set_html_now(new_html);
            }
        },

        /**
         * [align description]
         * @this {Progress_Overlay}
         * @method align
         */
        align: function() {
            Progress_Overlay.superclass.align.apply(this, arguments);

            var covered = this.cfg.getProperty("covers");
            if (covered && (covered = DOM.get(covered))) {
                var new_width = covered.offsetWidth;
                var new_height = covered.offsetHeight;

                if (new_width !== this._covered_width) {
                    this._covered_width = new_width;
                    this.cfg.setProperty("width", new_width + "px");
                }
                if (new_height !== this._covered_height) {
                    this._covered_height = new_height;
                    this.cfg.setProperty("height", new_height + "px");
                }
            }
        },
    });

    // Publish the object
    CPANEL.ajax.Progress_Overlay = Progress_Overlay;


    /**
     * A convenience class that dims out the "covers"ed element
     * and aligns the overlay. Auto-renders.
     * @class Page_Progress_Overlay
     * @extends {Progress_Overlay}
     * @constructor
     * @param {String} id   Id of the element
     * @param {Hash} opts   Configurable properties include:
     *   effect: animation effect to run
     */
    var Page_Progress_Overlay = function(id, opts) {
        if (!opts) {
            opts = {};
        }

        var default_options = {
            effect: {
                effect: YAHOO.widget.ContainerEffect.FADE,
                duration: ANIM_TIME,
            },
        };

        if (opts.covers) {
            default_options.context = [opts.covers, "tl", "tl", ["windowResize", "textResize"]];
            default_options.zIndex = parseInt(CPANEL.dom.get_zindex(DOM.get(opts.covers)), 10) + 1;
        }

        YAHOO.lang.augmentObject(opts, default_options);

        Page_Progress_Overlay.superclass.constructor.call(this, id, opts);

        this.renderEvent.subscribe(function() {
            DOM.addClass(this.element, "cjt-page-progress-overlay");
        });

        this.make_autorender();

        var to_enable = [];
        var to_focus;

        this.beforeShowEvent.subscribe(function() {
            var covered = this.cfg.getProperty("covers");
            if (covered && (covered = DOM.get(covered))) {
                var overlay = this;

                if (!this._covered_opacity) {
                    this._covered_opacity = DOM.getStyle(covered, "opacity");
                }

                if (this._fade) {
                    this._fade.stop();
                }

                this._fade = new YAHOO.util.Anim(
                    covered, {
                        opacity: {
                            to: this._covered_opacity / 4,
                        },
                    },
                    ANIM_TIME
                );
                this._fade.onComplete.subscribe(function() {
                    overlay._fade = null;
                });
                this._fade.animate();

                var form_els = CPANEL.Y(covered).all("input, button, textarea, select");

                var e = 0,
                    cur_el = form_els[e];
                while (cur_el) {
                    if (!cur_el.disabled) {
                        to_enable.push(cur_el);
                        if (cur_el === document.activeElement) {
                            to_focus = cur_el;
                            cur_el.blur();
                        }
                        cur_el.disabled = true;
                    }
                    e++;
                    cur_el = form_els[e];
                }

                // Prevent focusing anything beneath the overlay.
                EVENT.on(covered, "focusin", document.focus, document, true);
            }
        });

        this.beforeHideEvent.subscribe(function() {
            var covered = this.cfg.getProperty("covers");
            if (covered && (covered = DOM.get(covered))) {
                var overlay = this;

                if (this._fade) {
                    this._fade.stop();
                }
                this._fade = new YAHOO.util.Anim(
                    covered, {
                        opacity: {
                            to: this._covered_opacity,
                        },
                    },
                    ANIM_TIME
                );
                this._fade.onComplete.subscribe(function() {
                    overlay._fade = null;
                });
                this._fade.animate();

                for (var e = to_enable.length - 1; e >= 0; e--) {
                    var cur_el = to_enable[e];
                    cur_el.disabled = false;
                    if (cur_el === to_focus) {
                        cur_el.focus();
                        to_focus = null;
                    }
                }
                to_enable = [];

                EVENT.removeListener(covered, "focusin", document.focus);
            }
        });

        this.after_hideEvent.subscribe(this.destroy, this, true);
    };
    YAHOO.lang.extend(Page_Progress_Overlay, Progress_Overlay);
    CPANEL.ajax.Page_Progress_Overlay = Page_Progress_Overlay;

    /**
     * A modal panel variant of Progress_Overlay.
     * @class Progress_Panel
     * @extends {YAHOO.widget.Panel}
     * @augment {Progress_Overlay}
     * @constructor
     * @param {String} id   Id of the element
     * @param {Hash} opts   Configurable properties include:
     */
    var Progress_Panel = function(id, opts) {

        // NOTE: Extends YAHOO.widget.Panel and augmented by Progress_Overlay.
        // Kind of like a version of multiple inheritance.

        var default_progress_panel_opts = {
            modal: true,
            fixedcenter: true,
            draggable: false,
            dragOnly: true,
            close: false,
            underlay: "none",
            monitorresize: false, // for IE7; see case 48257
            visible: false,
        };

        if (!id) {
            id = DOM.generateId();
        } else if (typeof id === "object") {
            opts = id;
            id = DOM.generateId();
        }

        if (!opts) {
            opts = {};
        }

        YAHOO.lang.augmentObject(opts, default_progress_panel_opts);

        // We not forwarding the opts since the framework prefers
        // that objects only do constructor configuration once in
        // the call heirarchy.
        YAHOO.widget.Panel.call(this, id /* , opts*/ );
        Progress_Overlay.call(this, id, opts);

        this.beforeInitEvent.fire(Progress_Panel);

        DOM.addClass(this.element, "cjt_progress_panel_container");
        DOM.addClass(this.innerElement, "cjt_progress_panel");

        this.cfg.applyConfig(opts, true);

        this.make_autorender();

        // To prevent a focus on the Panel innerElement from drawing a
        // focus box around the Panel.
        // This should be safe since YUI 2.9.0 is unlikely to change at this point.
        if (!this._modalFocus) {
            this._createHiddenFocusElement();
        }
    };
    YAHOO.lang.extend(Progress_Panel, YAHOO.widget.Panel, {
        initDefaultConfig: function() {
            Progress_Panel.superclass.initDefaultConfig.call(this);
            Progress_Overlay.prototype.initDefaultConfig.call(this, true);
        },
    });
    YAHOO.lang.augment(Progress_Panel, Progress_Overlay);
    CPANEL.ajax.Progress_Panel = Progress_Panel;


    // class Fading_Text_Field
    //
    //
    // NOTE: The text values passed in are HTML, so be sure and HTML-encode them.

    /**
     * Make a text field fade among value assignments.
     * @class Fading_Text_Field
     * @constructor
     * @param {String|DomElement} dom_node Id or referece to a dom element.
     */
    CPANEL.ajax.Fading_Text_Field = function(dom_node) {
        dom_node = DOM.get(dom_node);
        DOM.addClass(dom_node, "cjt-fading-text-field");
        this._dom_node = dom_node;
        this._dom_node_parent = dom_node.parentNode;

        this._prototype_node = dom_node.cloneNode(false);
        this._prototype_node.style.display = "none";
        this._prototype_node.style.position = "absolute";
    };
    YAHOO.lang.augmentObject(CPANEL.ajax.Fading_Text_Field.prototype, {

        /**
         * [_fade_in description]
         * @this {Fading_Text_Field}
         * @private
         * @property {?} _fade_in
         */
        _fade_in: null,

        /**
         * [_fade_in_el description]
         * @this {Fading_Text_Field}
         * @private
         * @property {DomElement} _fade_in_el
         */
        _fade_in_el: null,

        /**
         * [_fade_out description]
         * @this {Fading_Text_Field}
         * @private
         * @property {?} _fade_out
         */
        _fade_out: null,

        /**
         * [_dom_node description]
         * @this {Fading_Text_Field}
         * @private
         * @property {DomElement} _dom_node
         */
        _dom_node: null,

        /**
         * [_dom_node_parent description]
         * @this {Fading_Text_Field}
         * @private
         * @property {DomElement} _dom_node_parent
         */
        _dom_node_parent: null,

        /**
         * [set_html_now description]
         * @method set_html_now
         * @this {Fading_Text_Field}
         * @param {String} new_html
         */
        set_html_now: function(new_html) {
            if (this._fade_in) {
                this._fade_in.stop();
            }
            if (this._fade_out) {
                this._fade_out.stop();
            }
            this._dom_node.innerHTML = new_html;
            DOM.setStyle(this._dom_node, "opacity", "");
            this._fade_in = null;
            this._fade_out = null;
        },

        /**
         * [set_html_now description]
         * @method set_html
         * @this {Fading_Text_Field}
         * @param {String} new_html
         */
        set_html: function(new_html) {
            var old_dom_node = this._dom_node;
            var dom_node_parent = this._dom_node_parent;

            // We want the fade object, or false.
            var fade_in = this._fade_in && this._fade_in.isAnimated() && this._fade_in;
            var fade_out = this._fade_out && this._fade_out.isAnimated() && this._fade_out;

            if (!fade_in && fade_out) {
                fade_out.stop();
                fade_out = false;
            }

            var new_span = this._prototype_node.cloneNode(false);
            new_span.id = DOM.generateId();
            new_span.innerHTML = new_html;
            dom_node_parent.insertBefore(new_span, this._dom_node);

            this._dom_node = new_span;

            // something was being faded in already, so kill that
            if (fade_in) {
                this._fade_in.stop();
                dom_node_parent.removeChild(this._fade_in_el);
            }

            // the new fade-in
            this._fade_in = CPANEL.animate.fade_in(new_span);
            this._fade_in_el = new_span;

            if (!fade_out && DOM.inDocument(old_dom_node)) {
                fade_out = CPANEL.animate.fade_out(old_dom_node);
                fade_out.onComplete.subscribe(function() {
                    dom_node_parent.removeChild(old_dom_node);
                    new_span.style.position = "";
                });
                this._fade_out = fade_out;
            }
        },
    });


    /**
     * Extend YAHOO.widget.Panel to have ability to fade from
     * one panel to another.
     * @method fade_to
     * @class YAHOO.widget.Panel
     * @param  {?} other_panel ???
     */
    YAHOO.widget.Panel.prototype.fade_to = function(other_panel) {
        var panel = this;

        var panel_modal = panel.cfg.getProperty("modal"),
            other_modal = other_panel.cfg.getProperty("modal"),
            fade_in,
            fade_out,
            hide,
            other_effect;

        if (panel_modal && other_modal) {

            // Suspend any effects that would normally go on here.
            // We'll put them back once the fade-in is done.
            other_effect = other_panel.cfg.getProperty("effect");

            // other_panel might not be rendered, in which case show() below
            // will trigger our own autorender code, which in turn will trigger
            // other_panel.cfg.fireQueue, which in turn will set "effect".
            // We need to ensure that "effect" is null.
            if (other_panel.element && DOM.inDocument(other_panel.element)) {
                other_panel.cfg.setProperty("effect", null);
            } else {
                other_panel.cfg.queueProperty("effect", null);
            }

            other_panel.cfg.setProperty("zIndex", this.cfg.getProperty("zIndex") + 1);

            var the_mask = this.mask;

            var other_mask = other_panel.mask;

            // remove other_panel's own mask
            if (other_mask && DOM.inDocument(other_mask)) {
                other_mask.parentNode.removeChild(other_mask);
            }

            // A reasonable guess that YUI 2 will not change the mask ID scheme...
            // ...otherwise it would be prudent to do other_panel.buildMask() and then
            // assign the_mask.id to be that ID.
            the_mask.id = other_panel.id + "_mask";

            // exchange masks
            other_panel.mask = the_mask;
            this.mask = null;

            // Process the fadeout
            fade_out = new YAHOO.util.Anim(
                panel.element, {
                    opacity: {
                        to: 0,
                    },
                },
                ANIM_TIME
            );
            fade_out.onComplete.subscribe(function f_d() {
                delete panel._fade;

                panel.hide();
                if (panel.cfg) { // in case destroy() is subscribed to hide()
                    DOM.setStyle(panel.element, "opacity", "");
                }
            });
            if ("_fade" in this) {
                hide = this.hide;
                this.hide = function() {}; // in case onComplete would hide() the panel
                this._fade.stop();
                this.hide = hide;
            }
            this._fade = fade_out;
            fade_out.animate();

            DOM.setStyle(other_panel.element, "opacity", 0);
            other_panel.show();

            // set a z-index above the mask so we still see the fade out
            var target_zindex = parseFloat(CPANEL.dom.get_zindex(the_mask)) + 1;
            DOM.setStyle(this.element, "z-index", target_zindex);

            fade_in = new YAHOO.util.Anim(other_panel.element, {
                opacity: {
                    to: 1,
                },
            }, ANIM_TIME);
            fade_in.onComplete.subscribe(function() {
                DOM.setStyle(other_panel.element, "opacity", "");
                other_panel.cfg.setProperty("effect", other_effect);
                delete other_panel._fade;
            });
            if ("_fade" in other_panel) {
                hide = other_panel.hide;
                other_panel.hide = function() {};
                other_panel._fade.stop();
                other_panel.hide = hide;
            }
            other_panel._fade = fade_in;
            fade_in.animate();
        } else {
            var yui_fade = {
                effect: YAHOO.widget.ContainerEffect.FADE,
                duration: ANIM_TIME,
            };

            var panel_effect = panel.cfg.getProperty("effect");
            other_effect = other_panel.cfg.getProperty("effect");
            var panel_new_effect = panel_modal ? FADE_MODAL : yui_fade;
            var other_new_effect = other_modal ? FADE_MODAL : yui_fade;

            panel.hideEvent.subscribe(function resetter() {
                this.hideEvent.unsubscribe(resetter);
                this.cfg.setProperty("effect", panel_effect, true);
            });
            other_panel.hideEvent.subscribe(function other_resetter() {
                this.hideEvent.unsubscribe(other_resetter);
                this.cfg.setProperty("effect", other_effect, true);
            });

            panel.cfg.setProperty("effect", panel_new_effect, true);
            other_panel.cfg.setProperty("effect", other_new_effect, true);

            panel.hide();
            other_panel.show();
        }
    };

    /**
     * Extend YAHOO.widget.Panel to have ability to show a Panel
     * zooming/moving from a particular point, fading in the modal
     * mask if it is a modal Panel.
     * @method show_from_source
     * @class YAHOO.widget.Panel
     * @param  {Varies} source either a DOM element (string/object) or an [x,y] array
     */
    YAHOO.widget.Panel.prototype.show_from_source = function(source) {

        // TODO: Should be in a yui extension.js

        var clicked_el, source_xy;
        if (source instanceof Array) {
            source_xy = source;
        } else {

            // make the Overlay appear as though it came from the middle of the source el
            clicked_el = DOM.get(source);
            source_xy = _find_el_center(clicked_el);
        }

        var this_el = this.element;
        var this_el_style = this_el.style;

        var modal = this.cfg.getProperty("modal");

        DOM.setStyle(this_el, "opacity", 0);
        if (modal) {
            this.beforeShowMaskEvent.subscribe(function make_clear() {

                // we only want this function to be called once
                this.beforeShowMaskEvent.unsubscribe(make_clear);

                DOM.setStyle(this.mask, "opacity", 0);
            });
        }

        var already_shown = this._already_shown;
        if (!already_shown) {
            this.beforeShowEvent.subscribe(function to_center() {
                this.beforeShowEvent.unsubscribe(to_center);
                this.center();
                this._already_shown = true;
            });
        }

        this.show();
        var target_xy = DOM.getXY(this_el);

        // this prevents things from sliding around as we expand
        var inner_el = this.innerElement;
        var inner_el_style = inner_el.style;

        var inner_width_to_restore = inner_el_style.width;
        var inner_height_to_restore = inner_el_style.height;
        var outer_width_to_restore = this_el_style.width;
        var outer_height_to_restore = this_el_style.height;

        var target_width = CPANEL.dom.get_content_width(inner_el) + "px";
        var target_height = CPANEL.dom.get_content_height(inner_el) + "px";
        inner_el_style.width = target_width;
        inner_el_style.height = target_height;

        this_el_style.width = 0;
        this_el_style.height = 0;
        DOM.addClass(this_el, "cjt_panel_animating");

        DOM.setStyle(this_el, "opacity", "");

        var motion = new YAHOO.util.Motion(this_el, {
            points: {
                from: source_xy,
                to: target_xy,
            },
            width: {
                from: 0,
                to: parseFloat(target_width),
            },
            height: {
                from: 0,
                to: parseFloat(target_height),
            },
        }, ANIM_TIME);

        motion.animate();

        motion.onComplete.subscribe(function() {
            inner_el_style.width = inner_width_to_restore;
            inner_el_style.height = inner_height_to_restore;
            this_el_style.width = outer_width_to_restore;
            this_el_style.height = outer_height_to_restore;
            DOM.removeClass(this_el, "cjt_panel_animating");
        });

        // set visibility to hidden to allow fade_in() to the CSS-given opacity
        if (modal) {
            this.mask.style.visibility = "hidden";
            DOM.setStyle(this.mask, "opacity", "");
            CPANEL.animate.fade_in(this.mask);
            this.mask.style.visibility = "";
        }

        return motion;
    };


    /**
     * Extend YAHOO.widget.Panel to have ability to hide
     * panel zooming/moving to a particular point, fading out the
     * modal mask if it is a modal Panel. If the "point" is a DOM node,
     * the Panel zooms to the node's center, and the node, if possible,
     * is focused once the animation is done.
     * @method hide_to_point
     * @class YAHOO.widget.Panel
     * @param  {Varies} point_xy either a DOM element (string/object) or an [x,y] array
     */
    YAHOO.widget.Panel.prototype.hide_to_point = function(point_xy) {

        // TODO: Should be in a yui extension.js
        var clicked_el;
        if (!(point_xy instanceof Array)) {
            clicked_el = DOM.get(point_xy);
            point_xy = _find_el_center(clicked_el);
        }

        var panel = this;
        var panel_el = this.element;
        panel_el.style.overflow = "hidden";
        var last_xy = DOM.getXY(panel_el);
        var motion = new YAHOO.util.Motion(panel_el, {
            points: {
                from: last_xy,
                to: point_xy,
            },
            width: {
                to: 0,
            },
            height: {
                to: 0,
            },
        }, ANIM_TIME);
        motion.animate();
        var fade_out;
        if (this.mask) {
            fade_out = CPANEL.animate.fade_out(this.mask);
        }
        motion.onComplete.subscribe(function() {
            if (fade_out) {
                fade_out.stop(true);
            }
            panel.hide();

            DOM.setXY(panel_el, last_xy);
            panel_el.style.height = "";
            panel_el.style.width = "";
            if (clicked_el && clicked_el.focus) {
                var el_is_on_screen = CPANEL.dom.get_viewport_region()
                    .contains(DOM.getRegion(clicked_el));
                if (el_is_on_screen) {
                    clicked_el.focus();
                }
            }
        });

        return motion;
    };

    /**
     * a shortcut function that relieves us of the need to render Modules to
     * _masterContainerElement() (which is where most of them go, since they
     * are Panel or Dialog instances generally).
     * @method make_autorender
     * @return {[type]} [description]
     */
    YAHOO.widget.Module.prototype.make_autorender = function() {

        // TODO: Should be in yui_extension.js
        var _show = this.show;
        var _rendered = false;
        this.renderEvent.subscribe(function() {
            _rendered = true;
        });

        this.show = function() {
            if (!_rendered) {
                this.render(_masterContainerElement());
                _rendered = true;
            }
            this.show = _show;
            return _show.apply(this, arguments);
        };
    };


    /**
     * Contains the default dialog options use by various dialog sub classes below
     * @const
     * @type {Object}
     */
    var STANDARD_DIALOG_OPTS = {
        modal: true,
        draggable: true,
        close: false,
        visible: false,
        postmethod: "manual",
        hideaftersubmit: false,
        constraintoviewport: true,
        dragOnly: true,
        effect: null, // so resetProperty() will work on this
        strings: {
            "close": LOCALE.maketext("Close"),
        },
        buttons: [{
            text: LOCALE.maketext("Proceed"),
            handler: function() {
                this.submit();
            },
            isDefault: true,
        }, {
            text: LOCALE.maketext("Cancel"),
            classes: "cancel",
            handler: function() {
                this.cancel();
            },
        }],
    };

    /**
     * TODO: Reword
     * a set of standard behaviors for Dialog instances, including:
     *  behavior?
     *  buttons
     *  form handling (manual only)
     *  destroy on cancel()
     *  modal mask over the body & footer and show a Progress_Overlay on submit
     * @method Common_Dialog
     * @constructor
     * @class
     * @extends {YAHOO.widget.Dialog}
     * @param {String} id   [description]
     * @param {[type]} opts [description]
     */
    var Common_Dialog = function(id, opts) {
        if (id && (typeof id === "object")) {
            opts = id;
            id = DOM.generateId();
        } else if (!id) {
            id = DOM.generateId();
        }

        // assign standard props
        // assign submit handler - hide/destroy

        if (!opts) {
            opts = {};
        }

        var copy_buttons = !("buttons" in opts);
        YAHOO.lang.augmentObject(opts, STANDARD_DIALOG_OPTS);

        if (copy_buttons) {
            var copied_buttons = [];
            for (var i = opts.buttons.length - 1; i >= 0; i--) {
                copied_buttons[i] = YAHOO.lang.augmentObject({}, opts.buttons[i]);
            }
            opts.buttons = copied_buttons;
        }

        Common_Dialog.superclass.constructor.call(this, id /* , opts */ );

        this.beforeInitEvent.fire(Common_Dialog);

        DOM.addClass(this.element, "cjt_common_dialog_container");

        this.cfg.applyConfig(opts, true);

        // Set up the dialog title
        this.setHeader(CPANEL.widgets.Dialog.applyDialogHeader("&nbsp;"));

        this.setBody("");

        this.make_autorender();

        var the_dialog = this;

        this.form.onsubmit = function() {
            return false;
        }; // YUI does its own submit()

        if (this.cfg.getProperty("draggable") && this.cfg.getProperty("fixedcenter")) {
            this.showEvent.subscribe(function() {
                this.cfg.setProperty("fixedcenter", false, false);
            });
            this.hideEvent.subscribe(function() {
                DOM.setStyle(this.element, "left", "");
                DOM.setStyle(this.element, "top", "");
                this.cfg.setProperty("fixedcenter", true, false);
            });
        }

        this.cancelEvent.subscribe(function() {
            this.after_hideEvent.subscribe(function destroyer() {

                // so successive cancelEvents will not create lots of these:
                this.after_hideEvent.unsubscribe(destroyer);

                if (the_dialog.cfg) {
                    the_dialog.destroy();
                }
            });
        });

        this.manualSubmitEvent.subscribe(function() {
            if (this.cfg.getProperty("progress_overlay")) {
                var body_region = DOM.getRegion(this.body);
                var footer_region = DOM.getRegion(this.footer);

                var mask_z_index = parseFloat(CPANEL.dom.get_zindex(this.element)) + 1;

                // NOTE: This ugliness is for generating masks for the body and the
                // footer after submitting the form. It was done originally because
                // innerHTML injection was faster than DOM manipulation in most
                // browsers; however, at some later point, that may not be the case.
                var dummy_div = document.createElement("div");
                dummy_div.style.display = "none";
                document.body.appendChild(dummy_div);

                // TODO: Remove to a markup island
                var div_html_template = "<div class='cjt_common_dialog_mask' style='" +
                    "position:absolute;visibility:hidden;" +
                    "z-index:{z_index};" +
                    "background-color:{body_background_color};" +
                    "width:{body_inner_width}px;" +
                    "height:{body_inner_height}px;" +
                    "'>&nbsp;</div>" +
                    "<div class='cjt_common_dialog_mask' style='" +
                    "position:absolute;visibility:hidden;" +
                    "z-index:{z_index};" +
                    "background-color:{footer_background_color};" +
                    "width:{footer_inner_width}px;" +
                    "height:{footer_inner_height}px;" +
                    "'>&nbsp;</div>";

                var div_html = YAHOO.lang.substitute(div_html_template, {
                    z_index: mask_z_index,
                    body_background_color: CPANEL.dom.get_background_color(this.body),
                    body_inner_width: body_region.width,
                    body_inner_height: body_region.height,
                    footer_background_color: CPANEL.dom.get_background_color(this.footer),
                    footer_inner_width: footer_region.width,
                    footer_inner_height: footer_region.height,
                });
                dummy_div.innerHTML = div_html;
                var body_mask = dummy_div.firstChild;
                var footer_mask = dummy_div.lastChild;

                // Different browsers report this value differently,
                // and YUI doesn't perfectly abstract it all away.
                var target_opacity = DOM.getStyle(body_mask, "opacity");

                // JNK :TODO: This may not handle "inherits" properly, however
                // fixing it will increase risk at this stage
                if (!target_opacity || target_opacity == 1) {
                    target_opacity = 0.7;
                }

                DOM.setStyle(body_mask, "opacity", 0);
                DOM.setStyle(footer_mask, "opacity", 0);

                body_mask.style.visibility = "";
                footer_mask.style.visibility = "";

                var body_fader = new YAHOO.util.Anim(body_mask, {
                    opacity: {
                        to: target_opacity,
                    },
                }, ANIM_TIME);
                var footer_fader = new YAHOO.util.Anim(footer_mask, {
                    opacity: {
                        to: target_opacity,
                    },
                }, ANIM_TIME);

                this.body.appendChild(body_mask);
                this.footer.appendChild(footer_mask);
                document.body.removeChild(dummy_div);

                // in case there is no height/width set on the body or footer
                DOM.setXY(body_mask, [body_region.left, body_region.top]);
                DOM.setXY(footer_mask, [footer_region.left, footer_region.top]);

                body_fader.animate();
                footer_fader.animate();

                var progress_overlay = new Progress_Overlay(null, {
                    zIndex: mask_z_index + 1,
                    visible: false,
                    show_status: this.cfg.getProperty("show_status"),
                    effect: {
                        effect: YAHOO.widget.ContainerEffect.FADE,
                        duration: ANIM_TIME,
                    },
                    status_html: this.cfg.getProperty("status_html"),
                });
                progress_overlay.render(this.body);

                progress_overlay.beforeShowEvent.subscribe(function() {
                    DOM.setXY(this.element, [
                        body_region.left + body_region.width / 2 - this.element.offsetWidth / 2, (footer_region.bottom + body_region.top) / 2 - this.element.offsetHeight / 2,
                    ]);
                });

                progress_overlay.show();
                this.progress_overlay = progress_overlay;


                // prevent focusing anything by making an invisible modal panel
                // lamentably, this prevents dragging the original Dialog
                var focus_killer = new YAHOO.widget.Panel(DOM.generateId(), {
                    modal: true,
                    x: DOM.getX(this.element),
                    y: DOM.getY(this.element),
                    visible: false,
                });

                focus_killer.render(this.element);
                focus_killer.buildMask();
                DOM.setStyle(focus_killer.element, "opacity", 0);
                DOM.setStyle(focus_killer.mask, "opacity", 0);
                focus_killer.show();

                var kill_focus_killer = function() {
                    if (focus_killer.cfg) {
                        focus_killer.destroy();
                    }
                };

                progress_overlay.destroyEvent.subscribe(kill_focus_killer);

                // undo the fades and disables after hide, in case this gets reshown
                progress_overlay.beforeHideEvent.subscribe(function kill_mask() {
                    this.beforeHideEvent.unsubscribe(kill_mask);

                    kill_focus_killer();

                    var body_out = new YAHOO.util.Anim(body_mask, {
                        opacity: {
                            to: 0,
                        },
                    }, ANIM_TIME);
                    var footer_out = new YAHOO.util.Anim(footer_mask, {
                        opacity: {
                            to: 0,
                        },
                    }, ANIM_TIME);
                    body_out.onComplete.subscribe(function() {
                        if (the_dialog.body) {
                            the_dialog.body.removeChild(body_mask);
                        }
                    });
                    footer_out.onComplete.subscribe(function() {
                        if (the_dialog.footer) {
                            the_dialog.footer.removeChild(footer_mask);
                        }
                    });
                    body_out.animate();
                    footer_out.animate();
                });

                progress_overlay.after_hideEvent.subscribe(progress_overlay.destroy, progress_overlay, true);

                // In the success case when we're in all-modal mode,
                // we have to listen for when the dialog dialog hides.
                this.beforeHideEvent.subscribe(function make_sure() {
                    this.beforeHideEvent.unsubscribe(make_sure);
                    if (focus_killer.cfg) {
                        focus_killer.destroy();
                    }
                });

                this.hideEvent.subscribe(function make_sure2() {
                    if (progress_overlay.cfg) {
                        progress_overlay.cfg.setProperty("effect", null);
                        progress_overlay.hide();
                    }
                });
            } else {
                if (this.cfg.getProperty("modal")) {
                    this.cfg.setProperty("effect", FADE_MODAL);
                }

                this.hide();
            }
        });
    };
    Common_Dialog.default_options = STANDARD_DIALOG_OPTS;
    YAHOO.lang.extend(Common_Dialog, YAHOO.widget.Dialog, {

        /**
         * [initDefaultConfig description]
         * @return {[type]} [description]
         */
        initDefaultConfig: function() {
            YAHOO.widget.Dialog.prototype.initDefaultConfig.call(this);

            this.cfg.addProperty("progress_overlay", {
                value: true,
            });
            this.cfg.addProperty("show_status", {
                value: false,
            });
            this.cfg.addProperty("status_html", {
                value: "",
            });
        },

        /**
         * Destroy the dialog and, if applicable, its progress overlay object.
         *
         * @method destroy
         */
        destroy: function() {
            if (this.progress_overlay) {
                if (this.progress_overlay.cfg) {
                    this.progress_overlay.destroy();
                }
                this.progress_overlay = null;
            }

            return Common_Dialog.superclass.destroy.apply(this, arguments);
        },

        // QUESTION: Why are these here? Need an explanation
        showMacGeckoScrollbars: function() {},
        hideMacGeckoScrollbars: function() {},
    });
    CPANEL.ajax.Common_Dialog = Common_Dialog;

    /**
     * Find the center point of an element. Assumes a rectangular element...
     * NOTE: may not be valid with new markup stuff for html5.
     * @method _find_el_center
     * @param  {DOMElement} el Element to find the center of...
     * @return {Number[]}    xy position of the element ? should this be a YUI Point?
     */
    var _find_el_center = function(el) {
        var xy = DOM.getXY(el);
        xy[0] += (parseFloat(DOM.getStyle(el, "width")) || el.offsetWidth) / 2;
        xy[1] += (parseFloat(DOM.getStyle(el, "height")) || el.offsetHeight) / 2;
        return xy;
    };


    /**
     * A shortcut class that ties into some CSS to make displaying error
     * popups quick and easy. This is sort of like YUI SimpleDialog.
     * @extends {Common_Dialog}
     * @constructor
     * @class
     * @param {[type]} id   [description]
     * @param {[type]} opts [description]
     */
    var Error_Dialog = function(id, opts) {
        if (id && (typeof id === "object")) {
            opts = id;
            id = DOM.generateId();
        } else if (!id) {
            id = DOM.generateId();
        }

        if (!opts) {
            opts = {};
        }

        YAHOO.lang.augmentObject(opts, {
            fixedcenter: true,
            width: "400px",
            buttons: [{
                text: LOCALE.maketext("OK"),
                handler: this.cancel,
                isDefault: true,
            }],
        });

        Error_Dialog.superclass.constructor.call(this, id /* , opts */ );
        this.beforeInitEvent.fire(Error_Dialog);
        DOM.addClass(this.element, "cjt_notice_dialog cjt_error_dialog");

        this.cfg.applyConfig(opts, true);

        this.beforeRenderEvent.subscribe(function() {
            if (!this.header || !this.header.innerHTML) {
                this.setHeader(CPANEL.widgets.Dialog.applyDialogHeader(LOCALE.maketext("Error")));
            }
        });
    };
    YAHOO.lang.extend(Error_Dialog, Common_Dialog);
    CPANEL.ajax.Error_Dialog = Error_Dialog;


    /*
     * A further extension from Common_Dialog that implements standard behaviors
     * like form templates, chaining API calls, etc. In theory, no interaction with
     * setHeader/setBody/etc. is necessary when using this class.
     *
     * TODO: Fix this so it can work with CPANEL.api "batch".
     *
     * @extends {Common_Dialog}
     * @constructor
     * @class
     * @param {[type]} id   [description]
     * @param {[type]} opts
     *   header_html
     *   clicked_element
     *   preload: an API call (see below) to run before showing the dialog box
     *   errors_in_notice_box: if true, use a Notice instead of an alternate dialog box for error notices. Default false.
     * TODO: Make this default to true, and remove the alternate workflow.
     *   show_status: boolean
     *   status_template: template (YAHOO.lang.substitute) for the submit status may be specified per API call as well
     *   form_template: template (YAHOO.lang.substitute) for the form HTML
     *   form_template_variables: object
     *   no_hide_after_success: Keep the dialog box in place after the last API call
     *   success_function: Executed after the last API call succeeds.
     *   success_status: Text (should it be a template?) for the last API call.
     *   success_notice_options: Options to pass to the success Notice
     *   api_calls: {Array}
     *       api_version
     *       api_module
     *       api_function
     *       data: for the function call itself (e.g. user, domain, etc.)
     *       api_data: sort/filter/paginate
     *       status_template: see above
     *       success_function: see above
     */
    var Common_Action_Dialog = function(id, opts) {
        if (!opts) {
            opts = {};
        }

        Common_Action_Dialog.superclass.constructor.call(this, id, opts);

        // Setup the title
        if (opts.header_html) {
            var header_html = opts.header_html;
            header_html = CPANEL.widgets.Dialog.applyDialogHeader(header_html);
            this.setHeader(header_html);
        }

        var the_dialog = this;

        if (opts.preload) {
            var loading_panel = new Progress_Panel();
            loading_panel.render(_masterContainerElement());

            if (opts.clicked_element) {
                loading_panel.show_from_source(opts.clicked_element);
            } else {
                loading_panel.show();
            }

            loading_panel.after_hideEvent.subscribe(loading_panel.destroy, loading_panel, true);

            var preload_copy = {
                application: opts.preload.api_application,
                module: opts.preload.api_module,
                func: opts.preload.api_function,
                data: opts.preload.data,
                api_data: opts.preload.api_data,
                callback: null,
            };

            var given_success = opts.preload.success_function;

            var preload_callback = CPANEL.ajax.build_callback(
                function() {
                    if (given_success) {
                        given_success.apply(the_dialog, arguments);
                    }

                    the_dialog.beforeShowEvent.subscribe(function center() {
                        the_dialog.beforeShowEvent.unsubscribe(center);
                        the_dialog.center();
                    });

                    var form_template = the_dialog.cfg.getProperty("form_template");
                    if (form_template) {
                        var template_vars = opts.form_template_variables;

                        var template_text = CPANEL.ajax.templates[form_template] || form_template;
                        the_dialog.form.innerHTML = YAHOO.lang.substitute(template_text, template_vars || {});
                    }
                }, {
                    current: loading_panel,
                    success: the_dialog,
                }, {
                    whm: opts.preload.api_application && (opts.preload.api_application === "whm") || CPANEL.is_whm(),
                }
            );

            preload_copy.callback = preload_callback;

            CPANEL.api(preload_copy);
        } else {
            if (opts.form_template) {
                var form_template_variables = opts.form_template_variables || {};

                var template_text = CPANEL.ajax.templates[opts.form_template] || opts.form_template;
                this.form.innerHTML = YAHOO.lang.substitute(template_text, form_template_variables);
            }
        }

        this.manualSubmitEvent.subscribe(function() {
            var api_calls = this.cfg.getProperty("api_calls");

            if (!api_calls) {
                return;
            }

            var index = 0;
            var _run_api_call_queue = function() {
                var cur_api_call = api_calls[index];
                var is_first_api_call = (index === 0);
                var is_last_api_call = (index === api_calls.length - 1);
                index++;

                var data;
                if (cur_api_call.data) {
                    if (cur_api_call.data instanceof Function) {
                        data = cur_api_call.data.apply(the_dialog);
                    } else {
                        data = cur_api_call.data;
                    }
                } else {
                    data = CPANEL.dom.get_data_from_form(the_dialog.form);
                }

                var callback_success;
                if (is_last_api_call) {
                    callback_success = function() {
                        if (cur_api_call.success_function) {
                            cur_api_call.success_function.apply(the_dialog, arguments);
                        }

                        if (the_dialog.cfg.getProperty("show_status")) {
                            var success_opts = the_dialog.cfg.getProperty("success_notice_options") || {};
                            if (!success_opts.content) {
                                success_opts.content = the_dialog.cfg.getProperty("success_status") || LOCALE.maketext("Success!");
                                if (!success_opts.level) {
                                    success_opts.level = "success";
                                }
                            }
                            the_dialog.notice = new Dynamic_Notice(success_opts);
                        }

                        if (the_dialog.cfg.getProperty("success_function")) {
                            the_dialog.cfg.getProperty("success_function").call(the_dialog);
                        }
                    };
                } else {
                    callback_success = function() {
                        if (cur_api_call.success_function) {
                            cur_api_call.success_function.apply(the_dialog, arguments);
                        }
                        _run_api_call_queue();
                    };
                }

                var status_template = opts.show_status && (cur_api_call.status_template || opts.status_template);
                if (status_template) {
                    var data_html = {};
                    for (var key in data) {
                        if (data.hasOwnProperty(key)) {
                            data_html[key] = String(data[key]).html_encode();
                        }
                    }

                    var status_html = YAHOO.lang.substitute(status_template, data_html);
                    if (is_first_api_call) {
                        the_dialog.progress_overlay.set_status_now(status_html);
                    } else {
                        the_dialog.progress_overlay.set_status(status_html);
                    }
                    the_dialog.progress_overlay.align();
                }

                var callback;
                if (the_dialog.cfg.getProperty("errors_in_notice_box")) {
                    callback = {
                        success: function() {
                            if (!the_dialog.cfg.getProperty("no_hide_after_success")) {
                                the_dialog.animated_hide();
                            }
                            return callback_success.apply(this, arguments);
                        },
                        failure: function(o) {
                            the_dialog.progress_overlay.hide();
                            the_dialog._api_error_notice = new CPANEL.widgets.Dynamic_Page_Notice({
                                replaces: the_dialog._api_error_notice,
                                container: CPANEL.Y(the_dialog.form).one(".details-error-notice"),
                                level: "error",
                                content: _make_failure_html(o),
                            });

                            if (cur_api_call.on_error) {
                                return cur_api_call.on_error.apply(this, arguments);
                            }
                        },
                    };
                } else {

                    // if we fail on anything but the first API call,
                    // then we go back to the page (and probably refresh the data)
                    var try_again_after_error = is_first_api_call && the_dialog.cfg.getProperty("try_again_after_error");

                    callback = CPANEL.ajax.build_callback(
                        callback_success, {
                            current: the_dialog,
                            after_error: try_again_after_error ? the_dialog : undefined,
                        }, {
                            on_error: cur_api_call.on_error,
                            whm: cur_api_call.api_application && (cur_api_call.api_application === "whm") || CPANEL.is_whm(),
                            keep_current_on_success: !is_last_api_call || the_dialog.cfg.getProperty("no_hide_after_success"),
                        }
                    );
                }

                var api_call = {
                    application: cur_api_call.api_application,
                    module: cur_api_call.api_module,
                    func: cur_api_call.api_function,
                    api_data: cur_api_call.api_data,
                    data: data,
                    callback: callback,
                };

                if (cur_api_call.api_version) {
                    api_call["version"] = cur_api_call.api_version;
                }

                CPANEL.api(api_call);
            };

            _run_api_call_queue();
        });

    };
    YAHOO.lang.extend(Common_Action_Dialog, Common_Dialog, {

        /**
         * [initDefaultConfig description]
         * @this Common_Action_Dialog
         * @method  initDefaultConfig
         */
        initDefaultConfig: function() {
            Common_Action_Dialog.superclass.initDefaultConfig.call(this);

            var extra_properties = [
                "header_html",
                "form_template",
                "form_template_variables",
                "clicked_element",
                "status_template",
                "api_calls",
                "preload",
                "no_hide_after_success",
                "success_function",
                "success_status",
                "success_notice_options", ["errors_in_notice_box", false],
                ["try_again_after_error", true],
            ];
            var that = this;
            extra_properties.forEach(function(p) {
                if (p instanceof Array) {
                    that.cfg.addProperty(p[0], {
                        value: p[1],
                    });
                } else {
                    that.cfg.addProperty(p, {
                        value: null,
                    });
                }
            });
        },

        /**
         * [animated_show description]
         * @this Common_Action_Dialog
         */
        animated_show: function() {
            var clicked_el = this.cfg.getProperty("clicked_element");
            if (clicked_el) {
                var motion = this.show_from_source(clicked_el);
                return motion;
            } else {
                this.show();
            }
        },

        /**
         * [animated_hide description]
         * @this Common_Action_Dialog
         */
        animated_hide: function() {
            var clicked_el = this.cfg.getProperty("clicked_element");
            if (clicked_el) {
                var motion = this.hide_to_point(clicked_el);
                return motion;
            } else {
                this.hide();
            }
        },
    });
    CPANEL.ajax.Common_Action_Dialog = Common_Action_Dialog;


    /**
     * Sets the current "default" values in a form's elements to their current value.
     * @method set_form_defaults
     * @param {HTMLForm} form [description]
     */
    CPANEL.dom.set_form_defaults = function(form) {
        var els = form.elements;
        for (var e = els.length - 1; e >= 0; e--) {
            var cur_el = els[e];

            if (cur_el.tagName.toLowerCase() === "select") {
                var opts = cur_el.options;
                for (var o = opts.length - 1; o >= 0; o--) {
                    var cur_opt = opts[o];
                    cur_opt.defaultSelected = cur_opt.selected;
                }
            } else {
                if ("defaultChecked" in cur_el) {
                    cur_el.defaultChecked = cur_el.checked;
                }
                if ("defaultValue" in cur_el) {
                    cur_el.defaultValue = cur_el.value;
                }
            }
        }
    };


    // fix for IE6 and IE7, which do not report the "value" attribute
    // of an <option> unless it is explicitly given
    var opt = document.createElement("option");
    opt.innerHTML = "test";
    var _option_elements_value_from_content = (opt.value !== opt.innerHTML);

    CPANEL.dom.TRIM_FORM_DATA = true;


    /**
     * Parses the elements in an HTML <form> element into a JavaScript object
     * that represents what would be submitted on HTTP submission.
     *
     * This fixes some bugs/quirks in YUI Dialog's .getData() method; in particular:
     *   * getData() errantly ignores single radio buttons.
     *   * getData() won't combine values of consecutive inputs with the same name.
     *   * getData() doesn't care which elements are disabled.
     *   * getData() puts all <select> values into arrays; this function takes a
     *      more general approach in that, if a form key only has one value, it's a
     *      string, and if the key appears more than once, the value is an array.
     *      This accurately models an HTTP form submission.
     *
     * @method  get_data_from_form
     * @param  {HTMLForm} form [description]
     * @param  {[type]} opts
     *    url_instead: Return an HTTP query string instead of a JavaScript object
     *    include_unchecked_checkboxes: Assigns this value to unchecked checkboxes.
     *        (instead of the default, i.e. omitting unchecked checkboxes)
     *
     * @return {[type]}      [description]
     */
    CPANEL.dom.get_data_from_form = function(form, opts) {
        if (typeof form === "string") {
            form = document.getElementById(form);
        }

        var _add_to_form_data, form_data;
        if (opts && opts.url_instead) {
            form_data = [];
            _add_to_form_data = function(new_name, new_value) {
                if (CPANEL.dom.TRIM_FORM_DATA && typeof new_value === "string") {
                    new_value = new_value.trim();
                }

                form_data.push(encodeURIComponent(new_name) + "=" + encodeURIComponent(new_value));
            };
        } else {
            form_data = {};
            _add_to_form_data = function(new_name, new_value) {
                if (CPANEL.dom.TRIM_FORM_DATA && typeof new_value === "string") {
                    new_value = new_value.trim();
                }

                if (new_name in form_data) {
                    if (YAHOO.lang.isArray(form_data[new_name])) {
                        form_data[new_name].push(new_value);
                    } else {
                        form_data[new_name] = [form_data[new_name], new_value];
                    }
                } else {
                    form_data[new_name] = new_value;
                }
            };
        }

        // It's important to iterate through in DOM order!
        var form_elements = form.elements;
        var elements_length = form_elements.length;
        for (var fc = 0; fc < elements_length; fc++) {
            var cur_control = form_elements[fc];
            if ("value" in cur_control &&
                "name" in cur_control &&
                cur_control.name && !cur_control.disabled
            ) {
                var control_name = cur_control.nodeName.toLowerCase();
                if (control_name === "input") {
                    var control_type = cur_control.type.toLowerCase();
                    switch (control_type) {
                        case "radio":
                            if (cur_control.checked) {
                                _add_to_form_data(cur_control.name, cur_control.value);
                            }
                            break;
                        case "checkbox":
                            if (cur_control.checked) {
                                _add_to_form_data(cur_control.name, cur_control.value);
                            } else if (opts && ("include_unchecked_checkboxes" in opts)) {
                                _add_to_form_data(cur_control.name, opts.include_unchecked_checkboxes);
                            }
                            break;
                        default:
                            _add_to_form_data(cur_control.name, cur_control.value);
                            break;
                    }
                } else if (control_name === "select") {
                    var cur_opt,
                        cur_value;

                    if (cur_control.selectedIndex !== -1) {
                        var cur_control_name = cur_control.name;
                        if (cur_control.multiple) {
                            var cur_options = cur_control.options;
                            var cur_options_length = cur_options.length;
                            for (var o = 0; o < cur_options_length; o++) {
                                cur_opt = cur_options[o];
                                if (cur_opt.selected && !cur_opt.disabled) {

                                    // This only happens in IE6 and IE7 (?),
                                    // so we might as well use innerText
                                    // instead of CPANEL.util.get_text_content()
                                    // and save a function call.
                                    // We also assume hasAttribute("value"),
                                    // which is safe in IE6/7.
                                    if (_option_elements_value_from_content && !cur_opt.getAttributeNode("value").specified) {
                                        cur_value = cur_opt.innerText;
                                    } else {
                                        cur_value = cur_opt.value;
                                    }
                                    _add_to_form_data(cur_control_name, cur_value);
                                }
                            }
                        } else {
                            cur_opt = cur_control.options[cur_control.selectedIndex];

                            // see above about IE6 and IE7
                            if (_option_elements_value_from_content && !cur_opt.getAttributeNode("value").specified) {
                                cur_value = cur_opt.innerText;
                            } else {
                                cur_value = cur_opt.value;
                            }
                            _add_to_form_data(cur_control_name, cur_value);
                        }
                    }
                } else if (control_name === "button") {
                    _add_to_form_data(cur_control.name, cur_control.value);
                } else if (control_name === "textarea") {

                    // Some old IE versions use Windows-style line breaks.
                    // The HTML 5 standard is to use UNIX line breaks
                    // for getting and setting a <textarea>'s "value" property.
                    // cf. HTML 5 standard, <textarea>, "API value" vs. "raw value"
                    _add_to_form_data(
                        cur_control.name,
                        cur_control.value.replace(/\r\n?/g, "\n")
                    );
                }
            }
        }

        if (opts && opts.url_instead) {
            return form_data.join("&");
        } else {
            return form_data;
        }
    };


    /**
     * Adds an arbitrary CSS style to the page
     * This is intentionally lazy loaded since the stylesheet may not
     * be defined at the load time preventing us from having to create
     * a style sheet use in the test statements.
     * @example
     *     add_styles([[".foo", "color:red"], [".bar","color:blue"]])
     * @method  add_styles
     * @deprecated Not used in code and has some issues with complexity and
     * which style sheet its applied to. Also there are alternatives in YUI2 and
     * YUI3 for this that are preferred. Do not use in new code.
     */
    var add_styles = function() {

        // NOTE: This is a bad design, should use distinct variable names or something
        // Bad to self modify outside scope.
        var stylesheet = document.styleSheets[0];
        if (!stylesheet) {
            document.head.appendChild(document.createElement("style"));
            stylesheet = document.styleSheets[0];
        }

        if ("insertRule" in stylesheet) { // W3C DOM
            add_styles = function(styles) {
                for (var s = 0; s < styles.length; s++) {
                    stylesheet.insertRule(styles[s][0] + " {" + styles[s][1] + "}", 0);
                }
            };
        } else { // IE
            add_styles = function(styles) {
                for (var s = 0; s < styles.length; s++) {
                    stylesheet.addRule(styles[s][0], styles[s][1], 0);
                }
            };
        }

        CPANEL.dom.add_styles = add_styles;
        return add_styles.apply(this, arguments);
    };


    /**
     * [add_style description]
     * @example
     *     add_style( "body", "background-color:gray" ),
     * @method  add_style
     * @deprecated Not used in code and has some issues with complexity and
     * which style sheet its applied to. Also there are alternatives in YUI2 and
     * YUI3 for this that are preferred. Do not use in new code.
     */
    CPANEL.dom.add_style = function(new_style) {
        return CPANEL.dom.add_styles.call(this, [new_style]);
    };

    /**
 * [add_styles description]
 * @example
 *     add_styles([[".foo", "color:red"], [".bar","color:blue"]])
 * @deprecated Not used in code and has some issues with complexity and
 * which style sheet its applied to. Also there are alternatives in YUI2 and
 * YUI3 for this that are preferred. Do not use in new code.
 @method  add_styles
 */
    CPANEL.dom.add_styles = add_styles;


    /**
     * Toggle disabled on an element such that it can "receive" a click
     * to re-enable it.
     * @method  smart_disable
     * @param  {[type]} el         [description]
     * @param  {[type]} to_disable [description]
     * @param  {[type]} on_enable  [description]
     * @return {[type]}            [description]
     */
    CPANEL.dom.smart_disable = function(el, to_disable, on_enable) {

        el = DOM.get(el);
        var overlay;
        if (typeof (to_disable) === "undefined") {
            to_disable = !el.disabled;
        }

        if (to_disable) {
            if (el._smart_disable_overlay) {
                return el._smart_disable_overlay;
            }

            el.disabled = true;

            overlay = new Smart_Disable_Overlay(el);
            overlay.render(el.parentNode);
            overlay.show();

            // TODO: Should this be a mousedown instead of onclick?
            overlay.element.onclick = function() {
                overlay.destroy();
                try { // IE throws an error in many cases when doing this
                    delete el._smart_disable_overlay;
                } catch (e) {
                    el._smart_disable_overlay = undefined;
                }
                el.disabled = false;
                if (on_enable) {
                    on_enable.apply(el);
                }
            };
            el._smart_disable_overlay = overlay;
        } else {
            el.disabled = false;
            overlay = el._smart_disable_overlay;
            try {
                delete el._smart_disable_overlay;
            } catch (e) {
                el._smart_disable_overlay = undefined;
            }

            if (overlay) {
                overlay.destroy();
            }
        }
        return overlay;
    };

    var _smart_disable_overlay_styles_needed = !!YAHOO.env.ua.ie;

    /**
     * A subclass of YUI Overlay that sizes to the passed-in "el"(ement)
     * and positions itself (via z-index) "above" that element.
     * This is useful for "catching" mouse clicks on disabled elements.
     *
     * @constructor
     * @class
     * @extends {YAHOO.widget.Overlay}
     * @param {DOM} el The HTML node to use as the reference element.
     */
    var Smart_Disable_Overlay = function(el) {

        // IE (all versions <= 10, at least) needs styles added
        // in order for smart_disable overlays to work.
        if (_smart_disable_overlay_styles_needed) {
            CPANEL.dom.add_style([
                ".cjt-smart-disable",
                "background-color:red;filter:alpha(opacity=0);opacity:0;",
            ]);
            _smart_disable_overlay_styles_needed = false;
        }

        var el_zIndex = parseFloat(CPANEL.dom.get_zindex(el));

        Smart_Disable_Overlay.superclass.constructor.call(this, DOM.generateId(), {
            iframe: false,
            zIndex: el_zIndex + 1,
            width: el.offsetWidth + "px",
            height: el.offsetHeight + "px",
            context: [el, "tl", "tl"],
        });

        // otherwise Mac Gecko will tab to it
        this.showEvent.subscribe(this.hideMacGeckoScrollbars, this, true);
        this.hideMacGeckoScrollbars = this.showMacGeckoScrollbars; // blackhole it

        DOM.addClass(this.element, "cjt-smart-disable");

        this._context_el = el;
    };
    YAHOO.lang.extend(Smart_Disable_Overlay, YAHOO.widget.Overlay, {
        align: function() {
            var el_zIndex = parseFloat(CPANEL.dom.get_zindex(this._context_el));
            this.cfg.setProperty("zIndex", el_zIndex + 1);
            this.cfg.setProperty("width", this._context_el.offsetWidth + "px");
            this.cfg.setProperty("height", this._context_el.offsetHeight + "px");
            Smart_Disable_Overlay.superclass.align.apply(this, arguments);
        },
        showMacGeckoScrollbars: function() {},
    });

    // Expose this publicly for other widgets, e.g., Combobox.
    CPANEL.dom.Smart_Disable_Overlay = Smart_Disable_Overlay;

    /**
     * methods for retrieving useful values instead of "auto", "transparent", etc.
     * [get_recursive_style description]
     * @method get_recursive_style
     * @param  {[type]} obj           [description]
     * @param  {[type]} property      [description]
     * @param  {[type]} recurse_if    [description]
     * @param  {[type]} default_value [description]
     * @return {[type]}               [description]
     */
    CPANEL.dom.get_recursive_style = function(obj, property, recurse_if, default_value) {
        var cur_obj = DOM.get(obj);
        var cur_value;

        do {
            cur_value = DOM.getComputedStyle(cur_obj, property);
        } while ((cur_value === recurse_if) && (cur_obj = cur_obj.parentNode) && (cur_obj !== document));

        if (!cur_obj || (cur_value === recurse_if)) {
            cur_value = default_value;
        }

        return cur_value;
    };

    /**
     * [get_background_color description]
     * @method get_background_color
     * @param  {[type]} obj [description]
     * @return {[type]}     [description]
     */
    CPANEL.dom.get_background_color = function(obj) {
        return CPANEL.dom.get_recursive_style(obj, "backgroundColor", "transparent");
    };

    /**
     * [get_zindex description]
     * @method get_zindex
     * @param  {[type]} obj [description]
     * @return {[type]}     [description]
     */
    CPANEL.dom.get_zindex = function(obj) {
        return CPANEL.dom.get_recursive_style(obj, "zIndex", "auto", 0);
    };


    /**
     * streamline setting up disable/enable relationships among elements groups
     * that are toggled with radio buttons.
     *
     * each group is: {
     *       radio: HTMLElement, - required
     *       inputs: [HTMLElement],
     *       listeners: [HTMLElement] - optional, listens for click to enable
     *       disablees: [HTMLElement] - optional, sets/removes "disabled" class
     *    }
     *
     * This also accepts (form, start_index/el, end_index/el) and will parse them.
     *
     * @constructor
     * @class
     * @extends {YAHOO.widget.Overlay}
     */
    CPANEL.ajax.Grouped_Input_Set = function() {

        // ISSUE: No common argument set defined, bad constructor
        var groups, first_arg = arguments[0];
        if ((typeof first_arg === "string") || first_arg.tagName && first_arg.tagName.toLowerCase() === "form") {
            groups = CPANEL.ajax.Grouped_Input_Set.make_groups_from_form.apply(this, arguments);
        } else {
            groups = first_arg;
        }

        this._groups = groups;
        var the_set = this;
        var register_group_listeners = function(this_group) {
            EVENT.on(this_group.listeners, "click", function() {
                if (!this_group.radio.checked) {
                    this_group.radio.checked = true;
                    the_set.refresh();
                }
            });
        };
        for (var g = 0, l = groups.length; g < l; g++) {
            var group = groups[g];
            YAHOO.util.Event.on(group.radio, "click", this.refresh, this, true);

            if (group.listeners) {
                register_group_listeners(group);
            }
        }
        this.refresh();
    };

    var FORM_ELEMENTS = {
        button: 1,
        input: 1,
        select: 1,
        textarea: 1,
    };

    /**
     * [make_groups_from_form description]
     * @method  make_groups_from_form
     * @static
     * @param  {[type]} form     [description]
     * @param  {[type]} start_el can be elements or indexes of form.elements
     * @param  {[type]} end_el   can be elements or indexes of form.elements
     * @return {[type]}          [description]
     */
    CPANEL.ajax.Grouped_Input_Set.make_groups_from_form = function(form, start_el, end_el) {

        form = DOM.get(form);

        var form_labels_with_for = CPANEL.Y(form).all("label[for]");
        var labels_with_for = {};
        var cur_label;
        for (var l = form_labels_with_for.length - 1; l >= 0; l--) {
            cur_label = form_labels_with_for[l];
            labels_with_for[cur_label.htmlFor] = cur_label;
        }

        // form.elements is not guaranteed to be in DOM order, e.g. WebKit 534.24
        // This also gives us an array rather than an HTML collection, which is nice.
        // TODO: Would CPANEL.Y(form).all("button, input, select, textarea") work here?
        var els = DOM.getElementsBy(
            function(el) {
                return (el.tagName.toLowerCase() in FORM_ELEMENTS);
            },
            undefined,
            form
        );

        var cur_el, i;
        if (typeof start_el !== "undefined" && typeof start_el !== "number") {
            if (typeof start_el === "string") {
                start_el = DOM.get(start_el);
            }

            if (start_el) {
                i = 0;

                while ((cur_el = els[i]) && (cur_el !== start_el)) {
                    i++;
                }

                if (!cur_el) {
                    return;
                }
                start_el = i;
            }
        }
        if (!start_el) {
            start_el = 0;
        }

        if (typeof end_el !== "undefined" && typeof end_el !== "number") {
            if (typeof end_el === "string") {
                end_el = DOM.get(end_el);
            }
            if (end_el) {
                i = start_el || 0;
                i++;
                while ((cur_el = els[i]) && (cur_el !== end_el)) {
                    i++;
                }

                if (!cur_el) {
                    return;
                }
                end_el = i;
            }
        }

        var groups = [];
        var cur_group;

        // ISSUE: LOOP TEST SHOULD NOT HAVE SIDE EFFECTS
        for (var e = start_el;
            (cur_el = els[e]) && cur_el; e++) {
            if (end_el && e > end_el) {
                break;
            }

            if (cur_el.type && cur_el.type.toLowerCase() === "radio") {
                if (cur_group) {
                    groups.push(cur_group);
                }
                cur_group = {
                    radio: cur_el,
                    inputs: [],
                    listeners: [],
                };
            } else if (cur_group) {
                cur_group.inputs.push(cur_el);
                var label = DOM.getAncestorByTagName(cur_el, "label");

                if (!label && cur_el.id) {
                    label = labels_with_for[cur_el.id];
                }

                if (label && (cur_group.listeners.indexOf(label) === -1)) {
                    cur_group.listeners.push(label);
                }
            }
        }
        if (cur_group) {
            groups.push(cur_group);
        }

        return groups;
    };

    YAHOO.lang.augmentObject(CPANEL.ajax.Grouped_Input_Set.prototype, {

        // TODO: Add documentation
        _groups: null,

        // TODO: Add documentation
        get_groups: function() {
            return this._groups && this._groups.slice(0);
        },

        // TODO: Add documentation
        refresh: function() {
            var enabled;

            for (var g = 0; g < this._groups.length; g++) {
                var group = this._groups[g];

                if (group.radio.checked) {
                    enabled = group;
                    this._enable_group(group);
                } else {
                    this._disable_group(group);
                }
            }

            if (this.onrefresh) {
                this.onrefresh.call(this, enabled);
            }
        },

        // TODO: Add documentation
        align: function() {
            var do_align = function(o) {
                o.align();
            };
            this.get_groups().forEach(function(g) {
                if (g.disabled) {
                    g.smart_disable_overlays.forEach(do_align);
                }
            });
        },

        // TODO: Add documentation
        onrefresh: null,

        // TODO: Add documentation
        _enable_group: function(group) {
            if (group.inputs) {
                for (var i = 0; i < group.inputs.length; i++) {
                    CPANEL.dom.smart_disable(group.inputs[i], false);
                }
            }
            if (group.noninputs) {
                for (var n = 0; n < group.noninputs.length; n++) {
                    DOM.removeClass(group.noninputs[n], "disabled");
                }
            }
            group.disabled = false;
            group.smart_disable_overlays = null;
        },

        // TODO: Add documentation
        _disable_group: function(group) {
            var the_set = this;
            group.disabled = true;
            group.smart_disable_overlays = [];
            if (group.inputs) {
                var on_enable = function() {
                    group.radio.checked = true;
                    the_set.refresh();
                    this.focus();

                    // For some reason, setSelectionRange is a no-op
                    // for number-type inputs. It *does* work, though,
                    // to convert the input to text, do the selection,
                    // then switch back to number. That’s what this does.
                    //
                    const oldType = this.type;
                    if (oldType !== "text") {
                        this.type = "text";
                    }
                    this.setSelectionRange(0, this.value.length);
                    if (oldType !== "text") {
                        this.type = oldType;
                    }
                };
                for (var i = 0; i < group.inputs.length; i++) {
                    var ov = CPANEL.dom.smart_disable(group.inputs[i], true, on_enable);
                    group.smart_disable_overlays.push(ov);
                }

            }
            if (group.noninputs) {
                for (var n = 0; n < group.noninputs.length; n++) {
                    DOM.addClass(group.noninputs[n], "disabled");
                }
            }
        },
    });

    /**
     * Interactive notifications, e.g. for growl-type AJAX call success notices
     * opts:
     *  fade_delay: if true, # of seconds after show() to destroy() (default: 5)
     *  closable {Boolean} whether clicking will close it (class "cjt-notice-closable")
     *  closable_tooltip {String} tooltip text for a closable Dynamic_Notice element
     * @constructor
     * @class
     * @extends {CPANEL.widgets.Notice}
     * TODO: Parameters???
     */
    var Dynamic_Notice = function() {
        Dynamic_Notice.superclass.constructor.apply(this, arguments);
    };

    // Static constants
    Dynamic_Notice.DEFAULT_CONTAINER_ID = "cjt_dynamicnotice_container";
    Dynamic_Notice.CLASS = "cjt-dynamicnotice";

    YAHOO.lang.extend(Dynamic_Notice, CPANEL.widgets.Notice, {

        /**
         * [reset_fade_timeout description]
         * @return {[type]} [description]
         */
        reset_fade_timeout: function() {
            this.config_fade_delay(this.cfg.getProperty("fade_delay"));
        },

        /**
         * [init description]
         * @param  {[type]} el   [description]
         * @param  {[type]} opts [description]
         * @return {[type]}      [description]
         */
        init: function(el, opts) {
            Dynamic_Notice.superclass.init.call(this, el /* , opts */ );

            this.beforeInitEvent.fire(Dynamic_Notice);

            DOM.addClass(this.element, Dynamic_Notice.CLASS);

            if (opts) {
                this.cfg.applyConfig(opts, true);
                this.render();
            }

            this.initEvent.fire(Dynamic_Notice);
        },

        /**
         * [initDefaultConfig description]
         * @return {[type]} [description]
         */
        initDefaultConfig: function() {
            Dynamic_Notice.superclass.initDefaultConfig.call(this);

            this.cfg.addProperty("closable", {
                value: true,
                handler: this.config_closable,
            });

            this.cfg.addProperty("closable_tooltip", {
                value: LOCALE.maketext("Click to close."),
            });

            this.cfg.addProperty("fade_delay", {
                value: 5,
                handler: this.config_fade_delay,
            });
        },

        config_closable: function(type, args, obj) {
            if (!this.body) {
                var the_args = arguments;
                this.beforeShowEvent.subscribe(function configger() {
                    this.beforeShowEvent.unsubscribe(configger);
                    this.config_closable.apply(this, the_args);
                });
                return;
            }

            var closable = args[0];
            var tooltip = this.cfg.getProperty("closable_tooltip");
            if (closable) {
                DOM.addClass(this.element, "cjt-notice-closable");
                this._click_listener = EVENT.on(this.body, "mousedown", function(e) {
                    var target = EVENT.getTarget(e);
                    if (YAHOO.widget.Panel.FOCUSABLE.indexOf(target.tagName.toLowerCase()) === -1) {
                        this.fade_out();
                    }
                }, this, true);
                if (tooltip) {
                    this._former_tooltip = this.body.title;
                    this.body.title = tooltip;
                }
            } else {
                DOM.removeClass(this.element, "cjt-notice-closable");
                if (this._click_listener) {
                    EVENT.removeListener(this.body, "mousedown", this._click_listener);
                    delete this._click_listener;
                }
                if (tooltip && this.body.title === tooltip && ("_former_tooltip" in this)) {
                    this.body.title = this._former_tooltip;
                    delete this._former_tooltip;
                }
            }
        },

        /**
         * [config_fade_delay description]
         * @param  {[type]} type [description]
         * @param  {[type]} args [description]
         * @param  {[type]} obj  [description]
         * @return {[type]}      [description]
         */
        config_fade_delay: function(type, args /* , obj */ ) {
            this._cancel_fade();

            var fade_delay = args[0];
            if (fade_delay) {
                var that = this;
                this._fade_timeout = window.setTimeout(function() {
                    that.fade_out();
                }, fade_delay * 1000);
            }
        },

        /**
         * [destroy description]
         * @return {[type]} [description]
         */
        destroy: function() {
            if (this._fade_timeout) {
                window.clearTimeout(this._fade_timeout);
                delete this._fade_timeout;
            }

            // Check to be sure the element is still in the document since
            // we have multiple things destroy()ing Notice instances, and those
            // destroy()ers are not necessarily aware of each other.
            if (this.cfg) {
                Dynamic_Notice.superclass.destroy.apply(this, arguments);
            }
        },

        /**
         * [_cancel_fade description]
         * @return {[type]} [description]
         */
        _cancel_fade: function() {
            if (this._fade_timeout) {
                window.clearTimeout(this._fade_timeout);
                delete this._fade_timeout;
            }
        },

        /**
         * [render description]
         * @return {[type]} [description]
         */
        render: function() {
            if (!Dynamic_Notice.notice_container) {
                var notice_container = document.createElement("div");
                notice_container.id = "cjt_dynamicnotice_container";
                _masterContainerElement().appendChild(notice_container);
                Dynamic_Notice.notice_container = notice_container;
                DOM.addClass(notice_container, "cjt-dynamicnotice-container");
            }

            var container = this.cfg.getProperty("container");
            if (container) {
                DOM.addClass(container, "cjt-dynamicnotice-container");
            } else {
                container = Dynamic_Notice.notice_container;
            }

            var ret = Dynamic_Notice.superclass.render.call(this, container);

            return ret;
        },
    });
    CPANEL.ajax.Dynamic_Notice = Dynamic_Notice;


    /**
     * Underlying object to help with custom tooltips display. Do not call directly as
     * these are not single instance, please use Tooltip_Notice.toggleToolTip()
     * @method Tooltip_Notice
     * @param [String|HTMLElement] targetEl element or id of element to load from, must have a title attribute with the text to show.
     * @param [String] headerText optional string to display in the title, will be the localized version of "Notice" if not defined.
     * @param [String] id optional id of the dialog, will be generated if not defined.
     * @param [Hash]   opts optional options to pass to the notice.
     *     overlayCorner : [tr, tl, br, bl]
     *     contextCorner : [tr, tl, br, bl]
     *     offsetX : [Number] Pixel to offest in the x, may be negative or positive.
     *     offsetY : [Number] Pixel to offset in the y, may be negative or positive.
     *     format : [Hash] contains formatting options.
     *          processText : [Function] Optional formatting function to customize formatting.
     *          highlightWords : [Array] Words to highlight.
     *          highlightClassName : [String] CSS class name to apply to highlighted words. */
    var Tooltip_Notice = function(targetEl, headerTxt, id, opts) {

        // Setup the options
        if (!opts) {
            opts = {};
        }

        YAHOO.lang.augmentObject(opts, Tooltip_Notice.standardOptions);

        // Setup the render context
        if (!opts.context) {
            opts.context = [
                targetEl,

                // Overlay corner position is bottom right unless overridden
                opts.overlayCorner ? opts.overlayCorner : "tl",

                // Context corner position is top left unless overridden
                opts.contextCorner ? opts.contextCorner : "tr", [ // Perform the context on these events
                    "beforeShow",
                    "windowResize",
                ],
                [

                    // Offest 2px down unless overridden
                    opts.offsetX ? opts.offsetX : 10,

                    // Offest 2px right unless overridden
                    opts.offsetY ? opts.offsetY : -5,
                ],
            ];
        }

        // Give it an id if one is not provided
        if (!id) {
            id = DOM.generateId();
        }

        // Create the notice
        var noticebox = new CPANEL.ajax.Common_Dialog(id, opts);

        var text = targetEl.title;

        // cf. HTML 5, section 3.2.3.2
        var displayText = text.html_encode().replace(/\n/g, "<br>");

        if (opts.format) {
            var OF = opts.format;
            OF.highlightClassName = OF.highlightClassName || Tooltip_Notice.DEFAULT_TOOLTIP_HIGHLIGHT_CLASS_NAME;
            if (OF.processText) {
                try {
                    displayText = OF.processText(displayText, OF.highlightWords, OF.highlightClassName);
                } catch (ex) {

                    // Ignore
                }
            } else {
                if (OF.highlightWords && OF.highlightWords.length) {
                    var template = "<span class='{class}'>{word}</span>".replace("{class}", OF.highlightClassName);
                    for (var i = 0, l = OF.highlightWords.length; i < l; i++) {
                        var word = OF.highlightWords[i];
                        try {
                            displayText = displayText.replace(word, template.replace("{word}", word));
                        } catch (ex) {

                            // Ignore
                        }
                    }
                }
            }
        }
        noticebox.setBody(displayText);

        // Save the title and clear it so we don't get the
        // browser tooltip showing while the custom one is open.
        noticebox.restoreTitle = text;
        targetEl.title = "";

        // Setup the title
        var headerHTML = headerTxt ? headerTxt : LOCALE.maketext("Notice");
        headerHTML = CPANEL.widgets.Dialog.applyDialogHeader(headerHTML);
        noticebox.setHeader(headerHTML);

        // Setup ok button
        noticebox.cfg.getProperty("buttons")[0].text = LOCALE.maketext("OK");
        noticebox.submit = function() {
            this.hide();
            if (this.restoreTitle) {
                targetEl.title = this.restoreTitle;
            }
            delete Tooltip_Notice.active[targetEl.id];
        };

        this.close = function() {
            noticebox.submit();
        };

        // Omit the cancel button
        noticebox.cfg.getProperty("buttons").pop();

        DOM.addClass(noticebox.element, "cjt_notice_dialog cjt_info_dialog");

        noticebox.beforeShowEvent.subscribe(noticebox.center, noticebox, true);
        noticebox.show_from_source(targetEl);
    };

    /**
     * Predefined rules for displaying a Tooltip_Notice.
     * @member [Hash] Tooltip_Notice.standardOptions */
    Tooltip_Notice.standardOptions = {
        modal: false,
        width: "300px",
        fixedcenter: false,
    };

    /**
     * Default class name used in word high-lighting
     * @static
     * @member [String] Tooltip_Notice.DEFAULT_TOOLTIP_HIGHLIGHT_CLASS_NAME */
    Tooltip_Notice.DEFAULT_TOOLTIP_HIGHLIGHT_CLASS_NAME = "cjt-highlight-word";


    /**
     * Simple wrapper to make calling show only one tooltips easy to display.
     * @method Tooltip_Notice.toggleToolTip
     * @param [String|HTMLElement] targetEl element or id of element to load from, must have a title attribute with the text to show.
     * @param [String] headerText optional string to display in the title, will be the localized version of "Notice" if not defined.
     * @param [String] id optional id of the dialog, will be generated if not defined.
     * @param [Hash]   opts optional options to pass to the notice.
     *     overlayCorner : [tr, tl, br, bl]
     *     contextCorner : [tr, tl, br, bl]
     *     offsetX : [Number] Pixil to offest in the x, may be negative or positive.
     *     offsetY : [Number] Pixil to offset in the y, may be negative or positive. */
    Tooltip_Notice.toggleToolTip = function(targetEl, headerText, id, opts) {

        // Element must have an id, so give it one if needed
        if (!targetEl.id) {
            targetEl.id = DOM.generateId();
        }

        // See if this is an open or close click
        if (!Tooltip_Notice.active[targetEl.id]) {
            var tooltip = new Tooltip_Notice(targetEl, headerText, id, opts);
            Tooltip_Notice.active[targetEl.id] = tooltip;
        } else {
            Tooltip_Notice.active[targetEl.id].close();
        }
    };


    /**
     * Static array of the actively displayed tooltips on the window.
     * @member [Array] Tooltip_Notice.active Array of the id's of the active tooltips. Used to track which ones are currently visible.*/
    Tooltip_Notice.active = [];

    // Register the functions.
    CPANEL.ajax.toggleToolTip = Tooltip_Notice.toggleToolTip;

})(window);
