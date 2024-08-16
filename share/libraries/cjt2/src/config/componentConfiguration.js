/*
# cjt/config/componentConfiguration.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [

        // Libraries
        "angular",
        "cjt/core",
        "cjt/util/locale"
    ],
    function(angular, CJT, LOCALE) {
        "use strict";

        /**
         * @typedef {Object} ComponentConfiguration
         * @description Base class for all configuration objects.
         * @property {String} component Name of the component associated with the configuration
         */

        /**
         * @typedef {ComponentConfiguration} AlertListConfiguration
         * @property {string} position - one of the following:
         *   top-right
         *   top-middle
         *   top-left
         *   bottom-right
         *   bottom-middle
         *   bottom-left
         *   middle-right
         *   middle-middle
         *   middle-left
         * @property {boolean} inline - if false, the alert list will use the position rule, otherwise, it will appear where it naturally flows in the html.
         */

        /**
          * @typedef {Object} ComponentConfigurations
          * @property {AlertListConfiguration} alertList
          */

        /**
         * Generates the default render rules which are used if the user
         * has not set a preference about where their alerts render, or if
         * there is an error retrieving the user's render rules.
         *
         * @method _defaultComponentConfiguration
         * @private
         * @return {ComponentConfiguration} default display properties for the various UI components.
         */
        function _defaultComponentConfiguration() {
            return {
                alertList: {
                    component: "alertList",
                    position: !LOCALE.is_rtl() ? "top-right" : "top-left",
                    inline: false
                }
            };
        }

        /**
         * Get the component's configuration
         * @method _getComponent
         * @private
         * @param  {ComponentConfigurations} config Configuration for all components
         * @param  {String} [component] Name of the component.
         * @return {ComponentConfiguration|ComponentConfigurations}
         */
        function _getComponent(config, component) {
            if (!component) {
                return config;
            } else if (component in config) {
                return config[component];
            } else {
                throw new Error("The component " + component + " is not available in the configuration.");
            }
        }

        /**
         * Set the value of a component's configuration. Only components defined in
         * the default configuration may be set.
         *
         * @method  _setComponent
         * @param {ComponentConfigurations} config Configuration for all components
         * @param {String} component Name of the component.
         * @param {ComponentConfiguration} value
         */
        function _setComponent(config, component, value) {
            if (!component) {
                throw new Error("You must provide a component name when setting a component");
            }

            var defaultConfig = _defaultComponentConfiguration();
            if (component in defaultConfig) {
                if (!value) {
                    config[component] = defaultConfig[component];
                } else {
                    value.component = component;
                    config[component] = value;
                }
            } else {
                throw new Error("The component " + component + " is not available in the configuration.");
            }
        }

        var module = angular.module("cjt2.config.componentConfiguration", []);

        module.provider("componentConfiguration", function() {
            var config = _defaultComponentConfiguration();

            return {

                /**
                 * Get a named component of the display configuration.
                 *
                 * @method getComponent
                 * @param  {String} [component] Name of the component. If not provided the whole configuration is returned
                 * @return {Any} Data for the component. Varies depending on what component was requested. If no component is passed, the whole configuration is returned.
                 * @throws {Error} If the component name is not available in the configuration.
                 */
                getComponent: function(component) {
                    return _getComponent(config, component);
                },

                /**
                 * Sets the value for a component for the display configurtion
                 *
                 * @method setComponent
                 * @param {String} component Name of the component.
                 * @param {Any} value Data for the component. Varies depending on what component was requested.
                 */
                setComponent: function(component, value) {
                    _setComponent(config, component, value);
                },

                /**
                 * Gets the complete display configuration.
                 *
                 * @method get
                 * @return {Object} Object whose properties are the display configuration properties for various components.
                 */
                get: function() {
                    return config;
                },

                /**
                 * Sets the complete display configuration.
                 *
                 * @method set
                 * @param {Object} value An object whose keys represent the various component display properties.
                 */
                set: function(value) {
                    config = value;
                },


                /**
                 * @method $get
                 * @return {componentConfigurationService} [description]
                 */
                $get: function() {


                    /**
                     * @classdesc The display properties used by shared components.
                     * @name componentConfigurationService
                     * @class
                     */
                    return {

                        /**
                         * Gets a specific component from the configuration
                         *
                         * @method getComponent
                         * @param  {String} [component] Component name, if not passed, will get the whole configuration.
                         * @return {ComponentConfiguration|AlertListConfiguration} The configuration data for the component or the whole configuration.
                         */
                        getComponent: function(component) {
                            return _getComponent(config, component);
                        },

                        /**
                         * Gets the complete configuration.
                         *
                         * @method  get
                         * @return {ComponentConfiguration}  The configuration data for the component or the whole configuration.
                         */
                        get: function() {
                            return config;
                        },

                        /**
                         * Sets the value for a component for the display configurtion
                         *
                         * @method setComponent
                         * @param {String} component Name of the component.
                         * @param {Any} value Data for the component. Varies depending on what component was requested.
                         * @throws Will throw an error if component name is not provided OR if component is not available in the configuration.
                         */
                        setComponent: function(component, value) {
                            return _setComponent(config, component, value);
                        },

                        /**
                         * Gets the default configuration so callers can see what changed in the component setup.
                         *
                         * @method  getDefaults
                         * @return {ComponentConfigurations} All default component configurations
                         */
                        getDefaults: function() {
                            var config = _defaultComponentConfiguration();

                            /**
                             * Gets a specific component from the default configuration
                             *
                             * @method getComponent
                             * @param  {String} [component] Component name, if not passed, will get the whole configuration.
                             * @return {ComponentConfiguration|AlertListConfiguration} The configuration data for the component or the whole configuration.
                             */
                            config.getComponent = function(component) {
                                return _getComponent(config, component);
                            };

                            /**
                             * Gets the complete default configuration.
                             *
                             * @method  get
                             * @return {ComponentConfiguration}  The configuration data for the component or the whole configuration.
                             */
                            config.get = function() {
                                return config;
                            };
                            return config;
                        }
                    };
                }
            };

        });
    }
);
