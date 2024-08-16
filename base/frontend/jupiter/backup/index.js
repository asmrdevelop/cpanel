/*
# cpanel - base/frontend/jupiter/backup/index.js
                                                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    /* global YAHOO, document */

    /**
     * List of file validators and if they are currently enabled.
     * These states are used with the validation control function returned by makeValidatorControlFunction().
     * @type {Object}
     */
    var enableFileValidator = {
        "restore-home-file": true,
        "restore-db-file": true,
        "restore-forwarder-file": true,
        "restore-filter-file": true,
    };

    /**
     * List of forms and the handlers for that forms submit action.
     * Each name is an id on the actual form.
     * @type {Object}
     */
    var uploads = {
        "restore-db-form": handleDatabaseRestore,
        "restore-home-form": handleHomeFilesRestore,
        "restore-forwarder-form": handleEmailForwardersRestore,
        "restore-filter-form": handleEmailFiltersRestore,
    };

    /**
     * List of <input type="file"> ids vs the forms related submit buttons.
     *
     * Note: the file ids must match a corresponding {id}_error element where
     * the cjt2 validation system outputs validation errors.
     *
     * @type {Object}
     */
    var uploadButtonIds = {
        "restore-home-file": "restore-home-submit-button",
        "restore-db-file": "restore-db-submit-button",
        "restore-forwarder-file": "restore-forwarder-submit-button",
        "restore-filter-file": "restore-filter-submit-button",
    };

    /**
     * Check if the browser supports the features we need.
     *
     * This checks for:
     *
     *   * Promise
     *   * fetch
     *
     * @return {Boolean} true when it supports the needed features, false otherwise.
     */
    function browserSupportsNeededFeatures() {
        return window.Promise && window.fetch;
    }

    /**
     * Load a list of scripts and call the done() callback when all the scripts
     * have loaded.
     *
     * @param  {string[]} scripts List of urls to load the specified scripts.
     * @param  {Function} done    Callback method with the signature:
     *
     *  function done(error) {
     *      if(error) {
     *          // one of the scripts failed to load
     *      }
     *      // Do the thing that depends on the scripts.
     *  }
     */
    function loadScripts(scripts, done) {
        var scriptsLoaded = {};

        /**
         * Hide the AMD system while the polyfill loads
         */
        var hideAmd = function() {
            if (window.define) {
                window.defineHide = window.define;
                window.define = null;
            }
        };

        /**
         * Restore the AMD system after the polyfills are loaded.
         */
        var restoreAmd = function() {
            if (window.defineHide) {
                window.define = window.defineHide;
                delete window.defineHide;
            }
        };

        /**
         * Helper to check if all the desired scripts are loaded.
         *
         * @param  {Error} error This parameter is passed to the callback if
         *                       the load fails for some reason.
         */
        var checkIfPolyfillsLoaded = function(error) {
            var doneCount = 0;
            var calledBack = false;
            for (var index in scripts) {
                if (scripts.hasOwnProperty(index)) {
                    var script = scripts[index];
                    if (scriptsLoaded[script] === true) {
                        doneCount++;
                    } else if (scriptsLoaded[script] instanceof Error) {
                        if (!calledBack) {
                            calledBack = true;
                            restoreAmd();
                            done(scriptsLoaded[script]);
                        }
                    }
                }
            }

            if (doneCount === scripts.length) {
                if (!calledBack) {
                    calledBack = true;
                    restoreAmd();
                    done();
                }
            }
        };

        /**
         * Helper to build a load callback function.
         *
         * @param  {string} script
         * @return {function} a load callback function with the state captured.
         */
        var loadFactory = function(script) {
            return function() {
                scriptsLoaded[script] = true;
                checkIfPolyfillsLoaded();
            };
        };

        /**
         * Helper to build a error callback function.
         *
         * @param  {string} script
         * @return {function} an error callback function with the state captured.
         */
        var errorFactory = function(script) {
            return function() {
                scriptsLoaded[script] = new Error("Failed to load script " + script);
                checkIfPolyfillsLoaded();
            };
        };

        // Move define/amd out of the way.
        hideAmd();

        // Load the scripts
        for (var index in scripts) {
            if (scripts.hasOwnProperty(index)) {
                var script = scripts[index];
                var js = document.createElement("script");
                js.src = script;
                js.onload = loadFactory(script);
                js.onerror = errorFactory(script);
                document.head.appendChild(js);
            }
        }
    }

    /**
     * Create an error message block from the template on the page.
     *
     * @param  {string}   message Error message to inject into the template.
     * @param  {string}   id      Base id to use for the notices various elements.
     * @param  {string[]} rest    Additional error details.
     * @return {string}           Html blob ready to inject into an elements innerHTML.
     */
    function makeError(message, id, rest) {
        var source   = document.getElementById("error-template").innerHTML;
        var template = Handlebars.compile(source);
        return template({ id: id, message: message, rest: rest });
    }

    /**
     * Create an success message block from the template on the page.
     *
     * @param  {string} message Success message to inject into the template.
     * @param  {string} id      Base id to use for the notices various elements.
     * @return {string}         Html blob ready to inject into an elements innerHTML.
     */
    function makeSuccess(message, id) {
        var source   = document.getElementById("success-template").innerHTML;
        var template = Handlebars.compile(source);
        return template({ id: id, message: message });
    }

    /**
     * Send the file to the api via the fetch API.
     * @param  {FileInputElement} inputFile
     * @param  {string} url       url to post the file too.
     * @return {Promise}          promise that when resolved will report how the API submission went.
     */
    function handleUpload(inputFile, url) {
        var formData = new FormData();
        formData.append("file1", inputFile.files[0]);

        return fetch(url, {
            method: "POST",
            body: formData,
        }).then(function(response) {
            return response.json();
        });
    }

    /**
     * Show an element on the page.
     * @param  {Element} el  Reference to a dom element on the page.
     * @param  {string}  def Default way to show the element. If not provided it defaults to 'block'.
     */
    function show(el, def) {
        if (def === undefined) {
            def = "block";
        }
        el.style.display = def;
    }

    /**
     * Hide an element on the page.
     * @param  {Element} el  Reference to a dom element on the page.
     */
    function hide(el) {
        el.style.display = "none";
    }

    /**
     * Initialize the notice so. This sets up the close hander.
     *
     * @param  {Element}  el       Reference to a dom container element on the page.
     * @param  {string}   id       Partial id of the close button
     * @param  {Function} callback Callback to call when the close button is clicks.
     */
    function initMessageBlock(el, id, callback) {
        var btnClose = el.querySelector("#" + id + "-close");
        btnClose.addEventListener("click", function(e) {
            el.innerHTML = "";
            if (callback && typeof (callback) === "function") {
                callback();
            }
        }, false);
    }

    /**
     * Event handler for the submission of the restore database form.
     *
     * @param  {Event} e
     * @return {Boolean}   always false.
     */
    function handleDatabaseRestore(e) {
        e.preventDefault();
        var url = PAGE.session + "/execute/Backup/restore_databases";
        uploadTo(url, "db", PAGE.restoringDb);
        return false;
    }

    /**
     * Event handler for the submission of the restore home directory form.
     *
     * @param  {Event} e
     * @return {Boolean}   always false.
     */
    function handleHomeFilesRestore(e) {
        e.preventDefault();
        var url = PAGE.session + "/execute/Backup/restore_files";
        uploadTo(url, "home", PAGE.restoringHome);
        return false;
    }

    /**
     * Event handler for the submission of the restore email forwarders form.
     *
     * @param  {Event} e
     * @return {Boolean}   always false.
     */
    function handleEmailForwardersRestore(e) {
        e.preventDefault();
        var url = PAGE.session + "/execute/Backup/restore_email_forwarders";
        uploadTo(url, "forwarder", PAGE.restoringForwarders);
        return false;
    }

    /**
     * Event handler for the submission of the restore email filters form.
     *
     * @param  {Event} e
     * @return {Boolean}   always false.
     */
    function handleEmailFiltersRestore(e) {
        e.preventDefault();
        var url = PAGE.session + "/execute/Backup/restore_email_filters";
        uploadTo(url, "filter", PAGE.restoringFilters);
        return false;
    }

    /**
     * Perform the upload asynchronously.
     *
     * @param  {String} url  Api url to upload to.
     * @param  {String} kind Usually shorter name: db, home, filter, forwarder
     * @param  {String} msg  Translated message while the spinner is running.
     */
    function uploadTo(url, kind, msg) {
        enableFileValidator["restore-" + kind + "-file"] = false;

        var inputFile = document.getElementById("restore-" + kind + "-file");
        var divFields = document.getElementById("restore-" + kind + "-fields");
        var btnSubmit = document.getElementById("restore-" + kind + "-submit-button");
        var message   = document.getElementById("restore-" + kind + "-message");
        var spinner   = document.getElementById("restore-" + kind + "-spinner");

        message.innerHTML = "";
        btnSubmit.disabled = true;
        message.innerText = msg;
        hide(divFields);
        show(spinner, "inline");
        handleUpload(inputFile, url)
            .then(function(response) {
                hide(spinner);
                if (response.status == 1) { // eslint-disable-line eqeqeq
                    message.innerHTML = makeSuccess(response.messages[response.messages.length - 1], "success-" + kind + "-restore");
                    initMessageBlock(message, "success-" + kind + "-restore");
                    show(divFields);
                    inputFile.value = "";
                } else {
                    message.innerHTML = makeError(response.errors.shift(), "failed-" + kind + "-restore", response.errors);
                    initMessageBlock(message, "failed-" + kind + "-restore");
                    show(divFields);
                }

                btnSubmit.disabled = false;
                enableFileValidator["restore-" + kind + "-file"] = true;
            })
            .catch(function(error) {
                hide(spinner);
                message.innerHTML = makeError(error, "failed-network-" + kind + "-restore");
                initMessageBlock(message, "failed-network-" + kind + "-restore", function() {
                    show(divFields);
                });
                btnSubmit.disabled = false;
                show(divFields);
                enableFileValidator["restore-" + kind + "-file"] = true;
            });
    }

    /**
     * Helper to build a function to check if the file validators
     * are enabled. Generates a closure around the id.
     *
     * @param  {string} id
     * @return {Function}
     */
    function makeValidatorControlFunction(id) {
        return function(el, val) {
            return enableFileValidator[id];
        };
    }

    /**
     * Initialize the forms on the page.
     *
     *  * Setup the validators.
     *  * Setup the submit handlers.
     *
     */
    function initialize(error) {
        for ( var inputId in uploadButtonIds ) {
            if (document.getElementById(inputId)) {
                // eslint-disable-next-line new-cap
                var validator = new CPANEL.validate.validator(PAGE.validationTitle);
                validator.add(inputId, "min_length(%input%, 1)", PAGE.missingFile, makeValidatorControlFunction(inputId));
                validator.attach();
                CPANEL.validate.attach_to_form(uploadButtonIds[inputId], validator);
            }
        }

        if (error instanceof Error) {
            alert(error);
            return;
        }

        for (var formId in uploads) {
            if (uploads.hasOwnProperty(formId)) {
                var form = document.getElementById(formId);
                if (form) {
                    form.addEventListener("submit", uploads[formId], false);
                }
            }
        }
    }

    if (browserSupportsNeededFeatures()) {
        YAHOO.util.Event.onDOMReady(initialize);
    } else {
        YAHOO.util.Event.onDOMReady(function() {
            loadScripts(PAGE.polyfills, initialize);
        });
    }
})();
