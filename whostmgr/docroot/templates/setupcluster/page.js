/**
 * Page-specific Javascript for Set Up Cluster Configuration page.
 * @class SetupCluster
 */

/* global jQuery */
/* jshint -W100 */

(function() {

    /**
     * After successful link creation, adds row to table.
     *
     * @method addServerRow
     */
    var addServerRow = function(name, user, key) {

        // build new row
        var newRow = document.createElement("tr");
        newRow.className = "serverLink";
        newRow.setAttribute("data-server", name);
        var nameCell = document.createElement("td");
        nameCell.className = "serverName";
        nameCell.innerHTML = name;
        var userCell = document.createElement("td");
        userCell.className = "userName";
        userCell.innerHTML = user;
        var keyCell = document.createElement("td");
        keyCell.className = "hashValue";
        keyCell.innerHTML = key;
        var actionsCell = document.createElement("td");
        actionsCell.className = "actions text-right";
        actionsCell.innerHTML = "";
        var deleteBtn = document.createElement("button");
        deleteBtn.className = "deleteBtn btn-link";
        var documentDirection = document.documentElement.dir;
        if (documentDirection !== "rtl") {
            deleteBtn.className += " newRowIconHack";
        }
        deleteBtn.type = "button";
        var deleteIcon = document.createElement("span");
        deleteIcon.className = "glyphicon glyphicon-trash";
        deleteBtn.appendChild(deleteIcon);
        deleteBtn.title = LOCALE.maketext("Delete entry for “[_1]”.", name);

        actionsCell.appendChild(deleteBtn);
        var manageBtn = document.createElement("button");
        manageBtn.className = "manageBtn btn-link";
        if (documentDirection === "rtl") {
            manageBtn.className += " newRowIconHack";
        }
        manageBtn.type = "button";
        manageBtn.title = LOCALE.maketext("Edit key for “[_1]”.", name);
        var manageIcon = document.createElement("span");
        manageIcon.innerHTML = "";
        manageIcon.className = documentDirection === "rtl" ? "glyphicon glyphicon-chevron-left" : "glyphicon glyphicon-chevron-right";
        manageBtn.appendChild(manageIcon);

        actionsCell.appendChild(manageBtn);

        newRow.appendChild(nameCell);
        newRow.appendChild(userCell);
        newRow.appendChild(keyCell);
        newRow.appendChild(actionsCell);

        jQuery("#serverList tr:last").after(newRow);

        jQuery("#serverList tr:last td:last button.deleteBtn").on("click", confirmDelete);
        jQuery("#serverList tr:last td:last button.manageBtn").on("click", editServerLink);

        // add success highlight color to new row

        jQuery("#serverList tr:last").addClass("success");

        // set timer to remove success color after 4 seconds

        window.setTimeout(function() {
            jQuery("#serverList tr:last").removeClass("success");
        }, 4000);
    };

    /**
     * Attempts to create new server link based on editor values.
     *
     * @method addServer
     */
    var addServer = function() {
        if (validateEditorData("create")) {
            jQuery("#serverSaveChanges").prop("disabled", true);
            CPANEL.api({
                application: "whm",
                func: "add_configclusterserver",
                data: {
                    name: jQuery("#serverNameEditor").val(),
                    key: jQuery("#serverKeyEditor").val(),
                    user: jQuery("#serverUserEditor").val(),
                },
                callback: {
                    success: addLinkServerSuccess,
                    failure: addLinkServerFailure,
                },
            });
        }
    };

    /**
     * Attempts to create update an existing server link based on editor values.
     *
     * @method updateServer
     */
    var updateServer = function() {
        if (validateEditorData("update")) {
            CPANEL.api({
                application: "whm",
                func: "update_configclusterserver",
                data: {
                    name: jQuery("#serverNameEditor").val(),
                    user: jQuery("#serverUserEditor").val(),
                    key: jQuery("#serverKeyEditor").val(),
                },
                callback: {
                    success: function(args) {
                        if (args.cpanel_raw.metadata.result === 1) {
                            updateLinkServerSuccess(args);
                        } else {
                            updateLinkServerFailure(args);
                        }
                    },
                    failure: updateLinkServerFailure,
                },
            });
        }
    };

    /**
     * Clears the values in the editor fields so placeholders displayed correctly for add
     *
     * @method clearEditorFields
     */
    var clearEditorFields = function() {

        // clear the fields in the editor

        jQuery("#serverNameEditor").val("");
        jQuery("#serverKeyEditor").val("");
        jQuery("#serverUserEditor").val("");

        // make sure the Save button is enabled

        jQuery("#serverSaveChanges").prop("disabled", false);

        // set the key editor placeholder back to the default

        jQuery("#serverKeyEditor").attr("placeholder", LOCALE.maketext("Paste the server’s API token here."));
    };

    /**
     * Provides basic front-end validation for editor values.
     *
     * @param {String} mode The type of change being attempted (create|update).
     * @method validateEditorData
     */

    var validateEditorData = function(mode) {
        var isValid = true;
        var errorMsg = "";
        var serverName = jQuery("#serverNameEditor").val().trim();
        var serverKey = jQuery("#serverKeyEditor").val().trim();
        var serverUser = jQuery("#serverUserEditor").val().trim();

        // check to see if both fields are filled
        if (mode === "create" && (!serverName || !serverKey || !serverUser)) {
            errorMsg = LOCALE.maketext("The server name, username, and API token are required.");
            isValid = false;
        } else if (mode === "create" && (!CPANEL.validate.host(serverName) && !CPANEL.validate.ip(serverName))) {
            errorMsg = LOCALE.maketext("The server name must be a valid host name or ip address.");
            isValid = false;
        } else if (mode === "create" && !serverUser.match(/^[0-9a-zA-Z]+/)) {
            errorMsg = LOCALE.maketext("The username can only include alphanumeric characters.");
            isValid = false;
        } else if (mode !== "create" && !serverUser && !serverKey) {
            errorMsg = LOCALE.maketext("You must specify both a username and an API token.");
            isValid = false;
        } else if (mode !== "create" && serverUser && !serverUser.match(/^[0-9a-zA-Z]+/)) {
            errorMsg = LOCALE.maketext("The username can only include alphanumeric characters.");
            isValid = false;
        }

        if (errorMsg) {
            showFailureMessage(errorMsg);
        }

        return isValid;
    };

    /**
     * Displays a global success message alert
     *
     * @param {String} message The message to be displayed
     * @method showSuccessMessage
     */
    var showSuccessMessage = function(message) {

        // hide any existing failure messages
        hideFailureMessage();
        jQuery("#globalSuccessMessage").html(message);
        if (jQuery("#globalSuccessNotice").hasClass("hidden")) {
            jQuery("#globalSuccessNotice").removeClass("hidden");
        }
        window.setTimeout(function() {
            jQuery("#globalSuccessNotice").addClass("hidden");
        }, 7000);
    };

    /**
     * Displays a global failure message alert
     *
     * @param {String} message The message to be displayed
     * @method showFailureMessage
     */
    var showFailureMessage = function(message) {
        hideSuccessMessage();
        jQuery("#globalFailureMessage").html(message);
        jQuery("#globalFailureNotice").removeClass("hidden");
    };

    /**
     * Hide any existing success message.
     *
     * @method hideSuccessMessage
     */
    var hideSuccessMessage = function() {
        if (!jQuery("#globalSuccessNotice").hasClass("hidden")) {
            jQuery("#globalSuccessNotice").addClass("hidden");
        }
    };

    /**
     * Hide any existing failure message.
     *
     * @method hideFailureMessage
     */
    var hideFailureMessage = function() {
        if (!jQuery("#globalFailureNotice").hasClass("hidden")) {
            jQuery("#globalFailureNotice").addClass("hidden");
        }
    };

    /**
    * Updates the user interface when a link entry has been successfully updated
    *
    * @param {Object} args Data returned by API call
    * @method updateLinkServerSuccess
    */
    var updateLinkServerSuccess = function(args) {
        var serverName = args.cpanel_raw.metadata.name;

        showSuccessMessage(LOCALE.maketext("Link definition for server, [output,strong,_1], successfully updated.", serverName));

        // update the row in the table

        jQuery("tr[data-server=\"" + serverName + "\"] td.hashValue").html(args.cpanel_raw.metadata.signature);
        jQuery("tr[data-server=\"" + serverName + "\"] td.userName").html(args.cpanel_raw.metadata.user);

        hideEditor();

        clearEditorFields();
    };

    /**
    * Updates the user interface when a link entry has not been successfully updated
    *
    * @param {Object} args Data returned by API call
    * @method updateLinkServerFailure
    */
    var updateLinkServerFailure = function(args) {
        try {
            showFailureMessage(LOCALE.maketext("Link definition for server, [output,strong,_1], not updated.", args.cpanel_raw.metadata.name));
        } catch (err) {
            showFailureMessage(LOCALE.maketext("Link definition for server not updated."));
        }
    };


    /**
    * Updates the user interface when a new link entry has been successfully created
    *
    * @param {Object} args Data returned by API call
    * @method addLinkServerSuccess
    */
    var addLinkServerSuccess = function(args) {
        hideEditor();

        var callbackData = args.cpanel_raw.metadata;

        showSuccessMessage(LOCALE.maketext("Link to server, [output,strong,_1], successfully created.", callbackData.name));
        addServerRow(callbackData.name, callbackData.user, callbackData.signature);

        if (jQuery("tbody").children(".serverLink").length > 0 && !jQuery("#noLinksDefined").hasClass("hidden")) {
            jQuery("#noLinksDefined").addClass("hidden");
        }

        clearEditorFields();
    };

    /**
    * Updates the user interface when a new link entry has been successfully created
    *
    * @param {Object} args Data returned by API call
    * @method addLinkServerFailure
    */
    var addLinkServerFailure = function(args) {
        try {
            showFailureMessage(LOCALE.maketext("Unable to create link to server “[output,strong,_1]”.", args.cpanel_raw.metadata.name));
        } catch (err) {
            showFailureMessage(LOCALE.maketext("Unable to create link to server."));
        }
    };

    /**
    * Updates the user interface when a link entry has not been successfully deleted
    *
    * @param {Object} args Data returned by API call
    * @method deleteLinkServerFailure
    */
    var deleteLinkServerFailure = function(args) {
        try {
            showFailureMessage(LOCALE.maketext("Unable to delete link to server “[output,strong,_1]”.", args.cpanel_raw.metadata.name));
        } catch (err) {
            showFailureMessage(LOCALE.maketext("Unable to delete link to server."));
        }
        jQuery("#serverDeleteContinueBtn").prop("disabled", false);
    };

    /**
    * Prompts the user to confirm that he/she really wants to delete a server link
    *
    * @method confirmDelete
    */
    var confirmDelete = function() {
        var itemToDelete = jQuery(this).closest("tr").data("server");

        jQuery("#serverToDelete").val(itemToDelete);
        jQuery("#confirmMessage").html(LOCALE.maketext("Delete link to server “[output,strong,_1]”?", itemToDelete));

        var itemRow = jQuery("tr[data-server=\"" + itemToDelete + "\"]");
        var confirmRow = jQuery("#confirmDelete").detach();
        confirmRow.insertAfter(itemRow);

        toggleButtonStateForInlineModalAlert(true);

        itemRow.addClass("hidden");
        confirmRow.removeClass("hidden");
    };

    /**
    * Processes a delete server link request (after user confirmation)
    *
    * @method doDelete
    */
    var doDelete = function() {
        jQuery("#serverDeleteContinueBtn").prop("disabled", true);
        CPANEL.api({
            application: "whm",
            func: "delete_configclusterserver",
            data: {
                name: jQuery("#serverToDelete").val(),
            },
            callback: {
                success: function(args) {
                    if (args.cpanel_raw.metadata.result === 1) {
                        var serverName = args.cpanel_raw.metadata.name;
                        jQuery("tr[data-server=\"" + serverName + "\"]").remove();
                        jQuery("#tableAlerts").append(jQuery("#confirmDelete").detach());
                        var rowsLeft = jQuery("tbody").children(".serverLink").length;
                        var noLinksWarningIsHidden = jQuery("#noLinksDefined").hasClass("hidden");
                        if (rowsLeft === 0 && noLinksWarningIsHidden) {
                            jQuery("#noLinksDefined").removeClass("hidden");
                        }
                        toggleButtonStateForInlineModalAlert(false);
                        showSuccessMessage(LOCALE.maketext("Link to server, [output,strong,_1], successfully deleted.", serverName));
                        jQuery("#serverDeleteContinueBtn").prop("disabled", false);
                    } else {
                        deleteLinkServerFailure(args);
                    }
                },
                failure: deleteLinkServerFailure,
            },
        });
    };

    /**
    * Returns user interface to prior state (after user cancels a delete)
    *
    * @method cancelDelete
    */
    var cancelDelete = function() {
        var rowToRestore = jQuery("#serverToDelete").val();
        var alertRow = jQuery("#confirmDelete").detach();
        jQuery("#tableAlerts").append(alertRow);
        jQuery("#serverToDelete").val("");
        jQuery("tr[data-server=\"" + rowToRestore + "\"]").removeClass("hidden");
        toggleButtonStateForInlineModalAlert(false);
    };

    /**
     * Clears error message. Enables Save button.
     *
     * @method clearError
     */
    var clearError = function() {
        if (jQuery("#globalFailureMessage").html() !== "") {
            hideFailureMessage();
            jQuery("#globalFailureMessage").html("");
            jQuery("#serverSaveChanges").prop("disabled", false);
        }
    };


    /**
     * Shows link editor for adding and updating server links.
     *
     * @param {String} mode Which version of the editor to display (edit | add)
     * @method showEditor
     */
    var showEditor = function(mode) {

        jQuery("#serverSaveChanges").off("click");
        jQuery("#createBtnContainer").addClass("hidden");
        jQuery("#serverList").addClass("hidden");
        jQuery("#extraCreateButton").addClass("hidden");
        if (mode === "edit") {
            jQuery("#editServerHeadline").removeClass("hidden");
            jQuery("#addServerHeadline").addClass("hidden");
            jQuery("#serverSaveChanges").on("click", updateServer);
            jQuery("#serverNameEditor").prop("disabled", true);
        } else {
            jQuery("#editServerHeadline").addClass("hidden");
            jQuery("#addServerHeadline").removeClass("hidden");
            jQuery("#serverSaveChanges").on("click", addServer);
            jQuery("#serverUserEditor").val("root");
        }
        jQuery("#serverLinkEditor").removeClass("hidden");
        if (mode === "edit") {
            jQuery("#serverKeyEditor").focus();
        } else {
            jQuery("#serverNameEditor").focus();
        }
    };

    /**
     * Hides link editor and shows list again.
     *
     * @method hideEditor
     */
    var hideEditor = function() {
        jQuery("#serverLinkEditor").addClass("hidden");
        jQuery("#createBtnContainer").removeClass("hidden");
        jQuery("#serverList").removeClass("hidden");
        jQuery("#extraCreateButton").removeClass("hidden");
        jQuery("#serverNameEditor").prop("disabled", false);
    };

    /**
     * Disables/enables all user interface buttons except for those in the editor.
     * This prevents the application getting into a confusing state.
     *
     * @param {Boolean} disabled Determines which state buttons should reflect (true if you want buttons disabled)
     * @method toggleButtonStateForInlineModalAlert
     */
    var toggleButtonStateForInlineModalAlert = function(disabled) {

        if (disabled) {
            jQuery("#createBtn").attr("disabled", "disabled");
            jQuery("#createBtn2").attr("disabled", "disabled");
            jQuery(".deleteBtn").prop("disabled", disabled);
            jQuery(".manageBtn").prop("disabled", disabled);
            jQuery(".deleteBtn").addClass("disabled");
            jQuery(".manageBtn").addClass("disabled");
        } else {
            jQuery("#createBtn").removeAttr("disabled");
            jQuery("#createBtn2").removeAttr("disabled");
            jQuery(".deleteBtn").removeAttr("disabled");
            jQuery(".manageBtn").removeAttr("disabled");
            jQuery(".deleteBtn").removeClass("disabled");
            jQuery(".manageBtn").removeClass("disabled");
        }
    };

    /**
     * Shows editor populated with correct values for server in clicked row.
     *
     * @method editServerLink
     */
    var editServerLink = function() {
        var itemToEdit = jQuery(this).closest("tr").data("server");
        var scrambledKey = jQuery(this).closest("tr").children().filter(".hashValue").html();
        var userName = jQuery(this).closest("tr").children().filter(".userName").html();
        jQuery("#serverNameEditor").val(itemToEdit);
        jQuery("#serverUserEditor").attr("placeholder", userName);
        jQuery("#serverKeyEditor").attr("placeholder", LOCALE.maketext("Paste the replacement API token here. The current signature is: [_1]", scrambledKey.trim()));
        showEditor("edit");
    };

    /*
     * Initializes page-specific object.
     *
     * @method initialize
     */

    var initialize = function() {

        jQuery("#serverSaveChanges").on("click", addServer);

        jQuery(".deleteBtn").on("click", confirmDelete);

        jQuery("#goBack").on("click", function() {
            hideFailureMessage();
            hideSuccessMessage();
            hideEditor();
            clearEditorFields();
        });

        jQuery("#serverNameEditor").on("input", clearError);
        jQuery("#serverUserEditor").on("input", clearError);
        jQuery("#serverKeyEditor").on("input", clearError);

        jQuery("#createBtn").on("click", function() {
            showEditor("add");
        });

        jQuery("#createBtn2").on("click", function() {
            showEditor("add");
        });

        jQuery("#serverDeleteCancelBtn").on("click", cancelDelete);
        jQuery("#serverDeleteContinueBtn").on("click", doDelete);

        jQuery("#hideSuccessAlertBtn").on("click", function() {
            jQuery("#globalSuccessNotice").addClass("hidden");
        });

        jQuery("#hideFailureAlertBtn").on("click", function() {
            jQuery("#globalFailureNotice").addClass("hidden");
        });

        // Firefox seems to want to remember a bunch of
        // crap between reloads. What a pain.

        // force serverToDelete to empty string
        jQuery("#serverToDelete").val("");

        // clear the name and key fields in the editor
        clearEditorFields();

        // enable all buttons
        toggleButtonStateForInlineModalAlert(false);

        jQuery(".manageBtn").on("click", editServerLink);
    };

    jQuery(document).ready(initialize);
}());
