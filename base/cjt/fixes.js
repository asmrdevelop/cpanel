(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var DOM = YAHOO.util.Dom;
    var EVENT = window.EVENT;

    var L = YAHOO.lang;

    // YUI bugs 2529100 and 2529292
    // The fix for these in YUI 2.9.0 does not work.
    if (YAHOO.lang.substitute("{a} {b}", {
        a: "1",
        b: "{"
    }) !== "1 {") {
        YAHOO.lang.substitute = function(s, o, f) {
            var i, j, k, key, v, meta, saved = [],
                token,
                DUMP = "dump",
                SPACE = " ",
                LBRACE = "{",
                RBRACE = "}",
                dump, objstr;

            for (;;) {
                i = i ? s.lastIndexOf(LBRACE, i - 1) : s.lastIndexOf(LBRACE);
                if (i < 0) {
                    break;
                }
                j = s.indexOf(RBRACE, i);

                // YUI 2 bug 2529292
                // YUI 2.8.2 uses >= here, which kills the function on "{}"
                if (i + 1 > j) {
                    break;
                }

                // Extract key and meta info
                token = s.substring(i + 1, j);
                key = token;
                meta = null;
                k = key.indexOf(SPACE);
                if (k > -1) {
                    meta = key.substring(k + 1);
                    key = key.substring(0, k);
                }

                // lookup the value
                // if a substitution function was provided, execute it
                v = f ? f(key, v, meta) : o[key];

                if (L.isObject(v)) {
                    if (L.isArray(v)) {
                        v = L.dump(v, parseInt(meta, 10));
                    } else {
                        meta = meta || "";

                        // look for the keyword 'dump', if found force obj dump
                        dump = meta.indexOf(DUMP);
                        if (dump > -1) {
                            meta = meta.substring(4);
                        }

                        objstr = v.toString();

                        // use the toString if it is not the Object toString
                        // and the 'dump' meta info was not found
                        if (objstr === OBJECT_TOSTRING || dump > -1) {
                            v = L.dump(v, parseInt(meta, 10));
                        } else {
                            v = objstr;
                        }
                    }
                } else if (!L.isString(v) && !L.isNumber(v)) {
                    continue;

                    // unnecessary with fix for YUI bug 2529100
                    //                // This {block} has no replace string. Save it for later.
                    //                v = "~-" + saved.length + "-~";
                    //                saved[saved.length] = token;
                    //
                    //                // break;
                }

                s = s.substring(0, i) + v + s.substring(j + 1);

            }

            // unnecessary with fix for YUI bug 2529100
            //        // restore saved {block}s
            //        for (i=saved.length-1; i>=0; i=i-1) {
            //            s = s.replace(new RegExp("~-" + i + "-~"), "{"  + saved[i] + "}", "g");
            //        }

            return s;
        };
    }

    if (YAHOO.widget.Panel) {
        var panel_proto = YAHOO.widget.Panel.prototype;

        // YUI 2 bug 2529256: avoid focusing unchecked radio buttons in tab loop
        // Strictly speaking, this should be fixed for focusLast as well,
        // but the usefulness of that seems questionable since the only breakage case
        // is that the last focusable element in the panel/dialog would be a radio
        // button.
        // This runs the original focusFirst() method then advances the focus to
        // the next non-enabled-unchecked-radio focusable element if necessary.
        // This is not being fixed for YUI 2.9.0.
        if (!panel_proto.focusFirst._2529256_fixed) {
            ["Panel", "Dialog"].forEach(function(module) {
                var _focus_first = YAHOO.widget[module].prototype.focusFirst;
                YAHOO.widget[module].prototype.focusFirst = function() {
                    var focused_el = _focus_first.apply(this, arguments) && document.activeElement;

                    if (focused_el && (("" + focused_el.type).toLowerCase() === "radio") && !focused_el.checked) {
                        var els = this.focusableElements;
                        var i = els && els.indexOf(focused_el);
                        if (i !== -1) {
                            i++;
                            var cur_el = els[i];
                            while (cur_el) {
                                if (!cur_el.disabled && ((("" + cur_el.type).toLowerCase() !== "radio") || cur_el.checked)) {
                                    break;
                                }
                                i++;
                                cur_el = els[i];
                            }
                            if (cur_el && cur_el.focus) {
                                cur_el.focus();
                                focused_el = cur_el;
                            }
                        }
                    }

                    return !!focused_el;
                };
                YAHOO.widget[module].prototype.focusFirst._2529256_fixed = true;
            });
        }

        // YUI 2 bug 2529257: prevent back-TAB from escaping focus out of a modal Panel
        // This is not being fixed for YUI 2.9.0.
        var _set_first_last_focusable = panel_proto.setFirstLastFocusable;

        var catcher_html = "<input style='position:absolute;top:1px;outline:0;margin:0;border:0;padding:0;height:1px;width:1px;z-index:-1' />";
        var _catcher_div = document.createElement("div");
        _catcher_div.innerHTML = catcher_html;
        var catcher_prototype = _catcher_div.firstChild;
        DOM.setStyle(catcher_prototype, "opacity", 0);

        panel_proto.setFirstLastFocusable = function() {
            _set_first_last_focusable.apply(this, arguments);

            if (this.firstElement && !this._first_focusable_catcher) {
                var first_catcher = catcher_prototype.cloneNode(false);
                YAHOO.util.Event.on(first_catcher, "focus", function() {
                    first_catcher.blur();
                    this.focusLast();
                }, this, true);
                this.innerElement.insertBefore(first_catcher, this.innerElement.firstChild);
                this._first_focusable_catcher = first_catcher;

                var last_catcher = catcher_prototype.cloneNode(false);
                YAHOO.util.Event.on(last_catcher, "focus", function() {
                    last_catcher.blur();
                    this.focusFirst();
                }, this, true);
                this.innerElement.appendChild(last_catcher);
                this._last_focusable_catcher = last_catcher;
            }
        };

        var _get_focusable_elements = panel_proto.getFocusableElements;
        panel_proto.getFocusableElements = function() {
            var els = _get_focusable_elements.apply(this, arguments);

            // An element that has display:none is not focusable.
            var len = els.length;
            for (var i = 0; i < len; i++) {
                if (DOM.getStyle(els[i], "display") === "none") {
                    els.splice(i, 1);
                    i--;
                }
            }

            if (els.length) {
                if (this._first_focusable_catcher) {
                    els.shift();
                }
                if (this._last_focusable_catcher) {
                    els.pop();
                }
            }

            return els;
        };

        // In WebKit and Opera, Panel assumes that we can't focus() its innerElement.
        // To compensate, it creates a dummy <button> and puts it into the
        // innerElement, absolutely positioned with left:-10000em. In LTR this is
        // fine, but in RTL it makes the screen REEEALLY wide.
        //
        // To fix, just replace the "left" CSS style with "right".
        if (document.documentElement.dir === "rtl") {
            var rtl_createHidden = panel_proto._createHiddenFocusElement;
            panel_proto._createHiddenFocusElement = function() {
                if (typeof this.innerElement.focus !== "function") {
                    rtl_createHidden.apply(this, arguments);
                    this._modalFocus.style.right = this._modalFocus.style.left;
                    this._modalFocus.style.left = "";
                }
            };
        }
    }

    // Make YUI 2 AutoComplete play nicely with RTL.
    // This is a little inefficient since it will have just set _elContainer for
    // LTR in the DOM, but it's a bit cleaner than rewriting snapContainer entirely.
    if (document.documentElement.dir === "rtl") {
        EVENT.onDOMReady(function() {
            if ("AutoComplete" in YAHOO.widget) {
                var _do_before_expand = YAHOO.widget.AutoComplete.prototype.doBeforeExpandContainer;
                YAHOO.widget.AutoComplete.prototype.doBeforeExpandContainer = function() {
                    var xpos = DOM.getX(this._elTextbox);
                    var containerwidth = this._elContainer.offsetWidth;
                    if (containerwidth) {
                        xpos -= containerwidth - DOM.get(this._elTextbox).offsetWidth;
                        DOM.setX(this._elContainer, xpos);
                    }

                    return _do_before_expand.apply(this, arguments);
                };
            }
        });
    }

    /*
     * 1) Instantiate an Overlay with an "effect" on show.
     * 2) .show() the Overlay object.
     * 3) .destroy() the Overlay object before it finishes animating in.
     *
     * OBSERVE: A very confusing JS error results once that "effect"
     * finishes animating in because the .destroy() call doesn't pull the plug
     * on the animation, and the animation presumes that the DOM object is still
     * there after it's done.
     *
     * The fix relies on the "cacheEffects" property being true (which it is
     * by default). It also accesses private methods and properties, but since
     * Yahoo! no longer maintains this code, that shouldn't be a problem.
     */
    if (YAHOO.widget && YAHOO.widget.Overlay) {
        var ovl_destroy = YAHOO.widget.Overlay.prototype.destroy;
        YAHOO.widget.Overlay.prototype.destroy = function destroy() {
            var effects = this._cachedEffects;
            if (effects && effects.length) {
                for (var e = 0; e < effects.length; e++) {

                    // Passing in (true) tells it to finish up rather than
                    // just stopping dead in its tracks.
                    effects[e]._stopAnims(true);
                }
            }

            return ovl_destroy.apply(this, arguments);
        };
    }

})(window);
