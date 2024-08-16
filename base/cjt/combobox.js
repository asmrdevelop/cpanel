// CPANEL.widgets.Combobox
// extends YAHOO.widget.AutoComplete
//
// will automatically create/insert a container element as needed
// extra option: expander, a DOM element that rotates with expand/collapse
//
// requires YAHOO.util.DataSource and YAHOO.widget.AutoComplete
(function() {
    var default_ac_config = {
        useShadow: false,
        autoHighlight: false,
        queryDelay: 0,
        animVert: false,
        minQueryLength: 0
    };

    /*
     * A combobox widget built on YUI 2 AutoComplete.
     *
     * NOTE: This widget is a bit messy to set up. (Sorry.)
     *
     * REQUIRES:
     *  JS:  YUI 2 Autocomplete
     *  CSS: YUI 2 Sam-skin autocomplete
     *       CJT combobox.css
     *  HTML:
     *      <div class="cjt-combobox-wrapper">
     *          <input><a class="cjt-combobox-expander"></a>
     *      </div>
     *
     * Parameters are the same as YUI 2 Autocomplete, plus these properties:
     *  expander: An element to use as the "expander".
     */
    var Combobox = function(input, ac_container, datasource, ac_config) {
        if (typeof input === "string") {
            input = DOM.get(input);
        }

        if (!(datasource instanceof YAHOO.util.DataSourceBase)) {
            datasource = new YAHOO.util.LocalDataSource(datasource);
        }

        if (typeof ac_container === "string") {
            ac_container = DOM.get(ac_container);
        }
        if (!ac_container) {
            ac_container = document.createElement("div");
            input.parentNode.insertBefore(ac_container, input.nextSibling);
        }

        if (!ac_config) {
            ac_config = {};
        }
        YAHOO.lang.augmentObject(ac_config, default_ac_config);

        Combobox.superclass.constructor.call(this, input, ac_container, datasource, ac_config);

        var cb = this;

        if (this.expander) {
            this.expander = DOM.get(this.expander);
            DOM.addClass(this.expander, "cjt-combobox-expander");
            if (!this.expander.innerHTML) {
                this.expander.innerHTML = "&#9660;";
            }
            EVENT.on(this.expander, "mousedown", this._mousedown_expand, this, true);
        }

        DOM.addClass(ac_container, "cjt-combobox");

        var input = cb.getInputEl();
        EVENT.on(input, "blur", this._on_textbox_blur, this, true);
        EVENT.on(input, "blur", this._reset_autocomplete_keycode, this, true);
        EVENT.on(input, "focus", this._on_textbox_focus, this, true);

        this.containerExpandEvent.subscribe(this._on_container_expand);
        this.containerCollapseEvent.subscribe(this._on_container_collapse);

        this.disableEvent = new YAHOO.util.CustomEvent("disable", this);
        this.enableEvent = new YAHOO.util.CustomEvent("enable", this);
    };

    Combobox.DISABLED_CLASS = "disabled";

    YAHOO.lang.extend(Combobox, YAHOO.widget.AutoComplete, {
        expander_expanded_class: "open",

        destroy: function() {
            this.disableEvent.unsubscribeAll();
            this.enableEvent.unsubscribeAll();

            return Combobox.superclass.prototype.destroy.apply(this, arguments);
        },

        disable: function() {
            DOM.addClass(this.getContainerEl(), Combobox.DISABLED_CLASS);
            this.getInputEl().disabled = true;

            var hz = this.animHoriz;
            var vt = this.animVert;

            this.collapseContainer();

            this.animHoriz = hz;
            this.animVert = vt;

            this._disabled = true;

            this.disableEvent.fire(this);
        },

        enable: function() {
            DOM.removeClass(this.getContainerEl(), Combobox.DISABLED_CLASS);
            this.getInputEl().disabled = false;

            this._disabled = false;

            this.enableEvent.fire(this);
        },

        _disabled: false,

        // In stock YUI 2, if you tab out of a combobox input, then click the
        // expander, AutoComplete will still "remember" the tab and collapse on any
        // mousedown in the expanded container, which prevents "click"ing anything.
        // This fix is a small faux pas since it's mucking with AutoComplete's own
        // private variable, but YUI 2 is not expected to be updated again, so it
        // should be fine.
        _reset_autocomplete_keycode: function() {
            this._nKeyCode = null;
        },

        // in case the autocomplete is set to animate
        _is_collapsing: false,

        _is_expanded: false,

        _prevent_sendQuery_on_focus: false,

        // This is so AutoComplete doesn't put in a value right away
        // when we focus the element.
        _dummy_value: "\t\t\t", // unlikely to occur normally

        _kill_dummy_value: function(type, args) {
            var input_el = this.getInputEl();
            if (input_el.value === this._dummy_value) {
                input_el.value = "";
                this.dataReturnEvent.unsubscribe(this._kill_dummy_value);
            }
        },

        _on_textbox_blur: function() {
            this._is_collapsing = true;
        },

        _on_textbox_focus: function(e) {
            if (!this._prevent_sendQuery_on_focus && !this.isContainerOpen()) {

                // Prevent a flash on/off of an HTML5 placeholder
                var input_el = this.getInputEl();
                var value = input_el.value;
                if (input_el.placeholder && (value === "")) {
                    input_el.value = this._dummy_value;
                    this.dataReturnEvent.subscribe(this._kill_dummy_value);
                }
                this.sendQuery(value || "");
            }
        },

        _on_container_expand: function() {

            // this event fires every time the autocomplete list is updated,
            // so filter out consecutive expansions
            if (!this._is_expanded) {
                var cb = this;
                var anim = new CPANEL.animate.Rotation(cb.expander, {
                    from: 0,
                    to: 180
                }, 0.2);
                anim.onComplete.subscribe(function() {
                    DOM.addClass(cb.expander, cb.expander_expanded_class);
                });
                anim.animate();

                this._is_expanded = true;
            }
        },

        _on_container_collapse: function() {
            if (this._is_expanded) {
                var cb = this;
                var anim = new CPANEL.animate.Rotation(cb.expander, {
                    from: 180,
                    to: 360
                }, 0.2);
                anim.onComplete.subscribe(function() {
                    DOM.removeClass(cb.expander, cb.expander_expanded_class);
                });
                anim.animate();

                this._is_collapsing = false;
                this._is_expanded = false;
            }
        },

        _mousedown_expand: function() {

            // Is open
            if (this.isContainerOpen()) {
                if (!this._is_collapsing) {
                    this.collapseContainer();
                }
            } else if (!this._disabled) { // Is closed
                var input_el = this.getInputEl();
                var cb = this;
                setTimeout(function() { // For IE
                    cb.sendQuery(input_el.value);
                    cb._prevent_sendQuery_on_focus = true;
                    cb.containerCollapseEvent.subscribe(function suppress() {
                        cb.containerCollapseEvent.unsubscribe(suppress);
                        cb._prevent_sendQuery_on_focus = false;
                    });
                    input_el.focus(); // Needed to keep widget active
                }, 0);
            }
        }
    });
    Combobox.NAME = "Combobox";

    CPANEL.widgets.Combobox = Combobox;

})();
