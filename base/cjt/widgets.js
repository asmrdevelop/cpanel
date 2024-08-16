/*
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {

    // TODO: This stuff should go in a markup island; however, there isn't currently
    // a template that CJT can always rely on being there, so for now this is going
    // into JS directly.
    var close_x = (YAHOO.env.ua.ie && (YAHOO.env.ua.ie < 9)) ?
        "X" :

        // NOTE: The final <rect> is so that the entire <svg> surface is a single
        // target for DOM clicks. Otherwise, the pixel-shift that CSS does with this
        // will make the mousedown and mouseup have different targets, which
        // prevents "click" from being triggered.
        '<svg width="100%" height="100%" xmlns="http://www.w3.org/2000/svg"><line stroke="currentColor" stroke-width="1.5" stroke-linecap="round" x1="35%" y1="35%" x2="65%" y2="65%" /><line stroke="currentColor" stroke-width="1.5" stroke-linecap="round" x1="35%" y1="65%" x2="65%" y2="35%" /><rect width="100%" height="100%" style="fill:transparent;opacity:1.0" /></svg>';

    var closeButton = YAHOO.lang.substitute(
        "<a class='cjt-dynamic-pagenotice-close-button' href='javascript:void(0)' title=\"{title}\">{close_x}</a>", {
            title: LOCALE.maketext("Click to close."),
            close_x: close_x
        }
    );

    // check to be sure the CPANEL global object already exists
    if (typeof CPANEL == "undefined" || !CPANEL) {
        alert("You must include the CPANEL global object before including widgets.js!");
    } else {

        /**
        The widgets module contains widget objects used in cPanel.
        @module widgets
*/

        /**
        The widgets class contains widget objects used in cPanel.
        @class widgets
        @namespace CPANEL
        @extends CPANEL
*/
        CPANEL.widgets = {

            // LEGACY USE ONLY.
            Text_Input_Placeholder: function(context_el, text, before_show) {
                context_el = DOM.get(context_el);

                var id = context_el.id;
                if (id) {
                    id += "_cjt-text-input-placeholder";
                } else {
                    id = DOM.generateId();
                }

                // adjust the overlay for the context element border and padding
                var region = CPANEL.dom.get_inner_region(context_el);
                var xy_offset = [
                    region.padding.left + region.border.left,
                    region.padding.top + region.border.top
                ];

                var opts = {
                    context: [context_el, "tl", "tl", ["beforeShow", "windowResize"], xy_offset],
                    width: region.width + "px",
                    height: region.height + "px",
                    zIndex: parseInt(DOM.getStyle(context_el, "z-index"), 10) + 1,
                    visible: false
                };

                arguments.callee.superclass.constructor.call(this, id, opts);


                var render_parent = context_el.parentNode;
                if (render_parent.nodeName.toLowerCase() === "label") {
                    render_parent = render_parent.parentNode;
                }

                this.render(render_parent);

                var overlay = this;
                this.element.onclick = function() {
                    overlay.hide();
                    context_el.focus();
                };

                DOM.addClass(this.element, "cjt-text-input-placeholder");

                var helper_text = text || "";
                this.setBody(helper_text);

                YAHOO.util.Event.addListener(context_el, "focus", function() {
                    overlay.hide();
                });
                YAHOO.util.Event.addListener(context_el, "blur", function() {
                    if (!this.value.trim()) {
                        overlay.show();
                    }
                });

                if (before_show) {
                    before_show.apply(this);
                }

                if (!context_el.value.trim()) {
                    this.show();
                }
            },

            // show a progress bar
            progress_bar: function(el, percentage, text, options) {

                // just a legacy thing so I don't have to backmerge a change for 11.25
                if (options == '{"inverse_colors":"true"}') {
                    options = {
                        inverse_colors: true
                    };
                }

                if (!options) {
                    options = {};
                }
                if (!options.text_style) {
                    options.text_style = "";
                }
                if (!options.inverse_colors) {
                    options.inverse_colors = false;
                }
                if (!options.one_color) {
                    options.one_color = false;
                }
                if (!options.return_html) {
                    options.return_html = false;
                }

                // clean the percentage
                percentage = parseInt(percentage, 10);
                if (percentage < 0) {
                    percentage = 0;
                }
                if (percentage > 100) {
                    percentage = 100;
                }

                // get the element
                if (options.return_html === false) {
                    el = YAHOO.util.Dom.get(el);
                }

                // set the color of the bar
                var color;
                if (percentage >= 0) {
                    color = "#FF0000";
                } // red
                if (percentage >= 20) {
                    color = "#FF9837";
                } // orange
                if (percentage >= 40) {
                    color = "#F1FF4D";
                } // yellow
                if (percentage >= 60) {
                    color = "#C5FF00";
                } // chartreuse
                if (percentage >= 80) {
                    color = "#8FFF00";
                } // lt green

                if (options.inverse_colors) {
                    if (percentage >= 0) {
                        color = "#8FFF00";
                    } // lt green
                    if (percentage >= 20) {
                        color = "#C5FF00";
                    } // chartreuse
                    if (percentage >= 40) {
                        color = "#F1FF4D";
                    } // yellow
                    if (percentage >= 60) {
                        color = "#FF9837";
                    } // orange
                    if (percentage >= 80) {
                        color = "#FF0000";
                    } // red
                }

                if (options.one_color) {
                    color = options.one_color;
                }

                var height = "100%";

                // BROWSER-SPECIFIC CODE: manually get the height from the parent element for ie6
                if (YAHOO.env.ua.ie == 6 && options.return_html === false) {
                    var div_region = YAHOO.util.Region.getRegion(el);
                    height = div_region.height + "px";
                }

                var html;

                // container div with relative positioning, height/width set to 100% to fit the container element
                html = '<div class="cpanel_widget_progress_bar" title="' + percentage + '%" style="position: relative; width: 100%; height: ' + height + '; padding: 0px; margin: 0px; border: 0px">';

                // text div fits the width and height of the container div and has it's text vertically centered; has an opaque background and z-index of 1 to put it above the color bar div
                if (text) {
                    html += '<div style="position: absolute; left: 0px; width: 100%; height: ' + height + '; padding: 0px; margin: 0px; border: 0px; z-index: 1; background-image: url(\'/cPanel_magic_revision_0/cjt/images/1px_transparent.gif\')">';
                    html += '<table style="width: 100%; height: 100%; padding: 0px; margin: 0px; border: 0px">';
                    html += '<tr><td valign="middle" style="padding: 0px; margin: 0px; border: 0px;">'; // use a table to vertically center for greatest compatability
                    html += '<div style="width: 100%; ' + options.text_style + '">' + text + "</div>";
                    html += "</td></tr></table>";
                    html += "</div>";
                }

                // color bar div fits the width and height of the container div and width changes depending on the strength of the password
                if (percentage > 0) {
                    html += '<div style="position: absolute; left: 0px; top: 0px; width: ' + percentage + "%; height: " + height + "; background-color: " + color + '; padding: 0px; margin: 0px; border: 0px"></div>';
                }

                // close the container div
                html += "</div>";

                // save the percent information in a hidden div
                if (options.return_html === false) {
                    html += '<div class="cpanel_widget_progress_bar_percent" style="display: none">' + percentage + "</div>";
                }

                if (options.return_html === true) {
                    return html;
                }

                el.innerHTML = html;
            },

            build_progress_bar: function(percentage, text, options) {


            },

            // variable used to hold the status box overlay widget
            status_box: null,

            // variable used to hold the status box overlay's timeout
            status_box_timeout: null,

            status: function(message, class_name) {

                // if the status bar is currently being displayed clear the previous timeout
                clearTimeout(this.status_box_timeout);

                var options = {
                    zIndex: 1000,
                    visible: true,
                    effect: {
                        effect: YAHOO.widget.ContainerEffect.FADE,
                        duration: 0.25
                    }
                };
                this.status_box = new YAHOO.widget.Overlay("cpanel_status_widget", options);
                this.status_box.setBody('<span class="cpanel_status_widget_message">' + message + "</span>");

                var footer = '<br /><div style="width: 100%; text-align: right; font-size: 10px">';
                footer += LOCALE.maketext("Click to close.") + ' [<span id="cpanel_status_widget_countdown">10</span>]';
                footer += "</div>";
                this.status_box.setFooter(footer);
                this.status_box.render(document.body);

                YAHOO.util.Dom.removeClass("cpanel_status_widget", "cpanel_status_success");
                YAHOO.util.Dom.removeClass("cpanel_status_widget", "cpanel_status_error");
                YAHOO.util.Dom.removeClass("cpanel_status_widget", "cpanel_status_warning");
                if (class_name) {
                    YAHOO.util.Dom.addClass("cpanel_status_widget", "cpanel_status_" + class_name);
                } else {
                    YAHOO.util.Dom.addClass("cpanel_status_widget", "cpanel_status_success");
                }

                var hide_me = function() {
                    CPANEL.widgets.status_box.hide();
                    clearTimeout(CPANEL.widgets.status_box_timeout);
                };

                YAHOO.util.Event.on("cpanel_status_widget", "click", hide_me);

                var second_decrease = function() {
                    var seconds_el = YAHOO.util.Dom.get("cpanel_status_widget_countdown");
                    if (seconds_el) {
                        var seconds = parseInt(seconds_el.innerHTML, 10);

                        // close the window when the countdown is finished
                        if (seconds === 0) {
                            hide_me();
                        } else { // else decrease the counter and set a new timeout
                            seconds_el.innerHTML = seconds - 1;
                            CPANEL.widgets.status_box_timeout = setTimeout(second_decrease, 1000);
                        }
                    }
                };

                // initialize the first timeout
                this.status_box_timeout = setTimeout(second_decrease, 1000);
            },

            // status_bar widget
            /*
            var status_bar_options = {
            duration : integer,
            callbackFunc : function literal,
            hideCountdown : true,
            noCountdown : true,
            rawHTML : HTML string
            }
            */
            status_bar: function(el, style, title, message, options) {
                var duration = 10;
                if (style == "error") {
                    duration = 0;
                }

                // options
                var callback_func = function() {};
                var hide_countdown = false;
                var countdown = true;
                if (duration === 0) {
                    countdown = false;
                }
                var raw_html = false;
                if (options) {
                    if (options.duration) {
                        duration = options.duration;
                    }
                    if (options.callbackFunc) {
                        if (typeof (options.callbackFunc) == "function") {
                            callback_func = options.callbackFunc;
                        }
                    }
                    if (options.hideCountdown) {
                        hide_countdown = true;
                    }
                    if (options.rawHTML) {
                        raw_html = options.rawHTML;
                    }
                    if (options.noCountdown) {
                        countdown = false;
                    }
                }

                el = YAHOO.util.Dom.get(el);
                if (!el) {
                    alert("Error in CPANEL.widgets.status_bar: '" + el + "' does not exist in the DOM.");
                    return;
                }

                var hide_bar = function() {
                    CPANEL.animate.slide_up(el, function() {
                        el.innerHTML = "";
                        callback_func();
                        CPANEL.align_panels_event.fire();
                    });
                };

                // set the style class
                YAHOO.util.Dom.removeClass(el, "cjt_status_bar_success");
                YAHOO.util.Dom.removeClass(el, "cjt_status_bar_error");
                YAHOO.util.Dom.removeClass(el, "cjt_status_bar_warning");
                YAHOO.util.Dom.addClass(el, "cjt_status_bar_" + style);

                var status = "";
                if (raw_html === false) {
                    status = CPANEL.icons.success;
                    if (style == "error") {
                        status = CPANEL.icons.error;
                    }
                    if (style == "warning") {
                        status = CPANEL.icons.warning;
                    }

                    status += " <strong>" + title + "</strong>";
                    if (message) {
                        if (message !== "") {
                            status += '<div style="height: 5px"></div>';
                            status += CPANEL.util.convert_breaklines(message);
                        }
                    }
                } else {
                    status = raw_html;
                }

                var countdown_div = "";
                if (countdown === true) {
                    countdown_div = '<div class="cjt_status_bar_countdown"';
                    if (hide_countdown === true) {
                        countdown_div += ' style="display: none"';
                    }

                    var countdown_inner = LOCALE.maketext("Click to close.") + " {durationspan}"; // See first post in rt 62397, in the meantime the text will be localized
                    countdown_inner = countdown_inner.replace("{durationspan}", '[<span id="' + el.id + '_countdown">' + duration + "</span>]");

                    countdown_div += ">" + countdown_inner + "</div>";
                } else {
                    countdown_div = '<div class="cjt_status_bar_countdown">' + LOCALE.maketext("Click to close.") + "</div>";
                }

                el.innerHTML = status + countdown_div;

                CPANEL.animate.slide_down(el, function() {

                    // give the status bar element "hasLayout" property in IE
                    if (YAHOO.env.ua.ie > 5) {
                        YAHOO.util.Dom.setStyle(el, "zoom", "1");
                    }
                    if (countdown === true) {
                        CPANEL.util.countdown(el.id + "_countdown", hide_bar);
                    }
                    CPANEL.align_panels_event.fire();
                });

                YAHOO.util.Event.on(el, "click", hide_bar);
            },

            collapsible_header: function(header_el, div_el, before_show, after_show, before_hide, after_hide) {

                // grab the DOM elements
                header_el = YAHOO.util.Dom.get(header_el);
                div_el = YAHOO.util.Dom.get(div_el);

                if (!header_el) {
                    alert("Error in CPANEL.widgets.collapsable_header: header_el '" + header_el + "' does not exist in the DOM.");
                    return;
                }
                if (!div_el) {
                    alert("Error in CPANEL.widgets.collapsable_header: div_el '" + div_el + "' does not exist in the DOM.");
                    return;
                }

                // set up the functions if they are not defined
                if (!before_show || typeof (before_show) != "function") {
                    before_show = function() {};
                }
                if (!after_show || typeof (after_show) != "function") {
                    after_show = function() {};
                }
                if (!before_hide || typeof (before_hide) != "function") {
                    before_hide = function() {};
                }
                if (!after_hide || typeof (after_hide) != "function") {
                    after_hide = function() {};
                }

                // toggle function
                var toggle_function = function() {

                    // if the display is none, expand the div
                    if (YAHOO.util.Dom.getStyle(div_el, "display") == "none") {
                        before_show();
                        YAHOO.util.Dom.replaceClass(header_el, "cjt_header_collapsed", "cjt_header_expanded");
                        CPANEL.animate.slide_down(div_el, function() {
                            after_show();
                            CPANEL.align_panels_event.fire();
                        });
                    } else { // else hide it
                        before_hide();
                        CPANEL.animate.slide_up(div_el, function() {
                            after_hide();
                            YAHOO.util.Dom.replaceClass(header_el, "cjt_header_expanded", "cjt_header_collapsed");
                            CPANEL.align_panels_event.fire();
                        });
                    }
                };

                // add the event handler
                YAHOO.util.Event.on(header_el, "click", toggle_function);
            },

            /**
            The Dialog class contains objects and static helpers for Dialogs used in cPanel.
            @class Dialog
            @namespace CPANEL.widgets
            */
            Dialog: function() {}
        }; // end widgets object

        // ----------------------------------------------
        // Static extension to the widgets
        // ----------------------------------------------

        /**
         * Default dialog header template used if the header template is missing
         * @class  CPANEL.widgets.Dialog
         * @static
         * @property dialog_header_template
         * @type [string] the header template. */
        CPANEL.widgets.Dialog.dialog_header_template = "<div class='lt'></div><span>{header}</span><div class='rt'></div>";

        /**
         * Dialog header template match expression used to determin if the template if correctly formed.
         * @class  CPANEL.widgets.Dialog
         * @static
         * @property dialog_header_rule
         * @type [string] the header template match rule. */
        CPANEL.widgets.Dialog.dialog_header_rule = /<.*class='lt'.*\/>|<.*class='rt'.*\/>/gi;

        /**
         * Apply the default template to the dialog header if its missing
         * @class  CPANEL.widgets.Dialog
         * @static
         * @method applyDialogHeader
         * @param [string] header Current contents of the header. */
        CPANEL.widgets.Dialog.applyDialogHeader = function applyDialogHeader(header) {
            var CwD = CPANEL.widgets.Dialog;
            if (!header.match(CwD.dialog_header_rule)) {
                header = YAHOO.lang.substitute(CwD.dialog_header_template, {
                    "header": header
                });
            }
            return header;
        };


        YAHOO.lang.extend(CPANEL.widgets.Text_Input_Placeholder, YAHOO.widget.Overlay);

        var _is_ie6_or_7 = YAHOO.env.ua.ie && (YAHOO.env.ua.ie <= 7);
        if (_is_ie6_or_7) {
            var ie_shell_prototype; // lazy-load this value
            CPANEL.widgets.Text_Input_Placeholder.prototype.setBody = function(content) {
                if (content.nodeName) {
                    if (!ie_shell_prototype) {
                        ie_shell_prototype = document.createElement("div");
                        ie_shell_prototype.className = "cjt-ie-shell";
                    }
                    var ie_shell = ie_shell_prototype.cloneNode(false);
                    ie_shell.appendChild(content);
                } else {
                    content = "<div class=\"cjt-ie-shell\">" + content + "</div>";
                }

                return this.constructor.superclass.setBody.call(this, content);
            };
        }

        // -------------------------------------------------------------------------------------
        // Common notice functionality. This object contains many options for rendering notices
        //  into the user interface.
        //
        // If visible when rendered:
        //   If DOMReady, then slide down; otherwise, just be visible.
        //
        // @class Notice
        // @extends YAHOO.widget.Module
        // @param id {String} optional id of the content to show.
        // @param opts {Hash} first or second argument depending on if @id is passed.
        //  content   {String} HTML content of the notice
        //  level     {String} one of "success", "info", "warn", "error"
        //  container {HTMLElement|String} ID or node reference of the container (required)
        //  replaces  {Object} a Notice object, ID, or DOM node that this instance will replace
        // -------------------------------------------------------------------------------------
        var Notice = function(id, opts) {
            if (id) {
                if (typeof id === "object") {
                    opts = id;
                    id = DOM.generateId();
                }
            } else {
                id = DOM.generateId();
            }

            Notice.superclass.constructor.call(this, id, opts);
        };

        // Enum of the levels
        Notice.LEVELS = {
            success: "success",
            info: "info",
            error: "error",
            warn: "warn"
        };

        // Common notice container class name
        Notice.CLASS = "cjt-notice";

        // Notice container sub-classes
        Notice.CLASSES = {
            success: "cjt-notice-success",
            info: "cjt-notice-info",
            warn: "cjt-notice-warn",
            error: "cjt-notice-error"
        };

        YAHOO.lang.extend(Notice, YAHOO.widget.Module, {
            render: function(render_obj, mod_el) {
                var container;
                if (render_obj) {
                    container = DOM.get(render_obj);
                }

                if (container) {
                    this.cfg.queueProperty("container", container);
                } else {
                    var container_property = this.cfg.getProperty("container");
                    container = DOM.get(container_property);

                    if (!container) {
                        container = document.body;
                        this.cfg.queueProperty("container", container);
                    }
                }

                DOM.addClass(container, "cjt-notice-container");

                if (EVENT.DOMReady) {
                    var visible = this.cfg.getProperty("visible");
                    if (visible) {
                        this.element.style.display = "none";
                        this.renderEvent.subscribe(function do_vis() {
                            this.renderEvent.unsubscribe(do_vis);
                            this.animated_show();
                        });
                    }
                }

                return Notice.superclass.render.call(this, container, mod_el);
            },

            init: function(el, opts) {
                Notice.superclass.init.call(this, el /* , opts */ );

                this.beforeInitEvent.fire(Notice);

                DOM.addClass(this.element, Notice.CLASS);

                if (opts) {
                    this.cfg.applyConfig(opts, true);
                    this.render();
                }

                this.initEvent.fire(Notice);
            },

            animated_show: function() {
                this.beforeShowEvent.fire();

                var replacee = this.cfg.getProperty("replaces");
                if (replacee) {
                    if (typeof replacee === "string") {
                        replacee = DOM.get(replacee);
                    } else if (replacee instanceof Notice) {
                        replacee = replacee.element;
                    }
                }
                if (replacee) {
                    replacee.parentNode.removeChild(replacee);

                    /*
                    Removed until it can be fixed.   The commented block does not
                    replace (page_notice) if another notice is requested while an
                    annimation is in effect.

                    var container = DOM.get( this.cfg.getProperty("container") );
                    container.insertBefore( this.element, DOM.getNextSibling(replacee) || undefined );
                    var rep_slide = CPANEL.animate.slide_up( replacee );
                    console.log(replacee);
                    if ( replacee instanceof Notice ) {
                         rep_slide.onComplete.subscribe( replacee.destroy, replacee, true );
                    }
                    */
                }

                var ret = CPANEL.animate.slide_down(this.element);

                this.showEvent.fire();

                this.cfg.setProperty("visible", true, true);

                return ret;
            },

            initDefaultConfig: function() {
                Notice.superclass.initDefaultConfig.call(this);

                this.cfg.addProperty("replaces", {
                    value: null
                });
                this.cfg.addProperty("level", {
                    value: "info", // default to "info" level
                    handler: this.config_level
                });
                this.cfg.addProperty("content", {
                    value: "",
                    handler: this.config_content
                });
                this.cfg.addProperty("container", {
                    value: null
                });
            },

            config_content: function(type, args, obj) {
                var content = args[0];
                if (!this.body) {
                    this.setBody("<div class=\"cjt-notice-content\">" + content + "</div>");
                } else {
                    CPANEL.Y(this.body).one(".cjt-notice-content").innerHTML = content;
                }
                this._content_el = this.body.firstChild;
            },

            fade_out: function() {
                if (!this._fading_out && this.cfg) {
                    var fade = CPANEL.animate.fade_out(this.element);
                    if (fade) {
                        this._fading_out = fade;
                        this.after_hideEvent.subscribe(this.destroy, this, true);
                        fade.onComplete.subscribe(this.hide, this, true);
                    }
                }
            },

            config_level: function(type, args, obj) {
                var level = args[0];
                var level_class = level && Notice.CLASSES[level];
                if (level_class) {
                    if (this._level_class) {
                        DOM.replaceClass(this.element, this._level_class, level_class);
                    } else {
                        DOM.addClass(this.element, level_class);
                    }
                    this._level_class = level_class;
                }
            }
        });


        // -------------------------------------------------------------------------------------
        // Extensions to Notice for in page notifications.
        //
        // @class Page_Notice
        // @extends Notice
        // @param id {String} optional id of the content to show.
        // @param opts {Hash} first or second arugment depending on if @id is passed.
        //  content   {String} HTML content of the notice
        //  level     {String} one of "success", "info", "warn", "error"
        //  container {HTMLElement|String} ID or node reference of the container, but defaults
        //  to "cjt_pagenotice_container".
        //  replaces  {Object} a Notice object, ID, or DOM node that this instance will replace
        // -------------------------------------------------------------------------------------
        var Page_Notice = function() {
            Page_Notice.superclass.constructor.apply(this, arguments);
        };

        Page_Notice.CLASS = "cjt-pagenotice";

        Page_Notice.DEFAULT_CONTAINER_ID = "cjt_pagenotice_container";

        YAHOO.lang.extend(Page_Notice, Notice, {
            init: function(el, opts) {
                Page_Notice.superclass.init.call(this, el /* , opts */ );

                this.beforeInitEvent.fire(Page_Notice);

                DOM.addClass(this.element, Page_Notice.CLASS);

                if (opts) {
                    this.cfg.applyConfig(opts, true);
                    this.render();
                }

                this.initEvent.fire(Page_Notice);
            },

            initDefaultConfig: function() {
                Page_Notice.superclass.initDefaultConfig.call(this);

                if (!this.cfg.getProperty("container")) {
                    this.cfg.queueProperty("container", Page_Notice.DEFAULT_CONTAINER_ID);
                }
            },

            render: function(container) {
                container = DOM.get(container || this.cfg.getProperty("container"));
                if (container) {
                    DOM.addClass(container, "cjt-pagenotice-container");
                }

                var args_copy = Array.prototype.slice.call(arguments, 0);
                args_copy[0] = container;

                var ret = Page_Notice.superclass.render.apply(this, args_copy);

                return ret;
            }
        });


        // -------------------------------------------------------------------------------------
        // Extensions to Page_Notice for TEMPORARY in-page notifications.
        // (The exact UI controls are not defined publicly.)
        //
        // @class Dynamic_Page_Notice
        // @extends Page_Notice
        //
        // (Same interface as Page_Notice.)
        // -------------------------------------------------------------------------------------
        var Dynamic_Page_Notice = function() {
            Dynamic_Page_Notice.superclass.constructor.apply(this, arguments);
        };

        Dynamic_Page_Notice.CLASS = "cjt-dynamic-pagenotice";

        Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME = 30;

        YAHOO.lang.extend(Dynamic_Page_Notice, Page_Notice, {
            init: function(el, opts) {
                Dynamic_Page_Notice.superclass.init.call(this, el /* , opts */ );

                this.changeBodyEvent.subscribe(this._add_close_button);
                this.changeBodyEvent.subscribe(this._add_close_link);

                this.beforeInitEvent.fire(Dynamic_Page_Notice);

                DOM.addClass(this.element, Dynamic_Page_Notice.CLASS);

                if (opts) {
                    this.cfg.applyConfig(opts, true);
                    this.render();
                }

                this.initEvent.fire(Dynamic_Page_Notice);

                this.cfg.subscribeToConfigEvent("content", this._reset_close_link, this, true);
            },

            _add_close_link: function() {
                var close_text = LOCALE.maketext("Click to close.");
                var close_html = '<a href="javascript:void(0)">' + close_text + "</a>";

                var close_link;

                // Can't add to innerHTML because that will recreate
                // DOM nodes, which may have listeners on them.
                var nodes = CPANEL.dom.create_from_markup(close_html);
                close_link = nodes[0];

                DOM.addClass(close_link, "cjt-dynamic-pagenotice-close-link");
                EVENT.on(close_link, "click", this.fade_out, this, true);
                this.body.appendChild(close_link);

                if (this.cfg.getProperty("level") === "success") {
                    close_link.innerHTML += ' [<span id="' + this.element.id + '_countdown">' + Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME + "</span>]";
                    this._countdown_timeout = CPANEL.util.countdown(this.element.id + "_countdown", this.fade_out.bind(this));
                }
            },

            _reset_close_link: function() {
                if (this.cfg.getProperty("level") === "success") {
                    var span_el = DOM.get(this.element.id + "_countdown");
                    span_el.innerHTML = Dynamic_Page_Notice.SUCCESS_COUNTDOWN_TIME;
                }
            },

            /**
             * Attached to changeBodyEvent when "closebutton" is enabled.
             *
             * @method _add_close_button
             * @private
             */
            _add_close_button: function() {
                if (!this._cjt_close_button || !DOM.inDocument(this._cjt_close_button)) {
                    this.body.innerHTML += closeButton;
                    this._cjt_close_button = CPANEL.Y(this.body).one(".cjt-dynamic-pagenotice-close-button");

                    EVENT.on(this._cjt_close_button, "click", this.fade_out, this, true);
                }
            },

            /**
             * A reference to the close button.
             *
             * @property _cjt_close_button
             * @private
             */
            _cjt_close_button: null
        });

        // Publish the public interface
        CPANEL.widgets.Notice = Notice;
        CPANEL.widgets.Page_Notice = Page_Notice;
        CPANEL.widgets.Dynamic_Page_Notice = Dynamic_Page_Notice;

        // CSS for this doesn't work in IE<8. IE8 support may be possible,
        // but getting the wrapper to "contain" the <select> "tightly"
        // may be more trouble than its worth. So, we only do this for
        // IE9+.
        // Sets classes "cjt-wrapped-select" and "cjt-wrapped-select-skin"
        // Sets ID "(ID)-cjt-wrapped-select" if the <select> has an ID
        var _prototype_wrapper;
        var _arrow_key_codes = {
            37: 1,
            38: 1,
            39: 1,
            40: 1
        };
        var Wrapped_Select = function(sel) {
            if (YAHOO.env.ua.ie && (YAHOO.env.ua.ie < 9)) {
                return;
            }

            if (typeof sel === "string") {
                sel = DOM.get(sel);
            }

            if (sel.multiple) {
                throw "Can't use Wrapped_Select on multi-select!";
            }

            if (!_prototype_wrapper) {
                var dummy = document.createElement("div");
                dummy.innerHTML = "<div class='cjt-wrapped-select'><div class='cjt-wrapped-select-skin'></div><div class='cjt-wrapped-select-icon'></div></div>";
                _prototype_wrapper = dummy.removeChild(dummy.firstChild);
            }

            var wrapper = this._wrapper = _prototype_wrapper.cloneNode(true);

            if (sel.id) {
                wrapper.id = sel.id + "-cjt-wrapped-select";
            }

            this._select = sel;
            this._options = sel.options;
            this._label = wrapper.firstChild;

            this.synchronize_label();

            sel.parentNode.insertBefore(wrapper, sel);
            wrapper.insertBefore(sel, this._label);

            EVENT.on(sel, "keydown", function(e) {
                if (_arrow_key_codes[e.keyCode]) {
                    setTimeout(function() {
                        sel.blur();
                        sel.focus();
                    }, 1);
                }
            });
            EVENT.on(sel, "change", this.synchronize_label, this, true);
        };
        Wrapped_Select.prototype.synchronize_label = function() {
            if (this._select) {
                var label = "";
                var idx = this._select.selectedIndex;
                if (idx > -1) {
                    var opt = this._options[idx];
                    label = CPANEL.util.get_text_content(opt) || opt.value;
                }
                CPANEL.util.set_text_content(this._label, label);
            } else {
                this.synchronize_label = Object; // Use an existing function.
            }
        };
        CPANEL.widgets.Wrapped_Select = Wrapped_Select;

        /**
         * This YUI Tooltip subclass adds a mousedown listener for touch displays.
         * NOTE: To accomplish this, we have to twiddle with some privates.
         *
         * Arguments, parameters, and usage are the same as YUI Tooltip, except
         * for adding the *MouseDown events and methods.
         *
         * @class CPANEL.widgets.Touch_Tooltip
         * @extends YAHOO.widget.Tooltip
         * @constructor
         * @param {string|object} el The ID of the tooltip, or the config object
         * @param {object} cfg If an ID was given in the first argument, this is the config object.
         */
        var Touch_Tooltip = function(el, cfg) {
            if (!cfg) {
                cfg = el;
                el = null;
            }
            if (!el) {
                el = DOM.generateId();
            }

            return YAHOO.widget.Tooltip.call(this, el, cfg);
        };
        var CustomEvent = YAHOO.util.CustomEvent;
        var Event = EVENT;
        YAHOO.lang.extend(Touch_Tooltip, YAHOO.widget.Tooltip, {

            /**
             * See the YUI Tooltip docs.
             */
            initEvents: function() {
                Touch_Tooltip.superclass.initEvents.call(this);
                var SIGNATURE = CustomEvent.LIST;

                this.contextMouseDownEvent = this.createEvent("contextMouseDown");
                this.contextMouseDownEvent.signature = SIGNATURE;
            },

            /**
             * Similar to other functions defined in the YUI Tooltip prototype.
             * See the YUI Tooltip docs.
             */
            onContextMouseDown: function(e, obj) {
                var context = this;

                // Fire first, to honor disabled set in the listner
                if (obj.fireEvent("contextMouseDown", context, e) !== false && !obj.cfg.getProperty("disabled")) {

                    var showdelay = obj.cfg.getProperty("showdelay");
                    var hidedelay = obj.cfg.getProperty("hidedelay");
                    obj.cfg.setProperty("showdelay", 0);
                    obj.cfg.setProperty("hidedelay", 0);

                    if (obj.cfg.getProperty("visible")) {
                        obj.doHide();
                    } else {
                        obj.doShow();
                    }

                    obj.cfg.setProperty("showdelay", showdelay);
                    obj.cfg.setProperty("hidedelay", hidedelay);
                }
            },

            /**
             * See the YUI Tooltip docs.
             * NB: copied from Tooltip; tweaks made where noted
             */
            configContext: function(type, args, obj) {

                // Not in Tooltip natively, but that's probably an oversight.
                YAHOO.widget.Overlay.prototype.configContext.apply(this, arguments);

                var context = args[0],
                    aElements,
                    nElements,
                    oElement,
                    i;

                if (context) {

                    // Normalize parameter into an array
                    if (!(context instanceof Array)) {
                        if (typeof context == "string") {
                            this.cfg.setProperty("context", [document.getElementById(context)], true);
                        } else { // Assuming this is an element
                            this.cfg.setProperty("context", [context], true);
                        }
                        context = this.cfg.getProperty("context");
                    }

                    // Remove any existing mouseover/mouseout listeners
                    this._removeEventListeners();

                    // Add mouseover/mouseout listeners to context elements
                    this._context = context;

                    aElements = this._context;

                    if (aElements) {
                        nElements = aElements.length;
                        if (nElements > 0) {
                            i = nElements - 1;
                            do {
                                oElement = aElements[i];
                                Event.on(oElement, "mouseover", this.onContextMouseOver, this);
                                Event.on(oElement, "mousemove", this.onContextMouseMove, this);
                                Event.on(oElement, "mouseout", this.onContextMouseOut, this);

                                // THIS IS ADDED.
                                Event.on(oElement, "mousedown", this.onContextMouseDown, this);
                            }
                            while (i--);
                        }
                    }
                }
            },

            /**
             * See the YUI Tooltip docs.
             * NB: copied from Tooltip; tweaks made where noted
             */
            _removeEventListeners: function() {
                Touch_Tooltip.superclass._removeEventListeners.call(this);

                var aElements = this._context,
                    nElements,
                    oElement,
                    i;

                if (aElements) {
                    nElements = aElements.length;
                    if (nElements > 0) {
                        i = nElements - 1;
                        do {
                            oElement = aElements[i];
                            Event.removeListener(oElement, "mouseover", this.onContextMouseOver);
                            Event.removeListener(oElement, "mousemove", this.onContextMouseMove);
                            Event.removeListener(oElement, "mouseout", this.onContextMouseOut);

                            // THIS IS ADDED.
                            Event.removeListener(oElement, "mousedown", this.onContextMouseDown);
                        }
                        while (i--);
                    }
                }
            }
        });
        CPANEL.widgets.Touch_Tooltip = Touch_Tooltip;

    } // end else statement
})();
