/*
# cjt/util/module.js                                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides angular module helper methods used in the construction
 * of the bundles for each major application. *
 *
 * @module   cjt/util/module
 */

define(
    [
        "angular"
    ],
    function(angular) {
        "use strict";

        /**
         * Test if the given module is available to angular.js.
         *
         * @method isModuleAvailable
         * @param  {String}  name Module name
         * @return {Boolean}      true if found, false if not found.
         */
        function _isModuleAvailable(name) {
            var module = null;
            try {
                module = angular.module(name);
                return module !== null;
            } catch (e) {
                return false;
            }
        }

        return {

            /**
             * Test if the given module is available to angular.js.
             *
             * @method isModuleAvailable
             * @param  {String}  name Module name
             * @return {Boolean}      true if found, false if not found.
             */
            isModuleAvailable: _isModuleAvailable,

            /**
             * Creates a module that depends on a set of other modules. This allows us to
             * reference that set of dependencies with a single name.
             *
             * Ex: Assume we have a set of modules that are commonly used in various parts
             * of an application. That set includes module "a", "b", and "c". We can create
             * a module package called "myDeps" that depends on those three modules, and in
             * our Angular app we can now just use the module dependency "myDeps" instead
             * of enumerating "a", "b", and "c".
             *
             * This method checks for the existence of all dependent modules before adding
             * them to the module package since we can't guarantee their existence.
             *
             * @method createModule
             * @private
             * @param {String} packageName    The name of the resulting module package that will be registered with Angular.
             * @param {String[]} moduleList   A list of module names that the resulting package will require.
             */
            createModule: function(packageName, moduleList) {
                var packageDependencies = [];
                moduleList.forEach(function(module) {
                    if (_isModuleAvailable(module)) {
                        packageDependencies.push(module);
                    } else if (module) {
                        window.console.log(module + " not found");
                    }
                });
                angular.module(packageName, packageDependencies);
            }
        };
    }
);
