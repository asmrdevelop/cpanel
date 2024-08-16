/*
 * cjt2/src/services/componentSettingSaverFactory.js
 *                                                  Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * Factory module that generates componentSettingSaverServices for the
 * current application environment.
 *
 * @module cjt/services/componentSettingSaverFactory
 *
 */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/services/pageIdentifierService"
    ],
    function(angular, CJT, LOCALE) {
        "use strict";

        /**
         * Factory method to generate the componentSettingSaverService for the
         * context.
         *
         * @method makeService
         * @param  {String} moduleName angularjs module name for the generated service
         * @return {ComponentSettingSaverService}
         */
        return function makeService(moduleName, dependencies) {

            // Retrieve the current application
            var module = angular.module(moduleName, dependencies);

            return module.factory("componentSettingSaverService", [
                "nvDataService",
                "$log",
                "$q",
                "$window",
                "pageIdentifierService",
                function(nvDataService, $log, $q, $window, pageIdentifierService) {
                    return {

                        /**
                         * The most recent promise fetching the nvdata if any.
                         * If null, there is no outstanding promise.
                         *
                         * @name _currentGetPromise
                         * @private
                         * @type {?Promise}
                         */
                        _currentGetPromise: null,


                        /**
                         * The last time an update was requested
                         *
                         * @name _lastUpdateRequest
                         * @private
                         * @type {DateTime}
                         */
                        _lastUpdateRequest: -1,

                        /**
                         * Last time a save was requested
                         *
                         * @name _lastSavedRequest
                         * @private
                         * @type {DateTime}
                         */
                        _lastSavedRequest: 0,

                        /**
                         * The collection of components that have been fetched or set. All the data is
                         * stored as a JSON serialized version of this object. Each key is a component
                         * and each value is the settings stored for that component.
                         *
                         * @name _components
                         * @private
                         * @type {Object}
                         */
                        _components: {},


                        /**
                         * The collection of components that are managed with this service.
                         * Each key is a component name. All these components are associated
                         * with the page identifier so are page specific.
                         *
                         * @name _registeredComponents
                         * @private
                         * @type {Object}
                         */
                        _registeredComponents: {},


                        /**
                         * Use for registering new saveable components. When a component name is registered
                         * a get request is automatically started.
                         *
                         * @method register
                         * @async
                         * @param  {String} componentName page unique identifier for the saveable component
                         * @return {Promise.<NameValuePair|Object.<NameValuePair>>} if componentName is specified, it will return just that setting, otherwise it returns all the settings for the specific _pageIdentifier
                         * @throws {Promise.<String>} If the api call fails, the request times out or the request fails
                         */
                        register: function registerComponent(componentName) {

                            if (!componentName) {
                                throw new Error(LOCALE.maketext("The [asis,register] method requires the [asis,componentName]."));
                            }

                            var pageId = pageIdentifierService.getPageIdentifier();
                            if ( !pageId ) {
                                throw new Error(LOCALE.maketext("[asis,ComponentSettingSaverService] failed to register the component “[_1]”. You must set the page identifier.", componentName));
                            }

                            // register as a deletable NVData file if function is available to do so.
                            // TODO: Replace with something portable from cjt2
                            if (!angular.isFunction($window["register_interfacecfg_nvdata"])) {
                                $log.warn(LOCALE.maketext("The system could not register the page for the interface settings reset. Is the [asis,interfacereset.js] file missing?"));
                            } else {

                                // TODO: Alter register_interfacecfg_nvdata() to prevent duplicate registration
                                $window.register_interfacecfg_nvdata(this._pageIdentifier);
                            }

                            // QUESTION: From what I can tell the only thing that the register() is used for is
                            // to prevent you from using the same componentName twice, but register() is really
                            // just a call to get(). What is the reason we want to prevent calling get() twice with
                            // the same name. It already has the promise cache to prevent multiple backend requests.
                            if (this._registeredComponents[componentName]) {
                                throw new Error(LOCALE.maketext("[asis,ComponentSettingSaverService] failed to register the component “[_1]”. A component with the same identifier already exists.", componentName));
                            }

                            this._registeredComponents[componentName] = componentName;

                            return this.get(componentName);

                        },

                        /**
                         * Unregisters a saveable component. Single Page Apps may try to register the same component name
                         * more than once when navigating from one view to another and back again. Use this method to free
                         * up the component key when it's no longer needed for a view.
                         *
                         * @method unregisterComponent
                         * @param  {String} componentName   The unique identifier for the component.
                         * @return {Boolean}                True if it succeeds, false if it fails.
                         */
                        unregister: function unregisterComponent(componentName) {

                            // QUESTION: Should unregistering a component also clear it data from the _components
                            // structure since its not part of the other view?
                            // QUESTION: It seems like this tool needs to have a way to pick up the view name also?
                            // NOTE: If we remove register(), then unregister can be removed too.

                            if (this._registeredComponents[componentName]) {
                                delete this._registeredComponents[componentName];
                                return true;
                            } else {
                                $log.error(LOCALE.maketext("[asis,ComponentSettingSaverService] failed to unregister the component “[_1]”. No such component exists.", componentName));
                                return false;
                            }

                        },

                        /**
                         * Set the value of a component
                         *
                         * @method set
                         * @async
                         * @param  {String} componentName page unique identifier for the saveable component. must be registered
                         * @param  {Object|Array} settings JSON encodeable object representing the component settings
                         * @return {Promise.<Array.<SavedNameValuePair>>} returns a promise call that is setting the values via api
                         * @throws {Promise.<String>} If the api call fails, the request times out or the request fails
                         */
                        set: function setComponentSettings(componentName, settings) {

                            var pageId = pageIdentifierService.getPageIdentifier();
                            if (!pageId) {
                                $log.error(LOCALE.maketext("[asis,ComponentSettingSaverService] failed to save the component settings for “[_1]”. You must set the page identifier.", componentName));
                                return false; // TODO: It's complicated to return both a promise and a bool. Should probably throw or return a $q.defer().reject()
                            }

                            this._components[componentName] = settings;

                            var nvdata = {};
                            nvdata[pageId] = JSON.stringify(this._components);

                            this._lastSavedRequest = new Date().getTime();

                            return nvDataService.setObject(nvdata);

                        },

                        /**
                         * Used for getting the updated values of a component as stored in the NVData
                         *
                         * @method get
                         * @async
                         * @param  {String} componentName page unique identifier for the saveable component. must be registered through .register()
                         * @return {Promise.<NameValuePair|Object.<NameValuePair>>} if componentName is specified, it will return just that setting, otherwise it returns all the settings for the specific _pageIdentifier
                         * @throws {Promise.<String>} If the api call fails, the request times out or the request fails
                         */
                        get: function getComponentSettings(componentName) {
                            var self = this;

                            // If we are in the process of getting an updated file, just use the existing promise
                            if (self._currentGetPromise) {
                                return self._currentGetPromise;
                            }

                            // If we haven't saved anything new since we last saved this page, don't retrieve again.
                            if (self._lastUpdateRequest > self._lastSavedRequest) {
                                var deferred = $q.defer();
                                if (componentName) {
                                    deferred.resolve(self._components[componentName]);
                                } else {
                                    deferred.resolve(self._components);
                                }
                                return deferred.promise;
                            }

                            self._lastUpdateRequest = new Date().getTime();

                            var pageId = pageIdentifierService.getPageIdentifier();
                            if (!pageId) {
                                $log.error(LOCALE.maketext("[asis,ComponentSettingSaverService] failed to retrieve the requested component settings. You must set the page identifier."));
                                return false;
                            }

                            self._currentGetPromise = nvDataService.get(pageId).then(
                                function(pairs) {
                                    var pair = pairs.pop();
                                    var value = pair.value;
                                    if (value) {
                                        try {
                                            value = JSON.parse(value);
                                        } catch (e) {
                                            var pageId = pageIdentifierService.getPageIdentifier();
                                            $log.error(LOCALE.maketext("[asis,ComponentSettingSaverService] failed to parse the stored [asis,NVData] file for this page “[_1]”.", pageId));
                                            value = {};
                                        }
                                        self._components = value;
                                    }

                                    // Need to clear this before calling again so it resolves properly
                                    self._currentGetPromise = null;
                                    return self.get(componentName);
                                }).finally(function() {
                                self._currentGetPromise = null;
                            });

                            return self._currentGetPromise;

                        },

                        /**
                         * Get the cached settings for a component. This is useful when you are not willing to wait on
                         * the network request and just want to get the currently known value.
                         *
                         * @param {string} componentName   The component whose values we want to retrieve.
                         * @returns {object}   An object containing cachedValue and requestInProgress keys.
                         */
                        getCached: function getCachedComponentSettings(componentName) {
                            return {
                                cachedValue: componentName ? this._components[componentName] : this._components,
                                requestInProgress: Boolean( this._currentGetPromise ),
                            };
                        },
                    };
                }
            ]);
        };
    }
);
