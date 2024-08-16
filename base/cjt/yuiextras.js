/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var DOM = YAHOO.util.Dom;
    var EVENT = YAHOO.util.Event;
    var document = window.document;

    // Add a "noscroll" config option: the panel will not scroll with the page.
    // Works by wrapping the panel element in a position:fixed <div>.
    // NOTE: This only works when initializing the panel.
    if (("YAHOO" in window) && YAHOO.widget && YAHOO.widget.Panel) {
        var _old_init = YAHOO.widget.Panel.prototype.init;
        YAHOO.widget.Panel.prototype.init = function(el, userConfig) {
            _old_init.apply(this, arguments);

            this.cfg.addProperty("noscroll", {
                value: !!userConfig && !!userConfig.noscroll
            });
        };

        var _old_initEvents = YAHOO.widget.Panel.prototype.initEvents;
        YAHOO.widget.Panel.prototype.initEvents = function() {
            _old_initEvents.apply(this, arguments);

            this.renderEvent.subscribe(function() {
                if (this.cfg.getProperty("noscroll")) {
                    var wrapper_div = document.createElement("div");
                    wrapper_div.style.position = "fixed";

                    var parent_node = this.element.parentNode;
                    parent_node.insertBefore(wrapper_div, this.element);
                    wrapper_div.appendChild(this.element);
                    this.wrapper = wrapper_div;
                }
            });
        };
    }


    // YUI 2's Overlay context property does not factor in margins of either the
    // context element or the overlay element. This change makes it look for a
    // margin on the overlay element (not the context element) and add that to
    // whatever offset may have been passed in.
    // See YUI 3 feature request 25298897.
    if (!YAHOO.widget.Overlay._offset_uses_margin) {
        var Overlay = YAHOO.widget.Overlay;
        var _align = Overlay.prototype.align;
        var _margins_to_check = {};
        _margins_to_check[Overlay.TOP_LEFT] = ["margin-top", "margin-left"];
        _margins_to_check[Overlay.TOP_RIGHT] = ["margin-top", "margin-right"];
        _margins_to_check[Overlay.BOTTOM_LEFT] = ["margin-bottom", "margin-left"];
        _margins_to_check[Overlay.BOTTOM_RIGHT] = ["margin-bottom", "margin-right"];

        Overlay.prototype.align = function(el_align, context_align, xy_offset) {

            // Most of the time that this is called, we want to query the
            // object itself for these configuration parameters.
            if (!el_align) {
                if (this.cfg) {
                    var this_context = this.cfg.getProperty("context");
                    if (this_context) {
                        el_align = this_context[1];

                        if (!context_align) {
                            context_align = this_context[2];
                        }

                        if (!xy_offset) {
                            xy_offset = this_context[4];
                        }
                    }
                }
            }

            if (!el_align) {
                return _align.apply(this, arguments);
            }

            var el = this.element;
            var margins = _margins_to_check[el_align];
            var el_y_offset = parseInt(DOM.getStyle(el, margins[0]), 10) || 0;
            var el_x_offset = parseInt(DOM.getStyle(el, margins[1]), 10) || 0;

            if (el_x_offset) {
                var x_offset_is_negative = (el_align === Overlay.BOTTOM_RIGHT) || (el_align === Overlay.TOP_RIGHT);
                if (x_offset_is_negative) {
                    el_x_offset *= -1;
                }
            }

            if (el_y_offset) {
                var y_offset_is_negative = (el_align === Overlay.BOTTOM_LEFT) || (el_align === Overlay.BOTTOM_RIGHT);
                if (y_offset_is_negative) {
                    el_y_offset *= -1;
                }
            }

            if (el_x_offset || el_y_offset) {
                var new_xy_offset;
                if (xy_offset) {
                    new_xy_offset = [xy_offset[0] + el_x_offset, xy_offset[1] + el_y_offset];
                } else {
                    new_xy_offset = [el_x_offset, el_y_offset];
                }
                return _align.call(this, el_align, context_align, new_xy_offset);
            } else {
                return _align.apply(this, arguments);
            }
        };

        Overlay._offset_uses_margin = true;
    }

    // HTML forms don't usually submit from ENTER unless they have a submit
    // button, which YUI Dialog forms do not have by design. Moreover, they *do*
    // submit if there is just one text field. To smooth out these peculiarities:
    // 1) Add a dummy <input type="text"> to kill native ENTER submission.
    // 2) Listen for keydown events on a dialog box and run submit() from them.
    if (!YAHOO.widget.Dialog._handles_enter) {
        var _registerForm = YAHOO.widget.Dialog.prototype.registerForm;
        YAHOO.widget.Dialog.prototype.registerForm = function() {
            _registerForm.apply(this, arguments);

            if (!this._cjt_dummy_input) {
                var dummy_input = document.createElement("input");
                dummy_input.style.display = "none";
                this.form.appendChild(dummy_input);
                this._cjt_dummy_input = dummy_input;
            }
        };

        // YUI 2 KeyListener does not make its own copy of the key data object
        // that it receives when the KeyListener is created; as a result, it is
        // possible to alter the listener by changing the key data object after
        // creating the KeyListener. It's also problematic that KeyListener doesn't
        // make that information available to us after creating the listener.
        // We fix both of these issues here.
        var _key_listener = YAHOO.util.KeyListener;
        var new_key_listener = function(attach_to, key_data, handler, event) {
            var new_key_data = {};
            for (var key in key_data) {
                new_key_data[key] = key_data[key];
            }
            this.key_data = new_key_data;

            _key_listener.call(this, attach_to, new_key_data, handler, event);
        };
        YAHOO.lang.extend(new_key_listener, _key_listener);
        YAHOO.lang.augmentObject(new_key_listener, _key_listener); // static properties
        YAHOO.util.KeyListener = new_key_listener;

        // We want all dialog boxes to submit when their form receives ENTER,
        // unless the ENTER went to a <textarea> or <select>.
        // Check for this immediately after init();
        var _init = YAHOO.widget.Dialog.prototype.init;
        var _non_submit = {
            textarea: true,
            select: true
        };
        YAHOO.widget.Dialog.prototype.init = function(el, cfg) {
            var ret = _init.apply(this, arguments);

            var key_listeners = this.cfg.getProperty("keylisteners");

            var need_to_add_enter_key_listener = !key_listeners;

            if (key_listeners) {
                if (!(key_listeners instanceof Array)) {
                    key_listeners = [key_listeners];
                }

                need_to_add_enter_key_listener = !key_listeners.some(function(kl) {
                    if (!kl.key_data) {
                        return false;
                    }

                    if (kl.key_data.keys === 13) {
                        return true;
                    }

                    if (kl.key_data.indexOf && kl.key_data.indexOf(13) !== -1) {
                        return true;
                    }

                    return false;
                });
            } else {
                key_listeners = [];
                need_to_add_enter_key_listener = true;
            }

            if (need_to_add_enter_key_listener) {
                var the_dialog = this;
                key_listeners.push(new YAHOO.util.KeyListener(document.body, {
                    keys: 13
                }, function(type, args) {
                    if (the_dialog.cfg.getProperty("postmethod") !== "form") {
                        var original = EVENT.getTarget(args[1]);
                        if (original && !_non_submit[original.nodeName.toLowerCase()] && original.form === the_dialog.form) {
                            the_dialog.submit();
                        }
                    }
                }));

                this.cfg.setProperty("keylisteners", key_listeners);
            }

            return ret;
        };

        YAHOO.widget.Dialog._handles_enter = true;
    }

    // Allow YUI Dialog buttons to set "classes" in their definitions
    var _configButtons = YAHOO.widget.Dialog.prototype.configButtons;
    YAHOO.widget.Dialog.prototype.configButtons = function() {
        var ret = _configButtons.apply(this, arguments);

        var button_defs = this.cfg.getProperty("buttons");
        if (!button_defs || !button_defs.length) {
            return ret;
        }

        var buttons = this.getButtons();
        if (!buttons.length) {
            return ret;
        }

        var yui_button = YAHOO.widget.Button && (buttons[0] instanceof YAHOO.widget.Button);

        for (var b = buttons.length - 1; b >= 0; b--) {
            var cur_button = buttons[b];
            var classes = button_defs[b].classes;
            if (classes) {
                if (classes instanceof Array) {
                    classes = classes.join(" ");
                }

                if (yui_button) {
                    cur_button.addClass(classes);
                } else {
                    DOM.addClass(cur_button, classes);
                }
            }
        }

        return ret;
    };


    // http://yuilibrary.com/projects/yui2/ticket/2529451
    //
    // Custom Event: after_hideEvent
    //  This allows us to tell YUI to destroy() a Module once it's hidden.
    //
    // If we're animated, then just execute as the last hideEvent subscriber.
    // If not, then execute immeditaely after hide() is done.
    //
    // We have to do the two cases separately because of the call to
    // cfg.configChangedEvent.fire() immediately after hideEvent.fire() in
    // cfg.setProperty().
    var modpro = YAHOO.widget.Module.prototype;
    var init_ev = modpro.initEvents;
    modpro.initEvents = function() {
        init_ev.apply(this, arguments);
        this.after_hideEvent = this.createEvent("after_hide");
        this.after_hideEvent.signature = YAHOO.util.CustomEvent.LIST;
    };
    var hide = modpro.hide;
    modpro.hide = function() {
        var delayed = this.cfg.getProperty("effect");
        if (delayed) {
            this.hideEvent.subscribe(function afterward() {
                this.hideEvent.unsubscribe(afterward);
                this.after_hideEvent.fire();
            });
        }
        hide.apply(this, arguments);
        if (!delayed) {
            this.after_hideEvent.fire();
        }
    };

})(window);
