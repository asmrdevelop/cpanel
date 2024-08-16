/**
 * Provides utility and validation methods for forms
 *
 * @module formUtilities
 *
 */
var form = angular.module("formUtilities", []);

/**
 * Angular Directive that opens a collapsed form from it's primary button
 *
 * @method openform
 * @return {Function} A function that adds a click handler to the element
 */
form.directive("openform", function() {
    return function(scope, element) {
        element.click(function(e) {
            var form = element[0].form;
            if ($(form).hasClass("closed-form")) {

                // stop submit if we are opening the form
                e.preventDefault();
            }
            $(form).removeClass("closed-form");
        });
    };
});

/**
 * Angular Directive that collapses a form and resets the status of the form
 *
 * @method closeform
 * @return {Function} A function that adds a click handler to the element
 */
form.directive("closeform", function() {
    return function(scope, element) {
        element.click(function() {
            var form = element[0].form,
                formName = $(form).attr("name");
            $(form).addClass("closed-form");
            form.reset();
            scope[formName].$setPristine();
        });
    };
});

/**
 * Attribute that adds validation of IPv6 CIDR ranges by managing the following properties:
 *       ipv6Collapsed - checks for multiple :: denoting collapsed segments
 *       ipv6Address - checks the format of the IPv6 address part of the CIDR ranges
 *       ipv6Characters - checks each segment of the address for valid characters
 *       ipv6Range - checks for a network prefix at the end of the address
 *
 * @method ipv6cidr
 * @return {Object} A function that validates the value of an input element
 */
form.directive("ipv6cidr", function() {
    return {
        restrict: "A",
        require: "ngModel",
        link: function(scope, elem, attr, ctrl) {
            ctrl.$parsers.unshift(function(value) {
                var range = value.split("/"),
                    prefix = range[1],
                    address = range[0],
                    collapsed = address.match(/::/g),
                    segments = address.split(":"),
                    i;

                // check for multiple collapsed groups or too many colons
                if (collapsed) {
                    scope.ipv6Collapsed = (collapsed.length > 1 ||
                        /:{3,}/.test(address)) ? false : "valid";
                } else {
                    scope.ipv6Collapsed = "valid";
                }

                // check address segments
                if (segments) {
                    var length = segments.length,
                        valid128 = length === 8 && segments[length - 1] !== "",
                        validCollapsed = false;
                    if (collapsed) {
                        validCollapsed = length > 2 && collapsed.length === 1;
                    }

                    if (valid128 && prefix >= 16) {
                        for (i = Math.floor((Number(prefix) + 15) / 16); i < 8; i++) {
                            if (!/^0{1,4}$/.test(segments[i])) {
                                valid128 = false;
                            }
                        }
                    }

                    // ensure the range ends with :: or a non-empty last segment for /128
                    if (valid128 || validCollapsed) {
                        scope.ipv6Address = "valid";
                    } else {
                        scope.ipv6Address = false;
                    }

                    // check each segment of the address for invalid characters
                    var invalidLengthFound = false,
                        invalidCharactersFound = false;
                    for (i = 0; i < length; i++) {
                        var segment = segments[i],
                            segmentLength = segment.length;
                        if (segmentLength > 0) {
                            if (!invalidCharactersFound) {
                                scope.ipv6Characters = (/[^0-9a-f]/i.test(segment)) ? false : "valid";
                            }
                            if (!invalidLengthFound) {
                                scope.ipv6SegmentLength = segmentLength > 4 ? false : "valid";
                            }
                        }

                        if (scope.ipv6Characters === false) {
                            invalidCharactersFound = true;
                        }

                        if (scope.ipv6SegmentLength === false) {
                            invalidLengthFound = true;
                        }
                    }
                } else {
                    scope.ipv6Characters = "valid";
                    scope.ipv6Address = false;
                }

                // check the cidr range prefix
                if (prefix) {
                    scope.ipv6Range = (/\D/.test(prefix) ||
                        prefix < 1 || prefix > 128) ? false : "valid";
                } else {
                    scope.ipv6Range = false;
                }

                if (scope.ipv6Collapsed &&
                    scope.ipv6Address &&
                    scope.ipv6Characters &&
                    scope.ipv6SegmentLength &&
                    scope.ipv6Range) {

                    // set the input as valid
                    ctrl.$setValidity("ipv6cidr", true);
                    return value;
                } else {

                    // set the input as invalid
                    ctrl.$setValidity("ipv6cidr", false);
                    return false;
                }
            });
        }
    };
});
