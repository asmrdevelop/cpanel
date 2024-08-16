/*

    This code disables and enables stylesheets as the resolution changes.

    Dependencies: YUI2
    Author: Patrick Hunlock
    Last Mod: 8-4-2010

    # cpanel - scaler.js                              Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited

    Nomenclature: a stylesheet with an ID which identifies it as a resolution dependent stylesheet
    is refered to as an "activated stylesheet" in this documentation.

    Activated stylesheets must have an id of "Label--resolution" to be recognized by this script.
    The double-dash (--) is a delimeter and identifier; it is important.
    The label identifies a range group and should be the same value for all stylesheets that define that group.
    The resolution identifies the minimum resolution needed to activate the stylesheet.

    Activated Stylesheets can either be <link>s or <style>s so long as the ID is formatted propperly

    <link rel="stylesheet" type="text/css" href="lowres.css" id="ss1--0" disabled="disabled" />
    <link rel="stylesheet" type="text/css" href="medres.css" id="ss1--800" disabled="disabled" />
    <link rel="stylesheet" type="text/css" href="highres.css" id="ss1--1200" disabled="disabled" />

    ss1-0 will be active when the screen resolution is between 0 and 800px.  All others will be inactive
    ss1-800 will be active when the screen resoltuion is 800-1199px.  All others will be inactive.
    ss1-1200 will be active when the screen resolution is 1200 or higher. All others will be inactive.

    If you remove the id="ss1-0" stylesheet and the resolution is below 800
    then NO activated stylesheets will be active.

    The label portion of the ID identifies the resolution set.

    <link rel="stylesheet" type="text/css" href="global.css" id="global--0" disabled="disabled" />
    <link rel="stylesheet" type="text/css" href="local.css" id="local--0" disabled="disabled" />

    Both global.css and local.css will be active if the resolution is zero or higher.

    Two links with the same label and resolution definition will result in unpredictable results.
    Duplicate resolutions are NOT checked for in the code.  If you need more than one stylesheet
    active at a certain resolution, ensure the label portions of the ID are different.

    It is HIGHLY recommended activated style sheets be defined with disabled="disabled"

    Feel free to define as many activated stylesheet <link>s as you need.

    CPANEL.scaleRes (event, forceWidth) is available as a function call.
    Event is ignored but must be present.

*/

// check to be sure the CPANEL global object already exists
if (typeof (CPANEL) === "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including scaler.js!");
} else {
    YAHOO.util.Event.onDOMReady(
        function() {
            if (document.styleSheets) {

                CPANEL.scaleRes = function(ev, forceWidth) { // Activate the appropriate stylesheet
                    var curRes = forceWidth || YAHOO.util.Dom.getViewportWidth();
                    for (var group = 0; group < grouped_sheets_length; group++) {
                        var useStyleSheet = -1;
                        var current_group = grouped_sheets[group];
                        var group_length = current_group.length;
                        for (var i = 0; i < group_length; i++) { // Find the right stylesheet to use
                            if (curRes >= current_group[i].res) {
                                useStyleSheet = i;
                            }
                        }
                        if (current_group.lastActive != useStyleSheet) {
                            if (current_group.lastActive >= 0) {
                                current_group[current_group.lastActive].obj.disabled = true;
                            }
                            if (useStyleSheet >= 0) {
                                current_group[useStyleSheet].obj.disabled = false;
                            }
                            current_group.lastActive = useStyleSheet;
                        }
                    }
                };

                var sheets = document.styleSheets.length;
                var grouped_sheets = [];
                var scratch_groups = {};
                var grouped_sheets_length = 0;

                // Extract stylesheets we're going to use

                for (var i = 0; i < sheets; i++) {
                    var current_sheet = document.styleSheets[i];
                    if (current_sheet.ownerNode.id) { // Must have an id
                        var sheetId = current_sheet.ownerNode.id.split("--"); // must have a -- delimeter
                        var group_name = sheetId[0];
                        var sheet_range = sheetId[1];
                        if (/^\d+$/i.test(sheet_range)) { // second parameter must be a number
                            if (group_name in scratch_groups) {
                                group_index = scratch_groups[group_name].id;
                            } else { // Initialize a range set we haven't seen before.
                                group_index = grouped_sheets_length++;
                                scratch_groups[group_name] = {
                                    "id": group_index
                                };
                                grouped_sheets[group_index] = [];
                                grouped_sheets[group_index].lastActive = -999;
                            }

                            // Activated stylesheet so push the min res size, and node into the array
                            grouped_sheets[group_index].push({
                                "res": sheet_range, // Minimum resolution needed to activate this sheet
                                "obj": document.styleSheets[i]
                            });
                        }
                    }
                }

                // If we have resolution activated stylesheets, setup the sheets and events
                if (grouped_sheets_length) {
                    for (var group = 0; group < grouped_sheets_length; group++) {
                        grouped_sheets[group].sort(function(a, b) {
                            return (a.res - b.res);
                        });
                    }

                    // Set the initial stylesheet disabled states
                    var curRes = YAHOO.util.Dom.getViewportWidth();
                    for (var group = 0; group < grouped_sheets_length; group++) {
                        var current_group = grouped_sheets[group];
                        var group_length = current_group.length;
                        var useStyleSheet = -1;
                        for (var i = 0; i < group_length; i++) { // Find the right stylesheet to use
                            if (curRes >= current_group[i].res) {
                                useStyleSheet = i;
                            }
                        }

                        // Set the initial states for this group.
                        for (var i = 0; i < group_length; i++) {
                            current_group[i].obj.disabled = (!(i == useStyleSheet));
                        }
                        if (useStyleSheet >= 0) {
                            current_group.lastActive = useStyleSheet;
                        }
                    }

                    // Attach the event
                    YAHOO.util.Event.addListener(window, "resize", CPANEL.scaleRes);

                }
            }

        }
    );

}
