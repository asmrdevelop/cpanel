/**
# cpanel - whostmgr/docroot/js/modules/pkgform-help.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/*
 * This file defines a simple module that helps when displaying
 * package fields in a form.
 */

const helpPanelMap = new Map();

const EVENT = YAHOO.util.Event;
const PANEL = YAHOO.widget.Panel;

const PANEL_CLASS = "account-resource-help";

export function cPSetupResourceHelp(helpEl, helpHeader, helpContent) {
    EVENT.on(helpEl, "mouseover", function() {
        if (!helpPanelMap.has(helpEl)) {
            const panel = new PANEL(
                `pkgform-help-${helpPanelMap.size}`,
                {
                    width: "250px",
                    fixedcenter: false,
                    draggable: false,
                    modal: false,
                    visible: false,
                    close: false,
                }
            );

            panel.element.classList.add(PANEL_CLASS);

            panel.setHeader(helpHeader);
            panel.cfg.setProperty("context", [
                helpEl,
                "tl",
                "br",
            ]);
            panel.setBody(helpContent);
            panel.render(helpEl);

            helpPanelMap.set( helpEl, panel );
        }

        helpPanelMap.get(helpEl).show();
    });

    EVENT.on(helpEl, "mouseout", function() {
        const panel = helpPanelMap.get(helpEl);
        if (panel) {
            panel.hide();
        }
    });
}
