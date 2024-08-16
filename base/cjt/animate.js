/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint camelcase: 0 */

var CPANEL = window.CPANEL,
    YAHOO = window.YAHOO;

// check to be sure the CPANEL global object already exists
if (typeof CPANEL === "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including animate.js!");
} else if (typeof YAHOO.util.Anim === "undefined" || !YAHOO.util.Anim) {

    // check to be sure the YUI Animation library exists
    alert("You must include the YUI Animation library before including animate.js!");
} else {

    /**
    The animate module contains methods for animation.
    @module animate
*/

    (function() {

        // To prevent a slide or fade from starting in the middle of one
        // that's already in progress. Some optimizations here; modify with care.
        var _SLIDING = [];
        var _FADING = [];
        var i, cur_el;

        function _check(el, to_check) {
            for (i = 0; cur_el = to_check[i++]; /* nothing */ ) {
                if (cur_el === el) {
                    return false; // abort slide/fade
                }
            }
            to_check.push(el);

            return true;
        }

        function _done_check(el, to_check) {
            for (i = 0; cur_el = to_check[i++]; /* nothing */ ) {
                if (cur_el === el) {
                    return to_check.splice(--i, 1);
                }
            }

            return;
        }

        var WHM_NAVIGATION_TOP_CONTAINER_SELECTOR = "#navigation #breadcrumbsContainer";

        CPANEL.animate = {

            // animate the margins, borders, paddings, and height sequentially,
            // rather than animating them concurrently;
            // concurrent slide produces an unattractive "slide within a slide" that
            // sequential slide avoids, but it's jerky on most machines/browsers in 2010.
            // Set this to true in 2012 or so. Hopefully. :)
            sequential_slide: false,

            // Enable this to get useful console notices.
            debug: false,

            // Opts:
            //  expand_width: sets -10000px right margin when reading computed height;
            //      this is for when the animated element's container width influences
            //      computed height (e.g., if both container and animated element are
            //      absolutely positioned).
            slide_down: function(elem, opts) {
                var callback = (typeof opts === "function") && opts;
                var expand_width = opts && opts.expand_width;

                var el = DOM.get(elem);
                var check = _check(el, _SLIDING);
                if (!check) {
                    return;
                }

                var s = el.style;

                var old_position = s.position;
                var old_visibility = s.visibility;
                var old_overflow = s.overflow;
                var old_bottom = s.bottom; // See case 45653 for why this is needed.
                var old_display = DOM.getStyle(el, "display");

                // Set the right margin in case we slide something down in an
                // absolutely-positioned, flexibly-sized container; the wide right margin
                // will make the sliding-down element expand to its full width
                // when we read the attributes below.
                if (expand_width) {
                    var old_right_margin = s.marginRight;
                    s.marginRight = "-10000px";
                }

                var change_overflow = old_overflow !== "hidden";
                var change_position = old_position !== "absolute";
                var change_visibility = old_visibility !== "hidden";

                // guess at what kind of display to use
                var test_node = document.createElement(el.nodeName);
                test_node.style.position = "absolute";
                test_node.style.visibility = "hidden";
                document.body.appendChild(test_node);
                var default_display = DOM.getStyle(test_node, "display");
                document.body.removeChild(test_node);
                delete test_node;

                if (change_visibility) {
                    s.visibility = "hidden";
                }
                if (change_position) {
                    s.position = "absolute";
                }
                s.bottom = 0;
                if (change_overflow) {
                    s.overflow = "hidden";
                }
                s.display = default_display;

                var old_box_attrs = CPANEL.animate._get_box_attributes(el);
                var computed_box_attrs = CPANEL.animate._get_computed_box_attributes(el);


                var finish_up = function() {
                    for (var attr in computed_box_attrs) {
                        el.style[attr] = old_box_attrs[attr] || "";
                    }

                    if (change_overflow) {
                        s.overflow = old_overflow;
                    }
                    if (old_display !== "none") {
                        s.display = old_display;
                    }
                    _done_check(el, _SLIDING);
                };

                if (change_position) {
                    s.position = old_position;
                }
                s.bottom = old_bottom;
                if (change_visibility) {
                    s.visibility = old_visibility;
                }
                if (expand_width) {
                    s.marginRight = old_right_margin;
                }

                for (var attr in computed_box_attrs) {
                    s[attr] = 0;
                }

                if (CPANEL.animate.debug) {
                    console.debug("slide down", el, computed_box_attrs);
                }

                if (CPANEL.animate.sequential_slide) {
                    var total_slide_distance = 0;
                    for (var attr in computed_box_attrs) {
                        total_slide_distance += computed_box_attrs[attr];
                    }

                    var animations = [];
                    var all_animations = CPANEL.animate._animation_order;
                    var all_animations_count = CPANEL.animate._animation_order.length;
                    var last_animation;
                    for (var a = 0; a < all_animations_count; a++) {
                        var attr = all_animations[a];
                        if (attr in computed_box_attrs) {
                            var slide_distance = computed_box_attrs[attr];
                            var slide_time = CPANEL.animate.slideTime * slide_distance / total_slide_distance;
                            var anims = {};
                            anims[attr] = {
                                from: 0,
                                to: computed_box_attrs[attr]
                            };
                            var cur_anim = new YAHOO.util.Anim(el, anims, slide_time);
                            if (last_animation) {
                                (function(frozen_anim_obj) {
                                    var next_trigger = function() {
                                        frozen_anim_obj.animate();
                                    };
                                    last_animation.onComplete.subscribe(next_trigger);
                                })(cur_anim);
                            }
                            animations.push(cur_anim);
                            last_animation = cur_anim;
                        }
                    }
                    last_animation.onComplete.subscribe(finish_up);
                    if (callback) {
                        last_animation.onComplete.subscribe(callback);
                    }

                    animations[0].animate();

                    return animations;
                } else {
                    var animations = {};
                    for (var attr in computed_box_attrs) {
                        animations[attr] = {
                            from: 0,
                            to: computed_box_attrs[attr]
                        };
                    }

                    var anim = new YAHOO.util.Anim(elem, animations, CPANEL.animate.slideTime);

                    anim.onComplete.subscribe(finish_up);
                    if (callback) {
                        anim.onComplete.subscribe(callback);
                    }

                    anim.animate();

                    return anim;
                }
            },
            slide_up: function(elem, callback) {
                var el = DOM.get(elem);
                var check = _check(el, _SLIDING);
                if (!el || !check) {
                    return;
                }

                var s = el.style;

                old_overflow = s.overflow;
                var change_overflow = old_overflow !== "hidden";

                if (change_overflow) {
                    s.overflow = "hidden";
                }

                var old_box_settings = CPANEL.animate._get_box_attributes(el);
                var computed_box_settings = CPANEL.animate._get_computed_box_attributes(el);

                var finish_up = function() {
                    for (var attr in computed_box_settings) {
                        s[attr] = old_box_settings[attr] || "";
                    }

                    s.display = "none";
                    if (change_overflow) {
                        s.overflow = old_overflow;
                    }

                    _done_check(el, _SLIDING);
                };

                if (CPANEL.animate.sequential_slide) {
                    var total_slide_distance = 0;
                    for (var attr in computed_box_settings) {
                        total_slide_distance += computed_box_settings[attr];
                    }
                    var animations = [];
                    var all_animations = CPANEL.animate._animation_order;
                    var all_animations_count = CPANEL.animate._animation_order.length;
                    var last_animation;
                    for (var a = all_animations_count - 1; a > -1; a--) {
                        var attr = all_animations[a];
                        if (attr in computed_box_settings) {
                            var slide_distance = computed_box_settings[attr];
                            var slide_time = CPANEL.animate.slideTime * slide_distance / total_slide_distance;
                            var anims = {};
                            anims[attr] = {
                                to: 0
                            };
                            var cur_anim = new YAHOO.util.Anim(el, anims, slide_time);
                            if (last_animation) {
                                (function(frozen_anim_obj) {
                                    var next_trigger = function() {
                                        frozen_anim_obj.animate();
                                    };
                                    last_animation.onComplete.subscribe(next_trigger);
                                })(cur_anim);
                            }
                            animations.push(cur_anim);
                            last_animation = cur_anim;
                        }
                    }
                    last_animation.onComplete.subscribe(finish_up);
                    if (callback) {
                        last_animation.onComplete.subscribe(callback);
                    }

                    animations[0].animate();

                    return animations;
                } else {
                    var animations = {};

                    for (var attr in computed_box_settings) {
                        animations[attr] = {
                            to: 0
                        };
                    }

                    var anim = new YAHOO.util.Anim(el, animations, CPANEL.animate.slideTime);

                    anim.onComplete.subscribe(finish_up);
                    if (callback) {
                        anim.onComplete.subscribe(callback);
                    }
                    anim.animate();

                    return anim;
                }
            },

            slide_up_and_empty: function(elem, callback) {
                return CPANEL.animate.slide_up(elem, function() {
                    var that = this;
                    if (callback) {
                        callback.call(that);
                    }
                    this.getEl().innerHTML = "";
                });
            },
            slide_up_and_remove: function(elem, callback) {
                return CPANEL.animate.slide_up(elem, function() {
                    var that = this;
                    if (callback) {
                        callback.call(that);
                    }
                    var el = this.getEl();
                    el.parentNode.removeChild(el);
                });
            },
            slide_toggle: function(elem, callback) {
                var el = DOM.get(elem);
                var func_name = el.offsetHeight ? "slide_up" : "slide_down";
                return CPANEL.animate[func_name](el, callback);
            },

            _box_attributes: {
                height: "height",
                paddingTop: "padding-top",
                paddingBottom: "padding-bottom",
                borderTopWidth: "border-top-width",
                borderBottomWidth: "border-bottom-width",
                marginTop: "margin-top",
                marginBottom: "margin-bottom"
            },
            _animation_order: [ // for sliding down
                "marginTop", "borderTopWidth", "paddingTop",
                "height",
                "paddingBottom", "borderBottomWidth", "marginBottom"
            ],
            _get_box_attributes: function(el) {
                var attrs = CPANEL.util.keys(CPANEL.animate._box_attributes);
                var attrs_count = attrs.length;
                var el_box_attrs = {};
                for (var a = 0; a < attrs_count; a++) {
                    var cur_attr = attrs[a];
                    var attr_val = el.style[attrs[a]];
                    if (attr_val != "") {
                        el_box_attrs[cur_attr] = attr_val;
                    }
                }
                return el_box_attrs;
            },
            _get_computed_box_attributes: function(el) {
                var computed_box_attrs = {};
                var attr_map = CPANEL.animate._box_attributes;
                for (var attr in attr_map) {
                    var computed = parseFloat(DOM.getStyle(el, attr_map[attr]));
                    if (computed > 0) {
                        computed_box_attrs[attr] = computed;
                    }
                }

                // in case height is "auto"
                if (!("height" in computed_box_attrs)) {
                    var simple_height = el.offsetHeight;
                    if (simple_height) {
                        for (var attr in computed_box_attrs) {
                            if (attr !== "marginTop" && attr !== "marginBottom") {
                                simple_height -= computed_box_attrs[attr];
                            }
                        }
                        if (simple_height) {
                            computed_box_attrs.height = simple_height;
                        }
                    }
                }
                return computed_box_attrs;
            },

            fade_in: function(elem, callback) {
                var el = DOM.get(elem);
                var check = _check(el, _FADING);
                if (!check) {
                    return;
                }

                var old_filter = "",
                    element_style_opacity = "";
                if ("opacity" in el.style) {
                    element_style_opacity = el.style.opacity;
                } else {
                    var old_filter = el.style.filter;
                }

                var target_opacity = parseFloat(DOM.getStyle(el, "opacity"));

                var anim = new YAHOO.util.Anim(el, {
                    opacity: {
                        to: target_opacity || 1
                    }
                }, CPANEL.animate.fadeTime);

                anim.onComplete.subscribe(function() {
                    if ("opacity" in el.style) {
                        el.style.opacity = element_style_opacity;
                    } else if (old_filter) {
                        el.style.filter = old_filter;
                    }

                    _done_check(el, _FADING);
                });
                if (callback) {
                    anim.onComplete.subscribe(callback);
                }
                DOM.setStyle(el, "opacity", 0);
                el.style.visibility = "";
                if (el.style.display === "none") {
                    el.style.display = "";
                }
                anim.animate();
                return anim;
            },
            fade_out: function(elem, callback) {
                var el = DOM.get(elem);
                var check = _check(el, _FADING);
                if (!check) {
                    return;
                }
                var old_opacity = el.style.opacity;

                var anim = new YAHOO.util.Anim(el, {
                    opacity: {
                        to: 0
                    }
                }, CPANEL.animate.fadeTime);

                anim.onComplete.subscribe(function() {
                    el.style.display = "none";
                    el.style.opacity = old_opacity;

                    _done_check(el, _FADING);
                });
                if (callback) {
                    anim.onComplete.subscribe(callback);
                }
                anim.animate();
                return anim;
            },
            fade_toggle: function(elem, callback) {
                var el = DOM.get(elem);
                var func_name = el.offsetHeight ? "fade_out" : "fade_in";
                return CPANEL.animate[func_name](el, callback);
            },

            slideTime: 0.2,
            fadeTime: 0.32,

            /**
                Returns the browser-computed "auto" height of an element.<br />
                It calculates the height by changing the style of the element: opacity: 100%; z-index: 5000; display: block, height: auto<br />
                Then it grabs the height of the element in that state and returns the original style attributes.<br />
                This function is used by animation functions to determine the height to animate to.<br />
                NOTE: the height does NOT include padding-top or padding-bottom; only the actual height of the element
                @method getAutoHeight
                @param {DOM element} el a reference to a DOM element, will get passed to YAHOO.util.Dom.get
                @return {integer} the "auto" height of the element
            */
            getAutoHeight: function(elid) {

                // get the element
                el = YAHOO.util.Dom.get(elid);

                // copy the current style
                var original_opacity = YAHOO.util.Dom.getStyle(el, "opacity");
                var original_zindex = YAHOO.util.Dom.getStyle(el, "z-index");
                var original_display = YAHOO.util.Dom.getStyle(el, "display");
                var original_height = YAHOO.util.Dom.getStyle(el, "height");

                // make the element invisible and expand it to it's auto height
                YAHOO.util.Dom.setStyle(el, "opacity", 1);
                YAHOO.util.Dom.setStyle(el, "z-index", 5000);
                YAHOO.util.Dom.setStyle(el, "display", "block");
                YAHOO.util.Dom.setStyle(el, "height", "auto");

                // grab the height of the element
                var currentRegion = YAHOO.util.Dom.getRegion(el);
                var padding_top = parseInt(YAHOO.util.Dom.getStyle(el, "padding-top"));
                var padding_bottom = parseInt(YAHOO.util.Dom.getStyle(el, "padding-bottom"));
                var currentHeight = (currentRegion.bottom - currentRegion.top - padding_top - padding_bottom);

                // return the original style
                var original_opacity = YAHOO.util.Dom.setStyle(el, "opacity", original_opacity);
                var original_zindex = YAHOO.util.Dom.setStyle(el, "z-index", original_zindex);
                var original_display = YAHOO.util.Dom.setStyle(el, "display", original_display);
                var original_height = YAHOO.util.Dom.setStyle(el, "height", original_height);

                return currentHeight;
            }
        }; // end animate object


        if (!("ContainerEffect" in CPANEL.animate)) {
            CPANEL.animate.ContainerEffect = {};
        }
        var _get_style = YAHOO.util.Dom.getStyle;
        var _set_style = YAHOO.util.Dom.setStyle;
        var Config = YAHOO.util.Config;

        var _mask;
        var _get_mask_opacity = function() {
            if (!("_mask_opacity" in this)) {
                _mask = this.mask;
                this._mask_opacity = _get_style(_mask, "opacity");
                _set_style(_mask, "opacity", 0);
            }
        };

        var FADE_MODAL = function(ovl, dur) {
            var fade = YAHOO.widget.ContainerEffect.FADE.apply(this, arguments);

            if (!Config.alreadySubscribed(ovl.beforeShowMaskEvent, _get_mask_opacity, ovl)) {
                ovl.beforeShowMaskEvent.subscribe(_get_mask_opacity);
            }

            fade.animIn.onStart.subscribe(function() {
                if (ovl.mask) {
                    var anim = new YAHOO.util.Anim(ovl.mask, {
                        opacity: {
                            from: 0,
                            to: ovl._mask_opacity
                        }
                    }, dur);

                    // So the next _get_mask_opacity() will run.
                    delete this._mask_opacity;

                    anim.animate();
                }
            });
            fade.animOut.onStart.subscribe(function() {
                if (ovl.mask) {
                    var anim = new YAHOO.util.Anim(ovl.mask, {
                        opacity: {
                            to: 0
                        }
                    }, dur);
                    anim.animate();
                }
            });
            fade.animOut.onComplete.subscribe(function() {
                if (ovl.mask) {
                    DOM.setStyle(ovl.mask, "opacity", 0);
                }
            });

            return fade;
        };
        CPANEL.animate.ContainerEffect.FADE_MODAL = FADE_MODAL;

        // FADE_MODAL works by attaching a listener to the beforeShowMask event.
        // We need to remove that listener every time we set a new "effect" so that
        // any listener from FADE_MODAL won't affect the next one.
        var _configEffect = YAHOO.widget.Overlay.prototype.configEffect;
        YAHOO.widget.Overlay.prototype.configEffect = function() {
            if (this.beforeShowMaskEvent) {
                this.beforeShowMaskEvent.unsubscribe(_get_mask_opacity);
            }
            return _configEffect.apply(this, arguments);
        };


        // CPANEL.animate.Rotation
        // extension of YAHOO.util.Anim
        // attributes are just "from", "to", and "unit"
        // not super-complete...but it works in IE :)
        //
        // Notable limitation: The IE code assumes the rotating object is stationary.
        // It would be possible to adjust this code to accommodate objects that move
        // while rotating, but it would be "jaggier" and might interfere with the
        // other animation.
        var _xform_attrs = ["transform", "MozTransform", "WebkitTransform", "OTransform", "msTransform"];
        var _transform_attribute = null;
        var _test_style = (document.body || document.createElement("span")).style;
        for (var a = 0, cur_a; cur_a = _xform_attrs[a++]; /* */ ) {
            if (cur_a in _test_style) {
                _transform_attribute = cur_a;
                break;
            }
        }
        if (!_transform_attribute) {
            var ie_removeProperty = "removeProperty" in _test_style ? "removeProperty" : "removeAttribute";

            var half_pi = 0.5 * Math.PI;
            var pi = Math.PI;
            var pi_and_half = 1.5 * Math.PI;
            var two_pi = 2 * Math.PI;

            var abs = Math.abs;
            var sin = Math.sin;
            var cos = Math.cos;
        }

        var _rotate_regexp = /rotate\(([^\)]*)\)/;
        var _unit_conversions = {
            deg: {
                grad: 10 / 9,
                rad: Math.PI / 180,
                deg: 1
            },
            grad: {
                deg: 9 / 10,
                rad: Math.PI / 200,
                grad: 1
            },
            rad: {
                deg: 180 / Math.PI,
                grad: 200 / Math.PI,
                rad: 1
            }
        };

        var Rotation = function() {
            if (arguments[0]) {
                Rotation.superclass.constructor.apply(this, arguments);

                // IE necessitates a few workarounds:
                // 1) Since IE rotates "against the upper-left corner", move the element
                //   on each rotation to where it needs to be so it looks like we rotate
                //   from the center.
                // 2) Since IE doesn't remove an element from the normal flow when it rotates.
                //   create a clone of the object, make it position:absolute, and rotate that.
                //   This will produce a "jerk" if the rotation isn't to/from 0/180 degrees.
                if (!_transform_attribute) {
                    var el = YAHOO.util.Dom.get(arguments[0]);
                    var _old_visibility;
                    var _clone_el;
                    var _old_position;
                    var _top_style;
                    var _left_style;

                    this.onStart.subscribe(function() {
                        _top_style = el.style.top;
                        _left_style = el.style.left;

                        // setting any "zoom" property forces hasLayout
                        // without currentStyle.hasLayout, no filter controls display
                        if (!el.currentStyle.hasLayout) {
                            if (DOM.getStyle(el, "display") === "inline") {
                                el.style.display = "inline-block";
                            } else {
                                el.style.zoom = "1";
                            }
                        }

                        // The clone is needed:
                        // 1. When rotating an inline element (to maintain the layout)
                        // 2. When not rotating from a vertical
                        // ...but for simplicity, this code always creates the clone.
                        _clone_el = el.cloneNode(true);

                        _clone_el.id = "";
                        _clone_el.style.visibility = "hidden";
                        _clone_el.style.position = "absolute";
                        el.parentNode.insertBefore(_clone_el, el);

                        if (_clone_el.style.filter) {
                            _clone_el.style.filter = "";
                        }
                        var region = YAHOO.util.Dom.getRegion(_clone_el);
                        var width = parseFloat(YAHOO.util.Dom.getStyle(_clone_el, "width")) || region.width;
                        var height = parseFloat(YAHOO.util.Dom.getStyle(_clone_el, "height")) || region.height;
                        this._center_x = width / 2;
                        this._center_y = height / 2;
                        this._width = width;
                        this._height = height;

                        DOM.setXY(_clone_el, DOM.getXY(el));
                        this._left_px = _clone_el.offsetLeft;
                        this._top_px = _clone_el.offsetTop;

                        _clone_el.style.visibility = "visible";
                        _clone_el.style.filter = el.style.filter;

                        var z_index = YAHOO.util.Dom.getStyle(el, "z-index");
                        if (z_index === "auto") {
                            z_index = 0;
                        }
                        _clone_el.style.zIndex = z_index + 1;

                        _old_visibility = el.style.visibility;
                        el.style.visibility = "hidden";

                        this.setEl(_clone_el);

                        this.setRuntimeAttribute();
                        var attrs = this.runtimeAttributes._rotation;
                        var unit = attrs.unit;
                        var degrees = (unit === "deg") ? attrs.start : attrs.start * _unit_conversions[unit].deg;
                        var from_vertical = this._from_vertical = !(degrees % 180);
                        if (!from_vertical) {

                            // This only returns the computed xy compensatory offset
                            // for the start angle. It does not "setAttribute".
                            var xy_offset = this.setAttribute(null, degrees, "deg", true);

                            // We round here because we're dealing with real pixels;
                            // otherwise, rounding errors creep in.
                            this._left_px += Math.round(xy_offset[0]);
                            this._top_px += Math.round(xy_offset[1]);
                        }

                    });
                    this.onComplete.subscribe(function() {

                        // determine if we are rotating back to zero degrees,
                        // which will allow a cleaner-looking image
                        var attrs = this.runtimeAttributes._rotation;
                        var unit = attrs.unit;
                        var degrees = (unit === "deg") ? attrs.end : attrs.end * _unit_conversions[unit].deg;
                        var to_zero = !(degrees % 360);
                        var to_vertical = !(degrees % 180);

                        // Sometimes IE will fail to render the element if you
                        // change the "filter" property before restoring "visibility".
                        // Otherwise, it normally would make sense to do this after
                        // rotating and translating the source element.
                        el.style.visibility = _old_visibility;

                        if (to_zero) {
                            el.style[ie_removeProperty]("filter");
                        } else {
                            el.style.filter = _clone_el.style.filter;
                        }

                        if (this._from_vertical && to_vertical) {
                            if (_top_style) {
                                el.style.top = _top_style;
                            } else {
                                el.style[ie_removeProperty]("top");
                            }
                            if (_left_style) {
                                el.style.left = _left_style;
                            } else {
                                el.style[ie_removeProperty]("left");
                            }
                        } else {
                            DOM.setXY(el, DOM.getXY(_clone_el));
                        }

                        _clone_el.parentNode.removeChild(_clone_el);
                    });
                } else if (_transform_attribute === "WebkitTransform") {

                    // WebKit refuses (as of October 2010) to rotate inline elements
                    this.onStart.subscribe(function() {
                        var el = this.getEl();
                        var original_display = YAHOO.util.Dom.getStyle(el, "display");
                        if (original_display === "inline") {
                            el.style.display = "inline-block";
                        }
                    });
                }
            }
        };

        Rotation.NAME = "Rotation";

        YAHOO.extend(Rotation, YAHOO.util.Anim, {

            setAttribute: _transform_attribute ? function(attr, val, unit) {
                this.getEl().style[_transform_attribute] = "rotate(" + val + unit + ")";
            } : function(attr, val, unit, no_set) {
                var el, el_style, cos_val, sin_val, ie_center_x, ie_center_y, width, height;
                el = this.getEl();
                el_style = el.style;

                if (unit !== "rad") {
                    val = val * _unit_conversions[unit].rad;
                }
                val %= two_pi;
                if (val < 0) {
                    val += two_pi;
                }

                cos_val = cos(val);
                sin_val = sin(val);
                width = this._width;
                height = this._height;

                if ((val >= 0 && val < half_pi) || (val >= pi && val < pi_and_half)) {
                    ie_center_x = 0.5 * (abs(width * cos_val) + abs(height * sin_val));
                    ie_center_y = 0.5 * (abs(width * sin_val) + abs(height * cos_val));
                } else {
                    ie_center_x = 0.5 * (abs(height * sin_val) + abs(width * cos_val));
                    ie_center_y = 0.5 * (abs(height * cos_val) + abs(width * sin_val));
                }

                if (no_set) {
                    return [ie_center_x - this._center_x, ie_center_y - this._center_y];
                } else {
                    el_style.top = (this._top_px - ie_center_y + this._center_y) + "px";
                    el_style.left = (this._left_px - ie_center_x + this._center_x) + "px";
                    el_style.filter = "progid:DXImageTransform.Microsoft.Matrix(sizingMethod='auto expand'" + ",M11=" + cos_val + ",M12=" + -1 * sin_val + ",M21=" + sin_val + ",M22=" + cos_val + ")";
                }
            },

            // the only way to get this from IE would be to parse transform values,
            // which is reeeeally icky
            getAttribute: function() {
                if (!_transform_attribute) {
                    return 0;
                }

                var match = this.getEl().style[_transform_attribute].match(_rotate_regexp);
                return match ? match[1] : 0;
            },

            defaultUnit: "deg",

            setRuntimeAttribute: function() {
                var attr = "_rotation";
                var current_rotation;
                var unit = ("unit" in this.attributes) ? this.attributes[attr].unit : this.defaultUnit;
                if ("from" in this.attributes) {
                    current_rotation = this.attributes.from;
                } else {
                    current_rotation = this.getAttribute();
                    if (current_rotation) {
                        var number_units = current_rotation.match(/^(\d+)(\D+)$/);
                        if (number_units[2] === unit) {
                            current_rotation = parseFloat(number_units[1]);
                        } else {
                            current_rotation = number_units[1] * _unit_conversions[unit][number_units[2]];
                        }
                    }
                }
                this.runtimeAttributes[attr] = {
                    start: current_rotation,
                    end: this.attributes.to,
                    unit: unit
                };
                return true;
            }
        });

        CPANEL.animate.Rotation = Rotation;


        /**
         * The WindowScroll constructor.  This subclasses YAHOO.util.Scroll which itself subclasses YAHOO.util.Anim
         *   1) An element (or its ID)
         *   2) A YUI Region
         *   3) A Y-coordinate
         * @method WindowScroll
         * @param {object} obj - An object that contains the "destination" field which may be an ID, YAHOO.util.Region, or int
         */
        var WindowScroll = function() {


            var SCROLL_ANIMATION_DURATION = 0.5;
            var destination = arguments[0] || 0;
            var targetRegion;

            if (typeof destination === "string") {
                destination = DOM.get(destination);
                targetRegion = DOM.getRegion(destination);
            }

            if (typeof destination === "object") {
                if (!(destination instanceof YAHOO.util.Region)) {
                    destination = DOM.getRegion(destination);
                }
            } else {
                destination = new YAHOO.util.Point(0, destination);
            }
            targetRegion = destination;

            var scroll_window_to_y;
            var top_scroll_y = destination.top;

            // As of WHM 11.34+, there is a top banner that we need to account for;
            // otherwise the scroll will put things underneath that banner.
            if (CPANEL.is_whm() && CPANEL.Y.one(WHM_NAVIGATION_TOP_CONTAINER_SELECTOR)) {
                top_scroll_y -= DOM.get("breadcrumbsContainer").offsetHeight;
            }

            var scroll_y = DOM.getDocumentScrollTop();

            // If we've scrolled past where the notice is, scroll back.
            if (scroll_y > top_scroll_y) {
                scroll_window_to_y = top_scroll_y;
            } else {

                // If we've not scrolled far enough down to see the region,
                // scroll forward until the element is at the bottom of the screen,
                // OR the top of the element is at the top of the screen,
                // whichever comes first.
                var vp_region = CPANEL.dom.get_viewport_region();
                var bottom_scroll_y = Math.max(destination.bottom - vp_region.height, 0);
                if (scroll_y < bottom_scroll_y) {
                    scroll_window_to_y = Math.min(top_scroll_y, bottom_scroll_y);
                } else {

                    // This means the image is viewable so it should not scroll
                    scroll_window_to_y = vp_region.top;
                }
            }

            var scrollDesc = {
                scroll: {
                    to: [DOM.getDocumentScrollLeft(), scroll_window_to_y]
                }
            };

            // If the region is already in the viewport the time should be 0
            var scrollTime = CPANEL.dom.get_viewport_region().contains(targetRegion) ? 0 : SCROLL_ANIMATION_DURATION;

            var easing = YAHOO.util.Easing.easeBothStrong;

            // Whether we animate document.body or document.documentElement
            // is a mess, even in November 2017!! All of the following
            // browsers will only scroll with the given element:
            //
            // Chrome:  document.body
            // Safari:  document.documentElement
            // Edge:    document.body
            // Firefox: document.documentElement
            // IE11:    document.documentElement
            //
            // Since there appears to be no rhyme nor reason to the
            // above, we’ll animate both. Hopefully no new version
            // of any of the above will break on this. :-/

            (new YAHOO.util.Scroll(
                document.body,
                scrollDesc,
                scrollTime,
                easing
            )).animate();

            var args = [
                document.documentElement,
                scrollDesc,
                scrollTime,
                easing
            ];

            WindowScroll.superclass.constructor.apply(this, args);
        };

        WindowScroll.NAME = "WindowScroll";
        YAHOO.extend(WindowScroll, YAHOO.util.Scroll);

        CPANEL.animate.WindowScroll = WindowScroll;

    })();

} // end else statement
