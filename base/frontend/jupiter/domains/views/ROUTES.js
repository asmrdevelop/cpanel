/*
# domains/views/ROUTES.js                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/** @namespace cpanel.domains.views.ROUTES */

define(
    [
        "cjt/util/locale"
    ],
    function(LOCALE) {

        "use strict";

        var ROUTES = [
            {
                "id": "listDomains",
                "route": "/",
                "hideTitle": false,
                "controller": "listDomains",
                "templateUrl": "views/listDomains.phtml",
                "title": LOCALE.maketext("List Domains"),
                "breadcrumb": {
                    "id": "listDomains",
                    "name": LOCALE.maketext("List Domains"),
                    "path": "/"
                },
                "resolve": {
                    "currentDomains": ["domains", function($service) {
                        return $service.get();
                    }]
                }
            },
            {
                "id": "createDomain",
                "route": "/create",
                "controller": "createDomain",
                "templateUrl": "views/createDomain.ptt",
                "title": LOCALE.maketext("Create a New Domain"),
                "breadcrumb": {
                    "id": "createDomain",
                    "name": LOCALE.maketext("Create a New Domain"),
                    "path": "/create/",
                    "parentID": "listDomains"
                },
                "resolve": {
                    "domainTypes": ["domains", function($service) {
                        return $service.getTypes();
                    }],
                    "currentDomains": ["domains", function($service) {
                        return $service.get();
                    }]
                }
            },
            {
                "id": "manageDomain",
                "route": "/manage",
                "controller": "manageDomain",
                "templateUrl": "views/manageDomain.ptt",
                "hideTitle": true,
                "title": LOCALE.maketext("Manage the Domain"),
                "breadcrumb": {
                    "id": "manageDomain",
                    "name": LOCALE.maketext("Manage the Domain"),
                    "path": "/manage/",
                    "parentID": "listDomains"
                },
                "resolve": {
                    "domainTypes": ["domains", function($service) {
                        return $service.getTypes();
                    }],
                    "currentDomains": ["domains", function($service) {
                        return $service.get();
                    }]
                }
            }

        ];

        return ROUTES;
    }
);
