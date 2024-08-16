/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
(function(window) {
    "use strict";

    /**
     * This module contains various CJT extension methods supporting
     * dom object minipulation and measurement.
     * @module  Cpanel.dom
     */

    // ----------------------
    // Shortcuts
    // ----------------------
    var YAHOO = window.YAHOO;
    var DOM = window.DOM;
    var EVENT = window.EVENT;
    var document = window.document;
    var CPANEL = window.CPANEL;

    // ----------------------
    // Setup the namespaces
    // ----------------------
    CPANEL.namespace("dom");

    var _ARROW_KEY_CODES = {
        37: 1,
        38: 1,
        39: 1,
        40: 1
    };

    /**
     * Used internally for normalizing <select> keyboard behavior.
     *
     * @method _do_blur_and_focus
     * @private
     */
    var _do_blur_then_focus = function() {
        this.blur();
        this.focus();
    };

    // Used for creating arbitrary markup.
    var dummy_div;

    YAHOO.lang.augmentObject(CPANEL.dom, {

        /**
         * Detects if the oninput event is working for the current browser.
         * NOTE: IE9's oninput event is horribly broken. Best just to avoid it.
         * http://msdn.microsoft.com/en-us/library/ie/gg592978%28v=vs.85%29.aspx
         *
         * @property has_oninput
         * @static
         * @type {Boolean}
         */
        has_oninput: (parseInt(YAHOO.env.ua.ie, 10) !== 9) && ("oninput" in document.createElement("input")),

        /**
         * Gets the region for the content box.
         * @method get_content_region
         * @static
         * @param  {String|HTMLElement} el Element to calculate the region.
         * @return {YAHOO.util.Region}    Region consumed by the element. Accounts for
         * padding and border. Also has custom properties:
         *   @param {[2]} outer_xy XY of the outer bounds?
         *   @param {RegionLike} padding Padding size for element
         *   @param {RegionLike} border Border top and left sizes.
         */
        get_content_region: function(el) {
            el = DOM.get(el);

            var padding_top = parseFloat(DOM.getStyle(el, "paddingTop")) || 0;
            var padding_bottom = parseFloat(DOM.getStyle(el, "paddingBottom")) || 0;
            var padding_left = parseFloat(DOM.getStyle(el, "paddingLeft")) || 0;
            var padding_right = parseFloat(DOM.getStyle(el, "paddingRight")) || 0;

            var border_left = parseFloat(DOM.getStyle(el, "borderLeftWidth")) || 0;
            var border_top = parseFloat(DOM.getStyle(el, "borderTopWidth")) || 0;

            var xy = DOM.getXY(el);
            var top = xy[1] + border_top + padding_top;
            var left = xy[0] + border_left + padding_left;
            var bottom = top + el.clientHeight - padding_top - padding_bottom;
            var right = left + el.clientWidth - padding_left - padding_right;

            var region = new YAHOO.util.Region(top, right, bottom, left);
            region.outer_xy = xy;
            region.padding = {
                "top": padding_top,
                right: padding_right,
                bottom: padding_bottom,
                left: padding_left
            };

            region.border = {
                "top": border_top,

                // no bottom or right since these are unneeded here
                left: border_left
            };

            return region;
        },

        /**
         * Gets the height of the element accounting for border and
         * padding offsets.
         * @method  get_content_height
         * @static
         * @param  {HTMLElement|String} el Element to measure.
         * @return {Number}    Height of the element.
         */
        get_content_height: function(el) {
            el = DOM.get(el);

            // most browsers return something useful from this
            var dom = parseFloat(DOM.getStyle(el, "height"));
            if (!isNaN(dom)) {
                return dom;
            }

            // IE makes us get it this way
            var padding_top = parseFloat(DOM.getStyle(el, "paddingTop")) || 0;
            var padding_bottom = parseFloat(DOM.getStyle(el, "paddingBottom")) || 0;

            var client_height = el.clientHeight;

            if (client_height) {
                return client_height - padding_top - padding_bottom;
            }

            var border_top = parseFloat(DOM.getStyle(el, "borderTopWidth")) || 0;
            var border_bottom = parseFloat(DOM.getStyle(el, "borderBottomWidth")) || 0;
            return el.offsetHeight - padding_top - padding_bottom - border_top - border_bottom;
        },

        /**
         * Gets the width of the element accounting for border and
         * padding offsets.
         * @method  get_content_width
         * @static
         * @param  {HTMLElement|String} el Element to measure.
         * @return {Number}    Width of the element.
         */
        get_content_width: function(el) {
            el = DOM.get(el);

            // most browsers return something useful from this
            var dom = parseFloat(DOM.getStyle(el, "width"));
            if (!isNaN(dom)) {
                return dom;
            }

            // IE makes us get it this way
            var padding_left = parseFloat(DOM.getStyle(el, "paddingLeft")) || 0;
            var padding_right = parseFloat(DOM.getStyle(el, "paddingRight")) || 0;

            var client_width = el.clientWidth;

            if (client_width) {
                return client_width - padding_left - padding_right;
            }

            var border_left = parseFloat(DOM.getStyle(el, "borderLeftWidth")) || 0;
            var border_right = parseFloat(DOM.getStyle(el, "borderRightWidth")) || 0;
            return el.offsetWidth - padding_left - padding_right - border_left - border_right;
        },

        /**
         * Gets the region of the current viewport
         * @method  get_viewport_region.
         * @return {YAHOO.util.Region} region for the viewport
         */
        get_viewport_region: function() {
            var vp_width = DOM.getViewportWidth();
            var vp_height = DOM.getViewportHeight();

            var scroll_x = DOM.getDocumentScrollLeft();
            var scroll_y = DOM.getDocumentScrollTop();
            return new YAHOO.util.Region(
                scroll_y,
                scroll_x + vp_width,
                scroll_y + vp_height,
                scroll_x
            );
        },

        /**
         * Adds the class if it does not exist, removes it if it does
         * exist on the element.
         * @method toggle_class
         * @static
         * @param  {HTMLElement|String} el The element to toggle the
         * CSS class name.
         * @param  {String} the_class A CSS class name to add or remove.
         */
        toggle_class: function(el, the_class) {
            el = DOM.get(el);

            // TODO: May want to consider caching since these are expensive to
            // regenerate on each call.
            var pattern = new RegExp("\\b" + the_class.regexp_encode() + "\\b");
            if (el.className.search(pattern) === -1) {
                DOM.addClass(el, the_class);
                return the_class;
            } else {
                DOM.removeClass(el, the_class);
            }
        },

        /**
         * Create one or more DOM nodes from markup.
         * These nodes are NOT injected into the page.
         *
         * @method create_from_markup
         * @param markup {String} HTML to use for creating DOM nodes
         * @return {Array} The DOM element nodes from the markup.
         */
        create_from_markup: function(markup) {
            if (!dummy_div) {
                dummy_div = document.createElement("div");
            }
            dummy_div.innerHTML = markup;

            return CPANEL.Y(dummy_div).all("> *");
        },

        /**
         * Ensure that keyboard manipulation of the <select> box will change
         * the actual value right away. On some platforms (e.g., MacOS),
         * "onchange" doesn't fire on up/down arrows until you blur() the element.
         *
         * This is primarily useful for validation; we might not want to use this
         * if "onchange" fires off anything "big" in the UI since it breaks users'
         * expectations of how drop-downs behave on their platform.
         *
         * On a related note, bear in mind that document.activeElement will be
         * different when "onchange" fires from a blur(): if it fires natively from
         * an arrow keydown, then activeElement is the <select>;
         * after a blur(), document.activeElement is probably document.body.
         *
         * @method normalize_select_arrows
         * @static
         */
        normalize_select_arrows: function(el) {
            EVENT.on(el, "keydown", function(e) {
                if (e.keyCode in _ARROW_KEY_CODES) {
                    window.setTimeout(_do_blur_then_focus.bind(this), 1);
                }
            });
        },

        /**
         * Sets the value of the element to the passed in value. If form is
         * provided, will be in the specified form.
         * @method  set_form_el_value
         * @static
         * @param {HTMLElement|String} form Optional, either a DOM element or
         * an ID of the form.
         * @param {HTMLCollection, HTMLSelect, HTMLInput, HTMLTextarea, String} el  can be an
         * HTML collection, a <select> element, an <input>, a <textarea>,
         * a name in the form, or an ID of one of these.
         * @param {Any} val  Value to set the element to.
         * @return {Boolean} true if successful, false otherwise.
         */
        set_form_el_value: function(form, el, val) {
            if (arguments.length === 2) {
                val = el;
                el = form;
                form = null;
            }

            // TODO: Need to check if form is found before calling form[el],
            // will throw an uncaught exception.
            if (typeof el === "string") {
                var element = null;
                if (form) {
                    form = DOM.get(form);
                    if (form) {

                        // Assumes the el is a name before
                        // checking if its an id further down.
                        element = form[el];
                    }
                }

                if (!element) {

                    // Form was not provided,
                    // el is an id and not a named form item,
                    // or el is already a DOM node.
                    element = DOM.get(el);
                }

                el = element;
            }

            var opts = el.options;
            if (opts) {
                for (var o = opts.length - 1; o >= 0; o--) {
                    if (opts[o].value === val) {
                        el.selectedIndex = o; // If a multi-<select>, clobber.
                        return true;
                    }
                }
            } else if ("length" in el) {
                for (var e = el.length - 1; e >= 0; e--) {
                    if (el[e].value === val) {
                        el[e].checked = true;
                        return true;
                    }
                }
            } else if ("value" in el) {
                el.value = val;
                return true;
            }

            return false;
        },

        /**
         * Shows the current element.
         * @method show
         * @static
         * @param {String|HTMLElement} el element to show
         * @param {String} display_type optional, alternative display type if the default is not desired */
        show: function(el, display_type) {
            display_type = display_type || "";
            DOM.setStyle(el, "display", display_type);
        },

        /**
         * Hides the current element.
         * @method hide
         * @static
         * @param {String|HTMLElement} el element to hide */
        hide: function(el) {
            DOM.setStyle(el, "display", "none");
        },

        /**
         * Checks if the current element is visible.
         * @method isVisible
         * @static
         * @param {String|HTMLElement} el element to check
         * @return {Boolean} true if visible, false if not. */
        isVisible: function(el) {
            return DOM.getStyle(el, "display") !== "none";
        },

        /**
         * Checks if the current element is hidden.
         * @method isHidden
         * isHidden
         * @param {String|HTMLElement} el element to check
         * @return {Boolean} true if not visible, false otherwise. */
        isHidden: function(el) {
            return DOM.getStyle(el, "display") === "none";
        },

        /**
         * Determins if the passed in element or
         * the documentElement if no element is passed in,
         * is in RTL mode.
         * @method isRtl
         * @param  {String|HtmlElement}  el Optional element, if provided,
         * this function will look for the dir attribute on the element, otherwise
         * it will look at the document.documentElement dir attribute.
         * @return {Boolean}    The document or element is in rtl if true and in ltr
         * if false.
         */
        isRtl: function(el) {
            if (!el) {
                if (document) {
                    return (document.documentElement.dir === "rtl");
                }
            } else {
                el = DOM.get(el);
                if (el) {
                    return el.dir === "rtl";
                }
            }

            // We are not operating in a browser
            // so we don't know, so just say no.
            return false;
        }
    });

    // QUESTION: Why do we need the same function with different names?
    CPANEL.dom.get_inner_region = CPANEL.dom.get_content_region;

})(window);
