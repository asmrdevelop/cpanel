/*
# cjt/utils/dumper.js                             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W089 */
/* global define: false */

define(function() {

    return {
        dump: function dump(object, options) {
            options = options || {};
            options.tabs = options.tabs || 0;
            options.tabCharacter = options.tabCharacter || "\t";
            options.nlCharacter = options.nlCharacter || "\n";

            var result = "";
            for (var propertyName in object) {
                var propertyValue = object[propertyName];
                if (typeof propertyValue === "string") {
                    propertyValue = "'" + propertyValue + "'";
                } else if (typeof propertyValue === "function") {
                    propertyValue = "function(){ ... }";
                } else if (typeof propertyValue === "object") {
                    if (propertyValue instanceof Array) {
                        propertyValue = "[" + options.nlCharacter;
                        for (var i = 0, l = propertyValue.length; i < l; i++) {
                            propertyValue += dump(propertyValue[i], { tabs: options.tabs + 1 });
                        }
                        propertyValue += [options.tabs].join(options.tabCharacter) + "]" + options.nlCharacter;
                    } else {
                        propertyValue =  "{" +  options.nlCharacter;
                        propertyValue +=  dump(propertyValue, { tabs: options.tabs + 1 });
                        propertyValue += [options.tabs].join(options.tabCharacter) + "}" +  options.nlCharacter;
                    }
                }
                result += [options.tabs].join(options.tabCharacter);
                result += "'" + propertyName + "' : " + propertyValue + ",";
                result += options.nlCharacter;
            }
            return result;
        }
    };
});
