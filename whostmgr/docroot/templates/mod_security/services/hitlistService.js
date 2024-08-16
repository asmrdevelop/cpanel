/* global define: false */

define(
    [

        // Libraries
        "angular",

        // Application

        // CJT
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready

        // Angular components
        "cjt/services/APIService"

    ],
    function(angular, LOCALE, API, APIREQUEST, APIDRIVER) {

        // Constants
        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * Converts the response to our application data structure
         * @private
         * @param  {Object} response
         * @return {Object} Sanitized data structure.
         */
        function _convertResponseToList(response) {
            var items = [];
            if (response.status) {
                var data = response.data;
                for (var i = 0, length = data.length; i < length; i++) {
                    var hitList = data[i];
                    items.push(
                        hitList
                    );
                }

                var meta = response.meta;

                var totalItems = meta.paginate.total_records || data.length;
                var totalPages = meta.paginate.total_pages || 1;

                return {
                    items: items,
                    totalItems: totalItems,
                    totalPages: totalPages
                };
            } else {
                return {
                    items: [],
                    totalItems: 0,
                    totalPages: 0
                };
            }
        }

        /**
         * Setup the hitlist models API service
         */
        app.factory("hitListService", ["$q", "APIService", function($q, APIService) {

            // Set up the service's constructor and parent
            var HitListService = function() {};
            HitListService.prototype = new APIService({
                transformAPISuccess: _convertResponseToList
            });

            // Extend the prototype with any class-specific functionality
            angular.extend(HitListService.prototype, {

                /**
                 * Get a list of mod_security rule hits that match the selection criteria passed in meta parameter
                 * @param {object} meta Optional meta data to control sorting, filtering and paging
                 *   @param {string} meta.sortBy Name of the field to sort by
                 *   @param {string} meta.sordDirection asc or desc
                 *   @param {string} meta.sortType Optional name of the sort rule to apply to the sorting
                 *   @param {string} meta.filterBy Name of the filed to filter by
                 *   @param {string} meta.filterCompare Optional comparator to use when comparing for filter.
                 *   If not provided, will default to ???.
                 *   May be one of:
                 *       TODO: Need a list of valid filter types.
                 *   @param {string} meta.filterValue  Expression/argument to pass to the compare method.
                 *   @param {string} meta.pageNumber Page number to fetch.
                 *   @param {string} meta.pageSize Size of a page, will default to 10 if not provided.
                 * @return {Promise} Promise that will fulfill the request.
                 */
                fetchList: function fetchList(meta) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_get_log");
                    if (meta) {
                        if (meta.sortBy && meta.sortDirection) {
                            apiCall.addSorting(meta.sortBy, meta.sortDirection, meta.sortType);
                        }
                        if (meta.pageNumber) {
                            apiCall.addPaging(meta.pageNumber, meta.pageSize || 10);
                        }
                        if (meta.filterBy && meta.filterValue) {
                            apiCall.addFilter(meta.filterBy, meta.filterCompare, meta.filterValue);
                        }
                    }

                    return this.deferred(apiCall).promise;
                },

                /**
                 * Retrieve an individual hit from the unique hit ID, which is the primary key in the modsec.hits table.
                 *
                 * @method fetchById
                 * @param  {[type]} hitId [description]
                 * @return {[type]}       [description]
                 */
                fetchById: function fetchById(hitId) {
                    var promise = this.fetchList({
                        filterBy: "id",
                        filterValue: hitId,
                        filterCompare: "eq"
                    }).then(function(response) {

                        // Check the length of the results to make sure we only have one hit
                        var length = response.items.length;

                        if (length === 1) {
                            return response;
                        } else if (length > 1) {
                            return $q.reject({
                                message: LOCALE.maketext("More than one hit matched hit ID “[_1]”.", hitId),
                                count: length
                            });
                        } else {
                            return $q.reject({
                                message: LOCALE.maketext("No hits matched ID “[_1]”.", hitId),
                                count: length
                            });
                        }
                    });

                    return promise;
                },

                /**
                *  Helper method that calls convertResponseToList to prepare the data structure
                * @param  {Object} response
                * @return {Object} Sanitized data structure.
                */
                prepareList: function prepareList(response) {

                    // Since this is coming from the backend, but not through the api.js layer,
                    // we need to parse it to the frontend format.
                    response = APIDRIVER.parse_response(response).parsedResponse;
                    return _convertResponseToList(response);
                }

            });

            return new HitListService();

        }]);
    }
);
