/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 *
 * A module with various drag-and-drop implementations.
 * @module CPANEL.dragdrop
 *
 */

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including dragdrop.js!");
} else {

    // keep things out of global scope
    (function() {

        // cache variable lookups
        var DDM = YAHOO.util.DragDropMgr;
        var ddtarget_prototype = YAHOO.util.DDTarget.prototype;
        var get = DOM.get;
        var get_next_sibling = DOM.getNextSibling;
        var get_xy = DOM.getXY;
        var set_xy = DOM.setXY;
        var get_style = DOM.getStyle;
        var get_content_height = CPANEL.dom.get_content_height;
        var ease_out = YAHOO.util.Easing.easeOut;

        /**
         *
         * This class extends DDProxy with several event handlers and
         * a custom createFrame method. If you extend event handlers beyond this class,
         * be sure to call DDItem's handlers, e.g.:
         * DDItem.prototype.<event name>.apply(this, arguments);
         * @class DDItem
         * @namespace CPANEL.dragdrop
         * @extends YAHOO.util.DDProxy
         * @constructor
         * @param {String|HTMLElement} id See parent class documentation.
         * @param {String} sGroup See parent class documentation.
         * @param {config} Passed to parent class constructor, and also accepts:
         *                 drag_region: of type YAHOO.util.Region
         *                 placeholder: an HTML Element or ID to designate as the item's placeholder
         *                 animation: whether to animate DDItem interactions (default: true)
         *                 animation_proxy_class: class for a DDItem animation proxy (default: _cp_animation_proxy)
         *
         */
        var DDItem = function(id, sGroup, config) {
            DDItem.superclass.constructor.apply(this, arguments);

            if (!config) {
                return;
            }

            if ("drag_region" in config) {
                var region = config.drag_region;

                var el = this.getEl();
                var xy = get_xy(el);

                if (region.width) {
                    var width = el.offsetWidth;
                    var el_left = xy[0];
                    var left = el_left - region.left;
                    var right = region.right - el_left - width;
                    this.setXConstraint(left, right);
                }

                if (region.height) {
                    var height = el.offsetHeight;
                    var el_top = xy[1];
                    var top = el_top - region.top;
                    var bottom = region.bottom - el_top - height;
                    this.setYConstraint(top, bottom);
                }
            }

            if ("placeholder" in config) {
                var new_placeholder = get(config.placeholder);
                if (!new_placeholder && typeof config.placeholder === "string") {
                    new_placeholder = document.createElement("div");
                    new_placeholder.id = config.placeholder;
                }

                var _placeholder_style = new_placeholder.style;

                this._placeholder = new_placeholder;
                this._placeholder_style = _placeholder_style;

                _placeholder_style.position = "absolute";
                _placeholder_style.visibility = "hidden";
                document.body.appendChild(new_placeholder);

                // put this in the prototype so it's done once then available to all class members
                this.constructor.prototype._placeholder_hidden = true;
            }

            if ("animation" in config) {
                this._animation = config.animation;
            }
            if (this._animation) {
                if ("animation_proxy_class" in config) {
                    this._animation_proxy_class = config.animation_proxy_class;
                }
            }
        };

        YAHOO.extend(DDItem, YAHOO.util.DDProxy, {

            // initial values
            _going_up: null,
            _last_y: null,

            // defaults
            _animation: true,
            _animation_proxy_class: "_cp_animation_proxy",

            _sync_placeholder: function() {
                var placeholder = this._placeholder;
                var srcEl = this.getEl();
                if (!this._placeholder_hidden && this._animation) {
                    var motion = new YAHOO.util.Motion(
                        placeholder, {
                            points: {
                                to: get_xy(srcEl)
                            }
                        },
                        0.2
                    );
                    motion.animate();
                } else {
                    set_xy(placeholder, get_xy(srcEl));
                    this._placeholder_initialized = true;
                }
                if (this._placeholder_hidden) {
                    var _style = this._placeholder_style;
                    copy_size(srcEl, placeholder, _style);
                    _style.visibility = "";
                    this._placeholder_hidden = false;
                }
            },

            // override the default styles in DDProxy to create just a basic div
            createFrame: function() {
                var proxy = this.getDragEl();
                if (!proxy) {
                    proxy = document.createElement("div");
                    proxy.id = this.dragElId;
                    proxy.style.position = "absolute";
                    proxy.style.zIndex = "999";
                    document.body.insertBefore(proxy, document.body.firstChild);
                }
            },

            startDrag: function(x, y) {

                // make the proxy look like the source element
                var dragEl = this.getDragEl();
                var clickEl = this.getEl();

                dragEl.innerHTML = clickEl.innerHTML;
                clickEl.style.visibility = "hidden";
                if ("_placeholder" in this) {
                    this._sync_placeholder();
                }
            },

            endDrag: function(e) {
                var srcEl = this.getEl();
                var proxy = this.getDragEl();
                var proxy_style = proxy.style;

                // Show the proxy element and animate it to the src element's location
                proxy_style.visibility = "";
                var a = new YAHOO.util.Motion(
                    proxy, {
                        points: {
                            to: get_xy(srcEl)
                        }
                    },
                    0.2,
                    ease_out
                );

                var that = this;

                // Hide the proxy and show the source element when finished with the animation
                a.onComplete.subscribe(function() {
                    proxy_style.visibility = "hidden";
                    srcEl.style.visibility = "";

                    if ("_placeholder" in that) {
                        that._placeholder_style.visibility = "hidden";
                        that._placeholder_hidden = true;
                    }
                });
                a.animate();
            },

            onDrag: function(e) {

                // Keep track of the direction of the drag for use during onDragOver
                var y = EVENT.getPageY(e);
                var last_y = this._last_y;

                if (y < last_y) {
                    this._going_up = true;
                } else if (y > last_y) {
                    this._going_up = false;
                } else {
                    this._going_up = null;
                }

                this._last_y = y;
            },

            // detect a new parent element
            onDragEnter: function(e, id) {
                if (this.parent_id === null) {
                    var srcEl = this.getEl();
                    var destEl = get(id);

                    this.parent_id = id;

                    if (this.last_parent !== id) {
                        destEl.appendChild(srcEl);
                    }

                    if ("placeholder" in this) {
                        this._sync_placeholder();
                    }
                }
            },

            onDragOut: function(e, id) {
                if (this.getEl().parentNode === get(id)) {
                    this.last_parent = id;
                    this.parent_id = null;
                }
            },

            onDragOver: function(e, id) {
                var srcEl = this.getEl();
                var destEl = get(id);

                // we don't care about horizontal motion here
                var going_up = this._going_up;
                if (going_up === null) {
                    return;
                }

                // We are only concerned with draggable items, not containers
                var is_container = ddtarget_prototype.isPrototypeOf(DDM.getDDById(id));
                if (is_container) {
                    return;
                }

                var parent_el = destEl.parentNode;

                // When drag-dropping between targets, sometimes the srcEl is inserted
                // below the destEl when the mouse is going down.
                // The result is that the srcEl keeps being re-inserted and re-inserted.
                // Weed this case out.
                var next_after_dest = get_next_sibling(destEl);
                var dest_then_src = (next_after_dest === srcEl);
                if (!going_up && dest_then_src) {
                    return;
                }

                if (this._animation) {

                    // similar check to the above;
                    // this only seems to happen when there is animation
                    var src_then_dest = (get_next_sibling(srcEl) === destEl);
                    if (going_up && src_then_dest) {
                        return;
                    }

                    // only animate adjacent drags
                    if (src_then_dest || dest_then_src) {
                        dp_parent = document.body;

                        var dest_proxy = document.createElement("div");
                        dest_proxy.className = this._animation_proxy_class;
                        var dp_style = dest_proxy.style;

                        dp_style.position = "absolute";
                        dp_style.display = "none";
                        dest_proxy.innerHTML = destEl.innerHTML;
                        copy_size(destEl, dest_proxy, dp_style);
                        dp_parent.appendChild(dest_proxy);

                        var dest_proxy_motion_destination = get_xy(srcEl);
                        var height_difference = get_content_height(dest_proxy) - get_content_height(srcEl);
                        if (going_up) {
                            dest_proxy_motion_destination[1] -= height_difference;
                        }

                        var attrs = {
                            points: {
                                from: get_xy(destEl),
                                to: dest_proxy_motion_destination
                            }
                        };
                        var anim = new YAHOO.util.Motion(dest_proxy, attrs, 0.25);

                        var de_style = destEl.style;
                        anim.onComplete.subscribe(function() {
                            de_style.visibility = "";
                            dp_parent.removeChild(dest_proxy);
                        });

                        dp_style.display = "";
                        de_style.visibility = "hidden";
                        anim.animate();
                    }
                }

                if (going_up) {
                    parent_el.insertBefore(srcEl, destEl); // insert above
                } else {
                    parent_el.insertBefore(srcEl, next_after_dest); // insert below
                }

                if ("_placeholder" in this) {
                    this._sync_placeholder();
                }

                DDM.refreshCache();
            }
        });

        // pass in the style as a parameter to save a lookup
        var copy_size = function(src, dest, dest_style) {
            var br = parseFloat(get_style(dest, "border-right-width")) || 0;
            var bl = parseFloat(get_style(dest, "border-left-width")) || 0;
            var newWidth = Math.max(0, src.offsetWidth - br - bl);

            var bt = parseFloat(get_style(dest, "border-top-width")) || 0;
            var bb = parseFloat(get_style(dest, "border-bottom-width")) || 0;
            var newHeight = Math.max(0, src.offsetHeight - bt - bb);

            dest_style.width = newWidth + "px";
            dest_style.height = newHeight + "px";
        };

        CPANEL.dragdrop = {

            /**
             *
             * This method returns an object of "items" that can be drag-dropped
             * among the object's "containers".
             * @method containers
             * @namespace CPANEL.dragdrop
             * @param { Array | HTMLElement } containers Either a single HTML container (div, ul, etc.) or an array of containers to initialize as YAHOO.util.DDTarget objects and whose "children" will be initialized as CPANEL.dragdrop.DDItem objects.
             * @param { String } group The DragDrop group to use in initializing the containers and items.
             * @param { object } config Options for YAHOO.util.DDTarget and CPANEL.dragdrop.DDItem constructors; accepts:
             *                   item_constructor: function to use for creating the item objects (probably override DDItem)
             *
             */
            containers: function(containers, group, config) {
                if (!(containers instanceof Array)) {
                    containers = [containers];
                }

                var container_objects = [];
                var drag_item_objects = [];

                var item_constructor = (config && config.item_constructor) || DDItem;

                var containers_length = containers.length;
                for (var c = 0; c < containers_length; c++) {
                    var cur_container = get(containers[c]);
                    container_objects.push(new YAHOO.util.DDTarget(cur_container, group, config));

                    var cur_contents = cur_container.children;
                    var cur_contents_length = cur_contents.length;
                    for (var i = 0; i < cur_contents_length; i++) {
                        drag_item_objects.push(new item_constructor(cur_contents[i], group, config));
                    }
                }

                return {
                    containers: container_objects,
                    items: drag_item_objects
                };
            },
            DDItem: DDItem
        };

    })();

} // end else statement
