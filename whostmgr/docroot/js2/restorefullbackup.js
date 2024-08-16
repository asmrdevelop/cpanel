/* jshint -W098 */
(function(window) {

    "use strict";

    var EVENT = window.EVENT;
    var CPANEL = window.CPANEL;
    var LOCALE = window.LOCALE;
    var YAHOO = window.YAHOO;
    var PAGE = window.PAGE || {};
    var document = window.document;
    var VALIDATORS = {};
    var usernameIsVisible = true; // Global flag to prevent the ajax call from enabling the field while hidden

    var USER_COMBOBOX_CONFIG = {
        useShadow: false,
        expander: "userexpander",
        applyLocalFilter: true,
        queryMatchCase: false,
        typeAhead: true,
        autoHighlight: false
    };

    /**
     * Function to clear CJT validation messages
     *
     * @method clearValidation
     */
    var clearValidation = function() {
        ["restoreFile", "user"].forEach(function(validation_type) {
            if (VALIDATORS[validation_type]) {
                VALIDATORS[validation_type].clear_messages();
            }
        });
    };

    /**
     * Function to toggle what input we use
     *
     * @method toggleInput
     */
    var toggleInput = function(e, toggleTo) {

        if (CPANEL.PAGE.fileInputAnimation) {
            e.preventDefault();
            return;
        }

        toggleTo = toggleTo === "username" ? "username" : "file";

        /* current state is already expanded to the correct 'restoreWith' */
        if (toggleTo === CPANEL.PAGE.restoreWithState) {
            return;
        }

        var restoreRadio = CPANEL.Y.all("input[name='restoreOption']"),
            restoreWithUsername = CPANEL.Y.one("#restoreWithUsername"),
            userInputWrapper = CPANEL.Y.one("#userInputWrapper"),
            fileInputWrapper = CPANEL.Y.one("#fileInputWrapper"),
            fileInput = CPANEL.Y.one("#restorePackage"),
            userInput = CPANEL.Y.one("#user"),
            restoreAnimation;

        CPANEL.PAGE.restoreWithState = toggleTo;

        // We only need to track one animation since they both have the same animate time and will finish at the same time.
        if (toggleTo === "username") {
            CPANEL.PAGE.restoreAnimation = CPANEL.animate.slide_down(userInputWrapper);
            CPANEL.PAGE.fileInputAnimation = CPANEL.animate.slide_up(fileInputWrapper);
            CPANEL.PAGE.fileInputAnimation.onComplete.subscribe(function() {

                // Resets input ty=e"file" since browsers won't let you modify value
                CPANEL.Y.one("#restorePackage").parentElement.innerHTML = CPANEL.Y.one("#restorePackage").parentElement.innerHTML;

                // We have to 'reset' the validators since the html is being regenerated and the previous validator lost
                VALIDATORS.restoreFile.validators = [];
                VALIDATORS.restoreFile.add_for_submit("restorePackage", validateFileExists, LOCALE.maketext("You must provide a file."), function() {
                    return !CPANEL.Y.one("#restoreWithUsername").checked;
                });
            });
            fileInput.disabled = true;
            userInput.disabled = false;
            VALIDATORS.restoreFile.attach();
        } else {
            fileInput.disabled = false;
            userInput.disabled = true;
            CPANEL.PAGE.restoreAnimation = CPANEL.animate.slide_up(userInputWrapper);
            CPANEL.PAGE.fileInputAnimation = CPANEL.animate.slide_down(fileInputWrapper);
        }
        CPANEL.PAGE.fileInputAnimation.onComplete.subscribe(function() {

            /* on complete of fileInputAnimation destroy it */
            CPANEL.PAGE.fileInputAnimation = null;
        });

        clearValidation();
    };


    /**
     * Function that calls the list_cparchive_files API and passes the result to generate a
     *   Combobox for the user.
     *
     * @method refreshMatchingFiles
     */
    var refreshMatchingFiles = function() {
        var userComboInfo = [];
        PAGE["userList"] = {};

        CPANEL.Y.one("#user").disabled = true;
        YAHOO.util.Dom.addClass("user", "processing");

        CPANEL.api({
            func: "list_cparchive_files",
            api_data: {
                sort: [
                    ["user", "lexicographic"]
                ]
            },
            callback: {
                success: function(o) {

                    if (usernameIsVisible) {
                        CPANEL.Y.one("#user").disabled = false;
                    }
                    YAHOO.util.Dom.removeClass("user", "processing");

                    if (o.cpanel_data && o.cpanel_data.length > 0) {
                        for (var x = 0; x < o.cpanel_data.length; x++) {

                            // Push the username into a user array
                            userComboInfo.push({
                                "name": o.cpanel_data[x]["user"],
                                "fileInfo": o.cpanel_data[x]["path"] + "/" + o.cpanel_data[x]["file"]
                            });

                            // We create an object of users so we can validate against that in O(n).
                            PAGE["userList"][o.cpanel_data[x]["user"]] = o.cpanel_data[x]["path"] + "/" + o.cpanel_data[x]["file"];
                        }
                    } else {
                        userComboInfo.push({
                            "name": LOCALE.maketext("None"),
                            "fileInfo": LOCALE.maketext("No matching files were found.")
                        });
                    }
                    initializeSelector(userComboInfo);
                },
                failure: function() {
                    CPANEL.Y.one("#user").disabled = false;
                    YAHOO.util.Dom.removeClass("user", "processing");

                    userComboInfo.push({
                        "name": LOCALE.maketext("None"),
                        "fileInfo": LOCALE.maketext("Unable to get retrieve list of files, please try again later.")
                    });
                    initializeSelector(userComboInfo);
                }
            }
        });
    };

    /**
     * Sets the filePath.  Triggered on validation.
     *
     * @method setFilePath
     */
    var setFilePath = function(filePath) {
        var filePathInput = CPANEL.Y.one("#filepath"),
            filePathDisplay = CPANEL.Y.one("#filepathDisplay");
        if (!filePath) {
            filePath = LOCALE.maketext("No filepath associated with username.");
            filePathInput.value = "";
        } else {
            filePathInput.value = filePath;
        }
        filePathDisplay.innerHTML = filePath;
    };

    /**
     * Validator for username.  We generate an object with each user added and do a lookup to verify
     *   it exists.  If not return false.
     *
     * @method validateUserComboSelect
     */
    var validateUserComboSelect = function() {
        if (!PAGE["userList"]) {
            return false;
        } else {
            return !!PAGE["userList"][CPANEL.Y.one("#user").value];
        }
    };

    /**
     * Validates the file exists.  The existing validator functions were not working with type="file"
     *
     * @method validateFileExists
     */
    var validateFileExists = function() {
        var fileName = CPANEL.Y.one("#restorePackage").value;
        if (fileName.trim().length > 0) {
            return true;
        } else {
            return false;
        }
    };

    /**
     * This function creates the Combobox and attaches data for it.  It also sets the format
     *   and ties an event listener to the onSelect of the combobox.
     *   it exists.  If not return false.
     *
     * @method initializeSelector
     * @param {object} userComboInfo An object that contains 'file', 'path', and 'user' returned from 'list_cparchive_files'
     */
    var initializeSelector = function(userComboInfo) {

        // We create a DataSource here since we are passing in an object instead of an array.  Normally
        //  Combobox will create it's own DataSource in this same manner but we would be unable to
        //  edit the responseSchema otherwise.
        var dataSource = new YAHOO.util.LocalDataSource(userComboInfo);
        dataSource.responseSchema = {
            fields: ["name", "fileInfo"]
        };

        var cfg = YAHOO.lang.augmentObject({
            maxResultsDisplayed: userComboInfo.length
        }, USER_COMBOBOX_CONFIG);
        var userCombo = new CPANEL.widgets.Combobox(CPANEL.Y.one("#user"), null, dataSource, cfg);

        userCombo.resultTypeList = false;

        // If we select a user we also want to trigger the validate
        userCombo.itemSelectEvent.subscribe(function(eventName, data) {

            // Data[2] is the object associated with the item the user selects and contains 'name' and 'fileInfo'
            if (data[2]) {
                setFilePath(data[2]["fileInfo"]);
            }
            VALIDATORS.user.verify();
        });

        // Normally a template would be a better choice but this call is being made on every draw,
        //  so for a list that has a huge dataset this will cause freezing
        userCombo.formatResult = function(oResultData) {
            return "<strong>" + oResultData.name + "</strong>" + "<p class=\"text-muted small\">" + oResultData.fileInfo + "</p>";
        };

    };

    /**
     * This function initializes all the validators and ties an event to the file onChange
     *
     * @method initializeValidators
     */
    var initializeValidators = function() {
        VALIDATORS.user = new CPANEL.validate.validator(LOCALE.maketext("User Name"));
        VALIDATORS.user.add_for_submit("user", "min_length($input$.trim(),1)", LOCALE.maketext("You must provide a username."), function() {
            return CPANEL.Y.one("#restoreWithUsername").checked;
        });
        VALIDATORS.user.add("user", validateUserComboSelect, LOCALE.maketext("You must choose a valid username."), function() {
            return CPANEL.Y.one("#restoreWithUsername").checked;
        });
        VALIDATORS.user.attach();

        VALIDATORS.restoreFile = new CPANEL.validate.validator(LOCALE.maketext("Restore File"));
        VALIDATORS.restoreFile.add_for_submit("restorePackage", validateFileExists, LOCALE.maketext("You must provide a file."), function() {
            return !CPANEL.Y.one("#restoreWithUsername").checked;
        });
        VALIDATORS.restoreFile.attach();

        var submitButton = CPANEL.Y.one("#restoreButton");

        CPANEL.validate.attach_to_form(submitButton.id, VALIDATORS, {
            no_panel: true,
            success_callback: function() {
                document.forms["restoreForm"].submit();
            }
        });
    };

    /**
     * This function sets the validation up and triggers the refreshMatchingFiles function to load data on the page.
     *
     * @method init
     */
    var init = function() {
        EVENT.on(CPANEL.Y.all("#restoreWithFile , #restoreWithUsername"), "click", function(e) {
            var toggleTo = e.currentTarget.id === "restoreWithFile" ? "file" : "username";
            toggleInput.call(this, e, toggleTo);
        });
        EVENT.on(CPANEL.Y.one("#user"), "input", function() {
            setFilePath(PAGE["userList"][CPANEL.Y.one("#user").value]);
        });

        initializeValidators();
        toggleInput(null, "username");
        refreshMatchingFiles();
    };

    EVENT.onDOMReady(init);
})(window);
