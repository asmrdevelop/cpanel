/*
# cpanel - base/frontend/jupiter/statmanager/index.js
                                                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    /* global document, window, $ */

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
     * Update the configuration via the fetch API.
     * @param  {string} url       url to post the file too.
     * @param  {object} config    The configuration object to post to the api call.
     * @return {Promise}          promise that when resolved will report how the API submission went.
     */
    function postJSON(url, config) {

        return fetch(url, {
            method: "POST",
            body: JSON.stringify(config),
            headers: {
                "Content-Type": "application/json",
            },
        }).then(function(response) {
            return response.json();
        });
    }

    /**
     * Event handler for the submission of the restore database form.
     *
     * @param  {Event} e
     * @return {Boolean}   always false.
     */
    function handleSaveConfiguration(e) {
        e.preventDefault();
        var url = PAGE.session + "/execute/StatsManager/save_configuration";
        var config = gatherData();
        $("#save-spinner").show();
        $("#save").prop("disabled", true);
        var $responseEl = $("#response");
        $responseEl.hide();
        postJSON(url, config)
            .then(function(response) {
                $("#save-spinner").hide();
                $("#save").prop("disabled", false);
                var message, id;
                if (response.status) {
                    id = "success";
                    message = makeSuccess(PAGE.saveSuccess, id);
                } else {
                    id = "failure";
                    message = makeError(PAGE.saveFailed, id);
                }
                updateCheckBoxes(response.data);
                $responseEl.html(message);
                initializeMessageBlock($responseEl, id);
                $responseEl.show();
            })
            .catch(function() {
                $("#save-spinner").hide();
                $("#save").prop("disabled", false);
                var $responseEl = $("#response");
                var id = "network-failure";
                var message = makeError(PAGE.networkFailed, id);
                $responseEl.html(message);
                initializeMessageBlock($responseEl, id);
                $responseEl.show();
            });
        return false;
    }


    function updateCheckBoxes(updates) {
        updates.forEach(function(domainConfig) {
            var idPrefix = "#check-" + domainConfig.domain + "-";
            domainConfig.analyzers.forEach(function(analyzerConfig) {
                var id = idPrefix + analyzerConfig.name;
                $(id).prop("checked", !!analyzerConfig.enabled);
            });
        });

        PAGE.analyzerNames.forEach(function(analyzer) {
            syncCheckboxes(analyzer);
        });
    }

    /**
     * @type AnalyzerConfiguration
     * @property {string }name    Name of the analyzer. Must be one of: analog, awstats, or webalizer.
     * @property {number} enabled 1 when enabled, 0 when disabled.
     */

    /**
     * @type DomainConfiguration
     * @property {string} domain - the domain to apply the configuration too.
     * @property {AnalyzerConfiguration[]} analyzers - list of analyzer configuration for the domain.
     */

    /**
     * Gather the configuration data from the form.
     *
     * @returns {DomainConfiguration[]} - list of the domain configurations for the web log analyzers.
     */
    function gatherData() {

        var config = {};

        PAGE.analyzerNames.forEach(function(analyzer) {
            $(".check-" + analyzer).each(function() {
                var parts = $(this).attr("name").split("--");
                var enabled = $(this).prop("checked");
                var domain = parts[0], analyzerName = parts[1];
                if (typeof (config[domain]) !== "object" ) {
                    config[domain] = {
                        domain: domain,
                        analyzers: [],
                    };
                }
                config[domain].analyzers.push({
                    name: analyzerName,
                    enabled: enabled ? 1 : 0,
                });
            });
        });

        return { changes: Object.values(config) };
    }

    /**
     * Initialize the notice so. This sets up the close hander.
     *
     * @param  {HTMLElement} $el      Reference to a dom container element on the page.
     * @param  {string}      id       Partial id of the close button
     */
    function initializeMessageBlock($el, id) {
        var $btnClose = $("#" + id + "-close");
        $btnClose.click(function(e) {
            $el.hide();
            $el.html("");
        });
    }

    /**
     * See if all the elements in the list are checked.
     *
     * @param {HTMLElements[]} $elements
     * @returns {boolean} When true, all are checked, otherwise false.
     */
    function areAllChecked($elements) {
        var allChecked = true;
        $elements.each(
            function(index, element) {
                allChecked = allChecked && ($(element).prop("checked"));
            }
        );
        return allChecked;
    }

    /**
     * Create an error message block from the template on the page.
     *
     * @param  {string}   message Error message to inject into the template.
     * @param  {string}   id      Base id to use for the notices various elements.
     * @return {string}           Html blob ready to inject into an elements innerHTML.
     */
    function makeError(message, id) {
        var source   = document.getElementById("error-template").innerHTML;
        var template = Handlebars.compile(source);
        return template({ id: id, message: message });
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
     * Setup the form submit process handing.
     */
    function setupFormSubmit() {
        $("#the_form").submit(handleSaveConfiguration);
    }

    function syncCheckboxes(analyzer) {
        var allSimilar = $("input.check-" + analyzer + ":checkbox");
        var allChecked = areAllChecked(allSimilar);
        $("#check-all-" + analyzer).prop("checked", allChecked);
    }

    /**
     * Setup the check all and check/uncheck one group behavior
     * for each available analyzer.
     */
    function setupCheckboxes() {

        // Setup the check all checkboxes handlers
        $(".check-all").click(function() {
            var id = $(this).attr("id");
            var analyzer = id.replace(/^check-all-/, "");
            $("input.check-" + analyzer + ":checkbox").prop("checked", this.checked);
        });

        PAGE.analyzerNames.forEach(function(analyzer) {

            // Initialize the check all checkboxes base on the current state at load time.
            syncCheckboxes(analyzer);

            // Setup the dependent checkbox handlers
            $(".check-" + analyzer).click(function() {
                syncCheckboxes(analyzer);
            });
        });
    }

    /**
     * Initialize the forms event handlers.
     */
    function initialize() {
        setupCheckboxes();
        setupFormSubmit();
    }

    $( document ).ready(function() {
        if (browserSupportsNeededFeatures()) {
            initialize();
        } else {
            loadScripts(PAGE.polyfills, initialize);
        }
    });

})();
