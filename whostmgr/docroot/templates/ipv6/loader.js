var loader = angular.module("httpLoader", []);

loader.mask = function(disabled) {
    disabled = disabled || false;

    // toggle the loading class
    if (disabled) {
        $("#page_loader").addClass("loading");
    } else {
        $("#page_loader").removeClass("loading");
    }

    // toggle form elements under the mask
    $("#page_loader input, #page_loader button").each(function(index) {
        $(this).prop("disabled", disabled);
    });
};

loader.config(["$httpProvider",
    function($httpProvider) {
        $httpProvider.responseInterceptors.push("loadingInterceptor");
        $httpProvider.defaults.transformRequest.push(function(data) {
            loader.mask(true);
            return data;
        });
    }
]);

loader.factory("loadingInterceptor", ["$q",
    function($q) {
        return function(promise) {
            return promise.then(
                function(response) {

                    // success
                    loader.mask(false);
                    return response;
                },
                function(reponse) {

                    // failure
                    loader.mask(false);
                    return $q.reject(response);
                }
            );
        };
    }
]);
