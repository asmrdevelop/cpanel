// Copyright 2022 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

let maxTeamUsersHelpPanel;

EVENT.on("max-team-users__help", "mouseover", function() {
    "use strict";
    if (!maxTeamUsersHelpPanel) {
        maxTeamUsersHelpPanel = new YAHOO.widget.Panel(
            "max-team-users__help-panel",
            {
                width: "250px",
                fixedcenter: false,
                draggable: false,
                modal: false,
                visible: false,
                close: false,
            }
        );

        maxTeamUsersHelpPanel.setHeader(LOCALE.maketext("Set Max Team Users with Roles"));
        maxTeamUsersHelpPanel.cfg.setProperty("context", [
            DOM.get("max-team-users__help"),
            "tl",
            "br",
        ]);
        maxTeamUsersHelpPanel.setBody(DOM.get("max-team-users__help-content"));
        maxTeamUsersHelpPanel.render(DOM.get("max-team-users__help"));

        DOM.get("max-team-users__help-content").style = "";
    }

    maxTeamUsersHelpPanel.show();
});

EVENT.on("max-team-users__help", "mouseout", function() {
    "use strict";
    if (maxTeamUsersHelpPanel) {
        maxTeamUsersHelpPanel.hide();
    }
});
