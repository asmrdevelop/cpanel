/**
 * Provides loading state and interaction with WHM API functions
 *
 * @module apiService
 *
 */
var api = angular.module("apiService", []);

/**
 * Service that handles GET and POST requests for WHM API functions
 *
 * @method api
 * @param {Object} $http The Angular HTTP resource
 * @return {Object} An object literal containing the get and post methods
 */
api.factory("api", ["$http",
    function($http) {
        var token = location.pathname.match(/((?:\/cpsess\d+)?)(?:\/([^\/]+))?/)[1] || "",
            pack = function(response) {
                response = response.data;
                if (response.metadata.result) {
                    return {
                        type: "success",
                        status: response.metadata.result,
                        data: response.data
                    };
                } else {
                    return {
                        type: "error",
                        status: response.metadata.result,
                        message: response.metadata.reason
                    };
                }
            };

        return {
            get: function(apiFunction) {
                return $http.get(token + "/json-api/" + apiFunction + "?api.version=1")
                    .then(pack);
            },
            post: function(apiFunction, data) {
                data = $.param(data);
                return $http.post(token + "/json-api/" + apiFunction + "?api.version=1", data)
                    .then(pack);
            }
        };
    }
]);

/**
 * Manages loading class on the #page_loader container
 *
 * @method mask
 * @param {Boolean} [disabled=false] Adds class if true, removes class otherwise
 */
api.mask = function(disabled) {
    disabled = disabled || false;

    // toggle the loading class
    if (disabled) {
        $("#page_loader").addClass("loading");
    } else {
        $("#page_loader").removeClass("loading");
    }

    // toggle form elements under the mask
    $("#page_loader input, #page_loader button").each(function() {

        // we want to keep the disabled state prior to masking
        if (disabled && $(this).prop("disabled")) {

            // so if a control is disabled, let's mark it as "was previously disabled"
            $(this).addClass("mask_was_previously_disabled");
        } else if (!disabled && $(this).hasClass("mask_was_previously_disabled")) {

            // and we'll unmark it, as opposed to re-enabling, if it was previously disabled
            $(this).removeClass("mask_was_previously_disabled");
        } else {

            // otherwise we'll just apply the toggled state
            $(this).prop("disabled", disabled);
        }
    });
};

/**
 * Configuration of the Angular HTTP provider that pushes the loadingInterceptor
 * and initial loading mask into the appropriate properties of the provider object.
 *
 * @method $httpProvider
 * @param {Object} $httpProvider
 */
api.config(["$httpProvider",
    function($httpProvider) {
        $httpProvider.interceptors.push("loadingInterceptor");
    }
]);

/**
 * An interceptor that calls the mask function to remove the loading state
 * after an Angular promise is fulfilled.
 *
 * @method loadingInterceptor
 * @param {Object} $q Angular query object
 * @return {Function} Angular promise function
 */
api.factory("loadingInterceptor", ["$q",
    function($q) {
        return {
            "request": function(data) {
                api.mask(true);
                return data;
            },
            "response": function(response) {
                return $q.when(response).then(function(data) {

                    // success
                    api.mask(false);
                    return data;
                }, function(data) {

                    // failure
                    api.mask(false);
                    return $q.reject(data);
                });
            }
        };
    }
]);
