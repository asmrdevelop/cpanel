/*
# cpanel - whostmgr/docroot/templates/menu/main.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    var shared = (function() {
        return {
            setnvdata: function(key, value, store) {
                var data = {
                    "api.version": 1,
                    "personalization": {},
                };
                data["personalization"][key] = value;
                if (store) {
                    data["store"] = store;
                }

                var fetchPromise = fetch(PAGE.token + "/json-api/personalization_set", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(data),
                });

                return fetchPromise.then(function(response) {
                    return response.json();
                });
            },
            debounce: function(callback, time) {
                var timer;

                return function() {
                    if (timer) {
                        clearTimeout(timer);
                    }
                    timer = setTimeout(function() {
                        callback();
                        timer = null;
                    }, time);
                };
            },
        };
    }());

    (function() {
        var groups = PAGE.expanded_groups || {};
        var localGroups = {};
        var saveExpandStatusDebounced = shared.debounce(saveExpandStatus, 500);

        /**
         * Checks cPanel version expiry
         *
         * @method checkVersionExpiry
         */
        function checkVersionExpiry() {
            var messageDiv = document.getElementById("versionExpiryMessage");
            var topSection = document.getElementById("topSection");
            if (messageDiv && topSection) {
                var request = new XMLHttpRequest();
                request.addEventListener("load", function(event) {
                    if (request.status >= 200 && request.status < 300 ||
                        request.status === 304) {
                        var response = JSON.parse(event.target.responseText);
                        if (response.data && response.data.expires_in_next_three_months) {
                            var currentVersionContent = document.getElementById("PLACEHOLDER_CURRENT_VERSION");
                            var expiryContent = document.getElementById("PLACEHOLDER_EXPIRY");
                            currentVersionContent.textContent = response.data.full_version;
                            expiryContent.textContent = new Date(response.data.expiration * 1000).toDateString();

                            messageDiv.classList.remove("hide");
                            topSection.classList.remove("hide");
                        }
                    }
                });
                request.open("GET", PAGE.token + "/json-api/get_current_lts_expiration_status?api.version=1", true);
                request.send();
            }
        }


        /**
         * Expands left navigation
         *
         * @method expandLeftNav
         */
        function expandLeftNav() {
            if (typeof window.commander !== "undefined" && window.commander) {
                window.commander.doNavExpandCollapse();
            }
        }

        function showHideAdditionalApps(info) {
            var additionaAppsDiv = document.getElementById("divAdditionalApps");
            if (info.detail === "expand") {
                additionaAppsDiv.classList.add("hide");
            } else {
                additionaAppsDiv.classList.remove("hide");
            }
        }

        /**
         * Hides important next steps
         *
         * @method dismissImportantNextSteps
         */
        function dismissImportantNextSteps() {
            var nextStepsContainer = document.getElementById("nextStepsSection");

            if (typeof nextStepsContainer !== "undefined" && nextStepsContainer) {
                nextStepsContainer.classList.add("hide-next-steps");
                shared.setnvdata("home:hide_important_next_steps", 1);
            }

        }

        /**
         * Hides alert from ISA
         *
         * @method dismissAlert
         */
        function dismissAlert() {
            var alertSection = document.getElementById("isaAlertSection");

            if (typeof alertSection !== "undefined" && alertSection) {
                alertSection.classList.add("hide");
            }
        }

        /**
         * Start the spinner on a change-view button.
         * @param {Event} e   The click event
         */
        function startChangeViewSpinner(e) {
            var spinnnerElem = this.querySelector(".fa-spin");
            if (spinnnerElem) {
                spinnnerElem.classList.remove("hide");
            }
        }

        /**
         * save expanded information to the server
         *
         * @method saveExpandStatus
         */
        function saveExpandStatus() {

            // Only send updated groups
            var changedGroups = Object
                .keys(localGroups)
                .reduce(function(_groups, group) {
                    if (groups[group] !== localGroups[group]) {
                        _groups[group] = localGroups[group];
                    }
                    return _groups;
                }, {});

            if (!Object.keys(changedGroups).length) {
                return;
            }
            groups = Object.assign(groups, localGroups);

            shared.setnvdata("toggle-status", groups, "home-tools-toggle-status");

            localGroups = {};
        }

        /**
         * Initilize collapsible group element
         *
         * @method collapsibleGroup
         * @param {Element} el - the root element of the collapsible group
         */
        function collapsibleGroup(el) {
            var expandButton = el.querySelector(".cp-group__header");
            expandButton.addEventListener("click", function() {
                var groupKey = el.getAttribute("data-group-key");
                var expanded = el.classList.contains("expanded");
                if (expanded) {
                    el.classList.remove("expanded");
                    localGroups[groupKey] = 0;
                } else {
                    el.classList.add("expanded");
                    localGroups[groupKey] = 1;
                }
                saveExpandStatusDebounced();
            });
        }

        function copyUuidHandler() {
            var uuidTxtEl = document.getElementById("txtAcctUuid");
            var copyMsgEl = document.getElementById("copyMsgContainer");
            const copyText = uuidTxtEl.textContent;

            navigator.clipboard
                .writeText(copyText)
                .then(() => {
                    copyMsgEl.classList.add("show-copy-success");
                    window.setTimeout(function() {
                        copyMsgEl.classList.remove("show-copy-success");
                    }, 3000);
                },
                (err) => {
                    console.error(err);
                });
        }

        /**
         * initialization
         *
         * @method init
         */
        function init() {
            checkVersionExpiry();

            var lnkDismissNextSetps = document.getElementById("lnkDismissNextSteps");
            if (typeof lnkDismissNextSetps !== "undefined" && lnkDismissNextSetps) {
                lnkDismissNextSetps.addEventListener("click", dismissImportantNextSteps);
            }

            var btnCloseAlert = document.getElementById("btnCloseAlert");
            if (typeof btnCloseAlert !== "undefined" && btnCloseAlert) {
                btnCloseAlert.addEventListener("click", dismissAlert);
            }

            var btnViewAllApps = document.getElementById("btnViewAllApps");

            if (typeof btnViewAllApps !== "undefined" && btnViewAllApps) {
                btnViewAllApps.addEventListener("click", expandLeftNav);
            }

            // These buttons are in a group and act as a set of radio buttons
            var topChangeViewButtons = document.querySelectorAll(".change-view-button");
            if (topChangeViewButtons.length) {
                Array.prototype.forEach.call(topChangeViewButtons, function(button) {
                    button.addEventListener("click", function(e) {
                        if (this.classList.contains("active")) {
                            e.preventDefault();
                            e.stopPropagation();
                            return;
                        }

                        // Deselect the other button as part of the radio functionality
                        var sibling = this.nextElementSibling || this.previousElementSibling;
                        if (sibling) {
                            sibling.classList.remove("active");
                        }

                        startChangeViewSpinner.call(this, e);
                        this.classList.add("active");
                    });
                });
            }

            Array.prototype.forEach.call(document.querySelectorAll(".cp-group"), collapsibleGroup);
            window.addEventListener("toggle-navigation", showHideAdditionalApps);

            // Account UUID copy event handler.
            var copyUuidLinkEl = document.getElementById("linkCopyUuid");
            var copyUuidIconEl = document.getElementById("iconCopyUuid");
            if (copyUuidLinkEl) {
                copyUuidLinkEl.addEventListener("click", copyUuidHandler);
            }
            if (copyUuidIconEl) {
                copyUuidIconEl.addEventListener("click", copyUuidHandler);
            }
        }

        init();

    }());

    (function() {
        var editMode = false;
        var ids = [];
        var sortable;

        var saveFavoritesDebounced = function(ids) {
            return shared.debounce(save(ids), 1000);
        };

        var saveSettingsDebounced = function(showFavoritesDescriptions) {
            return shared.debounce(saveSettings(showFavoritesDescriptions), 1000);
        };

        /**
         * Process all the components via the action.
         *
         * @param {string} kind - the tag name of the component
         * @param {function} action - the action to take on each component
         *
         * @returns Promise;
         */
        function allComponents(kind, action) {
            return customElements
                .whenDefined(kind)
                .then(function() {
                    var tag = kind;
                    var els = Array.from(document.querySelectorAll(tag));
                    els.forEach(function(el) {
                        action(el);
                    });
                });
        }

        /**
         * Process the one component via the action.
         *
         * @param {string} kind - the tag name of the component
         * @param {function} action - the action to take on each component
         * @returns
         */
        function oneComponent(kind, action) {
            return customElements
                .whenDefined(kind)
                .then(function() {
                    var tag = kind;
                    var el = document.querySelector(tag);
                    action(el);
                });
        }

        /**
         * Adjust the hidden state of the passed in element based on the editMode
         *
         * @param {Boolean} editMode
         * @param {HtmlElement} el
         */
        function setHiddenClass(editMode, el) {
            if (editMode) {
                if (el.classList.contains("hidden")) {
                    el.classList.remove("hidden");
                }
            } else {
                if (!el.classList.contains("hidden")) {
                    el.classList.add("hidden");
                }
            }
        }

        /**
         * Event handler for toggling the tools edit mode
         *
         * @param {Event} e
         */
        function toggleEditMode(e) {
            editMode = !editMode;

            setHiddenClass(!editMode && ids.length === 0, getPlaceholder());

            // Update the cards already in the list
            allComponents("cp-favorite", function(el) {
                el.setEditMode(editMode);
            });

            allComponents("cp-favorite-selector", function(el) {
                el.setEditMode(editMode);
            });

            allComponents("cp-app", function(el) {
                el.setEditMode(editMode);
            });

            var btnEl = document.getElementsByClassName("toggle-edit-favorites-button");
            if (btnEl && btnEl.length) {
                var txtEditOnEl = btnEl[0].querySelector(".toggle-edit-favorites-button__select");
                if (txtEditOnEl) {
                    setHiddenClass(!editMode, txtEditOnEl);
                }

                var txtEditOffEl = btnEl[0].querySelector(".toggle-edit-favorites-button__done");
                if (txtEditOffEl) {
                    setHiddenClass(editMode, txtEditOffEl);
                }
            }

            var instructionEl = document.getElementsByClassName("cp-favorite-instructions");
            if (instructionEl) {
                setHiddenClass(editMode, instructionEl[0]);
            }

            sortable.option("disabled", !editMode);
        }

        /**
         * Helper to persist the personalized tools
         *
         * @param {string[]} ids - The unique identifiers for the tools.
         */
        function save(ids) {
            return shared.setnvdata("favorites", ids);
        }

        /**
         * Preserve the users selection for whether to show or hide the additional descriptions
         * in the Favorites section.
         *
         * @param {boolean} showFavoritesDescriptions - show/hide the descriptions in the favorites
         * @returns
         */
        function saveSettings(showFavoritesDescriptions) {
            return shared.setnvdata("showFavoritesDescriptions", showFavoritesDescriptions);
        }

        /**
         * Find the tool data for the application.
         *
         * @param {string} groupId
         * @param {string} appId
         * @returns Application
         */
        function findTool(groupId, appId) {
            if (groupId === "plugins") {
                var plugin = PAGE.plugins.find(function(app) {
                    return app.key === appId;
                });
                if (plugin) {
                    return plugin;
                }
            }

            var group = PAGE.tools.groups.find(function(group) {
                return group.key === groupId;
            });

            if (!group) {
                return;
            }

            return group.items.find(function(app) {
                return app.key === appId;
            });
        }

        /**
         * The placeholder is used when there are no favorites selected
         * by the user to remind them that there is a cool feature they are
         * ignoring.
         */
        var placeholderEl;

        /**
         * Retrieve the DOM element for the tools placeholder text.
         */
        function getPlaceholder() {
            if (!placeholderEl) {
                placeholderEl = document.getElementsByClassName("tools-grid-placeholder")[0];
            }
            return placeholderEl;
        }

        /**
         * Show the placeholder
         */
        function showPlaceholder() {
            setHiddenClass(true, getPlaceholder());
        }

        /**
         * Hide the placeholder
         */
        function hidePlaceholder() {
            setHiddenClass(false, getPlaceholder());
        }

        /**
         * Add a new favorite.
         *
         * @param {string} id - the unique identifier for the favorite
         */
        function addItemToFavorites(id) {

            // Find the application
            var parts = id.split("$");
            var application = findTool(parts[0], parts[1]);
            if (!application) {
                return;
            }

            hidePlaceholder();

            // Add the item to the view
            PAGE.favorites.push({
                group: parts[0],
                key: parts[1],
                url: application.fullUrl,
                target: application.target || "_self",
                iconUrl: application.iconUrl,
                name: application.itemdesc,
                description: application.description,
            });
            oneComponent("cp-favorite-list", function(el) {

                // need a new reference for stenciljs to
                // recognize the data changed
                el.favorites = PAGE.favorites.slice();
            });

            // Persist the data
            var newIds = Array.from(ids);
            newIds.push(id);
            saveFavoritesDebounced(newIds);
            ids = newIds;
        }

        /**
         * Remove the item from the
         *
         * @param {string} uniqueId - unique identifer for the favorite
         */
        function removeItemFromFavorites(uniqueId) {

            // Remove the item from the view.
            PAGE.favorites = PAGE.favorites.filter(function(favorite) {
                return uniqueId !== favorite.group + "$" + favorite.key;
            });
            oneComponent("cp-favorite-list", function(el) {

                // need a new reference for stenciljs to
                // recognize the data changed
                el.favorites = PAGE.favorites.slice();
            });

            // Unselect the cp-favorite-selector component
            var appName = uniqueId.split("$")[1];
            var el = document.querySelector("cp-favorite-selector[name=" + CSS.escape(appName) + "]");
            if (el) {
                el.selected(false);
            }

            // Persist the data.
            var newIds = ids.filter(function(id) {
                return id !== uniqueId;
            });

            saveFavoritesDebounced(newIds);
            ids = newIds;
        }

        /**
         * Initialize the toggle button handling
         */
        function initializeToggleButton() {
            var btnEl = document.getElementsByClassName("toggle-edit-favorites-button");
            if (btnEl && btnEl.length) {
                btnEl[0].addEventListener("click", toggleEditMode);
            }
        }

        /**
         * Creates a callback function for the close (x) links on each favorite.
         *
         * @param {HtmlElement} el
         */
        function removeFavoriteFactory(el) {
            return function(e) {
                var toolEl = el;
                var removeId = toolEl.group + "$" + toolEl.name;

                removeItemFromFavorites(removeId);

                allComponents("cp-main-menu", function(el) {
                    el.updateFavorites(PAGE.favorites.slice());
                });
            };
        }

        /**
         * Initialize the favorites handling
         */
        function initializeFavorites() {
            allComponents("cp-favorite", function(el) {
                el.setEditMode(editMode);
                if (el.removeFavoriteHandler) {
                    return;
                }

                el.removeFavoriteHandler = removeFavoriteFactory(el);
                el.addEventListener("removeFavorite", el.removeFavoriteHandler);
            });
        }

        /**
         * Initialize the favorite selectors
         */
        function initializeSelectors() {

            // eslint-disable-next-line no-undef
            var initialSet = new Set(
                PAGE.favorites.map(function(favorite) {
                    return favorite.group + "$" + favorite.key;
                })
            );

            allComponents("cp-favorite-selector", function(el) {
                el.uniqueId().then(function(identifier) {

                    var id = identifier.toString();
                    if (initialSet.has(id)) {
                        el.selected(true);
                    }

                    return el;
                }).then(function(el) {
                    el.addEventListener("changeFavorite", function(e) {
                        var id = e.detail.toString();
                        if ( e.detail.selected ) {
                            addItemToFavorites(id);
                        } else {
                            removeItemFromFavorites(id);
                        }

                        allComponents("cp-main-menu", function(el) {
                            el.updateFavorites(PAGE.favorites.slice());
                        });
                    });
                });

            });
        }

        /**
         * Wait for a global variable to appear as in indication that the supporting
         * library is now loaded. When its present call the callback that depends on
         * this libraries presence.
         *
         * @param {string} name - the name of the global we are waiting for.
         * @param {Function} fn - the function that depends on the library.
         */
        function whenApiAvailable(name, fn) {
            var interval = 2; // ms
            window.setTimeout(function() {
                if (window[name]) {
                    fn(window[name]);
                } else {
                    whenApiAvailable(name, fn);
                }
            }, interval);
        }

        /**
         * Move an element from one position in the array to another
         * The general idea for this algorigthm was takend from:
         *   https://github.com/granteagon/move/blob/master/src/index.js
         * which is MIT licensed.
         *
         * @param {Array} array - the array to minipulate
         * @param {number} from - the index of the source element.
         * @param {number} to - the index of the destination element.
         * @returns {Array} - the new array.
         */
        function move(array, from, to) {
            var length = array.length;
            var delta = from - to;
            var newArray;

            if (delta > 0) {

                // Move to the left
                newArray = array.slice(0, to);
                newArray.push(array[from]);
                array.slice(to, from).forEach(function(item) {
                    newArray.push(item);
                });
                array.slice(from + 1, length).forEach(function(item) {
                    newArray.push(item);
                });

                return newArray;
            } else if (delta < 0) {

                // Move to the right
                to += 1;

                newArray = array.slice(0, from);
                array.slice(from + 1, to).forEach(function(item) {
                    newArray.push(item);
                });
                newArray.push(array[from]);
                array.slice(to, length).forEach(function(item) {
                    newArray.push(item);
                });
                return newArray;
            }

            // No move
            return array;
        }

        /**
         * Initialize the drag drop sorting of the favorites.
         */
        function initializeSortable() {
            whenApiAvailable("Sortable", function() {
                var list = document.getElementsByClassName("favorites-container")[0];
                sortable = Sortable.create(list, { // eslint-disable-line no-undef
                    disabled: true,
                    animation: 100,
                    delay: 200,
                    delayOnTouchOnly: true,
                    onEnd: function(/** Event*/evt) {
                        var from = evt.oldIndex;
                        var to = evt.newIndex;

                        // Persist the data
                        var newIds = move(ids, from, to);
                        PAGE.favorites = move(PAGE.favorites, from, to);
                        saveFavoritesDebounced(newIds);
                        ids = newIds;
                        allComponents("cp-main-menu", function(el) {
                            el.updateFavorites(PAGE.favorites.slice());
                        });
                    },
                });
            });
        }

        /**
         * Build the ids list
         */
        function initializeIds() {
            ids = PAGE.favorites.reduce(function(acc, current) {
                acc.push(current.group + "$" + current.key);
                return acc;
            }, []);
        }

        /**
         * Wire in a temporary UI to test.
         */
        function initializeEditOptions(chkEl) {
            if (chkEl) {
                chkEl.addEventListener("toggle", function(e) {
                    var showDescriptions = e.detail.state === "on";
                    saveSettingsDebounced(showDescriptions);
                    allComponents("cp-favorite-list", function(el) {
                        el.updateOptions({ showDescriptions: showDescriptions });
                    });
                });
            }
        }

        // Initialize the view
        initializeIds();
        oneComponent("cp-favorite-list", function(el) {
            el.favorites = PAGE.favorites.slice();
        });
        oneComponent("cp-favorite-list", function(el) {
            el.addEventListener("favoritesLoaded", initializeFavorites);
        });
        oneComponent("cpw-toggle-switch", function(el) {
            initializeEditOptions(el);
        });
        initializeSelectors();
        initializeToggleButton();
        initializeSortable();
    }());
}());
