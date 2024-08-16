/*
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// check to be sure the CPANEL global object already exists
if (typeof(CPANEL) === "undefined" || !CPANEL) {
    alert('You must include the CPANEL global object before including ui/widgits/pager.js!');
} else {

    (function() {

        // Define the namespace for this module
        CPANEL.namespace("CPANEL.ui.widgets");

        /**
    The pager module contains pager related objects used in cPanel.
    @module CPANEL.ui.widgets.pager
    */

        if (typeof(CPANEL.ui.widgets.pager) === 'undefined') {

            /**
        The PageActions enum contains the defined action flags reported to
        various action callbacks used by the PageManager class during events.
        @enum
        @static
        @class PagerActions
        @namespace CPANEL.ui.widgets */
            var PagerActions = {
                /**
            Signals to registered callbacks that this is a page size change event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                CHANGE_PAGE_SIZE: 1,
                /**
            Signals to registered callbacks that this is a go to page event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                GO_TO_PAGE: 2,
                /**
            Signals to registered callbacks that this is a show all event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                SHOW_ALL: 4,
                /**
            Signals to registered callbacks that this is a clear filter event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                CLEAR_FILTER: 8,
                /**
            Signals to registered callbacks that this is a clear sort event.
            @static
            @class PagerActions
            @property  CHANGE_PAGE_SIZE */
                CLEAR_SORT: 16,
                /**
            Signals to registered callbacks that this is a change filter event.
            @static
            @class PagerActions
            @property  CHANGE_FILTER */
                CHANGE_FILTER: 32,
                /**
            Signals to registered callbacks that this is a change sort event.
            @static
            @class PagerActions
            @property  CHANGE_SORT */
                CHANGE_SORT: 64
            };

            /**
        This class manages the parameters associated with each pager defined on a page. I is used as part of the
        common pagination system.
        @enum
        @static
        @class PagerManager
        @namespace CPANEL.ui.widgets */
            var PagerManager = function() {
                this.cache = {};
            };

            PagerManager.prototype = {
                /**
                 * Call back called before the manager fires an action.
                 * @class PagerManager
                 * @event
                 * @name beforeAction
                 * @param [String] scope- Unique name of the pager being initilized.
                 * @param [Hash] container - reference to the settings for the current pager.
                 * @param [PagerActions] action
                 */

                /**
                 * Call back called after the manager fires an action.
                 * @class PagerManager
                 * @event
                 * @name afterAction
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Hash] container - reference to the settings for the current pager.
                 * @param [PagerActions] action
                 */

                /**
                 * Initialize the PageManager object for a specific scope
                 * @class PagerManager
                 * @name initialize
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] url - Optional alternative url. If same page, leave null.
                 * @param [Hash] params - Initial values for parameters passed to the url.
                 * @param [String] method - Either GET or POST
                 * @param [Hash] callbacks - Hash containing optional callbacks
                 *     Supported eveents include:
                 *     beforeAction - Called before the action triggers
                 *     afterAction - Called after the action triggers
                 */
                initialize: function(scope, url, params, method, callbacks) {
                    var container = {
                        url: url || "",
                        params: params || {},
                        method: method || "GET",
                        callbacks: {}
                    };

                    if (callbacks) {
                        if (callbacks.beforeAction) {
                            container.callback.beforeAction = callbacks.beforeAction;
                        }
                        if (callbacks.afterAction) {
                            container.callback.afterAction = callbacks.afterAction;
                        }
                    }

                    this.cache[scope] = container;
                },

                /**
                 * Sets the callbacks for a specific pager.
                 * @class PagerManager
                 * @name setCallback
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Hash] callbacks - Hash containing optional callbacks
                 *     Supported eveents include:
                 *     beforeAction - Called before the action triggers
                 *     afterAction - Called after the action triggers
                 */
                setCallback: function(scope, callbacks) {
                    var container = this.cache[scope];
                    if (container && callbacks) {
                        if (callbacks.beforeAction) {
                            container.callback.beforeAction = callbacks.beforeAction;
                        }
                        if (callbacks.afterAction) {
                            container.callback.afterAction = callbacks.afterAction;
                        }
                    }
                },

                /**
                 * Sets the parameters for a specific pager.
                 * @class PagerManager
                 * @name setParameters
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Hash] params - Name value pairs that you want to set. Items in the current params cache that are not specified in this argument are not changed or removed.
                 */
                setParameters: function(scope, params) {
                    if (params) {
                        var container = this.cache[scope];
                        for (var p in params) {
                            container.params[p] = params[p];
                        }
                    }
                },

                /**
                 * Gets the parameters for a specific pager.
                 * @class PagerManager
                 * @name getParameters
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Array] params - Names of the paramters you want to get.
                 * @return [Hash] - name value pairs in a hash.
                 */
                getParameters: function(scope, params) {
                    var output = {};
                    if (params) {
                        var container = this.cache[scope];
                        for (var i = 0, l = params.length; i < l; i++) {
                            var key = params[i];
                            output[key] = container.params[key];
                        }
                    }
                    return output;
                },
                /**
                 * Sets the specific parameter to the specific value for a specific pager.
                 * @class PagerManager
                 * @name setParameter
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] name - Name of the parameter to set.
                 * @param [String] value - Value of the paramter.
                 */
                setParameter: function(scope, name, value) {
                    var container = this.cache[scope];
                    container.params[name] = value;
                },
                /**
                 * Gets the specific parameter for a specific pager.
                 * @class PagerManager
                 * @name getParameter
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] name - Name of the parameter to set.
                 *
                 */
                getParameter: function(scope, name) {
                    var container = this.cache[scope];
                    return container.params[name];
                },
                /**
                 * Fires the go to page event.
                 * @class PagerManager
                 * @name fireGoToPage
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Number] start - Start index of first item on a page...
                 * @param [Number] page - Page to go to.
                 * @param [Number] skip - Number of pages to skip.
                 * @note There is signifigant data redundancy in the current implementation to track
                 * all three of these, likely only one is needed, but there seems to be dependancies
                 * on each in various code modules. Consider refactoring this when we have more time.
                 * @refactor
                 */
                fireGoToPage: function(scope, start, page, skip) {
                    var container = this.cache[scope];
                    container.params["api2_paginate_start"] = start;
                    container.params["page"] = page;
                    container.params["skip"] = skip;
                    return this.fireAction(scope, container, PagerActions.GO_TO_PAGE);
                },
                /**
                 * Fires the change items per page event.
                 * @class PagerManager
                 * @name fireChangePageSize
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Number] itemsperpage - Number of items per page.
                 */
                fireChangePageSize: function(scope, itemsperpage, submit) {
                    var container = this.cache[scope];
                    container.params["itemsperpage"] = itemsperpage;
                    if (submit) {
                        return this.fireAction(scope, container, PagerActions.CHANGE_PAGE_SIZE);
                    }
                    return true;
                },
                /**
                 * Fires the show all pages event.
                 * @class PagerManager
                 * @name fireShowAll
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Boolean] clearFilterSort - If true clear the filter and sort, otherwise, leaves them in tact.
                 *  Must implement this action on the server.
                 */
                fireShowAll: function(scope, clearFilterSort) {
                    var container = this.cache[scope];
                    container.params["viewall"] = clearFilterSort ? "1" : "0";
                    return this.fireAction(scope, container, clearFilterSort ? PagerActions.SHOW_ALL | PagerActions.CLEAR_FILTER | PagerActions.CLEAR_SORT : PagerActions.SHOW_ALL);
                },
                /**
                 * Fires the change page filter event.
                 * @class PagerManager
                 * @name fireChangeFilter
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] searchregex - The new search expression.
                 * @param [Hash] params - Additional name/value pairs to add to the request, normally additional or custom filter tags.
                 */
                fireChangeFilter: function(scope, searchregex, params) {
                    var container = this.cache[scope];
                    container.params["searchregex"] = searchregex;
                    // Merge in the additianal parameters
                    for (var p in params) {
                        container.params[p] = params[p];
                    }
                    return this.fireAction(scope, container, PagerActions.CHANGE_FILTER);
                },
                /**
                 * Fires the change page sort event.
                 * @class PagerManager
                 * @name fireChangeSort
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [String] column - The name of the column to sort on.
                 * @param [String] direction - Either 'ascending' or 'descending'.
                 * @param [Hash] params - Additional name/value pairs to add to the request, normally additional or custom filter tags.
                 */
                fireChangeSort: function(scope, column, direction, params) {
                    var container = this.cache[scope];
                    container.params["api2_sort_column"] = column;
                    container.params["api2_sort_reverse"] = direction;
                    // Merge in the additianal parameters
                    for (var p in params) {
                        container.params[p] = params[p];
                    }
                    return this.fireAction(scope, container, PagerActions.CHANGE_SORT);
                },
                /**
                 * Fires the specified event including any optional beforeAction() and afterAction()
                 * handlers.
                 * @class PagerManager
                 * @name fireAction
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @param [Object] container - Container for this scope holding all the arguments for the call
                 * @param [PagerAction] action - Action triggering this event.
                 */
                fireAction: function(scope, container, action) {
                    var cancel = false;

                    // Call the before action handler if its available
                    if (container.callbacks["beforeAction"]) {
                        cancel = container.callbacks["beforeAction"](scope, container, action);
                    }

                    if (cancel) {
                        return false;
                    }

                    var href = container.href || window.location.href.split('?')[0];
                    if (container.method == "GET") {
                        window.location = this._makeQuery(href, this._getQuery(container));
                    } else if (container.method === "POST") {
                        var form = this._buildForm(url, container.params);
                        if (form) {
                            form.submit();
                        }
                    }

                    // Call the after action handler if its available
                    if (container.callbacks["afterAction"]) {
                        container.callbacks["afterAction"](scope, container, action);
                    }
                    return true;
                },
                /**
                 * Converts the cached parameters into a URL querystring.
                 * @class PagerManager
                 * @name getQuery
                 * @param [String] scope - Unique name of the pager being initilized.
                 * @return [String] - Query string generated from the current list of parameters for the specificed pager.
                 */
                getQuery: function(scope) {
                    var container = this.cache[scope];
                    return this._getQuery(container);
                },
                /**
                 * Converts the cached parameters into a URL querystring.
                 * @private
                 * @class PagerManager
                 * @name _getQuery
                 * @param [Object] container - Container with parameters for a given scope.
                 * @return [String] - Query string generated from the current list of parameters for the specificed pager.
                 */
                _getQuery: function(container) {
                    return this._serialize(container.params);
                },
                /**
                 * Builds a complete url for a GET call
                 * @private
                 * @class PagerManager
                 * @name _makeQuery
                 * @param [String] url
                 * @param [String] query
                 * @return [String] full URL.
                 */
                _makeQuery: function(url, query) {
                    return url + (query ? "?" + query : "");
                },
                /**
                 * Builds a complete form to submit via post. First checks to see if
                 * there is an old version of itself and removes it. It the injects the
                 * form into the DOM and returns a reference to it.
                 * @private
                 * @class PagerManager
                 * @name _buildForm
                 * @param [String] url
                 * @param [String] params
                 * @return [HTMLElement] form element generated for the url and parameters.
                 */
                _buildForm: function(url, params) {
                    var form = document.createElement("form");
                    form.href = url;
                    form.method = "POST";
                    form.id = scope + "-page-form";
                    for (var param in params) {
                        if (typeof(param) === "string") {
                            var input = document.createElement("input");
                            input.type = "hidden";
                            input.id = scope + "-page-param-" + param;
                            input.name = param;
                            input.value = params[param];
                            form.appendChild(input);
                        }
                    }

                    // Remove the older version of it so we don't bloat the webpage
                    var oldForm = document.getElementById(form.id);
                    if (oldForm) {
                        this._removeElement(oldForm);
                    }

                    // Inject it into the document so its live
                    document.appendChild(form);
                    return form;
                },
                /**
                 * Converts a hash into a URI compatible query string.
                 * @private
                 * @class PagerManager
                 * @name _serialize
                 * @param [Hash] obj
                 * @return [String] URI compatible querystring.
                 * @source http://stackoverflow.com/questions/1714786/querystring-encoding-of-a-javascript-object
                 */
                _serialize: function(obj) {
                    var str = [];
                    for (var p in obj)
                        str.push(encodeURIComponent(p) + "=" + encodeURIComponent(obj[p]));
                    return str.join("&");
                },
                /**
                 * Removes the element from it parent node if it has a parent.
                 * @private
                 * @class PagerManager
                 * @name _removeElement
                 * @param [HTMLElement] el
                 */
                _removeElement: function(el) {
                    var parent = el.parentNode;
                    if (parent) {
                        parent.removeChild(el);
                    }
                }
            };

            // Exports
            CPANEL.ui.widgets.PagerActions = PagerActions;
            CPANEL.ui.widgets.pager = new PagerManager();
        }

    })();
}
