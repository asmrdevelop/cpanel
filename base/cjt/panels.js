/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including panels.js!");
} else {

    /**
    The panels module contains methods for creating and controlling help and modal panels.
    @module panels
*/

    /**
    The panels class contains methods for creating and controlling help and modal panels.
    @class panels
    @namespace CPANEL
    @extends CPANEL
*/
    CPANEL.panels = {

        /**
        An object of all the help panels.
        @property help_panels
    */
        help_panels: {},

        /**
        Initialize a help panel and add an event listener to toggle it's display.
        @method create_help
        @param {DOM element} panel_el The DOM element to toggle the display of the panel.
        @param {DOM element} help_el The DOM element containing the help text.
    */
        create_help: function(panel_el, help_el) {

            // get the elements
            panel_el = YAHOO.util.Dom.get(panel_el);
            help_el = YAHOO.util.Dom.get(help_el);

            // destroy the panel if it already exists (ie: if we call create_help twice on the same page)
            if (this.help_panels[panel_el.id]) {
                this.help_panels[panel_el.id].destroy();
            }

            // create the panel
            var panel_id = panel_el.id + "_yuipanel";
            var panel_options = {
                width: "300px",
                visible: false,
                draggable: false,
                close: false,
                context: [panel_el.id, "tl", "br", ["beforeShow", "windowResize", CPANEL.align_panels_event]],
                effect: {
                    effect: YAHOO.widget.ContainerEffect.FADE,
                    duration: 0.25
                }
            };
            this.help_panels[panel_el.id] = new YAHOO.widget.Panel(panel_id, panel_options);

            // body
            this.help_panels[panel_el.id].setBody(help_el.innerHTML);

            // footer
            var close_div_id = panel_el.id + "_yuipanel_close_div";
            var close_link_id = panel_el.id + "_yuipanel_close_link";
            var footer = '<div style="text-align: right">';
            footer += '<a id="' + close_link_id + '" href="javascript:void(0);">' + LOCALE.maketext("Close") + "</a>";
            footer += "</div>";
            this.help_panels[panel_el.id].setFooter(footer);

            // render the panel
            this.help_panels[panel_el.id].render(document.body);

            // put the focus on the close link after the panel is shown
            this.help_panels[panel_el.id].showEvent.subscribe(function() {
                YAHOO.util.Dom.get(close_link_id).focus();
            });

            // add the "help_panel" style class to the panel
            YAHOO.util.Dom.addClass(panel_id, "help_panel");

            // add the event handlers to close the panel
            YAHOO.util.Event.on(close_link_id, "click", function() {
                CPANEL.panels.toggle_help(panel_el.id);
            });

            // add the event handler to the toggle element
            YAHOO.util.Event.on(panel_el.id, "click", function() {
                CPANEL.panels.toggle_help(panel_el.id);
            });
        },

        /**
        Toggle a single help panel.
        @method toggle_help
        @param {DOM element} el The id of the DOM element containing the help text.
    */
        toggle_help: function(el) {
            if (this.help_panels[el].cfg.getProperty("visible") === true) {
                this.help_panels[el].hide();
            } else {
                this.hide_all_help();
                this.help_panels[el].show();
            }
        },

        /**
        Show a single help panel.
        @method show_help
        @param {DOM element} el The id of the DOM element containing the help text.
    */
        show_help: function(el) {
            this.help_panels[el].show();
        },

        /**
        Hide a single help panel.
        @method hide_help
        @param {DOM element} el The id of the DOM element containing the help text.
    */
        hide_help: function(el) {
            this.help_panels[el].hide();
        },

        /**
        Hides all help panels.
        @method hide_all_help
    */
        hide_all_help: function() {
            for (var i in this.help_panels) {
                this.help_panels[i].hide();
            }
        }

    }; // end panels object
} // end else statement
