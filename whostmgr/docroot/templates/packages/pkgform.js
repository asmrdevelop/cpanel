(function() {
    var DOM = YAHOO.util.Dom,
        EVENT = YAHOO.util.Event,
        DRY_DOCK_ID = "extensionDryDock";

    /*
     * Moves a given package extension editor fieldset from
     * the form to the form "drydock."
     *
     * @method drydockExtensionForm
     * @param {HTMLElement} subform The form to move
     */
    var drydockExtensionForm = function(subform) {
        var dryDock = DOM.get(DRY_DOCK_ID);
        var removedSubform = subform.parentNode.removeChild(subform);

        if (removedSubform) {
            dryDock.appendChild(removedSubform);
            DOM.replaceClass(removedSubform, "visible", "hidden");
        }
    };

    /*
     * Moves a given package extension editor fieldset from
     * the form "drydock" to the form.
     *
     * @method showExtensionForm
     * @param {HTMLElement} subform The form to move
     * @param {HTMLElement} control The control (usually a checkbox) that shows/hides the package extension fields
     */
    var showExtensionForm = function(subform, control) {
        var dryDock = DOM.get(DRY_DOCK_ID);
        var subformToShow = dryDock.removeChild(subform);
        if (subformToShow) {
            var packageExtensionsContainer = DOM.get("packageExtensions");
            packageExtensionsContainer.insertBefore(subformToShow, control.parentNode.nextSibling);
            DOM.replaceClass(subformToShow, "hidden", "visible");
        }
    };

    /*
     * Toggles the visibility of a given package extension form.
     *
     * @method showHidePackageOptions
     * @param {MouseEvent} mouseEvt Mouse event data
     * @param {Object} controlData Click handler data structure
     */
    var showHidePackageOptions = function(mouseEvt, controlData) {
        var subform = DOM.get(controlData.packageName);
        var relatedControl = DOM.get(controlData.controlId);
        if (relatedControl.checked) {
            showExtensionForm(subform, relatedControl);
        } else {
            drydockExtensionForm(subform);
        }
    };

    /*
     * Adds click handlers to package extension toggle control (usually a checkbox).
     * Click handlers add remove related fieldset items from page form.
     * Called from onDOMReady
     *
     * @method addClickHandlers
     */
    var addClickHandlers = function() {
        var pkgOptionsControls = DOM.getElementsByClassName("packageOptionSelector", "input", "packageExtensions");
        var pkgOptionsControlCount = pkgOptionsControls.length;
        for (var i = 0; i < pkgOptionsControlCount; i++) {
            var control = pkgOptionsControls[i];
            control.checked = false; // turn off checkbox on reload
            EVENT.addListener(control, "click",
                showHidePackageOptions, {
                    packageName: DOM.getAttribute(control, "data-packageOptions"),
                    controlId: control.id
                }
            );
        }
    };

    /*
     * Adds "last" class to last property editor within a property group.
     * Makes sure last property editor doesn't have a bottom border
     * (primarily for IE8 compatibility).
     * Called from onDOMReady
     *
     * @method addLastStyleToPropertyGroups
     */
    var addLastStyleToPropertyGroups = function() {
        var isLastPropertyEditor = function(el) {
            return DOM.hasClass(el, "propertyEditor");
        };

        var fixLastPropertyEditors = function(containerId) {
            var packageExtensions = DOM.getElementsByClassName("propertyGroup", "div", containerId);

            var propertyGroupCount = packageExtensions.length;
            for (var j = 0; j < propertyGroupCount; j++) {
                var lastInGroup = DOM.getLastChildBy(packageExtensions[j], isLastPropertyEditor);
                if (lastInGroup) {
                    DOM.addClass(lastInGroup, "last");
                }
            }
        };

        // check extension dry dock first
        fixLastPropertyEditors("extensionDryDock");

        // now do package extensions
        fixLastPropertyEditors("packageExtensions");
    };


    YAHOO.util.Event.onDOMReady(addClickHandlers);
    YAHOO.util.Event.onDOMReady(addLastStyleToPropertyGroups);
}());
