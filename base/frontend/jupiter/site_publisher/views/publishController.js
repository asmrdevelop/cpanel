// Copyright 2023 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

/* eslint-disable no-prototype-builtins */
/* global _: true */
define([
    "angular",
    "cjt/util/locale",
    "uiBootstrap",
    "cjt/filters/wrapFilter",
    "cjt/directives/actionButtonDirective",
    "cjt/directives/jsonFieldDirective",
    "cjt/decorators/growlDecorator",
    "app/services/publishService",
], function(angular, LOCALE) {
    "use strict";

    // Retrieve the current application
    var app = angular.module("App");

    // Setup the controller
    var controller = app.controller("publishController", [
        "$scope",
        "$routeParams",
        "publishService",
        "$timeout",
        "alertService",
        "growl",
        "$q",
        function(
            $scope,
            $routeParams,
            publishService,
            $timeout,
            alertService,
            growl,
            $q
        ) {
            $scope.domainList = [];
            $scope.templateList = [];

            // meta information
            $scope.meta = {

                // Search/Filter options
                filterBy: "*",
                filterCompare: "contains",
                filterValue: "",

                // Pager settings
                maxPages: 0,
                totalItems: $scope.domainList.length,
                currentPage: 1,
                pageSize: 10,
                pageSizes: [10, 20, 50, 100],
                start: 0,
                limit: 10,
            };

            /**
       * Clears the selected template object properties
       */
            var clearSelectedTemplate = function() {
                for (var i = 0, length = $scope.templateList.length; i < length; i++) {
                    delete $scope.templateList[i].selected;
                }
            };

            /**
       * Clears the selected domain object properties
       */
            var clearSelectedDomain = function() {
                for (var i = 0, length = $scope.domainList.length; i < length; i++) {
                    delete $scope.domainList[i].selected;
                }
            };

            /**
       * Resets the state of the wizard to the initial step
       */
            $scope.resetSteps = function() {
                $scope.status = {
                    isDomainSelectOpen: true,
                    isDomainSelectStep: true,
                    isTemplateSelectOpen: false,
                    isTemplateSelectStep: false,
                    isTemplateFormOpen: false,
                    isTemplateFormStep: false,
                    isPublished: false,
                };
                $scope.selectedDomain = null;
                clearSelectedDomain();
                $scope.selectedTemplate = null;
                clearSelectedTemplate();
            };

            /**
       * Returns the panel class depending on workflow step
       *
       * @method getPanelClass
       * @param  {String} step The workflow step
       * @returns {String} Returns the panel class name
       */
            $scope.getPanelClass = function(step) {
                var panelClass = "panel-default",
                    activeClass = "panel-primary";
                if (step === "domain" && $scope.status.isDomainSelectStep) {
                    panelClass = activeClass;
                } else if (step === "template" && $scope.status.isTemplateSelectStep) {
                    panelClass = activeClass;
                } else if (step === "publish" && $scope.status.isTemplateFormStep) {
                    panelClass = activeClass;
                }
                return panelClass;
            };

            /**
       * Applies the array of domains to the scoped domain list
       *
       * @method processDomainList
       * @param  {Array} resultList The paginated array of domains
       */
            var processDomainList = function(resultList) {
                var domainList = resultList.data;

                // update the total items after search
                $scope.meta.totalItems = resultList.meta.paginate.total_records;
                $scope.meta.records_before_filter =
          resultList.meta.records_before_filter;

                var filteredList = domainList;

                // filter list based on page size and pagination
                if ($scope.meta.totalItems > _.min($scope.meta.pageSizes)) {
                    var start = ($scope.meta.currentPage - 1) * $scope.meta.pageSize;

                    $scope.showPager = true;

                    // table statistics
                    $scope.meta.start = start + 1;
                    $scope.meta.limit = start + filteredList.length;
                } else {

                    // hide pager and pagination
                    $scope.showPager = false;

                    if (filteredList.length === 0) {
                        $scope.meta.start = 0;
                    } else {

                        // table statistics
                        $scope.meta.start = 1;
                    }

                    $scope.meta.limit = filteredList.length;
                }

                // set selected flag if the domain is in this page of results
                if ($scope.selectedDomain) {
                    for (var i = 0, length = filteredList.length; i < length; i++) {
                        if (filteredList[i].domain === $scope.selectedDomain.domain) {
                            filteredList[i].selected = true;
                            break;
                        }
                    }
                }

                $scope.domainList = filteredList;

                // preselect a single domain only if it's not a filtered result
                if ($scope.meta.records_before_filter === 1) {
                    $scope.selectDomain(0);
                }
            };

            var fetchDomainsList = function() {
                return publishService.listDomains($scope.meta).then(
                    function(response) {
                        processDomainList(response);
                    },
                    function(error) {
                        growl.error(error);
                    }
                );
            };

            /**
       * Clear the search query
       *
       * @method clearFilter
       */
            $scope.clearFilter = function() {
                $scope.meta.filterValue = "";

                return $scope.selectPage(1);
            };

            /**
       * Select a specific page
       * @param  {Number} page Page number
       */
            $scope.selectPage = function(page) {

                // set the page if requested.
                if (page && angular.isNumber(page)) {
                    $scope.meta.currentPage = page;
                }

                return fetchDomainsList();
            };

            /**
       * Returns site address for the domain
       * @param  {Object} domain Object with domain information
       */
            $scope.getSiteAddress = function(domain) {

                // TODO: get protocol for domain
                return "//" + domain.domain;
            };

            /**
       * Returns file manager link for the domain
       * @param  {Object} domain Object with domain information
       */
            $scope.getFileManagerLink = function(domain) {
                if (domain) {
                    var docroot = domain.documentroot.slice(domain.homedir.length + 1);
                    return (
                        $scope.deprefix +
            $scope.fileManagerObj.url +
            "?dir=" +
            encodeURIComponent(docroot)
                    );
                } else {
                    return $scope.fileManagerObj.url;
                }
            };

            /**
       * Select a specific domain by it's index in the domain list
       * @param  {Number} id The index of the domain to select
       */
            $scope.selectDomain = function(id) {
                $scope.selectedDomain = $scope.domainList[id];
                clearSelectedDomain();
                $scope.domainList[id].selected = true;
                $scope.status.isDomainSelectOpen =
          $scope.status.isDomainSelectStep = false;
                $scope.status.isTemplateSelectOpen =
          $scope.status.isTemplateSelectStep = true;
                $scope.status.isTemplateFormOpen =
          $scope.status.isTemplateFormStep = false;
                clearSelectedTemplate();
                if (
                    $scope.selectedDomain.template_settings.hasOwnProperty("template")
                ) {

                    // a template is installed, apply the selected styling to the proper one
                    for (
                        var i = 0, length = $scope.templateList.length;
                        i < length;
                        i++
                    ) {
                        var template = $scope.templateList[i];
                        if (
                            $scope.selectedDomain.template_settings.template ===
              template.template
                        ) {
                            template.selected = true;
                            break;
                        }
                    }
                }
                $scope.selectedTemplate = false;
                $scope.status.isPublished = false;

                // if only one template preselect template
                if ($scope.templateList.length === 1) {
                    $scope.selectTemplate(0);
                }
            };

            /**
       * Select a specific template by it's index in the template list
       * @param  {Number} id The index of the template to select
       */
            $scope.selectTemplate = function(id) {
                $scope.selectedTemplate = $scope.templateList[id];
                clearSelectedTemplate();
                $scope.templateList[id].selected = true;
                for (
                    var i = 0, length = $scope.templateList[id].meta.fields.length;
                    i < length;
                    i++
                ) {

                    // check the selected domain template settings for this field and populate it if so
                    var field = $scope.templateList[id].meta.fields[i];
                    if (
                        $scope.selectedDomain.template_settings.hasOwnProperty(field.id)
                    ) {
                        field.value = $scope.selectedDomain.template_settings[field.id];
                    }
                }

                $scope.status.isTemplateSelectOpen =
          $scope.status.isTemplateSelectStep = false;
                $scope.status.isTemplateFormOpen =
          $scope.status.isTemplateFormStep = true;
                $scope.status.isPublished = false;
            };

            /**
       * Check validity of the supplied form field
       * @param  {Object} field The model for the form field to check
       * @return {Boolean} Returns true if there are errors
       */
            $scope.hasError = function(field) {
                var form = document.publish_form;
                if (
                    form.hasOwnProperty(field.name) &&
          typeof form[field.name].checkValidity === "function"
                ) {
                    return !form[field.name].checkValidity();
                }
                return false;
            };

            /**
       * Publish a site by it's selected template and domain along with the supplied form data
       * @param  {Object} template The selected template object
       * @param  {Object} domain The selected domain object
       * @return {Promise} Promise that will fulfill the request.
       */
            $scope.publishTemplate = function(template, domain) {
                if (window.mixpanel) {
                    window.mixpanel.track("SitePublisher-Publish-Clicked", {
                        template: template.template,
                    });
                }

                var errorCount =
          document.publish_form.getElementsByClassName("has-error").length;
                if (errorCount) {

                    // prevent form submit on invalid inputs to allow for html5 validation
                    growl.error(
                        LOCALE.maketext(
                            "The form has returned [quant,_1,error,errors]",
                            errorCount
                        )
                    );
                    return $q.when(false);
                }

                domain.url = $scope.getSiteAddress(domain);
                return publishService.publish(template, domain).then(
                    function() {
                        $scope.status.isTemplateFormOpen =
              $scope.status.isTemplateFormStep = false;
                        $scope.status.isPublished = true;

                        if (window.mixpanel) {
                            window.mixpanel.track("SitePublisher-Publish-Success", {
                                template: template.template,
                            });
                        }

                        // update the published domain in the active data set
                        domain.template_settings = {
                            is_empty: 0,
                            path: template.path,
                            template: template.template,
                            docroot: domain.documentroot,
                        };

                        // persist the template variables bacck to the object without page load
                        for (
                            var i = 0, length = template.meta.fields.length;
                            i < length;
                            i++
                        ) {
                            var field = template.meta.fields[i];
                            domain.template_settings[field.id] = field.value;
                        }
                    },
                    function(error) {
                        if (window.mixpanel) {
                            window.mixpanel.track("SitePublisher-Publish-Failed", {
                                template: template.template,
                            });
                        }
                        growl.error(error);
                    }
                );
            };

            /**
       * Initialize the view
       *
       * @private
       * @method _initializeView
       */
            var _initializeView = function() {
                $scope.locale = LOCALE;
                $scope.resetSteps();

                if (PAGE.deprefix) {
                    $scope.deprefix = PAGE.deprefix;
                }

                if (PAGE.fileManagerObj) {
                    $scope.fileManagerObj = PAGE.fileManagerObj;
                }

                if (PAGE.accountsObj) {
                    $scope.accountsObj = PAGE.accountsObj;
                }

                if (PAGE.webdiskObj) {
                    $scope.webdiskObj = PAGE.webdiskObj;
                }

                // check for page data in the template if this is a first load
                if (app.firstLoad.publish && PAGE.domainList && PAGE.templateList) {
                    app.firstLoad.publish = false;

                    // perform a reverse sort on the template list based on metadata throwing null dates to the bottom
                    $scope.templateList = publishService
                        .convertResponseToList(PAGE.templateList)
                        .data.sort(function(a, b) {
                            var aDate, bDate, aName, bName;

                            // ensure we have valid dates and parse to millisecond values
                            if (a.meta.information.hasOwnProperty("date")) {
                                aDate = Date.parse(a.meta.information.date);
                                if (isNaN(aDate)) {
                                    aDate = 0;
                                }
                            } else {
                                aDate = 0;
                            }
                            if (b.meta.information.hasOwnProperty("date")) {
                                bDate = Date.parse(b.meta.information.date);
                                if (isNaN(bDate)) {
                                    bDate = 0;
                                }
                            } else {
                                bDate = 0;
                            }

                            // sort latest dates to the top
                            if (bDate > aDate) {
                                return 1;
                            } else if (bDate < aDate) {
                                return -1;
                            } else {

                                // ensure we have valid template names
                                if (
                                    a.meta.information.hasOwnProperty("name") &&
                  a.meta.information.name !== null
                                ) {
                                    aName = a.meta.information.name.toLowerCase();
                                } else {
                                    aName = "";
                                }

                                if (
                                    b.meta.information.hasOwnProperty("name") &&
                  b.meta.information.name !== null
                                ) {
                                    bName = b.meta.information.name.toLowerCase();
                                } else {
                                    bName = "";
                                }

                                // sort equal dates by their names
                                return aName > bName ? 1 : aName < bName ? -1 : 0;
                            }
                        });
                    processDomainList(
                        publishService.convertResponseToList(PAGE.domainList)
                    );
                } else {

                    // Otherwise, retrieve it via ajax
                    fetchDomainsList();
                }

                if ($routeParams["domain"]) {

                    // Allow Deep-linking of a domain
                    $scope.meta.filterValue = $routeParams["domain"];
                    $scope.selectPage(1).then(function() {
                        $scope.domainList.forEach(function(domain, key) {
                            if (domain.domain === $routeParams["domain"]) {
                                $scope.selectDomain(key);
                            }
                        });
                    });
                }
            };

            _initializeView();
        },
    ]);

    function ExceptionHandler($provide) {
        $provide.decorator("$exceptionHandler", [
            "$injector",
            function($injector) {
                return function(exception) {
                    $injector
                        .get("growl")
                        .error(
                            LOCALE.maketext("A problem has occurred: [_1]", exception.message)
                        );
                };
            },
        ]);
    }
    ExceptionHandler.$inject = ["$provide"];
    app.config(ExceptionHandler);

    return controller;
});
