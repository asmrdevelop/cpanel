/**
 * Angular application that manages a list of IPv6 ranges
 *
 * @module ipv6RangesApp
 *
 */
var ipv6RangesApp = angular.module("ipv6RangesApp", ["apiService", "formUtilities"]);

/**
 * Controller that initializes and handles user interaction with the list of ranges
 *
 * @method RangeList
 * @param {Object} $scope The Angular scope variable
 * @param {Object} api The object literal returned by the apiService module
 */
ipv6RangesApp.controller("RangeList", ["$scope", "api",
    function($scope, api) {
        $scope.rangeName = "";
        $scope.rangeCIDR = "";
        $scope.rangeEnabled = 1;
        $scope.rangeNote = "";
        $scope.notice = {};

        // populate range list from API service
        api.get("ipv6_range_list").then(function(result) {
            if (result.status) {
                $scope.ranges = result.data.range;
            } else {
                $scope.ranges = [];
                $scope.notice = result;
            }
        });

        /**
         * Removes the form notice from the page
         *
         * @method closeNotice
         */
        $scope.closeNotice = function() {
            $scope.notice = {};
        };

        /**
         * Attempts to add an IPv6 range to the system. Adding the range to the list
         * on success or displaying an error from the range API on failure.
         *
         * @method addRange
         */
        $scope.addRange = function() {

            // clear existing notices when opening the form
            $scope.notice = {};

            $scope.range.$setDirty();

            // check the validity of the form before submitting
            if ($scope.range.$valid) {

                // setup form data and call the api
                var apiData = {
                    name: $scope.rangeName,
                    range: $scope.rangeCIDR, // TODO: change range to cidr in add api calls then remove the range key
                    CIDR: $scope.rangeCIDR,
                    enabled: $scope.rangeEnabled,
                    note: $scope.rangeNote
                };
                api.post("ipv6_range_add", apiData).then(function(result) {
                    if (result.status) {

                        // success, push the range and reset the form values
                        $scope.ranges.push(apiData);
                        $scope.rangeName = "";
                        $scope.rangeCIDR = "";
                        $scope.rangeEnabled = 1;
                        $scope.rangeNote = "";
                        $scope.range.$setPristine();
                        $("#range_form").addClass("closed-form");
                        result.message = LOCALE.maketext("“[_1]” successfully added to the range list.", apiData.name);
                    }
                    $scope.notice = result;
                });
            } else {

                // force validation of required fields on form submit
                if ($scope.range.name.$viewValue === undefined || $scope.range.name.$viewValue === "") {
                    $scope.range.name.$setViewValue("");
                    $scope.range.name.$setDirty();
                }
                if ($scope.range.cidr.$viewValue === undefined || $scope.range.cidr.$viewValue === "") {
                    $scope.range.cidr.$setViewValue("");
                    $scope.range.cidr.$setDirty();
                }
            }
        };

        /**
         * Clears inputs and notices associated with the range form
         *
         * @method clearRangeForm
         */
        $scope.clearRangeForm = function() {
            $scope.notice = {};

            // reset required fields in model on cancel
            $scope.rangeName = "";
            $scope.rangeCIDR = "";
            $scope.rangeEnabled = 1;
            $scope.rangeNote = "";

        };

        /**
         * Attempts to remove an IPv6 range from the system. Removing the range from the list
         * on success or displaying an error from the range API on failure.
         *
         * @method deleteRange
         */
        $scope.deleteRange = function(range) {
            var index = $scope.ranges.indexOf(range),
                rangeName = $scope.ranges[index].name,
                confirmDelete = confirm(LOCALE.maketext("Delete the “[_1]” range?", rangeName));
            $scope.notice = {};
            if (confirmDelete) {
                api.post("ipv6_range_remove", {
                    name: range.name
                }).then(function(result) {
                    if (result.status) {
                        $scope.ranges.splice(index, 1);
                        result.message = LOCALE.maketext("“[_1]” successfully removed from the range list.", rangeName);
                        $scope.notice = result;
                    }
                    $scope.notice = result;
                });
            }
        };
    }
]);
