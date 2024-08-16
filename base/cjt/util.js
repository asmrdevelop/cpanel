/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including util.js!");
} else {

    /**
    The util module contains miscellaneous utilities.
    @module array
*/

    /**
    The util module contains miscellaneous utilities.
    @class util
    @namespace CPANEL
    @extends CPANEL
*/
    if (!("util" in CPANEL)) {
        CPANEL.util = {};
    }
    (function() {

        var _wrap_template = "<wbr><span class=\"wbr\"></span>";

        var _wrap_callback = function(match) {
            return match.html_encode() + _wrap_template;
        };

        var IGNORE_KEY_CODES = {
            9: true, // tab
            13: true, // enter
            16: true, // shift
            17: true, // ctrl
            18: true // alt
        };
        var STOP_TYPING_TIMEOUT = 500;

        YAHOO.lang.augmentObject(CPANEL.util, {

            /**
             * Return the # of bytes that the string uses in UTF-8.
             *
             * @method  byte_length
             * @param str {String} The string whose byte length to compute.
             * @return {Number} the string's byte count
             */
            byte_length: (typeof Blob !== "undefined") ? function byte_length(str) {
                return (new Blob([str])).size;
            } : function byte_length(str) {
                return unescape(encodeURIComponent(str)).length;
            },

            // Catches the "enter" key when pressed in a text field.  Useful for simulating native <form> behavior.
            catch_enter: function(els, func) {

                // if func is a string, assume it's a submit button
                if (typeof (func) == "string") {
                    var submit_button = func;
                    var press_button = function() {
                        YAHOO.util.Dom.get(submit_button).click();
                    };
                    func = press_button;
                }

                var _catch_enter = function(e, o) {
                    var key = YAHOO.util.Event.getCharCode(e);
                    if (key == 13) {
                        o.func.call(this, e);
                    }
                };

                YAHOO.util.Event.on(els, "keydown", _catch_enter, {
                    func: func
                });
            },

            // initialize a second-decreasing countdown
            countdown_timeouts: [],
            countdown: function(el, after_func, args) {
                var seconds_el = YAHOO.util.Dom.get(el);
                if (!seconds_el) {
                    return;
                }

                var second_decrease = function() {
                    if (seconds_el) {
                        var seconds = parseInt(seconds_el.innerHTML);
                        if (seconds == 0) {
                            after_func(args);
                        } else {
                            seconds_el.innerHTML = seconds - 1;
                            CPANEL.util.countdown_timeouts[seconds_el.id] = setTimeout(second_decrease, 1000);
                        }
                    }
                };
                clearTimeout(this.countdown_timeouts[seconds_el.id]);
                this.countdown_timeouts[seconds_el.id] = setTimeout(second_decrease, 1000);
                return this.countdown_timeouts[seconds_el.id];
            },

            // add zebra stripes to a table, all arguments optional except el
            zebra: function(els, rowA, rowB, group_size) {
                if (!rowA) {
                    rowA = "rowA";
                }
                if (!rowB) {
                    rowB = "rowB";
                }
                if (!group_size) {
                    group_size = 1;
                }

                // if els is not an array make it one
                if (YAHOO.lang.isArray(els) == false) {
                    var el = els;
                    els = [el];
                }

                // initialize the row and group
                var row = rowA;
                var group_count = 0;

                for (var i = 0; i < els.length; i++) {
                    var table = YAHOO.util.Dom.get(els[i]);
                    var rows = YAHOO.util.Dom.getElementsByClassName("zebra", "", table);

                    for (var j = 0; j < rows.length; j++) {

                        // remove any existing row stripes
                        YAHOO.util.Dom.removeClass(rows[j], rowA);
                        YAHOO.util.Dom.removeClass(rows[j], rowB);

                        // add the stripe class
                        YAHOO.util.Dom.addClass(rows[j], row);
                        group_count++;

                        // alternate
                        if (group_count == group_size) {
                            group_count = 0;
                            row = (row == rowA) ? rowB : rowA;
                        }
                    }
                }
            },

            convert_breaklines: function(str) {
                return str.replace(/\n/, "<br />");
            },

            HTML_WRAP: _wrap_template,

            // A backport of "wrapFilter" from CJT2.
            //
            wrap_string_after_pattern_and_html_encode: function(string, pattern) {
                return string.replace(pattern, _wrap_callback);
            },

            // returns the value of the checked radio button
            // if no buttons are checked returns false
            get_radio_value: function(name, root) {
                if (!root) {
                    alert("Please provide a root element for the get_radio_value function to make it faster.");
                }
                var inputs = YAHOO.util.Dom.getElementsBy(function(el) {
                    return (YAHOO.util.Dom.getAttribute(el, "name") == name);
                }, "input", root);
                for (var i = 0; i < inputs.length; i++) {
                    if (inputs[i].checked) {
                        return inputs[i].value;
                    }
                }
                return false;
            },

            toggle_more_less: function(toggle_el, text_el, state) {
                toggle_el = YAHOO.util.Dom.get(toggle_el);
                text_el = YAHOO.util.Dom.get(text_el);
                if (!toggle_el || !text_el) {
                    alert("You passed non-existent elements to the CPANEL.util.toggle_more_less function.");
                    return;
                }
                if (!state) {
                    if (YAHOO.util.Dom.getStyle(text_el, "display") == "none") {
                        state = "more";
                    }
                }
                if (state == "more") {
                    CPANEL.animate.slide_down(text_el, function() {
                        toggle_el.innerHTML = LOCALE.maketext("less »");
                        CPANEL.align_panels_event.fire();
                    });
                } else {
                    CPANEL.animate.slide_up(text_el, function() {
                        toggle_el.innerHTML = LOCALE.maketext("more »");
                        CPANEL.align_panels_event.fire();
                    });
                }
            },

            keys: function(object) {
                var obj_keys = [];

                // no hasOwnProperty check here since we probably want prototype stuff
                for (var key in object) {
                    obj_keys.push(key);
                }
                return obj_keys;
            },

            values: function(object) {
                var obj_values = [];

                // no hasOwnProperty check here since we probably want prototype stuff
                for (var key in object) {
                    obj_values.push(object[key]);
                }
                return obj_values;
            },

            operating_system: function() {
                if (navigator.userAgent.search(/Win/) != -1) {
                    return "Windows";
                }
                if (navigator.userAgent.search(/Mac/) != -1) {
                    return "Mac";
                }
                if (navigator.userAgent.search(/Linux/) != -1) {
                    return "Linux";
                }
                return "Unknown";
            },

            toggle_unlimited: function(clicked_el, el_to_disable) {
                clicked_el = YAHOO.util.Dom.get(clicked_el);
                el_to_disable = YAHOO.util.Dom.get(el_to_disable);

                if (clicked_el.tagName.toLowerCase() != "input" || el_to_disable.tagName.toLowerCase() != "input") {
                    alert("Error in CPANEL.util.toggle_unlimited() function:\nInput arguments are not of type <input />");
                    return;
                }

                if (clicked_el.type.toLowerCase() == "text") {
                    YAHOO.util.Dom.removeClass(clicked_el, "disabled_text_input");
                    el_to_disable.checked = false;
                } else {
                    clicked_el.checked = true;
                    YAHOO.util.Dom.addClass(el_to_disable, "disabled_text_input");
                }
            },

            value_or_unlimited: function(text_input_el, radio_el, validation) {
                text_input_el = YAHOO.util.Dom.get(text_input_el);
                radio_el = YAHOO.util.Dom.get(radio_el);

                // add event handlers
                YAHOO.util.Event.on(text_input_el, "focus", function() {
                    radio_el.checked = false;
                    YAHOO.util.Dom.removeClass(text_input_el, "cjt_disabled_input");
                    validation.verify();
                });

                YAHOO.util.Event.on(radio_el, "click", function() {
                    radio_el.checked = true;
                    YAHOO.util.Dom.addClass(text_input_el, "cjt_disabled_input");
                    validation.verify();
                });

                // set initial state

            },

            // deep copy an object
            clone: function(obj) {
                var temp = YAHOO.lang.JSON.stringify(obj);
                return YAHOO.lang.JSON.parse(temp);
            },

            // prevent submitting the form when Enter is pressed on an <input> element
            prevent_submit: function(elem) {
                elem = YAHOO.util.Dom.get(elem);
                var stop_propagation = function(e) {
                    var key_code = YAHOO.util.Event.getCharCode(e);
                    if (key_code == 13) {
                        YAHOO.util.Event.preventDefault(e);
                    }
                };

                YAHOO.util.Event.addListener(elem, "keypress", stop_propagation);
                YAHOO.util.Event.addListener(elem, "keydown", stop_propagation);
            },

            get_text_content: function() {
                var lookup_property = CPANEL.has_text_content ? "textContent" : "innerText";
                this.get_text_content = function(el) {
                    if (typeof el === "string") {
                        el = document.getElementById(el);
                    }
                    return el[lookup_property];
                };
                return this.get_text_content.apply(this, arguments);
            },

            set_text_content: function() {
                var lookup_property = CPANEL.has_text_content ? "textContent" : "innerText";
                this.set_text_content = function(el, value) {
                    if (typeof el === "string") {
                        el = document.getElementById(el);
                    }
                    return (el[lookup_property] = value);
                };
                return this.set_text_content.apply(this, arguments);
            },

            // This registers an event to happen after STOP_TYPING_TIMEOUT has
            // passed after a keyup without a keydown. The event object is the
            // last keyup event.
            on_stop_typing: function(el, callback, obj, context_override) {
                el = DOM.get(el);

                var my_callback = (function() {
                    if (context_override && obj) {
                        return function(e) {
                            callback.call(obj, e);
                        };
                    } else if (obj) {
                        return function(e) {
                            callback.call(el, e, obj);
                        };
                    } else {
                        return function(e) {
                            callback.call(el, e);
                        };
                    }
                })();

                var search_timeout = null;
                EVENT.on(el, "keyup", function(e) {
                    if (!(e.keyCode in IGNORE_KEY_CODES)) {
                        clearTimeout(search_timeout);
                        search_timeout = setTimeout(my_callback, STOP_TYPING_TIMEOUT);
                    }
                });
                EVENT.on(el, "keydown", function(e) {
                    if (!(e.keyCode in IGNORE_KEY_CODES)) {
                        clearTimeout(search_timeout);
                    }
                });
            },

            // creates an HTTP query string from a JavaScript object
            // For convenience when assembling the data, we make null and undefined
            // values not be part of the query string.
            make_query_string: function(data) {
                var query_string_parts = [];
                for (var key in data) {
                    var value = data[key];
                    if ((value !== null) && (value !== undefined)) {
                        var encoded_key = encodeURIComponent(key);
                        if (YAHOO.lang.isArray(value)) {
                            for (var cv = 0; cv < value.length; cv++) {
                                query_string_parts.push(encoded_key + "=" + encodeURIComponent(value[cv]));
                            }
                        } else {
                            query_string_parts.push(encoded_key + "=" + encodeURIComponent(value));
                        }
                    }
                }

                return query_string_parts.join("&");
            },

            // parses a given query string, or location.search if none is given
            // returns an object corresponding to those values
            parse_query_string: function(qstr) {
                if (qstr === undefined) {
                    qstr = location.search.replace(/^\?/, "");
                }

                var parsed = {};

                if (qstr) {

                    // This rejects invalid stuff
                    var pairs = qstr.match(/([^=&]*=[^=&]*)/g);
                    var plen = pairs.length;
                    if (pairs && pairs.length) {
                        for (var p = 0; p < plen; p++) {
                            var key_val = pairs[p].split(/=/).map(decodeURIComponent);
                            var key = key_val[0].replace(/\+/g, " ");
                            if (key in parsed) {
                                if (typeof parsed[key] !== "string") {
                                    parsed[key].push(key_val[1].replace(/\+/g, " "));
                                } else {
                                    parsed[key] = [parsed[key_val[0]], key_val[1].replace(/\+/g, " ")];
                                }
                            } else {
                                parsed[key] = key_val[1].replace(/\+/g, " ");
                            }
                        }
                    }
                }

                return parsed;
            },

            get_numbers_from_string: function(str) {
                str = "" + str; // convert str to type String
                var numbers = str.replace(/\D/g, "");
                numbers = parseInt(numbers);
                return numbers;
            }

        }); // end util object

    }());

} // end else statement
